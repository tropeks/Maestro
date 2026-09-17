#!/usr/bin/env bash
# maestro lib/core-evidence.sh — E13/S-1301, extraído de bin/maestro na ordem
# 009 (E24, docs/designs/e24-nucleo-e-adaptadores.md).
#
# DONO do formato do recibo (maestro-evidence-v1). Antes desta ordem, o
# formato vivia só dentro de `cmd_evidence`, e `cmd_retro` reimplementava a
# leitura por conta própria (`grep -q '^exit=0$'`) — duplicação de
# conhecimento sem chamada de função nenhuma para denunciá-la. O recibo ganhou
# `load1m_x100`, `ncpu` e `inconclusive` na ordem 005; o `retro` não sabia de
# nenhum dos três. Esta lib existe para que ISSO não se repita: quem quiser
# saber algo de um recibo passa por aqui, nunca por regex própria.
#
# Sourced por bin/maestro (via _ev_lib_load, I-2) DENTRO do mesmo processo —
# nenhum fork. Convenção (firmada no lote do `order`, E24): parâmetro
# posicional, nenhuma função fecha sobre local de outra.

# ---------------------------------------------------------- leitura genérica
_ev_field() { # <arquivo> <campo> → valor bruto de "<campo>=..." (1ª ocorrência, janela de 20 linhas), vazio se ausente
  # Generico DE PROPÓSITO: não enumera nomes de campo. É o que faz o dono do
  # formato ser dono de verdade — campo novo (escrito por _ev_write) fica
  # visível a QUALQUER leitor que chame _ev_field, sem tocar o leitor.
  local f="$1" field="$2" v
  [[ -f "$f" && -r "$f" ]] || return 0
  v=$(awk -F= -v k="$field" 'NR>20{exit} $1==k{ sub(/^[^=]*=/, ""); print; exit }' "$f" 2>/dev/null) || v=""
  printf '%s' "$v"
  return 0
}

_ev_is_ok() { # <arquivo> → rc 0 se o recibo prova exit 0 (predicado de "passou" — único ponto que sabe disso)
  [[ "$(_ev_field "$1" exit)" == "0" ]]
}

# ------------------------------------------- leitura validada (veredito da evidence)
_ev_read_vars() { # <arquivo> → linhas "e_x=valor" (aspas simples), só campos validados — caller faz eval "$(...)"
  # Janela alargada de 12 para 20 na ordem 005 (issue #11): dá espaço para +8
  # campos futuros antes de precisar mexer aqui de novo.
  local f="$1"
  [[ -f "$f" && -r "$f" ]] || return 0
  awk -F= 'NR>20 { exit }
    /^epoch=/        { if ($2 ~ /^[0-9]+$/)          print "e_epoch=" $2 }
    /^exit=/         { if ($2 ~ /^[0-9]+$/)          print "e_exit="  $2 }
    /^cmd_hash=/     { if ($2 ~ /^([0-9a-f]{16}|none)$/) print "e_hash=\047" $2 "\047" }
    /^cmd_match=/    { if ($2 ~ /^(yes|no|free)$/)   print "e_match=\047" $2 "\047" }
    /^wtree_before=/ { if ($2 ~ /^([0-9a-f]{40}|none)$/) print "e_wb=\047" $2 "\047" }
    /^wtree_after=/  { if ($2 ~ /^([0-9a-f]{40}|none)$/) print "e_wa=\047" $2 "\047" }
    /^load1m_x100=/  { if ($2 ~ /^[0-9]+$/)          print "e_load=" $2 }
    /^ncpu=/         { if ($2 ~ /^[0-9]+$/)          print "e_ncpu=" $2 }
    /^inconclusive=/ { if ($2 ~ /^[0-9]+$/)          print "e_inc="  $2 }
    /^probe_ms=/     { if ($2 ~ /^[0-9]+$/)          print "e_probe=" $2 }' "$f" 2>/dev/null
  return 0
}

# ------------------------------------------------------------------- escrita
_ev_write() { # <arquivo> <label> <cmd_hash> <exit> <wtree_before> <wtree_after> <cmd_match> <load1m_x100> <ncpu> <inconclusive> [probe_ms] → grava (tmp+mv); rc 0/2
  local ef="$1" label="$2" cmd_hash="$3" rc="$4" w_before="$5" w_after="$6" \
        cmd_match="$7" load1m_x100="$8" ncpu="$9" inconclusive="${10}"
  # ordem 016 PR1: `probe_ms` é o 11º parâmetro, OPCIONAL na assinatura —
  # `${11:-0}`, não `${11}` nu. `set -u` está ligado em quem sourceia este
  # arquivo (ex.: tests/lib/test-evidence-ownership.sh, que chama _ev_write
  # direto com os 10 args de antes desta ordem, provando a POSSE do formato
  # sem depender de lib/cmd-evidence.sh); um `${11}` sem default MATA esse
  # chamador com "unbound variable" — quebra a garantia ADITIVA que esta
  # própria ordem promete (campo novo não pode quebrar chamador antigo).
  local probe_ms="${11:-0}"
  mkdir -p "${ef%/*}" 2>/dev/null || return 2
  local tmp="$ef.tmp.$$"
  {
    printf 'schema=maestro-evidence-v1\n'
    printf 'label=%s\nts=%s\nepoch=%s\n' "$label" "$(date -Iseconds)" "$(maestro_now_epoch)"
    printf 'cmd_hash=%s\nexit=%s\n' "$cmd_hash" "$rc"
    printf 'wtree_before=%s\nwtree_after=%s\n' "$w_before" "$w_after"
    printf 'cmd_match=%s\n' "$cmd_match"
    # issue #11 — campos ADITIVOS, no FIM (DATA_MODEL §8): campo novo nunca
    # empurra o que já existe para fora da janela do leitor (velho OU novo).
    printf 'load1m_x100=%s\nncpu=%s\ninconclusive=%s\n' "$load1m_x100" "$ncpu" "$inconclusive"
    # ordem 016 PR1: sonda de baseline (N invocações NO-OP do hook pelo
    # caminho do kill-switch, MAESTRO_OFF=1) — mede CAPACIDADE da máquina
    # nesta corrida, ao lado da CARGA que já era gravada acima. Também
    # ADITIVO, no FIM (mesma regra): nenhum campo existente sai da janela.
    printf 'probe_ms=%s\n' "$probe_ms"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$ef" 2>/dev/null && return 0
  rm -f "$tmp" 2>/dev/null
  return 2
}

# ------------------------------------------------------- cobertura do ledger
_ev_ledger_summary() { # <diretório de evidência> → "total<TAB>ok" — cobertura do ledger inteiro
  # Ordem 009: isto é o bloco de 9 linhas que morava dentro de `cmd_retro`
  # (bin/maestro:3034-3042) reimplementando `grep -q '^exit=0$'` por conta
  # própria. Agora "o que conta como recibo OK" tem UM dono (_ev_is_ok); o
  # retro só soma.
  local dir="$1" total=0 ok=0 evf
  shopt -s nullglob
  for evf in "$dir"/*; do
    total=$(( total + 1 ))
    _ev_is_ok "$evf" && ok=$(( ok + 1 ))
  done
  shopt -u nullglob
  printf '%s\t%s\n' "$total" "$ok"
  return 0
}
