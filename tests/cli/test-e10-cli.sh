#!/usr/bin/env bash
# E10 / S-1001 + S-1002 + S-1004 — outcome (a variável dependente) e retro
# (a agregação determinística que fecha o loop de aprendizado).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v jq >/dev/null || { echo "FAIL jq ausente"; exit 1; }
command -v bun >/dev/null || { echo "FAIL bun ausente (decide precisa)"; exit 1; }

# E23a/S-2301 — `accepted` em mode subagent|multi exige prova de delegação no
# log. A prova sai do hook de verdade (integração, não fixture escrita à mão).
emit_started() { # emit_started <session_id> [agente]
  printf '{"session_id":"%s","tool_name":"Task","tool_input":{"subagent_type":"%s"}}' \
    "$1" "${2:-dev-pleno}" | "$REPO/hooks/pre-agent.sh" >/dev/null 2>&1 || true
}

echo "-- outcome fecha uma decisão existente"
"$BIN" decide --session out-1 --workflow fix --mode subagent --agents dev-pleno >/dev/null 2>&1
emit_started out-1
"$BIN" outcome --session out-1 accepted --suite pass >/dev/null; rc=$?
chk "outcome sobre record existente → exit 0" "$rc" "0"
REC="$MAESTRO_HOME/sessions/out-1.json"
chk "record ganha outcome" "$(jq -r .outcome "$REC")" "accepted"
chk "record ganha suite" "$(jq -r .suite "$REC")" "pass"
jq -e '.outcome_ts | length > 0' "$REC" >/dev/null && ok "outcome_ts carimbado" || bad "outcome_ts carimbado"
"$BIN" outcome --session out-1 rework >/dev/null
chk "último desfecho vence (rework sobrescreve)" "$(jq -r .outcome "$REC")" "rework"

echo "-- validações do outcome"
"$BIN" outcome --session sem-record accepted >/dev/null 2>&1; rc=$?
chk "sem record → exit 1 (desfecho fecha decisão, não a inventa)" "$rc" "1"
"$BIN" outcome --session out-1 talvez >/dev/null 2>&1; rc=$?
chk "veredito fora do enum → exit 1" "$rc" "1"
"$BIN" outcome --session out-1 accepted --suite quase >/dev/null 2>&1; rc=$?
chk "--suite fora do enum → exit 1" "$rc" "1"

LOG="$MAESTRO_HOME/logs/routing.jsonl"
grep -q '"event":"outcome".*"outcome":"accepted"' "$LOG" && ok "outcome no log (enum)" || bad "outcome no log"

# ---------------------------------------------------------------------------
echo "-- E23a/S-2301: aceitar trabalho delegado exige prova de delegação"
# ---------------------------------------------------------------------------
chk "record com prova ganha delegation_proof=started" \
    "$(jq -r '.delegation_proof // "AUSENTE"' "$REC")" "started"

"$BIN" decide --session del-a --workflow fix --mode subagent --agents dev-pleno >/dev/null 2>&1
out=$("$BIN" outcome --session del-a accepted 2>&1); rc=$?
chk "subagent sem 'delegation phase=started' → accepted recusado (exit 1)" "$rc" "1"
grep -q 'prova de delegação' <<<"$out" && ok "recusa explica que falta prova" || bad "recusa sem explicação ($out)"
grep -q 'maestro delegation --session del-a' <<<"$out" \
  && ok "recusa cita o comando que mostra o funil" || bad "recusa não cita maestro delegation"
grep -q -- '--unproven' <<<"$out" && ok "recusa cita a válvula honesta" || bad "recusa não cita --unproven"
chk "record recusado NÃO recebe outcome" "$(jq -r '.outcome // "AUSENTE"' "$MAESTRO_HOME/sessions/del-a.json")" "AUSENTE"

out=$("$BIN" outcome --session del-a accepted --unproven 2>&1); rc=$?
chk "--unproven passa (exit 0)" "$rc" "0"
chk "--unproven grava delegation_proof=none" \
    "$(jq -r '.delegation_proof' "$MAESTRO_HOME/sessions/del-a.json")" "none"
