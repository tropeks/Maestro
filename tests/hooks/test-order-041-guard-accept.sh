#!/usr/bin/env bash
# ordem 041 (aceite por identidade) — item 7 do desenho: `pre-bash-guard.sh`
# levanta a categoria NOVA `accept` para `maestro order --accept` em sessão
# de EXECUTOR (mode: subagent/multi) — quem tem shell não pode aceitar a
# própria ordem sem o humano no loop. Mesmo harness de
# tests/hooks/test-guarda-destrutiva.sh (S-502): payload sintético, JSON via
# stdin, decision record isolado em MAESTRO_HOME de mktemp.
#
# Lição da 003/004A/013/017/021/022/036: o teste NÃO exige o patch já
# aplicado. Categoria `accept` ausente no vocabulário fechado do guard →
# PENDENTE (nunca reprova — hooks/ está fora do alcance de edição comum,
# quem aplica é o Capitão); presente → cobra de verdade.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/pre-bash-guard.sh"
PROJ="/home/user/proj"
SID="sess-guard-accept01"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
pending() { echo "PENDENTE  $1"; }

GUARD_PATCHED=0
grep -qF '_g_flag accept' "$GUARD" 2>/dev/null && GUARD_PATCHED=1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export MAESTRO_HOME="$TMP/home"
export CLAUDE_PROJECT_DIR="$PROJ"
mkdir -p "$MAESTRO_HOME/sessions" "$MAESTRO_HOME/logs"
LOG="$MAESTRO_HOME/logs/routing.jsonl"

write_record() { # $1 = mode
  local mode="$1" now exp agents=',"agents":["golang-pro"]'
  [[ "$mode" == "direct" ]] && agents=""
  now=$(date -Iseconds)
  exp=$(date -Iseconds -d "@$(( $(date +%s) + 14400 ))")
  cat > "$MAESTRO_HOME/sessions/$SID.json" <<EOF
{"session_id":"$SID","ts":"$now","expires_at":"$exp","workflow":"fix","mode":"$mode"$agents,"reason":"teste"}
EOF
}
drop_record() { rm -f "$MAESTRO_HOME/sessions/$SID.json"; }
reset_log() { : > "$LOG"; }
last_cmd() { tail -1 "$LOG" 2>/dev/null | jq -r '.cmd // ""' 2>/dev/null; }

payload() { jq -n --arg c "$1" --arg s "$SID" --arg d "$PROJ" \
  '{session_id:$s,transcript_path:"/dev/null",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
run_cmd() { ERR=$(payload "$1" | "$GUARD" 2>&1 >/dev/null); RC=$?; }

if (( GUARD_PATCHED == 0 )); then
  pending "ordem 041: categoria 'accept' ainda ausente em hooks/pre-bash-guard.sh — aplicar o patch"
  exit 0
fi

# ===========================================================================
# 1. sessão de EXECUTOR (subagent) — --accept BLOQUEIA
# ===========================================================================
echo "-- ordem 041: maestro order --accept em sessão de executor"
write_record subagent
reset_log

ACCEPT_CMDS=(
  'maestro order --accept 41'
  'maestro order --accept 41 --project /home/user/proj'
  'maestro order --accept 41 --absorbed-by main'
  'maestro order --accept 41 --intent-reviewed'
  './bin/maestro order --accept 041'
)
for c in "${ACCEPT_CMDS[@]}"; do
  run_cmd "$c"
  if [[ "$RC" == "2" ]]; then ok "bloqueia (subagent): $c"; else bad "bloqueia (subagent): $c (rc=$RC, esperado 2)"; fi
done
C=$(last_cmd)
[[ "$C" == "accept" ]] && ok "categoria logada é 'accept'" || bad "categoria logada é '$C', esperado 'accept'"

# ===========================================================================
# 2. sessão DIRETA (humano no volante) — --accept vira AVISO, nunca bloqueia
# ===========================================================================
echo "-- ordem 041: modo direto não bloqueia (humano no loop)"
write_record direct
reset_log
run_cmd 'maestro order --accept 41'
[[ "$RC" == "0" ]] && ok "modo direto: aviso, exit 0" || bad "modo direto: esperado exit 0, obtido $RC"

echo "-- ordem 041: sem decision record — aviso, nunca bloqueia"
drop_record
reset_log
run_cmd 'maestro order --accept 41'
[[ "$RC" == "0" ]] && ok "sem record: aviso, exit 0" || bad "sem record: esperado exit 0, obtido $RC"

# ===========================================================================
# 3. anti-falso-positivo — nem todo `maestro order` levanta `accept`
# ===========================================================================
echo "-- ordem 041: outros subcomandos de 'maestro order' NÃO levantam 'accept'"
write_record subagent
ROTINEIROS=(
  'maestro order --status 41'
  'maestro order --status 41 --json'
  'maestro order --list'
  'maestro order --create --title x'
)
for c in "${ROTINEIROS[@]}"; do
  run_cmd "$c"
  [[ "$RC" == "0" ]] && ok "não bloqueia: $c" || bad "não bloqueia: $c (rc=$RC, esperado 0)"
done

if (( fail )); then
  echo "FALHOU: tests/hooks/test-order-041-guard-accept.sh"
  exit 1
fi
echo "OK: tests/hooks/test-order-041-guard-accept.sh"
