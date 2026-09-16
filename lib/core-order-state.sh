#!/usr/bin/env bash
# maestro lib/core-order-state.sh — E15/S-1501/S-1502/E22/E23b, extraído de
# bin/maestro no E24 (núcleo, ver docs/designs/e24-nucleo-e-adaptadores.md).
#
# NÚCLEO de `maestro order`: leitura de campos/carimbo, estado DERIVADO
# (aberta→em_execucao→provada→aceita|absorvida — issue #12), verificação
# obrigatória por área (E23b) e o gate de direção (E22). Zero I/O de CLI —
# só predicados e leituras sobre o arquivo da ordem e o repo/ledger.
#
# Sourced por bin/maestro (_order_lib_load, I-2) ANTES de lib/cmd-order.sh, no
# MESMO processo — REPO_DIR, die(), maestro_evidence_file já no escopo.
# `maestro_verif_*`/`verif_base_ref`/`verif_record_hint` (lib/cmd-verify.sh,
# ordem 011) NÃO são mais residentes: _order_verif_areas chama
# `_verif_lib_load` antes de usá-las (mesma técnica de `_ev_lib_load`),
# acoplamento mapeado pela ordem A e resolvido aqui. `_intent_version`/
# `_intent_file` (lib/core-intent.sh, ordem 015) também NÃO são residentes:
# `_order_stamp_intent`/`_order_intent_gate` chamam `_intent_lib_load` antes
# de usá-las, mesma técnica.
#
# Convenção (firmada em _order_field antes de custar caro, E24): nenhuma
# função fecha sobre local de outra — `proj`/`of`/`oid` chegam SEMPRE por
# parâmetro posicional, nessa ordem; função pura não recebe `proj`.


