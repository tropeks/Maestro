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
#
# `maestro_verif_load` (lib/cmd-verify.sh, ordem 011) NÃO é mais residente:
# cmd_order chama `_verif_lib_load` antes, fora de `$(...)` — mesma nota já
# registrada abaixo sobre subshell, mesma técnica de `_order_lib_load`.
#
# `_intent_valid`/`_intent_version`/`_intent_file`/`_intent_body_hash`
# (lib/core-intent.sh, ordem 015) e `cmd_docs` (lib/cmd-docs.sh, ordem 015)
# também NÃO são residentes: cada função que os usa chama `_intent_lib_load`/
# `_docs_lib_load` antes, mesma técnica — acoplamento mapeado na ordem 015.

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
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
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
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
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
_order_show_context() { # <proj> <arquivo> [status] → blocos direção(E22)/verif(E23b)/doc no boletim (vazio se não citado)
  local proj="$1" of="$2" st="${3-}" _ov _ivn _ihn _oh _vrep _vl _vareas _od
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
  _docs_lib_load     # ordem 015: cmd_docs não é mais residente (bloco `doc` abaixo)
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
  # ordem 013: adiada não anda — verificação por área compara com o tip ATUAL
  # do branch, e é exatamente esse "vencer por mudança de árvore" que
  # trabalho suspenso não deve sofrer. Pula o bloco inteiro (não reprova).
  if [[ "$st" != "adiada" ]]; then
    _vareas=$(_order_verif_areas "$proj" "$of"); _vrep=$(_order_verif_report "$proj" "$of" "$_vareas")
    if [[ -n "$_vrep" ]]; then
      printf '  verif   : áreas %s\n' "$(printf '%s\n' "$_vareas" | tr '\n' ' ' | sed 's/ $//')"
      while IFS= read -r _vl; do [[ -n "$_vl" ]] && printf '            %s\n' "$_vl"; done <<<"$_vrep"
    fi
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
      # ordem 021: registro fora da árvore é a fonte; arquivo conta na migração.
      _at2=$(_order_terminal_field_appended "$proj" "$of" accepted_tree) || true
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
      printf '  encerrada por absorção — provada junto de %s; nada mais a executar aqui.\n' \
        "$(_order_terminal_field_header "$proj" "$of" absorbed_by)"
      ;;
    adiada)   # ordem 013: SUSPENSA, distinta de absorvida — não é terminal, volta
      printf '  suspensa por decisão de %s — não cobra aceite nem prova enquanto o campo existir.\n' "$(_order_field "$of" deferred_by)"
      printf '  próximo : retomar é remover deferred_by do cabeçalho e seguir o fluxo normal.\n'
      ;;
    *) echo '  próximo : executor abre o branch, entrega e prova via ledger' ;;
  esac
}
_order_action_status() { # <proj> <arquivo> <id> — imprime o boletim completo de uma ordem
  local proj="$1" of="$2" oid="$3" st br _ptree="" _idmis
  st=$(_order_status "$proj" "$of"); br=$(_order_field "$of" branch)
  printf 'ordem %s: %s\n' "$oid" "$st"
  printf '  arquivo : %s\n  branch  : %s' "$of" "${br:-?}"
  git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1 \
    && printf ' (existe, tip %s)\n' "$(git -C "$proj" rev-parse --short=7 "$br" 2>/dev/null)" \
    || printf ' (não existe)\n'
  # ordem 018: id/branch DIVERGEM — diagnóstico, não reparo; silêncio quando
  # coerente ou quando não dá pra extrair número do branch com confiança.
  _idmis=$(_order_identifier_mismatch "$of")
  [[ -n "$_idmis" ]] && printf '  ATENÇÃO: %s\n' "$_idmis"
  printf '  prova   : '
  # ordem 021: registro fora da árvore é a fonte; arquivo conta na migração.
  [[ "$st" == "aceita" ]] && _ptree=$(_order_terminal_field_appended "$proj" "$of" accepted_tree) || true
  if [[ "$st" == "absorvida" ]]; then
    printf 'ABSORVIDA por %s — árvore %s (prova é da absorvente, não desta ordem)\n' \
      "$(_order_terminal_field_header "$proj" "$of" absorbed_by)" \
      "$(_order_terminal_field_header "$proj" "$of" absorbed_tree | head -c 12)"
  elif [[ "$st" == "adiada" ]]; then
    # ordem 013: NUNCA "VENCIDA" — nem por idade nem por mudança de árvore.
    # A árvore mostrada é a que o recibo JÁ CONGELOU (_order_deferred_tree),
    # nunca comparada ao tip atual do branch (essa comparação é o que
    # "venceria" o recibo por mudança de árvore).
    local _dtree; _dtree=$(_order_deferred_tree "$proj" "$of")
    if [[ -n "$_dtree" ]]; then
      printf 'ADIADA por %s — prova congelada em %s (idade e mudança de árvore não se aplicam: trabalho adiado não anda)\n' \
        "$(_order_field "$of" deferred_by)" "${_dtree:0:12}"
    else
      printf 'ADIADA por %s — sem recibo gravado ainda (nada a congelar)\n' "$(_order_field "$of" deferred_by)"
    fi
  elif [[ -n "$_ptree" && "$_ptree" != "desconhecida" ]]; then
    printf 'VÁLIDA na aceitação — árvore %s, recibo order-%s exit 0\n' "${_ptree:0:12}" "$((10#$oid))"
  else
    "$REPO_DIR/bin/maestro" evidence --label "$(_order_evidence_label "$proj" "$of")" --project "$proj" 2>/dev/null | head -1 || echo "?"
  fi
  _order_show_context "$proj" "$of" "$st"
  _order_show_next "$proj" "$of" "$oid" "$st" "$br"
}

