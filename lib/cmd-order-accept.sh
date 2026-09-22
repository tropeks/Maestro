#!/usr/bin/env bash
# maestro lib/cmd-order-accept.sh — ordem 022, extraído de lib/cmd-order.sh
# para não cruzar o teto de `oversized-file` (400 linhas) — medido: o arquivo
# estava EXATAMENTE em 400, margem zero, e esta ordem já tinha de tocá-lo
# para o conserto do carimbo só-por-arquivo (ver DATA_MODEL.md §9, emenda
# v1.18). Mesmo molde de `lib/cmd-order-json.sh` (ordem 014, issue #18):
# responsabilidade distinta o bastante pra ter nome — aceite/absorção é um
# ADAPTADOR de ESCRITA sobre o mesmo núcleo (`core-order-state.sh`) que
# `--status`/`--status --json` já leem; puxar as duas ações de volta para
# `cmd-order.sh` engordaria o arquivo acima do teto sem nenhum motivo além de
# conveniência de edição.
#
# Sourced por lib/cmd-order.sh (`_order_accept_lib_load`, I-2) SOB DEMANDA —
# só quando a ação é `--accept` — DEPOIS de core-order-state.sh e
# hooks/lib/common.sh (já residentes no processo por essa altura: REPO_DIR,
# die(), log_event(), maestro_order_state_file/maestro_evidence_file,
# _order_field/_order_status/_order_state_write/_order_terminal_field_header/
# _order_terminal_field_appended/_order_default_branch/_order_proof_tree/
# _order_moved_since_accept/_order_intent_gate/_order_verif_gate/
# _order_stamp_intent/_order_work_project — todas já no escopo). Módulo
# ausente derruba SÓ o comando `--accept` (die env em
# `_order_accept_lib_load`), nunca o CLI; `--create`/`--list`/`--status`
# nunca carregam este arquivo.
#
# Convenção de core-order-state.sh/cmd-order.sh: proj/wproj/of/oid/sid
# chegam por parâmetro posicional, nessa ordem. ordem 036 (DATA_MODEL §9
# v1.22): `wproj` — R1/R2, projeto do TRABALHO — só entra onde a função
# precisa de git/ledger; `_order_default_branch`/o rótulo do recibo de
# `--absorbed-by main|master` CONTINUAM sobre `proj` (dono) de propósito —
# absorção por OUTRA ordem/branch é um conceito do MESMO projeto dono, fora
# do escopo desta ordem (§10 do desenho: "ordem cujo trabalho vive em DOIS
# repos" não inclui "absorvida por branch de um terceiro repo").

