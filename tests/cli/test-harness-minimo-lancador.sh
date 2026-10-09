#!/usr/bin/env bash
# ordem 077 — tools/harness-minimo/lancar.sh com um `claude` FALSO: o argv da config 1 é o do runner do
# ponte-daemon (sem flag proibida, com Ponte e envelope), o da config 2 é o `claude -p` puro (--safe-mode,
# sem MCP, sem maestro no PATH, dontAsk com lista fechada); os dois recebem MAESTRO_HOME temporário e
# vazio; a base suja é recusada; o recibo da ordem original roda por fora e o rc é gravado.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/harness-minimo/lancar.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

[[ -x "$TOOL" ]] || { bad "lancar.sh não existe ou não é executável"; exit 1; }

# base de fixture: um commit só
B="$tmp/base"; mkdir -p "$B/.maestro"
echo "# intent" > "$B/.maestro/INTENT.md"; echo "regras" > "$B/CLAUDE.md"; echo "x: 1" > "$B/.maestro.yaml"
git -C "$B" init -q -b main; git -C "$B" config user.email t@t; git -C "$B" config user.name t
git -C "$B" add -A; git -C "$B" commit -qm base

# políticas de fixture (mesmo formato do docs/experimento/politicas.json)
cat > "$tmp/politicas.json" <<'EOF'
[{"project":"maestro","manager_model_policy":"sonnet","tool_allowlist":"[\"Read\",\"Edit\",\"Write\",\"Grep\",\"Glob\",\"Task\",\"Bash(maestro *)\",\"Bash(./bin/maestro *)\",\"Bash(git *)\",\"Bash(bash tests/*)\",\"Bash(shellcheck *)\",\"mcp__ponte__director_ask\",\"mcp__ponte__director_wait\",\"mcp__ponte__director_report\"]","mcp_allowlist":"[\"ponte\"]","risk_policy":"{\"permission_mode\":\"default\",\"max_turns\":150}"}]
EOF

# claude falso: registra argv e ambiente e devolve um result
cat > "$tmp/claude" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]] && { echo "9.9.9 (Claude Code)"; exit 0; }
# o lançador roda o filho com `env -i`: o destino vem de um arquivo ao lado, não do ambiente
OUT=$(cat "$(dirname "$0")/outdir")
printf '%s\n' "$@" > "$OUT/argv"
printf 'MAESTRO_HOME=%s\nPATH=%s\nHERDR_ENV=%s\nCWD=%s\n' "${MAESTRO_HOME:-}" "${PATH:-}" "${HERDR_ENV:-}" "$PWD" > "$OUT/env"
echo '{"type":"result","num_turns":1,"total_cost_usd":0.01,"usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":4}}'
EOF
chmod +x "$tmp/claude"
FAKE_OUT="$tmp/fake"; mkdir -p "$FAKE_OUT"; printf '%s' "$FAKE_OUT" > "$tmp/outdir"
export HM_CLAUDE_BIN="$tmp/claude"

printf 'ORDEM-INTEIRA\n' > "$tmp/prompt-1.md"
printf 'ORDEM-CORTADA\nRode `bash tests/run-all.sh` e termine quando sair 0.\n' > "$tmp/prompt-2.md"
HERDR_ENV=1 bash "$TOOL" --config 2 --base "$B" --saida "$tmp/s2" --prompt "$tmp/prompt-2.md" --politicas "$tmp/politicas.json" \
  --max-budget-usd 4.00 --recibo "echo recibo-rodou; exit 3" >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "config 2: lançamento com claude falso sai 0" || bad "config 2 saiu $rc"
A2=$(cat "$tmp/s2/argv.txt")
has2() { grep -qxF -- "$1" <<<"$A2"; }
for flag in -p --safe-mode --strict-mcp-config --verbose; do
  has2 "$flag" && ok "config 2: argv tem $flag" || bad "config 2: falta $flag"
