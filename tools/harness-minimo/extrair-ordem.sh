#!/usr/bin/env bash
# tools/harness-minimo/extrair-ordem.sh — tira o texto de uma ordem JÁ ACEITA do git (ordem 077).
# A ordem original vive num commit posterior ao `head:` dela; a base sem futuro não a tem, então o
# texto sai daqui para um arquivo FORA da árvore da base e alimenta `texto-da-ordem`.
# Só LÊ o repo. Uso: extrair-ordem.sh <repo> <commit-da-ordem> <caminho-da-ordem-no-commit> <arquivo-de-saida>
set -u
[[ $# -eq 4 ]] || { echo "uso: extrair-ordem.sh <repo> <commit> <caminho> <saida>" >&2; exit 2; }
repo="$1"; commit="$2"; caminho="$3"; saida="$4"
git -C "$repo" cat-file -e "${commit}:${caminho}" 2>/dev/null || { echo "extrair-ordem: '${commit}:${caminho}' não existe" >&2; exit 2; }
mkdir -p "$(dirname "$saida")" || exit 2
git -C "$repo" show "${commit}:${caminho}" > "$saida" || exit 1
