#!/usr/bin/env bash
# maestro lib/core-order-entry.sh — ordem 059 (Etapa 1 do plano v2 da fábrica):
# o CONTRATO DE ENTRADA da ordem e o validador `maestro order --entry-check N`.
#
# Ordem boa entra com critério verificável, arquivo commitado no branch e
# dependências satisfeitas. O validador é máquina: sai 0 se e só se as cinco
# checagens passam; senão sai 1 com UMA linha de motivo por falha. Nada é
# enfileirado por ele (o despacho é a Etapa 2).
#
#   (a) o arquivo da ordem está COMMITADO no branch da ordem (e igual ao disco);
#   (b) o bloco `## Turno` é válido (reaproveita _turno_missing, ordem 046);
#   (c) `## Critérios de aceite` tem ao menos um critério e cada um traz
#       `[oráculo: <comando|teste: nome>]` ou `[humano]`;
#   (d) `depende_de:` (cabeçalho ou corpo) aponta ordens que existem e estão
#       `aceita` no estado derivado;
#   (e) a política do projeto existe: INTENT válido e `.maestro.yaml`.
#
# Compatibilidade: ordens antigas sem a seção só são reprovadas AQUI, com
# motivo; --list/--status não leem nada deste módulo. MAESTRO_ENTRY_REQUIRE
# (env > `entry_require:` do .maestro.yaml do dono > desligado, precedência da
# ordem 041) liga o esqueleto de critérios no `--create`; desligado, o
# `--create` sai byte a byte como antes.
#
# Sourced por lib/cmd-order.sh (sob demanda). Usa o núcleo já no escopo
# (_order_field, _order_status, _order_work_project, _turno_missing,
# _intent_valid). `proj` e `of` chegam por parâmetro posicional.

_order_entry_required() { # <dono> → rc 0 se MAESTRO_ENTRY_REQUIRE (env > yaml) está ligado
  local proj="$1" v=""
  if [[ -n "${MAESTRO_ENTRY_REQUIRE+x}" ]]; then v="$MAESTRO_ENTRY_REQUIRE"
  elif [[ -f "$proj/.maestro.yaml" ]]; then
    v=$(awk '/^entry_require:/ { sub(/^entry_require:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' "$proj/.maestro.yaml" 2>/dev/null) || v=""
  fi
  case "${v,,}" in 1 | true | yes | on) return 0 ;; *) return 1 ;; esac
}

_order_criteria_skeleton() { # esqueleto emitido por --create (flag ligada) quando o corpo não traz a seção
  printf '\n## Critérios de aceite\n'
  printf -- '- [oráculo: <comando que sai 0 ou 1 | teste: nome>] <o que esse critério prova>\n'
  printf -- '- [humano] <critério que depende de julgamento humano>\n'
}

_entry_criteria_lines() { # <arquivo> → itens (`- …`) da seção `## Critérios de aceite`
  awk '/^## Critérios de aceite/ { f = 1; next }
       /^## /                    { f = 0 }
       f && /^[[:space:]]*[-*][[:space:]]/ { print }' "$1" 2>/dev/null
}

_entry_criteria_bad() { # <arquivo> → itens sem oráculo nem [humano], um por linha (placeholder `<…>` conta como vazio)
  local l body o
  while IFS= read -r l; do
    body="${l#"${l%%[![:space:]]*}"}"; body="${body#?}"; body="${body#"${body%%[![:space:]]*}"}"
    if [[ "$body" =~ ^\[[Oo]ráculo:[[:space:]]*([^]]*)\] ]]; then
      o="${BASH_REMATCH[1]}"; o="${o//\`/}"; o="${o#"${o%%[![:space:]]*}"}"
      [[ -n "$o" && "$o" != "<"* ]] && continue
    elif [[ "$body" =~ ^\[[Hh]umano\] ]]; then continue; fi
    printf '%s\n' "${body:0:60}"
  done < <(_entry_criteria_lines "$1")
}

