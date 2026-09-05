#!/usr/bin/env bash
# maestro hooks/pre-agent.sh — evento PreToolUse, matcher Agent|Task (E23a / S-2301)
#
# PROPÓSITO: provar que a delegação ACONTECEU. `maestro decide --agents` registra
# a APOSTA (fase `planned`); até aqui nada no Maestro via o disparo real de um
# subagente — "delegou" era palavra. Este hook fecha a metade que faltava: uma
# linha `delegation phase=started` por disparo do Task/Agent, correlacionada por
# `session_id`. O funil que o `maestro delegation` conta é
# planned → started → received → accepted.
#
# REGRAS DURAS (API_SPEC §1):
#   1. kill-switch primeiro; qualquer degradação sai 0.
#   2. SEMPRE exit 0 — observador, nunca gate. Delegação não se bloqueia aqui
#      (quem bloqueia edição é o pre-tool-gate).
#   3. Nada em stdout (`exec 1>&2`): stdout de PreToolUse é canal de decisão do
#      Claude Code.
#   4. Só metadados: `session_id` e `agents` (o `subagent_type`, sem o prefixo
#      `maestro:`, e só se casar `^[a-z0-9-]+$`). O `prompt` e a `description`
#      do Task NUNCA são lidos para log nem para decisão — é ali que mora o
#      texto do usuário, e o log do Maestro é fechado a metadado (ADR-008).
#
# Bash puro, sem jq (regex cobre o payload real), sem Bun, sem rede. Janela de
# 4096 bytes no stdin: o suficiente para a cabeça do payload (session_id e
# tool_input) sem pagar a leitura de um prompt inteiro. Prompt gigante que empurre
# o `subagent_type` para fora da janela degrada no ponto certo — o evento sai sem
# `agents`, nunca com um pedaço de texto.

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
# Sem sessão o evento não entra no funil (o `maestro delegation` correlaciona por
# session_id) — melhor não logar do que logar solto.
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 0

# `subagent_type` é o único campo do tool_input que interessa. O prefixo
# `maestro:` (agente do plugin) sai: no log o nome é o do roster, o mesmo que o
# `--agents` do decide grava, senão o funil não casaria planned com started.
agent=""
if [[ "$raw" =~ \"subagent_type\"[[:space:]]*:[[:space:]]*\"([^\"]{1,64})\" ]]; then
  agent="${BASH_REMATCH[1]}"
  agent="${agent#maestro:}"
  [[ "$agent" =~ ^[a-z0-9-]+$ ]] || agent=""
fi

log_event delegation phase=started session_id="$sid" ${agent:+agents="$agent"} || :
exit 0
