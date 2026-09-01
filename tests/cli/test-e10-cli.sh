#!/usr/bin/env bash
# E10 / S-1001 + S-1002 + S-1004 — outcome (a variável dependente) e retro
# (a agregação determinística que fecha o loop de aprendizado).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v jq >/dev/null || { echo "FAIL jq ausente"; exit 1; }
command -v bun >/dev/null || { echo "FAIL bun ausente (decide precisa)"; exit 1; }

echo "-- outcome fecha uma decisão existente"
"$BIN" decide --session out-1 --workflow fix --mode subagent --agents dev-pleno >/dev/null 2>&1
"$BIN" outcome --session out-1 accepted --suite pass >/dev/null; rc=$?
chk "outcome sobre record existente → exit 0" "$rc" "0"
REC="$MAESTRO_HOME/sessions/out-1.json"
chk "record ganha outcome" "$(jq -r .outcome "$REC")" "accepted"
chk "record ganha suite" "$(jq -r .suite "$REC")" "pass"
jq -e '.outcome_ts | length > 0' "$REC" >/dev/null && ok "outcome_ts carimbado" || bad "outcome_ts carimbado"
"$BIN" outcome --session out-1 rework >/dev/null
chk "último desfecho vence (rework sobrescreve)" "$(jq -r .outcome "$REC")" "rework"

echo "-- validações do outcome"
"$BIN" outcome --session sem-record accepted >/dev/null 2>&1; rc=$?
chk "sem record → exit 1 (desfecho fecha decisão, não a inventa)" "$rc" "1"
"$BIN" outcome --session out-1 talvez >/dev/null 2>&1; rc=$?
chk "veredito fora do enum → exit 1" "$rc" "1"
"$BIN" outcome --session out-1 accepted --suite quase >/dev/null 2>&1; rc=$?
chk "--suite fora do enum → exit 1" "$rc" "1"

LOG="$MAESTRO_HOME/logs/routing.jsonl"
grep -q '"event":"outcome".*"outcome":"accepted"' "$LOG" && ok "outcome no log (enum)" || bad "outcome no log"

echo "-- retro agrega a janela"
# fixture: log sintético controlado (hoje, dentro de qualquer janela)
TS=$(date -Iseconds)
mkdir -p "$MAESTRO_HOME/logs"
cat > "$LOG" <<J
{"ts":"$TS","event":"decision","session_id":"r1","workflow":"fix","mode":"subagent","agents":["dev-pleno"]}
{"ts":"$TS","event":"decision","session_id":"r2","workflow":"fix","mode":"direct"}
{"ts":"$TS","event":"decision","session_id":"r3","workflow":"feature","mode":"multi","agents":["engenheiro","typescript-pro"]}
{"ts":"$TS","event":"override_manual","session_id":"r4","cmd":"gstack-ship"}
{"ts":"$TS","event":"gate_pass","session_id":"r1","tool":"Edit","file_ext":".py","gate_mode":"warn"}
{"ts":"$TS","event":"gate_warn","session_id":"r4","tool":"Edit","file_ext":".ts","gate_mode":"warn"}
{"ts":"$TS","event":"habit_warn","session_id":"r1","smell":"swallowed-error","n":"2","file_ext":".py"}
{"ts":"$TS","event":"habit_warn","session_id":"r2","smell":"swallowed-error","n":"1","file_ext":".py"}
{"ts":"$TS","event":"habit_warn","session_id":"r3","smell":"debug-leftover","n":"1","file_ext":".ts"}
{"ts":"$TS","event":"outcome","session_id":"r1","outcome":"accepted","suite":"pass"}
{"ts":"$TS","event":"outcome","session_id":"r3","outcome":"rework"}
{"ts":"$TS","event":"consent_grant","session_id":"r1","scope":"routing-table"}
J
out=$("$BIN" retro --days 7); rc=$?
chk "retro → exit 0" "$rc" "0"
grep -q 'decisões: 3 · override roteável: 1 · não-roteável: 0 · taxa de override: 33%' <<<"$out" \
  && ok "taxa de override calculada (1 roteável de 3 decisões = 33%)" || bad "taxa de override ($out)"
grep -q 'swallowed-error: 2' <<<"$out" && ok "smells ordenados por frequência" || bad "smells por frequência"
grep -q 'accepted: 1' <<<"$out" && ok "desfechos agregados" || bad "desfechos agregados"
grep -q 'grant 1' <<<"$out" && ok "consentimentos contados" || bad "consentimentos contados"
grep -q 'sem uso na janela' <<<"$out" && ok "workflows declarados sem uso aparecem" || bad "workflows sem uso"
grep -q 'override em 33% (≥20%)' <<<"$out" \
  && ok "sinal de calibração dispara com override alto" || bad "sinal de calibração"
