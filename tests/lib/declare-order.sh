#!/usr/bin/env bash
# ordem 078 — ajudante dos testes que gravam recibo `order-N`: o `evidence --record` só executa o comando
# declarado entre crases no `fim:` da ordem, lido do commit-base (fim_commit, gravado por `order --baseline`).
# Quem faz `source` já definiu BIN (bin/maestro sob teste) e MAESTRO_HOME exportado.
#
#   declare_order <projeto> <N> <comando>...   cada argumento é UM comando declarado (ex.: 'true' 'bash tests/run-all.sh')
#
# Escreve (ou reescreve) o `fim:` do bloco ## Turno da ordem N, commita o arquivo da ordem (só .maestro/) no
# branch corrente e grava o baseline. Chame DEPOIS de `order --create` e ANTES do primeiro `--record`.

declare_order() {
  local proj="$1" n="$2" f cmds="" c
  shift 2
  for c in "$@"; do cmds+="\`$c\` "; done
  f=$(ls "$proj/.maestro/orders/$(printf '%03d' "$((10#$n))")"-*.md | head -1)
  if grep -q '^- fim:' "$f"; then
    FIMV="$cmds" awk '/^- fim:/ { print "- fim: " ENVIRON["FIMV"]; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    printf '\n## Turno\n- fatia: t\n- fim: %s\n- teto: 1\n- fora: nada\n- relatório: v54\n' "$cmds" >> "$f"
  fi
  git -C "$proj" add -A .maestro
  git -C "$proj" -c user.email=t@t -c user.name=t commit -qm "declara o fim: da ordem $n" 2>/dev/null || :
  "$BIN" order --baseline "$n" --project "$proj" >/dev/null
}