grep -q 'SEM prova de delegação' <<<"$out" && ok "--unproven avisa o que foi assumido" || bad "--unproven silencioso ($out)"

"$BIN" decide --session del-b --workflow fix --mode multi --agents dev-pleno,revisor >/dev/null 2>&1
"$BIN" outcome --session del-b accepted >/dev/null 2>&1; rc=$?
chk "multi sem prova também é recusado" "$rc" "1"
emit_started del-b revisor
"$BIN" outcome --session del-b accepted >/dev/null 2>&1; rc=$?
chk "multi com started → aceito" "$rc" "0"
chk "multi com started grava delegation_proof=started" \
    "$(jq -r '.delegation_proof' "$MAESTRO_HOME/sessions/del-b.json")" "started"

"$BIN" decide --session del-c --workflow fix --mode direct >/dev/null 2>&1
"$BIN" outcome --session del-c accepted >/dev/null 2>&1; rc=$?
chk "direct não exige prova (exit 0)" "$rc" "0"
chk "direct NÃO grava delegation_proof" \
    "$(jq -r 'has("delegation_proof")' "$MAESTRO_HOME/sessions/del-c.json")" "false"

"$BIN" decide --session del-d --workflow fix --mode subagent --agents dev-pleno >/dev/null 2>&1
"$BIN" outcome --session del-d rework >/dev/null 2>&1; rc=$?
chk "rework/reverted não passam pelo gate (só accepted)" "$rc" "0"
chk "rework não grava delegation_proof" \
    "$(jq -r 'has("delegation_proof")' "$MAESTRO_HOME/sessions/del-d.json")" "false"

echo "-- maestro delegation: o funil"
out=$("$BIN" delegation --session del-b); rc=$?
chk "delegation --session → exit 0" "$rc" "0"
grep -qE 'planned *: *1' <<<"$out" && ok "conta planned (decide --agents)" || bad "planned ($out)"
grep -qE 'started *: *1' <<<"$out" && ok "conta started (hook pre-agent)" || bad "started ($out)"
grep -qE 'received *: *0' <<<"$out" && ok "conta received" || bad "received ($out)"
grep -qE 'accepted *: *0' <<<"$out" && ok "conta accepted" || bad "accepted ($out)"
printf '{"session_id":"del-b","hook_event_name":"SubagentStop","agent_type":"revisor"}' \
  | "$REPO/hooks/subagent-stop.sh" >/dev/null 2>&1
out=$("$BIN" delegation --session del-b)
grep -qE 'received *: *1' <<<"$out" && ok "subagent-stop entra no funil" || bad "received após stop ($out)"
grep -q 'delegação provada' <<<"$out" && ok "veredito: delegação provada" || bad "veredito provada ($out)"
out=$("$BIN" delegation --session del-a)
grep -q 'planejada e NÃO disparada' <<<"$out" \
  && ok "veredito: planejada sem disparo" || bad "veredito planned-sem-started ($out)"
out=$("$BIN" delegation --session sessao-sem-nada)
grep -q 'sem delegação registrada' <<<"$out" && ok "sessão sem funil é dita, não inventada" || bad "sessão vazia ($out)"
out=$("$BIN" delegation --all); rc=$?
chk "delegation --all → exit 0" "$rc" "0"
grep -q 'del-b' <<<"$out" && ok "--all lista as sessões vistas" || bad "--all sem del-b ($out)"
grep -qE 'del-b +1 +1 +1 +0' <<<"$out" && ok "--all agrega por sessão" || bad "--all agregação ($out)"
"$BIN" delegation --session del-b --flag-que-nao-existe >/dev/null 2>&1; rc=$?
chk "flag desconhecida → exit 1" "$rc" "1"
"$BIN" delegation >/dev/null 2>&1; rc=$?
chk "sem --session nem --all → exit 1" "$rc" "1"
# O funil também lê os rotacionados (DATA_MODEL §4): sessão longa que cruzou uma
# rotação não pode perder a prova que já tinha.
ROT="$MAESTRO_HOME/logs/routing-2026-01.jsonl"
printf '{"ts":"2026-01-02T10:00:00-03:00","event":"delegation","phase":"started","session_id":"del-rot"}\n' > "$ROT"
"$BIN" decide --session del-rot --workflow fix --mode subagent --agents dev-pleno >/dev/null 2>&1
"$BIN" outcome --session del-rot accepted >/dev/null 2>&1; rc=$?
chk "prova em log rotacionado vale (accepted exit 0)" "$rc" "0"
out=$("$BIN" delegation --session del-rot)
grep -qE 'started *: *1' <<<"$out" && ok "delegation conta o rotacionado" || bad "rotacionado ($out)"
rm -f "$ROT"

