#!/usr/bin/env bash
# maestro lib/cmd-domain.sh — E28 (diretoria por domínio): `maestro conduct
# --domain-decision '<json>'`, o registro MANUAL de uma decisão de domínio.
#
# A autoridade é a Ponte (identidade do peer provada pelo runtime, nunca campo
# de texto). O caminho que libera a edição é o espelho automático do resultado
# da tool `director_wait` (hooks/post-director-wait.sh, via=ponte). Este comando
# é o caminho DEGRADADO, sem Ponte ou para registrar o que veio por fora: grava
# com via=manual, e aprovação manual conta como `pending` — não libera o
# pre-tool-gate. Sem Ponte, a edição dos alvos é do humano (fluxo manual, I-2).
#
# Contrato e recusas: hooks/lib/domain-record.sh (`domain_decision_why`) —
# campo fora ou faltando do contrato (tropeks/spock:docs/diretoria/
# CONTRATO.md), pedido alheio, `response` fora do enum, diretor de outro
# domínio, aprovação mecânica (timeout nunca aprova), INTENT diferente do
# pedido, validade vencida, `decision_id` repetido, segunda resolução de
# pedido já resolvido pela Ponte e revogação (`revoked_at`, ou o `revoked` antigo),
# que só vem da Ponte. Forma da decisão: CONTRATO v2 (escalate_to/escalation_class,
# conditions {texto, check_ref}, reason até 120 no charset da Ponte).
# `decided_by.label` é derivado, nunca lido.
#
# Sourced por bin/maestro (via _domain_lib_load, I-2) DENTRO do mesmo processo
# — REPO_DIR, die, has, log_event já no escopo. Parâmetro posicional, nenhuma
# função fecha sobre local de outra.

cmd_domain_decision() { # <sid> <json> <n_flags> <approach>
  local sid="$1" ddec="$2" why vu vu_epoch now resp rec
  [[ "$3" == 0 && -z "$4" ]] || die validation \
    "--domain-decision vai sozinho" "registre a decisão de domínio num conduct próprio" 1
  has jq || die env "conduct exige jq" "instale jq (dependência declarada)" 2
  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  # shellcheck source=hooks/lib/domain-record.sh
  source "$REPO_DIR/hooks/lib/domain-record.sh" || die env "hooks/lib/domain-record.sh ausente" "reinstale o plugin" 2
  rec="$MAESTRO_SESSIONS_DIR/$sid.json"
  [[ -f "$rec" ]] || die validation "não há decision record para a sessão $sid" \
    "conduct muta uma decisão existente (maestro decide primeiro)" 1
  jq -e '(.domain.requests // []) | length > 0' "$rec" >/dev/null 2>&1 || die validation \
    "o record da sessão $sid não tem pedido de domínio" \
    "decisão de domínio só existe para plano que tocou domínio (maestro decide de workflow com gate domain)" 1
  (( ${#ddec} <= 4096 )) || die validation "--domain-decision acima de 4096 bytes" "" 1
  jq -e 'type == "object"' <<<"$ddec" >/dev/null 2>&1 || die validation \
    "--domain-decision não é um objeto JSON" "passe a decisão como JSON de uma linha" 1
  # Revogação só pelo espelho (via=ponte): texto digitado não desfaz decisão da Ponte —
  # reabriria o pedido já resolvido e trocaria `denied` por `pending`.
  if jq -e "$DOMAIN_REVOKED_JQ revoked_of" <<<"$ddec" >/dev/null 2>&1; then
    die validation "--domain-decision recusada: revogação só pela Ponte" \
      "a revogação chega pelo resultado do director_wait (espelhado sozinho); o conduct manual não revoga" 1
  fi
  why=$(domain_decision_why "$rec" "$ddec")
  [[ "$why" == "ok" ]] || die validation "--domain-decision recusada: $why" \
    "contrato em tropeks/spock:docs/diretoria/CONTRATO.md" 1
  vu=$(jq -r '.valid_until' <<<"$ddec")
  vu_epoch=$(domain_valid_until_epoch "$vu") || die validation "valid_until não é data legível" "use ISO 8601" 1
  now=$(maestro_now_epoch)
  (( vu_epoch > now )) || die validation "decisão vencida (valid_until no passado)" \
    "peça a decisão de novo pela Ponte" 1

  resp=$(jq -r '.response' <<<"$ddec")
  domain_record_apply "$rec" "$ddec" manual "$vu_epoch" "$now" \
    || die env "falha ao atualizar o record" "cheque permissões em $MAESTRO_SESSIONS_DIR" 2
  log_event conduct session_id="$sid" flags_n=0 approach=no cmd="domain_$resp" via=manual
  printf 'record %s: decisão de domínio %s registrada como MANUAL · status %s\n' \
    "$sid" "$resp" "$(jq -r '.domain.status' "$rec")"
  if [[ "$resp" == approved* ]]; then
    printf '  registro manual não libera a edição dos alvos: a liberação vem do resultado da\n'
    printf '  tool director_wait da Ponte (espelhado sozinho). Sem Ponte, quem aplica é o humano.\n'
  fi
  return 0
}
