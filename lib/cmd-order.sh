#!/usr/bin/env bash
# maestro lib/cmd-order.sh — E15/S-1501/S-1502, extraído de bin/maestro no E24
# (adaptador; núcleo em lib/core-order-state.sh — ver
# docs/designs/e24-nucleo-e-adaptadores.md).
#
# `maestro order`: as 4 ações do CLI (--create/--list/--status/--accept) e o
# despacho de flags. A derivação de estado, verificação por área e o gate de
# direção vivem em core-order-state.sh (sourced ANTES deste arquivo, mesmo
# processo, via _order_lib_load — I-2). Executor não fecha a própria ordem;
# o diretor assina.
#
# Convenção (E24): nenhuma função fecha sobre local de outra — `proj`/`of`/
# `oid`/`sid`/`odir` chegam SEMPRE por parâmetro posicional, nessa ordem;
# função pura não recebe `proj`. `_order_action_*` (as ações do CLI) é a
# exceção declarada ao teto de 5 parâmetros: cada uma espelha 1:1 as flags
# do comando — sacola genérica esconderia o contrato.

# ------------------------------------------------------------- ação: --create
_order_slug() { # <título> → slug de arquivo/branch (minúsculo, [a-z0-9-], até 32)
  local slug; slug=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-' | head -c 32)
  slug="${slug%-}"; printf '%s' "${slug#-}"
}
_order_create_write() { # <proj> <oid> <título> <branch> <frozen> <extra> <doc> <sid> — grava, loga, imprime confirmação
  local proj="$1" oid="$2" title="$3" branch="$4" frozen="$5" extra="$6" odoc="$7" sid="$8"
  local of="$proj/.maestro/orders/$oid-$(_order_slug "$title").md" head_sha
  head_sha=$(git -C "$proj" rev-parse HEAD 2>/dev/null) || head_sha="none"
  local i_ver="" i_hash=""   # E22: ordem nasce citando a direção vigente; sem carimbo, sai avisando
  if _intent_valid "$proj"; then
    i_ver=$(_intent_version "$(_intent_file "$proj")")
    i_hash=$(_intent_body_hash "$(_intent_file "$proj")")
  fi
  local body; body=$(head -c 16384)
  {
    printf '<!-- maestro-order v1\n'
    printf 'id: %s\nts: %s\nepoch: %s\nhead: %s\n' "$oid" "$(date -Iseconds)" "$(maestro_now_epoch)" "$head_sha"
    printf 'branch: %s\n' "$branch"
    printf '%s' "$extra"
    [[ -n "$i_ver" ]]  && printf 'intent_version: %s\n' "$i_ver"
    [[ -n "$i_hash" ]] && printf 'intent_hash: %s\n' "$i_hash"
    printf 'author_session: %s\n' "${sid:-desconhecido}"
    printf -- '-->\n# Ordem %s — %s\n\n%s\n' "$oid" "$title" "$body"
    printf '\n## Contrato de execução\n'
    printf -- '- Trabalhe APENAS no branch `%s`; NUNCA no main/master.\n' "$branch"
    [[ -n "$frozen" ]] && printf -- '- Zonas CONGELADAS (não toque): %s\n' "$frozen"
    printf -- '- Prove com o ledger: `maestro evidence --record --label order-%s -- <suíte>` no tip do branch.\n' "$((10#$oid))"
    [[ -n "$i_ver" ]] && printf -- '- Direção vigente na criação: INTENT v%s (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.\n' "$i_ver"
    [[ -n "$odoc" ]] && printf -- '- Esta ordem é autorizada por `%s` — siga-o; se a entrega mudar o contrato, EMENDE o doc no mesmo changeset (o aceite confere o frescor).\n' "$odoc"
    printf -- '- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.\n'
    printf -- '- O aceite é do diretor: `maestro order --accept %s` (você não fecha a própria ordem).\n' "$oid"
  } > "$of.tmp.$$" && mv -f "$of.tmp.$$" "$of" \
    || { rm -f "$of.tmp.$$" 2>/dev/null; die env "falha ao gravar $of" "" 2; }
  log_event order_create ${sid:+session_id="$sid"} n="$((10#$oid))"
  printf 'ordem %s criada: %s\n  branch: %s\n  status: aberta (derivado — nada executado ainda)\n' "$oid" "$of" "$branch"
  if [[ -n "$i_ver" ]]; then
    printf '  direção: INTENT v%s carimbada na ordem\n' "$i_ver"
  else
    printf '  AVISO: ordem sem direção — %s\n' \
      "$([[ -f "$(_intent_file "$proj")" ]] && echo 'INTENT incompleto ou sem carimbo (maestro intent --check)' || echo 'não há .maestro/INTENT.md (maestro intent --init)')"
  fi
}
_order_action_create() { # <proj> <sid> <título> <branch> <frozen> <budget "steps:min:cents"> <doc>
  local proj="$1" sid="$2" title="$3" branch="$4" frozen="$5" odoc="$7"
  local b_steps="" b_min="" b_cents="" v extra="" odir="$proj/.maestro/orders" n next=1 f oid
  IFS=: read -r b_steps b_min b_cents <<<"$6"
  [[ -n "$title" ]] || die validation "--title obrigatório" "o título é o contrato em uma linha" 1
  [[ -t 0 ]] && die validation "corpo ausente" "passe objetivo/critérios/Ask-First via stdin (heredoc)" 1
  for v in "$b_steps" "$b_min" "$b_cents"; do
    [[ -z "$v" || "$v" =~ ^[0-9]{1,6}$ ]] || die validation "orçamento exige inteiros" "E14: passos/min/centavos" 1
  done
  mkdir -p "$odir" 2>/dev/null || die env "não consigo criar $odir" "cheque permissões" 2
  shopt -s nullglob
  for f in "$odir"/[0-9][0-9][0-9]-*.md "$odir"/[0-9][0-9][0-9].md; do
    n="${f##*/}"; n="${n%%[-.]*}"; n=$((10#$n))
    (( n >= next )) && next=$(( n + 1 ))
  done
  shopt -u nullglob
  oid=$(printf '%03d' "$next")
  [[ -n "$branch" ]] || branch="order/$oid-$(_order_slug "$title")"
  [[ "$branch" =~ ^[A-Za-z0-9/_-]{1,80}$ ]] || die validation "branch inválido" "" 1
  [[ -n "$frozen" ]]  && extra+="frozen: $frozen"$'\n'
  [[ -n "$b_steps" ]] && extra+="budget_steps: $b_steps"$'\n'
  [[ -n "$b_min" ]]   && extra+="budget_min: $b_min"$'\n'
  [[ -n "$b_cents" ]] && extra+="budget_cents: $b_cents"$'\n'
  [[ -n "$odoc" ]]    && extra+="doc: $odoc"$'\n'
  _order_create_write "$proj" "$oid" "$title" "$branch" "$frozen" "$extra" "$odoc" "$sid"
}

# --------------------------------------------------------------- ação: --list
_order_action_list() { # <proj> <odir> — lista ordens com estado derivado
  [[ -d "$2" ]] || { echo "nenhuma ordem em $2 (crie: maestro order --create)"; return 0; }
  local proj="$1" odir="$2" f any=0 iv_now mark id _skip="" _seen=" " _dupe=""
  iv_now=$(_intent_version "$(_intent_file "$proj")")
  shopt -s nullglob
  for f in "$odir"/*.md; do
    if ! _order_valid_stamp "$f"; then   # issue #13: sem carimbo válido não é ordem
      _skip+="${_skip:+ }${f##*/}"
      continue
    fi
    any=1
    mark=""
    _order_intent_stale "$f" "$iv_now" && mark="  [direção mudou]"
    id=$(_order_field "$f" id)
    if [[ -n "$id" ]]; then
      [[ "$_seen" == *" $id "* ]] && _dupe+="${_dupe:+ }$id"
      _seen+="$id "
    fi
    printf '%s  [%s]%s  %s\n' "$id" "$(_order_status "$proj" "$f")" "$mark" \
      "$(grep -m1 '^# ' "$f" | sed 's/^# //')"
  done
  shopt -u nullglob
  (( any == 0 )) && echo "nenhuma ordem em $odir"
  [[ -n "$_dupe" ]] && printf 'ATENÇÃO: id de ordem duplicado — %s (dois arquivos com o mesmo id; renomeie/ajuste um)\n' "$_dupe"
  [[ -n "$_skip" ]] && printf '(ignorado(s) em %s sem carimbo de ordem: %s)\n' "$odir" "$_skip"
  return 0
}

# ------------------------------------------------------------- ação: --status
_order_show_context() { # <proj> <arquivo> → blocos direção(E22)/verif(E23b)/doc no boletim (vazio se não citado)
  local proj="$1" of="$2" _ov _ivn _ihn _oh _vrep _vl _vareas _od
  _ov=$(_order_field "$of" intent_version); _ivn=$(_intent_version "$(_intent_file "$proj")")
  if [[ -n "$_ov" ]]; then
    printf '  direção : v%s\n' "$_ov"
    if _order_intent_stale "$of" "$_ivn"; then
      printf '  ATENÇÃO: a direção mudou (v%s → v%s) depois desta ordem — revise o plano contra .maestro/INTENT.md\n' "$_ov" "$_ivn"
    elif [[ "$_ov" == "$_ivn" ]]; then
      _ihn=$(_intent_body_hash "$(_intent_file "$proj")"); _oh=$(_order_field "$of" intent_hash)
      [[ -n "$_oh" && -n "$_ihn" && "$_oh" != "$_ihn" ]] && \
        printf '           a direção foi editada sem bump (ainda v%s, conteúdo outro) — maestro intent --bump\n' "$_ov"
    fi
  fi
  _vareas=$(_order_verif_areas "$proj" "$of"); _vrep=$(_order_verif_report "$proj" "$of" "$_vareas")
  if [[ -n "$_vrep" ]]; then
    printf '  verif   : áreas %s\n' "$(printf '%s\n' "$_vareas" | tr '\n' ' ' | sed 's/ $//')"
    while IFS= read -r _vl; do [[ -n "$_vl" ]] && printf '            %s\n' "$_vl"; done <<<"$_vrep"
  fi
  _od=$(_order_field "$of" doc)
  if [[ -n "$_od" ]]; then
    printf '  doc     : %s — ' "$_od"
    cmd_docs --project "$proj" 2>/dev/null | grep -m1 "^$_od:" | sed "s|^$_od: ||" || echo "?"
  fi
}
_order_show_next() { # <proj> <arquivo> <id> <status> <branch> → bloco final ("próximo"/"encerrada")
  local proj="$1" of="$2" oid="$3" st="$4" br="$5"
  case "$st" in
    provada) echo '  próximo : revisar e aceitar — maestro order --accept '"$oid" ;;
    aceita)   # S-1805: avisa se o branch andou DEPOIS do aceite (compara CAMINHO, não árvore)
      local _at2 _tip2 _mudou=""
      _at2=$(grep '^accepted_tree: ' "$of" 2>/dev/null | tail -1 | sed 's/^accepted_tree: //') || true
      _tip2=$(git -C "$proj" rev-parse --verify --quiet "$br^{tree}" 2>/dev/null || true)
      if [[ -n "$_at2" && "$_at2" != "desconhecida" && -n "$_tip2" && "$_at2" != "$_tip2" ]]; then
        _mudou=$(git -C "$proj" diff --name-only "$_at2" "$_tip2" 2>/dev/null \
                 | grep -v '^\.maestro/orders/' | head -3 | tr '\n' ' ') || true
      fi
      if [[ -n "$_mudou" ]]; then
        printf '  ATENÇÃO: o branch andou DEPOIS do aceite — aceito %s, tip %s.\n' "${_at2:0:12}" "${_tip2:0:12}"
        printf '           mudou fora do bookkeeping: %s\n' "$_mudou"
        printf '           o que está no branch NÃO foi aceito; reaceite se for o caso.\n'
      else
        echo '  encerrada.'
      fi
      ;;
    absorvida)   # issue #12: terminal, DISTINTO de aceita
      printf '  encerrada por absorção — provada junto de %s; nada mais a executar aqui.\n' "$(_order_field "$of" absorbed_by)"
      ;;
    *) echo '  próximo : executor abre o branch, entrega e prova via ledger' ;;
  esac
}
_order_action_status() { # <proj> <arquivo> <id> — imprime o boletim completo de uma ordem
  local proj="$1" of="$2" oid="$3" st br _ptree=""
  st=$(_order_status "$proj" "$of"); br=$(_order_field "$of" branch)
  printf 'ordem %s: %s\n' "$oid" "$st"
  printf '  arquivo : %s\n  branch  : %s' "$of" "${br:-?}"
  git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1 \
    && printf ' (existe, tip %s)\n' "$(git -C "$proj" rev-parse --short=7 "$br" 2>/dev/null)" \
    || printf ' (não existe)\n'
  printf '  prova   : '
  [[ "$st" == "aceita" ]] && _ptree=$(grep '^accepted_tree: ' "$of" 2>/dev/null | tail -1 | sed 's/^accepted_tree: //') || true
  if [[ "$st" == "absorvida" ]]; then
    printf 'ABSORVIDA por %s — árvore %s (prova é da absorvente, não desta ordem)\n' \
      "$(_order_field "$of" absorbed_by)" "$(_order_field "$of" absorbed_tree | head -c 12)"
  elif [[ -n "$_ptree" && "$_ptree" != "desconhecida" ]]; then
    printf 'VÁLIDA na aceitação — árvore %s, recibo order-%s exit 0\n' "${_ptree:0:12}" "$((10#$oid))"
  else
    "$REPO_DIR/bin/maestro" evidence --label "$(_order_evidence_label "$proj" "$of")" --project "$proj" 2>/dev/null | head -1 || echo "?"
  fi
  _order_show_context "$proj" "$of"
  _order_show_next "$proj" "$of" "$oid" "$st" "$br"
}

