#!/usr/bin/env bash
# E23a / S-2301 — prova de delegação: hooks/pre-agent.sh (PreToolUse Agent|Task)
# e hooks/subagent-stop.sh (SubagentStop).
#
# O que estes testes travam:
#   - o disparo real vira `delegation phase=started` com o agente NORMALIZADO
#     (sem o prefixo `maestro:`), que é o mesmo nome que o `decide --agents`
#     grava — sem isso o funil não casa planned com started;
#   - `subagent_type` fora do tipo NÃO vira chave (log_event rejeitaria com
#     ruído no stderr do usuário);
#   - NADA do prompt/description do Task entra no log (ADR-008: vocabulário
#     fechado, só metadados);
#   - kill-switch, stdin vazio e lixo saem 0 sem efeito — hook observador nunca
#     atrapalha trabalho.
#
# Isolamento: MAESTRO_HOME em mktemp -d. O ~/.maestro real NUNCA é tocado.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PRE="$REPO/hooks/pre-agent.sh"
STOP="$REPO/hooks/subagent-stop.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export MAESTRO_HOME="$TMP/home"
mkdir -p "$MAESTRO_HOME/logs" "$MAESTRO_HOME/sessions"
LOG="$MAESTRO_HOME/logs/routing.jsonl"

command -v jq >/dev/null || { echo "FAIL jq ausente (dependência declarada)"; exit 1; }

reset_log() { : > "$LOG"; }
log_lines() { wc -l < "$LOG" 2>/dev/null | tr -d ' '; }
last()      { tail -1 "$LOG" 2>/dev/null; }

