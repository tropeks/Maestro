#!/usr/bin/env bash
# ordem 085 (CONTRATO v3) — `approved_with_conditions` com todo check_ref libera a
# edição do gate domain; cada condição vira critério do aceite da ordem.
# Gate: (a) todas com check_ref liberam; (b) uma null não libera; (c) revogada ou
# vencida não libera; (d) manual não libera; `approved` puro segue igual.
# Aceite: (e) sem --condicoes-conferidas recusa e lista; (f) com a flag aceita e
# grava `accepted_conditions:` (só texto e check_ref). Hermético (mktemp -d).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
GATE="$REPO/hooks/pre-tool-gate.sh"
WAIT="$REPO/hooks/post-director-wait.sh"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

SB=$(mktemp -d)
trap '[[ $$ == $BASHPID ]] && rm -rf "$SB"' EXIT
export MAESTRO_HOME="$SB/home" MAESTRO_NO_UPDATE_CHECK=1
P="$SB/proj"; mkdir -p "$P/.maestro" "$P/docs" "$MAESTRO_HOME/sessions" "$MAESTRO_HOME/logs"
export CLAUDE_PROJECT_DIR="$P"
body=$'## Problema\np\n'
printf '<!-- maestro-intent\nversion: 7\nhash: %s\n-->\n%s' "$(printf '%s' "$body" | sha256sum | head -c 8)" "$body" \
  > "$P/.maestro/INTENT.md"
printf '# Plano\n\n## Rollback\ngit revert\n' > "$P/docs/rollback.md"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
REC() { printf '%s/sessions/%s.json' "$MAESTRO_HOME" "$1"; }

command -v jq >/dev/null || { echo "FAIL jq ausente"; exit 1; }
if ! command -v bun >/dev/null; then echo "skip sem Bun (decide é src/cli.ts)"; exit 0; fi

printf 'MAESTRO_GATE_MODE="block"\nMAESTRO_GATE_ALLOW_EXT=".md .txt"\nMAESTRO_GATE_ALLOW_PATHS=".maestro/ docs/"\nMAESTRO_GATE_DENY_PATHS=".claude/"\nMAESTRO_PLUGIN_ROOT="/opt/maestro-plugin"\nMAESTRO_GATE_DOMAIN_SECURITY_RE='"'"'^(\\.env.*)$'"'"'\n' \
  > "$MAESTRO_HOME/gate-policy.sh"

VU=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
new_session() { # <sid> — pedido de segurança da ordem 85
  "$BIN" decide --session "$1" --workflow feature --mode direct \
    --brief "essencia: chave nova; impacto: integra x; approach: le a chave no boot" \
    --targets ".env.example" --effects "variavel nova" --rollback "docs/rollback.md#rollback" --order 85 >/dev/null 2>&1
}
dec() { # dec <sid> <decision_id> <response> <conds json> — decisão do diretor de segurança
  local rid ih; rid=$(jq -r '.domain.requests[0].request_id' "$(REC "$1")"); ih=$(jq -r '.domain.requests[0].intent.hash' "$(REC "$1")")
  jq -nc --arg did "$2" --arg rid "$rid" --arg r "$3" --argjson c "$4" --arg vu "${VUX:-$VU}" --arg ih "$ih" '
    {decision_id:$did, request_id:$rid, response:$r, conditions:$c, reason:"plano verificado",
     decided_by:{role:"director_domain", domain:"security", label:"x"},
     policy_ref:"tropeks/spock:docs/diretoria/MANDATOS@v2#1a2b3c4d5e6f", intent:{version:7, hash:$ih}, valid_until:$vu}'
}
wait_hook() { # <sid> <decisão json> — director_wait como o servidor da Ponte devolve
  jq -nc --arg sid "$1" --arg note "decisao: $2" --argjson d "$2" '
    {session_id:$sid, hook_event_name:"PostToolUse", tool_name:"mcp__ponte__director_wait", tool_input:{decision_id:"01ABC"},
     tool_response:[{type:"text", text:({status:"respondida", decision_id:"01ABC", resposta:$note,
       resolvido_em:"2026-10-20T00:00:00Z", domain_decisions:[$d]} | tojson)}]}' | bash "$WAIT" >/dev/null 2>&1
}
edit() { printf '{"tool_name":"Edit","session_id":"%s","tool_input":{"file_path":"%s/%s"}}' "$1" "$P" "$2" | bash "$GATE" >/dev/null 2>&1; echo $?; }
COK='[{"texto":"sem segredo no log","check_ref":"tests/log.sh"},{"texto":"rotaciona a chave","check_ref":"docs/rot.md#passo"}]'
CNULL='[{"texto":"sem segredo no log","check_ref":"tests/log.sh"},{"texto":"revisar na mao","check_ref":null}]'

