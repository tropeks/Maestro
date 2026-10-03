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

# shellcheck source=lib/core-order-turno.sh
source "$REPO_DIR/lib/core-order-turno.sh"   # ordem 046: _turno_missing

_conform_headless_re='^[[:space:]]{0,3}(>[[:space:]]*)?(#{1,6}[[:space:]]+)?(\*\*)?Execução headless'

_conform_turno_gaps() { # <id> <arquivo> → lacunas do bloco Turno (ordem 046): order-no-turno / order-no-relatorio
  local id="$1" f="$2" miss
  miss=$(_turno_missing "$f" | tr '\n' ' ')
  [[ "$miss" =~ (fatia|fim|teto|fora) ]] \
    && printf '4\torder-no-turno\tordem %s\tpreencha o bloco "## Turno" (fatia, fim, teto inteiro, fora): rotulos faltando ou invalidos — %s\n' "$id" "$miss"
  [[ "$miss" == *relatório* ]] \
    && printf '4\torder-no-relatorio\tordem %s\tcite o contrato do relatorio de fim de turno no rotulo "relatório:" do bloco "## Turno"\n' "$id"
  return 0
}

_conform_check_orders() { # <proj> → TSV de lacunas da família (d) ordens
  local proj="$1" odir f id wproj st seen=" "
  odir="$proj/.maestro/orders"
  [[ -d "$odir" ]] || return 0
  _order_lib_load
  shopt -s nullglob
  for f in "$odir"/*.md; do
    _order_valid_stamp "$f" || continue   # issue #13: sem carimbo válido não é ordem
    id=$(_order_field "$f" id)
    # ordem 049: dois arquivos com o mesmo id é ERRO (nunca ordem duplicada em silêncio)
    [[ "$seen" == *" $id "* ]] && printf '4\torder-id-duplicado\tordem %s\tdois arquivos com o mesmo id em .maestro/orders/ — renomeie/ajuste um (a numeração por reserva evita a colisão nova)\n' "$id"
    seen+="$id "
    wproj=$(_order_work_project_list_wproj "$proj" "$f")
    st=$(_order_status "$proj" "$wproj" "$f")
    case "$st" in
      aceita|absorvida) continue ;;   # terminal — fora do escopo do conform
    esac
    grep -Eq "$_conform_headless_re" "$f" \
      || printf '4\torder-no-headless\tordem %s\tadicione uma linha "Execução headless" (título, negrito ou blockquote) descrevendo como esta ordem prova SEM humano\n' "$id"
    _conform_turno_gaps "$id" "$f"
  done
  shopt -u nullglob
  return 0
}
