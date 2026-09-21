#!/usr/bin/env bash
# ordem 036 (DATA_MODEL §9 v1.22) — T3 do desenho (§8): O TESTE DO HOMÔNIMO
# (M2). Repos A (dono) e B (trabalho) com branches de MESMO NOME e árvores
# DIFERENTES, recibo válido só no ledger de B — a ordem em A com
# `work_project: B` deriva provada; a MESMA ordem SEM o campo deriva
# em_execucao (a inferência erraria: o branch homônimo do dono não tem o
# recibo). Reproduz em miniatura o caso REAL medido na 033 do Maestro/
# ponte-daemon (M2 do desenho): `order/033-director-report-project` existe
# nos DOIS repos, árvores `88dc74a3` (Maestro) e `65e38fc7` (ponte-daemon).
#
# Mesmo padrão PENDENTE/reprova-de-verdade das ordens 003/004A/013/017/021/022.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

CORE_PATCHED=0
if [[ -f "$REPO/lib/core-order-workproject.sh" ]] && grep -qF '_order_work_project' "$REPO/lib/core-order-workproject.sh" 2>/dev/null; then
  CORE_PATCHED=1
fi
if (( CORE_PATCHED == 0 )); then
  pending "ordem 036: work_project ainda ausente; aplicar os patches em docs/patches/036-*.patch"
  exit 0
fi

git_id() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }
git_init_main() { local d="$1"; git -C "$d" init -q; git -C "$d" symbolic-ref HEAD refs/heads/main; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
export MAESTRO_WORK_ROOT="$tmp/work"
mkdir -p "$MAESTRO_WORK_ROOT"

A="$tmp/dono"; B="$MAESTRO_WORK_ROOT/trabalho"
mkdir -p "$A" "$B"
git_init_main "$A"; echo a > "$A/f.txt"; git_id "$A" add f.txt; git_id "$A" commit -qm base
git_init_main "$B"; echo b > "$B/g.txt"; git_id "$B" add g.txt; git_id "$B" commit -qm base

BR="order/1-homonimo"
"$BIN" order --create --title "T3 homonimo" --branch "$BR" --project "$A" --session t3 --work-project trabalho <<'BODY' >/dev/null
## Objetivo
T3 do desenho: o teste do homônimo (M2).
BODY

# branch HOMÔNIMO nos DOIS repos, ÁRVORES DIFERENTES — exatamente o caso da
# 033 (Maestro: 88dc74a3 · ponte-daemon: 65e38fc7, branches homônimos reais).
git_id "$A" branch "$BR"   # o Maestro só versiona o .md — árvore de A (errada p/ prova)
git_id "$B" checkout -qb "$BR"
echo trabalho-de-verdade >> "$B/g.txt"; git_id "$B" add g.txt; git_id "$B" commit -qm "o trabalho de verdade vive aqui"

TREE_A=$(git -C "$A" rev-parse "$BR^{tree}")
TREE_B=$(git -C "$B" rev-parse "$BR^{tree}")
[[ "$TREE_A" != "$TREE_B" ]] && ok "(T3) fixture: árvores do branch homônimo são DIFERENTES em A e B" \
  || bad "(T3) fixture quebrada: árvores iguais, o teste não prova nada"

D8=$(REPO_DIR="$REPO" bash -c 'source "'"$REPO"'/hooks/lib/common.sh"; source "'"$REPO"'/lib/core-order-state.sh" 2>/dev/null; _order_dono8 "'"$A"'"')
# recibo válido SÓ no ledger de B (o repo do TRABALHO) — nada gravado em A.
"$BIN" evidence --record --label "order-1-$D8" --project "$B" -- true >/dev/null

ST_COM_WP=$("$BIN" order --status 1 --project "$A" 2>&1 | head -1)
[[ "$ST_COM_WP" == "ordem 001: provada" ]] \
  && ok "(T3) COM work_project: deriva provada (ancorada na árvore de B, o repo certo)" \
  || bad "(T3) COM work_project esperava provada, obtido: $ST_COM_WP"

# a MESMA ordem, SEM o campo (removido do cabeçalho) — a inferência erraria
# (o branch homônimo de A não tem recibo nenhum; sem o campo, --status só
# pode olhar para A).
OF=$(ls "$A"/.maestro/orders/001-*.md)
sed -i '/^work_project:/d' "$OF"
ST_SEM_WP=$("$BIN" order --status 1 --project "$A" 2>&1 | head -1)
[[ "$ST_SEM_WP" == "ordem 001: em_execucao" ]] \
  && ok "(T3) SEM work_project: deriva em_execucao (o campo é o que desambigua; sem ele, o branch homônimo de A não prova nada)" \
  || bad "(T3) SEM work_project esperava em_execucao, obtido: $ST_SEM_WP"

if (( fail == 0 )); then echo "SUITE test-order-036-t3-homonimo.sh: OK"; else echo "SUITE test-order-036-t3-homonimo.sh: FALHAS" >&2; fi
exit $fail