# ------------------------------------------------------------- ação: --accept
_order_accept_absorb() { # <proj> <odir> <arquivo> <id> <sid> <absorbed_by> — --accept --absorbed-by (issue #12)
  local proj="$1" odir="$2" of="$3" oid="$4" sid="$5" absorbed_by="$6" st abs_tree="" stamp
  st=$(_order_status "$proj" "$of")
  case "$st" in
    aceita) die validation "ordem $oid já está aceita (provou o próprio trabalho)" \
              "--absorbed-by não se aplica a ordem já aceita" 1 ;;
    absorvida) printf 'ordem %s já absorvida por %s — nada a fazer\n' "$oid" "$(_order_field "$of" absorbed_by)"; return 0 ;;
  esac
  [[ "$absorbed_by" != "$oid" && "$absorbed_by" != "$((10#$oid))" ]] \
    || die validation "ordem $oid não pode absorver a si mesma" "" 1
  if [[ "$absorbed_by" == "main" ]]; then
    git -C "$proj" rev-parse --verify --quiet main >/dev/null 2>&1 \
      || die validation "'main' não existe neste repositório" "" 1
    local m_tip m_ef m_ew=""
    m_tip=$(git -C "$proj" rev-parse --verify --quiet "main^{tree}" 2>/dev/null)
    m_ef=$(maestro_evidence_file "$proj" main 2>/dev/null)
    if [[ -n "$m_ef" && -f "$m_ef" ]] && grep -q '^exit=0$' "$m_ef" 2>/dev/null; then
      m_ew=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$m_ef" 2>/dev/null)
    fi
    [[ -n "$m_ew" && -n "$m_tip" && "$m_ew" == "$m_tip" ]] \
      || die validation "main não tem recibo válido (label 'main') no conteúdo ATUAL" \
           "grave no tip do main: maestro evidence --record --label main -- <suíte>" 1
    abs_tree="$m_tip"
  elif [[ "$absorbed_by" =~ ^[0-9]{1,3}$ ]]; then
    local m_oid m_of m_st
    m_oid=$(printf '%03d' "$((10#$absorbed_by))")
    m_of=$(ls "$odir/$m_oid"-*.md "$odir/$m_oid.md" 2>/dev/null | head -1 || true)
    [[ -n "$m_of" && -f "$m_of" ]] || die validation "ordem absorvente $absorbed_by não existe" "maestro order --list" 1
    m_st=$(_order_status "$proj" "$m_of")
    case "$m_st" in
      provada) abs_tree=$(_order_proof_tree "$proj" "$m_of") ;;
      aceita)  abs_tree=$(grep '^accepted_tree: ' "$m_of" 2>/dev/null | tail -1 | sed 's/^accepted_tree: //') ;;
      *) die validation "ordem $absorbed_by está '$m_st', não 'provada' nem 'aceita'" \
           "a absorvente tem de provar o PRÓPRIO trabalho antes de absorver outra — prove $absorbed_by: maestro evidence --record --label order-$((10#$absorbed_by)) -- <suíte>" 1 ;;
    esac
    [[ -n "$abs_tree" && "$abs_tree" != "desconhecida" ]] || die validation "ordem $absorbed_by não tem árvore provada legível" "" 1
  else
    die validation "--absorbed-by exige 'main' ou o id numérico (1-3 dígitos) de uma ordem" "" 1
  fi
  stamp=$(printf 'absorbed_by: %s\nabsorbed_tree: %s\nabsorbed_at: %s\nabsorbed_session: %s' \
    "$absorbed_by" "$abs_tree" "$(date -Iseconds)" "${sid:-desconhecido}")
  awk -v ins="$stamp" '!done && $0 == "-->" { print ins; done=1 } { print }' "$of" > "$of.tmp.$$" \
    && mv -f "$of.tmp.$$" "$of" || { rm -f "$of.tmp.$$" 2>/dev/null; die env "falha ao gravar $of" "" 2; }
  log_event order_accept ${sid:+session_id="$sid"} n="$((10#$oid))"
  log_event delegation phase=accepted ${sid:+session_id="$sid"} n="$((10#$oid))"
  printf 'ordem %s ABSORVIDA por %s — árvore %s; estado terminal, DISTINTO de aceita (esta ordem não provou o próprio trabalho)\n' \
    "$oid" "$absorbed_by" "${abs_tree:0:12}"
}
_order_accept_own() { # <proj> <arquivo> <id> <sid> <intent_reviewed> — aceita/reaceita o PRÓPRIO trabalho
  local proj="$1" of="$2" oid="$3" sid="$4" reviewed="$5" st ptree _mv
  st=$(_order_status "$proj" "$of")
  if [[ "$st" == "aceita" ]]; then
    _mv=$(_order_moved_since_accept "$proj" "$of")   # S-1806: reaceite é no-op se nada andou
    if [[ -z "$_mv" ]]; then echo "ordem $oid já aceita"; return 0; fi
    _order_intent_gate "$proj" "$of" "$oid" "$reviewed"
    ptree=$(_order_proof_tree "$proj" "$of")
    [[ -n "$ptree" ]] || die validation "ordem $oid andou depois do aceite e não tem prova do conteúdo atual" \
      "mudou fora do bookkeeping: ${_mv}— re-rode e regrave: maestro evidence --record --label order-$((10#$oid)) -- <suíte>" 1
    _order_verif_gate "$proj" "$of" "$oid"
    printf 'accepted_at: %s\naccepted_session: %s\naccepted_tree: %s\n' \
      "$(date -Iseconds)" "${sid:-desconhecido}" "$ptree" >> "$of"
    _order_stamp_intent "$proj" "$of"
    log_event order_accept ${sid:+session_id="$sid"} n="$((10#$oid))"
    log_event delegation phase=accepted ${sid:+session_id="$sid"} n="$((10#$oid))"
    printf 'ordem %s REACEITA — o branch andou depois do aceite anterior (%s), e o conteúdo de agora tem prova própria\n' "$oid" "${_mv% }"
    return 0
  fi
  [[ "$st" == "provada" ]] || die validation "ordem $oid está '$st', não 'provada'" \
    "aceite exige prova mecânica no ledger (evidência verde no tip do branch)" 1
  _order_intent_gate "$proj" "$of" "$oid" "$reviewed"
  _order_verif_gate "$proj" "$of" "$oid"   # S-1803: grava a árvore que a prova cobriu, fato histórico
  ptree=$(_order_proof_tree "$proj" "$of")
  printf 'accepted_at: %s\naccepted_session: %s\naccepted_tree: %s\n' \
    "$(date -Iseconds)" "${sid:-desconhecido}" "${ptree:-desconhecida}" >> "$of"
  _order_stamp_intent "$proj" "$of"
  log_event order_accept ${sid:+session_id="$sid"} n="$((10#$oid))"
  log_event delegation phase=accepted ${sid:+session_id="$sid"} n="$((10#$oid))"
  printf 'ordem %s ACEITA — merge/integração fica a seu critério (o aceite não mescla nada)\n' "$oid"
}

