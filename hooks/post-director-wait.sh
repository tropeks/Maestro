#!/usr/bin/env bash
[[ "${MAESTRO_OFF:-0}" == 1 ]] && exit 0
# hooks/post-director-wait.sh — PostToolUse, matcher `director_wait` da Ponte (E28).
#
# O gate domain libera a edição dos alvos de um plano só com a decisão do diretor
# do domínio. Essa decisão chega ao gerente no RESULTADO da tool `director_wait`
# (campo `domain_decisions[]` da raiz, v1.27 e R13 da v1.28), e o resultado de
# uma tool MCP é escrito
# pelo servidor, não pelo modelo. Este hook é
# o espelho: lê esse campo do `tool_response` e grava cada decisão no record da
# sessão com via=ponte (hooks/lib/domain-record.sh). O `maestro conduct
# --domain-decision` digitado continua existindo, mas grava via=manual e não
# libera — identidade de quem decidiu nunca sai de campo de texto do cliente.
#
# Só `domain_decisions[]` é lido; o resto da resposta
# (texto do Diretor) não é logado nem guardado. Run headless que espera por
# `director.wait_for` recebe a decisão como texto da retomada, que não é resultado
# de tool e não vale como prova: o gate manda chamar `director.wait` uma vez ao
# retomar (decisão já resolvida volta na hora) e o espelho a registra por aqui.
# Log: só metadados (cmd=domain_<response>, via=auto).
# Observador: sempre exit 0, nada no stdout. Bash + jq, sem Bun, sem rede.

set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR="."
# shellcheck source=lib/common.sh
if ! source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null; then
  exit 0
fi
maestro_killswitch
exec 1>&2

[[ -t 0 ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
# shellcheck source=lib/domain-record.sh
source "$SCRIPT_DIR/lib/domain-record.sh" 2>/dev/null || exit 0

raw=""
IFS= read -r -d '' -t 2 -n 262144 raw 2>/dev/null || :
[[ -n "$raw" ]] || exit 0

# Um fork de jq: 1ª linha "tool<TAB>sid"; depois cada decisão em JSON compacto.
# O resultado MCP pode vir como texto, lista de blocos ou objeto — por isso o
# `fromjson?` de 1º nível. Uma forma de decisão só: o campo `domain_decisions[]`
# (v1.27, API_SPEC §5.4.2 da Enterprise; R13 da v1.28). A linha `decisao: {json}`
# da `resposta` NÃO é lida: a `resposta` carrega texto de quem resolveu, e ler
# linha (inclusive decodificando JSON em texto) abria decisão forjada. O campo só é
# lido da RAIZ do DirectorWaitOutput (`status: respondida` + `decision_id`): o
# próprio tool_response, ou o texto JSON de cada bloco `content[]` de 1º nível —
# nunca de um JSON achado dentro de outra string (a `resposta` é texto de quem
# resolveu). Revogações (`revoked_at`, ou o `revoked` antigo, CONTRATO v2) vêm antes
# das decisões novas: a nova decisão do mesmo pedido só é aceita depois que a
# anterior está revogada.
out=$(jq -r "$DOMAIN_REVOKED_JQ"'
  def s: if type == "string" then . else "" end;
  def blocks: if type == "object" then ., (.content? | arrays | .[] | objects | .text? | strings | fromjson?)
              elif type == "array" then (.[] | objects | .text? | strings | fromjson?)
              else empty end;
  "\((.tool_name? // "") | s)\t\((.session_id? // "") | s)",
  ([.tool_response? | if type == "string" then (fromjson? // null) else . end | blocks | objects
      | select(.status == "respondida" and (.decision_id | type == "string"))] as $roots
    | [ $roots[] | .domain_decisions? | arrays | .[] | objects ]
    | reduce .[] as $d ([]; if any(.[]; . == $d) then . else . + [$d] end)
    | sort_by(if revoked_of then 0 else 1 end)
    | .[] | tojson)
' <<<"$raw" 2>/dev/null) || exit 0

head_line="${out%%$'\n'*}"
tool="${head_line%%$'\t'*}"
sid="${head_line#*$'\t'}"
# Só a tool da Ponte (servidor `ponte`, direto ou via plugin).
[[ "$tool" =~ ^mcp__(plugin_[A-Za-z0-9_-]+_)?ponte__director_wait$ ]] || exit 0
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 0
rec="$MAESTRO_SESSIONS_DIR/$sid.json"
[[ -f "$rec" && -r "$rec" ]] || exit 0
maestro_record_valid "$sid" || exit 0
jq -e '(.domain.requests // []) | length > 0' "$rec" >/dev/null 2>&1 || exit 0

[[ "$out" == *$'\n'* ]] || exit 0
n=0
while IFS= read -r d; do
  [[ -n "$d" ]] || continue
  n=$(( n + 1 )); (( n <= 4 )) || break   # um pedido por domínio; teto de folga
  (( ${#d} <= 4096 )) || continue
  [[ "$(domain_decision_why "$rec" "$d")" == ok ]] || continue
  vu=$(jq -r '.valid_until' <<<"$d" 2>/dev/null) || continue
  vu_epoch=$(domain_valid_until_epoch "$vu") || continue
  now=$(maestro_now_epoch)
  (( vu_epoch > now )) || continue
  resp=$(jq -r '.response' <<<"$d" 2>/dev/null) || continue
  domain_record_apply "$rec" "$d" ponte "$vu_epoch" "$now" || continue
  log_event conduct session_id="$sid" flags_n=0 approach=no cmd="domain_$resp" via=auto
done <<<"${out#*$'\n'}"

exit 0
