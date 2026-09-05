#!/usr/bin/env bash
# maestro hooks/subagent-stop.sh — evento SubagentStop (E23a / S-2301)
#
# PROPÓSITO: a outra ponta do disparo. `pre-agent.sh` prova que o subagente
# COMEÇOU (`phase=started`); este prova que ele VOLTOU (`phase=received`). A
# diferença entre os dois no funil (`maestro delegation`) é a delegação que
# morreu no meio — subagente disparado e nunca colhido.
#
# Mesmas regras duras do pre-agent.sh: kill-switch primeiro, sempre exit 0, nada
# em stdout, só metadados (`session_id` e, quando o payload traz, o `agent_type`
# — nunca o transcript, nunca o resultado do subagente). Bash puro, sem jq, sem
# Bun, sem rede; janela de 4096 bytes no stdin.

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

raw=""
IFS= read -r -d '' -t 2 -n 4096 raw 2>/dev/null || :
[[ -n "$raw" ]] || exit 0

sid=""
if [[ "$raw" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,64})\" ]]; then
  sid="${BASH_REMATCH[1]}"
fi
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || sid="${CLAUDE_SESSION_ID:-}"
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 0

# O payload do SubagentStop nem sempre nomeia o agente; quando nomeia, o campo é
# `agent_type` (o `subagent_type` é aceito por simetria com o PreToolUse). Sem
# nome, o evento sai só com a sessão — o funil conta a volta do mesmo jeito.
agent=""
if [[ "$raw" =~ \"agent_type\"[[:space:]]*:[[:space:]]*\"([^\"]{1,64})\" ]] ||
   [[ "$raw" =~ \"subagent_type\"[[:space:]]*:[[:space:]]*\"([^\"]{1,64})\" ]]; then
  agent="${BASH_REMATCH[1]}"
  agent="${agent#maestro:}"
  [[ "$agent" =~ ^[a-z0-9-]+$ ]] || agent=""
fi

log_event delegation phase=received session_id="$sid" ${agent:+agents="$agent"} || :
exit 0
