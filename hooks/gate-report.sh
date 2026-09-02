#!/usr/bin/env bash
# maestro hooks/gate-report.sh — evento Stop (E21 / S-2101)
#
# PROPÓSITO: quando o turno termina com um GATE HUMANO pendente (plan: brief com
# `approach: pendente` em workflow plan-gated; ship: workflow ship sem desfecho),
# deixa a pergunta num lugar que um transporte externo consegue ler — o herdr
# (runtime das sessões) e, por cima dele, o forwarder do Telegram (Legatus vNext).
#
# Duas saídas, ambas só dentro do herdr (HERDR_ENV=1 + HERDR_PANE_ID):
#   1. $MAESTRO_HOME/herdr/gates/<pane> — chave=valor: gate, session, project,
#      ts, message. É a mensagem LIMPA que o forwarder prefere ao scrape da tela.
#   2. `herdr pane report-agent … --state blocked --message …` — best-effort:
#      para o Claude Code a autoridade de estado é a leitura de tela do herdr
#      (docs "Status authority"), então este report pode ser ignorado; custa um
#      fork e não muda nada quando ignorado. Quem responde (UserPromptSubmit)
#      apaga o arquivo e libera a autoridade.
#
# Sem gate pendente, apaga um arquivo velho do mesmo pane (o gate foi resolvido
# por outro caminho) e sai. REGRAS: sempre exit 0; nada em stdout (um Stop hook
# com JSON no stdout vira decisão do Claude Code); só metadados + a essência
# do brief (texto regido, ≤200 chars, que o Capitão já leu); bash puro, sem jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
if ! source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null; then
  exit 0
fi
maestro_killswitch
exec 1>&2

[[ "${HERDR_ENV:-}" == "1" ]] || exit 0
PANE="${HERDR_PANE_ID:-}"
[[ "$PANE" =~ ^[A-Za-z0-9:_-]{1,32}$ ]] || exit 0
GATES_DIR="$MAESTRO_HOME/herdr/gates"
GATE_FILE="$GATES_DIR/${PANE//:/_}"

raw=""
[[ -t 0 ]] || read -r -t 2 -N 262144 raw || :
sid=""
if [[ -n "$raw" && "$raw" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,64})\" ]]; then
  sid="${BASH_REMATCH[1]}"
fi
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || sid="${CLAUDE_SESSION_ID:-}"
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 0

# ---------------------------------------------------------------------------
# Há gate pendente? Leitura por regex do record (presença + enums), como no
# session-end.sh — nada de parser.
# ---------------------------------------------------------------------------
rec="${MAESTRO_SESSIONS_DIR:-$MAESTRO_HOME/sessions}/$sid.json"
gate=""; essencia=""
if [[ -f "$rec" && -r "$rec" ]]; then
  body=$(head -c 65536 -- "$rec" 2>/dev/null) || body=""
  wf=""; [[ "$body" =~ \"workflow\"[[:space:]]*:[[:space:]]*\"([a-z]+)\" ]] && wf="${BASH_REMATCH[1]}"
  settled=0; [[ "$body" =~ \"outcome\"[[:space:]]*:[[:space:]]*\"(accepted|rework|reverted)\" ]] && settled=1
  case "$wf" in
    feature|refactor)
      # gate plan: approach ainda pendente no brief regido
      if [[ "$body" =~ approach:[[:space:]]*pendente ]]; then gate="plan"; fi ;;
    ship)
      (( settled == 0 )) && gate="ship" ;;
  esac
  if [[ "$body" =~ essencia:[[:space:]]*([^;\"]{1,200}) ]]; then
    essencia="${BASH_REMATCH[1]}"
    essencia="${essencia%"${essencia##*[![:space:]]}"}"
  fi
fi

if [[ -z "$gate" ]]; then
  rm -f -- "$GATE_FILE" 2>/dev/null || :
  exit 0
fi

project="${CLAUDE_PROJECT_DIR:-$PWD}"; project="${project##*/}"
[[ "$project" =~ ^[A-Za-z0-9._-]{1,48}$ ]] || project="projeto"
case "$gate" in
  plan) message="gate plan · $project${essencia:+ · $essencia} — Aprovo o plano? (aprovo | ajusta: …)" ;;
  ship) message="gate ship · $project${essencia:+ · $essencia} — Shipo agora? (shipa | espera)" ;;
esac
# uma linha só: quebras viram espaço (o arquivo é chave=valor por linha)
message="${message//$'\n'/ }"; message="${message//$'\r'/ }"

mkdir -p "$GATES_DIR" 2>/dev/null || exit 0
tmp="$GATE_FILE.tmp.$$"
{
  printf 'gate=%s\n' "$gate"
  printf 'session=%s\n' "$sid"
  printf 'project=%s\n' "$project"
  printf 'ts=%s\n' "$(maestro_now_epoch 2>/dev/null || date +%s)"
  printf 'message=%s\n' "$message"
} > "$tmp" 2>/dev/null && mv -f "$tmp" "$GATE_FILE" 2>/dev/null || { rm -f "$tmp"; exit 0; }

# best-effort: report ao herdr (pode ser ignorado pela autoridade de tela)
bin="${HERDR_BIN_PATH:-herdr}"
if command -v "$bin" >/dev/null 2>&1 || [[ -x "$bin" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    timeout 2 "$bin" pane report-agent "$PANE" --source custom:maestro --agent claude \
      --state blocked --message "$message" --seq "$(date +%s%N 2>/dev/null || date +%s)" >/dev/null 2>&1 || :
  else
    "$bin" pane report-agent "$PANE" --source custom:maestro --agent claude \
      --state blocked --message "$message" --seq "$(date +%s%N 2>/dev/null || date +%s)" >/dev/null 2>&1 || :
  fi
fi
exit 0
