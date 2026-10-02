#!/usr/bin/env bash
# maestro lib/core-tree.sh — ordem 044.
#
# Compara duas árvores de CONTEÚDO ignorando `.maestro/**`.
#
# Por que existe: `bin/maestro-wtree` já deixa `.maestro/**` fora do que o
# recibo prova (issue #6, DATA_MODEL §3 v1.10), mas o faz CONGELANDO essas
# entradas no que estava no index — a árvore do recibo carrega o `.maestro/`
# de QUANDO foi gravada. O tip de um branch (`<br>^{tree}`) carrega o de
# AGORA. Enquanto os dois coincidiam, `==` bastava. Ordem empilhada rompe a
# coincidência: o aceite da anterior commita o carimbo na main, o rebase traz
# o carimbo para dentro do tip, e o recibo — gravado antes — vence por uma
# mudança que a política já diz não ser de conteúdo.
#
# O conserto fica do lado da LEITURA (aqui, em lib/): ambos os lados perdem a
# entrada `.maestro` antes de comparar. Recibos já gravados continuam valendo
# (a árvore deles existe no object store), sem tocar `bin/` (autoproteção).
#
# Convenção da casa: parâmetro posicional, nenhuma função fecha sobre local
# alheio. Sourced no MESMO processo — nenhum fork a mais no caso comum
# (árvores idênticas saem antes de qualquer `git`).

maestro_tree_canon() { # <proj> <árvore> → árvore SEM a entrada `.maestro` (sha), rc 1 se não resolve
  local proj="$1" tree="$2" out
  [[ "$tree" =~ ^[0-9a-f]{40}$ ]] || return 1
  # `ls-tree` + `mktree`: sem index temporário. A entrada tem formato
  # "<modo> <tipo> <sha>\t<nome>"; só o nome EXATO `.maestro` sai.
  out=$(git -C "$proj" ls-tree "$tree" 2>/dev/null) || return 1
  printf '%s\n' "$out" | awk -F'\t' '$2 != ".maestro"' | git -C "$proj" mktree 2>/dev/null
}

maestro_tree_same() { # <proj> <a> <b> → rc 0 se mesmo conteúdo fora de .maestro/**; falha FECHADA (rc 1) se não der para provar
  local proj="$1" a="$2" b="$3" ca cb
  [[ -n "$a" && -n "$b" ]] || return 1
  [[ "$a" == "$b" ]] && return 0          # caminho comum: zero fork
  ca=$(maestro_tree_canon "$proj" "$a") || return 1
  cb=$(maestro_tree_canon "$proj" "$b") || return 1
  [[ -n "$ca" && "$ca" == "$cb" ]]
}
