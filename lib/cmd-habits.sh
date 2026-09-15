#!/usr/bin/env bash
# maestro lib/cmd-habits.sh — E9/S-903, extraído de bin/maestro na ordem 009
# (E24, docs/designs/e24-nucleo-e-adaptadores.md).
#
# `maestro habits`: os MESMOS sensores do hook (hooks/lib/habit-sensors.awk),
# no momento do review/CI. Sensor único, dois momentos — divergência entre
# eles seria dois vocabulários de smell. Exit: 0 limpo · 1 achados · 2
# ambiente.
#
# Sourced por bin/maestro (via _habits_lib_load, I-2) DENTRO do mesmo
# processo — REPO_DIR, MAESTRO_HABIT_GUIDES, die(), join_semi(),
# maestro_now_epoch já no escopo.
#
# Convenção (lote do `order`, E24): parâmetro posicional, nenhuma função
# fecha sobre local de outra. Exceção documentada (molde TEL_STATE/EV_RUN_*):
# HABITS_* abaixo — funções que precisam devolver MAIS de um valor (lista +
# sinalizador) gravam globals do módulo e são chamadas SEM `$(...)` (uma
# função chamada dentro de `$(...)` roda em SUBSHELL — qualquer global que
# ela grave lá dentro some quando o subshell termina; foi o bug que a suíte
# pegou em _retro_routable neste mesmo lote).

# --------------------------------------------------------------- flags/escopo
HABITS_SCOPE="diff"
HABITS_PROJ=""
HABITS_WRITE_BASELINE=0
HABITS_PATHS=()

_habits_parse_args() { # <args...> → grava HABITS_SCOPE/HABITS_PROJ/HABITS_WRITE_BASELINE/HABITS_PATHS
  HABITS_SCOPE="diff"; HABITS_PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"; HABITS_WRITE_BASELINE=0; HABITS_PATHS=()
  while (( $# )); do
    case "$1" in
      --all) HABITS_SCOPE="all" ;;
      --baseline) HABITS_WRITE_BASELINE=1; HABITS_SCOPE="all" ;;   # S-905: catraca grava do repo inteiro
      --project) HABITS_PROJ="${2:-}"; shift ;;
      -*) die validation "flag desconhecida '$1'" "maestro habits [--all|--baseline] [caminhos...]" 1 ;;
      *) HABITS_SCOPE="paths"; HABITS_PATHS+=("$1") ;;
    esac
    shift
  done
  return 0
}

# ------------------------------------------------------------- sensores ativos
_habits_enabled_sensors() { # <proj> → lista de sensores habilitados (MAESTRO_HABITS > .maestro.yaml > all); vazio = desligado
  local proj="$1" enabled="all" hline=""
  if [[ -n "${MAESTRO_HABITS+x}" ]]; then
    enabled="$MAESTRO_HABITS"
  elif [[ -f "$proj/.maestro.yaml" ]]; then
    hline=$(awk '/^habits:/ { sub(/^habits:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' \
      "$proj/.maestro.yaml" 2>/dev/null) || hline=""
    if [[ "$hline" =~ ^\[[[:space:]]*\]$ ]]; then enabled=""
    elif [[ "$hline" =~ ^\[.*\]$ ]]; then
      enabled=$(printf '%s' "$hline" | tr -d '[]" ' | tr ',' '\n' \
        | grep -E '^[a-z-]{1,24}$' | paste -sd, -) || enabled=""
    fi
  fi
  printf '%s' "$enabled"
  return 0
}

_habits_ignore_prefixes() { # <proj> → prefixos de habits_ignore (E23d), um por linha; vazio = nada ignorado
  local proj="$1" iline="" ip
  [[ -f "$proj/.maestro.yaml" && -r "$proj/.maestro.yaml" ]] || return 0
  iline=$(awk '/^habits_ignore:/ { sub(/^habits_ignore:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' \
    "$proj/.maestro.yaml" 2>/dev/null) || iline=""
  [[ -n "$iline" ]] || return 0
  # shellcheck disable=SC2086  # split deliberado: a lista é de prefixos
  for ip in $(printf '%s' "$iline" | tr -d "[]\",'" ); do
    [[ "$ip" =~ ^[A-Za-z0-9._/-]{1,120}$ ]] && printf '%s\n' "$ip"
  done
  return 0
}