# run <hook> <payload> → RC / OUT / ERR
run() {
  OUT=$(printf '%s' "$2" | "$1" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}

SEGREDO='NAO-PODE-VAZAR-9f3a1c'

# ---------------------------------------------------------------------------
echo "-- pre-agent: Task com agente do plugin (prefixo maestro:)"
# ---------------------------------------------------------------------------
reset_log
run "$PRE" '{"session_id":"del-1","transcript_path":"/x/y.jsonl","cwd":"/home/user/proj","hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"description":"'"$SEGREDO"'","prompt":"'"$SEGREDO"' — texto longo do usuário","subagent_type":"maestro:dev-pleno"}}'
chk "Task com subagent_type → exit 0" "$RC" "0"
chk "uma linha no log" "$(log_lines)" "1"
chk "evento delegation" "$(last | jq -r .event)" "delegation"
chk "phase=started" "$(last | jq -r .phase)" "started"
chk "session_id correlacionado" "$(last | jq -r .session_id)" "del-1"
chk "agents é array (DATA_MODEL §4)" "$(last | jq -r '.agents|type')" "array"
chk "prefixo maestro: removido do nome do agente" "$(last | jq -r '.agents[0]')" "dev-pleno"
chk "stdout vazio (PreToolUse: stdout é canal de decisão)" "$OUT" ""
chk "sem ruído no stderr" "$ERR" ""

echo "-- o prompt do Task NÃO vaza para o log"
if grep -q "$SEGREDO" "$LOG"; then
  bad "texto do prompt/description apareceu no routing.jsonl"
else
  ok "nada do prompt/description no routing.jsonl"
fi
chk "log não tem chave prompt" "$(last | jq -r 'has("prompt")')" "false"
chk "log não tem chave description" "$(last | jq -r 'has("description")')" "false"
if grep -q '"/' "$LOG"; then bad "caminho vazou para o log"; else ok "nenhum caminho no log"; fi
chk "chaves do evento são só as do vocabulário" "$(last | jq -c 'keys_unsorted')" \
    '["ts","event","phase","session_id","agents"]'

# ---------------------------------------------------------------------------
echo "-- pre-agent: ferramenta Agent (o outro nome do mesmo matcher)"
# ---------------------------------------------------------------------------
reset_log
run "$PRE" '{"session_id":"del-2","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"prompt":"x","subagent_type":"revisor"}}'
chk "Agent → exit 0" "$RC" "0"
chk "phase=started" "$(last | jq -r .phase)" "started"
chk "agente sem prefixo passa direto" "$(last | jq -r '.agents[0]')" "revisor"

# ---------------------------------------------------------------------------
echo "-- pre-agent: subagent_type fora do tipo não vira chave"
# ---------------------------------------------------------------------------
for mau in 'Revisor Geral' '../../etc/passwd' 'a,b' 'MAIUSCULA'; do
  reset_log
  run "$PRE" '{"session_id":"del-3","tool_name":"Task","tool_input":{"subagent_type":"'"$mau"'"}}'
  chk "subagent_type '$mau' → exit 0" "$RC" "0"
  chk "subagent_type '$mau' → evento sai mesmo assim" "$(last | jq -r .phase)" "started"
  chk "subagent_type '$mau' → sem chave agents" "$(last | jq -r 'has("agents")')" "false"
  chk "subagent_type '$mau' → sem aviso no stderr do usuário" "$ERR" ""
done

reset_log
run "$PRE" '{"session_id":"del-4","tool_name":"Task","tool_input":{"prompt":"sem tipo declarado"}}'
chk "Task sem subagent_type → exit 0" "$RC" "0"
chk "Task sem subagent_type → started sem agents" "$(last | jq -r '.phase + ":" + (has("agents")|tostring)')" "started:false"

# ---------------------------------------------------------------------------
echo "-- subagent-stop: a volta do subagente"
# ---------------------------------------------------------------------------
reset_log
run "$STOP" '{"session_id":"del-5","hook_event_name":"SubagentStop","agent_type":"maestro:qa","transcript_path":"/x/y.jsonl"}'
chk "SubagentStop → exit 0" "$RC" "0"
chk "phase=received" "$(last | jq -r .phase)" "received"
chk "session_id correlacionado" "$(last | jq -r .session_id)" "del-5"
chk "agent_type vira agents (sem prefixo)" "$(last | jq -r '.agents[0]')" "qa"
chk "stdout vazio" "$OUT" ""
chk "sem ruído no stderr" "$ERR" ""

reset_log
run "$STOP" '{"session_id":"del-6","hook_event_name":"SubagentStop"}'
chk "SubagentStop sem nome de agente → received sem agents" \
    "$(last | jq -r '.phase + ":" + (has("agents")|tostring)')" "received:false"

reset_log
run "$STOP" '{"session_id":"del-7","hook_event_name":"SubagentStop","subagent_type":"dev-junior"}'
chk "SubagentStop com subagent_type (simetria com o PreToolUse)" "$(last | jq -r '.agents[0]')" "dev-junior"

# ---------------------------------------------------------------------------
echo "-- degradação: kill-switch, vazio, lixo, sessão fora do tipo"
# ---------------------------------------------------------------------------
reset_log
OUT=$(printf '%s' '{"session_id":"del-8","tool_name":"Task","tool_input":{"subagent_type":"dev-pleno"}}' \
      | MAESTRO_OFF=1 "$PRE" 2>&1); RC=$?
chk "MAESTRO_OFF=1 no pre-agent → exit 0" "$RC" "0"
chk "MAESTRO_OFF=1 no pre-agent → nada no log" "$(log_lines)" "0"
chk "MAESTRO_OFF=1 no pre-agent → nada na saída" "$OUT" ""

OUT=$(printf '%s' '{"session_id":"del-8","agent_type":"dev-pleno"}' | MAESTRO_OFF=1 "$STOP" 2>&1); RC=$?
chk "MAESTRO_OFF=1 no subagent-stop → exit 0" "$RC" "0"
chk "MAESTRO_OFF=1 no subagent-stop → nada no log" "$(log_lines)" "0"

for par in "pre-agent:$PRE" "subagent-stop:$STOP"; do
  nome="${par%%:*}"; hook="${par#*:}"
  reset_log
  run "$hook" ''
  chk "$nome com payload vazio → exit 0" "$RC" "0"
  chk "$nome com payload vazio → nada no log" "$(log_lines)" "0"

  run "$hook" 'isto nao e json { [ '
  chk "$nome com lixo → exit 0" "$RC" "0"
  chk "$nome com lixo → nada no log" "$(log_lines)" "0"

  run "$hook" '{"tool_name":"Task","tool_input":{"subagent_type":"dev-pleno"}}'
  chk "$nome sem session_id → exit 0" "$RC" "0"
  chk "$nome sem session_id → nada no log (evento solto não entra no funil)" "$(log_lines)" "0"

  run "$hook" '{"session_id":"nao vale como id","tool_name":"Task"}'
  chk "$nome com session_id fora do tipo → nada no log" "$(log_lines)" "0"

  "$hook" < /dev/null >/dev/null 2>&1; rc=$?
  chk "$nome sem stdin → exit 0" "$rc" "0"
done

echo "-- CLAUDE_SESSION_ID como fallback do payload"
reset_log
OUT=$(printf '%s' '{"tool_name":"Task","tool_input":{"subagent_type":"dev-pleno"}}' \
      | CLAUDE_SESSION_ID=del-env "$PRE" 2>&1); RC=$?
chk "sem session_id no payload, usa o do ambiente" "$(last | jq -r .session_id)" "del-env"

# ---------------------------------------------------------------------------
echo "-- prompt gigante: a janela de 4096 bytes não trava nem vaza"
# ---------------------------------------------------------------------------
reset_log
GRANDE=$(head -c 20000 /dev/zero | tr '\0' 'x')
run "$PRE" '{"session_id":"del-9","tool_name":"Task","tool_input":{"prompt":"'"$GRANDE$SEGREDO"'","subagent_type":"dev-pleno"}}'
chk "payload de 20KB → exit 0" "$RC" "0"
if grep -q "$SEGREDO" "$LOG"; then bad "prompt gigante vazou para o log"; else ok "prompt gigante não vaza"; fi
# O evento sai sem `agents` (o campo ficou fora da janela) — degradar o METADADO
# é aceitável; logar texto do usuário, jamais.
chk "sessão (cabeça do payload) sobrevive à janela" "$(last | jq -r .session_id)" "del-9"

# ---------------------------------------------------------------------------
echo "-- registro em hooks/hooks.json"
# ---------------------------------------------------------------------------
HJ="$REPO/hooks/hooks.json"
jq -e '.hooks.PreToolUse[] | select(.matcher == "Agent|Task") | .hooks[0]
       | (.command | test("pre-agent.sh")) and (.timeout == 5)' "$HJ" >/dev/null 2>&1 \
  && ok "hooks.json: PreToolUse matcher Agent|Task → pre-agent.sh (timeout 5)" \
  || bad "hooks.json não registra o pre-agent.sh no matcher Agent|Task"
jq -e '.hooks.SubagentStop[0].hooks[0]
       | (.command | test("subagent-stop.sh")) and (.timeout == 5)' "$HJ" >/dev/null 2>&1 \
  && ok "hooks.json: SubagentStop → subagent-stop.sh (timeout 5)" \
  || bad "hooks.json não registra o subagent-stop.sh"
jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit")' "$HJ" >/dev/null 2>&1 \
  && ok "hooks.json: gate estrutural preservado" || bad "hooks.json perdeu o gate estrutural"
[[ -x "$PRE" && -x "$STOP" ]] && ok "hooks novos com bit de execução" || bad "hook sem bit de execução"

# ---------------------------------------------------------------------------
echo "-- latência (NFR: <100ms por hook)"
# ---------------------------------------------------------------------------
measure() { # min de 7 execuções, em ms
  local t0 t1 ms min=999999
  for _ in 1 2 3 4 5 6 7; do
    t0=$(date +%s%N)
    printf '%s' "$2" | "$1" >/dev/null 2>&1
    t1=$(date +%s%N)
    ms=$(( (t1 - t0) / 1000000 ))
    (( ms < min )) && min=$ms
  done
  MIN=$min
}
reset_log
measure "$PRE" '{"session_id":"del-lat","tool_name":"Task","tool_input":{"subagent_type":"dev-pleno"}}'
printf '     pre-agent min=%sms (orçamento 100ms)\n' "$MIN"
(( MIN < 100 )) && ok "pre-agent <100ms" || bad "pre-agent estourou o NFR (${MIN}ms)"
measure "$STOP" '{"session_id":"del-lat","agent_type":"dev-pleno"}'
printf '     subagent-stop min=%sms (orçamento 100ms)\n' "$MIN"
(( MIN < 100 )) && ok "subagent-stop <100ms" || bad "subagent-stop estourou o NFR (${MIN}ms)"

if [[ "$MAESTRO_HOME" == "$TMP/home" ]]; then ok "estado isolado em mktemp -d"; else bad "MAESTRO_HOME escapou do tmpdir"; fi

exit $fail