echo "-- gate: (a) todas as condições com check_ref liberam"
new_session s-a; wait_hook s-a "$(dec s-a d1 approved_with_conditions "$COK")"
chk "status approved, cleared security" "$(jq -r '"\(.domain.status) \(.domain.cleared)"' "$(REC s-a)")" "approved security"
chk "edição do alvo de domínio passa" "$(edit s-a .env.example)" "0"

echo "-- gate: (b) um check_ref null não libera"
new_session s-b; wait_hook s-b "$(dec s-b d1 approved_with_conditions "$CNULL")"
chk "status segue approved_with_conditions" "$(jq -r '.domain.status' "$(REC s-b)")" "approved_with_conditions"
chk "edição bloqueada" "$(edit s-b .env.example)" "2"

echo "-- gate: (c) revogada ou vencida não libera"
RV=$(dec s-a d1 approved_with_conditions "$COK" | jq -c '.revoked_at = "2026-10-26T00:00:00Z"')
wait_hook s-a "$RV"
chk "revogada: pending" "$(jq -r '.domain.status' "$(REC s-a)")" "pending"
chk "revogada: edição bloqueada" "$(edit s-a .env.example)" "2"
new_session s-c; wait_hook s-c "$(dec s-c d1 approved_with_conditions "$COK")"
jq -c '.domain.decisions |= map(.until_epoch = 1) | .domain.cleared_until = 1' "$(REC s-c)" > "$SB/t" && mv "$SB/t" "$(REC s-c)"
chk "vencida: edição bloqueada" "$(edit s-c .env.example)" "2"

echo "-- gate: (d) manual não libera"
new_session s-d
"$BIN" conduct --session s-d --domain-decision "$(dec s-d m1 approved_with_conditions "$COK")" >/dev/null 2>&1
chk "manual: decisão registrada, status pending" "$(jq -r '.domain.status' "$(REC s-d)")" "pending"
chk "manual: edição bloqueada" "$(edit s-d .env.example)" "2"

echo "-- gate: approved puro continua igual"
new_session s-p; wait_hook s-p "$(dec s-p d1 approved '[]')"
chk "approved: edição passa" "$(edit s-p .env.example)" "0"

echo "-- aceite: condições liberadas viram critério (e, f)"
git -C "$P" init -q; echo a > "$P/f.txt"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm base
"$BIN" order --create --title "Cond" --project "$P" --session s-a >/dev/null <<<$'## Objetivo\nx\n'
source "$REPO/tests/lib/declare-order.sh"
declare_order "$P" 1 'true'
OF=$(ls "$P/.maestro/orders/"001-*.md)
git -C "$P" checkout -qb "$(awk '/^branch:/ {print $2}' "$OF")"
echo b >> "$P/f.txt"; git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm entrega
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
new_session s-e; wait_hook s-e "$(dec s-e e1 approved_with_conditions "$COK")"
jq -c '.domain.requests |= map(.order_ref = "1")' "$(REC s-e)" > "$SB/t" && mv "$SB/t" "$(REC s-e)"
OUT=$("$BIN" order --accept 1 --project "$P" --session s-e --intent-reviewed 2>&1); RC=$?
chk "(e) sem a flag: recusa" "$RC" "1"
[[ "$OUT" == *"sem segredo no log"* && "$OUT" == *"tests/log.sh"* && "$OUT" == *"docs/rot.md#passo"* ]] \
  && ok "(e) recusa lista texto e check_ref" || bad "(e) saída: $OUT"
grep -q '^accepted_at:' "$OF" && bad "(e) gravou carimbo apesar da recusa" || ok "(e) nada gravado"
OUT=$("$BIN" order --accept 1 --project "$P" --session s-e --intent-reviewed --condicoes-conferidas 2>&1); RC=$?
chk "(f) com a flag: aceita" "$RC" "0"
chk "(f) carimbo grava só texto e check_ref" "$(sed -n 's/^accepted_conditions: //p' "$OF")" \
  '[{"texto":"sem segredo no log","check_ref":"tests/log.sh"},{"texto":"rotaciona a chave","check_ref":"docs/rot.md#passo"}]'

exit "$fail"
