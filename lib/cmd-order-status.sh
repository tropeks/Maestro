#!/usr/bin/env bash
# maestro lib/cmd-order-status.sh — ordem 036 (DATA_MODEL §9 v1.22),
# extraído de lib/cmd-order.sh para não cruzar o teto de `oversized-file`
# (400 linhas) — mesmo motivo medido das extrações da ordem 014
# (lib/cmd-order-json.sh)/022 (lib/cmd-order-accept.sh): a RENDERIZAÇÃO em
# texto de `--status` (`_order_action_status`/`_order_show_context`/
# `_order_show_next`) é um ADAPTADOR de LEITURA sobre o mesmo núcleo
# (core-order-state.sh) que `--status --json` já lê — responsabilidade
# distinta o bastante pra ter nome próprio, mesmo corte que já separa texto
# de JSON.
#
# Sourced por lib/cmd-order.sh (`_order_status_lib_load`, MESMO molde de
# `_order_json_lib_load`/`_order_accept_lib_load`, I-2) SOB DEMANDA — só
# quando a ação é `--status` SEM `--json` — DEPOIS de core-order-state.sh e
# hooks/lib/common.sh (já residentes no processo por essa altura: REPO_DIR,
# die(), _order_field/_order_status/_order_evidence_match/_order_proof_tree/
# _order_deferred_tree/_order_evidence_label/_order_terminal_field_header/
# _order_terminal_field_appended/_order_identifier_mismatch/
# _order_work_project_note/_order_verif_areas/_order_verif_report,
# _intent_*/cmd_docs sob demanda — todas já no escopo). Módulo ausente
# derruba SÓ o comando `--status` texto (`die env`), nunca o CLI; `--create`/
# `--list`/`--status --json`/`--accept` nunca carregam este arquivo.
#
# Mesma convenção de core-order-state.sh/cmd-order.sh: `proj`/`wproj`/`of`/
# `oid` chegam por parâmetro posicional, nessa ordem (ordem 036: `wproj`
# logo depois de `proj`, R1/R2 do projeto do TRABALHO).
# ------------------------------------------------------------- ação: --status
_order_show_context() { # <proj> <wproj> <arquivo> [status] → blocos direção(E22)/verif(E23b)/doc no boletim (vazio se não citado)
  local proj="$1" wproj="$2" of="$3" st="${4-}" _ov _ivn _ihn _oh _vrep _vl _vareas _od
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
  # ordem 036: verificação por área é R1/R2 — roda contra $wproj.
  if [[ "$st" != "adiada" ]]; then
    _vareas=$(_order_verif_areas "$wproj" "$of"); _vrep=$(_order_verif_report "$wproj" "$of" "$_vareas")
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
_order_show_next() { # <proj> <wproj> <arquivo> <id> <status> <branch> → bloco final ("próximo"/"encerrada")
  local proj="$1" wproj="$2" of="$3" oid="$4" st="$5" br="$6"
  case "$st" in
    provada) echo '  próximo : revisar e aceitar — maestro order --accept '"$oid" ;;
    aceita)   # S-1805: avisa se o branch andou DEPOIS do aceite (compara CAMINHO, não árvore)
      local _at2 _tip2 _mudou=""
      # ordem 021: registro fora da árvore é a fonte; arquivo conta na migração.
      # ordem 036: accepted_tree é R3 (dono); o tip comparado é R1 (wproj).
      _at2=$(_order_terminal_field_appended "$proj" "$of" accepted_tree) || true
      _tip2=$(git -C "$wproj" rev-parse --verify --quiet "$br^{tree}" 2>/dev/null || true)
      if [[ -n "$_at2" && "$_at2" != "desconhecida" && -n "$_tip2" && "$_at2" != "$_tip2" ]]; then
        _mudou=$(git -C "$wproj" diff --name-only "$_at2" "$_tip2" 2>/dev/null \
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
_order_action_status() { # <proj> <wproj> <arquivo> <id> — imprime o boletim completo de uma ordem
  local proj="$1" wproj="$2" of="$3" oid="$4" st br _ptree="" _idmis
  st=$(_order_status "$proj" "$wproj" "$of"); br=$(_order_field "$of" branch)
  printf 'ordem %s: %s\n' "$oid" "$st"
  printf '  arquivo : %s\n  branch  : %s' "$of" "${br:-?}"
  git -C "$wproj" rev-parse --verify --quiet "$br" >/dev/null 2>&1 \
    && printf ' (existe, tip %s)\n' "$(git -C "$wproj" rev-parse --short=7 "$br" 2>/dev/null)" \
    || printf ' (não existe)\n'
  # ordem 018: id/branch DIVERGEM — diagnóstico, não reparo; silêncio quando
  # coerente ou quando não dá pra extrair número do branch com confiança.
  _idmis=$(_order_identifier_mismatch "$of")
  [[ -n "$_idmis" ]] && printf '  ATENÇÃO: %s\n' "$_idmis"
  # ordem 036: work_project resolvendo pro PRÓPRIO dono é typo — nota, não morte.
  local _wpnote; _wpnote=$(_order_work_project_note "$proj" "$of")
  [[ -n "$_wpnote" ]] && printf '  ATENÇÃO: %s\n' "$_wpnote"
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
    local _dtree; _dtree=$(_order_deferred_tree "$proj" "$wproj" "$of")
    if [[ -n "$_dtree" ]]; then
      printf 'ADIADA por %s — prova congelada em %s (idade e mudança de árvore não se aplicam: trabalho adiado não anda)\n' \
        "$(_order_field "$of" deferred_by)" "${_dtree:0:12}"
    else
      printf 'ADIADA por %s — sem recibo gravado ainda (nada a congelar)\n' "$(_order_field "$of" deferred_by)"
    fi
  elif [[ -n "$_ptree" && "$_ptree" != "desconhecida" ]]; then
    printf 'VÁLIDA na aceitação — árvore %s, recibo order-%s exit 0\n' "${_ptree:0:12}" "$((10#$oid))"
  elif [[ "$st" == "provada" ]]; then
    # ordem 036 (§5.5): sai da PRÓPRIA derivação, não pergunta a `maestro
    # evidence` — a pergunta do `evidence` ("a árvore de trabalho DESTE
    # checkout bate?") não é a pergunta da ordem ("o tip do branch bate?"),
    # e perguntar a outra produz boletim contraditório (provada/VENCIDA).
    local _prtree _prlabel
    _prtree=$(_order_proof_tree "$proj" "$wproj" "$of")
    _prlabel=$(_order_evidence_label "$proj" "$wproj" "$of")
    printf 'VÁLIDA no tip do branch — árvore %s, recibo %s exit 0\n' "${_prtree:0:12}" "$_prlabel"
  else
    "$REPO_DIR/bin/maestro" evidence --label "$(_order_evidence_label "$proj" "$wproj" "$of")" --project "$wproj" 2>/dev/null | head -1 || echo "?"
  fi
  _order_show_context "$proj" "$wproj" "$of" "$st"
  _order_show_next "$proj" "$wproj" "$of" "$oid" "$st" "$br"
}