if grep -q '"event":"delegation"' "$LOG"; then ok "eventos de delegação no log"; else bad "eventos de delegação no log"; fi
if grep -q '"/' "$LOG"; then bad "log sem caminho"; else ok "log sem caminho de arquivo"; fi

echo "-- retro agrega a janela"
# fixture: log sintético controlado (hoje, dentro de qualquer janela)
TS=$(date -Iseconds)
mkdir -p "$MAESTRO_HOME/logs"
cat > "$LOG" <<J
{"ts":"$TS","event":"decision","session_id":"r1","workflow":"fix","mode":"subagent","agents":["dev-pleno"]}
{"ts":"$TS","event":"decision","session_id":"r2","workflow":"fix","mode":"direct"}
{"ts":"$TS","event":"decision","session_id":"r3","workflow":"feature","mode":"multi","agents":["engenheiro","typescript-pro"]}
{"ts":"$TS","event":"override_manual","session_id":"r4","cmd":"gstack-ship"}
{"ts":"$TS","event":"gate_pass","session_id":"r1","tool":"Edit","file_ext":".py","gate_mode":"warn"}
{"ts":"$TS","event":"gate_warn","session_id":"r4","tool":"Edit","file_ext":".ts","gate_mode":"warn"}
{"ts":"$TS","event":"habit_warn","session_id":"r1","smell":"swallowed-error","n":"2","file_ext":".py"}
{"ts":"$TS","event":"habit_warn","session_id":"r2","smell":"swallowed-error","n":"1","file_ext":".py"}
{"ts":"$TS","event":"habit_warn","session_id":"r3","smell":"debug-leftover","n":"1","file_ext":".ts"}
{"ts":"$TS","event":"outcome","session_id":"r1","outcome":"accepted","suite":"pass"}
{"ts":"$TS","event":"outcome","session_id":"r3","outcome":"rework"}
{"ts":"$TS","event":"consent_grant","session_id":"r1","scope":"routing-table"}
J
out=$("$BIN" retro --days 7); rc=$?
chk "retro → exit 0" "$rc" "0"
grep -q 'decisões: 3 · override roteável: 1 · não-roteável: 0 · taxa de override: 33%' <<<"$out" \
  && ok "taxa de override calculada (1 roteável de 3 decisões = 33%)" || bad "taxa de override ($out)"
grep -q 'swallowed-error: 2' <<<"$out" && ok "smells ordenados por frequência" || bad "smells por frequência"
grep -q 'accepted: 1' <<<"$out" && ok "desfechos agregados" || bad "desfechos agregados"
grep -q 'grant 1' <<<"$out" && ok "consentimentos contados" || bad "consentimentos contados"
grep -q 'sem uso na janela' <<<"$out" && ok "workflows declarados sem uso aparecem" || bad "workflows sem uso"
grep -q 'override em 33% (≥20%)' <<<"$out" \
  && ok "sinal de calibração dispara com override alto" || bad "sinal de calibração"
grep -q 'promoção warn→block: ainda não' <<<"$out" \
  && ok "promoção NÃO elegível com 3 decisões (piso é 10)" || bad "promoção não elegível"

