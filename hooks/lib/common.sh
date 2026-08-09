#!/usr/bin/env bash
# maestro hooks/lib/common.sh — regras canônicas (ENGINEERING_SPEC)
# REGRA: kill-switch é a PRIMEIRA coisa checada por todo hook (via maestro_killswitch).
# REGRA: log nunca bloqueia operação; nunca contém prompt nem caminho completo.

set -euo pipefail

MAESTRO_HOME="${MAESTRO_HOME:-$HOME/.maestro}"
MAESTRO_LOG_DIR="$MAESTRO_HOME/logs"
MAESTRO_SESSIONS_DIR="$MAESTRO_HOME/sessions"
MAESTRO_LOG_FILE="$MAESTRO_LOG_DIR/routing.jsonl"
MAESTRO_TTL_SECONDS="${MAESTRO_TTL_SECONDS:-14400}"   # 4h (ADR-003 v1.1)

# Kill-switch (S-102): sai do hook inteiro com exit 0, sem efeito algum.
maestro_killswitch() {
  if [[ "${MAESTRO_OFF:-0}" == "1" ]]; then
    exit 0
  fi
}

maestro_ensure_dirs() {
  mkdir -p "$MAESTRO_LOG_DIR" "$MAESTRO_SESSIONS_DIR" 2>/dev/null || true
}

# Vocabulário fechado de eventos (DATA_MODEL §4). Qualquer outro valor é descartado.
_maestro_event_valid() {
  case "$1" in
    decision|gate_pass|gate_warn|gate_block|override_manual|killswitch|session_end) return 0 ;;
    *) return 1 ;;
  esac
}

# log_event <event> [chave=valor]...   — valores passam por sanitização dura:
# só [A-Za-z0-9._/-], truncado em 80 chars. Nunca texto livre.
log_event() {
  local event="$1"; shift || true
  _maestro_event_valid "$event" || { echo "maestro: log: evento invalido descartado" >&2; return 0; }
  maestro_ensure_dirs
  local ts pairs="" k v
  ts=$(date -Iseconds)
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    k=$(printf '%s' "$k" | tr -cd 'a-z_' | cut -c1-32)
    v=$(printf '%s' "$v" | tr -cd 'A-Za-z0-9._/-' | cut -c1-80)
    [[ -n "$k" ]] && pairs="$pairs,\"$k\":\"$v\""
  done
  # Append atômico, lock NÃO bloqueante (flock -n): contenção descarta a linha.
  {
    exec 9>>"$MAESTRO_LOG_FILE"
    if flock -n 9; then
      printf '{"ts":"%s","event":"%s"%s}\n' "$ts" "$event" "$pairs" >&9
    else
      echo "maestro: log: contencao, linha descartada" >&2
    fi
  } 2>/dev/null || true
  return 0
}
