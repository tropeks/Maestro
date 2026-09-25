#!/usr/bin/env bash
# maestro lib/cmd-conform.sh — ordem 042 (INTENT v6 §Prioridades 3/4):
# `maestro conform --check [<dir>] [--json]`.
#
# Determinístico, sem LLM e sem rede: lista o que falta para um projeto
# entrar no método e rodar headless. NÃO reimplementa nenhum formato que já
# existe — cada família chama o dono do formato correspondente:
#   (a) INTENT      → lib/core-intent.sh          (_intent_lib_load)
#   (b) .maestro.yaml → hooks/lib/verifications.sh (_verif_lib_load)
#   (c) frescor      → lib/cmd-brief.sh/cmd-docs.sh (maestro_brief_file/_docs_declared_list)
#   (d) ordens       → lib/core-order-state.sh     (_order_lib_load)
#   (e) daemon       → sqlite3 -readonly sobre ~/.ponte/ponte.db
#   (f) CLAUDE.md    → só existência, aqui mesmo (família pequena demais p/ módulo próprio)
# As cinco primeiras famílias moram em lib/core-conform-*.sh (teto de 400
# linhas do sensor `oversized-file` — um módulo só estouraria); este arquivo
# é o dispatch, a família (f), a ordenação estável e a emissão texto/JSON.
#
# Sourced por bin/maestro (via `_conform_lib_load`, molde de
# `_order_json_lib_load`/I-2) SOB DEMANDA — só quando o comando é `conform`.
# REPO_DIR/die()/has() já no escopo (bin/maestro). `_conform_core_lib_load`
# (abaixo) carrega os cinco módulos de família, no molde de
# `_order_workproject_lib_load` (core-order-state.sh).
#
# Não escreve nada, em lugar nenhum: nem no projeto, nem em ~/.maestro/, nem
# no ponte.db. O único rastro é `log_event conform` (n_lacunas/familias/rc) —
# DÉBITO DECLARADO (mesmo padrão de route_fix, DATA_MODEL §4 emenda v1.19/
# ordem 030): `hooks/` está CONGELADA nesta ordem (contrato de execução), então
# `_maestro_event_valid`/`_maestro_set_key_regex` (hooks/lib/common.sh) ainda
# NÃO reconhecem `conform`/`n_lacunas`/`familias` — a chamada abaixo já está
# correta e é descartada em silêncio (comportamento padrão de log_event para
# vocabulário desconhecido) até um patch futuro em hooks/lib/common.sh (mesmo
# mecanismo desta ordem: docs/patches/, aplicado pelo Capitão). DATA_MODEL
# §4 já documenta o evento — é a emenda que esta ordem pode fazer sem tocar
# zona congelada.

_CONFORM_FAMILIA_NOME=(intent yaml frescor ordens daemon claude-md)   # índice 1..6

_conform_core_lib_load() { # carrega os 5 módulos core-conform-*.sh — uma vez (I-2)
  declare -f _conform_check_intent >/dev/null 2>&1 && return 0
  local m
  for m in core-conform-intent core-conform-yaml core-conform-fresh core-conform-orders core-conform-ponte; do
    if [[ -f "$REPO_DIR/lib/$m.sh" ]]; then
      # shellcheck disable=SC1090
      source "$REPO_DIR/lib/$m.sh"
    else
      die env "lib/$m.sh não encontrado em $REPO_DIR" "reinstale o plugin (maestro doctor)" 2
    fi
  done
  return 0
}

_conform_check_claude_md() { # <proj> → TSV família (f) CLAUDE.md
  [[ -f "$1/CLAUDE.md" ]] || printf '6\tclaude-md-missing\tCLAUDE.md\tcrie CLAUDE.md na raiz com as regras do método\n'
  return 0
}

CONFORM_ARG_DIR=""; CONFORM_ARG_JSON=0; CONFORM_ARG_CHECK=0

