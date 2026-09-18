#!/usr/bin/env bash
# maestro lib/cmd-order-json.sh — ordem 014 (issue #18), extraído de
# lib/cmd-order.sh para não cruzar o teto de `oversized-file` (400 linhas).
#
# Emissão JSON de `maestro order --status N --json`: o supervisor mora em
# repo próprio e RECALCULAVA a derivação de estado por conta — a que
# interrompia humano era a que errava, e cada estado novo (absorvida na
# ordem 004, adiada na 013) alargava o buraco porque o consumidor externo
# não os conhecia. Esta é a FONTE ÚNICA: lê os MESMOS predicados de
# core-order-state.sh que `_order_action_status` (lib/cmd-order.sh) lê para
# o texto — nunca uma segunda derivação (precedente hooks/lib/habit-sensors.awk:
# "sensor único, dois momentos"; aqui são dois momentos de ESTADO). Contrato
# em docs/architecture/DATA_MODEL.md §9, emenda v1.15: nome de campo e forma
# do objeto não mudam sem emenda; campo novo é sempre ADITIVO.
#
# Sourced por lib/cmd-order.sh (_order_json_lib_load, I-2) SOB DEMANDA — só
# quando `--status` vem com `--json` — DEPOIS de core-order-state.sh e
# hooks/lib/common.sh (já residentes no processo por essa altura: REPO_DIR,
# die(), _order_field/_order_status/_order_evidence_match/_order_proof_tree/
# _order_deferred_tree/_order_moved_since_accept/_order_intent_stale/
# _order_verif_areas/_order_verif_report, _order_evidence_label — todas já no
# escopo). Módulo ausente derruba SÓ o comando --json (die env em
# _order_json_lib_load), nunca o CLI; `--status` sem `--json` nunca carrega
# este arquivo.
#
# `_intent_version`/`_intent_file`/`_intent_body_hash` (lib/core-intent.sh,
# ordem 015) NÃO são residentes: `_order_json_direcao_frag` chama
# `_intent_lib_load` antes de usá-las, mesma técnica de `_verif_lib_load`.
#
# Mesma convenção de core-order-state.sh/cmd-order.sh: proj/of/oid/st chegam
# por parâmetro posicional, nessa ordem. Cada bloco do boletim (prova/
# direção/verificação/ação) virou uma função `_order_json_*_frag`, por
# RESPONSABILIDADE — não é _order_action_status_json cortada ao meio, é o
# mesmo recorte que _order_show_context/_order_show_next já fazem no texto,
# só que cada fragmento devolve o literal JSON pronto para embutir.

_order_json_esc() { # <str> → escapado para caber dentro de aspas JSON (puro bash, zero lib externa)
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}
_order_json_field() { # <chave> <valor> → "chave":"valor" — valor vazio vira null, nunca ""
  if [[ -z "${2-}" ]]; then printf '"%s":null' "$1"; else printf '"%s":"%s"' "$1" "$(_order_json_esc "$2")"; fi
}
_order_json_bool() { # <chave> <0|1> → "chave":true|false
  [[ "$2" == "1" ]] && printf '"%s":true' "$1" || printf '"%s":false' "$1"
}

_order_json_prova_frag() { # <proj> <arquivo> <id> <estado_derivado> → objeto "prova" — MESMO condicional/chamada de _order_action_status
  local proj="$1" of="$2" oid="$3" st="$4" _ptree="" p_estado="" p_detalhe="" p_arvore=""
  # ordem 021: registro fora da árvore é a fonte; arquivo conta na migração.
  [[ "$st" == "aceita" ]] && _ptree=$(_order_terminal_field_appended "$proj" "$of" accepted_tree) || true
  if [[ "$st" == "absorvida" ]]; then
    p_estado="absorvida"; p_arvore=$(_order_terminal_field_header "$proj" "$of" absorbed_tree)
    p_detalhe=$(printf 'ABSORVIDA por %s — árvore %s (prova é da absorvente, não desta ordem)' \
      "$(_order_terminal_field_header "$proj" "$of" absorbed_by)" "${p_arvore:0:12}")
  elif [[ "$st" == "adiada" ]]; then
    p_estado="adiada"; p_arvore=$(_order_deferred_tree "$proj" "$of")
    if [[ -n "$p_arvore" ]]; then
      p_detalhe=$(printf 'ADIADA por %s — prova congelada em %s (idade e mudança de árvore não se aplicam: trabalho adiado não anda)' \
        "$(_order_field "$of" deferred_by)" "${p_arvore:0:12}")
    else
      p_detalhe=$(printf 'ADIADA por %s — sem recibo gravado ainda (nada a congelar)' "$(_order_field "$of" deferred_by)")
    fi
  elif [[ -n "$_ptree" && "$_ptree" != "desconhecida" ]]; then
    p_estado="valida"; p_arvore="$_ptree"
    p_detalhe=$(printf 'VÁLIDA na aceitação — árvore %s, recibo order-%s exit 0' "${_ptree:0:12}" "$((10#$oid))")
  else
    p_detalhe=$("$REPO_DIR/bin/maestro" evidence --label "$(_order_evidence_label "$proj" "$of")" --project "$proj" 2>/dev/null | head -1)
    [[ -z "$p_detalhe" ]] && p_detalhe="?"
    case "$p_detalhe" in
      *VÁLIDA*)  p_estado="valida" ;;
      *VENCIDA*) p_estado="vencida" ;;
      *NENHUMA*) p_estado="nenhuma" ;;
      *)         p_estado="desconhecida" ;;
    esac
    [[ "$st" == "provada" ]] && p_arvore=$(_order_proof_tree "$proj" "$of")
  fi
  printf '{%s,%s,%s}' "$(_order_json_field estado "$p_estado")" "$(_order_json_field detalhe "$p_detalhe")" \
    "$(_order_json_field arvore "$p_arvore")"
}

