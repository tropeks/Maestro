#!/usr/bin/env bash
# maestro lib/core-order-accept-proof.sh — ordem 041 (aceite por identidade,
# dívida de segurança sob docs/ENCERRAMENTO-v1.md §5), extraído para arquivo
# próprio pelo mesmo motivo medido das extrações da ordem 014/022/036: grupo
# coeso (envelope/predicados da prova de identidade do `--accept`) e o teto
# de `oversized-file` (400 linhas) já estava sem margem em core-order-state.sh.
#
# Sourced por `_order_workproject_lib_load` (lib/core-order-state.sh) — NA
# HORA, junto com core-order-workproject.sh/core-order-terminal.sh, porque
# `_order_status` (predicado usado por quase todo comando) precisa conferir
# a prova em toda leitura, não só quando a ação é `--accept`. lib/cmd-order-
# accept.sh (já sob demanda, só quando a ação É `--accept`) reusa as MESMAS
# funções para a gravação — um único lugar decide o que é "prova válida".
#
# ---------------------------------------------------------------------------
# VETOR CANÔNICO (2026-09-22): docs-ops/045/VETOR-CANONICO-prova-de-aceite.md
# do ponte-daemon, decisão do Diretor a partir da Ponte 01M34JJYS7ZDHH2HWM877
# PPQS7. Fecha os quatro pontos em que duas implementações corretas
# divergiriam sem ninguém notar:
#   (a) `id` no payload: SEMPRE 3 dígitos (`042`, nunca `42`) — repadronizado
#       NA HORA, venha o valor de onde vier (o cabeçalho grava `id: 042`, o
#       registro fora da árvore grava `id=42`; as DUAS fontes discordam no
#       disco HOJE — quem monta o payload sem repadronizar assina bytes
#       diferentes e falha sem motivo aparente. Ver `%03d` nos chamadores).
#   (b) assinatura: base64url SEM padding (`-`/`_`, sem `=`).
#   (c) payload: SEM newline final depois do sujeito.
#   (d) transporte: `MAESTRO_ACCEPT_PROOF = "v1:" + sujeito + ":" + assinatura`.
# `projeto` no payload é o NOME (basename do caminho real), não o caminho —
# mesma técnica de `_intent_action_init` (lib/cmd-intent.sh): o vetor usa
# `ponte-daemon`, que é justamente o basename do repo do daemon.
#
# `config/accept-proof.pub` nasce com a CHAVE DE TESTE do vetor (publicada de
# propósito no documento, para os dois lados fecharem o contrato) — NUNCA é a
# chave de produção, que ainda não existe. O comentário no próprio arquivo
# .pub diz isso em voz alta.

# ------------------------------------------------------- interruptor (por projeto, default OFF)
_order_accept_require_proof() { # <proj-dono> → rc 0 se MAESTRO_ACCEPT_REQUIRE_PROOF está LIGADO para este projeto
  # Precedência: env var (override explícito, útil em teste/CI) > chave
  # `accept_require_proof:` do .maestro.yaml do DONO (por projeto, como o
  # desenho pede) > default DESLIGADO — MESMA precedência de
  # `_habits_enabled_sensors` (lib/cmd-habits.sh), só que aqui é um booleano.
  local proj="$1" v yline
  if [[ -n "${MAESTRO_ACCEPT_REQUIRE_PROOF+x}" ]]; then
    v="$MAESTRO_ACCEPT_REQUIRE_PROOF"
  elif [[ -f "$proj/.maestro.yaml" ]]; then
    yline=$(awk '/^accept_require_proof:/ { sub(/^accept_require_proof:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' \
      "$proj/.maestro.yaml" 2>/dev/null) || yline=""
    v="$yline"
  else
    v=""
  fi
  case "${v,,}" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------------- âncora de confiança
_order_accept_proof_pubkey_file() { # → caminho da chave pública Ed25519 (âncora de confiança)
  # config/accept-proof.pub (PEM) — entra na DENY_SELF do gate (item 6 do
  # desenho): trocar a âncora deixa de ser edição comum. NÃO RESOLVE o
  # executor rodar com o MESMO uid do Diretor nesta forge — ver comentário em
  # bin/maestro (check_accept_proof_key).
  printf '%s' "${REPO_DIR:?REPO_DIR precisa estar no escopo}/config/accept-proof.pub"
}

# ------------------------------------------------------------------- sujeito (vocabulário fechado)
_order_accept_proof_subject_ok() { # <sujeito> → rc 0 se pertence a {spock, captain}
  case "${1:-}" in
    spock | captain) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------- base64url → base64 padrão
_order_accept_b64url_to_std() { # <b64url> → base64 padrão (com padding) no stdout; rc 1 se alfabeto/tamanho inválido
  # `openssl` fala base64 padrão com padding; MAESTRO_ACCEPT_PROOF chega em
  # base64url SEM padding (alfabeto `-_`). Conversão determinística, sem
  # depender do vetor — decodificação que não fecha é RECUSA, nunca um
  # "adivinha o resto" (nota da coordenação).
  local s="${1:-}" rem pad
  [[ -n "$s" && "$s" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  s="${s//-/+}"
  s="${s//_/\/}"
  rem=$(( ${#s} % 4 ))
  case "$rem" in
    0) pad=0 ;;
    2) pad=2 ;;
    3) pad=1 ;;
    *) return 1 ;;   # resto 1 nunca é base64 válido
  esac
  case "$pad" in
    0) printf '%s' "$s" ;;
    1) printf '%s=' "$s" ;;
    2) printf '%s==' "$s" ;;
  esac
}

