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
# O status agregado é o pior pedido; aprovação manual e `approved_with_conditions`
# não liberam (o Maestro não verifica condição; a Ponte também não executa ação
# com condição em texto). Decisão revogada (`revoked`, v1.27) também não: a última
# decisão do pedido revogada conta como `pending`.
#
# Forma da decisão aceita (contrato + v1.27 da Enterprise, API_SPEC §5.4.2/§5.4.5):
#   conditions[]  texto (até 120) ou {texto ≤ 200, check_ref, id?}; até 8 itens
#   reason        texto até 500
#   revoked       opcional: true ou a data da revogação (texto); false/null = vigente.
#                 Só pelo espelho (via=ponte): o caminho manual não revoga.
#                 Revogação de decision_id já registrado marca a decisão no lugar
#                 (não duplica); de decision_id desconhecido é recusada (não cobria nada).
#
# Sourced por lib/cmd-domain.sh e hooks/post-director-wait.sh. Bash + jq.

# Recalcula status, cleared e cleared_until do bloco e o reescreve na ordem fixa
# (status, scope, cleared, cleared_until, requests, decisions): o gate lê os
# quatro primeiros por regex numa janela de 4 KiB. Espera --argjson now.
# shellcheck disable=SC2016  # programa jq, não expansão de shell
DOMAIN_RECOMPUTE_JQ='
  def last_of($ds; $id): [$ds[] | select(.request_id == $id)] | last;
  def revoked($d): ($d.revoked // false) as $v | $v == true or ($v | type == "string" and length > 0);
  def clears($d): $d != null and $d.response == "approved" and $d.via == "ponte"
    and (revoked($d) | not) and (($d.until_epoch // 0) > $now);
  .domain as $b
  | ($b.decisions // []) as $ds
  | ["denied","revise","escalate","needs_evidence","pending","approved_with_conditions","approved"] as $ord
  | [$b.requests[] | last_of($ds; .request_id) as $d
      | if $d == null or revoked($d) then "pending"
        elif ($d.response | startswith("approved")) and $d.via != "ponte" then "pending"
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
  jq -r --slurpfile r "$1" --argjson in "$2" '
    def s: type == "string";
    def rev: (. // false) as $v | $v == true or ($v | type == "string" and length > 0);
    def cond: (s and length > 0 and length <= 120)
      or (type == "object" and ((keys - ["id","texto","check_ref"]) | length) == 0
          and (.texto | s and length > 0 and length <= 200)
          and (.check_ref | s and length > 0 and length <= 200)
          and (if has("id") then (.id | s and length > 0 and length <= 64) else true end));
    ["decision_id","request_id","response","conditions","reason","decided_by",
     "policy_ref","intent","valid_until"] as $f
    | ($f + ["revoked"]) as $opt
    | ($r[0].domain.requests // []) as $reqs
    | ($reqs | map(select(.request_id == $in.request_id)) | first) as $req
    | ($r[0].domain.decisions // []) as $prev
    | ($prev | map(select(.request_id == $in.request_id and .via == "ponte")) | last) as $old
    | ($prev | map(select(.decision_id == $in.decision_id))) as $same
    | (.revoked | rev) as $isrev
    | if ((keys - $opt) | length) > 0 then "campo fora do contrato: \((keys - $opt) | join(","))"
      elif (($f - keys) | length) > 0 then "faltam campos: \(($f - keys) | join(","))"
      elif ((.decision_id | s and test("^[A-Za-z0-9._:-]{1,64}$")) | not) then "decision_id inválido"
      elif $req == null then "request_id não é pedido deste record"
      elif ((.response as $x | ["approved","approved_with_conditions","needs_evidence","revise","denied","escalate"] | index($x)) == null) then "response fora do enum"
      elif ((.conditions | type == "array" and length <= 8 and all(.[]; cond)) | not) then "conditions não é lista de até 8 condições (texto até 120 ou {texto, check_ref})"
      elif .response == "approved_with_conditions" and (.conditions | length) == 0 then "approved_with_conditions sem condição"
      elif ((.reason | s and length <= 500)) | not then "reason não é texto até 500 chars"
      elif has("revoked") and ((.revoked | . == null or type == "boolean" or (s and length <= 64)) | not) then "revoked não é booleano nem data"
      elif ((.policy_ref | s and length > 0 and length <= 120)) | not then "policy_ref vazio"
      elif ((.decided_by | type == "object" and ((keys - ["role","domain","label"]) | length) == 0
              and (.role as $x | ["spock","director_domain","captain","mechanical"] | index($x)) != null
              and (.domain == null or (.domain as $x | ["security","infrastructure"] | index($x)) != null)
              and ((.label // "") | s and length <= 120))) | not then "decided_by fora do contrato (role, domain, label)"
      elif .decided_by.role == "director_domain" and .decided_by.domain != $req.domain then "diretor de \(.decided_by.domain) não decide pedido de \($req.domain)"
      elif .decided_by.role != "director_domain" and .decided_by.domain != null then "só director_domain tem domínio"
      elif .decided_by.role == "mechanical" and (.response | startswith("approved")) then "decisão mecânica não aprova (timeout nunca aprova)"
      elif ((.intent | type == "object") and .intent.version == $req.intent.version and .intent.hash == $req.intent.hash) | not then "intent da decisão difere do intent do pedido"
      elif ((.valid_until | s and length > 0)) | not then "valid_until ausente"
      elif $isrev then
        (if ($same | length) == 0 then "revogação de decisão não registrada"
         elif ($same | any(.request_id != $in.request_id or .response != $in.response)) then "revogação difere da decisão registrada"
         elif ($same | all(.revoked | rev)) then "decisão já revogada"
         else "ok" end)
      elif ($same | length) > 0 then "decision_id já registrado"
      elif $old != null and ($old.revoked | rev | not) and (($old.response as $x | ["needs_evidence","escalate","approved_with_conditions"] | index($x)) == null) then "pedido já resolvido (\($old.response)): plano novo → decida de novo"
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
#   Anexa a decisão (label derivado, via, until_epoch) — ou, se é a revogação de
#   uma decisão já registrada, marca `revoked` nela —, recalcula o bloco e grava
#   atômico (tmp + mv, 0600). rc 0 = gravado; rc 1 = falha de escrita.
domain_record_apply() {
  local rec="$1" json="$2" via="$3" until="$4" now="$5" tmp="$1.tmp.$$"
  [[ "$via" == ponte || "$via" == manual ]] || return 1
  [[ "$until" =~ ^[0-9]{1,12}$ && "$now" =~ ^[0-9]{1,12}$ ]] || return 1
  # Revogação só pelo espelho: o caminho manual nunca marca `revoked` (defesa em
  # profundidade; lib/cmd-domain.sh já recusa antes).
  if [[ "$via" != ponte ]] && jq -e '(.revoked // false) as $v | $v == true or ($v | type == "string" and length > 0)' \
       <<<"$json" >/dev/null 2>&1; then
    return 1
  fi
  if jq -c --argjson d "$json" --arg via "$via" --argjson ue "$until" --argjson now "$now" '
       ($d.decided_by | {role, domain,
         label: (if .role == "director_domain"
                 then (if .domain == "security" then "diretor-seguranca" else "diretor-infra" end)
                 elif .role == "spock" then "spock"
                 elif .role == "captain" then "capitao"
                 else "mecanico" end)}) as $by
       | ($d.revoked // false) as $rv
       | if ($rv == true or ($rv | type == "string" and length > 0))
            and ((.domain.decisions // []) | any(.decision_id == $d.decision_id))
         then .domain.decisions |= map(if .decision_id == $d.decision_id then . + {revoked: $rv} else . end)
         else .domain.decisions = ((.domain.decisions // []) + [$d + {decided_by: $by, via: $via, until_epoch: $ue}])
         end
       | '"$DOMAIN_RECOMPUTE_JQ" "$rec" > "$tmp" 2>/dev/null \
     && chmod 600 "$tmp" 2>/dev/null && mv -f "$tmp" "$rec" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || :
  return 1
}
