#!/usr/bin/env bash
# maestro lib/core-order-cold.sh — ordem 084 (v58 Etapa 1 + v56 estação "revisar"):
# a REVISÃO FRIA do plano e o recibo de DRIFT de épico.
#
# O gerente especifica e desenvolve a mesma ordem; o `--entry-check` (059) confere
# forma, não mérito; e o aceite é ordem a ordem. Aqui o revisor recebe um PACOTE
# montado por máquina (`--cold-bundle`: ordem, INTENT, brief, design doc, roteiro —
# nada de transcrito, relatório ou conversa) e o veredito vira RECIBO
# (`--cold-record`) que duas travas leem, atrás de MAESTRO_COLD_REVIEW_REQUIRE
# (env > `cold_review_require:` do .maestro.yaml do dono > desligado, ordem 041):
#   (f) --entry-check: `risco: alto` exige `plan-review-N` aprova com o sha256 do
#       arquivo da ordem igual ao de agora (plano mudou, revisão nova);
#   (g) --accept: ordem com `fecha_epico:` exige `drift-N` aprova.
# Desligada, nada disto lê nada: o comportamento é byte a byte o de hoje.
#
# Recibos moram FORA da árvore, no order-state (como o pedido de validação, 050):
# `<order-state>/<proj>-NNN.plan-review`, `.drift` e `.cold-rounds`. Nunca em
# evidence/ (o doctor só aceita schema maestro-evidence-v1 ali). O log recebe só
# metadado: jamais o texto dos achados.
#
# Sourced por lib/cmd-order.sh e lib/core-order-entry.sh/cmd-order-accept.sh (sob
# demanda). Usa o núcleo já no escopo (_order_field, _order_status, die, log_event,
# maestro_order_state_file, maestro_brief_file, _intent_file).

COLD_MAX_DEVOLVE=2

_order_cold_required() { # <dono> → rc 0 se MAESTRO_COLD_REVIEW_REQUIRE (env > yaml) está ligado
  local proj="$1" v=""
  if [[ -n "${MAESTRO_COLD_REVIEW_REQUIRE+x}" ]]; then v="$MAESTRO_COLD_REVIEW_REQUIRE"
  elif [[ -f "$proj/.maestro.yaml" ]]; then
    v=$(awk '/^cold_review_require:/ { sub(/^cold_review_require:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' "$proj/.maestro.yaml" 2>/dev/null) || v=""
  fi
  case "${v,,}" in 1 | true | yes | on) return 0 ;; *) return 1 ;; esac
}

_cold_turno_value() { # <arquivo> <rótulo> → valor do rótulo em `## Turno` (placeholder `<…>` = vazio)
  local v
  v=$(awk -v l="$2" '
    /^## Turno[[:space:]]*$/ { f=1; next }
    /^## /                   { f=0 }
    f { s=$0; sub(/^[[:space:]]*-?[[:space:]]*/, "", s)
        if (index(s, l ":") == 1) { v=substr(s, length(l) + 2); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); print v; exit } }' "$1" 2>/dev/null)
  [[ "$v" == "<"* ]] && v=""
  printf '%s' "$v"
}

_cold_risk() { # <arquivo> → alto|baixo (ausente = baixo; valor estranho = baixo)
  local v; v=$(_cold_turno_value "$1" risco); v="${v,,}"; v="${v//\`/}"
  [[ "$v" == alto ]] && printf 'alto' || printf 'baixo'
}

_cold_sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }   # <arquivo> → sha256

_cold_receipt() { # <dono> <oid> <plan-review|drift|cold-rounds> → caminho do recibo (fora da árvore)
  printf '%s.%s' "$(maestro_order_state_file "$1" "$2")" "$3"
}

_cold_field() { # <recibo> <chave> → valor
  awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$1" 2>/dev/null
}

