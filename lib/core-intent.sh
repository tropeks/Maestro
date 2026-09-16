#!/usr/bin/env bash
# maestro lib/core-intent.sh — E22/S-2201, extraído de bin/maestro na ordem
# 015 (E24 ordem C, docs/designs/e24-nucleo-e-adaptadores.md).
#
# DONO do formato do `.maestro/INTENT.md`: a direção do projeto vira ARTEFATO
# em vez de frase no prompt — viaja com o repo (como a ordem do E15), tem
# VERSÃO que só sobe com conteúdo, e é o número que as ordens citam. Seis
# seções obrigatórias; seção sem texto conta como AUSENTE — seção vazia não é
# direção, é intenção de escrever direção. O hash é do corpo SEM o carimbo:
# carimbar não é mudar o conteúdo, e sem isso `--bump` viraria contador de
# saves.
#
# Sourced por bin/maestro (via _intent_lib_load, I-2) DENTRO do mesmo
# processo — nenhum fork. `_intent_valid`/`_intent_version`/`_intent_file`/
# `_intent_body_hash` são chamados de FORA desta família (lib/cmd-order.sh,
# lib/core-order-state.sh, lib/cmd-order-json.sh — acoplamento mapeado na
# ordem 015): cada um desses chama `_intent_lib_load` antes de usar qualquer
# uma, mesma técnica de `_verif_lib_load`/`_ev_lib_load`.
#
# TRAVA DE CONTRATO (ordem 015): forma das seis seções, o carimbo (version/
# hash/ts/head) e a regra "hash é do corpo SEM o carimbo" não mudam aqui —
# outros projetos e o supervisor leem esse formato.

_intent_file() { printf '%s/.maestro/INTENT.md' "${1:-$PWD}"; }

# 8 hex do sha256 do corpo (tudo depois da linha `-->`). sha256sum é aceitável
# aqui: isto é CLI, não hot path — o session-start só lê `version:` com awk.
_intent_body_hash() { # <arquivo> → 8 hex ou vazio
  local h=""
  h=$(sed '1,/^-->$/d' "$1" 2>/dev/null | sha256sum 2>/dev/null | head -c 8) || h=""
  printf '%s' "$h"
  return 0
}

_intent_stamp_field() { # <arquivo> <chave> → valor do carimbo
  awk -F': ' -v k="$2" 'NR>20 || /^-->$/ { exit } $1 == k { print substr($0, length(k)+3); exit }' \
    "$1" 2>/dev/null || true
}

_intent_version() { # <arquivo> → inteiro ≥1 (normalizado) ou vazio
  local v=""
  [[ -f "$1" && -r "$1" ]] || { printf ''; return 0; }
  v=$(_intent_stamp_field "$1" version)
  if [[ "$v" =~ ^[0-9]{1,9}$ ]] && (( 10#$v >= 1 )); then printf '%s' "$((10#$v))"; fi
  return 0
}

# "<seção>\t<linhas de texto>" para as SEIS obrigatórias, na ordem de exigência.
# A ordem das seções DENTRO do arquivo é livre; a contagem ignora o carimbo e
# linhas em branco. `## ` é fronteira de seção; `### ` conta como texto.
_intent_sections() { # <arquivo>
  awk '
    BEGIN { n = split("Problema|Público|Resultado|Prioridades|Limites|Fora de escopo", req, "|"); body = 0; sec = "" }
    NR == 1 && $0 !~ /^<!-- maestro-intent/ { body = 1 }
    !body { if ($0 ~ /^-->$/) body = 1; next }
    /^## / { sec = substr($0, 4); sub(/[ \t]+$/, "", sec); next }
    { t = $0; gsub(/[ \t]/, "", t); if (t != "" && sec != "") cnt[sec]++ }
    END { for (i = 1; i <= n; i++) printf "%s\t%d\n", req[i], (req[i] in cnt ? cnt[req[i]] : 0) }
  ' "$1" 2>/dev/null || true
}

_intent_missing() { # <arquivo> → seções ausentes/vazias separadas por " · "
  local out="" name cnt
  while IFS=$'\t' read -r name cnt; do
    [[ -n "$name" ]] || continue
    (( cnt > 0 )) || out+="${out:+ · }$name"
  done < <(_intent_sections "$1")
  printf '%s' "$out"
  return 0
}

_intent_valid() { # <projeto> → rc 0 se há direção CITÁVEL (carimbo + 6 seções)
  local f; f=$(_intent_file "$1")
  [[ -f "$f" && -r "$f" ]] || return 1
  [[ -n "$(_intent_version "$f")" ]] || return 1
  [[ -z "$(_intent_missing "$f")" ]] || return 1
  return 0
}