_entry_deps() { # <arquivo> → ids declarados em `depende_de:` (cabeçalho ou corpo), um por linha
  awk '/^depende_de:/ { sub(/^depende_de:[[:space:]]*/, ""); n = split($0, a, /[^0-9]+/); for (i = 1; i <= n; i++) if (a[i] != "") print a[i] }' "$1" 2>/dev/null
}

_entry_committed() { # <proj> <arquivo> → rc 0 se o arquivo está no branch da ordem, idêntico ao disco; senão motivo em stdout
  local proj="$1" of="$2" br rel
  br=$(_order_field "$of" branch); rel=".maestro/orders/${of##*/}"
  [[ -n "$br" ]] || { printf 'ordem sem branch: no cabeçalho'; return 1; }
  git -C "$proj" rev-parse --verify -q "refs/heads/$br" >/dev/null 2>&1 \
    || { printf 'branch %s da ordem não existe (crie e commite a ordem nele)' "$br"; return 1; }
  git -C "$proj" cat-file -e "refs/heads/$br:$rel" 2>/dev/null \
    || { printf '%s não está commitado no branch %s' "$rel" "$br"; return 1; }
  git -C "$proj" show "refs/heads/$br:$rel" 2>/dev/null | cmp -s - "$of" \
    || { printf '%s tem mudanças não commitadas em relação ao branch %s' "$rel" "$br"; return 1; }
  return 0
}

_entry_fail() { # <oid> <motivo> — uma linha por falha
  printf 'entry-check: ordem %s reprovada — %s\n' "$1" "$2"
}

_order_entry_check() { # <proj> <wproj> <arquivo> <id> — rc 0 passa; rc 1 com uma linha de motivo por falha
  local proj="$1" of="$3" oid="$4" n=0 r m d df dst
  # (a) commitado no branch da ordem
  r=$(_entry_committed "$proj" "$of") || { _entry_fail "$oid" "(a) $r"; n=$((n + 1)); }
  # (b) bloco Turno válido
  m=$(_turno_missing "$of" | tr '\n' ' ')
  [[ -z "${m// /}" ]] || { _entry_fail "$oid" "(b) bloco ## Turno inválido — falta/vazio: ${m% }"; n=$((n + 1)); }
  # (c) critérios com oráculo
  if [[ -z "$(_entry_criteria_lines "$of")" ]]; then
    _entry_fail "$oid" "(c) sem seção '## Critérios de aceite' com ao menos um critério"; n=$((n + 1))
  else
    while IFS= read -r m; do
      [[ -n "$m" ]] && { _entry_fail "$oid" "(c) critério sem oráculo nem [humano]: $m"; n=$((n + 1)); }
    done < <(_entry_criteria_bad "$of")
  fi
  # (d) dependências existem e estão aceitas
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    d=$(printf '%03d' "$((10#$d))")
    df=""; for m in "$proj/.maestro/orders/$d"-*.md "$proj/.maestro/orders/$d.md"; do [[ -f "$m" ]] && { df="$m"; break; }; done
    if [[ -z "$df" || ! -f "$df" ]] || ! _order_valid_stamp "$df"; then
      _entry_fail "$oid" "(d) dependência $d não existe"; n=$((n + 1)); continue
    fi
    dst=$(_order_status "$proj" "$(_order_work_project "$proj" "$df")" "$df")
    [[ "$dst" == aceita ]] || { _entry_fail "$oid" "(d) dependência $d está '$dst', não 'aceita'"; n=$((n + 1)); }
  done < <(_entry_deps "$of")
  # (e) política do projeto
  _intent_valid "$proj" || { _entry_fail "$oid" "(e) política ausente: INTENT inválido ou sem carimbo (maestro intent --check)"; n=$((n + 1)); }
  [[ -f "$proj/.maestro.yaml" ]] || { _entry_fail "$oid" "(e) política ausente: .maestro.yaml não existe"; n=$((n + 1)); }
  (( n == 0 )) || return 1
  printf 'entry-check: ordem %s passa nas 5 checagens (a-e)\n' "$oid"
}
