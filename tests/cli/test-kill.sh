#!/usr/bin/env bash
# E25 / S-2501 — `killed`: decidir NÃO construir é desfecho, não silêncio.
#
# O que este teste protege: o porquê é OBRIGATÓRIO (kill sem motivo é ruído, e
# quem lê o retro daqui a um mês precisa dele); o kill não passa pelos gates de
# prova (não há entrega a provar) nem HERDA a prova de um desfecho anterior; o
# texto do porquê fica no record e nunca no log; e o record continua válido no
# schema em toda transição de desfecho — inclusive na volta.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
# Projeto NEUTRO: `outcome accepted` consulta o `.maestro.yaml` corrente, e sem
# isto a suíte julgaria o repo do Maestro (que declara `verifications:`).
NEUTRO="$tmp/neutro"; mkdir -p "$NEUTRO"; export CLAUDE_PROJECT_DIR="$NEUTRO"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pend(){ printf 'PEND %s\n' "$1"; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v jq >/dev/null || { echo "FAIL jq ausente"; exit 1; }
command -v bun >/dev/null || { echo "FAIL bun ausente (decide precisa)"; exit 1; }

LOG="$MAESTRO_HOME/logs/routing.jsonl"

emit_started() { # a prova de delegação sai do hook de verdade, não de fixture
  printf '{"session_id":"%s","tool_name":"Task","tool_input":{"subagent_type":"%s"}}' \
    "$1" "${2:-dev-pleno}" | "$REPO/hooks/pre-agent.sh" >/dev/null 2>&1 || true
}

echo "-- E25/S-2501: killed é desfecho de primeira classe (decidimos NÃO construir)"
# ---------------------------------------------------------------------------
"$BIN" decide --session kill-a --workflow fix --mode subagent --agents dev-pleno >/dev/null 2>&1
RECK="$MAESTRO_HOME/sessions/kill-a.json"
KMOTIVO="o custo do build supera o valor; o fluxo manual ja resolve"
out=$("$BIN" outcome --session kill-a killed --reason "$KMOTIVO" 2>&1); rc=$?
chk "killed --reason sobre record existente → exit 0" "$rc" "0"
chk "record fecha com outcome killed" "$(jq -r '.outcome' "$RECK")" "killed"
chk "record grava o porquê" "$(jq -r '.kill_reason' "$RECK")" "$KMOTIVO"
# mode subagent SEM nenhuma 'delegation phase=started': o gate do E23a existe
# porque o ACEITE afirma que a entrega serve — no kill não há entrega.
chk "kill não passa pelo gate de delegação (nem carimba delegation_proof)" \
    "$(jq -r 'has("delegation_proof")' "$RECK")" "false"
grep -q 'Fora de escopo' <<<"$out" && ok "a saída aponta onde o kill sobrevive (INTENT)" || bad "saída sem ponteiro para o INTENT ($out)"
grep -q 'intent --bump' <<<"$out" && ok "e lembra que a versão sobe à mão" || bad "saída sem intent --bump ($out)"

"$BIN" decide --session kill-b --workflow fix --mode direct >/dev/null 2>&1
RECB="$MAESTRO_HOME/sessions/kill-b.json"
out=$("$BIN" outcome --session kill-b killed 2>&1); rc=$?
chk "killed sem --reason → exit 1 (kill sem porquê é ruído, não registro)" "$rc" "1"
grep -q -- '--reason' <<<"$out" && ok "a recusa entrega o comando certo" || bad "recusa sem o comando ($out)"
chk "e o record NÃO é tocado" "$(jq -r '.outcome // "AUSENTE"' "$RECB")" "AUSENTE"
"$BIN" outcome --session kill-b accepted --reason "por que sim" >/dev/null 2>&1; rc=$?
chk "--reason com veredito ≠ killed → exit 1 (a razão da aposta é do decide)" "$rc" "1"
"$BIN" outcome --session kill-b killed --reason "por que não" --suite pass >/dev/null 2>&1; rc=$?
chk "killed --suite → exit 1 (nada foi construído, não há suíte a anexar)" "$rc" "1"
chk "nenhuma das recusas fechou o record" "$(jq -r '.outcome // "AUSENTE"' "$RECB")" "AUSENTE"

LONGA=$(printf '%0.sx' {1..200})
out=$("$BIN" outcome --session kill-b killed --reason "$LONGA" 2>&1); rc=$?
chk "--reason acima de 120 → exit 0 (trunca, não falha em silêncio)" "$rc" "0"
chk "e o record guarda exatamente 120 chars (teto do reason, DATA_MODEL §3)" \
    "$(jq -r '.kill_reason | length' "$RECB")" "120"
grep -q 'truncado em 120' <<<"$out" && ok "o truncamento é dito em voz alta" || bad "truncamento silencioso ($out)"

# A regressão que o del(.kill_reason) evita: desfecho é last-wins, e uma sessão
# morta e depois reaberta como accepted ficaria com kill_reason órfão — record
# inválido no doctor para quem fez tudo certo.
"$BIN" outcome --session kill-b accepted >/dev/null 2>&1; rc=$?
chk "record morto e depois fechado como accepted → exit 0" "$rc" "0"
chk "e o kill_reason SOME do record" "$(jq -r 'has("kill_reason")' "$RECB")" "false"

out=$("$BIN" doctor --ci 2>&1); rc=$?
chk "doctor com record killed → exit 0" "$rc" "0"
grep -q 'decision records.*inválido' <<<"$out" && bad "doctor reprova record ($out)" || ok "record killed passa no schema DATA_MODEL §3"

grep -q "$KMOTIVO" "$LOG" && bad "o porquê do descarte VAZOU para o log" || ok "o porquê fica no record, jamais no log"
# O log tem vocabulário próprio (DATA_MODEL §4) e a allowlist de valores mora em
# hooks/lib/common.sh — arquivo de outra frente. Enquanto `killed` não entrar lá,
# o log_event descarta o valor (degrada, não quebra) e o evento sai sem o campo.
if grep -q 'accepted|rework|reverted|killed' "$REPO/hooks/lib/common.sh"; then
  grep -q '"event":"outcome".*"outcome":"killed"' "$LOG" \
    && ok "log carrega outcome=killed (enum)" || bad "outcome=killed ausente no log"
else
  pend "hooks/lib/common.sh: outcome ainda aceita só (accepted|rework|reverted) — killed é descartado do log"
  grep -q '"event":"outcome","session_id":"kill-a"' "$LOG" \
    && ok "o evento de desfecho do kill é logado mesmo assim (degrada, não bloqueia)" \
    || bad "evento de outcome do kill ausente no log"
fi


echo "-- E25: o kill não HERDA a prova do desfecho anterior (del simétrico)"
"$BIN" decide --session sym-1 --workflow fix --mode subagent --agents dev-pleno >/dev/null 2>&1
emit_started sym-1
"$BIN" outcome --session sym-1 accepted --suite pass >/dev/null 2>&1
SYM="$MAESTRO_HOME/sessions/sym-1.json"
chk "antes: suite gravada" "$(jq -r '.suite // "-"' "$SYM")" "pass"
chk "antes: delegação provada" "$(jq -r '.delegation_proof // "-"' "$SYM")" "started"
"$BIN" outcome --session sym-1 killed --reason "mudei de ideia: não deve existir" >/dev/null 2>&1
chk "killed limpa suite" "$(jq -r 'has("suite")' "$SYM")" "false"
chk "killed limpa suite_evidence" "$(jq -r 'has("suite_evidence")' "$SYM")" "false"
chk "killed limpa delegation_proof" "$(jq -r 'has("delegation_proof")' "$SYM")" "false"
chk "killed limpa verifications" "$(jq -r 'has("verifications")' "$SYM")" "false"
chk "e grava o porquê" "$(jq -r '.kill_reason' "$SYM")" "mudei de ideia: não deve existir"
"$BIN" doctor 2>&1 | grep -q 'decision records:.*inválido' \
  && bad "record do kill herdado reprova no schema" || ok "record segue válido no doctor"

echo "-- E25: flag sem valor ensina, não morre em silêncio"
err=$("$BIN" outcome --session sym-1 killed --reason 2>&1 >/dev/null); rc=$?
chk "--reason sem valor → exit 1" "$rc" "1"
grep -q '^maestro: validation:' <<<"$err" \
  && ok "e com o envelope de erro do API_SPEC §3 (não um exit mudo)" || bad "erro mudo: '$err'"

echo "-- E25: o porquê é cortado em fronteira ASCII (nunca no meio de um caractere)"
LONGO=$(printf 'ação e reação com acento até estourar o teto de cento e vinte caracteres do schema e seguir bem além disso aqui ó pronto acabou')
"$BIN" outcome --session sym-1 killed --reason "$LONGO" >/dev/null 2>&1
KR=$(jq -r '.kill_reason' "$SYM")
[[ ${#KR} -le 120 ]] && ok "cabe no teto de 120 (${#KR})" || bad "estourou o teto (${#KR})"
[[ "$KR" != *" " || "$KR" != *"  "* ]] && ok "corte não deixou espaço solto no fim" || bad "corte sujo"
jq -e '.kill_reason | test("\\uFFFD") | not' "$SYM" >/dev/null \
  && ok "sem caractere de substituição (UTF-8 não foi partido)" || bad "UTF-8 partido no corte"

echo "-- E25: o doctor não cobra approach de quem descartou"
"$BIN" decide --session sym-2 --workflow feature --mode direct \
  --brief "essencia: ideia; impacto: y; approach: pendente" >/dev/null 2>&1
"$BIN" outcome --session sym-2 killed --reason "não vale construir" >/dev/null 2>&1
"$BIN" doctor 2>&1 | grep -q 'record sym-2: outcome registrado com approach pendente' \
  && bad "doctor pede o plano de execução do que foi descartado" \
  || ok "kill não gera cobrança de approach"
"$BIN" outcome --session sym-2 rework >/dev/null 2>&1
"$BIN" doctor 2>&1 | grep -q 'record sym-2: outcome registrado com approach pendente' \
  && ok "e a cobrança volta para desfecho que pressupõe entrega" || bad "cobrança sumiu para rework"

exit $fail

exit $fail
