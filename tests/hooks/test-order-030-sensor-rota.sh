#!/usr/bin/env bash
# ordem 030 — sensor mecânico de correção de rota (`route_fix`).
#
# O Resultado do INTENT v3 promete "zero correção manual do modo/modelo
# escolhido", mas era INVERIFICÁVEL: não havia sensor para a correção em
# linguagem natural ("não, faz direto", "usa haiku nessa"), que nunca começa
# com `/` e por isso escapava do `override_manual` existente.
#
# A ARMADILHA CENTRAL desta suíte: um sensor que conta DEMAIS é pior que
# nenhum. Por isso o bloco mais importante aqui não é o que emite — é o que
# PROVA que menção sem contradição, ambiguidade e ausência de âncora NÃO
# emitem nada (bloco 3), e que nenhum caminho grava um trecho do prompt no
# log (bloco 8, a asserção de canário).
#
# Molde: tests/hooks/test-order-026-papercuts.sh (MAESTRO_HOME em mktemp,
# hermético; nada toca o ~ real). Prioridade 1 do INTENT ("nunca bloquear
# trabalho por estar quebrado"): jq ausente e record corrompido são MUDOS,
# exit 0, sem exceção.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/user-prompt-submit.sh"

SANDBOX=$(mktemp -d)
export MAESTRO_HOME="$SANDBOX"
LOG="$MAESTRO_HOME/logs/routing.jsonl"
ERR="$SANDBOX/stderr.txt"
trap 'chmod -R u+rwX "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL jq ausente — a suíte da ordem 030 exige jq" >&2
  exit 1
fi

mkdir -p "$MAESTRO_HOME/sessions"

# write_record <session_id> <workflow> <mode> <agents-csv-ou-""> — grava um
# decision record VÁLIDO (expira em 2099), no MESMO formato compacto de
# `JSON.stringify(record)` (src/cli.ts, sem indentação) que o hook assume ao
# extrair por regex builtin (sem fork de um segundo jq).
write_record() {
  local sid="$1" wf="$2" md="$3" ag_csv="${4:-}" agents_json="[]" a out=""
  if [[ -n "$ag_csv" ]]; then
    local IFS=','
    for a in $ag_csv; do out="$out,\"$a\""; done
    agents_json="[${out#,}]"
  fi
  printf '{"session_id":"%s","ts":"2026-09-19T10:00:00-03:00","expires_at":"2099-01-01T00:00:00-03:00","workflow":"%s","mode":"%s","agents":%s,"reason":"fixture"}\n' \
    "$sid" "$wf" "$md" "$agents_json" > "$MAESTRO_HOME/sessions/$sid.json"
}

# write_expired_record — MESMOS campos, mas `expires_at` no passado. Existe
# para provar a ressalva da reordenação (ordem 030, pedido do coordenador):
# a leitura do record deixou de exigir validade, mas o EVENTO continua
# exigindo — ler campos de um record vencido não pode virar `route_fix`.
write_expired_record() {
  local sid="$1" wf="$2" md="$3" ag_csv="${4:-}" agents_json="[]" a out=""
  if [[ -n "$ag_csv" ]]; then
    local IFS=','
    for a in $ag_csv; do out="$out,\"$a\""; done
    agents_json="[${out#,}]"
  fi
  printf '{"session_id":"%s","ts":"2020-01-01T00:00:00-03:00","expires_at":"2020-01-01T01:00:00-03:00","workflow":"%s","mode":"%s","agents":%s,"reason":"fixture vencida"}\n' \
    "$sid" "$wf" "$md" "$agents_json" > "$MAESTRO_HOME/sessions/$sid.json"
}

OUT=''; RC=0
run_hook() { # run_hook <session_id> <prompt> → OUT/RC
  local json
  json=$(jq -nc --arg s "$1" --arg p "$2" '{session_id:$s, prompt:$p}')
  OUT=$(printf '%s' "$json" | "$HOOK" 2>"$ERR"); RC=$?
  return 0
}