done
has2 dontAsk && ok "config 2: --permission-mode dontAsk" || bad "config 2: sem dontAsk"
grep -q '^--allowedTools=' <<<"$A2" && ok "config 2: lista fechada em --allowedTools= (forma com '=', a flag é variadica)" || bad "config 2: sem --allowedTools="
grep -q 'maestro\|mcp__ponte' "$tmp/s2/arquivos/allowlist.json" && bad "config 2: a lista tem item do método" || ok "config 2: a lista fechada não tem maestro nem Ponte"
grep -q '"Bash(git \*)"' "$tmp/s2/arquivos/allowlist.json" && ok "config 2: a lista mantém o núcleo (git, leitura, edição)" || bad "config 2: perdeu o núcleo"
for flag in --append-system-prompt-file --permission-prompt-tool --session-id --settings --dangerously-skip-permissions --bare; do
  has2 "$flag" && bad "config 2: argv tem $flag" || ok "config 2: argv sem $flag"
done
[[ "$(tail -n 1 "$tmp/s2/argv.txt")" == "$(head -n 1 "$tmp/prompt-2.md")" || "$(tail -n 2 "$tmp/s2/argv.txt" | head -n 1)" == "ORDEM-CORTADA" ]] \
  && ok "config 2: o prompt posicional é o prompt-2.md" || bad "config 2: o prompt posicional não é o prompt-2.md"
grep -q '^MAESTRO_HOME=' "$FAKE_OUT/env" && ok "config 2: MAESTRO_HOME definido para o filho" || bad "config 2: sem MAESTRO_HOME"
mh=$(sed -n 's/^MAESTRO_HOME=//p' "$FAKE_OUT/env")
[[ "$mh" != "$HOME/.maestro" && -d "$mh" && -z "$(ls -A "$mh")" ]] && ok "config 2: MAESTRO_HOME é temporário e VAZIO (não o ~/.maestro)" || bad "config 2: MAESTRO_HOME=$mh"
grep -q '^HERDR_ENV=$' "$FAKE_OUT/env" && ok "ambiente do filho montado do zero (HERDR_ENV do shell não vaza)" || bad "HERDR_ENV vazou para o filho"
p2=$(sed -n 's/^PATH=//p' "$FAKE_OUT/env")
[[ ":$p2:" != *":$HOME/.local/bin:"* ]] && ok "config 2: PATH sem o diretório do maestro/ponte-daemon" || bad "config 2: PATH tem $HOME/.local/bin"
[[ "$(sed -n 's/^CWD=//p' "$FAKE_OUT/env")" == "$B" ]] && ok "o claude roda DENTRO da base" || bad "cwd errado"
grep -q '^rc=0$' "$tmp/s2/tempos.txt" && grep -q '^parede_ms=[0-9]*$' "$tmp/s2/tempos.txt" && ok "tempos.txt: spawn, fim, parede em ms e rc" || bad "tempos.txt incompleto"
[[ "$(cat "$tmp/s2/recibo.rc")" == "3" ]] && ok "o recibo da ordem original roda por fora e o rc é gravado (3)" || bad "recibo.rc errado"
grep -q recibo-rodou "$tmp/s2/recibo.log" && ok "recibo.log guarda a saída" || bad "recibo.log vazio"
[[ "$(cat "$tmp/s2/versao.txt")" == "9.9.9 (Claude Code)" && -s "$tmp/s2/uptime.txt" && -s "$tmp/s2/base-tree.txt" ]] && ok "versão, uptime e hash da árvore registrados" || bad "registro de versão/uptime/árvore incompleto"
grep -q -- '--max-budget-usd' <<<"$A2" && has2 4.00 && ok "teto em dólar vai ao claude" || bad "teto em dólar ausente"

# a base ficou limpa? o claude falso não escreve; a segunda corrida na mesma base é aceita
# base suja → recusada
echo sujo > "$B/sujeira.txt"
bash "$TOOL" --config 2 --base "$B" --saida "$tmp/s-suja" --texto x --politicas "$tmp/politicas.json" --dry-run >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "base suja é recusada (rc 2)" || bad "base suja aceita (rc $rc)"
rm -f "$B/sujeira.txt"

# --- config 1: o argv do runner ---
bash "$TOOL" --config 1 --base "$B" --saida "$tmp/s1" --prompt "$tmp/prompt-1.md" --politicas "$tmp/politicas.json" \
  --ponte-bridge /bin/true --ponte-socket /tmp/sock-fixture >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]] && ok "config 1: lançamento com claude falso sai 0" || bad "config 1 saiu $rc"
