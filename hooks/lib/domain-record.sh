# shellcheck shell=bash
# hooks/lib/domain-record.sh — E28: o espelho, no decision record, da decisão do
# diretor do domínio (contrato: tropeks/spock:docs/diretoria/CONTRATO.md).
#
# Dois caminhos gravam por aqui, e SÓ UM libera a edição:
#   via=ponte  — hooks/post-director-wait.sh (PostToolUse): a decisão veio no
#                RESULTADO da tool `director_wait`, escrito pelo servidor MCP da
#                Ponte, não pelo modelo. É a prova de runtime que o Maestro tem.
#   via=manual — `maestro conduct --domain-decision` (lib/cmd-domain.sh): texto
#                digitado. Fica no record como registro; aprovação manual conta
#                como `pending` e não libera nada.
# O espelho não é a autoridade: a trava do efeito é da Ponte (o diretor decide
# por `domain.decide`, peer provado pelo runtime). O que o pre-tool-gate faz com
# o espelho é anti-descuido (ADR-003 v1.1), não controle de acesso — quem tem o
# mesmo uid pode reescrever o record à mão, e isso fica visível no transcrito.
#
# `decided_by.label` NUNCA vem do cliente: é derivado de role/domain aqui.
#
# Campos que o Maestro acrescenta ao bloco (DATA_MODEL §3 v1.26):
#   domain.cleared        domínios cujo pedido tem aprovação `approved` via ponte
#                         e não vencida ("security infrastructure"; "" = nenhum)
#   domain.cleared_until  menor validade (epoch) entre essas aprovações; 0 = nenhuma
#   decisions[].via       ponte | manual
#   decisions[].until_epoch  valid_until da decisão em epoch
# O status agregado é o pior pedido; aprovação manual não libera. CONTRATO v3:
# `approved_with_conditions` via ponte libera a EDIÇÃO quando toda condição traz
# `check_ref` (conta como `approved`; cada condição vira critério do aceite da ordem,
# `maestro order --accept --condicoes-conferidas`); com algum `check_ref: null` segue
# pendente (a Ponte também não executa ação com condição em texto). Decisão revogada (`revoked_at`) também não: a última
# decisão do pedido revogada conta como `pending`.
#
# Forma da decisão aceita (CONTRATO v2, tropeks/spock:docs/diretoria/CONTRATO.md):
#   conditions[]      {texto, check_ref}: texto no charset do reason da Ponte, até 120;
#                     check_ref em ^[A-Za-z0-9._:/#-]{1,120}$ ou null; até 3 itens; vazia
#                     fora de approved_with_conditions (CHECK_REF_RE e CONDICOES_MAX do
#                     ponte-daemon, domain/diretoria.ts)
#   reason            ^[A-Za-z0-9 .,:/_-]{1,120}$ (texto longo só por referência ao decision_id)
#   escalate_to       spock | captain só em `escalate`; null (ou ausente) nas outras
#   escalation_class  desvio_de_curso | crash, obrigatória com escalate_to=captain; null fora
#   revoked_at        timestamp ISO da revogação ou null (ausente = null). Campo único:
#                     `revoked` booleano antigo só é lido por compatibilidade (true =
#                     revogada) e nunca é gravado — vira revoked_at no record.
#                     Só pelo espelho (via=ponte): o caminho manual não revoga.
#                     Revogação de decision_id já registrado marca a decisão no lugar
#                     (não duplica); de decision_id desconhecido é recusada (não cobria nada).
#
# Sourced por lib/cmd-domain.sh e hooks/post-director-wait.sh. Bash + jq.

