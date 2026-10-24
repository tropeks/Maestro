#!/usr/bin/env bash
# Fase 1 da auditoria (INTENT v62, sombra de 7 dias): com `gate.mode: warn` na política da sessão o
# pre-bash-guard só REGISTRA o que bloquearia (gate_warn, exit 0). Com a política em block, ausente
# ou ilegível, o guarda se comporta exatamente como antes (exit 2 + gate_block). O rollback é o
# `gate.mode: block` e nada mais.
#   1. política em warn + sessão autônoma + comando destrutivo → exit 0, gate_warn, nenhum gate_block;
#   2. política em warn + escrita por Bash em self_paths → exit 0, gate_warn cmd=self_path_write;
#   3. política em block → exit 2 + gate_block nos dois casos (nada mudou);
#   4. política ausente e política ilegível → exit 2 nos dois casos (falha fechada no guarda);
#   5. routing-table.yaml traz gate.mode: block (fase 1 encerrada, decisão 01M5NMF64W) e o rollback declarado.
# Os casos 1-2 seguem provando o caminho `warn` por fixture (política explícita), não pela tabela real.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/pre-bash-guard.sh"
SID="sess-sombra01"
PROJ="/home/user/proj"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export MAESTRO_HOME="$TMP/home"
export CLAUDE_PROJECT_DIR="$PROJ"
mkdir -p "$MAESTRO_HOME/sessions" "$MAESTRO_HOME/logs"
LOG="$MAESTRO_HOME/logs/routing.jsonl"

now=$(date -Iseconds); exp=$(date -Iseconds -d "@$(( $(date +%s) + 14400 ))")
printf '{"session_id":"%s","ts":"%s","expires_at":"%s","workflow":"fix","mode":"subagent","agents":["golang-pro"],"reason":"teste"}\n' \
  "$SID" "$now" "$exp" > "$MAESTRO_HOME/sessions/$SID.json"

printf 'MAESTRO_GATE_MODE="warn"\n'  > "$TMP/policy-warn.sh"
printf 'MAESTRO_GATE_MODE="block"\n' > "$TMP/policy-block.sh"
printf 'if [[ ((((\n'                > "$TMP/policy-ilegivel.sh"

payload() { jq -n --arg c "$1" --arg s "$SID" --arg d "$2" \
  '{session_id:$s,transcript_path:"/dev/null",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }

# run <política> <cwd> <comando> → RC e o conjunto de eventos novos do log
run() {
  : > "$LOG"
  payload "$3" "$2" | MAESTRO_GATE_POLICY="$1" "$GUARD" >/dev/null 2>&1; RC=$?
  EVS=$(jq -r '.event + ":" + (.cmd // "")' "$LOG" 2>/dev/null | tr '\n' ' ')
}

DESTRUTIVO="git push --force origin main"
SELFW="echo x > lib/a.sh"

echo "-- 1: política em warn, sessão autônoma, comando destrutivo → só registra"
run "$TMP/policy-warn.sh" "$PROJ" "$DESTRUTIVO"
check "warn: exit 0" "$RC" "0"
[[ "$EVS" == *"gate_warn:git_force_push"* ]] && ok "warn: gate_warn cmd=git_force_push no log" || bad "warn: sem gate_warn git_force_push ($EVS)"
[[ "$EVS" != *gate_block* ]] && ok "warn: nenhum gate_block" || bad "warn: gate_block no log ($EVS)"

echo "-- 2: política em warn, escrita por Bash em self_paths → só registra"
run "$TMP/policy-warn.sh" "$REPO" "$SELFW"
check "warn self_path: exit 0" "$RC" "0"
[[ "$EVS" == *"gate_warn:self_path_write"* ]] && ok "warn self_path: gate_warn cmd=self_path_write" || bad "warn self_path: sem gate_warn ($EVS)"
[[ "$EVS" != *gate_block* ]] && ok "warn self_path: nenhum gate_block" || bad "warn self_path: gate_block no log ($EVS)"

echo "-- 3: política em block → nada mudou"
run "$TMP/policy-block.sh" "$PROJ" "$DESTRUTIVO"
check "block: exit 2" "$RC" "2"
[[ "$EVS" == *"gate_block:git_force_push"* ]] && ok "block: gate_block cmd=git_force_push" || bad "block: sem gate_block ($EVS)"
run "$TMP/policy-block.sh" "$REPO" "$SELFW"
check "block self_path: exit 2" "$RC" "2"
[[ "$EVS" == *"gate_block:self_path_write"* ]] && ok "block self_path: gate_block cmd=self_path_write" || bad "block self_path: sem gate_block ($EVS)"

echo "-- 4: política ausente ou ilegível → o guarda segue como antes (exit 2)"
run "$TMP/nao-existe.sh" "$PROJ" "$DESTRUTIVO"
check "política ausente: exit 2" "$RC" "2"
run "$TMP/policy-ilegivel.sh" "$PROJ" "$DESTRUTIVO"
check "política ilegível: exit 2" "$RC" "2"
run "$TMP/nao-existe.sh" "$REPO" "$SELFW"
check "política ausente, self_path: exit 2" "$RC" "2"

echo "-- 5: fase 1 encerrada — routing-table.yaml em block, com a decisão e o rollback citados na linha 3"
grep -qE '^  mode: block( |$)' "$REPO/config/routing-table.yaml" \
  && ok "routing-table.yaml: gate.mode: block" || bad "routing-table.yaml: gate.mode não é block"
L3=$(sed -n 3p "$REPO/config/routing-table.yaml")
[[ "$L3" == *"FASE 1 ENCERRADA"* && "$L3" == *"01M5NMF64W"* ]] \
  && ok "routing-table.yaml linha 3: cita o encerramento e a decisão 01M5NMF64W" || bad "routing-table.yaml linha 3: sem o encerramento/decisão ($L3)"
[[ "$(sed -n 4p "$REPO/config/routing-table.yaml")" == *"rollback declarado = block"* ]] \
  && ok "routing-table.yaml: rollback declarado = block ao lado do modo" || bad "routing-table.yaml: sem o rollback declarado ao lado do modo"

exit $fail
