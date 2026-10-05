#!/usr/bin/env bash
# ordem 066 (2) — a prova central: o perfil `pesquisa` NUNCA toca o socket da Ponte.
#   fixture: servidor Unix em diretório temporário que REGISTRA cada conexão; HOME e
#   PONTE_MCP_SOCKET do teste apontam para ela (o ~/.ponte real jamais é tocado).
#   vermelho: o provedor do jeito de hoje (sem perfil), com a Ponte configurada → CONECTA.
#   verde:    `maestro agente --perfil pesquisa` → NENHUMA conexão.
#   controle: `gerente` conecta (a Ponte carrega onde deve); `diretor` declara a Ponte
#             por --mcp-config (o `mcp list` ignora essa flag: conexão real = NAO VERIFICADO).
#   medição sem modelo e sem rede: `claude mcp list` (sonda os servidores).
#   sem `claude` instalado a camada real vira NAO VERIFICADO explícito, nunca verde.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
srvpid=''
trap '[[ -n "$srvpid" ]] && kill "$srvpid" 2>/dev/null; rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
nv()  { printf 'NAO VERIFICADO %s\n' "$1"; }

# --- fixture: HOME falso, socket falso, ponte-daemon falso; nada do ambiente real
export HOME="$tmp/home"; mkdir -p "$HOME" "$tmp/cwd" "$tmp/bin"
export MAESTRO_HOME="$HOME/.maestro-home"
SOCK="$tmp/ponte.sock"; LOG="$tmp/conexoes.log"; : > "$LOG"
export PONTE_MCP_SOCKET="$SOCK"
cfg=$(<"$REPO/tests/fixtures/066-claude-home.json")
printf '%s\n' "${cfg//@SOCK@/$SOCK}" > "$HOME/.claude.json"
ln -s "$REPO/tests/lib/ponte-daemon-stub.sh" "$tmp/bin/ponte-daemon"
export PATH="$tmp/bin:$PATH"

python3 "$REPO/tests/lib/ponte-socket-fixture.py" "$SOCK" "$LOG" >"$tmp/srv.out" 2>&1 &
srvpid=$!
for _ in $(seq 1 50); do grep -q pronto "$tmp/srv.out" 2>/dev/null && break; sleep 0.1; done
grep -q pronto "$tmp/srv.out" && ok "fixture do socket de pé (tmp, nunca ~/.ponte)" || { bad "fixture não subiu"; exit 1; }
[[ "$SOCK" == "$tmp"/* && "$HOME" == "$tmp"/* ]] && ok "HOME e socket sob o diretório temporário" || bad "HOME/socket fora do tmp"

conexoes() { wc -l < "$LOG" | tr -d ' '; }
# roda <cmd...> no cwd temporário e devolve quantas conexões novas chegaram ao socket
# (o rc do comando medido fica em $tmp/rc: ausência de conexão só vale se o comando RODOU, rc 0)
delta() { local antes depois; antes=$(conexoes); ( cd "$tmp/cwd" && "$@" >"$tmp/saida.txt" 2>&1; echo $? > "$tmp/rc" ); sleep 0.3; depois=$(conexoes); echo $((depois - antes)); }

if ! command -v claude >/dev/null 2>&1; then
  nv "camada real: 'claude' não está instalado neste ambiente — nenhuma conexão foi medida"
  # a camada do núcleo roda sempre: pesquisa não declara a Ponte
  out=$("$BIN" agente --perfil pesquisa --dry-run -- mcp list 2>&1)
  grep -q 'ponte=nao' <<<"$out" && ok "dry-run: pesquisa declara ponte=nao" || bad "dry-run de pesquisa sem ponte=nao ($out)"
  exit $fail
fi

# --- VERMELHO antes: do jeito de hoje (sem perfil) a Ponte conecta — o incidente reproduzido
n=$(delta claude mcp list)
[[ "$n" -ge 1 ]] && ok "vermelho/controle: sem perfil, claude mcp list CONECTOU na Ponte ($n conexão)" || bad "sem perfil NÃO conectou — a fixture não reproduz o incidente ($(cat "$tmp/saida.txt"))"

# --- VERDE: pesquisa não conecta
n=$(delta "$BIN" agente --perfil pesquisa -- mcp list)
[[ "$(cat "$tmp/rc")" == "0" ]] && ok "pesquisa: o lançador rodou o provedor (rc 0)" || bad "pesquisa: o lançador não rodou ($(head -3 "$tmp/saida.txt"))"
[[ "$n" -eq 0 && "$(cat "$tmp/rc")" == "0" ]] && ok "pesquisa: ZERO conexões no socket da Ponte" || bad "pesquisa CONECTOU na Ponte, ou não rodou ($n conexão; $(head -3 "$tmp/saida.txt"))"
grep -q 'No MCP servers configured' "$tmp/saida.txt" && ok "pesquisa: o mcp list não enxerga servidor algum" || bad "pesquisa: mcp list enxerga servidor: $(head -3 "$tmp/saida.txt")"

# --- controles: onde a Ponte deve carregar
n=$(delta "$BIN" agente --perfil gerente -- mcp list)
[[ "$n" -ge 1 ]] && ok "controle: gerente CONECTA na Ponte ($n)" || bad "controle: gerente não conectou ($(head -3 "$tmp/saida.txt"))"
n=$(delta "$BIN" agente --perfil dev -- mcp list)
[[ "$n" -ge 1 ]] && ok "controle: dev (envelope) não esconde a Ponte ($n)" || bad "controle: dev não conectou ($(head -3 "$tmp/saida.txt"))"

# diretor: a Ponte vem por --mcp-config (independente do plugin); `mcp list` ignora essa flag
out=$("$BIN" agente --perfil diretor --dry-run -- mcp list 2>&1)
grep -q 'mcp-config' <<<"$out" && grep -q 'ponte-daemon' <<<"$out" && grep -q 'PONTE_MCP_SOCKET' <<<"$out" \
  && ok "diretor: dry-run declara a Ponte por --mcp-config (sem depender do plugin)" || bad "diretor: dry-run sem a Ponte declarada ($out)"
nv "diretor: a CONEXÃO real da Ponte via --mcp-config não é medível sem modelo (mcp list ignora --mcp-config)"
nv "sessão real (claude -p) de qualquer perfil: fora do escopo sem modelo; só mcp list/config"

exit $fail
