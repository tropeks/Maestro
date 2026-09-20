#!/usr/bin/env bash
# tests/hooks/test-order-029-gatilho.sh — ordem 029 (decisão do Capitão):
# o Maestro IMPÕE a convenção e FORÇA a chamada por MCP.
#
# Três caminhos, e o Stop deixa de liberar a rodada por TEXTO:
#   (1) paráfrase sem a linha canônica, com socket → REPROVA e manda reescrever
#   (2) canônica com socket → SEGURA até existir EVIDÊNCIA de director.ask
#   (3) sem socket → passa, e REGISTRA que passou sem a Ponte
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO/hooks/gate-report.sh"
PRE="$REPO/hooks/pre-director-ask.sh"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# A linha canônica é MONTADA, nunca escrita literal: um teste que a transcreve
# vira gatilho de si mesmo quando o arquivo passa pelo tail do transcript.
LB='['; RB=']'
CANON="${LB}spock${RB} aguardando:"

sock="$tmp/mcp.sock"
python3 - "$sock" <<'PY' 2>/dev/null || { echo "ok   (sem python3: fixture de socket pulada)"; exit 0; }
import socket,sys
s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])
PY

stop() { # $1=texto da rodada  $2=socket  $3=MAESTRO_HOME  → stdout do hook
  printf '{"session_id":"s029","stop_hook_active":false,"last_assistant_message":"%s"}' "$1" \
    | MAESTRO_HOME="$3" CLAUDE_PROJECT_DIR="$tmp/proj" PONTE_MCP_SOCKET="$2" \
      bash "$GATE" 2>/dev/null
}
mkdir -p "$tmp/proj"

echo "-- 029/1: PARÁFRASE sem a canônica, com socket → REPROVA"
h1=$(mktemp -d "$tmp/h.XXXXXX")
out=$(stop "Aguardo de voce: qual dos dois caminhos?" "$sock" "$h1")
grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"$out" \
  && ok "paráfrase é reprovada (decision: block)" || bad "paráfrase passou — devia reprovar"
grep -qi 'linha canonica\|linha exata' <<<"$out" \
  && ok "a mensagem manda reescrever com a linha" || bad "mensagem não ensina a correção"

echo "-- 029/2a: CANÔNICA com socket e SEM evidência → SEGURA"
h2=$(mktemp -d "$tmp/h.XXXXXX")
out=$(stop "$CANON qual dos dois?" "$sock" "$h2")
grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"$out" \
  && ok "canônica sem evidência: rodada segurada" || bad "liberou sem evidência de director.ask"
grep -qi 'director.ask' <<<"$out" \
  && ok "a mensagem manda chamar director.ask" || bad "mensagem não cita a tool"

echo "-- 029/2b: CANÔNICA com socket e COM evidência → LIBERA"
h3=$(mktemp -d "$tmp/h.XXXXXX")
printf '{"session_id":"s029","tool_name":"mcp__plugin_maestro_ponte__director_ask"}' \
  | MAESTRO_HOME="$h3" bash "$PRE" >/dev/null 2>&1
[[ -e "$h3/herdr/director-asked/s029" ]] \
  && ok "PreToolUse gravou a evidência da chamada" || bad "evidência não foi gravada"
out=$(stop "$CANON qual dos dois?" "$sock" "$h3")
grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"$out" \
  && bad "segurou mesmo COM evidência — a rodada devia ser liberada" \
  || ok "com evidência de director.ask: rodada liberada"

echo "-- 029/2c: a evidência é da tool CERTA (wait/report não liberam)"
h4=$(mktemp -d "$tmp/h.XXXXXX")
printf '{"session_id":"s029","tool_name":"mcp__plugin_maestro_ponte__director_wait"}' \
  | MAESTRO_HOME="$h4" bash "$PRE" >/dev/null 2>&1
[[ -e "$h4/herdr/director-asked/s029" ]] \
  && bad "director_wait gravou evidência — só ask prova que a pergunta foi ABERTA" \
  || ok "director_wait não grava evidência"

echo "-- 029/2d: a evidência é POR SESSÃO (não vaza entre sessões)"
h5=$(mktemp -d "$tmp/h.XXXXXX")
printf '{"session_id":"OUTRA","tool_name":"mcp__plugin_maestro_ponte__director_ask"}' \
  | MAESTRO_HOME="$h5" bash "$PRE" >/dev/null 2>&1
out=$(stop "$CANON qual dos dois?" "$sock" "$h5")
grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"$out" \
  && ok "evidência de outra sessão NÃO libera esta" || bad "evidência vazou entre sessões"

echo "-- 029/3: SEM socket → passa (Prioridade 1) e REGISTRA"
h6=$(mktemp -d "$tmp/h.XXXXXX")
out=$(stop "$CANON qual dos dois?" "$tmp/nao-existe.sock" "$h6")
grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"$out" \
  && bad "bloqueou sem Ponte — viola a Prioridade 1 do INTENT" \
  || ok "sem socket: a rodada passa, nunca bloqueia por componente ausente"
grep -q 'director_ask' "$h6/logs/routing.jsonl" 2>/dev/null \
  && ok "sem socket: o log registra que passou sem a Ponte" \
  || bad "sem socket: passou em SILÊNCIO — o log tem de saber"

echo "-- 029/4: rodada normal não dispara nada"
h7=$(mktemp -d "$tmp/h.XXXXXX")
out=$(stop "terminei a fatia, suite verde, nada pendente" "$sock" "$h7")
grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"$out" \
  && bad "rodada sem pergunta foi bloqueada (falso positivo)" \
  || ok "rodada sem pergunta: passa limpo"

echo "-- 029/4b: a razão emitida NÃO pode conter o marcador (auto-disparo)"
# Medido ao vivo: a razão antiga transcrevia o marcador, ia para o transcript, e o
# `tail -c` da rodada SEGUINTE o encontrava — três falsos positivos seguidos, sem
# pergunta pendente. O hook escrevia a causa do próprio disparo.
RE_CANON='\[[Ss]pock\][[:space:]]*[Aa]guardando[[:space:]]*:'
for v in MCP_ASK_REASON_JSON MCP_NUDGE_REASON_JSON; do
  linha=$(grep -o "^$v='.*'" "$GATE" || true)
  if [[ -z "$linha" ]]; then
    bad "$v não encontrada no gate"
  elif [[ "$linha" =~ $RE_CANON ]]; then
    bad "$v CONTÉM o marcador — vai se auto-disparar pelo transcript"
  else
    ok "$v descreve o marcador sem transcrevê-lo"
  fi
done

echo "-- 029/5: contrato do hook novo"
bash -n "$PRE" && ok "pre-director-ask.sh: sintaxe válida" || bad "pre-director-ask.sh: sintaxe quebrada"
head -1 "$PRE" | grep -q '^#!' && ok "shebang presente" || bad "sem shebang"
grep -q 'maestro_killswitch' "$PRE" && ok "kill-switch MAESTRO_OFF honrado" || bad "sem kill-switch"
if grep -qE '"(prompt|description)"' "$PRE"; then
  bad "o hook lê conteúdo do payload"
else
  ok "só metadados: não lê prompt nem argumentos"
fi
grep -qE 'bun|node |import ' "$PRE" && bad "hook invoca runtime proibido" || ok "bash puro"

exit $fail
