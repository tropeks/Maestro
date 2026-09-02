#!/usr/bin/env bash
# E20 / S-2001 — hooks/lib/telemetry-sync.sh via hooks/session-end.sh.
#
# Invariantes: opt-in (sem telemetry_remote nada sai da máquina); só routing*.jsonl
# viaja, em logs/<host-id>/, um escritor por arquivo; push honra o intervalo;
# dois hosts publicam sem conflito (rebase limpo); push falho fica registrado e a
# rodada seguinte publica o que ficou; remoto quebrado nunca quebra o hook (exit
# 0, teto de tempo); pull traz os outros hosts. Hermético: bare remote file://.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-end.sh"
LIB="$REPO/hooks/lib/telemetry-sync.sh"
SANDBOX=$(mktemp -d)
trap '[[ $$ == $BASHPID ]] && rm -rf "$SANDBOX"' EXIT   # só o shell principal limpa; subshell de pipeline não

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
command -v git >/dev/null || { echo "FAIL git ausente"; exit 1; }

REMOTE="$SANDBOX/remote.git"; git init -q --bare "$REMOTE"
home_of() { printf '%s/home-%s' "$SANDBOX" "$1"; }
mk_host() { # mk_host <a|b> — home com log e config apontando para o remoto
  local h; h=$(home_of "$1"); mkdir -p "$h/logs" "$h/sessions"
  printf '{"ts":"2026-09-01T00:00:00-03:00","event":"decision","session_id":"%s1","workflow":"fix","mode":"direct"}\n' "$1" > "$h/logs/routing.jsonl"
  printf 'telemetry_remote: %s\n' "$REMOTE" > "$h/config.yaml"
}
end() { # end <a|b> [VAR=VAL ...] — roda o SessionEnd do host; RC e estado
  local n="$1" h; h=$(home_of "$n"); shift
  printf '{"session_id":"s-%s"}' "$n" | env MAESTRO_HOME="$h" MAESTRO_HOST_ID="host$n$n$n$n" \
    MAESTRO_TELEMETRY_TIMEOUT=5 "$@" bash "$HOOK" >"$SANDBOX/out" 2>"$SANDBOX/err"
  RC=$?
}
st() { sed -n "s/^$2=\(.*\)$/\1/p" "$(home_of "$1")/telemetry-state" 2>/dev/null | head -1; }
remote_files() { git --git-dir="$REMOTE" ls-tree -r --name-only main 2>/dev/null | tr '\n' ' '; }

echo "-- sem telemetry_remote: nada sai, nada é gravado"
mk_host a; : > "$(home_of a)/config.yaml"
end a; chk "exit 0" "$RC" "0"
[[ -f "$(home_of a)/telemetry-state" ]] && bad "estado gravado sem config" || ok "sem estado: opt-in respeitado"
[[ -z "$(remote_files)" ]] && ok "remoto vazio" || bad "algo foi publicado sem config"

echo "-- MAESTRO_NO_TELEMETRY=1 desliga mesmo com config"
mk_host a; end a MAESTRO_NO_TELEMETRY=1
[[ -f "$(home_of a)/telemetry-state" ]] && bad "desligada e gravou" || ok "env desliga"

echo "-- primeiro push: clone criado, logs/<host>/ no remoto"
end a; chk "exit 0" "$RC" "0"
chk "result=pushed" "$(st a result)" "pushed"
chk "host id" "$(st a host)" "hostaaaa"
chk "1 arquivo" "$(st a files)" "1"
[[ "$(remote_files)" == *"logs/hostaaaa/routing-current.jsonl"* ]] && ok "routing-current.jsonl publicado" || bad "arquivo ausente: $(remote_files)"
[[ "$(remote_files)" == *"logs/hostaaaa/HOST"* ]] && ok "HOST publicado" || bad "HOST ausente"
[[ "$(remote_files)" == *sessions* || "$(remote_files)" == *brief* ]] && bad "algo além do log viajou" || ok "só o log viaja"
chk "branch do barramento é main" "$(git --git-dir="$REMOTE" rev-parse --abbrev-ref main 2>/dev/null)" "main"
grep -q '"event":"session_end"' "$(home_of a)/telemetry/logs/hostaaaa/routing-current.jsonl" \
  && ok "o session_end desta mesma sessão já foi junto" || bad "log copiado antes do session_end"