# ------------------------------------------------------------------- envelope (FIXADO)
# MAESTRO_ACCEPT_PROOF = "v1:<sujeito>:<assinatura em base64url, sem padding>"
# ex.: v1:captain:MEUCIQ...   (sujeito nunca contém ':', assinatura tampouco)
_order_accept_proof_parse() { # <envelope> → stdout "sujeito<TAB>sig_b64url"; rc 1 se malformado
  local env="${1:-}" rest subj sig
  [[ "$env" == v1:* ]] || return 1
  rest="${env#v1:}"
  [[ "$rest" == *:* ]] || return 1
  subj="${rest%%:*}"
  sig="${rest#*:}"
  [[ -n "$subj" && -n "$sig" ]] || return 1
  [[ "$sig" != *:* ]] || return 1   # exatamente DOIS campos depois do "v1:" — terceiro ':' é forma inválida
  printf '%s\t%s' "$subj" "$sig"
}

# ------------------------------------------------------------------- nome do projeto (payload)
_order_accept_proof_project_name() { # <proj> → nome no payload = basename do caminho REAL
  # MESMA técnica de `_intent_action_init` (lib/cmd-intent.sh): `cd -P` resolve
  # symlink/`..` antes do basename, para dois caminhos do MESMO repo (worktree
  # vs raiz, symlink vs alvo) produzirem o MESMO nome — e portanto o MESMO
  # payload. Vetor canônico: `projeto` = `ponte-daemon`, o basename do repo.
  local proj="$1" pname
  pname=$(cd -P -- "$proj" 2>/dev/null && basename -- "$PWD") || pname=""
  printf '%s' "$pname"
}

# ------------------------------------------------------------------- verificador (vetor canônico)
_order_accept_proof_verify() { # <pubkey_pem> <projeto-nome> <id3> <arvore_provada> <sujeito> <sig_b64url> → rc 0 se a assinatura Ed25519 bate
  # docs-ops/045/VETOR-CANONICO-prova-de-aceite.md (ponte-daemon) — conferido
  # de ponta a ponta com a chave de teste do vetor antes de entrar aqui.
  local pub="$1" projeto="$2" id3="$3" arvore="$4" sujeito="$5" sig="$6"
  local sig_std payload_f sig_f rc
  command -v openssl >/dev/null 2>&1 || return 1
  [[ -f "$pub" && -s "$pub" ]] || return 1
  # base64url → base64 padrão: decodificação que não fecha é RECUSA, nunca um
  # "adivinha o resto" (nota da coordenação, repetida no vetor §"detalhes").
  sig_std=$(_order_accept_b64url_to_std "$sig") || return 1
  payload_f=$(mktemp 2>/dev/null) || return 1
  sig_f=$(mktemp 2>/dev/null) || { rm -f "$payload_f"; return 1; }
  # `printf '%s'` — NUNCA `echo`/heredoc: qualquer LF a mais quebra a
  # assinatura (vetor, ponto (c) — medido, não zelo). SEM newline final.
  printf '%s\n%s\n%s\n%s' "$projeto" "$id3" "$arvore" "$sujeito" > "$payload_f" 2>/dev/null
  if ! printf '%s' "$sig_std" | base64 -d > "$sig_f" 2>/dev/null; then
    rm -f "$payload_f" "$sig_f"; return 1
  fi
  # stderr do openssl (mensagem de falha) NUNCA vaza para a CLI — a recusa é
  # nomeada pelo CHAMADOR (`_order_accept_proof_gate`), não pelo openssl.
  openssl pkeyutl -verify -pubin -inkey "$pub" -rawin -in "$payload_f" -sigfile "$sig_f" >/dev/null 2>&1
  rc=$?
  rm -f "$payload_f" "$sig_f"
  return $rc
}

