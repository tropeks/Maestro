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
_order_default_branch() { # <proj> → branch padrão do repo, resolvido — SEM rede (NetForge: 'main' fixo recusava master)
  # Ordem de resolução: origin/HEAD (mais confiável quando existe) → config
  # LOCAL init.defaultBranch (só se o branch existir de verdade — config
  # desatualizada não vira sinal) → existência direta de main/master →
  # fallback literal 'main' (preserva a mensagem de hoje quando não há sinal
  # nenhum). `git remote show` fica de fora de propósito: chamaria a rede.
  local proj="$1" ref db
  ref=$(git -C "$proj" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    && [[ -n "$ref" ]] && { printf '%s' "${ref#origin/}"; return 0; }
  db=$(git -C "$proj" config --get init.defaultBranch 2>/dev/null)
  [[ -n "$db" ]] && git -C "$proj" rev-parse --verify --quiet "$db" >/dev/null 2>&1 \
    && { printf '%s' "$db"; return 0; }
  git -C "$proj" rev-parse --verify --quiet main   >/dev/null 2>&1 && { printf 'main';   return 0; }
  git -C "$proj" rev-parse --verify --quiet master >/dev/null 2>&1 && { printf 'master'; return 0; }
  printf 'main'
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
_order_evidence_frozen_tree() { # <proj> <arquivo> → wtree_after do recibo VÁLIDO (exit=0), sem comparar com tip
  # ordem 017: branch AUSENTE (nunca criado OU mergeado-e-apagado) não tem
  # tip vivo pra comparar — mesma situação de _order_deferred_tree (ordem
  # 013), por outro motivo (lá é "adiada não anda", aqui é "o branch sumiu").
  # Reusa a VARREDURA de _order_deferred_tree (candidatos + wtree_after),
  # mas não pode reusar a função: _order_deferred_tree não exige exit=0 (ali
  # o gate já é o campo deferred_by, a árvore é só para exibição) e aqui o
  # exit=0 É o gate — é o que decide 'provada' em vez de 'aberta', tem de
  # ser tão rígido quanto _order_evidence_match exige quando o branch existe.
  local proj="$1" f="$2" cand ev_f ev_w
  for cand in $(_order_evidence_candidates "$(_order_field "$f" id)"); do
    ev_f=$(maestro_evidence_file "$proj" "$cand" 2>/dev/null)
    [[ -f "$ev_f" ]] && grep -q '^exit=0$' "$ev_f" 2>/dev/null || continue
    ev_w=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$ev_f" 2>/dev/null)
    [[ -n "$ev_w" ]] && { printf '%s' "$ev_w"; return 0; }
  done
  return 0
}
# ------------------------------------ registro de estado TERMINAL, fora da árvore (ordem 021, DATA_MODEL §9 v1.18)
#
# Causa (medida no Agenda_Studio, issue da ordem 021): o carimbo terminal
# (`accepted_at`/`absorbed_by`) só existia como modificação NÃO COMMITADA no
# arquivo da ordem — `maestro order --accept` escreve na árvore de trabalho e
# para aí. Qualquer `git checkout`/`stash`/`reset` que restaure o HEAD apaga o
# carimbo em silêncio, e a ordem "reabre" sozinha. Mesma raiz da issue #36
# (o carimbo de aceite não atravessa worktree), um degrau abaixo (aqui não
# atravessa um checkout).
#
# O registro mora em `maestro_order_state_file` (hooks/lib/project-state.sh,
# ordem 021) — MESMA chave djb2 do brief/evidência, por ORDEM (id) em vez de
# rótulo livre. Formato chave=valor (mesmo parser/técnica de `_ev_write` em
# lib/core-evidence.sh — schema versionado, tmp+mv atômico).
_order_state_field() { # <arquivo-do-registro> <chave> → valor, ou vazio
  [[ -f "$1" ]] || return 0
  awk -F= -v k="$2" '$1 == k { print substr($0, length(k)+2); exit }' "$1" 2>/dev/null
}
_order_state_write() { # <proj> <arquivo-da-ordem> <outcome:aceita|absorvida> <k=v>... → grava o registro TERMINAL fora da árvore; rc 0/2
  local proj="$1" of="$2" outcome="$3" oid sf tmp kv
  shift 3
  oid=$(_order_field "$of" id)
  sf=$(maestro_order_state_file "$proj" "$oid") || return 2
  [[ -n "$sf" ]] || return 2
  mkdir -p "${sf%/*}" 2>/dev/null || return 2
  tmp="$sf.tmp.$$"
  { printf 'schema=maestro-order-state-v1\n'
    printf 'id=%s\noutcome=%s\n' "$((10#$oid))" "$outcome"
    for kv in "$@"; do printf '%s\n' "$kv"; done
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$sf" 2>/dev/null && return 0
  rm -f "$tmp" 2>/dev/null
  return 2
}
# Duas variantes de leitura — não é a MESMA função por CAMPO (v1.16 já
# firmou o precedente: irmã, não a mesma, quando o rigor difere). Aqui o que
# difere é ONDE cada campo vive no arquivo: `absorbed_*` no CABEÇALHO
# (_order_field, janela de 20 linhas — emenda v1.11); `accepted_*` ANEXADO ao
# FINAL, lido por grep+tail-1 SEM janela porque reaceite pode anexar mais de
# um carimbo e o ÚLTIMO vence (S-1806). Nos dois casos: registro (quando tem
# a chave) é a FONTE; arquivo é a conveniência de migração — MESMA
# precedência de _order_status.
_order_terminal_field_header() { # <proj> <arquivo> <chave> → valor de campo do CABEÇALHO (absorbed_*)
  local proj="$1" f="$2" k="$3" sf v
  sf=$(maestro_order_state_file "$proj" "$(_order_field "$f" id)" 2>/dev/null)
  if [[ -n "$sf" && -f "$sf" ]]; then
    v=$(_order_state_field "$sf" "$k")
    [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  fi
  _order_field "$f" "$k"
}
_order_terminal_field_appended() { # <proj> <arquivo> <chave> → valor de campo ANEXADO ao final (accepted_*, último vence)
  local proj="$1" f="$2" k="$3" sf v
  sf=$(maestro_order_state_file "$proj" "$(_order_field "$f" id)" 2>/dev/null)
  if [[ -n "$sf" && -f "$sf" ]]; then
    v=$(_order_state_field "$sf" "$k")
    [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  fi
  grep "^$k: " "$f" 2>/dev/null | tail -1 | sed "s/^$k: //"
}
_order_status() { # <proj> <arquivo> → status derivado no stdout
  local proj="$1" f="$2" br sf so
  # ordem 021: o registro fora da árvore é a FONTE do estado terminal.
  # Presente → DECIDE, mesmo que o arquivo tenha sido restaurado por um
  # checkout (é exatamente o defeito que esta ordem fecha). Ausente → o
  # carimbo do ARQUIVO ainda conta (migração: ordens carimbadas antes desta
  # ordem entrar, em qualquer projeto desta máquina, não podem "reabrir").
  sf=$(maestro_order_state_file "$proj" "$(_order_field "$f" id)" 2>/dev/null)
  if [[ -n "$sf" && -f "$sf" ]]; then
    so=$(_order_state_field "$sf" outcome)
    case "$so" in
      aceita)    printf 'aceita';    return 0 ;;
      absorvida) printf 'absorvida'; return 0 ;;
    esac
  fi
  grep -q '^accepted_at: ' "$f" 2>/dev/null && { printf 'aceita'; return 0; }
  [[ -n "$(_order_field "$f" absorbed_by)" ]] && { printf 'absorvida'; return 0; }   # issue #12
  [[ -n "$(_order_field "$f" deferred_by)" ]] && { printf 'adiada'; return 0; }   # ordem 013: suspensa, NÃO terminal — distinta de absorvida
  br=$(_order_field "$f" branch)
  if [[ -z "$br" ]] || ! git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1; then
    # ordem 017: branch ausente tem dois sentidos opostos — nunca criado
    # (nada começou) vs mergeado-e-apagado (tudo terminou). O recibo no
    # ledger é o que sobrevive aos dois e distingue: sem recibo, 'aberta'
    # continua certo; com recibo válido, é 'provada' (árvore CONGELADA do
    # recibo, decisão do diretor — não abre estado novo no enum).
    [[ -n "$(_order_evidence_frozen_tree "$proj" "$f")" ]] && { printf 'provada'; return 0; }
    printf 'aberta'; return 0
  fi
  [[ -n "$(_order_evidence_match "$proj" "$f")" ]] && { printf 'provada'; return 0; }
  printf 'em_execucao'
  return 0
}
_order_proof_tree() { # <proj> <arquivo> → árvore PROVADA (sha), vazio se não há prova
  local proj="$1" f="$2" m br
  m=$(_order_evidence_match "$proj" "$f")
  if [[ -n "$m" ]]; then printf '%s' "${m#* }"; return 0; fi
  # ordem 017: branch ausente não tem tip pra _order_evidence_match comparar
  # (ela devolve vazio de propósito, cedo, na linha 1) — cai para a árvore
  # CONGELADA do recibo, a MESMA que decidiu 'provada' em _order_status.
  br=$(_order_field "$f" branch)
  if [[ -z "$br" ]] || ! git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1; then
    printf '%s' "$(_order_evidence_frozen_tree "$proj" "$f")"
  fi
  return 0
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
  # ordem 021: accepted_tree pode só existir no registro fora da árvore, se
  # um checkout restaurou o arquivo depois do --accept — mesma precedência de
  # _order_status.
  at=$(_order_terminal_field_appended "$proj" "$f" accepted_tree) || true
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
