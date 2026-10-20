#!/usr/bin/env bash
# maestro lib/cmd-domain.sh — E28 (diretoria por domínio): `maestro conduct
# --domain-decision '<json>'`, o espelho no record da decisão do diretor do
# domínio que veio da Ponte.
#
# A autoridade é a Ponte (identidade do peer provada pelo runtime, nunca campo
# de texto); aqui só se confere o contrato mínimo (tropeks/spock:docs/diretoria/
# CONTRATO.md) contra o pedido que o `decide` gravou no PRÓPRIO record
# (DATA_MODEL §3 v1.26). Recusas: campo fora ou faltando do contrato, pedido
# alheio, `response` fora do enum, condição faltando, diretor de outro
# domínio, aprovação mecânica (timeout nunca aprova), INTENT diferente do
# pedido, validade vencida, `decision_id` repetido e segunda resolução de
# pedido já resolvido. O status agregado segue a ordem do decide (src/cli.ts):
# o pior pedido vence.
#
# Sourced por bin/maestro (via _domain_lib_load, I-2) DENTRO do mesmo processo
# — REPO_DIR, die, has, log_event já no escopo. Parâmetro posicional, nenhuma
# função fecha sobre local de outra.

_domain_decision_why() { # <rec> <json> → "ok" ou o motivo da recusa
  jq -r --slurpfile r "$1" --argjson in "$2" '
    def s: type == "string";
    ["decision_id","request_id","response","conditions","reason","decided_by",
     "policy_ref","intent","valid_until"] as $f
    | ($r[0].domain.requests // []) as $reqs
    | ($reqs | map(select(.request_id == $in.request_id)) | first) as $req
    | ($r[0].domain.decisions // []) as $prev
    | ($prev | map(select(.request_id == $in.request_id)) | last) as $old
    | if ((keys - $f) | length) > 0 then "campo fora do contrato: \((keys - $f) | join(","))"
      elif (($f - keys) | length) > 0 then "faltam campos: \(($f - keys) | join(","))"
      elif ((.decision_id | s and test("^[A-Za-z0-9._:-]{1,64}$")) | not) then "decision_id inválido"
      elif $req == null then "request_id não é pedido deste record"
      elif ((.response as $x | ["approved","approved_with_conditions","needs_evidence","revise","denied","escalate"] | index($x)) == null) then "response fora do enum"
      elif ((.conditions | type == "array" and all(.[]; s and length > 0 and length <= 120)) | not) then "conditions não é lista de textos (até 120 chars)"
      elif .response == "approved_with_conditions" and (.conditions | length) == 0 then "approved_with_conditions sem condição"
      elif ((.reason | s and length <= 120)) | not then "reason não é texto até 120 chars"
      elif ((.policy_ref | s and length > 0 and length <= 120)) | not then "policy_ref vazio"
      elif ((.decided_by | type == "object" and ((keys - ["role","domain","label"]) | length) == 0
              and (.role as $x | ["spock","director_domain","captain","mechanical"] | index($x)) != null
              and (.domain == null or (.domain as $x | ["security","infrastructure"] | index($x)) != null)
              and (.label | s and length <= 120))) | not then "decided_by fora do contrato (role, domain, label)"
      elif .decided_by.role == "director_domain" and .decided_by.domain != $req.domain then "diretor de \(.decided_by.domain) não decide pedido de \($req.domain)"
      elif .decided_by.role == "mechanical" and (.response | startswith("approved")) then "decisão mecânica não aprova (timeout nunca aprova)"
      elif ((.intent | type == "object") and .intent.version == $req.intent.version and .intent.hash == $req.intent.hash) | not then "intent da decisão difere do intent do pedido"
      elif ((.valid_until | s and length > 0)) | not then "valid_until ausente"
      elif ($prev | map(.decision_id) | index($in.decision_id)) != null then "decision_id já registrado"
      elif $old != null and (($old.response as $x | ["needs_evidence","escalate"] | index($x)) == null) then "pedido já resolvido (\($old.response)): plano novo → decida de novo"
      else "ok" end
  ' <<<"$2" 2>/dev/null || printf 'JSON ilegível\n'
}

cmd_domain_decision() { # <sid> <json> <n_flags> <approach>
  local sid="$1" ddec="$2" why vu vu_epoch resp rec tmp
  [[ "$3" == 0 && -z "$4" ]] || die validation \
    "--domain-decision vai sozinho" "registre a decisão de domínio num conduct próprio" 1
  has jq || die env "conduct exige jq" "instale jq (dependência declarada)" 2
  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  rec="$MAESTRO_SESSIONS_DIR/$sid.json"
  [[ -f "$rec" ]] || die validation "não há decision record para a sessão $sid" \
    "conduct muta uma decisão existente (maestro decide primeiro)" 1
  jq -e '(.domain.requests // []) | length > 0' "$rec" >/dev/null 2>&1 || die validation \
    "o record da sessão $sid não tem pedido de domínio" \
    "decisão de domínio só existe para plano que tocou domínio (maestro decide de workflow com gate domain)" 1
  (( ${#ddec} <= 4096 )) || die validation "--domain-decision acima de 4096 bytes" "" 1
  jq -e 'type == "object"' <<<"$ddec" >/dev/null 2>&1 || die validation \
    "--domain-decision não é um objeto JSON" "passe a decisão da Ponte como JSON de uma linha" 1
  why=$(_domain_decision_why "$rec" "$ddec")
  [[ "$why" == "ok" ]] || die validation "--domain-decision recusada: $why" \
    "a decisão vem da Ponte (contrato em tropeks/spock:docs/diretoria/CONTRATO.md)" 1
  vu=$(jq -r '.valid_until' <<<"$ddec")
  vu_epoch=$(date -d "$vu" +%s 2>/dev/null) || die validation "valid_until não é data legível" "use ISO 8601" 1
  (( vu_epoch > $(maestro_now_epoch) )) || die validation "decisão vencida (valid_until no passado)" \
    "peça a decisão de novo pela Ponte" 1

  tmp="$rec.tmp.$$"
  resp=$(jq -r '.response' <<<"$ddec")
  if jq -c --argjson d "$ddec" '
       .domain.decisions = ((.domain.decisions // []) + [$d])
       | ["denied","revise","escalate","needs_evidence","pending","approved_with_conditions","approved"] as $ord
       | .domain.decisions as $ds
       | .domain.status = ([.domain.requests[] | .request_id as $id
           | (([$ds[] | select(.request_id == $id)] | last | .response) // "pending") as $x
           | ($ord | index($x))] | min | $ord[.])
     ' "$rec" > "$tmp" 2>/dev/null && chmod 600 "$tmp" 2>/dev/null && mv -f "$tmp" "$rec" 2>/dev/null; then
    log_event conduct session_id="$sid" flags_n=0 approach=no cmd="domain_$resp"
    printf 'record %s: decisão de domínio %s registrada · status %s\n' \
      "$sid" "$resp" "$(jq -r '.domain.status' "$rec")"
  else
    rm -f "$tmp" 2>/dev/null
    die env "falha ao atualizar o record" "cheque permissões em $MAESTRO_SESSIONS_DIR" 2
  fi
  return 0
}