# --------------------------------- ação: --accept (ordem 022: cura o carimbo só-por-arquivo)
#
# Ordem 021 tirou o estado TERMINAL da árvore de trabalho (o registro em
# `~/.maestro/order-state`, `_order_state_write`/`_order_status`), mas só para
# quem foi carimbado DEPOIS do patch — ordem fechada antes continua com o
# carimbo SÓ no arquivo (`absorbed_by`/`accepted_at` no `.md`), sem o
# registro fora da árvore, e volta a morrer no próximo `git checkout`. Antes
# desta ordem, `--accept`/`--accept --absorbed-by` sobre uma ordem NESSE
# estado (terminal por arquivo, registro ausente) caíam direto no ramo
# "nada a fazer" — respondiam sem gravar nada, então a "migração" nunca
# acontecia de verdade.
#
# `_order_state_registrado` (abaixo) é o predicado que decide: o
# registro (`maestro_order_state_file`) existe? Se sim, é "nada a fazer" de
# VERDADE — a ordem já está curada ou nunca precisou (aceite/absorção
# normais sempre gravam o registro no mesmo passo que o carimbo, ver
# `_order_state_write` logo abaixo nesta função). Se não, é a lacuna que esta
# ordem fecha: os dois braços de --accept (absorve/aceita-sem-movimento)
# gravam o registro a partir do que já está no ARQUIVO — nunca do instante
# da cura — e SÓ isso; a cura não decide de novo quem absorveu, quando, nem
# contra qual árvore. Campo ausente no arquivo (carimbo manual antigo, ver
# DATA_MODEL §9 emenda v1.11 — `absorbed_by: main` carimbado à mão antes do
# CLI conhecer o campo) grava como `desconhecido`/`desconhecida` — mesmo
# sentinela que `accepted_tree`/`absorbed_tree` já usam em todo o arquivo
# para "não sei", nunca um valor inventado.
_order_state_registrado() { # <proj> <id> → rc 0 se o registro fora da árvore JÁ existe (nada a curar)
  local sf; sf=$(maestro_order_state_file "$1" "$2" 2>/dev/null)
  [[ -n "$sf" && -f "$sf" ]]
}
_order_accept_absorb_terminal() { # <proj> <arquivo> <id> <estado:aceita|absorvida> — ordem JÁ terminal: recusa ou cura-ou-no-op
  local proj="$1" of="$2" oid="$3" st="$4"
  case "$st" in
    aceita) die validation "ordem $oid já está aceita (provou o próprio trabalho)" \
              "--absorbed-by não se aplica a ordem já aceita" 1 ;;
    absorvida)
      if _order_state_registrado "$proj" "$oid"; then
        printf 'ordem %s já absorvida por %s — nada a fazer\n' "$oid" "$(_order_terminal_field_header "$proj" "$of" absorbed_by)"
      else
        _order_accept_cura_absorvida "$proj" "$of" "$oid"
      fi ;;
  esac
}
_order_accept_cura_absorvida() { # <proj> <arquivo> <id> — registro ausente, arquivo já 'absorvida': grava do ARQUIVO
  local proj="$1" of="$2" oid="$3" ab tr at se
  ab=$(_order_terminal_field_header "$proj" "$of" absorbed_by)
  tr=$(_order_terminal_field_header "$proj" "$of" absorbed_tree); [[ -n "$tr" ]] || tr="desconhecida"
  at=$(_order_terminal_field_header "$proj" "$of" absorbed_at);   [[ -n "$at" ]] || at="desconhecido"
  se=$(_order_terminal_field_header "$proj" "$of" absorbed_session); [[ -n "$se" ]] || se="desconhecido"
  _order_state_write "$proj" "$of" absorvida \
    "absorbed_by=$ab" "absorbed_tree=$tr" "absorbed_at=$at" "absorbed_session=$se" \
    || die env "ordem $oid: carimbo já é terminal no arquivo, mas a cura não conseguiu gravar o registro fora da árvore (~/.maestro/order-state) — rode --accept de novo" "" 2
  printf 'ordem %s: registro migrado do arquivo (carimbo era só-por-arquivo) — ABSORVIDA por %s, árvore %s\n' \
    "$oid" "$ab" "${tr:0:12}"
}
_order_accept_cura_aceita() { # <proj> <arquivo> <id> — registro ausente, arquivo já 'aceita' e nada moveu: grava do ARQUIVO
  local proj="$1" of="$2" oid="$3" at se tr
  at=$(_order_terminal_field_appended "$proj" "$of" accepted_at);      [[ -n "$at" ]] || at="desconhecido"
  se=$(_order_terminal_field_appended "$proj" "$of" accepted_session); [[ -n "$se" ]] || se="desconhecido"
  tr=$(_order_terminal_field_appended "$proj" "$of" accepted_tree);    [[ -n "$tr" ]] || tr="desconhecida"
  _order_state_write "$proj" "$of" aceita \
    "accepted_at=$at" "accepted_session=$se" "accepted_tree=$tr" \
    || die env "ordem $oid: carimbo já é terminal no arquivo, mas a cura não conseguiu gravar o registro fora da árvore (~/.maestro/order-state) — rode --accept de novo" "" 2
  printf 'ordem %s: registro migrado do arquivo (carimbo era só-por-arquivo) — ACEITA, árvore %s\n' "$oid" "${tr:0:12}"
}