_conform_parse_args() { # <argv> → grava CONFORM_ARG_*; die validation em uso inválido
  CONFORM_ARG_DIR=""; CONFORM_ARG_JSON=0; CONFORM_ARG_CHECK=0
  while (( $# )); do
    case "$1" in
      --check) CONFORM_ARG_CHECK=1 ;;
      --json)  CONFORM_ARG_JSON=1 ;;
      -*) die validation "flag desconhecida '$1'" "maestro conform --check [<dir>] [--json]" 2 ;;
      *)
        [[ -z "$CONFORM_ARG_DIR" ]] || die validation "argumento extra '$1'" \
          "maestro conform --check [<dir>] [--json]" 2
        CONFORM_ARG_DIR="$1"
        ;;
    esac
    shift
  done
  return 0
}

_conform_resolve_proj() { # <dir-cru> → projeto resolvido no stdout; die validation (2) se inválido
  local dir="$1" proj
  if [[ -n "$dir" ]]; then
    [[ -d "$dir" ]] || die validation "diretório '$dir' não existe" "maestro conform --check <dir>" 2
    proj=$(cd -P -- "$dir" 2>/dev/null && pwd) || die validation "não consigo resolver '$dir'" "" 2
  else
    proj=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || proj="$PWD"
  fi
  printf '%s' "$proj"
  return 0
}

_conform_collect() { # <proj> → todas as linhas "fam<TAB>código<TAB>alvo<TAB>fix", NÃO ordenadas
  local proj="$1"
  _conform_check_intent "$proj"
  _conform_check_yaml "$proj"
  _conform_check_fresh "$proj"
  _conform_check_orders "$proj"
  _conform_check_ponte "$proj"
  _conform_check_claude_md "$proj"
  return 0
}

_conform_familias_str() { # <lines TSV> → "intent,yaml,..." únicas, na ordem das famílias
  local idx list=""
  for idx in $(printf '%s\n' "$1" | awk -F'\t' '$1!=""{print $1}' | sort -un); do
    list+="${list:+,}${_CONFORM_FAMILIA_NOME[$((idx-1))]}"
  done
  printf '%s' "$list"
  return 0
}

_conform_print_json() { # <proj> <lines TSV ordenadas>
  local proj="$1" lines="$2" fam cod alvo fix first=1 conforme="true"
  [[ -z "$lines" ]] || conforme="false"
  printf '{%s,"conforme":%s,"lacunas":[' "$(_order_json_field project "$proj")" "$conforme"
  if [[ -n "$lines" ]]; then
    while IFS=$'\t' read -r fam cod alvo fix; do
      [[ -n "$cod" ]] || continue
      (( first == 1 )) || printf ','
      first=0
      printf '{%s,%s,%s,%s}' \
        "$(_order_json_field codigo "$cod")" "$(_order_json_field familia "${_CONFORM_FAMILIA_NOME[$((fam-1))]}")" \
        "$(_order_json_field alvo "$alvo")" "$(_order_json_field fix "$fix")"
    done <<<"$lines"
  fi
  printf ']}\n'
  return 0
}

cmd_conform() { # S-2701: `maestro conform --check` — lacunas para o método/headless
  _conform_parse_args "$@"
  (( CONFORM_ARG_CHECK == 1 )) || die validation "uso: maestro conform --check [<dir>] [--json]" \
    "informe --check" 2

  local proj; proj=$(_conform_resolve_proj "$CONFORM_ARG_DIR")
  _conform_core_lib_load

  local lines n=0 familias
  lines=$(_conform_collect "$proj" | LC_ALL=C sort -t $'\t' -k1,1n -k3,3)
  [[ -n "$lines" ]] && n=$(printf '%s\n' "$lines" | grep -c .)
  familias=$(_conform_familias_str "$lines")

  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  log_event conform n_lacunas="$n" familias="${familias:-none}" rc=$(( n > 0 ? 1 : 0 ))

  if (( CONFORM_ARG_JSON == 1 )); then
    _order_lib_load; _order_json_lib_load
    _conform_print_json "${proj##*/}" "$lines"
  elif [[ -n "$lines" ]]; then
    printf '%s\n' "$lines" | awk -F'\t' '{print $2"\t"$3"\t"$4}'
  fi

  (( n == 0 )) && return 0
  return 1
}