# --------------------------------------------------------------- coleta de arquivos
HABITS_FILES=()
HABITS_DIFF_EMPTY=0

_habits_collect_files() { # <scope> <proj> <paths...> → grava HABITS_FILES/HABITS_DIFF_EMPTY; die env se --all sem git
  local scope="$1" proj="$2"; shift 2
  HABITS_FILES=(); HABITS_DIFF_EMPTY=0
  local f
  if [[ "$scope" == "paths" ]]; then
    HABITS_FILES=("$@")
    return 0
  fi
  if [[ "$scope" == "all" ]]; then
    # rastreados + novos não-ignorados: slop novo chega em arquivo novo, e um
    # --all que não o vê é uma catraca com o dente quebrado.
    while IFS= read -r f; do [[ -n "$f" ]] && HABITS_FILES+=("$proj/$f"); done < <(
      { git -C "$proj" ls-files 2>/dev/null
        git -C "$proj" ls-files --others --exclude-standard 2>/dev/null; } | sort -u)
    [[ ${#HABITS_FILES[@]} -gt 0 ]] || die env "--all exige git" "passe caminhos explícitos" 2
    return 0
  fi
  while IFS= read -r f; do [[ -n "$f" ]] && HABITS_FILES+=("$proj/$f"); done < <(
    { git -C "$proj" diff --name-only HEAD 2>/dev/null
      git -C "$proj" ls-files --others --exclude-standard 2>/dev/null; } | sort -u)
  [[ ${#HABITS_FILES[@]} -eq 0 ]] && HABITS_DIFF_EMPTY=1
  return 0
}

# ------------------------------------------------------------- varredura por arquivo
HABITS_TOTAL=0
HABITS_SMELLS=""
HABITS_IGNORED_N=0
declare -g -A HABITS_COUNT=()

_habits_scan_file() { # <arquivo> <proj> <engine> <enabled> <scope> [prefixos de habits_ignore...]
  # Imprime achados na hora (não vira $(...) — ver nota de convenção acima) e
  # acumula HABITS_TOTAL/HABITS_SMELLS/HABITS_COUNT/HABITS_IGNORED_N.
  local f="$1" proj="$2" engine="$3" enabled="$4" scope="$5"; shift 5
  [[ -f "$f" && -r "$f" ]] || return 0
  case "$f" in */vendor/*|*/node_modules/*|*/.git/*) return 0 ;; esac
  local rel ip skipf=0
  if [[ "$scope" == "all" && $# -gt 0 ]]; then
    rel="${f#"$proj"/}"
    for ip in "$@"; do [[ "$rel" == "$ip"* ]] && { skipf=1; break; }; done
    (( skipf == 1 )) && { HABITS_IGNORED_N=$(( HABITS_IGNORED_N + 1 )); return 0; }
  fi
  local base ext is_test=0 is_gen=0
  base="${f##*/}"
  ext=$(maestro_lang_ext "$f")
  [[ -n "$ext" ]] || return 0
  case "$base" in test*|*_test.*|*.test.*|*.spec.*|conftest.py) is_test=1 ;; esac
  case "$f" in */tests/*|*/test/*|*/__tests__/*) is_test=1 ;; esac
  # S-1808: código GERADO (migration do Django etc.) não é slop de ninguém —
  # ver bin/maestro (comentário original, medição NetForge 66/135 migrations).
  case "$f" in */migrations/*.py|*_pb2.py|*_pb2_grpc.py|*.generated.*|*/gen/*) is_gen=1 ;; esac
  local out shown smell lineno detail
  out=$(awk -v EXT="$ext" -v ENABLED="$enabled" -v ISTEST="$is_test" -v ISGEN="$is_gen" \
    -f "$engine" "$f" 2>/dev/null | head -50) || out=""
  [[ -n "$out" ]] || return 0
  shown="${f#"$proj"/}"
  while IFS=$'\t' read -r smell lineno detail; do
    [[ -n "$smell" ]] || continue
    HABITS_TOTAL=$(( HABITS_TOTAL + 1 ))
    HABITS_COUNT["$smell"]=$(( ${HABITS_COUNT["$smell"]:-0} + 1 ))
    printf '%s:%s: %s — %s\n' "$shown" "$lineno" "$smell" "$detail"
    case " $HABITS_SMELLS " in *" $smell "*) ;; *) HABITS_SMELLS+="${HABITS_SMELLS:+ }$smell" ;; esac
  done <<<"$out"
  return 0
}

# ------------------------------------------------------------------- catraca (S-905)
_habits_write_baseline() { # <bfile> <total> → grava .maestro-habits.tsv (contagem POR SMELL); die env em falha
  local bfile="$1" total="$2" btmp="$1.tmp.$$" sm
  {
    printf '# maestro habits baseline (S-905) — catraca anti-slop: só desce.\n'
    printf '# Regenerar (sempre para baixo, no mesmo commit do fix): maestro habits --baseline\n'
    for sm in $HABITS_SMELLS; do printf '%s\t%s\n' "$sm" "${HABITS_COUNT[$sm]}"; done | sort
  } > "$btmp" 2>/dev/null && mv -f "$btmp" "$bfile" 2>/dev/null \
    || { rm -f "$btmp" 2>/dev/null; die env "não consegui gravar $bfile" "cheque permissões" 2; }
  printf -- '---\nbaseline gravado: %s (%s achado(s) em %s smell(s))\n' \
    "${bfile##*/}" "$total" "$(printf '%s\n' $HABITS_SMELLS | grep -c . || true)"
  return 0
}

_habits_check_baseline() { # <bfile> <total> → rc 0 dentro da catraca, 1 CATRACA estourada (over/due)
  # E24 Lote 0/0.3 — dívida DECLARADA com prazo (I-6: epoch é inteiro, sem
  # float). Colunas 3/4 são OPCIONAIS — retrocompatível (ver bin/maestro
  # original para a nota completa sobre o formato de 2 vs. 4 colunas).
  local bfile="$1" total="$2"
  local over=() due=() sm bl cur improved=0 vence alvo now_epoch=""
  declare -A base=() base_vence=() base_alvo=()
  while IFS=$'\t' read -r sm bl vence alvo; do
    [[ "$sm" =~ ^[a-z][a-z-]{2,23}$ && "$bl" =~ ^[0-9]+$ ]] || continue
    base["$sm"]=$bl
    [[ "$vence" =~ ^[0-9]+$ && "$alvo" =~ ^[0-9]+$ ]] || continue
    base_vence["$sm"]=$vence; base_alvo["$sm"]=$alvo
  done < "$bfile"
  for sm in "${!HABITS_COUNT[@]}"; do
    cur=${HABITS_COUNT[$sm]}; bl=${base[$sm]:-0}
    if (( cur > bl )); then over+=("$sm: $cur > baseline $bl")
    elif (( cur < bl )); then improved=1; fi
  done
  for sm in "${!base[@]}"; do
    [[ -n "${HABITS_COUNT[$sm]:-}" ]] || { (( base[$sm] > 0 )) && improved=1; }
  done
  if (( ${#base_vence[@]} > 0 )); then
    now_epoch=$(maestro_now_epoch)
    for sm in "${!base_vence[@]}"; do
      vence=${base_vence[$sm]}; alvo=${base_alvo[$sm]}; cur=${HABITS_COUNT[$sm]:-0}
      (( now_epoch > vence && cur > alvo )) \
        && due+=("$sm: vencida há $(( (now_epoch - vence) / 86400 ))d, $cur > alvo $alvo")
    done
  fi
  if (( ${#over[@]} > 0 || ${#due[@]} > 0 )); then
    (( ${#over[@]} > 0 )) && {
      printf -- '---\nCATRACA: slop novo acima do baseline — %s\n' "$(join_semi "${over[@]}")"
      printf 'Conserte o que entrou; a régua não sobe para acomodar o novo.\n'
    }
    (( ${#due[@]} > 0 )) && {
      printf -- '---\nCATRACA: dívida declarada VENCEU sem chegar ao alvo — %s\n' "$(join_semi "${due[@]}")"
      printf 'O prazo (vence_epoch) passou e a contagem segue acima do alvo declarado.\n'
    }
    return 1
  fi
  printf -- '---\ndentro da catraca: %s achado(s), nenhum smell acima do baseline\n' "$total"
  (( improved == 1 )) && printf 'a régua pode descer: rode `maestro habits --baseline` no mesmo commit do fix\n'
  return 0
}

_habits_final_report() { # <total> <n arquivos sensoriados> <guides> → limpo, ou achados + guias
  local total="$1" n_files="$2" guides="$3"
  if (( total == 0 )); then
    echo "habits: limpo (${n_files} arquivo(s) sensoriado(s))"
    return 0
  fi
  printf -- '---\n%s achado(s). Guias (sensor + guia, sempre juntos):\n' "$total"
  local g=0 gf smell
  for smell in $HABITS_SMELLS; do
    gf="$guides/$smell.md"
    [[ -f "$gf" ]] || continue
    g=$(( g + 1 )); (( g > 5 )) && { printf '… (guias restantes em %s/)\n' "$guides"; break; }
    printf '\n'; head -c 700 -- "$gf" 2>/dev/null || :; printf '\n'
  done
  return 1
}

# ------------------------------------------------------------------ o comando
cmd_habits() { # S-903: os MESMOS sensores do hook, no momento do review/CI
  _habits_parse_args "$@"
  local proj="$HABITS_PROJ" scope="$HABITS_SCOPE" write_baseline="$HABITS_WRITE_BASELINE"

  local engine="$REPO_DIR/hooks/lib/habit-sensors.awk"
  local guides="${MAESTRO_HABIT_GUIDES:-$REPO_DIR/config/habit-guides}"
  [[ -f "$engine" ]] || die env "hooks/lib/habit-sensors.awk ausente" "reinstale o plugin (maestro doctor)" 2
  # E24 Lote 0/0.2: maestro_lang_ext (detecção por shebang) — sensor único com
  # o hook (I-4). Degrada com die env, igual ao engine acima.
  # shellcheck source=hooks/lib/common.sh
  if [[ -f "$REPO_DIR/hooks/lib/common.sh" ]]; then
    source "$REPO_DIR/hooks/lib/common.sh"
  else
    die env "hooks/lib/common.sh não encontrado" "reinstale o plugin (maestro doctor)" 2
  fi

  local enabled; enabled=$(_habits_enabled_sensors "$proj")
  [[ -n "$enabled" ]] || { echo "habits: desligado neste projeto (habits: [])"; return 0; }
  local ignore_pfx=()
  while IFS= read -r ip; do [[ -n "$ip" ]] && ignore_pfx+=("$ip"); done < <(_habits_ignore_prefixes "$proj")

  _habits_collect_files "$scope" "$proj" "${HABITS_PATHS[@]}"
  if (( HABITS_DIFF_EMPTY == 1 )); then
    echo "habits: diff limpo (nada alterado desde HEAD; use --all ou caminhos)"
    return 0
  fi

  HABITS_TOTAL=0; HABITS_SMELLS=""; HABITS_IGNORED_N=0; HABITS_COUNT=()
  local f
  for f in "${HABITS_FILES[@]}"; do
    _habits_scan_file "$f" "$proj" "$engine" "$enabled" "$scope" "${ignore_pfx[@]}"
  done
  # Filtro que esconde em silêncio é armadilha: o que saiu do escopo é dito.
  (( HABITS_IGNORED_N > 0 )) && printf 'habits_ignore: %s arquivo(s) fora do escopo (.maestro.yaml)\n' "$HABITS_IGNORED_N"

  local bfile="$proj/.maestro-habits.tsv"
  if (( write_baseline == 1 )); then
    _habits_write_baseline "$bfile" "$HABITS_TOTAL"
    return 0
  fi
  if [[ "$scope" == "all" && -f "$bfile" && -r "$bfile" ]]; then
    _habits_check_baseline "$bfile" "$HABITS_TOTAL"
    return $?
  fi
  _habits_final_report "$HABITS_TOTAL" "${#HABITS_FILES[@]}" "$guides"
  return $?
}