A1=$(cat "$tmp/s1/argv.txt")
has1() { grep -qxF -- "$1" <<<"$A1"; }
for flag in -p --output-format stream-json --verbose --model sonnet --session-id --mcp-config --strict-mcp-config --settings \
            --permission-mode default --permission-prompt-tool mcp__ponte__permission_prompt --permission-prompts host --max-turns 150 \
            --append-system-prompt-file; do
  has1 "$flag" && ok "config 1: argv tem $flag" || bad "config 1: falta $flag"
done
for proibido in --safe-mode --bare --restricted --continue -c --resume -r --fork-session --dangerously-skip-permissions bypassPermissions dontAsk; do
  has1 "$proibido" && bad "config 1: argv tem o token proibido $proibido" || ok "config 1: argv sem $proibido"
done
grep -q '^--setting-sources' <<<"$A1" && bad "config 1: argv tem --setting-sources" || ok "config 1: argv sem --setting-sources (user/project carregam, como o gerente)"
[[ "$(tail -n 1 "$tmp/s1/argv.txt")" == "Gerente headless do projeto exp-harness-054, ordem order/054-exp-harness. O contexto da ordem está no system prompt. Relate pelo MCP da Ponte (director.report). Você nunca aceita a própria ordem." ]] \
  && ok "config 1: o prompt posicional é o template FIXO do runner, com o project/order_ref de FIXTURE" || bad "config 1: prompt posicional diferente do runner"
jq -e '.mcpServers.ponte | .type=="stdio" and .command=="/bin/true" and .args==["mcp"] and .env.PONTE_MCP_SOCKET=="/tmp/sock-fixture"' "$tmp/s1/arquivos/mcp.json" >/dev/null \
  && ok "config 1: mcp.json = bridge stdio da Ponte" || bad "config 1: mcp.json errado"
jq -e '(.permissions.allow | index("mcp__ponte__director_report")) and (.permissions.allow | index("Bash(maestro *)")) and (.permissions.deny | index("Read(~/.ponte/**)")) and (.permissions.deny | index("mcp__plugin_*")) and .allowedMcpServers==[{"serverName":"ponte"}]' \
  "$tmp/s1/arquivos/settings.json" >/dev/null && ok "config 1: settings = allow REAL do gerente + deny do ST13 + só a Ponte" || bad "config 1: settings errado"
grep -q '^Projeto: exp-harness-054$' "$tmp/s1/arquivos/envelope.md" && ok "config 1: envelope do project de FIXTURE" || bad "config 1: envelope sem o project de fixture"
grep -qF "$tmp/prompt-1.md" "$tmp/s1/arquivos/envelope.md" && ok "config 1: a ordem ativa do envelope aponta para o prompt-1.md" || bad "config 1: envelope não aponta para o prompt-1"
grep -qF "$B" "$tmp/s1/argv.txt" && bad "config 1: o argv cita o caminho da base" || ok "config 1: o argv não carrega caminho da base"
grep -qi 'order/054-reparo\|^Projeto: maestro$' "$tmp/s1/arquivos/envelope.md" "$tmp/s1/argv.txt" && bad "config 1: tocou o project/ordem REAL" || ok "config 1: nem o project 'maestro' nem a 054 real aparecem no envelope/argv"
[[ -z "$(git -C "$B" status --porcelain)" ]] && ok "a base continua limpa depois dos runs (nada escrito na árvore)" || bad "a base ficou suja"

# --- usos inválidos ---
bash "$TOOL" --config 3 --base "$B" --saida "$tmp/x" --texto x >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "--config inválida é recusada (rc 2)" || bad "--config 3 aceita (rc $rc)"
bash "$TOOL" --config 2 --base "$B" --saida "$tmp/x" --texto x --max-budget-usd 4,5 --politicas "$tmp/politicas.json" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "teto em dólar com vírgula é recusado (rc 2)" || bad "teto inválido aceito (rc $rc)"
bash "$TOOL" --config 1 --base "$B" --saida "$tmp/x" --texto x --fixture-order-ref "order/54" --politicas "$tmp/politicas.json" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "order_ref de fixture fora do alfabeto é recusado (rc 2)" || bad "order_ref inválido aceito (rc $rc)"

exit $fail
