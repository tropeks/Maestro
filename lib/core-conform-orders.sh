#!/usr/bin/env bash
# maestro lib/core-conform-orders.sh — ordem 042, família (d) de `maestro conform --check`.
#
# NÃO recalcula estado de ordem: usa `_order_valid_stamp`/`_order_field`/
# `_order_status`/`_order_work_project_list_wproj` de lib/core-order-state.sh
# (via `_order_lib_load`, bin/maestro I-2) — a MESMA derivação que
# `maestro order --status N --json` usa. Terminal = `aceita`|`absorvida`
# (core-order-state.sh: `adiada` é explicitamente NÃO terminal — suspensa,
# não encerrada). Este módulo só decide se a ordem não-terminal tem a linha
# de execução headless (convenção das ordens 022–024 do vitali): começa por
# "Execução headless", em título (`#`), em negrito (`**`) ou dentro de
# blockquote (`> **Execução headless`), com qualquer combinação das três.
#
# Sourced por lib/cmd-conform.sh — REPO_DIR/die() já no escopo (bin/maestro).

_conform_headless_re='^[[:space:]]{0,3}(>[[:space:]]*)?(#{1,6}[[:space:]]+)?(\*\*)?Execução headless'

_conform_check_orders() { # <proj> → TSV de lacunas da família (d) ordens
  local proj="$1" odir f id wproj st
  odir="$proj/.maestro/orders"
  [[ -d "$odir" ]] || return 0
  _order_lib_load
  shopt -s nullglob
  for f in "$odir"/*.md; do
    _order_valid_stamp "$f" || continue   # issue #13: sem carimbo válido não é ordem
    id=$(_order_field "$f" id)
    wproj=$(_order_work_project_list_wproj "$proj" "$f")
    st=$(_order_status "$proj" "$wproj" "$f")
    case "$st" in
      aceita|absorvida) continue ;;   # terminal — fora do escopo do conform
    esac
    grep -Eq "$_conform_headless_re" "$f" && continue
    printf '4\torder-no-headless\tordem %s\tadicione uma linha "Execução headless" (título, negrito ou blockquote) descrevendo como esta ordem prova SEM humano\n' "$id"
  done
  shopt -u nullglob
  return 0
}
