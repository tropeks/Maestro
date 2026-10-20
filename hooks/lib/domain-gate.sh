# shellcheck shell=bash
# hooks/lib/domain-gate.sh — o `gate: domain` no Stop (E28, diretoria por domínio).
#
# O plano de feature/refactor segue sem humano; quando toca domínio, o
# `maestro decide` (src/cli.ts) grava no record o bloco `domain` com o pedido ao
# diretor do domínio (DATA_MODEL §3 v1.26). Aqui o Stop (gate-report.sh) lê
# esse bloco por regex — presença + enum, sem parser, como o resto do hook — e,
# com o pedido pendente e a Ponte presente, segura a rodada para o gerente
# chamar `director.ask`/`director.wait`. Sem Ponte, só o arquivo de gate e o
# report ao herdr (fluxo manual, I-2). Timeout nunca aprova: nada aqui olha
# relógio para liberar; o TTL é só a rede de não-laço do `_maestro_mcp_ask_gate`.
#
# Sourced por hooks/gate-report.sh (que define `_maestro_mcp_ask_gate`,
# `ponte_sock` e `reentry` antes de chamar `maestro_domain_ask`). Bash puro,
# sem fork, sem rede.

# Texto fixo, ASCII, nunca cita o pedido (alvos e efeitos são do projeto).
MCP_DOMAIN_REASON_JSON='{"decision":"block","reason":"maestro: o plano desta sessao tocou dominio (gate domain) e o pedido ao diretor do dominio esta pendente. Chame a tool MCP director.ask uma vez com o pedido que o maestro decide imprimiu, depois director.wait em laco (ate 5 min por chamada, teto de 30 min). A resposta do director.wait e registrada sozinha pelo maestro, sem conduct. Sem resposta, a edicao dos alvos do plano segue suspensa: timeout nao aprova."}'

# maestro_domain_read <corpo do record> <settled 0|1>
#   rc 0 = record de workflow com `gate: domain` (tem o bloco `domain`); rc 1 = não.
#   Publica dom_status, dom_names ("security, infrastructure") e dom_gate
#   ("domain" quando o pedido não liberou e não há desfecho; senão vazio).
#   Record de gate domain NUNCA abre gate plan, mesmo com approach pendente.
# shellcheck disable=SC2034  # dom_* são publicadas para o gate-report.sh
maestro_domain_read() {
  local body="$1" settled="${2:-0}" d
  dom_status=""; dom_names=""; dom_gate=""
  [[ "$body" =~ \"domain\"[[:space:]]*:[[:space:]]*\{[[:space:]]*\"status\"[[:space:]]*:[[:space:]]*\"([a-z_]+)\" ]] || return 1
  dom_status="${BASH_REMATCH[1]}"
  for d in security infrastructure; do
    if [[ "$body" =~ \"domain\"[[:space:]]*:[[:space:]]*\"$d\" ]]; then dom_names+="$d, "; fi
  done
  dom_names="${dom_names%, }"
  case "$dom_status" in
    # approved_with_conditions também: não libera a edição (o Maestro não verifica condição).
    pending|needs_evidence|revise|denied|escalate|approved_with_conditions) if [[ "$settled" == 0 ]]; then dom_gate="domain"; fi ;;
  esac
  return 0
}

# maestro_domain_ask — só com pedido `pending` e socket da Ponte presente,
# uma vez por TTL (marcador `<sid>_domain`), sem depender da linha canônica:
# o pedido é FATO do record, não frase do gerente. Decisão que não libera
# (needs_evidence/revise/denied/escalate) não se pergunta de novo — muda o plano.
# shellcheck disable=SC2154  # ponte_sock e reentry vêm do gate-report.sh
maestro_domain_ask() {
  if [[ "$dom_status" == "pending" && -e "$ponte_sock" ]] && (( reentry == 0 )); then
    MCP_ASK_REASON_JSON="$MCP_DOMAIN_REASON_JSON" _maestro_mcp_ask_gate domain
  fi
  return 0
}