_cold_count() { # <findings> <1|2|3> → quantos achados Pn (linha que ABRE com Pn, com marcador/negrito/colchete opcional)
  grep -Ec "^[[:space:]]*[-*#>]*[[:space:]]*\**\[?P$2([^0-9A-Za-z]|$)" "$1" 2>/dev/null || :
}

# ------------------------------------------------------------------ pacote
_cold_strip_order() { # <arquivo> → a ordem sem adendos de rodada nem relatórios (seções `## Adendo…` / `## Relatório…`)
  awk '/^## / { skip = ($0 ~ /^## ([Aa]dendo|[Rr]elat(ó|o)rio)/) } !skip { print }' "$1"
}

_cold_first_citing() { # <dono> <doc> → id (3 dígitos) da primeira ordem que cita o design doc em fecha_epico:, vazio se nenhuma
  local f d
  shopt -s nullglob
  for f in "$1"/.maestro/orders/*.md; do
    _order_valid_stamp "$f" || continue
    d=$(_cold_turno_value "$f" fecha_epico); d="${d//\`/}"
    [[ "$d" == "$2" ]] && { _order_field "$f" id; break; }
  done
  shopt -u nullglob
}

_cold_drift_section() { # <dono> <wproj> <arquivo> <doc> — git diff --stat e ordens aceitas desde a primeira que cita o doc
  local proj="$1" wproj="$2" of="$3" doc="$4" first f base fid st br
  first=$(_cold_first_citing "$proj" "$doc"); [[ -n "$first" ]] || first=$(_order_field "$of" id)
  printf '\n=== DRIFT: git diff --stat ===\n'
  f=$(ls "$proj/.maestro/orders/$first"-*.md 2>/dev/null | head -1)
  base=""
  [[ -n "$f" ]] && base=$(git -C "$wproj" log --diff-filter=A --format=%H -- ".maestro/orders/${f##*/}" 2>/dev/null | tail -1)
  [[ -n "$base" ]] && base="${base}^" || base=$(_order_default_branch "$proj" 2>/dev/null)
  br=$(_order_field "$of" branch)
  git -C "$wproj" rev-parse --verify -q "refs/heads/$br" >/dev/null 2>&1 || br=HEAD
  git -C "$wproj" diff --stat "$base" "$br" 2>/dev/null || printf '(diff indisponível)\n'
  printf '\n=== DRIFT: ordens aceitas desde a %s (primeira que cita %s) ===\n' "$first" "$doc"
  shopt -s nullglob
  for f in "$proj"/.maestro/orders/*.md; do
    _order_valid_stamp "$f" || continue
    fid=$(_order_field "$f" id)
    (( 10#$fid >= 10#$first )) || continue
    st=$(_order_status "$proj" "$(_order_work_project "$proj" "$f")" "$f")
    [[ "$st" == aceita ]] && printf '%s %s\n' "$fid" "$(sed -n 's/^# Ordem [0-9]* — //p' "$f" | head -1)"
  done
  shopt -u nullglob
}

_order_cold_bundle() { # <dono> <wproj> <arquivo> <id> <drift:0|1> — o pacote do revisor, só em stdout
  local proj="$1" wproj="$2" of="$3" drift="$5" doc="" df bf
  doc=$(_cold_turno_value "$of" fecha_epico); doc="${doc//\`/}"
  if [[ -n "$doc" ]]; then
    df="$proj/$doc"
    [[ -f "$df" ]] || die validation "design doc '$doc' (fecha_epico:) não existe em $proj" "corrija o caminho em fecha_epico:" 1
  fi
  (( drift == 1 )) && [[ -z "$doc" ]] \
    && die validation "--drift exige 'fecha_epico:' no bloco ## Turno da ordem" "declare o design doc do épico" 1
  printf '=== ORDEM ===\n'; _cold_strip_order "$of"
  printf '\n=== INTENT ===\n'; cat "$(_intent_file "$proj")" 2>/dev/null || printf '(INTENT ausente)\n'
  bf=$(maestro_brief_file "$proj" 2>/dev/null)
  printf '\n=== BRIEF ===\n'; { [[ -n "$bf" && -f "$bf" ]] && cat "$bf"; } || printf '(brief ausente)\n'
  [[ -n "$doc" ]] && { printf '\n=== DESIGN DOC (%s) ===\n' "$doc"; cat "$df"; }
  (( drift == 1 )) && _cold_drift_section "$proj" "$wproj" "$of" "$doc"
  printf '\n=== ROTEIRO ===\n'
  cat "$REPO_DIR/docs/contracts/revisao-fria.md" 2>/dev/null || printf '(roteiro docs/contracts/revisao-fria.md ausente)\n'
}

# ------------------------------------------------------------------ recibo
_order_cold_record() { # <dono> <arquivo> <id> <veredito> <findings> <drift:0|1> <sid>
  local proj="$1" of="$2" oid="$3" verdict="$4" ff="$5" drift="$6" sid="$7" kind rf cf n p1 p2 p3 dev=0 tmp
  case "$verdict" in aprova | devolve) ;; *) die validation "--verdict exige aprova|devolve" "maestro order --cold-record N --verdict aprova|devolve --findings <arquivo>" 1 ;; esac
  [[ -n "$ff" && -r "$ff" ]] || die validation "--findings exige um arquivo legível" "grave os achados do revisor num arquivo e passe o caminho" 1
  kind=plan-review; (( drift == 1 )) && kind=drift
  n=$((10#$oid)); cf=$(_cold_receipt "$proj" "$oid" cold-rounds)
  [[ -f "$cf" ]] && dev=$(_cold_field "$cf" devolve); [[ "$dev" =~ ^[0-9]+$ ]] || dev=0
  (( dev >= COLD_MAX_DEVOLVE )) \
    && die validation "ordem $oid já teve $dev devolve — a terceira revisão não é aceita: escala ao Diretor" "o Diretor decide; P3 vira lista no relatório, não rodada" 1
  p1=$(_cold_count "$ff" 1); p2=$(_cold_count "$ff" 2); p3=$(_cold_count "$ff" 3)
  [[ "$verdict" == aprova ]] && (( p1 > 0 )) \
    && die validation "veredito aprova com $p1 achado(s) P1 — P1 obriga devolve" "registre --verdict devolve" 1
  rf=$(_cold_receipt "$proj" "$oid" "$kind")
  mkdir -p "${rf%/*}" 2>/dev/null || die env "não consigo criar ${rf%/*}" "cheque permissões" 2
  tmp="$rf.tmp.$$"
  { printf 'schema=maestro-cold-review-v1\nlabel=%s-%s\n' "$kind" "$n"
    printf 'order_sha256=%s\nverdict=%s\np1=%s\np2=%s\np3=%s\n' "$(_cold_sha "$of")" "$verdict" "$p1" "$p2" "$p3"
    printf 'recorded_at=%s\nrecorded_session=%s\n' "$(date -Iseconds)" "${sid:-desconhecido}"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$rf" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; die env "ordem $oid: falha ao gravar o recibo $kind-$n (~/.maestro/order-state)" "rode --cold-record de novo" 2; }
  if [[ "$verdict" == devolve ]]; then
    printf 'schema=maestro-cold-rounds-v1\ndevolve=%s\n' "$((dev + 1))" > "$cf.tmp.$$" 2>/dev/null && mv -f "$cf.tmp.$$" "$cf" 2>/dev/null || rm -f "$cf.tmp.$$" 2>/dev/null
  fi
  log_event cold_record ${sid:+session_id="$sid"} n="$n" kind="$kind" verdict="$verdict" p1="$p1" p2="$p2" p3="$p3"
  printf 'ordem %s: recibo %s-%s gravado — %s (P1=%s P2=%s P3=%s)\n' "$oid" "$kind" "$n" "$verdict" "$p1" "$p2" "$p3"
}

# ------------------------------------------------------------------ travas
_cold_gate_plan_reason() { # <dono> <arquivo> <id> → motivo em stdout se a trava (f) reprova; vazio se passa
  local proj="$1" of="$2" oid="$3" rf v sha
  rf=$(_cold_receipt "$proj" "$oid" plan-review)
  [[ -f "$rf" ]] || { printf 'ordem de risco alto sem recibo plan-review-%s (revisão fria do plano)' "$((10#$oid))"; return 0; }
  v=$(_cold_field "$rf" verdict)
  [[ "$v" == aprova ]] || { printf 'recibo plan-review-%s está %s, não aprova' "$((10#$oid))" "${v:-ilegível}"; return 0; }
  sha=$(_cold_field "$rf" order_sha256)
  [[ -n "$sha" && "$sha" == "$(_cold_sha "$of")" ]] \
    || printf 'o plano mudou depois do recibo plan-review-%s (sha256 difere) — revisão nova' "$((10#$oid))"
}

_order_cold_entry_gate() { # <dono> <arquivo> <id> — trava (f) do --entry-check: imprime a linha do motivo, rc 1 se reprova
  local proj="$1" of="$2" oid="$3" r
  _order_cold_required "$proj" || return 0
  [[ "$(_cold_risk "$of")" == alto ]] || return 0
  r=$(_cold_gate_plan_reason "$proj" "$of" "$oid")
  [[ -z "$r" ]] && return 0
  printf 'entry-check: ordem %s reprovada — (f) %s\n' "$oid" "$r"
  return 1
}

_order_cold_accept_gate() { # <dono> <arquivo> <id> — trava (g) do --accept: morre sem drift-N aprova
  local proj="$1" of="$2" oid="$3" rf doc
  _order_cold_required "$proj" || return 0
  doc=$(_cold_turno_value "$of" fecha_epico); [[ -n "$doc" ]] || return 0
  rf=$(_cold_receipt "$proj" "$oid" drift)
  [[ -f "$rf" && "$(_cold_field "$rf" verdict)" == aprova ]] && return 0
  die validation "ordem $oid fecha o épico ($doc) e não tem recibo drift-$((10#$oid)) aprova" \
    "rode o revisor sobre maestro order --cold-bundle $oid --drift e registre: maestro order --cold-record $oid --drift --verdict aprova --findings <arquivo>" 1
}

# ------------------------------------------------------------------ CLI
_order_cold_cmd() { # --cold-bundle N [--drift] | --cold-record N --verdict v --findings f [--drift] — ordem 084
  local act="$1" oid="${2:-}" proj="${CLAUDE_PROJECT_DIR:-$PWD}" sid="" verdict="" ff="" drift=0 of wproj
  shift; [[ $# -gt 0 ]] && shift
  while (( $# )); do
    case "$1" in
      --drift) drift=1 ;;
      --verdict) verdict="${2:-}"; shift ;;
      --findings) ff="${2:-}"; shift ;;
      --session) sid="${2:-}"; shift ;;
      --project) proj="${2:-}"; shift ;;
      *) die validation "flag desconhecida '$1'" "maestro order --cold-bundle N [--drift] | --cold-record N --verdict aprova|devolve --findings <arquivo> [--drift]" 1 ;;
    esac
    shift
  done
  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  _verif_lib_load; maestro_verif_load; _intent_lib_load
  [[ "$oid" =~ ^[0-9]{1,3}$ ]] || die validation "id de ordem inválido" "use o NNN do --list" 1
  oid=$(printf '%03d' "$((10#$oid))")
  of=$(_order_resolve_stamped "$proj/.maestro/orders" "$oid")
  if [[ "$act" == "--cold-bundle" ]]; then
    wproj=$(_order_work_project "$proj" "$of")
    _order_cold_bundle "$proj" "$wproj" "$of" "$oid" "$drift"
  else
    _order_cold_record "$proj" "$of" "$oid" "$verdict" "$ff" "$drift" "$sid"
  fi
}
