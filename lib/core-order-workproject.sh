#!/usr/bin/env bash
# maestro lib/core-order-workproject.sh — ordem 036 (DATA_MODEL §9 v1.22),
# extraído de lib/core-order-state.sh para não cruzar o teto de
# `oversized-file` (400 linhas) — mesmo motivo medido das extrações da
# ordem 014/022 (lib/cmd-order-json.sh/lib/cmd-order-accept.sh): grupo de
# funções que só conversa entre si (probe/resolve do campo `work_project`),
# coeso o bastante pra ter arquivo próprio.
#
# Sourced por lib/core-order-state.sh (`_order_workproject_lib_load`, molde
# de `_order_json_lib_load`/I-2, mas carregado NA HORA — não sob demanda de
# uma flag do CLI, porque `_order_status`/`_order_evidence_*` usam estas
# funções em QUASE todo predicado do núcleo). `bin/maestro` (congelado nesta
# ordem) não ganha linha nenhuma: quem carrega este módulo é o PRÓPRIO
# core-order-state.sh, não o CLI.
#
# `dono`/`wproj` (ordem 036): R1 (repo git) e R2 (chave do ledger) passam a
# ser o projeto do TRABALHO quando `work_project:` existe no cabeçalho; R3
# (arquivo/carimbo/order-state/INTENT/doc) continua SEMPRE o projeto DONO.
# `_order_work_project` é a fronteira de resolução — chamada por `cmd_order`
# DEPOIS de `_order_resolve_stamped`, ANTES de qualquer emissão (I5: morrer
# aqui nunca deixa stdout pela metade).

_order_work_project_re='^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$'

_order_dono8() { # <proj-dono> → 8 hex do djb2 (MESMA chave de maestro_brief_file/maestro_evidence_file), no stdout
  local bf; bf=$(maestro_brief_file "$1")
  local base="${bf##*/}"; base="${base%.md}"
  printf '%s' "${base##*-}"
}
_order_work_project_probe_value() { # <proj-dono> <valor-cru> → "TAG [resto]" no stdout; NUNCA morre, NUNCA depende do $PWD
  # TAG ∈ AUSENTE | OK <dir> | FORMA <valor> | NORESOLVE <valor> <root> | PROPRIO <dir>
  # Usado por --create (valor ainda não está em nenhum arquivo) e por
  # _order_work_project_probe (abaixo, lê o valor do cabeçalho).
  local dono="$1" val="$2" root real dir dono_real dir_real
  [[ -n "$val" ]] || { printf 'AUSENTE'; return 0; }
  [[ "$val" =~ $_order_work_project_re ]] || { printf 'FORMA %s' "$val"; return 0; }
  if [[ -n "${MAESTRO_WORK_ROOT:-}" ]]; then
    root="$MAESTRO_WORK_ROOT"
  else
    # irmão do DONO — NUNCA relativo ao $PWD (o daemon chama com cwd dele, um
    # humano chama de onde estiver; as duas respostas têm de ser a mesma).
    real=$(cd -P -- "$dono" 2>/dev/null && pwd) || real="$dono"
    root=$(dirname -- "$real")
  fi
  dir="$root/$val"
  git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1 || { printf 'NORESOLVE %s %s' "$val" "$root"; return 0; }
  dono_real=$(cd -P -- "$dono" 2>/dev/null && pwd) || dono_real="$dono"
  dir_real=$(cd -P -- "$dir" 2>/dev/null && pwd) || dir_real="$dir"
  [[ "$dir_real" == "$dono_real" ]] && { printf 'PROPRIO %s' "$dir"; return 0; }
  printf 'OK %s' "$dir"
}
_order_work_project_probe() { # <proj-dono> <arquivo> → mesma saída de _order_work_project_probe_value, valor lido do CABEÇALHO
  _order_work_project_probe_value "$1" "$(_order_field "$2" work_project)"
}
_order_work_project() { # <proj-dono> <arquivo> → <wproj> no stdout; die validation (rc 1) se forma inválida ou não resolve
  # Fronteira de resolução (cmd_order, DEPOIS de _order_resolve_stamped,
  # ANTES de qualquer emissão — I4/I5 do desenho): AUSENTE e PROPRIO (typo —
  # aponta pro próprio dono) são tratados como ausente, sem morrer; forma
  # inválida ou caminho que não resolve para repo git morrem aqui, cedo,
  # nunca no meio de um JSON.
  local dono="$1" f="$2" probe tag rest
  probe=$(_order_work_project_probe "$dono" "$f")
  tag="${probe%% *}"; rest="${probe#* }"
  case "$tag" in
    AUSENTE|PROPRIO) printf '%s' "$dono"; return 0 ;;
    OK)              printf '%s' "$rest"; return 0 ;;
    FORMA)
      die validation "work_project \"$rest\" tem forma inválida (esperado ${_order_work_project_re}, sem '/')" \
        "corrija o campo work_project no cabeçalho da ordem" 1 ;;
    NORESOLVE)
      die validation "work_project \"${rest%% *}\" não resolve para um repositório git em ${rest#* }" \
        "confira MAESTRO_WORK_ROOT ou o layout de diretórios irmãos (dirname do dono)" 1 ;;
  esac
}
_order_work_project_note() { # <proj-dono> <arquivo> → nota textual se work_project resolve pro PRÓPRIO dono (typo); vazio senão
  local dono="$1" f="$2" probe tag val
  probe=$(_order_work_project_probe "$dono" "$f")
  tag="${probe%% *}"
  [[ "$tag" == "PROPRIO" ]] || return 0
  val=$(_order_field "$f" work_project)
  printf 'work_project "%s" resolve para o próprio projeto dono — tratado como ausente' "$val"
}
_order_work_project_list_wproj() { # <proj-dono> <arquivo> → wproj a usar no --list; NUNCA morre (FORMA/NORESOLVE cai para o dono; a marca abaixo já avisa)
  local probe tag rest
  probe=$(_order_work_project_probe "$1" "$2")
  tag="${probe%% *}"; rest="${probe#* }"
  [[ "$tag" == "OK" ]] && { printf '%s' "$rest"; return 0; }
  printf '%s' "$1"
}
_order_work_project_list_mark() { # <proj-dono> <arquivo> → "[?] motivo" se work_project FORMA/NORESOLVE; vazio senão (--list NUNCA morre)
  local probe tag rest
  probe=$(_order_work_project_probe "$1" "$2")
  tag="${probe%% *}"; rest="${probe#* }"
  case "$tag" in
    FORMA)     printf '[?] work_project "%s": forma inválida' "$rest" ;;
    NORESOLVE) printf '[?] work_project "%s": não resolve para repositório git' "${rest%% *}" ;;
  esac
  return 0
}
