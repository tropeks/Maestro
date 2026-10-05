#!/usr/bin/env bash
# tests/lib/order-068-fixture.sh — fixtures da ordem 068 (hook defasado nunca roda turno).
# Sourceável; o nome não casa `test-*.sh`, então o run-all não o enumera como teste.
#
# Raízes de FIXTURE, nunca o cache real (~/.claude/plugins). `mk_root <dir> <versão>`
# copia o Maestro sob teste (REPO) para <dir> e fixa o `version` do plugin.json:
#   - a raiz "em uso" simula o cache do plugin (CLAUDE_PLUGIN_ROOT);
#   - a raiz "repo" simula o checkout do Maestro de onde o CLI roda.
# Requer: REPO (raiz do Maestro sob teste) já definido.

mk_root() { # mk_root <dir> <versão|-> — versão "-" = plugin.json ausente
  local d="$1" v="$2" x
  mkdir -p "$d/.claude-plugin"
  for x in bin lib hooks config agents; do cp -r "$REPO/$x" "$d/$x"; done
  if [[ "$v" != "-" ]]; then
    printf '{\n  "name": "maestro",\n  "version": "%s",\n  "description": "fixture"\n}\n' "$v" > "$d/.claude-plugin/plugin.json"
  fi
}

# mk_order_proj <dir> — projeto git no branch order/068-x com ordem em .maestro/orders/
mk_order_proj() {
  local p="$1"
  mkdir -p "$p/.maestro/orders"
  git -C "$p" init -q -b main
  git -C "$p" config user.email t@t; git -C "$p" config user.name t
  printf '# ordem 068\n\n## Turno\n- fatia: x\n- fim: y\n- teto: 1\n- fora: z\n- relatório: w\n' > "$p/.maestro/orders/068-x.md"
  echo a > "$p/a"; git -C "$p" add -A; git -C "$p" commit -qm base
  git -C "$p" checkout -q -b order/068-x
}