_order_json_direcao_frag() { # <proj> <arquivo> → objeto "direcao" (E22), ou "null" — MESMO condicional de _order_show_context
  local proj="$1" of="$2" _ov _ivn
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
  _ov=$(_order_field "$of" intent_version); _ivn=$(_intent_version "$(_intent_file "$proj")")
  [[ -n "$_ov" ]] || { printf 'null'; return 0; }
  local d_stale=0 d_bump=0
  _order_intent_stale "$of" "$_ivn" && d_stale=1
  if [[ "$d_stale" == "0" && "$_ov" == "$_ivn" ]]; then
    local _ihn _oh
    _ihn=$(_intent_body_hash "$(_intent_file "$proj")"); _oh=$(_order_field "$of" intent_hash)
    [[ -n "$_oh" && -n "$_ihn" && "$_oh" != "$_ihn" ]] && d_bump=1
  fi
  printf '{%s,%s,%s,%s}' \
    "$(_order_json_field ordem "$_ov")" "$(_order_json_field atual "$_ivn")" \
    "$(_order_json_bool desatualizada "$d_stale")" "$(_order_json_bool hash_bump_pendente "$d_bump")"
}

_order_json_verificacao_frag() { # <proj> <arquivo> <estado_derivado> → array "verificacao" (E23b), ou "null" — pula 'adiada' pelo MESMO motivo do texto
  local proj="$1" of="$2" st="$3" _vareas _vrep _vl _vitems="" _first=1 _rot _est
  [[ "$st" != "adiada" ]] || { printf 'null'; return 0; }
  _vareas=$(_order_verif_areas "$proj" "$of"); _vrep=$(_order_verif_report "$proj" "$of" "$_vareas")
  [[ -n "$_vrep" ]] || { printf 'null'; return 0; }
  while IFS= read -r _vl; do
    [[ -n "$_vl" ]] || continue
    _rot="${_vl%%:*}"; _est="${_vl#*: }"
    [[ $_first -eq 1 ]] && _first=0 || _vitems+=","
    _vitems+=$(printf '{%s,%s}' "$(_order_json_field rotulo "$_rot")" "$(_order_json_field estado "$_est")")
  done <<<"$_vrep"
  printf '[%s]' "$_vitems"
}

_order_json_acao_frag() { # <proj> <arquivo> <estado_derivado> → terminal/suspensa/pede_aceite/motivo — MESMOS casos de _order_show_next
  local proj="$1" of="$2" st="$3" pede=0 motivo=""
  case "$st" in
    provada) pede=1; motivo="revisar e aceitar" ;;
    aceita)
      local _mv; _mv=$(_order_moved_since_accept "$proj" "$of")
      if [[ -n "$_mv" ]]; then pede=1; motivo="branch andou depois do aceite (reaceite se for o caso)"
      else motivo="encerrada"; fi ;;
    absorvida) motivo="encerrada por absorção" ;;
    adiada)    motivo="suspensa — não cobra aceite nem prova enquanto deferred_by existir" ;;
    *)         motivo="aguardando execução" ;;
  esac
  local terminal=0 suspensa=0
  [[ "$st" == "aceita" || "$st" == "absorvida" ]] && terminal=1
  [[ "$st" == "adiada" ]] && suspensa=1
  printf '%s,%s,%s,%s' \
    "$(_order_json_bool terminal "$terminal")" "$(_order_json_bool suspensa "$suspensa")" \
    "$(_order_json_bool pede_aceite "$pede")" "$(_order_json_field motivo "$motivo")"
}

_order_action_status_json() { # <proj> <arquivo> <id> — o boletim de _order_action_status, em JSON, MESMA fonte
  local proj="$1" of="$2" oid="$3" st br br_existe=0 br_tip=""
  st=$(_order_status "$proj" "$of"); br=$(_order_field "$of" branch)
  if git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1; then
    br_existe=1; br_tip=$(git -C "$proj" rev-parse --short=7 "$br" 2>/dev/null)
  fi
  local out='{'
  out+="$(_order_json_field id "$oid")"
  out+=",$(_order_json_field estado "$st")"
  out+=",$(_order_json_field branch "$br")"
  out+=",$(_order_json_bool branch_existe "$br_existe")"
  out+=",$(_order_json_field branch_tip "$br_tip")"
  out+=",$(_order_json_field arquivo "$of")"
  out+=",$(_order_json_acao_frag "$proj" "$of" "$st")"
  out+=",\"direcao\":$(_order_json_direcao_frag "$proj" "$of")"
  out+=",\"verificacao\":$(_order_json_verificacao_frag "$proj" "$of" "$st")"
  out+=",$(_order_json_field absorvido_por "$(_order_terminal_field_header "$proj" "$of" absorbed_by)")"
  out+=",$(_order_json_field adiado_por "$(_order_field "$of" deferred_by)")"
  out+=",\"prova\":$(_order_json_prova_frag "$proj" "$of" "$oid" "$st")"
  out+='}'
  printf '%s\n' "$out"
}