# ------------------------------------------ ação: --accept (ordem 022, módulo próprio)
#
# `_order_accept_absorb`/`_order_accept_own` moram em MÓDULO PRÓPRIO
# (lib/cmd-order-accept.sh), MESMO molde de lib/cmd-order-json.sh (ordem 014,
# issue #18): responsabilidade distinta o bastante pra ter nome — aceite/
# absorção é um ADAPTADOR de ESCRITA sobre o mesmo núcleo
# (core-order-state.sh) que --status/--status --json já leem. Motivo medido,
# não estético: este arquivo estava EXATAMENTE em 400 linhas — o teto do
# sensor `oversized-file` — margem zero, e a ordem 022 (curar o carimbo
# terminal só-por-arquivo, DATA_MODEL §9 emenda v1.18) precisava tocar as
# duas ações. Carregado SOB DEMANDA — só quando a ação é `--accept` — no
# molde de `_order_json_lib_load` logo abaixo: módulo ausente derruba SÓ este
# comando (I-2, `die env`), nunca o CLI inteiro; `--create`/`--list`/
# `--status` nunca pagam o custo de sourcing de um módulo que não usam.
_order_accept_lib_load() { # carrega lib/cmd-order-accept.sh — uma vez, degradando por comando (I-2)
  declare -f _order_accept_own >/dev/null 2>&1 && return 0
  if [[ -f "$REPO_DIR/lib/cmd-order-accept.sh" ]]; then
    # shellcheck source=lib/cmd-order-accept.sh
    source "$REPO_DIR/lib/cmd-order-accept.sh" && return 0
  fi
  die env "lib/cmd-order-accept.sh não encontrado em $REPO_DIR" \
    "reinstale o plugin (maestro doctor)" 2
}

# ----------------------------------------- ação: --status --json (ordem 014, issue #18)
#
# A emissão JSON mora em MÓDULO PRÓPRIO (lib/cmd-order-json.sh, vocabulário
# cmd- do E24: responsabilidade distinta o bastante pra ter nome — texto e
# JSON são dois ADAPTADORES do mesmo núcleo, não a mesma peça): puxar
# _order_action_status_json para cá engordaria este arquivo acima do teto de
# `oversized-file` (400 linhas) sem nenhum motivo além de conveniência de
# edição. Carregado SOB DEMANDA — só quando `--status` vem com `--json` — no
# molde de `_order_lib_load`/`_verif_lib_load`: módulo ausente derruba SÓ
# este comando (I-2, `die env`), nunca o CLI inteiro; `--status` SEM `--json`
# nunca paga o custo de sourcing de um módulo que não usa.
_order_json_lib_load() { # carrega lib/cmd-order-json.sh — uma vez, degradando por comando (I-2)
  declare -f _order_action_status_json >/dev/null 2>&1 && return 0
  if [[ -f "$REPO_DIR/lib/cmd-order-json.sh" ]]; then
    # shellcheck source=lib/cmd-order-json.sh
    source "$REPO_DIR/lib/cmd-order-json.sh" && return 0
  fi
  die env "lib/cmd-order-json.sh não encontrado em $REPO_DIR" \
    "reinstale o plugin (maestro doctor)" 2
}

# ------------------------------------------------------------------ despacho
cmd_order() { # S-1501/S-1502 — parseia flags e despacha para a ação (única fronteira que fala com o CLI)
  local action="" proj="${CLAUDE_PROJECT_DIR:-$PWD}" title="" branch="" frozen="" oid="" sid="" odoc=""
  local b_steps="" b_min="" b_cents="" intent_reviewed=0 absorbed_by="" json_out=0
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
      --json) json_out=1 ;;   # ordem 014/issue #18, só com --status: fonte única p/ o supervisor ler
      --session) sid="${2:-}"; shift ;;
      --project) proj="${2:-}"; shift ;;
      *) die validation "flag desconhecida '$1'" \
           "maestro order --create --title t [--branch b] [--frozen \"a/ b/\"] | --list | --status N [--json] | --accept N [--absorbed-by M|main] [--intent-reviewed]" 1 ;;
    esac
    shift
  done
  [[ -n "$action" ]] || action="list"
  local odir="$proj/.maestro/orders"

  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  _verif_lib_load   # ordem 011: maestro_verif_load não é mais residente
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
    status)
      if (( json_out == 1 )); then _order_json_lib_load; _order_action_status_json "$proj" "$of" "$oid"
      else _order_action_status "$proj" "$of" "$oid"; fi ;;
    accept)
      _order_accept_lib_load
      if [[ -n "$absorbed_by" ]]; then _order_accept_absorb "$proj" "$odir" "$of" "$oid" "$sid" "$absorbed_by"
      else _order_accept_own "$proj" "$of" "$oid" "$sid" "$intent_reviewed"; fi ;;
  esac
}
