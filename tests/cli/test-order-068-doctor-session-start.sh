#!/usr/bin/env bash
# ordem 068 item 3 — `maestro doctor` e `session-start` acusam cache atrás do repo, em QUALQUER sessão,
# pelo MESMO veredito do núcleo (`maestro plugin-version`): nenhuma segunda comparação.
#   doctor: `warn` com a razão e o conserto ("gire o cache"); repo como raiz viva (CLAUDE_PLUGIN_ROOT = repo) não acusa.
#   session-start: UMA linha no bloco injetado, só quando há defasagem, dentro do orçamento de 8000 bytes.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/tests/lib/env-clean.sh"; maestro_env_clean_inherit
source "$REPO/tests/lib/order-068-fixture.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"
export MAESTRO_NO_UPDATE_CHECK=1 MAESTRO_PLUGINS_DIR="$tmp/plugins-vazio"; mkdir -p "$MAESTRO_PLUGINS_DIR"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

R="$tmp/repo";  mk_root "$R" 1.22.0
U="$tmp/cache"; mk_root "$U" 1.21.0
P="$tmp/proj";  mkdir -p "$P"

# o veredito do núcleo: a razão que os outros dois têm de repetir
nucleo=$(CLAUDE_PLUGIN_ROOT="$U" "$R/bin/maestro" plugin-version 2>&1); nrc=$?
razao="${nucleo#*: }"
[[ "$nrc" == 1 && "$razao" == "cache 1.21.0 < repo 1.22.0" ]] && ok "núcleo: atrás, razão '$razao'" || bad "núcleo: rc=$nrc '$nucleo'"

# --- doctor
dout=$(cd "$P" && CLAUDE_PLUGIN_ROOT="$U" "$R/bin/maestro" doctor 2>&1 || true)
printf '%s\n' "$dout" | grep -E '^warn.*cache 1\.21\.0 < repo 1\.22\.0' >/dev/null && ok "doctor: warn com a razão do núcleo" || bad "doctor sem warn de versão"
[[ "$dout" == *"gire o cache"* ]] && ok "doctor: traz o conserto (gire o cache)" || bad "doctor sem o conserto"

dout=$(cd "$P" && CLAUDE_PLUGIN_ROOT="$R" "$R/bin/maestro" doctor 2>&1 || true)
[[ "$dout" != *"cache 1."* && "$dout" != *"hook defasado"* ]] && ok "doctor: repo como raiz viva não acusa cache atrás" || bad "doctor acusa com o repo como raiz viva"

dout=$(cd "$P" && env -u CLAUDE_PLUGIN_ROOT "$R/bin/maestro" doctor 2>&1 || true)
[[ "$dout" != *"gire o cache"* ]] && ok "doctor: sem CLAUDE_PLUGIN_ROOT (indeterminado) não acusa atraso" || bad "doctor acusa atraso sem ter lido a versão em uso"

# --- session-start
ss() { # <CLAUDE_PLUGIN_ROOT|-> → $sso (stdout), $ssrc
  local root="$1" envs=(CLAUDE_PROJECT_DIR="$P" MAESTRO_REPO_DIR="$R")
  [[ "$root" == - ]] || envs+=(CLAUDE_PLUGIN_ROOT="$root")
  sso=$(printf '{"session_id":"s068"}' | env "${envs[@]}" bash "$REPO/hooks/session-start.sh" 2>/dev/null); ssrc=$?
}
LINHA="⚠ hook defasado: cache 1.21.0 < repo 1.22.0"
ss "$U"
[[ "$ssrc" == 0 ]] && ok "session-start: exit 0 mesmo defasado" || bad "session-start: exit $ssrc"
[[ "$sso" == *"$LINHA"* ]] && ok "session-start: linha de aviso com a razão do núcleo" || bad "session-start sem a linha '$LINHA'"
[[ $(printf '%s\n' "$sso" | grep -c 'hook defasado') == 1 ]] && ok "session-start: uma linha só" || bad "session-start: linha repetida ou ausente"
bytes=$(printf '%s' "$sso" | LC_ALL=C wc -c)
(( bytes <= 8000 )) && ok "session-start: orçamento da injeção segue verde (${bytes} bytes ≤ 8000)" || bad "injeção estourou: ${bytes} bytes"

ss "$R"
[[ "$sso" != *"hook defasado"* ]] && ok "session-start: repo como raiz viva não acusa" || bad "session-start acusa com o repo vivo"
ss -
[[ "$sso" != *"hook defasado"* ]] && ok "session-start: indeterminado não injeta a linha" || bad "session-start acusa sem versão em uso"

# a linha só entra com defasagem: o bloco em dia não ganha byte
ss "$R"; base=$(printf '%s' "$sso" | LC_ALL=C wc -c)
ss "$U"; com=$(printf '%s' "$sso" | LC_ALL=C wc -c)
(( com > base )) && ok "a linha é o único acréscimo (+$((com - base)) bytes só quando defasado)" || bad "sem diferença de bytes entre em dia e defasado"

# kill-switch
sso=$(printf '{"session_id":"s068"}' | env MAESTRO_OFF=1 CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$U" MAESTRO_REPO_DIR="$R" bash "$REPO/hooks/session-start.sh" 2>/dev/null)
[[ "$sso" != *"hook defasado"* ]] && ok "MAESTRO_OFF=1: nada checado" || bad "MAESTRO_OFF=1 acusa"

exit $fail