_order_accept_absorb() { # <proj> <wproj> <odir> <arquivo> <id> <sid> <absorbed_by> — --accept --absorbed-by (issue #12)
  local proj="$1" wproj="$2" odir="$3" of="$4" oid="$5" sid="$6" absorbed_by="$7" st abs_tree="" stamp ts
  st=$(_order_status "$proj" "$wproj" "$of")
  case "$st" in
    aceita|absorvida) _order_accept_absorb_terminal "$proj" "$of" "$oid" "$st"; return 0 ;;
  esac
  [[ "$absorbed_by" != "$oid" && "$absorbed_by" != "$((10#$oid))" ]] \
    || die validation "ordem $oid não pode absorver a si mesma" "" 1
  if [[ "$absorbed_by" == "main" || "$absorbed_by" == "master" ]]; then
    # NetForge: 'main'/'master' são os DOIS apelidos pro branch padrão real.
    # ordem 036: absorção pelo branch padrão continua sobre `proj` (dono) —
    # não é o trabalho cross-repo que esta ordem endereça (ver nota no topo).
    local def_br; def_br=$(_order_default_branch "$proj")
    git -C "$proj" rev-parse --verify --quiet "$def_br" >/dev/null 2>&1 \
      || die validation "branch padrão do repo ('$def_br') não existe" "" 1
    local m_tip m_ef m_ew=""
    m_tip=$(git -C "$proj" rev-parse --verify --quiet "$def_br^{tree}" 2>/dev/null)
    m_ef=$(maestro_evidence_file "$proj" "$def_br" 2>/dev/null)
    if [[ -n "$m_ef" && -f "$m_ef" ]] && grep -q '^exit=0$' "$m_ef" 2>/dev/null; then
      m_ew=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$m_ef" 2>/dev/null)
    fi
    [[ -n "$m_ew" && -n "$m_tip" && "$m_ew" == "$m_tip" ]] \
      || die validation "branch padrão '$def_br' não tem recibo válido (label '$def_br') no conteúdo ATUAL" \
           "grave no tip do $def_br: maestro evidence --record --label $def_br -- <suíte>" 1
    abs_tree="$m_tip"
    absorbed_by="$def_br"   # carimbo grava o branch REAL, não o apelido digitado
  elif [[ "$absorbed_by" =~ ^[0-9]{1,3}$ ]]; then
    local m_oid m_of m_st m_wproj
    m_oid=$(printf '%03d' "$((10#$absorbed_by))")
    m_of=$(ls "$odir/$m_oid"-*.md "$odir/$m_oid.md" 2>/dev/null | head -1 || true)
    [[ -n "$m_of" && -f "$m_of" ]] || die validation "ordem absorvente $absorbed_by não existe" "maestro order --list" 1
    m_wproj=$(_order_work_project "$proj" "$m_of")   # ordem 036: a ABSORVENTE pode ter o SEU PRÓPRIO work_project
    m_st=$(_order_status "$proj" "$m_wproj" "$m_of")
    case "$m_st" in
      provada) abs_tree=$(_order_proof_tree "$proj" "$m_wproj" "$m_of") ;;
      aceita)  abs_tree=$(_order_terminal_field_appended "$proj" "$m_of" accepted_tree) ;;
      *) die validation "ordem $absorbed_by está '$m_st', não 'provada' nem 'aceita'" \
           "a absorvente tem de provar o PRÓPRIO trabalho antes de absorver outra — prove $absorbed_by: maestro evidence --record --label order-$((10#$absorbed_by)) -- <suíte>" 1 ;;
    esac
    [[ -n "$abs_tree" && "$abs_tree" != "desconhecida" ]] || die validation "ordem $absorbed_by não tem árvore provada legível" "" 1
  else
    die validation "--absorbed-by exige 'main'/'master' (branch padrão) ou o id numérico (1-3 dígitos) de uma ordem" "" 1
  fi
  ts=$(date -Iseconds)
  stamp=$(printf 'absorbed_by: %s\nabsorbed_tree: %s\nabsorbed_at: %s\nabsorbed_session: %s' \
    "$absorbed_by" "$abs_tree" "$ts" "${sid:-desconhecido}")
  awk -v ins="$stamp" '!done && $0 == "-->" { print ins; done=1 } { print }' "$of" > "$of.tmp.$$" \
    && mv -f "$of.tmp.$$" "$of" || { rm -f "$of.tmp.$$" 2>/dev/null; die env "falha ao gravar $of" "" 2; }
  # ordem 021: registro é a FONTE; falha aqui não degrada — die e retry.
  _order_state_write "$proj" "$of" absorvida \
    "absorbed_by=$absorbed_by" "absorbed_tree=$abs_tree" "absorbed_at=$ts" "absorbed_session=${sid:-desconhecido}" \
    || die env "ordem $oid: carimbo gravado no arquivo mas falhou no registro fora da árvore (~/.maestro/order-state) — rode --accept de novo" "" 2
  log_event order_accept ${sid:+session_id="$sid"} n="$((10#$oid))"
  log_event delegation phase=accepted ${sid:+session_id="$sid"} n="$((10#$oid))"
  printf 'ordem %s ABSORVIDA por %s — árvore %s; estado terminal, DISTINTO de aceita (esta ordem não provou o próprio trabalho)\n' \
    "$oid" "$absorbed_by" "${abs_tree:0:12}"
}
# ------------------------------------------ ordem 041: aceite por identidade
#
# `MAESTRO_ACCEPT_PROOF` ("v1:<sujeito>:<assinatura b64url>", envelope FIXADO
# em lib/core-order-accept-proof.sh) chega ao `--accept` pelo mesmo canal que
# `--session` — variável de ambiente, não flag (quem assina é o daemon, não
# quem digita o comando). `_order_accept_session_resolve` decide o que vai em
# `accepted_session` e que campos extras (se algum) entram no registro
# terminal — UM lugar só, reusado pelos dois braços de `_order_accept_own`
# (aceite novo e reaceite pós-S-1806) para não duplicar a regra.
_order_accept_session_resolve() { # <proj> <oid> <ptree> <sid> → stdout "sessão<TAB>kv extra (pode vir vazio)"; morre (validation) se REQUIRE ligado e a prova não bater
  local proj="$1" oid="$2" ptree="$3" sid="$4" id3 envelope gate_out subj parsed kv=""
  id3=$(printf '%03d' "$((10#$oid))")
  envelope="${MAESTRO_ACCEPT_PROOF:-}"
  if _order_accept_require_proof "$proj"; then
    # REQUIRE ligado: as DUAS portas (comando E leitura, decisão do desenho)
    # — aqui é a do comando. Recusa fail-closed em toda camada (prova
    # ausente, envelope malformado, sujeito fora do conjunto, base64url
    # corrompido, chave pública/openssl ausentes, e — até o vetor canônico
    # chegar — SEMPRE, porque _order_accept_proof_verify é hoje um coto que
    # recusa de propósito; ver o comentário lá).
    gate_out=$(_order_accept_proof_gate "$proj" "$id3" "${ptree:-desconhecida}" "$envelope") || \
      die validation "ordem $oid: aceite recusado — ${gate_out#recusa }" \
        "MAESTRO_ACCEPT_REQUIRE_PROOF está ligado para este projeto; --accept exige prova de identidade Ed25519 do Diretor (sujeito captain/spock)" 1
    subj="${gate_out#ok }"
    parsed=$(_order_accept_proof_parse "$envelope")
    kv="accept_proof_subject=$subj accept_proof_sig=${parsed#*$'\t'} accept_proof_version=v1"
    printf '%s\t%s' "$subj" "$kv"
    return 0
  fi
  # REQUIRE desligado: comportamento de hoje, byte a byte —
  # `accepted_session` continua o `--session` autodeclarado, e NADA aqui
  # morre. Captura OPORTUNISTA: se uma prova bem-formada veio mesmo assim (o
  # daemon já pode estar emitindo antes do projeto ligar a exigência), grava
  # os campos no registro para o dia em que o REQUIRE ligar — mas um
  # envelope malformado é apenas IGNORADO aqui, nunca motivo de morte
  # (REQUIRE desligado nunca recusa).
  if [[ -n "$envelope" ]]; then
    parsed=$(_order_accept_proof_parse "$envelope" 2>/dev/null) && {
      subj="${parsed%%$'\t'*}"
      _order_accept_proof_subject_ok "$subj" \
        && kv="accept_proof_subject=$subj accept_proof_sig=${parsed#*$'\t'} accept_proof_version=v1"
    }
  fi
  printf '%s\t%s' "${sid:-desconhecido}" "$kv"
}

