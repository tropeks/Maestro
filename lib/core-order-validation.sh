#!/usr/bin/env bash
# maestro lib/core-order-validation.sh — ordem 050 (INTENT v56, "a linha de
# produção", pontos 1 a 4 da v55): estados de VALIDAÇÃO da ordem e o gate do
# `--accept`.
#
# O desenvolvimento não espera a CI; o que depende da CI é validação. Entre
# `provada` (recibo local verde no tip) e `aceita` entram três estados,
# DERIVADOS de recibos por árvore — nunca autodeclarados:
#
#   provada       recibo local verde no tip, sem pedido de validação para ele
#   em_validacao  pedido gravado para ESTA árvore, sem recibo de validação nela
#   validada      recibo `validation-N` verde NA MESMA árvore do pedido
#   reprovada     recibo `validation-N` vermelho na mesma árvore: é o sinal de
#                 REPARO (sem novo tip provado, não anda)
#
# Duas coisas moram fora da árvore, no ledger (~/.maestro):
#   pedido  — `maestro order --validate N` grava `<order-state>/<proj>-NNN.validate`
#             (schema, id, tree = árvore PROVADA, requested_at/session);
#   recibo  — `validation-N` no ledger de evidência do projeto do TRABALHO
#             (mesmo formato maestro-evidence-v1: exit= e wtree_after=),
#             gravado pelo runner, nunca por esta ordem.
# Árvore mudou depois (novo tip) → pedido e recibo deixam de casar com a árvore
# provada e a ordem volta a `provada` (mesma regra do recibo local, ordem 044:
# `maestro_tree_same`). Novo tip com recibo local verde ⇒ `provada` de novo.
#
# OPT-IN por projeto: sem chave `validation:` no `.maestro.yaml` do DONO nada
# disto deriva e a ordem segue `provada → aceita` (byte a byte). O GATE do
# aceite é outro interruptor, MAESTRO_ACCEPT_REQUIRE_VALIDATION (env >
# `accept_require_validation:` do yaml > desligado — mesma precedência da
# ordem 041): desligado, `--accept` passa de qualquer estado provado, como hoje.
#
# Sourced por lib/core-order-state.sh (NA HORA: `_order_status` consulta o
# derivado em toda leitura). Convenção do núcleo: `dono` (R3, pedido/flag/yaml)
# e `wproj` (R1/R2, git/recibo) chegam por parâmetro posicional, nessa ordem.