# Revogada: `revoked_at` não nulo, ou o `revoked` antigo (true; texto não vazio nos
# records gravados antes do CONTRATO v2). Prefixo de todo programa jq que a lê.
# shellcheck disable=SC2016  # programa jq, não expansão de shell
DOMAIN_REVOKED_JQ='def revoked_of: (.revoked_at? // null) != null
  or ((.revoked? // false) as $v | $v == true or ($v | type == "string" and length > 0));'

# Recalcula status, cleared e cleared_until do bloco e o reescreve na ordem fixa
# (status, scope, cleared, cleared_until, requests, decisions): o gate lê os
# quatro primeiros por regex numa janela de 4 KiB. Espera --argjson now.
# shellcheck disable=SC2016  # programa jq, não expansão de shell
DOMAIN_RECOMPUTE_JQ="$DOMAIN_REVOKED_JQ"'
  def last_of($ds; $id): [$ds[] | select(.request_id == $id)] | last;
  def libera($d): $d.response == "approved"
    or ($d.response == "approved_with_conditions" and (($d.conditions // []) | length) > 0
        and all(($d.conditions // [])[]; .check_ref != null));
  def clears($d): $d != null and libera($d) and $d.via == "ponte"
    and ($d | revoked_of | not) and (($d.until_epoch // 0) > $now);
  .domain as $b
  | ($b.decisions // []) as $ds
  | ["denied","revise","escalate","needs_evidence","pending","approved_with_conditions","approved"] as $ord
  | [$b.requests[] | last_of($ds; .request_id) as $d
      | if $d == null or ($d | revoked_of) then "pending"
        elif ($d.response | startswith("approved")) and $d.via != "ponte" then "pending"
        elif libera($d) then "approved"
        else $d.response end] as $eff
  | [$b.requests[] | last_of($ds; .request_id) as $d | select(clears($d))
      | {domain, until: $d.until_epoch}] as $ok
  | (if ($eff | length) == 0 then "clear"
     else ($eff | map(. as $x | $ord | index($x)) | min | $ord[.]) end) as $status
  | .domain = ({status: $status}
      + (if $b | has("scope") then {scope: $b.scope} else {} end)
      + {cleared: ([$ok[].domain] | unique | join(" ")),
         cleared_until: ([$ok[].until] | min // 0),
         requests: $b.requests}
      + (if ($ds | length) > 0 then {decisions: $ds} else {} end))
'

# domain_decision_why <rec> <json> → "ok" ou o motivo da recusa (stdout)
domain_decision_why() {
  jq -r --slurpfile r "$1" --argjson in "$2" "$DOMAIN_REVOKED_JQ"'
    def s: type == "string";
    def curto: s and test("^[A-Za-z0-9 .,:/_-]{1,120}$");
    def cond: type == "object" and (keys == ["check_ref","texto"]) and (.texto | curto)
      and (.check_ref == null or (.check_ref | s and test("^[A-Za-z0-9._:/#-]{1,120}$")));
    def iso: s and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$");
    ["decision_id","request_id","response","conditions","reason","decided_by",
     "policy_ref","intent","valid_until"] as $f
    | ($f + ["escalate_to","escalation_class","revoked_at","revoked"]) as $opt
    | ($r[0].domain.requests // []) as $reqs
    | ($reqs | map(select(.request_id == $in.request_id)) | first) as $req
    | ($r[0].domain.decisions // []) as $prev
    | ($prev | map(select(.request_id == $in.request_id and .via == "ponte")) | last) as $old
    | ($prev | map(select(.decision_id == $in.decision_id))) as $same
    | (.escalate_to // null) as $to
    | (.escalation_class // null) as $cls
    | if ((keys - $opt) | length) > 0 then "campo fora do contrato: \((keys - $opt) | join(","))"
      elif (($f - keys) | length) > 0 then "faltam campos: \(($f - keys) | join(","))"
      elif ((.decision_id | s and test("^[A-Za-z0-9._:-]{1,64}$")) | not) then "decision_id inválido"
      elif $req == null then "request_id não é pedido deste record"
      elif ((.response as $x | ["approved","approved_with_conditions","needs_evidence","revise","denied","escalate"] | index($x)) == null) then "response fora do enum"
      elif ((.conditions | type == "array" and length <= 3 and all(.[]; cond)) | not) then "conditions não é lista de até 3 {texto, check_ref} (texto no charset do reason, até 120; check_ref em [A-Za-z0-9._:/#-] até 120)"
      elif .response == "approved_with_conditions" and (.conditions | length) == 0 then "approved_with_conditions sem condição"
      elif .response != "approved_with_conditions" and (.conditions | length) > 0 then "conditions só em approved_with_conditions"
      elif (.reason | curto | not) then "reason fora do charset ou acima de 120 (texto longo só por referência ao decision_id)"
      elif ($to != null and $to != "spock" and $to != "captain") then "escalate_to não é spock nem captain"
      elif .response == "escalate" and $to == null then "escalate sem escalate_to"
      elif .response != "escalate" and $to != null then "escalate_to só em escalate"
      elif ($cls != null and $cls != "desvio_de_curso" and $cls != "crash") then "escalation_class não é desvio_de_curso nem crash"
      elif $to == "captain" and $cls == null then "escalate_to captain exige escalation_class"
      elif $to != "captain" and $cls != null then "escalation_class só com escalate_to captain"
      elif ((.revoked_at // null) | . == null or iso) | not then "revoked_at não é timestamp ISO nem null"
      elif ((.revoked // null) | . == null or type == "boolean") | not then "revoked (compatibilidade) não é booleano"
      elif ((.policy_ref | s and length > 0 and length <= 120)) | not then "policy_ref vazio ou acima de 120"
      elif ((.decided_by | type == "object" and ((keys - ["role","domain","label"]) | length) == 0
              and (.role as $x | ["spock","director_domain","captain","mechanical"] | index($x)) != null
              and (.domain == null or (.domain as $x | ["security","infrastructure"] | index($x)) != null)
              and ((.label // "") | s and length <= 120))) | not then "decided_by fora do contrato (role, domain, label)"
      elif .decided_by.role == "director_domain" and .decided_by.domain != $req.domain then "diretor de \(.decided_by.domain) não decide pedido de \($req.domain)"
      elif .decided_by.role != "director_domain" and .decided_by.domain != null then "só director_domain tem domínio"
      elif .decided_by.role == "mechanical" and (.response | startswith("approved")) then "decisão mecânica não aprova (timeout nunca aprova)"
      elif ((.intent | type == "object") and .intent.version == $req.intent.version and .intent.hash == $req.intent.hash) | not then "intent da decisão difere do intent do pedido"
      elif ((.valid_until | s and length > 0)) | not then "valid_until ausente"
      elif revoked_of then
        (if ($same | length) == 0 then "revogação de decisão não registrada"
         elif ($same | any(.request_id != $in.request_id or .response != $in.response)) then "revogação difere da decisão registrada"
         elif ($same | all(revoked_of)) then "decisão já revogada"
         else "ok" end)
      elif ($same | length) > 0 then "decision_id já registrado"
      elif $old != null and ($old | revoked_of | not) and (($old.response as $x | ["needs_evidence","escalate","approved_with_conditions"] | index($x)) == null) then "pedido já resolvido (\($old.response)): plano novo → decida de novo"
      else "ok" end
  ' <<<"$2" 2>/dev/null || printf 'JSON ilegível\n'
}

# domain_valid_until_epoch <iso> → epoch (stdout) ou rc 1
domain_valid_until_epoch() {
  local e=""
  e=$(date -d "$1" +%s 2>/dev/null) || return 1
  [[ "$e" =~ ^[0-9]{1,12}$ ]] || return 1
  printf '%s' "$e"
}

# domain_record_apply <rec> <json> <via ponte|manual> <until_epoch> <now_epoch>
#   Anexa a decisão (label derivado, via, until_epoch, escalate_to/escalation_class/
#   revoked_at normalizados para null) — ou, se é a revogação de uma decisão já
#   registrada, grava `revoked_at` nela (o `revoked` antigo vira revoked_at = agora) —,
#   recalcula o bloco e grava atômico (tmp + mv, 0600). rc 0 = gravado; rc 1 = falha.
domain_record_apply() {
  local rec="$1" json="$2" via="$3" until="$4" now="$5" tmp="$1.tmp.$$"
  [[ "$via" == ponte || "$via" == manual ]] || return 1
  [[ "$until" =~ ^[0-9]{1,12}$ && "$now" =~ ^[0-9]{1,12}$ ]] || return 1
  # Revogação só pelo espelho: o caminho manual nunca grava `revoked_at` (defesa em
  # profundidade; lib/cmd-domain.sh já recusa antes).
  if [[ "$via" != ponte ]] && jq -e "$DOMAIN_REVOKED_JQ revoked_of" <<<"$json" >/dev/null 2>&1; then
    return 1
  fi
  if jq -c --argjson d "$json" --arg via "$via" --argjson ue "$until" --argjson now "$now" "$DOMAIN_REVOKED_JQ"'
       ($d.decided_by | {role, domain,
         label: (if .role == "director_domain"
                 then (if .domain == "security" then "diretor-seguranca" else "diretor-infra" end)
                 elif .role == "spock" then "spock"
                 elif .role == "captain" then "capitao"
                 else "mecanico" end)}) as $by
       | ($d.revoked_at // ($now | todate)) as $ra
       | ($d | del(.revoked) + {escalate_to: (.escalate_to // null),
           escalation_class: (.escalation_class // null), revoked_at: null,
           decided_by: $by, via: $via, until_epoch: $ue}) as $novo
       | def marca: if .decision_id == $d.decision_id then del(.revoked) + {revoked_at: $ra} else . end;
       if ($d | revoked_of) and ((.domain.decisions // []) | any(.decision_id == $d.decision_id))
         then .domain.decisions |= map(marca)
         else .domain.decisions = ((.domain.decisions // []) + [$novo])
         end
       | '"$DOMAIN_RECOMPUTE_JQ" "$rec" > "$tmp" 2>/dev/null \
     && chmod 600 "$tmp" 2>/dev/null && mv -f "$tmp" "$rec" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || :
  return 1
}
