#!/usr/bin/env bash
# S-1811 — hooks/session-end.sh: uma linha `session_end` por fim de sessão, só
# metadados (decided/settled), nunca conteúdo do record; exit 0 em qualquer
# cenário; nada em stdout. Hermético: MAESTRO_HOME em mktemp.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-end.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

n=0; next_home() { n=$((n+1)); H="$SANDBOX/home$n"; mkdir -p "$H/sessions" "$H/logs"; }
run() { # run <stdin-string> [VAR=VAL ...]
  local input="$1"; shift
  printf '%s' "$input" | env MAESTRO_HOME="$H" "$@" bash "$HOOK" >"$SANDBOX/out" 2>"$SANDBOX/err"
  RC=$?
  OUT=$(cat "$SANDBOX/out")
}
last() { tail -1 "$H/logs/routing.jsonl" 2>/dev/null; }
record() { # record <sid> [outcome]
  local o=""; [[ -n "${2:-}" ]] && o=",\"outcome\":\"$2\",\"outcome_ts\":\"2026-09-01T00:00:00-03:00\""
  printf '{"session_id":"%s","ts":"2026-09-01T00:00:00-03:00","expires_at":"2099-01-01T00:00:00-03:00","workflow":"fix","mode":"direct","reason":"segredo-do-record","brief":"essencia: nao-vaza"%s}\n' "$1" "$o" > "$H/sessions/$1.json"
}

echo "-- sem record: decided=no settled=no"
next_home; run '{"session_id":"end-1","reason":"exit"}'
chk "exit 0" "$RC" "0"
chk "stdout vazio" "$OUT" ""
l=$(last)
[[ "$l" == *'"event":"session_end"'* && "$l" == *'"session_id":"end-1"'* ]] && ok "evento session_end com session_id" || bad "evento ausente: $l"
[[ "$l" == *'"decided":"no"'* && "$l" == *'"settled":"no"'* ]] && ok "decided=no settled=no" || bad "flags erradas: $l"

echo "-- record sem desfecho: decided=yes settled=no"
next_home; record end-2; run '{"session_id":"end-2"}'
l=$(last)
[[ "$l" == *'"decided":"yes"'* && "$l" == *'"settled":"no"'* ]] && ok "decided=yes settled=no" || bad "flags erradas: $l"
[[ "$l" == *segredo* || "$l" == *nao-vaza* || "$l" == *fix* ]] && bad "conteúdo do record vazou no log" || ok "nada do record no log"

echo "-- record com desfecho: settled=yes"
next_home; record end-3 accepted; run '{"session_id":"end-3"}'
l=$(last)
[[ "$l" == *'"decided":"yes"'* && "$l" == *'"settled":"yes"'* ]] && ok "decided=yes settled=yes" || bad "flags erradas: $l"

echo "-- desfecho fora do enum não conta"
next_home; record end-4 maybe; run '{"session_id":"end-4"}'
l=$(last)
[[ "$l" == *'"settled":"no"'* ]] && ok "enum fechado" || bad "aceitou desfecho inválido: $l"

echo "-- degradação: stdin vazio, lixo, session_id inválido, kill-switch"
next_home; run ''
chk "stdin vazio: exit 0" "$RC" "0"; [[ -f "$H/logs/routing.jsonl" ]] && bad "logou sem session_id" || ok "sem session_id, sem evento"
run 'isso nao e json'
chk "lixo: exit 0" "$RC" "0"; [[ -f "$H/logs/routing.jsonl" ]] && bad "logou com lixo" || ok "lixo: sem evento"
run '{"session_id":"../../etc/passwd"}'
chk "sid inválido: exit 0" "$RC" "0"; [[ -f "$H/logs/routing.jsonl" ]] && bad "logou sid inválido" || ok "sid fora do tipo: sem evento"
run '{"session_id":"end-5"}' MAESTRO_OFF=1
chk "kill-switch: exit 0" "$RC" "0"; [[ -f "$H/logs/routing.jsonl" ]] && bad "kill-switch não segurou" || ok "kill-switch vence"
run '{"session_id":"end-6"}' MAESTRO_HOME=/proc/nao-escreve
chk "home inescrevível: exit 0" "$RC" "0"

echo "-- CLAUDE_SESSION_ID cobre stdin sem id"
next_home; run '{"reason":"clear"}' CLAUDE_SESSION_ID=end-7
l=$(last)
[[ "$l" == *'"session_id":"end-7"'* ]] && ok "id do env" || bad "id do env ignorado: $l"

if command -v jq >/dev/null; then
  jq -e . "$H/logs/routing.jsonl" >/dev/null 2>&1 && ok "JSONL válido" || bad "JSONL malformado"
fi

echo
if [[ $fail -eq 0 ]]; then echo "test-session-end: OK"; else echo "test-session-end: FALHOU"; fi
exit $fail
