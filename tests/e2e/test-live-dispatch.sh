#!/usr/bin/env bash
# E13 / S-1303 — prova VIVA de que a injeção governa comportamento real.
#
# TIER MANUAL/PAGO (padrão gstack "gate tier"): roda uma sessão `claude -p`
# DE VERDADE (custa dinheiro e ~1-3min) num projeto-fixture e verifica no log
# do Maestro que a sessão OBEDECEU aos trilhos: registrou `decide` ANTES da
# primeira edição de código. Fora do run-all de propósito (filosofia do
# tests/eval): comportamento de modelo não é asserção de CI grátis.
#
# É o pré-requisito declarado da promoção warn→block (EPICS E13): não se
# aperta um gate sem prova comportamental de que o fluxo funciona.
#
# Uso:  bash tests/e2e/test-live-dispatch.sh
# Requer: claude autenticado no PATH; plugin maestro ativo (marketplace directory).
# Saída: PASS | FAIL <motivo> | INCONCLUSIVE <motivo> — exit 0 | 1 | 2.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
command -v claude >/dev/null || { echo "INCONCLUSIVE: claude ausente do PATH"; exit 2; }
command -v jq >/dev/null || { echo "INCONCLUSIVE: jq ausente"; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

PROJ="$tmp/proj"; mkdir -p "$PROJ"
git -C "$PROJ" init -q
printf '# fixture do live-dispatch E2E do Maestro\n' > "$PROJ/README.md"
git -C "$PROJ" add -A; git -C "$PROJ" -c user.email=e2e@maestro -c user.name=e2e commit -qm fixture

export MAESTRO_HOME="$tmp/home"
echo "== sessão headless real (custa tokens; ~1-3min)..."
( cd "$PROJ" && timeout 300 claude -p --permission-mode acceptEdits \
    "Crie o arquivo util.py com uma função soma(a, b) que retorna a+b, com docstring. É trabalho de código real neste projeto." \
    >/dev/null 2>&1 ) || { echo "INCONCLUSIVE: sessão headless falhou/timeout"; exit 2; }

LOG="$MAESTRO_HOME/logs/routing.jsonl"
[[ -f "$PROJ/util.py" ]] || { echo "INCONCLUSIVE: a sessão não produziu util.py (sem edição, nada a provar)"; exit 2; }
[[ -f "$LOG" ]] || { echo "FAIL: sessão editou código e o log do Maestro não existe (hooks não rodaram?)"; exit 1; }

DEC_TS=$(jq -rs 'map(select(.event == "decision")) | first | .ts // empty' "$LOG")
GATE_TS=$(jq -rs 'map(select(.event == "gate_pass" or .event == "gate_warn")) | first | .ts // empty' "$LOG")

if [[ -z "$DEC_TS" ]]; then
  echo "FAIL: a sessão editou código SEM registrar decisão (a injeção não governou)"
  exit 1
fi
if [[ -n "$GATE_TS" && ! "$DEC_TS" < "$GATE_TS" && "$DEC_TS" != "$GATE_TS" ]]; then
  # decide depois da primeira edição: registrou, mas fora de ordem
  echo "FAIL: decisão registrada DEPOIS da primeira edição ($GATE_TS < $DEC_TS)"
  exit 1
fi
MODE=$(jq -rs 'map(select(.event == "decision")) | first | .mode // "?"' "$LOG")
WF=$(jq -rs 'map(select(.event == "decision")) | first | .workflow // "?"' "$LOG")
echo "PASS: sessão viva obedeceu aos trilhos — decide($WF/$MODE) antes da primeira edição; util.py criado"
exit 0
