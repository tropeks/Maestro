#!/usr/bin/env bash
# maestro lib/core-proof-verdict.sh — ordem 060: o veredito da prova tem UMA verdade.
#
# Antes: `evidence --check` (motivos próprios), `order --status` (_order_evidence_match) e
# `order --accept` (_order_verif_report/_order_verif_gate) liam o MESMO recibo com três
# critérios — um recibo VENCIDO no evidence podia sair `provada` no --status e ser aceito.
# Agora os três chamam maestro_proof_verdict e não mantêm critério próprio. O formato do
# recibo (maestro-evidence-v1) segue de lib/core-evidence.sh. Idade e carga NÃO entram aqui:
# a idade é só informação impressa (ordem 060, decisão do Diretor) e a carga só qualifica
# o texto (ordem 055). Conteúdo idêntico ao tip é VÁLIDO por mais velho que o recibo seja.
#
# Sourced no mesmo processo (core-order-state.sh, cmd-evidence.sh); nenhum fork novo além do
# wtree/maestro_tree_same que o veredito de conteúdo já exigia.

if ! declare -f _ev_read_vars >/dev/null 2>&1; then
  # shellcheck source=lib/core-evidence.sh
  [[ -f "$REPO_DIR/lib/core-evidence.sh" ]] && source "$REPO_DIR/lib/core-evidence.sh"
fi

_ev_decl() { # <proj> <rótulo> → comando declarado; `suite-N` (recibo por ordem) herda o de `suite` (ordem 048)
  local d; d=$(maestro_verif_cmd "$1" "$2") || d=""
  [[ -z "$d" && "$2" =~ ^([a-z][a-z0-9-]*)-[0-9]{1,3}$ ]] && d=$(maestro_verif_cmd "$1" "${BASH_REMATCH[1]}")
  printf '%s' "$d"
  return 0
}

maestro_proof_verdict() { # <recibo> <proj> <rótulo> [árvore_agora] → motivos (stdout), vazio = VÁLIDO; rc 2 = recibo ilegível
  # <árvore_agora>: com ela o conteúdo é comparado a ESSA árvore (o tip da ordem); vazio compara
  # ao conteúdo atual de <proj> (evidence --check). Rótulo = o pedido pelo chamador (decl herda de `suite`).
  local ef="$1" proj="$2" label="$3" w_now="${4:-}" reasons="" decl
  local e_epoch="" e_exit="" e_wb="" e_wa="" e_hash="" e_match="" e_load="" e_ncpu="" e_inc="" e_probe=""
  _verif_lib_load   # ordem 011: maestro_verif_load não é mais residente
  maestro_verif_load
  eval "$(_ev_read_vars "$ef")" 2>/dev/null || :
  [[ -n "$e_match" ]] || e_match="free"
  [[ -n "$e_epoch" && -n "$e_wa" ]] || { printf 'recibo ilegível'; return 2; }
  decl=$(_ev_decl "$proj" "$label")
  if [[ -z "$w_now" ]]; then
    w_now="none"
    [[ -x "$REPO_DIR/bin/maestro-wtree" ]] && w_now=$("$REPO_DIR/bin/maestro-wtree" "$proj" 2>/dev/null) || w_now="none"
  fi
  [[ "$e_wb" != "$e_wa" ]] && reasons+="${reasons:+; }árvore mudou durante a corrida"
  [[ "$w_now" == "none" || "$e_wa" == "none" ]] && reasons+="${reasons:+; }sem git para comparar conteúdo"
  [[ "$w_now" != "none" && "$e_wa" != "none" ]] && ! maestro_tree_same "$proj" "$w_now" "$e_wa" \
    && reasons+="${reasons:+; }conteúdo mudou desde a prova"
  [[ "$e_exit" != "0" ]] && reasons+="${reasons:+; }a execução provou FALHA (exit $e_exit)"
  if [[ "$e_match" == "no" ]]; then
    reasons+="${reasons:+; }comando diferente do declarado em .maestro.yaml"
  elif [[ -n "$decl" && -n "$e_hash" && "$e_hash" != "none" && "$e_hash" != "$(maestro_verif_hash "$decl")" ]]; then
    reasons+="${reasons:+; }comando do recibo ≠ commands.$label (.maestro.yaml)"
  fi
  printf '%s' "$reasons"
  return 0
}