grep -q 'promoção warn→block: ainda não' <<<"$out" \
  && ok "promoção NÃO elegível com 3 decisões (piso é 10)" || bad "promoção não elegível"

echo "-- S-1004: promoção elegível só com critério cheio"
for i in $(seq 5 16); do
  printf '{"ts":"%s","event":"decision","session_id":"p%s","workflow":"fix","mode":"subagent"}\n' "$TS" "$i" >> "$LOG"
done
out=$("$BIN" retro --days 14)
grep -q 'PROMOÇÃO ELEGÍVEL' <<<"$out" \
  && ok "≥14d, ≥10 decisões, override <20% → propõe warn→block" || bad "promoção elegível ($out)"
grep -q 'exige consentimento ou mão humana' <<<"$out" \
  && ok "a proposta lembra que aplicar exige consent" || bad "proposta lembra do consent"

echo "-- honestidade com log vazio"
rm -f "$LOG"
out=$(MAESTRO_HOME="$tmp/vazio" "$BIN" retro); rc=$?
chk "sem log → exit 0" "$rc" "0"
grep -q 'sem dados' <<<"$out" && ok "diz que não há dado, não inventa conclusão" || bad "honestidade sem dados"

echo "-- S-1801: taxa de override conta só comando ROTEÁVEL (skill: dos bindings + workflows)"
RTHOME="$tmp/s1801"
export MAESTRO_HOME="$RTHOME"
mkdir -p "$MAESTRO_HOME/logs"
RTLOG="$MAESTRO_HOME/logs/routing.jsonl"
TS2=$(date -Iseconds)
{
  for i in $(seq 1 10); do
    printf '{"ts":"%s","event":"decision","session_id":"s%s","workflow":"fix","mode":"subagent"}\n' "$TS2" "$i"
  done
  printf '{"ts":"%s","event":"override_manual","session_id":"o0","cmd":"gstack-ship"}\n' "$TS2"
  for i in $(seq 1 5); do
    printf '{"ts":"%s","event":"override_manual","session_id":"o%s","cmd":"gstack-context-restore"}\n' "$TS2" "$i"
  done
} > "$RTLOG"
RTFIX="$tmp/routing-table-fixture.yaml"
cat > "$RTFIX" <<Y
version: 2
workflows:
  fix: {steps: [investigate], gate: none}
bindings:
  ship: skill:gstack-ship
Y
out=$(MAESTRO_ROUTING_TABLE="$RTFIX" "$BIN" retro --days 7); rc=$?
chk "retro com tabela fixture → exit 0" "$rc" "0"
grep -q 'decisões: 10 · override roteável: 1 · não-roteável: 5 · taxa de override: 10%' <<<"$out" \
  && ok "taxa conta só o roteável (1/10 = 10%, não 6/10 = 60%)" || bad "taxa roteável ($out)"
grep -q 'não-roteável: 5' <<<"$out" && ok "invocação de ciclo de vida contada à parte" || bad "não-roteável: 5"

out=$(MAESTRO_ROUTING_TABLE="$tmp/nao-existe.yaml" "$BIN" retro --days 7); rc=$?
chk "retro sem tabela (degrade) → exit 0, nunca quebra" "$rc" "0"
grep -q -- '-- aviso:' <<<"$out" && ok "degrade avisa que o filtro roteável não pôde ser derivado" || bad "aviso de degrade"
grep -q 'override roteável: 6' <<<"$out" \
  && ok "degrade conta como antes (6 override_manual no total)" || bad "degrade conta 6 ($out)"

echo "-- comando /maestro:retro registrado"
CMD="$REPO/commands/retro.md"
[[ -f "$CMD" ]] && ok "commands/retro.md existe" || bad "commands/retro.md existe"
grep -q 'maestro retro' "$CMD" && ok "usa o relatório determinístico como fonte" || bad "usa maestro retro"
grep -q 'consent --grant' "$CMD" && ok "fluxo de consentimento no comando" || bad "fluxo de consentimento"
grep -q 'eval' "$CMD" && ok "exame (eval-on-diff) antes do commit" || bad "exame antes do commit"
grep -q 'revoke' "$CMD" && ok "revogação após aplicar" || bad "revogação após aplicar"

exit $fail