log_lines()  { [[ -f "$LOG" ]] && wc -l <"$LOG" | tr -d ' ' || echo 0; }
last_line()  { [[ -f "$LOG" ]] && tail -1 "$LOG" || echo ""; }

# assert_no_new_line <descrição> <contagem-antes>
assert_no_new_line() {
  local desc="$1" before="$2" after
  after=$(log_lines)
  [[ "$after" -eq "$before" ]] && ok "$desc: NÃO emitiu" || bad "$desc: emitiu ($before -> $after)"
}

# assert_route_fix <descrição> <contagem-antes> <axis-esperado>
assert_route_fix() {
  local desc="$1" before="$2" want_axis="$3" after line ev got_sid got_axis
  after=$(log_lines)
  if [[ "$after" -ne $((before + 1)) ]]; then
    bad "$desc: esperava +1 linha, veio $((after - before))"
    return 0
  fi
  line=$(last_line)
  ev=$(printf '%s' "$line" | jq -r '.event // ""' 2>/dev/null)
  got_axis=$(printf '%s' "$line" | jq -r '.axis // ""' 2>/dev/null)
  got_sid=$(printf '%s' "$line" | jq -r '.session_id // ""' 2>/dev/null)
  [[ "$ev" == "route_fix" ]] && ok "$desc: event=route_fix" || bad "$desc: event='$ev'"
  [[ "$got_axis" == "$want_axis" ]] && ok "$desc: axis=$want_axis" || bad "$desc: axis='$got_axis' (esperado $want_axis)"
  [[ -n "$got_sid" ]] && ok "$desc: session_id presente" || bad "$desc: session_id ausente"
  # Contrato do vocabulário fechado: SÓ ts/event/session_id/axis, nada mais.
  local keys; keys=$(printf '%s' "$line" | jq -r 'keys_unsorted|sort|join(",")' 2>/dev/null)
  [[ "$keys" == "axis,event,session_id,ts" ]] && ok "$desc: chaves = ts/event/session_id/axis, nada mais" \
    || bad "$desc: chaves fora do contrato: $keys"
  return 0
}

echo "-- 1. contradição de mode (record subagent, prompt cita direct)"
write_record sess-mode fix subagent golang-pro
before=$(log_lines)
run_hook sess-mode "nao, roda em direct por favor"
[[ $RC -eq 0 ]] && ok "1: hook sai 0" || bad "1: rc=$RC"
[[ -z "$OUT" ]] && ok "1: stdout vazio" || bad "1: escreveu em stdout"
assert_route_fix "1 mode" "$before" "mode"

echo "-- 2. contradição de workflow (record fix, prompt cita feature)"
write_record sess-wf fix subagent golang-pro
before=$(log_lines)
run_hook sess-wf "trata isso como feature, por favor"
assert_route_fix "2 workflow" "$before" "workflow"

echo "-- 3. contradição de agente (record só golang-pro, prompt cita dev-pleno)"
write_record sess-ag fix subagent golang-pro
before=$(log_lines)
run_hook sess-ag "poe o dev-pleno nessa tarefa"
assert_route_fix "3 agente" "$before" "agents"

echo "-- 4. contradição de MODELO (golang-pro é sonnet; prompt pede haiku)"
write_record sess-mdl fix subagent golang-pro
before=$(log_lines)
run_hook sess-mdl "usa haiku nessa"
assert_route_fix "4 modelo" "$before" "agents"

echo "-- 4b. contradição real, mas contra record VENCIDO → não emite (ressalva da reordenação)"
write_expired_record sess-vencida fix subagent golang-pro
before=$(log_lines)
run_hook sess-vencida "nao, roda em direct por favor"
[[ $RC -eq 0 ]] && ok "4b: hook sai 0 com record vencido" || bad "4b: rc=$RC"
assert_no_new_line "4b contradição contra record vencido" "$before"

