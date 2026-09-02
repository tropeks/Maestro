#!/usr/bin/env bash
# E21 / S-2101 — hooks/gate-report.sh (Stop) + limpeza no user-prompt-submit.sh.
#
# Invariantes: fora do herdr é no-op absoluto; dentro, gate plan pendente
# (brief com approach: pendente em workflow plan-gated) ou gate ship sem desfecho
# deixam $MAESTRO_HOME/herdr/gates/<pane> com a pergunta e reportam `blocked`
# (best-effort); sem gate, o arquivo velho some; a resposta do humano
# (UserPromptSubmit) apaga o arquivo e libera a autoridade. Sempre exit 0, nada
# em stdout. Hermético: herdr FALSO via HERDR_BIN_PATH gravando os argumentos.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
STOP="$REPO/hooks/gate-report.sh"
UPS="$REPO/hooks/user-prompt-submit.sh"
SANDBOX=$(mktemp -d)
trap '[[ $$ == $BASHPID ]] && rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

FAKE="$SANDBOX/herdr"; CALLS="$SANDBOX/calls.log"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$CALLS" > "$FAKE"; chmod +x "$FAKE"

n=0; next_home() { n=$((n+1)); H="$SANDBOX/home$n"; mkdir -p "$H/sessions" "$H/logs"; }
record() { # record <sid> <workflow> <brief> [outcome]
  local o=""; [[ -n "${4:-}" ]] && o=",\"outcome\":\"$4\""
  printf '{"session_id":"%s","ts":"2026-09-02T00:00:00-03:00","expires_at":"2099-01-01T00:00:00-03:00","workflow":"%s","mode":"direct","reason":"segredo","brief":"%s"%s}\n' "$1" "$2" "$3" "$o" > "$H/sessions/$1.json"
}
stop() { # stop <sid> [VAR=VAL ...]
  local sid="$1"; shift
  printf '{"session_id":"%s","stop_hook_active":false}' "$sid" | env MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 \
    HERDR_BIN_PATH="$FAKE" CLAUDE_PROJECT_DIR="$SANDBOX/NetForge" "$@" bash "$STOP" >"$SANDBOX/out" 2>"$SANDBOX/err"
  RC=$?; OUT=$(cat "$SANDBOX/out")
}
gate_file() { printf '%s/herdr/gates/w9_p9' "$H"; }
gv() { sed -n "s/^$1=\(.*\)$/\1/p" "$(gate_file)" 2>/dev/null | head -1; }
mkdir -p "$SANDBOX/NetForge"

echo "-- fora do herdr: no-op absoluto"
next_home; record s1 feature "essencia: auto-update; impacto: x; approach: pendente"
printf '{"session_id":"s1"}' | MAESTRO_HOME="$H" HERDR_ENV=0 HERDR_BIN_PATH="$FAKE" bash "$STOP" >"$SANDBOX/out" 2>&1; chk "exit 0" "$?" "0"
[[ -e "$(gate_file)" ]] && bad "escreveu gate fora do herdr" || ok "sem arquivo de gate"
[[ -f "$CALLS" ]] && bad "chamou herdr fora do herdr" || ok "herdr não chamado"

echo "-- gate plan pendente: arquivo com a pergunta + report blocked"
stop s1; chk "exit 0" "$RC" "0"; chk "stdout vazio" "$OUT" ""
chk "gate=plan" "$(gv gate)" "plan"
chk "session" "$(gv session)" "s1"
chk "project = basename do projeto" "$(gv project)" "NetForge"
[[ "$(gv ts)" =~ ^[0-9]+$ ]] && ok "ts epoch" || bad "ts inválido"
chk "mensagem regida" "$(gv message)" "gate plan · NetForge · auto-update — Aprovo o plano? (aprovo | ajusta: …)"
grep -q "pane report-agent w9:p9 --source custom:maestro --agent claude --state blocked --message gate plan · NetForge" "$CALLS" \
  && ok "report-agent blocked com a mensagem" || bad "report-agent errado: $(cat "$CALLS" 2>/dev/null)"
