#!/usr/bin/env bash
# E14 / S-1401 + S-1402 — orçamento declarado: caps INTEIROS no record,
# enforcement WARN-ONLY no gate (1 aviso por cap, nunca bloqueia), cents
# declarativo. Hermético: MAESTRO_HOME/projeto em mktemp; política compilada
# pelo session-start real (gate.mode block da tabela real — o orçamento tem de
# conviver com block sem virar segundo bloqueio).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO/hooks/pre-tool-gate.sh"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

H="$tmp/home"
printf '{"session_id":"bg-1"}' | MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$REPO" \
  bash "$REPO/hooks/session-start.sh" >/dev/null 2>&1

echo "-- CLI: caps inteiros, validados, AND opcional"
MAESTRO_HOME="$H" "$BIN" decide --session bg-1 --workflow fix --mode direct \
  --max-steps 3 --max-min 60 --max-cents 250 >/dev/null
chk "budget no record" "$(jq -c .budget "$H/sessions/bg-1.json")" '{"steps":3,"minutes":60,"cents":250}'
MAESTRO_HOME="$H" "$BIN" decide --session bg-x --workflow fix --mode direct --max-steps 0 >/dev/null 2>&1; rc=$?
chk "cap 0 → exit 1 (inteiro ≥1)" "$rc" "1"
MAESTRO_HOME="$H" "$BIN" decide --session bg-x --workflow fix --mode direct --max-cents 3.5 >/dev/null 2>&1; rc=$?
chk "float em custo → exit 1 (regra da casa)" "$rc" "1"
MAESTRO_HOME="$H" "$BIN" decide --session bg-y --workflow fix --mode direct >/dev/null
jq -e '.budget' "$H/sessions/bg-y.json" >/dev/null 2>&1 \
  && bad "sem caps → sem campo budget" || ok "sem caps → sem campo budget"

echo "-- gate: passos contados, aviso ÚNICO no estouro, nunca bloqueia"
OUT=""; RC=0
probe() {
  OUT=$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' \
      "${2:-bg-1}" "$REPO/tests/x.py" \
    | MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$REPO" bash "$GATE" 2>&1 >/dev/null); RC=$?
  return 0
}
for i in 1 2 3; do probe; chk "passo $i dentro do cap → exit 0 silencioso" "$RC-${OUT:+msg}" "0-"; done
probe
chk "passo 4 de 3 → AVISA e passa (warn-only)" "$RC" "0"
grep -q 'passou do plano' <<<"$OUT" && ok "aviso instrui reportar ao humano" || bad "aviso instrui ($OUT)"
probe
chk "passo 5 → sem repetir o aviso (anti-ruído)" "${OUT:-vazio}" "vazio"
n=$(grep -c '"event":"budget_warn"' "$H/logs/routing.jsonl")
chk "exatamente 1 budget_warn no log" "$n" "1"
grep -q '"cap":"steps"' "$H/logs/routing.jsonl" && ok "cap logado como enum" || bad "cap enum"

echo "-- janela de minutos (ts retroativo no record)"
python3 - <<PY
import json
p="$H/sessions/bg-1.json"
d=json.load(open(p)); d["ts"]="2026-01-01T10:00:00-03:00"
open(p,"w").write(json.dumps(d,separators=(",",":")))
PY
rm -f "$H/sessions/budget-bg-1"
probe
grep -q 'janela de 60min' <<<"$OUT" && ok "janela estourada avisa" || bad "janela estourada ($OUT)"
chk "e continua passando (warn-only)" "$RC" "0"
probe
grep -q 'janela' <<<"$OUT" && bad "aviso de janela não repete" || ok "aviso de janela não repete"

echo "-- degradações"
python3 - <<PY
import json
p="$H/sessions/bg-1.json"
d=json.load(open(p)); d["budget"]="lixo"
open(p,"w").write(json.dumps(d,separators=(",",":")))
PY
probe
chk "budget malformado no record → gate segue (exit 0, sem crash)" "$RC" "0"

echo "-- doctor: schema v1.6 aceita budget íntegro e reprova float"
MAESTRO_HOME="$H" "$BIN" decide --session bg-ok --workflow fix --mode direct --max-steps 5 >/dev/null
rm -f "$H/sessions/bg-1.json"   # o corrompido de propósito sairia como ruído aqui
MAESTRO_HOME="$H" "$BIN" doctor 2>/dev/null | grep -q 'decision records:.*válido' \
  && ok "record com budget passa no schema" || bad "record com budget passa no schema"
python3 - <<PY2
import json
p="$H/sessions/bg-ok.json"
d=json.load(open(p)); d["budget"]={"steps":1.5}
open(p,"w").write(json.dumps(d,separators=(",",":")))
PY2
MAESTRO_HOME="$H" "$BIN" doctor 2>/dev/null | grep -q 'inválido' \
  && ok "budget com float reprova (inteiros são lei)" || bad "budget com float reprova"
rm -f "$H/sessions/bg-ok.json"

echo "-- status e retro"
MAESTRO_HOME="$H" "$BIN" decide --session bg-2 --workflow fix --mode direct --max-steps 7 >/dev/null
MAESTRO_HOME="$H" "$BIN" status --session bg-2 2>/dev/null | grep -q 'orçamento : 7 passo(s)' \
  && ok "status mostra o orçamento declarado" || bad "status mostra orçamento"
out=$(MAESTRO_HOME="$H" "$BIN" retro --days 7 2>/dev/null)
grep -q 'orçamento: 2 estouro(s)' <<<"$out" && ok "retro conta budget_warn da janela" \
                                            || bad "retro conta budget_warn ($out)"

exit $fail