echo "-- 5. menção SEM contradição — a asserção que protege a métrica"
write_record sess-nc fix subagent golang-pro
before=$(log_lines)
run_hook sess-nc "confirma que isso e subagent mesmo"
assert_no_new_line "5a mode citado = record" "$before"
before=$(log_lines)
run_hook sess-nc "e um fix simples, sem stress"
assert_no_new_line "5b workflow citado = record" "$before"
before=$(log_lines)
run_hook sess-nc "o golang-pro ja esta cuidando disso"
assert_no_new_line "5c agente citado = record" "$before"
before=$(log_lines)
run_hook sess-nc "sonnet da conta desse tamanho de tarefa"
assert_no_new_line "5d modelo citado = o do agente do record" "$before"

echo "-- 5e. ambíguo (≥2 tokens do mesmo alfabeto): não emite nem o eixo certo"
before=$(log_lines)
run_hook sess-mode "isso e fix ou feature, decide voce"
assert_no_new_line "5e workflow ambíguo" "$before"

echo "-- 6. sem record na sessão → não conta como correção"
before=$(log_lines)
run_hook sess-sem-record "roda em direct, usa haiku, e um feature"
assert_no_new_line "6 sem record" "$before"
[[ $RC -eq 0 ]] && ok "6: hook sai 0 mesmo sem record" || bad "6: rc=$RC"

echo "-- 7. record corrompido/ilegível → mudo, exit 0"
printf 'isto nao e json{{{' > "$MAESTRO_HOME/sessions/sess-corrompida.json"
before=$(log_lines)
run_hook sess-corrompida "roda em direct por favor"
[[ $RC -eq 0 ]] && ok "7a: hook sai 0 com record corrompido" || bad "7a: rc=$RC"
assert_no_new_line "7a record corrompido" "$before"

chmod 000 "$MAESTRO_HOME/sessions/sess-mode.json" 2>/dev/null
if [[ -r "$MAESTRO_HOME/sessions/sess-mode.json" ]]; then
  ok "7b: ilegível pulado (rodando como root?)"
else
  before=$(log_lines)
  run_hook sess-mode "roda em direct por favor"
  [[ $RC -eq 0 ]] && ok "7b: hook sai 0 com record ilegível" || bad "7b: rc=$RC"
  assert_no_new_line "7b record ilegível" "$before"
fi
chmod 600 "$MAESTRO_HOME/sessions/sess-mode.json" 2>/dev/null

echo "-- 8. sem jq no PATH → degrada MUDO, exit 0 (nem override_manual, nem route_fix)"
fakebin="$SANDBOX/bin"; mkdir -p "$fakebin"
for b in bash env sh dirname mkdir date stat cat flock tail wc tr grep sed; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$fakebin/$b"
done
write_record sess-nojq fix subagent golang-pro
before=$(log_lines)
json=$(jq -nc --arg s "sess-nojq" --arg p "roda em direct, usa haiku" '{session_id:$s, prompt:$p}')
out=$(printf '%s' "$json" | PATH="$fakebin" "$HOOK" 2>"$ERR"); rc=$?
[[ $rc -eq 0 && -z "$out" ]] && ok "8: sem jq — exit 0, stdout vazio" || bad "8: sem jq (rc=$rc out='$out')"
assert_no_new_line "8 sem jq" "$before"

echo "-- 9. canário: nenhum caminho grava trecho do prompt no log"
CANARY="CANARIO-UNICO-9f8e7d6c5b4a"
write_record sess-canario fix subagent golang-pro
run_hook sess-canario "${CANARY} roda em direct, usa haiku, poe o dev-pleno, e um feature"
if grep -qF -- "$CANARY" "$LOG"; then
  bad "9: VAZOU o canário no log"
else
  ok "9: canário não vazou no log inteiro"
fi
# Nenhuma chave do log aceita '/': garantia estrutural (DATA_MODEL §4).
grep -q '/' "$LOG" && bad "9: log contém '/' — vazamento de caminho" || ok "9: nenhum '/' no log inteiro"

if [[ $fail -eq 0 ]]; then echo "test-order-030-sensor-rota: OK"; else echo "test-order-030-sensor-rota: FALHOU" >&2; fi
exit $fail
