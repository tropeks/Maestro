#!/usr/bin/env bash
# hooks/pre-director-ask.sh — PreToolUse, matcher das tools `director_*` da Ponte.
#
# Ordem 029 (decisão do Capitão): o Stop deixa de liberar a rodada por TEXTO e
# passa a liberar por EVIDÊNCIA de que o gerente chamou `director.ask`. Este hook
# é essa evidência: quando a tool é de fato chamada, ele grava um marcador por
# sessão; o `gate-report.sh` (Stop) libera contra o marcador, não contra a prosa.
#
# Por que aqui e não lendo o daemon: a decisão aberta mora em `~/.ponte/ponte.db`
# (SQLite). Lê-la custaria `sqlite3` como dependência dura nova — que o próprio
# `pre-bash-guard.sh` classifica como comando de banco — e acoplaria o Maestro ao
# esquema interno de OUTRO produto, que o INTENT põe em "Fora de escopo" ("os
# gerentes e o supervisor vivem em repos próprios"). Tool passa por PreToolUse, e
# PreToolUse é do Maestro. O precedente é o `pre-agent.sh`, que observa `Agent|Task`
# e emite o funil de delegação sem ler prompt nenhum.
#
# Só metadados: `session_id` e o nome da tool. O `prompt`, a `description` e os
# ARGUMENTOS da chamada (que carregam a pergunta ao Diretor) NUNCA são lidos — nem
# para log, nem para decisão. A pergunta é conteúdo; o marcador é fato.
#
# Bash puro, sem jq, sem Bun, sem rede. Janela de 4096 bytes no stdin. Sempre
# exit 0, nada em stdout: observador, nunca gate (stdout de PreToolUse é canal de
# decisão do Claude Code).

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
# Sem sessão tipada não há marcador: o Stop correlaciona por session_id, e um
# marcador solto liberaria a rodada errada.
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 0

# `tool_name` é o único campo que interessa. O matcher do hooks.json já filtra,
# mas revalidamos aqui: cinto e suspensório, igual ao user-prompt-submit.sh.
# Só `ask` marca — `director_wait`/`director_report` são outras tools e não provam
# que a pergunta foi ABERTA.
tool=""
if [[ "$raw" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]{1,128})\" ]]; then
  tool="${BASH_REMATCH[1]}"
fi
[[ "$tool" == *director_ask* ]] || exit 0

# O marcador vive ao lado do de não-laço da 020/025, sob $MAESTRO_HOME — estado de
# máquina, nunca no repo. mkdir -p e touch degradam em silêncio (I-2): disco cheio
# ou permissão negada não derruba a chamada da tool.
asked_dir="${MAESTRO_HOME:-$HOME/.maestro}/herdr/director-asked"
mkdir -p "$asked_dir" 2>/dev/null || exit 0
: > "$asked_dir/$sid" 2>/dev/null || exit 0

log_event director_ask session_id="$sid"

exit 0