echo "-- S-1004: promoção elegível só com critério cheio"
for i in $(seq 5 16); do
  printf '{"ts":"%s","event":"decision","session_id":"p%s","workflow":"fix","mode":"subagent"}\n' "$TS" "$i" >> "$LOG"
done
out=$("$BIN" retro --days 14)
grep -q 'PROMOÇÃO ELEGÍVEL' <<<"$out" \
  && ok "≥14d, ≥10 decisões, override <20% → propõe warn→block" || bad "promoção elegível ($out)"
grep -q 'exige consentimento ou mão humana' <<<"$out" \
  && ok "a proposta lembra que aplicar exige consent" || bad "proposta lembra do consent"

echo "-- honestidade com log vazio"
rm -f "$LOG"
out=$(MAESTRO_HOME="$tmp/vazio" "$BIN" retro); rc=$?
chk "sem log → exit 0" "$rc" "0"
grep -q 'sem dados' <<<"$out" && ok "diz que não há dado, não inventa conclusão" || bad "honestidade sem dados"

echo "-- S-1801: taxa de override conta só comando ROTEÁVEL (skill: dos bindings + workflows)"
RTHOME="$tmp/s1801"
export MAESTRO_HOME="$RTHOME"
mkdir -p "$MAESTRO_HOME/logs"
RTLOG="$MAESTRO_HOME/logs/routing.jsonl"
TS2=$(date -Iseconds)
{
  for i in $(seq 1 10); do
    printf '{"ts":"%s","event":"decision","session_id":"s%s","workflow":"fix","mode":"subagent"}\n' "$TS2" "$i"
  done
  printf '{"ts":"%s","event":"override_manual","session_id":"o0","cmd":"gstack-ship"}\n' "$TS2"
  for i in $(seq 1 5); do
    printf '{"ts":"%s","event":"override_manual","session_id":"o%s","cmd":"gstack-context-restore"}\n' "$TS2" "$i"
  done
} > "$RTLOG"
RTFIX="$tmp/routing-table-fixture.yaml"
cat > "$RTFIX" <<Y
version: 2
workflows:
  fix: {steps: [investigate], gate: none}
bindings:
  ship: skill:gstack-ship
Y
out=$(MAESTRO_ROUTING_TABLE="$RTFIX" "$BIN" retro --days 7); rc=$?
chk "retro com tabela fixture → exit 0" "$rc" "0"
grep -q 'decisões: 10 · override roteável: 1 · não-roteável: 5 · taxa de override: 10%' <<<"$out" \
  && ok "taxa conta só o roteável (1/10 = 10%, não 6/10 = 60%)" || bad "taxa roteável ($out)"
grep -q 'não-roteável: 5' <<<"$out" && ok "invocação de ciclo de vida contada à parte" || bad "não-roteável: 5"

out=$(MAESTRO_ROUTING_TABLE="$tmp/nao-existe.yaml" "$BIN" retro --days 7); rc=$?
chk "retro sem tabela (degrade) → exit 0, nunca quebra" "$rc" "0"
grep -q -- '-- aviso:' <<<"$out" && ok "degrade avisa que o filtro roteável não pôde ser derivado" || bad "aviso de degrade"
grep -q 'override roteável: 6' <<<"$out" \
  && ok "degrade conta como antes (6 override_manual no total)" || bad "degrade conta 6 ($out)"

echo "-- comando /maestro:retro registrado"
CMD="$REPO/commands/retro.md"
[[ -f "$CMD" ]] && ok "commands/retro.md existe" || bad "commands/retro.md existe"
grep -q 'maestro retro' "$CMD" && ok "usa o relatório determinístico como fonte" || bad "usa maestro retro"
grep -q 'consent --grant' "$CMD" && ok "fluxo de consentimento no comando" || bad "fluxo de consentimento"
grep -q 'eval' "$CMD" && ok "exame (eval-on-diff) antes do commit" || bad "exame antes do commit"
grep -q 'revoke' "$CMD" && ok "revogação após aplicar" || bad "revogação após aplicar"

exit $fail
