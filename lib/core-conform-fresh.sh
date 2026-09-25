#!/usr/bin/env bash
# maestro lib/core-conform-fresh.sh — ordem 042, família (c) de `maestro conform --check`.
#
# Frescor: o `ts:` do brief, o último commit do README e o de cada doc
# listado em `docs:` do `.maestro.yaml` não podem ser ANTERIORES ao `ts:` do
# cabeçalho do INTENT — a direção andou e o artefato ficou para trás.
# Reusa `maestro_brief_file` (hooks/lib/project-state.sh, via
# hooks/lib/common.sh) para o caminho do brief e `_docs_declared_list`
# (lib/cmd-docs.sh, via `_docs_lib_load`) para a lista de docs — nenhum dos
# dois é recalculado aqui.
#
# Sem `ts:` de INTENT legível, a comparação não tem contra o quê existir:
# family (a) já cobre `intent-missing`/`intent-sections`, e repetir o aviso
# aqui seria ruído. `brief-missing` é a única checagem desta família que NÃO
# depende do INTENT (é só existência) — continua valendo mesmo sem direção.

_conform_iso_epoch() { # <iso8601> → epoch, ou vazio se ilegível
  local ts="${1:-}" e
  [[ -n "$ts" ]] || { printf ''; return 0; }
  e=$(date -d "$ts" +%s 2>/dev/null) || e=""
  [[ "$e" =~ ^[0-9]+$ ]] && printf '%s' "$e"
  return 0
}

_conform_readme_path() { # <proj> → caminho do README (relativo), vazio se nenhum
  local proj="$1" f
  f=$(find "$proj" -maxdepth 1 -type f -iname 'README*' 2>/dev/null | sort | head -1) || f=""
  [[ -n "$f" ]] && printf '%s' "${f#"$proj"/}"
  return 0
}

_conform_check_fresh() { # <proj> → TSV de lacunas da família (c) frescor
  local proj="$1" bf f

  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  bf=$(maestro_brief_file "$proj")
  if [[ ! -f "$bf" ]]; then
    printf '3\tbrief-missing\tbrief\trode "maestro brief --write" (ou --auto) para o projeto\n'
  fi

  _intent_lib_load
  f=$(_intent_file "$proj")
  local iv_ts iv_epoch
  iv_ts=$(_intent_stamp_field "$f" ts)
  iv_epoch=$(_conform_iso_epoch "$iv_ts")
  [[ -n "$iv_epoch" ]] || return 0   # sem direção legível, nada a comparar (family a já cobriu)

  if [[ -f "$bf" ]]; then
    local b_epoch
    b_epoch=$(awk '/^epoch: / { v=substr($0,8); if (v ~ /^[0-9]+$/) print v; exit }' "$bf" 2>/dev/null)
    if [[ "$b_epoch" =~ ^[0-9]+$ ]] && (( b_epoch < iv_epoch )); then
      printf '3\tbrief-stale\tbrief\tregrave com "maestro brief --write" (ou --auto) — direção andou depois do brief\n'
    fi
  fi

  if git -C "$proj" rev-parse --git-dir >/dev/null 2>&1; then
    local rp rc
    rp=$(_conform_readme_path "$proj")
    if [[ -n "$rp" ]]; then
      rc=$(git -C "$proj" log -1 --format=%ct -- "$rp" 2>/dev/null)
      [[ "$rc" =~ ^[0-9]+$ ]] && (( rc < iv_epoch )) \
        && printf '3\treadme-stale\t%s\tatualize o README (ou re-carimbe com "maestro intent --bump" após revisar)\n' "$rp"
    fi

    _docs_lib_load
    local dlist d dc
    dlist=$(_docs_declared_list "$proj")
    for d in $dlist; do
      if [[ ! -f "$proj/$d" ]]; then
        printf '3\tdoc-stale\t%s\tdoc declarado em docs: não existe — crie %s ou remova a entrada do .maestro.yaml\n' "$d" "$d"
        continue
      fi
      dc=$(git -C "$proj" log -1 --format=%ct -- "$d" 2>/dev/null)
      [[ "$dc" =~ ^[0-9]+$ ]] && (( dc < iv_epoch )) \
        && printf '3\tdoc-stale\t%s\tatualize %s (ou re-carimbe a direção com "maestro intent --bump" após revisar)\n' "$d" "$d"
    done
  fi
  return 0
}
