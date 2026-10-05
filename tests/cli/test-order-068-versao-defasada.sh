#!/usr/bin/env bash
# ordem 068 item 1 — o NÚCLEO: `maestro plugin-version` devolve o veredito de versão do plugin EM USO
# (CLAUDE_PLUGIN_ROOT) contra o repo do Maestro de onde o CLI roda (REPO_DIR). Uma função, um veredito:
#   exit 0 = ok · exit 1 = atrás · exit 2 = indeterminado; a razão legível vai no stdout.
# Semver por inteiros; só é `atrás` com as DUAS versões lidas e a em uso MENOR; falha de leitura é
# `indeterminado`, nunca `atrás`. Raízes de fixture — nunca o cache real.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/tests/lib/env-clean.sh"; maestro_env_clean_inherit
source "$REPO/tests/lib/order-068-fixture.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

n=0
caso() { # <rótulo> <versão em uso|-|sem-env|json-ruim> <versão repo> <exit esperado> <palavra> [razão esperada]
  local rot="$1" uso="$2" rep="$3" want="$4" word="$5" razao="${6:-}" out rc
  n=$((n + 1))
  local R="$tmp/repo$n" U="$tmp/uso$n"
  mk_root "$R" "$rep"
  case "$uso" in
    sem-env)   out=$(env -u CLAUDE_PLUGIN_ROOT "$R/bin/maestro" plugin-version 2>&1); rc=$? ;;
    json-ruim) mk_root "$U" 1.0.0; printf '{ "version": \n' > "$U/.claude-plugin/plugin.json"
               out=$(CLAUDE_PLUGIN_ROOT="$U" "$R/bin/maestro" plugin-version 2>&1); rc=$? ;;
    *)         mk_root "$U" "$uso"
               out=$(CLAUDE_PLUGIN_ROOT="$U" "$R/bin/maestro" plugin-version 2>&1); rc=$? ;;
  esac
  [[ "$rc" == "$want" ]] && ok "$rot: exit $rc" || bad "$rot: exit $rc (esperado $want) — $out"
  [[ "$out" == "$word"* ]] && ok "$rot: veredito '$word'" || bad "$rot: saída '$out' não começa com '$word'"
  [[ -z "$razao" || "$out" == *"$razao"* ]] && ok "$rot: razão legível" || bad "$rot: sem a razão '$razao' em '$out'"
}

caso "uso 1.21.0 < repo 1.22.0"        1.21.0 1.22.0 1 'atrás'         'cache 1.21.0 < repo 1.22.0'
caso "iguais"                          1.22.0 1.22.0 0 'ok'
caso "uso maior que o repo"            1.23.0 1.22.0 0 'ok'
caso "inteiros, não texto: 1.9.0 < 1.10.0"  1.9.0 1.10.0 1 'atrás'     'cache 1.9.0 < repo 1.10.0'
caso "inteiros: 1.10.0 não é atrás de 1.9.0" 1.10.0 1.9.0 0 'ok'
caso "patch: 1.22.0 < 1.22.1"          1.22.0 1.22.1 1 'atrás'
caso "major: 2.0.0 > 1.99.99"          2.0.0 1.99.99 0 'ok'
caso "plugin.json do uso ausente"      -      1.22.0 2 'indeterminado'
caso "JSON do uso ilegível"            json-ruim 1.22.0 2 'indeterminado'
caso "CLAUDE_PLUGIN_ROOT indefinido"   sem-env 1.22.0 2 'indeterminado'
caso "repo sem plugin.json"            1.21.0 -      2 'indeterminado'
caso "versão fora de major.minor.patch" 1.x.0 1.22.0 2 'indeterminado'

# só metadados: a saída não carrega caminho completo
R="$tmp/repo-path"; U="$tmp/uso-path"; mk_root "$R" 1.22.0; mk_root "$U" 1.21.0
out=$(CLAUDE_PLUGIN_ROOT="$U" "$R/bin/maestro" plugin-version 2>&1)
[[ "$out" != *"$tmp"* ]] && ok "saída sem caminho completo" || bad "saída vaza caminho: $out"

# o doctor acusa pela mesma razão do núcleo
out=$(cd "$tmp" && CLAUDE_PLUGIN_ROOT="$U" "$R/bin/maestro" doctor 2>&1 || true)
[[ "$out" == *"cache 1.21.0 < repo 1.22.0"* ]] && ok "doctor acusa versão (mesma razão do núcleo)" || bad "doctor não acusa 'cache 1.21.0 < repo 1.22.0'"

exit $fail