grep -q segredo "$(gate_file)" && bad "reason vazou para o gate" || ok "reason não vaza"

echo "-- approach fechado: sem gate, arquivo velho some"
record s1 feature "essencia: auto-update; impacto: x; approach: lib bash"
stop s1; chk "exit 0" "$RC" "0"
[[ -e "$(gate_file)" ]] && bad "arquivo velho ficou" || ok "arquivo de gate removido"

echo "-- gate ship sem desfecho; com desfecho, some"
next_home; record s2 ship "essencia: v2.0"
stop s2; chk "gate=ship" "$(gv gate)" "ship"
chk "pergunta do ship" "$(gv message)" "gate ship · NetForge · v2.0 — Shipo agora? (shipa | espera)"
record s2 ship "essencia: v2.0" accepted
stop s2; [[ -e "$(gate_file)" ]] && bad "ship aceito ainda pendente" || ok "ship com desfecho: sem gate"

echo "-- workflow sem gate (fix) nunca escreve"
next_home; record s3 fix "essencia: bug; approach: pendente"
stop s3; [[ -e "$(gate_file)" ]] && bad "fix gerou gate" || ok "fix: sem gate"

echo "-- sem record / sem session_id / lixo / kill-switch: exit 0, nada"
next_home; stop s9; chk "sem record: exit 0" "$RC" "0"; [[ -e "$(gate_file)" ]] && bad "gate sem record" || ok "sem record: sem gate"
printf 'lixo' | MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 HERDR_BIN_PATH="$FAKE" bash "$STOP" >/dev/null 2>&1; chk "lixo: exit 0" "$?" "0"
record s4 feature "essencia: k; approach: pendente"
printf '{"session_id":"s4"}' | MAESTRO_OFF=1 MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 HERDR_BIN_PATH="$FAKE" bash "$STOP" >/dev/null 2>&1; chk "kill-switch: exit 0" "$?" "0"
[[ -e "$(gate_file)" ]] && bad "kill-switch não segurou" || ok "kill-switch vence"
printf '{"session_id":"s4"}' | MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID='../../etc' HERDR_BIN_PATH="$FAKE" bash "$STOP" >/dev/null 2>&1; chk "pane inválido: exit 0" "$?" "0"
[[ -d "$H/herdr" ]] && bad "pane inválido escreveu algo" || ok "pane fora do tipo: nada escrito"

echo "-- a resposta do humano (UserPromptSubmit) apaga o gate e libera a autoridade"
next_home; record s5 feature "essencia: k; approach: pendente"; stop s5
[[ -e "$(gate_file)" ]] && ok "gate pendente antes da resposta" || bad "gate não existia"
: > "$CALLS"
printf '{"session_id":"s5","prompt":"aprovo"}' | env MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 HERDR_BIN_PATH="$FAKE" bash "$UPS" >"$SANDBOX/ups.out" 2>/dev/null
chk "UserPromptSubmit exit 0" "$?" "0"
chk "stdout vazio (nunca injeta)" "$(cat "$SANDBOX/ups.out")" ""
[[ -e "$(gate_file)" ]] && bad "gate ficou depois da resposta" || ok "gate apagado pela resposta"
grep -q "pane release-agent w9:p9 --source custom:maestro --agent claude" "$CALLS" && ok "release-agent chamado" || bad "release ausente: $(cat "$CALLS")"
: > "$CALLS"
printf '{"session_id":"s5","prompt":"segue"}' | env MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 HERDR_BIN_PATH="$FAKE" bash "$UPS" >/dev/null 2>&1
[[ -s "$CALLS" ]] && bad "release repetido sem gate" || ok "sem gate, sem chamada"

echo
if [[ $fail -eq 0 ]]; then echo "test-gate-report: OK"; else echo "test-gate-report: FALHOU"; fi
exit $fail