# ----------------------------------------------------------------- camadas de recusa (fail-closed)
_order_accept_proof_gate() { # <proj-dono> <id3> <arvore_provada> <envelope-ou-vazio> → stdout "ok <sujeito>" | "recusa <motivo>"; rc 0/1
  local proj="$1" id3="$2" arvore="$3" envelope="${4:-}" parsed subj sig pub pname
  if [[ -z "$envelope" ]]; then
    printf 'recusa prova ausente (MAESTRO_ACCEPT_PROOF não veio)'; return 1
  fi
  parsed=$(_order_accept_proof_parse "$envelope") || {
    printf 'recusa envelope malformado (esperado v1:<sujeito>:<assinatura b64url>)'; return 1
  }
  subj="${parsed%%$'\t'*}"
  sig="${parsed#*$'\t'}"
  _order_accept_proof_subject_ok "$subj" || {
    printf 'recusa sujeito "%s" fora do conjunto {spock, captain}' "$subj"; return 1
  }
  _order_accept_b64url_to_std "$sig" >/dev/null || {
    printf 'recusa assinatura corrompida (base64url inválido)'; return 1
  }
  pub=$(_order_accept_proof_pubkey_file)
  [[ -f "$pub" && -s "$pub" ]] || {
    printf 'recusa chave pública ausente (%s)' "$pub"; return 1
  }
  command -v openssl >/dev/null 2>&1 || {
    printf 'recusa openssl ausente'; return 1
  }
  pname=$(_order_accept_proof_project_name "$proj")
  if _order_accept_proof_verify "$pub" "$pname" "$id3" "$arvore" "$subj" "$sig"; then
    printf 'ok %s' "$subj"; return 0
  fi
  printf 'recusa assinatura Ed25519 inválida (payload projeto=%s id=%s árvore=%s sujeito=%s não confere)' \
    "$pname" "$id3" "${arvore:0:12}" "$subj"
  return 1
}

# --------------------------------------------------- confere na DERIVAÇÃO (fecha a porta dos fundos)
_order_accept_proof_derived_ok() { # <proj-dono> <id3> <arvore_provada> <sf-do-registro-ou-vazio> → rc 0 se 'aceita' pode ser DERIVADA
  # REQUIRE desligado: comportamento de hoje, byte a byte — nem olha o registro.
  _order_accept_require_proof "$1" || return 0
  # REQUIRE ligado: SEM registro (carimbo só-por-arquivo, ou registro sem os
  # campos de prova — é exatamente o carimbo escrito à mão dos dois lados),
  # nunca deriva 'aceita'. `_order_state_field` mora em core-order-terminal.sh
  # (já residente — mesmo módulo que grava/lê o registro).
  local proj="$1" id3="$2" arvore="$3" sf="$4" subj sig
  [[ -n "$sf" && -f "$sf" ]] || return 1
  subj=$(_order_state_field "$sf" accept_proof_subject)
  sig=$(_order_state_field "$sf" accept_proof_sig)
  [[ -n "$subj" && -n "$sig" ]] || return 1
  _order_accept_proof_gate "$proj" "$id3" "$arvore" "v1:$subj:$sig" >/dev/null
}
