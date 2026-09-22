#!/usr/bin/env bash
# ordem 041 — golden: compara o ANTES (tests/fixtures/order041-golden-BEFORE.json,
# capturado no head eadcacf, sem nenhuma linha desta ordem) contra o DEPOIS
# (recapturado com bash tests/fixtures/order041-golden-capture.sh, código
# desta ordem aplicado). Com MAESTRO_ACCEPT_REQUIRE_PROOF DESLIGADO (default),
# estado/pede_aceite/terminal/suspensa têm de sair IDÊNTICOS nas ordens reais
# do Maestro — "comportamento de hoje, byte a byte" (desenho, item 5).
#
# MESMO MOTIVO de tests/fixtures/order036-golden-compare.sh estar aqui (fora
# de tests/cli/, fora do glob de tests/run-all.sh): usa o `~/.maestro` REAL
# (MAESTRO_HOME NÃO isolado) — rodar dentro do runner hermético (que isola
# MAESTRO_HOME num tmpdir por design, tests/run-all.sh linha ~16) faria a
# captura ler um registro-fora-da-árvore VAZIO e mentir uma regressão que não
# existe (medido: 3 ordens 'aceita'→'aberta' — o registro sumiu, não a prova).
#
# Uso:
#   bash tests/fixtures/order041-golden-capture.sh > /tmp/order041-AFTER.json
#   bash tests/fixtures/order041-golden-compare.sh /tmp/order041-AFTER.json
set -u
command -v jq >/dev/null 2>&1 || { echo "PENDENTE  jq ausente — golden exige jq"; exit 0; }
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BEFORE="$REPO/tests/fixtures/order041-golden-BEFORE.json"
AFTER="${1:-/tmp/order041-AFTER.json}"
[[ -f "$BEFORE" ]] || { echo "FAIL  $BEFORE ausente — rode a captura ANTES do changeset primeiro"; exit 1; }
[[ -f "$AFTER"  ]] || { echo "FAIL  $AFTER ausente — rode: bash tests/fixtures/order041-golden-capture.sh > $AFTER"; exit 1; }

fail=0
n_compared=0
while IFS=$'\t' read -r id before_campos; do
  after_campos=$(jq -c --arg id "$id" '.[] | select(.id==$id) | .campos' "$AFTER" 2>/dev/null)
  [[ -n "$after_campos" && "$after_campos" != "null" ]] || { echo "AVISO  $id sumiu do AFTER (outra sessão pode ter mexido) — pulando"; continue; }
  n_compared=$((n_compared+1))
  if [[ "$before_campos" == "$after_campos" ]]; then
    :
  else
    fail=1
    echo "FAIL  ordem $id divergiu:"
    echo "  antes : $before_campos"
    echo "  depois: $after_campos"
  fi
done < <(jq -r '.[] | [.id, (.campos|tojson)] | @tsv' "$BEFORE")

echo "golden 041: $n_compared ordens comparadas"
if (( fail == 0 )); then
  echo "golden 041: OK — estado/pede_aceite/terminal/suspensa idênticos com REQUIRE desligado"
else
  echo "golden 041: FALHOU — ver divergências acima" >&2
fi
exit $fail