_order_accept_own() { # <proj> <wproj> <arquivo> <id> <sid> <intent_reviewed> — aceita/reaceita o PRÓPRIO trabalho
  local proj="$1" wproj="$2" of="$3" oid="$4" sid="$5" reviewed="$6" st ptree _mv ts
  st=$(_order_status "$proj" "$wproj" "$of")
  if [[ "$st" == "aceita" ]]; then
    _mv=$(_order_moved_since_accept "$proj" "$wproj" "$of")   # S-1806: reaceite é no-op se nada andou
    if [[ -z "$_mv" ]]; then
      if _order_state_registrado "$proj" "$oid"; then echo "ordem $oid já aceita"
      else _order_accept_cura_aceita "$proj" "$of" "$oid"; fi
      return 0
    fi
    _order_intent_gate "$proj" "$of" "$oid" "$reviewed"   # E22 — SEMPRE contra o INTENT do DONO (R3)
    ptree=$(_order_proof_tree "$proj" "$wproj" "$of")
    [[ -n "$ptree" ]] || die validation "ordem $oid andou depois do aceite e não tem prova do conteúdo atual" \
      "mudou fora do bookkeeping: ${_mv}— re-rode e regrave: maestro evidence --record --label order-$((10#$oid)) -- <suíte>" 1
    _order_verif_gate "$wproj" "$of" "$oid"   # E23b — SEMPRE contra o WPROJ (R1/R2)
    ts=$(date -Iseconds)
    local resolved sess kv kv_args=()
    resolved=$(_order_accept_session_resolve "$proj" "$oid" "$ptree" "$sid")
    sess="${resolved%%$'\t'*}"; kv="${resolved#*$'\t'}"
    [[ -n "$kv" ]] && read -ra kv_args <<<"$kv"
    printf 'accepted_at: %s\naccepted_session: %s\naccepted_tree: %s\n' \
      "$ts" "$sess" "$ptree" >> "$of"
    _order_state_write "$proj" "$of" aceita \
      "accepted_at=$ts" "accepted_session=$sess" "accepted_tree=$ptree" "${kv_args[@]}" \
      || die env "ordem $oid: carimbo gravado no arquivo mas falhou no registro fora da árvore (~/.maestro/order-state) — rode --accept de novo" "" 2
    _order_stamp_intent "$proj" "$of"
    log_event order_accept ${sid:+session_id="$sid"} n="$((10#$oid))"
    log_event delegation phase=accepted ${sid:+session_id="$sid"} n="$((10#$oid))"
    printf 'ordem %s REACEITA — o branch andou depois do aceite anterior (%s), e o conteúdo de agora tem prova própria\n' "$oid" "${_mv% }"
    return 0
  fi
  [[ "$st" == "provada" ]] || die validation "ordem $oid está '$st', não 'provada'" \
    "aceite exige prova mecânica no ledger (evidência verde no tip do branch)" 1
  _order_intent_gate "$proj" "$of" "$oid" "$reviewed"   # E22 — SEMPRE contra o INTENT do DONO (R3)
  _order_verif_gate "$wproj" "$of" "$oid"   # E23b — SEMPRE contra o WPROJ (R1/R2); S-1803: grava a árvore que a prova cobriu
  ptree=$(_order_proof_tree "$proj" "$wproj" "$of")
  ts=$(date -Iseconds)
  local resolved sess kv kv_args=()
  resolved=$(_order_accept_session_resolve "$proj" "$oid" "${ptree:-desconhecida}" "$sid")
  sess="${resolved%%$'\t'*}"; kv="${resolved#*$'\t'}"
  [[ -n "$kv" ]] && read -ra kv_args <<<"$kv"
  printf 'accepted_at: %s\naccepted_session: %s\naccepted_tree: %s\n' \
    "$ts" "$sess" "${ptree:-desconhecida}" >> "$of"
  _order_state_write "$proj" "$of" aceita \
    "accepted_at=$ts" "accepted_session=$sess" "accepted_tree=${ptree:-desconhecida}" "${kv_args[@]}" \
    || die env "ordem $oid: carimbo gravado no arquivo mas falhou no registro fora da árvore (~/.maestro/order-state) — rode --accept de novo" "" 2
  _order_stamp_intent "$proj" "$of"
  log_event order_accept ${sid:+session_id="$sid"} n="$((10#$oid))"
  log_event delegation phase=accepted ${sid:+session_id="$sid"} n="$((10#$oid))"
  printf 'ordem %s ACEITA — merge/integração fica a seu critério (o aceite não mescla nada)\n' "$oid"
}
