#!/usr/bin/env bash
# maestro hooks/session-end.sh — evento SessionEnd (E18 fase 2 / S-1811)
#
# PROPÓSITO: fechar a conta da sessão no log. `decision` registra a aposta e
# `outcome` registra se ela pagou — mas sessão que acaba SEM desfecho (ou sem
# decisão nenhuma) era invisível ao retro: o evento `session_end` existia no
# vocabulário desde o E2 e nada o emitia. Uma linha por fim de sessão, só
# metadados: houve decision record? (decided) houve desfecho registrado?
# (settled). O retro cruza com `decision` por session_id.
#
# REGRAS DURAS (API_SPEC §1):
#  1. SEMPRE exit 0. Fim de sessão não é lugar de bloquear nada.
#  2. Nada em stdout (exec 1>&2) — por simetria com os outros hooks.
#  3. Só metadados: session_id (tipado), decided/settled (yes|no). Nada do
#     record (brief, flags, reason) sai daqui — o record é 0600 por um motivo.
#  4. Degrada em silêncio: kill-switch, stdin vazio/tty/lixo, lib ausente.
#
# Bash puro, sem jq (regex cobre o payload real), sem Bun, sem rede.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
if ! source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null; then
  exit 0
fi
maestro_killswitch
exec 1>&2

[[ -t 0 ]] && exit 0

raw=""
read -r -t 2 -N 262144 raw || :
sid=""
if [[ -n "$raw" && "$raw" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,64})\" ]]; then
  sid="${BASH_REMATCH[1]}"
fi
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || sid="${CLAUDE_SESSION_ID:-}"
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 0

# O record diz se houve decisão; o campo outcome diz se houve desfecho.
# Leitura por regex, sem parser: só precisamos de presença + enum fechado.
decided="no"; settled="no"
rec="${MAESTRO_SESSIONS_DIR:-$MAESTRO_HOME/sessions}/$sid.json"
if [[ -f "$rec" && -r "$rec" ]]; then
  body=$(head -c 65536 -- "$rec" 2>/dev/null) || body=""
  if [[ "$body" =~ \"workflow\"[[:space:]]*:[[:space:]]*\"[a-z]+\" ]]; then decided="yes"; fi
  if [[ "$body" =~ \"outcome\"[[:space:]]*:[[:space:]]*\"(accepted|rework|reverted)\" ]]; then settled="yes"; fi
fi

log_event session_end session_id="$sid" decided="$decided" settled="$settled" || :
exit 0
