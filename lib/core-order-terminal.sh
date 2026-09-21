#!/usr/bin/env bash
# maestro lib/core-order-terminal.sh — ordem 021 (DATA_MODEL §9 v1.18),
# extraído de lib/core-order-state.sh na ordem 036 para não cruzar o teto de
# `oversized-file` (400 linhas) — mesmo motivo medido das extrações da
# ordem 014/022: o registro de estado TERMINAL fora da árvore
# (`~/.maestro/order-state/`) só conversa com `maestro_order_state_file`
# (hooks/lib/project-state.sh) e com o arquivo da ordem, grupo coeso o
# bastante pra ter arquivo próprio.
#
# Sourced por lib/core-order-state.sh (`_order_workproject_lib_load` já
# carrega os dois módulos irmãos — mesma chamada, molde de I-2), carregado NA
# HORA: `_order_status`/`_order_terminal_field_*` são usados em quase todo
# predicado do núcleo, nunca sob demanda de uma flag do CLI. `bin/maestro`
# (congelado nesta ordem) não ganha linha nenhuma.
#
# SEMPRE chaveado pelo projeto DONO (R3, ordem 036/I1): `work_project` NUNCA
# move onde o registro terminal mora — corolário duro: se fosse chaveado pelo
# repo do TRABALHO, duas ordens homônimas em dois projetos (a 033 do Maestro
# e uma futura 033 do daemon, M4) escreveriam no MESMO registro. Proibido.
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
# lib/core-evidence.sh — schema versionado, tmp+mv atômico). SEMPRE chaveado
# pelo DONO (`proj`/`dono`) — R3, ordem 036/I1: `work_project` NUNCA muda
# onde o registro terminal mora.
_order_state_field() { # <arquivo-do-registro> <chave> → valor, ou vazio
  [[ -f "$1" ]] || return 0
  awk -F= -v k="$2" '$1 == k { print substr($0, length(k)+2); exit }' "$1" 2>/dev/null
}
_order_state_write() { # <proj> <arquivo-da-ordem> <outcome:aceita|absorvida> <k=v>... → grava o registro TERMINAL fora da árvore; rc 0/2
  local proj="$1" of="$2" outcome="$3" oid oidn sf tmp kv
  shift 3
  oid=$(_order_field "$of" id)
  oidn=$(_order_num "$oid") || return 2   # ordem 037: sem carimbo, id vem vazio — não grava registro para "ordem" nenhuma
  sf=$(maestro_order_state_file "$proj" "$oidn") || return 2
  [[ -n "$sf" ]] || return 2
  mkdir -p "${sf%/*}" 2>/dev/null || return 2
  tmp="$sf.tmp.$$"
  { printf 'schema=maestro-order-state-v1\n'
    printf 'id=%s\noutcome=%s\n' "$oidn" "$outcome"
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
# precedência de _order_status. SEMPRE chaveado pelo DONO (R3).
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
