#!/usr/bin/env bash
# ordem 068 item 2 — hook defasado nunca roda turno. O `UserPromptSubmit` recusa (exit 2 + motivo no
# stderr) o turno de ordem NÃO ATENDIDO (branch order/NNN-… com .maestro/orders/ e
# CLAUDE_CODE_SESSION_ATTENDED=0) quando o veredito de versão é `atrás` com as duas versões lidas.
# Sessão atendida: só avisa. `indeterminado`, MAESTRO_OFF=1, branch comum: segue como hoje (exit 0).
# Reproduz o incidente da 062 (hook do cache 1.21.0, repo 1.22.0). Raízes de fixture; nunca o cache real.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/tests/lib/env-clean.sh"; maestro_env_clean_inherit
source "$REPO/tests/lib/order-068-fixture.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"
export MAESTRO_NO_UPDATE_CHECK=1

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

MOTIVO='hook defasado: o cache do plugin está em 1.21.0 e o repo em 1.22.0 — o turno não roda com hook antigo; peça o giro do cache ao Capitão'

R="$tmp/repo";  mk_root "$R" 1.22.0
U="$tmp/cache"; mk_root "$U" 1.21.0
P="$tmp/proj";  mk_order_proj "$P"
PC="$tmp/comum"; mk_order_proj "$PC"; git -C "$PC" checkout -q -b feat/comum

hook() { # <proj> <attended|-> [VAR=VAL...] → $rc, $so (stdout), $se (stderr)
  local proj="$1" att="$2"; shift 2
  local ef="$tmp/se"
  local envs=(CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$U" MAESTRO_REPO_DIR="$R")
  [[ "$att" == - ]] || envs+=(CLAUDE_CODE_SESSION_ATTENDED="$att")
  so=$(printf '{"session_id":"s068","prompt":"faca o turno"}' | env "${envs[@]}" "$@" bash "$REPO/hooks/user-prompt-submit.sh" 2>"$ef"); rc=$?
  se=$(cat "$ef")
}

# 1. o incidente da 062: turno de ordem headless, cache 1.21.0, repo 1.22.0 → recusa com o motivo
hook "$P" 0
[[ "$rc" == 2 ]] && ok "062: turno de ordem não atendido, cache atrás → exit 2 (recusa)" || bad "062: exit $rc (esperado 2)"
[[ "$se" == *"$MOTIVO"* ]] && ok "062: motivo no formato do relato fixo, no stderr" || bad "062: motivo ausente em '$se'"
[[ "$so" != *"defasado"* ]] && ok "stdout limpo (não injeta no contexto)" || bad "stdout carrega o motivo"
[[ "$se" != *"$tmp"* ]] && ok "motivo sem caminho completo" || bad "motivo vaza caminho"

# 2. sessão ATENDIDA: nunca recusa (só avisa)
hook "$P" 1
[[ "$rc" == 0 ]] && ok "atendida (ATTENDED=1): exit 0, sem recusa" || bad "atendida: exit $rc (esperado 0)"

# 3. sinal de 'não atendido' ausente ou duvidoso: não recusa
hook "$P" -
[[ "$rc" == 0 ]] && ok "sinal ATTENDED ausente: não recusa" || bad "ATTENDED ausente: exit $rc"
hook "$P" talvez
[[ "$rc" == 0 ]] && ok "sinal ATTENDED duvidoso: não recusa" || bad "ATTENDED duvidoso: exit $rc"

# 4. indeterminado → segue como hoje
U2="$tmp/cache-sem-json"; mk_root "$U2" -
so=$(printf '{"session_id":"s068","prompt":"x"}' | env CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$U2" MAESTRO_REPO_DIR="$R" CLAUDE_CODE_SESSION_ATTENDED=0 bash "$REPO/hooks/user-prompt-submit.sh" 2>/dev/null); rc=$?
[[ "$rc" == 0 ]] && ok "indeterminado (plugin.json do cache ausente): não recusa" || bad "indeterminado: exit $rc"
so=$(printf '{"session_id":"s068","prompt":"x"}' | env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$P" MAESTRO_REPO_DIR="$R" CLAUDE_CODE_SESSION_ATTENDED=0 bash "$REPO/hooks/user-prompt-submit.sh" 2>/dev/null); rc=$?
[[ "$rc" == 0 ]] && ok "indeterminado (CLAUDE_PLUGIN_ROOT indefinido): não recusa" || bad "sem CLAUDE_PLUGIN_ROOT: exit $rc"

# 5. kill-switch
hook "$P" 0 MAESTRO_OFF=1
[[ "$rc" == 0 && -z "$se" ]] && ok "MAESTRO_OFF=1: sai na primeira linha, nada checado" || bad "MAESTRO_OFF=1: exit $rc se='$se'"

# 6. branch comum (não é turno de ordem), mesmo defasado e não atendido: não recusa
hook "$PC" 0
[[ "$rc" == 0 ]] && ok "branch fora de order/NNN-: não recusa" || bad "branch comum: exit $rc"

# 7. cache em dia ou maior que o repo: não recusa
U3="$tmp/cache-novo"; mk_root "$U3" 1.22.0
so=$(printf '{"session_id":"s068","prompt":"x"}' | env CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$U3" MAESTRO_REPO_DIR="$R" CLAUDE_CODE_SESSION_ATTENDED=0 bash "$REPO/hooks/user-prompt-submit.sh" 2>/dev/null); rc=$?
[[ "$rc" == 0 ]] && ok "cache = repo: não recusa" || bad "cache em dia: exit $rc"

exit $fail