echo "-- dentro do intervalo: skipped, estado preservado"
P1=$(st a pushed); end a
chk "result segue pushed (skipped não regrava)" "$(st a result)" "pushed"
chk "pushed intacto" "$(st a pushed)" "$P1"

echo "-- segundo host publica; o primeiro faz rebase e publica o que mudou"
mk_host b; end b; chk "b: pushed" "$(st b result)" "pushed"
end a MAESTRO_TELEMETRY_INTERVAL=0; chk "a: pushed após b (rebase limpo)" "$(st a result)" "pushed"
[[ "$(remote_files)" == *hostaaaa* && "$(remote_files)" == *hostbbbb* ]] && ok "os dois hosts no remoto" || bad "faltou host: $(remote_files)"
n=$(git --git-dir="$REMOTE" log --oneline main | wc -l | tr -d ' ')
(( n >= 3 )) && ok "histórico linear com $n commits" || bad "commits: $n"

echo "-- push falho fica registrado; a rodada seguinte publica o que ficou"
printf 'telemetry_remote: %s\n' "$SANDBOX/quebrado.git" > "$(home_of b)/config.yaml"
echo '{"ts":"t","event":"gate_pass","session_id":"b1"}' >> "$(home_of b)/logs/routing.jsonl"
t0=$(date +%s); end b MAESTRO_TELEMETRY_INTERVAL=0; t1=$(date +%s)
chk "exit 0 com remoto quebrado" "$RC" "0"
chk "result=failed" "$(st b result)" "failed"
chk "reason=push" "$(st b reason)" "push"
(( t1 - t0 < 30 )) && ok "teto de tempo respeitado ($((t1 - t0))s)" || bad "demorou $((t1 - t0))s"
printf 'telemetry_remote: %s\n' "$REMOTE" > "$(home_of b)/config.yaml"
end b MAESTRO_TELEMETRY_INTERVAL=0; chk "b: publica na rodada seguinte" "$(st b result)" "pushed"
git --git-dir="$REMOTE" show main:logs/hostbbbb/routing-current.jsonl 2>/dev/null | grep -q gate_pass \
  && ok "o evento da rodada falha chegou" || bad "evento perdido"

echo "-- pull no host a traz o host b"
( export MAESTRO_HOME="$(home_of a)" MAESTRO_HOST_ID=hostaaaa
  source "$LIB"; maestro_telemetry_pull && echo pull-ok ) > "$SANDBOX/pull.out" 2>&1
grep -q pull-ok "$SANDBOX/pull.out" && ok "pull ok" || bad "pull falhou: $(cat "$SANDBOX/pull.out")"
[[ -f "$(home_of a)/telemetry/logs/hostbbbb/routing-current.jsonl" ]] && ok "log do b no clone do a" || bad "b ausente no clone do a"

echo "-- kill-switch e lixo no stdin: exit 0, nada publicado"
printf 'lixo' | MAESTRO_HOME="$(home_of a)" MAESTRO_HOST_ID=hostaaaa MAESTRO_TELEMETRY_INTERVAL=0 bash "$HOOK" >/dev/null 2>&1; chk "lixo: exit 0" "$?" "0"
printf '{"session_id":"s"}' | MAESTRO_OFF=1 MAESTRO_HOME="$(home_of a)" bash "$HOOK" >/dev/null 2>&1; chk "kill-switch: exit 0" "$?" "0"

echo
if [[ $fail -eq 0 ]]; then echo "test-telemetry-sync: OK"; else echo "test-telemetry-sync: FALHOU"; fi
exit $fail
