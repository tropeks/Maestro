#!/usr/bin/env bash
# ordem 077 (turno 3) — a allowlist do experimento, montada pelo lancar.sh a partir de
# docs/experimento/politicas.json: Bash(echo|printf|sort|uniq|cut|tr *) entram IGUAIS nas duas configurações;
# env, tee e mkdir não entram em nenhuma; a diferença entre as duas listas continua sendo só maestro e Ponte.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/harness-minimo/lancar.sh"
POL="$REPO/docs/experimento/politicas.json"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

[[ -x "$TOOL" && -f "$POL" ]] || { bad "lancar.sh ou politicas.json ausente"; exit 1; }

# base de fixture e claude falso (só --version é usado no --dry-run)
B="$tmp/base"; mkdir -p "$B"
echo "x" > "$B/a.txt"
git -C "$B" init -q -b main; git -C "$B" config user.email t@t; git -C "$B" config user.name t
git -C "$B" add -A; git -C "$B" commit -qm base
printf '#!/usr/bin/env bash\necho "9.9.9 (Claude Code)"\n' > "$tmp/claude"; chmod +x "$tmp/claude"
export HM_CLAUDE_BIN="$tmp/claude"

bash "$TOOL" --config 2 --base "$B" --saida "$tmp/s2" --texto x --politicas "$POL" --dry-run >/dev/null 2>&1 || bad "config 2 dry-run falhou"
bash "$TOOL" --config 1 --base "$B" --saida "$tmp/s1" --texto x --politicas "$POL" --ponte-bridge /bin/true --ponte-socket /tmp/sock-fixture --dry-run >/dev/null 2>&1 || bad "config 1 dry-run falhou"

L1=$(jq -c '.permissions.allow' "$tmp/s1/arquivos/settings.json" 2>/dev/null)
L2=$(jq -c '.' "$tmp/s2/arquivos/allowlist.json" 2>/dev/null)
[[ -n "$L1" && -n "$L2" ]] || { bad "listas montadas ausentes"; exit 1; }

for cmd in echo printf sort uniq cut tr; do
  jq -e --arg e "Bash($cmd *)" 'index($e)' <<<"$L1" >/dev/null && ok "config 1 tem Bash($cmd *)" || bad "config 1 sem Bash($cmd *)"
  jq -e --arg e "Bash($cmd *)" 'index($e)' <<<"$L2" >/dev/null && ok "config 2 tem Bash($cmd *)" || bad "config 2 sem Bash($cmd *)"
done
for cmd in env tee mkdir; do
  jq -e --arg e "Bash($cmd *)" 'index($e)' <<<"$L1" >/dev/null && bad "config 1 tem Bash($cmd *)" || ok "config 1 sem Bash($cmd *)"
  jq -e --arg e "Bash($cmd *)" 'index($e)' <<<"$L2" >/dev/null && bad "config 2 tem Bash($cmd *)" || ok "config 2 sem Bash($cmd *)"
done

# a diferença entre as duas listas é só maestro e Ponte
DIF=$(jq -rn --argjson a "$L1" --argjson b "$L2" '($a - $b) | sort | join(",")')
ESP='Bash(./bin/maestro *),Bash(maestro *),mcp__ponte__director_ask,mcp__ponte__director_report,mcp__ponte__director_wait'
[[ "$DIF" == "$ESP" ]] && ok "config 1 menos config 2 = só maestro e Ponte" || bad "diferença inesperada: $DIF"
[[ "$(jq -rn --argjson a "$L1" --argjson b "$L2" '($b - $a) | length')" == 0 ]] && ok "config 2 não tem nada além da config 1" || bad "config 2 tem item que a config 1 não tem"

exit $fail