# ------------------------------------------------------------------ despacho
cmd_order() { # S-1501/S-1502 — parseia flags e despacha para a ação (única fronteira que fala com o CLI)
  local action="" proj="${CLAUDE_PROJECT_DIR:-$PWD}" title="" branch="" frozen="" oid="" sid="" odoc=""
  local b_steps="" b_min="" b_cents="" intent_reviewed=0 absorbed_by=""
  while (( $# )); do
    case "$1" in
      --create)  action="create" ;;
      --list)    action="list" ;;
      --status)  action="status"; oid="${2:-}"; shift ;;
      --accept)  action="accept"; oid="${2:-}"; shift ;;
      --title)   title="${2:-}"; shift ;;
      --branch)  branch="${2:-}"; shift ;;
      --frozen)  frozen="${2:-}"; shift ;;
      --budget-steps) b_steps="${2:-}"; shift ;;
      --budget-min)   b_min="${2:-}"; shift ;;
      --budget-cents) b_cents="${2:-}"; shift ;;
      --doc)     odoc="${2:-}"; shift ;;
      --intent-reviewed) intent_reviewed=1 ;;   # E22
      --absorbed-by) absorbed_by="${2:-}"; shift ;;   # issue #12, usa-se COM --accept
      --session) sid="${2:-}"; shift ;;
      --project) proj="${2:-}"; shift ;;
      *) die validation "flag desconhecida '$1'" \
           "maestro order --create --title t [--branch b] [--frozen \"a/ b/\"] | --list | --status N | --accept N [--absorbed-by M|main] [--intent-reviewed]" 1 ;;
    esac
    shift
  done
  [[ -n "$action" ]] || action="list"
  local odir="$proj/.maestro/orders"

  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  maestro_verif_load   # E23b: AQUI — dentro de $(...) a lib morreria no subshell

  case "$action" in
    create) _order_action_create "$proj" "$sid" "$title" "$branch" "$frozen" "$b_steps:$b_min:$b_cents" "$odoc"; return 0 ;;
    list)   _order_action_list "$proj" "$odir"; return 0 ;;
  esac

  [[ "$oid" =~ ^[0-9]{1,3}$ ]] || die validation "id de ordem inválido" "use o NNN do --list" 1
  oid=$(printf '%03d' "$((10#$oid))")
  local of
  of=$(ls "$odir/$oid"-*.md "$odir/$oid.md" 2>/dev/null | head -1 || true)   # pipefail: glob vazio sai 2
  [[ -n "$of" && -f "$of" ]] || die validation "ordem $oid não existe" "maestro order --list" 1

  case "$action" in
    status) _order_action_status "$proj" "$of" "$oid" ;;
    accept)
      if [[ -n "$absorbed_by" ]]; then _order_accept_absorb "$proj" "$odir" "$of" "$oid" "$sid" "$absorbed_by"
      else _order_accept_own "$proj" "$of" "$oid" "$sid" "$intent_reviewed"; fi ;;
  esac
}