_order_validation_enabled() { # <dono> → rc 0 se o .maestro.yaml do DONO declara `validation:`
  [[ -f "$1/.maestro.yaml" ]] && grep -q '^validation:' "$1/.maestro.yaml" 2>/dev/null
}
_order_accept_require_validation() { # <dono> → rc 0 se o gate está LIGADO e o projeto declara `validation:`
  local proj="$1" v yline
  if [[ -n "${MAESTRO_ACCEPT_REQUIRE_VALIDATION+x}" ]]; then
    v="$MAESTRO_ACCEPT_REQUIRE_VALIDATION"
  elif [[ -f "$proj/.maestro.yaml" ]]; then
    yline=$(awk '/^accept_require_validation:/ { sub(/^accept_require_validation:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' \
      "$proj/.maestro.yaml" 2>/dev/null) || yline=""
    v="$yline"
  else
    v=""
  fi
  case "${v,,}" in
    1 | true | yes | on) _order_validation_enabled "$proj" ;;   # projeto sem `validation:` mantém provada → aceita
    *) return 1 ;;
  esac
}
_order_validation_request_file() { # <dono> <id> → caminho do pedido (registro fora da árvore)
  printf '%s.validate' "$(maestro_order_state_file "$1" "$2")"
}
_order_validation_receipt_file() { # <wproj> <id> → caminho do recibo `validation-N` no ledger
  local n; n=$(_order_num "${2:-}") || return 0
  maestro_evidence_file "$1" "validation-$n" 2>/dev/null || :
}
_order_validation_state() { # <dono> <wproj> <arquivo> → provada|em_validacao|validada|reprovada (chamado SÓ com a prova local já verde)
  local dono="$1" wproj="$2" f="$3" oid rq rtree ptree rf ev_w
  _order_validation_enabled "$dono" || { printf 'provada'; return 0; }
  oid=$(_order_field "$f" id)
  rq=$(_order_validation_request_file "$dono" "$oid")
  [[ -f "$rq" ]] || { printf 'provada'; return 0; }
  rtree=$(_order_state_field "$rq" tree)
  ptree=$(_order_proof_tree "$dono" "$wproj" "$f")
  # pedido de OUTRA árvore (o tip andou) não vale: volta a provada
  [[ -n "$rtree" && -n "$ptree" ]] && maestro_tree_same "$wproj" "$rtree" "$ptree" || { printf 'provada'; return 0; }
  rf=$(_order_validation_receipt_file "$wproj" "$oid")
  [[ -n "$rf" && -f "$rf" ]] || { printf 'em_validacao'; return 0; }
  ev_w=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$rf" 2>/dev/null)
  [[ -n "$ev_w" ]] && maestro_tree_same "$wproj" "$ev_w" "$ptree" || { printf 'em_validacao'; return 0; }   # recibo de outra árvore não vale
  if grep -q '^exit=0$' "$rf" 2>/dev/null; then printf 'validada'; else printf 'reprovada'; fi
}
_order_state_proven() { # <estado> → rc 0 se o estado carrega a prova LOCAL verde no tip (provada e os três de validação)
  case "$1" in provada | em_validacao | validada | reprovada) return 0 ;; *) return 1 ;; esac
}
_order_validation_accept_ready() { # <dono> <estado> → rc 0 se o `--accept` passa deste estado (gate desligado = como hoje)
  case "$2" in
    validada) return 0 ;;
    provada | em_validacao | reprovada) ! _order_accept_require_validation "$1" ;;
    *) return 1 ;;
  esac
}
_order_action_validate() { # <dono> <wproj> <arquivo> <id> <sid> — grava o PEDIDO de validação para a árvore provada
  local proj="$1" wproj="$2" of="$3" oid="$4" sid="$5" st ptree rq tmp
  _order_validation_enabled "$proj" \
    || die validation "projeto sem 'validation:' no .maestro.yaml — não há o que validar" \
         "declare a chave validation: no .maestro.yaml do projeto dono (ordem 050)" 1
  st=$(_order_status "$proj" "$wproj" "$of")
  case "$st" in
    provada) ;;
    em_validacao) printf 'ordem %s já está em validação — aguarda o recibo validation-%s no ledger\n' "$oid" "$((10#$oid))"; return 0 ;;
    validada) printf 'ordem %s já está validada neste tip\n' "$oid"; return 0 ;;
    reprovada)
      die validation "ordem $oid está 'reprovada' neste tip — é REPARO, não pedido novo" \
        "corrija, prove no novo tip (maestro evidence --record --label order-$((10#$oid)) -- <suíte>) e peça --validate de novo" 1 ;;
    *) die validation "ordem $oid está '$st', não 'provada'" \
         "validação exige a prova local verde no tip do branch" 1 ;;
  esac
  ptree=$(_order_proof_tree "$proj" "$wproj" "$of")
  [[ -n "$ptree" && "$ptree" != "desconhecida" ]] || die validation "ordem $oid não tem árvore provada legível" "" 1
  rq=$(_order_validation_request_file "$proj" "$oid")
  mkdir -p "${rq%/*}" 2>/dev/null || die env "não consigo criar ${rq%/*}" "cheque permissões" 2
  tmp="$rq.tmp.$$"
  { printf 'schema=maestro-order-validation-request-v1\n'
    printf 'id=%s\ntree=%s\nrequested_at=%s\nrequested_session=%s\n' \
      "$((10#$oid))" "$ptree" "$(date -Iseconds)" "${sid:-desconhecido}"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$rq" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; die env "ordem $oid: falha ao gravar o pedido de validação (~/.maestro/order-state)" "rode --validate de novo" 2; }
  log_event order_validate ${sid:+session_id="$sid"} n="$((10#$oid))"
  printf 'ordem %s: validação PEDIDA — árvore %s; em_validacao até o recibo validation-%s (verde = validada, vermelho = reprovada)\n' \
    "$oid" "${ptree:0:12}" "$((10#$oid))"
}
