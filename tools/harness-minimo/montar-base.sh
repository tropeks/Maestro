#!/usr/bin/env bash
# tools/harness-minimo/montar-base.sh — a BASE SEM FUTURO do experimento (ordem 077).
#
# O repo guarda a solução (`git log --all` a mostra). O executor do run não pode vê-la.
# Esta ferramenta monta, num diretório NOVO: `git archive` do commit `head:` da ordem,
# `git init` e UM único commit. Sem remoto, sem outros refs, sem objetos futuros.
# Cada run começa do mesmo estado byte a byte: o hash da árvore é impresso e conferido
# contra o da árvore do commit de origem (se divergir, a base não serve e sai 1).
#
# Uso: tools/harness-minimo/montar-base.sh <repo-origem> <commit> <destino>
# Saída (stdout): linhas `chave=valor` — tree=<hash> commit=<hash do commit único> destino=<dir>
# Só LÊ o repo de origem; escreve apenas em <destino> (que não pode existir não vazio).
set -u

uso() { echo "uso: montar-base.sh <repo-origem> <commit> <destino>" >&2; exit 2; }
[[ $# -eq 3 ]] || uso
origem="$1"; commit="$2"; destino="$3"

git -C "$origem" rev-parse --git-dir >/dev/null 2>&1 || { echo "montar-base: '$origem' não é repo git" >&2; exit 2; }
alvo=$(git -C "$origem" rev-parse --verify --quiet "${commit}^{commit}") || { echo "montar-base: commit '$commit' não existe em '$origem'" >&2; exit 2; }
arvore_origem=$(git -C "$origem" rev-parse "${alvo}^{tree}")

if [[ -e "$destino" ]] && [[ -n "$(ls -A "$destino" 2>/dev/null)" ]]; then
  echo "montar-base: destino '$destino' existe e não está vazio" >&2; exit 2
fi
mkdir -p "$destino" || { echo "montar-base: não criou '$destino'" >&2; exit 2; }

git -C "$origem" archive --format=tar "$alvo" | tar -x -C "$destino" || { echo "montar-base: git archive falhou" >&2; exit 1; }

# Identidade e data FIXAS: o commit único também é reprodutível entre runs.
export GIT_AUTHOR_NAME=harness-minimo GIT_AUTHOR_EMAIL=harness-minimo@invalid
export GIT_COMMITTER_NAME=harness-minimo GIT_COMMITTER_EMAIL=harness-minimo@invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00+0000" GIT_COMMITTER_DATE="2026-01-01T00:00:00+0000"
git -C "$destino" init -q -b main || exit 1
git -C "$destino" add -A || exit 1
git -C "$destino" -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m "base do experimento (sem futuro)" || exit 1

arvore_base=$(git -C "$destino" rev-parse 'HEAD^{tree}')
if [[ "$arvore_base" != "$arvore_origem" ]]; then
  echo "montar-base: árvore da base ($arvore_base) difere da do commit de origem ($arvore_origem)" >&2
  exit 1
fi
n=$(git -C "$destino" rev-list --all --count)
[[ "$n" == 1 ]] || { echo "montar-base: a base tem $n commits em --all (esperado 1)" >&2; exit 1; }

printf 'tree=%s\ncommit=%s\ndestino=%s\n' "$arvore_base" "$(git -C "$destino" rev-parse HEAD)" "$destino"
