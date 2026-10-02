#!/usr/bin/env bash
# maestro lib/core-order-turno.sh — ordem 046 (a ordem do turno no método).
#
# Três coisas, uma fonte: o BLOCO `## Turno` da ordem (fatia/fim/teto/fora/
# relatório), o CRITÉRIO do Stop de turno (`order --turno-check`) e a válvula
# `order --turno-livre`. O critério é o RECIBO no tip — o ledger decide, com a
# mesma derivação do `order --status` (_order_status, maestro_tree_same da 044);
# o hook só chama este comando e nunca executa o `fim:` da ordem. Rótulos do
# relatório são checagem ADICIONAL: entram na lista de faltas, nunca bloqueiam
# sozinhos. Honra declarada (o que o trilho não alcança): ENGINEERING_SPEC.
#
# Sourced por lib/cmd-order.sh e lib/core-conform-orders.sh; usa as funções de
# lib/core-order-state.sh (já no escopo: _order_field, _order_status, ...).

TURNO_LABELS="fatia fim teto fora relatório"
TURNO_REPORT_LABELS="feito provado aberto decisão próximo"
TURNO_CAP=3   # teto de bloqueios por sessão, qualquer que seja o `teto:` da ordem

_turno_value() { # <arquivo> <rótulo> → valor do rótulo dentro de `## Turno` (placeholder `<…>` conta como vazio)
  local v
  v=$(awk -v l="$2" '
    /^## Turno[[:space:]]*$/ { f=1; next }
    /^## /                   { f=0 }
    f { s=$0; sub(/^[[:space:]]*-?[[:space:]]*/, "", s)
        if (index(s, l ":") == 1) { v=substr(s, length(l) + 2); sub(/^[[:space:]]+/, "", v); print v; exit } }' "$1" 2>/dev/null)
  [[ "$v" == "<"* ]] && v=""
  printf '%s' "$v"
}

_turno_missing() { # <arquivo> → rótulos ausentes/vazios/inválidos, um por linha (teto precisa ser inteiro ≥ 1)
  local l v
  for l in $TURNO_LABELS; do
    v=$(_turno_value "$1" "$l")
    [[ -n "$v" ]] || { printf '%s\n' "$l"; continue; }
    [[ "$l" != "teto" || "$v" =~ ^[1-9][0-9]*$ ]] || printf '%s\n' "$l"
  done
}

_turno_has_block() { # <arquivo> → rc 0 se fatia, fim, teto e fora estão válidos (o relatório é outra lacuna)
  ! _turno_missing "$1" | grep -qE '^(fatia|fim|teto|fora)$'
}

_order_turno_skeleton() { # esqueleto emitido por --create quando o corpo não traz `## Turno`
  printf '\n## Turno\n'
  printf -- '- fatia: <o que cabe num turno>\n'
  printf -- '- fim: <comando que sai 0/1 — critério mecânico de término>\n'
  printf -- '- teto: <rodadas máximas, inteiro>\n'
  printf -- '- fora: <o que este turno NÃO faz>\n'
  printf -- '- relatório: <onde está o contrato do relatório de fim de turno>\n'
}

_turno_report_missing() { # <relatório.txt> → rótulos do relatório fixo ausentes, um por linha
  local f="$1" l
  for l in $TURNO_REPORT_LABELS; do
    grep -qiE "^[[:space:]]*[-*]*[[:space:]]*\**${l}\**[[:space:]]*:" "$f" 2>/dev/null || printf '%s\n' "$l"
  done
}

_turno_find_order() { # <proj> <branch> → arquivo da ordem cujo branch: é o dado, vazio se nenhuma
  local f
  shopt -s nullglob
  for f in "$1"/.maestro/orders/*.md; do
    _order_valid_stamp "$f" && [[ "$(_order_field "$f" branch)" == "$2" ]] && { printf '%s' "$f"; break; }
  done
  shopt -u nullglob
}

_turno_receipt_gap() { # <wproj> <rótulo> → "falta: …" distinguindo recibo AUSENTE de VENCIDA
  local ef; ef=$(maestro_evidence_file "$1" "$2" 2>/dev/null)
  if [[ -f "$ef" ]]; then
    printf 'falta: recibo %s VENCIDA — não é o conteúdo do tip (ou a execução falhou); regrave no tip\n' "$2"
  else
    printf 'falta: recibo %s ausente — maestro evidence --record --label %s -- <suíte>\n' "$2" "$2"
  fi
}

_turno_proof_gaps() { # <dono> <wproj> <arquivo> → "falta: …" por recibo ausente/vencido, vazio se tudo VÁLIDO no tip
  local dono="$1" wproj="$2" of="$3" st line
  st=$(_order_status "$dono" "$wproj" "$of")
  case "$st" in
    aceita|absorvida) return 0 ;;
    provada) ;;
    *) _turno_receipt_gap "$wproj" "$(_order_evidence_label "$dono" "$wproj" "$of")" ;;
  esac
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != *": VÁLIDA" ]] && printf 'falta: recibo da área — %s\n' "$line"
  done < <(_order_verif_report "$wproj" "$of")
  return 0
}

_turno_count_file() { printf '%s/turno/%s-%s' "$MAESTRO_HOME" "$1" "$2"; }   # <sid> <id>

_turno_gate() { # <arquivo> <sid> <id> <faltas> <relatório-faltas> → rc 1 (bloqueia, imprime) | rc 0 (teto atingido, libera)
  local of="$1" sid="$2" oid="$3" gaps="$4" rep="$5" cap cf n
  cap=$(_turno_value "$of" teto); (( cap > TURNO_CAP )) && cap=$TURNO_CAP
  cf=$(_turno_count_file "$sid" "$oid")
  n=$(cat "$cf" 2>/dev/null) || n=0
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if (( n >= cap )); then
    log_event turno_teto ${sid:+session_id="$sid"} n="$((10#$oid))" 2>/dev/null || :
    printf 'liberado: teto de %s bloqueio(s) atingido (turno_teto) — o recibo segue faltando\n' "$cap"
    return 0
  fi
  mkdir -p "${cf%/*}" 2>/dev/null && printf '%s' "$((n + 1))" > "$cf" 2>/dev/null || :
  printf '%s\n' "$gaps"
  [[ -n "$rep" ]] && printf 'falta rótulo do relatório de turno: %s\n' "$(tr '\n' ' ' <<<"$rep")"
  printf 'bloqueio %s de %s — registre o recibo no tip (maestro evidence --record) e relate de novo\n' "$((n + 1))" "$cap"
  return 1
}

_order_turno_check() { # <proj> <sid> <relatório.txt|""> → rc 0 libera (stdout vazio ou aviso de teto) | rc 1 bloqueia (stdout = faltas)
  local proj="$1" sid="${2:-desconhecido}" rf="${3:-}" br of oid wproj gaps rep=""
  br=$(git -C "$proj" symbolic-ref --quiet --short HEAD 2>/dev/null) || return 0
  [[ -d "$proj/.maestro/orders" ]] || return 0
  of=$(_turno_find_order "$proj" "$br"); [[ -n "$of" ]] || return 0
  grep -q '^turno_livre: ' "$of" 2>/dev/null && return 0
  _turno_has_block "$of" || return 0   # ordem antiga/sem bloco: lacuna do conform, nunca trava o Stop
  oid=$(_order_field "$of" id)
  wproj=$(_order_work_project "$proj" "$of")
  gaps=$(_turno_proof_gaps "$proj" "$wproj" "$of")
  if [[ -z "$gaps" ]]; then rm -f "$(_turno_count_file "$sid" "$oid")" 2>/dev/null; return 0; fi
  [[ -n "$rf" && -r "$rf" ]] && rep=$(_turno_report_missing "$rf")
  _turno_gate "$of" "$sid" "$oid" "$gaps" "$rep"
}

_order_turno_livre() { # <arquivo> <id> <sid> — carimba a válvula na ordem (visível no --status)
  local of="$1" oid="$2" sid="$3" stamp
  grep -q '^turno_livre: ' "$of" 2>/dev/null && { printf 'ordem %s: já estava turno-livre\n' "$oid"; return 0; }
  stamp=$(printf 'turno_livre: %s\nturno_livre_session: %s' "$(date -Iseconds)" "${sid:-desconhecido}")
  awk -v ins="$stamp" '!done && $0 == "-->" { print ins; done=1 } { print }' "$of" > "$of.tmp.$$" \
    && mv -f "$of.tmp.$$" "$of" || { rm -f "$of.tmp.$$" 2>/dev/null; die env "falha ao gravar $of" "" 2; }
  printf 'ordem %s: turno-livre registrado — o Stop não a bloqueia; a válvula fica visível no --status\n' "$oid"
}