# ---------------------------------------------- carimbo e campos (puro; janela = cabeçalho, 20 linhas)
_order_field() { # <arquivo> <chave> → valor do campo, ou vazio
  awk -F': ' -v k="$2" 'NR>20 { exit } $1 == k { print substr($0, length(k)+3); exit }' "$1" 2>/dev/null
}
_order_valid_stamp() { # <arquivo> → rc 0 se carimbo de ordem válido (issue #13: nem todo .md é ordem)
  awk -F': ' '
    NR>20 { exit }
    $0 ~ /^<!-- maestro-order v1/ { hdr=1 }
    $1 == "id" && $2 ~ /^[0-9]{1,3}$/ { idok=1 }
    END { exit !(hdr && idok) }
  ' "$1" 2>/dev/null
}
_order_intent_stale() { # <arquivo> <versão atual> → rc 0 se a direção andou depois da ordem (E22)
  local ov; ov=$(_order_field "$1" intent_version)
  [[ "$ov" =~ ^[0-9]{1,9}$ && "${2:-}" =~ ^[0-9]{1,9}$ ]] || return 1
  (( 10#$2 > 10#$ov ))
}
_order_evidence_candidates() { # <id> → as 2 variantes de rótulo (S-1802: canônica e acolchoada), uma por linha
  printf 'order-%s\n' "$((10#$1))"
  printf 'order-%03d\n' "$((10#$1))"
}

# --------------------------------------------------------- estado derivado (proj)
_order_evidence_match() { # <proj> <arquivo> → "rótulo árvore" do 1º candidato provado (S-1802), vazio se nenhum
  local proj="$1" f="$2" br cand ev_f ev_w tip_tree
  br=$(_order_field "$f" branch); [[ -n "$br" ]] || return 0
  tip_tree=$(git -C "$proj" rev-parse --verify --quiet "$br^{tree}" 2>/dev/null) || return 0
  for cand in $(_order_evidence_candidates "$(_order_field "$f" id)"); do
    ev_f=$(maestro_evidence_file "$proj" "$cand" 2>/dev/null)
    [[ -f "$ev_f" ]] && grep -q '^exit=0$' "$ev_f" 2>/dev/null || continue
    ev_w=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$ev_f" 2>/dev/null)
    [[ -n "$ev_w" && "$ev_w" == "$tip_tree" ]] && { printf '%s %s' "$cand" "$ev_w"; return 0; }
  done
  return 0
}
_order_status() { # <proj> <arquivo> → status derivado no stdout
  local proj="$1" f="$2" br
  grep -q '^accepted_at: ' "$f" 2>/dev/null && { printf 'aceita'; return 0; }
  [[ -n "$(_order_field "$f" absorbed_by)" ]] && { printf 'absorvida'; return 0; }   # issue #12
  [[ -n "$(_order_field "$f" deferred_by)" ]] && { printf 'adiada'; return 0; }   # ordem 013: suspensa, NÃO terminal — distinta de absorvida
  br=$(_order_field "$f" branch)
  if [[ -z "$br" ]] || ! git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1; then
    printf 'aberta'; return 0
  fi
  [[ -n "$(_order_evidence_match "$proj" "$f")" ]] && { printf 'provada'; return 0; }
  printf 'em_execucao'
  return 0
}
_order_proof_tree() { # <proj> <arquivo> → árvore PROVADA (sha), vazio se não há prova
  local m; m=$(_order_evidence_match "$1" "$2"); printf '%s' "${m#* }"
}
_order_deferred_tree() { # <proj> <arquivo> → wtree_after do recibo já gravado p/ esta ordem, vazio se nenhum
  # ordem 013: a árvore que a prova CONGELOU — nunca comparada ao tip atual
  # (isso é o que faria o recibo "vencer por mudança de árvore"; adiada não
  # anda, então não há comparação a fazer, só a árvore que ficou registrada).
  local proj="$1" f="$2" cand ev_f ew
  for cand in $(_order_evidence_candidates "$(_order_field "$f" id)"); do
    ev_f=$(maestro_evidence_file "$proj" "$cand" 2>/dev/null)
    [[ -f "$ev_f" ]] || continue
    ew=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$ev_f" 2>/dev/null)
    [[ -n "$ew" ]] && { printf '%s' "$ew"; return 0; }
  done
  return 0
}
_order_moved_since_accept() { # <proj> <arquivo> → caminhos mudados desde o aceite (S-1806; vazio = não andou)
  local proj="$1" f="$2" at tip br
  br=$(_order_field "$f" branch)
  at=$(grep '^accepted_tree: ' "$f" 2>/dev/null | tail -1 | sed 's/^accepted_tree: //') || true
  [[ -n "$at" && "$at" != "desconhecida" ]] || return 0
  tip=$(git -C "$proj" rev-parse --verify --quiet "$br^{tree}" 2>/dev/null || true)
  [[ -n "$tip" && "$at" != "$tip" ]] || return 0
  git -C "$proj" diff --name-only "$at" "$tip" 2>/dev/null \
    | grep -v '^\.maestro/orders/' | head -3 | tr '\n' ' ' || true
}
_order_evidence_label() { # <proj> <arquivo> → rótulo do recibo a EXIBIR (S-1804: mesma tolerância do status)
  local proj="$1" f="$2" m cand ev_f
  m=$(_order_evidence_match "$proj" "$f"); [[ -n "$m" ]] && { printf '%s' "${m%% *}"; return 0; }
  for cand in $(_order_evidence_candidates "$(_order_field "$f" id)"); do
    ev_f=$(maestro_evidence_file "$proj" "$cand" 2>/dev/null)
    [[ -f "$ev_f" ]] && { printf '%s' "$cand"; return 0; }
  done
  printf 'order-%s' "$((10#$(_order_field "$f" id)))"
}

# ------------------ verificação obrigatória por área (E23b): julga o TIP via recibo em arquivo, nunca ao vivo
_order_verif_areas() { # <proj> <arquivo> → áreas tocadas pelo branch (uma por linha)
  local proj="$1" f="$2" br base
  br=$(_order_field "$f" branch); [[ -n "$br" ]] || return 0
  git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1 || return 0
  _verif_lib_load   # ordem 011: maestro_verif_load não é mais residente
  maestro_verif_load
  base=$(verif_base_ref "$proj" "" "$br"); [[ -n "$base" ]] || return 0
  maestro_verif_touched "$proj" "$base" "$br"
  return 0
}
_order_verif_report() { # <proj> <arquivo> [áreas] → uma linha "rótulo: estado" por rótulo exigido
  local proj="$1" f="$2" areas="${3-}" labels lb tip br ef ev_w ev_m st
  [[ -n "$areas" || $# -ge 3 ]] || areas=$(_order_verif_areas "$proj" "$f")
  [[ -n "$areas" ]] || return 0
  # shellcheck disable=SC2086
  labels=$(maestro_verif_labels "$proj" $areas); [[ -n "$labels" ]] || return 0
  br=$(_order_field "$f" branch)
  tip=$(git -C "$proj" rev-parse --verify --quiet "$br^{tree}" 2>/dev/null) || tip=""
  for lb in $labels; do
    ef=$(maestro_evidence_file "$proj" "$lb" 2>/dev/null) || ef=""
    if [[ -z "$ef" || ! -f "$ef" || ! -r "$ef" ]]; then st='NENHUMA'
    elif ! grep -q '^exit=0$' "$ef" 2>/dev/null; then st='VENCIDA (a execução falhou)'
    else
      ev_w=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$ef" 2>/dev/null) || ev_w=""
      if [[ -z "$tip" || "$ev_w" != "$tip" ]]; then st='VENCIDA (não é o conteúdo do tip)'
      else
        ev_m=$(awk -F= '/^cmd_match=/ { print $2; exit }' "$ef" 2>/dev/null) || ev_m=""
        [[ "$ev_m" == "no" ]] && st='VENCIDA (comando ≠ o declarado)' || st='VÁLIDA'
      fi
    fi
    printf '%s: %s\n' "$lb" "$st"
  done
  return 0
}
_order_verif_gate() { # <proj> <arquivo> <id> — recusa (exit 1) o aceite sem o conjunto exigido
  local proj="$1" f="$2" id="$3" rep falta="" lb st
  rep=$(_order_verif_report "$proj" "$f"); [[ -n "$rep" ]] || return 0
  while IFS= read -r st; do
    [[ -n "$st" ]] || continue
    [[ "$st" == *": VÁLIDA" ]] && continue
    lb="${st%%:*}"
    falta+="  ${st} — $(verif_record_hint "$proj" "$lb")"$'\n'
  done <<<"$rep"
  [[ -n "$falta" ]] || return 0
  printf 'ordem %s toca área com verificação obrigatória e falta prova:\n%s' "$id" "$falta" >&2
  die validation "ordem $id sem o conjunto de verificações exigido pelo .maestro.yaml" \
    "rode os comandos acima NO TIP DO BRANCH e aceite de novo" 1
}

# --------------------------------------------------------------- direção (E22)
_order_stamp_intent() { # <proj> <arquivo> — grava sob QUAL direção o aceite foi dado
  local proj="$1" nv
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
  nv=$(_intent_version "$(_intent_file "$proj")")
  [[ -n "$nv" ]] && printf 'accepted_intent: %s\n' "$nv" >> "$2"
  return 0
}
_order_intent_gate() { # <proj> <arquivo> <id> <intent_reviewed> — aceite sob direção velha é decisão nova
  local proj="$1" f="$2" id="$3" reviewed="$4" nv ov
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
  nv=$(_intent_version "$(_intent_file "$proj")")
  _order_intent_stale "$f" "$nv" || return 0
  ov=$(_order_field "$f" intent_version)
  if (( reviewed == 1 )); then
    printf 'direção revisada pelo diretor: a ordem nasceu sob v%s, a direção está em v%s\n' "$ov" "$nv"
    return 0
  fi
  die validation "a direção mudou (v$ov → v$nv) depois da ordem $id" \
    "releia o plano contra .maestro/INTENT.md; se ele continua de pé, aceite com --intent-reviewed" 1
}
