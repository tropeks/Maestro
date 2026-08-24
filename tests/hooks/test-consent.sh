#!/usr/bin/env bash
# E10 / S-1005 — consentimento escopado (ADR-003 v1.2).
# A invariante que este teste defende: consentimento destrava DADOS
# (routing-table, roster), NUNCA a máquina (hooks/, bin/, src/, .claude-plugin/)
# — nem com arquivo de consentimento forjado. Fail closed em tudo.
# Hermético: MAESTRO_HOME em mktemp; política compilada pelo session-start real.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO/hooks/pre-tool-gate.sh"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

H="$tmp/home"
printf '{"session_id":"cons-1"}' | MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$REPO" \
  bash "$REPO/hooks/session-start.sh" >/dev/null 2>&1
[[ -f "$H/gate-policy.sh" ]] && ok "política compilada (pré-condição)" || bad "política compilada"

probe() { # probe <caminho-relativo-ao-repo> → rc do gate
  printf '{"session_id":"cons-1","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$REPO/$1" \
    | MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$REPO" bash "$GATE" >/dev/null 2>&1
  echo "$?"
}

# ---------------------------------------------------------------------------
echo "-- linha de base: denylist intacta sem consentimento"
# ---------------------------------------------------------------------------
chk "routing-table bloqueada" "$(probe config/routing-table.yaml)" "2"
chk "roster bloqueado" "$(probe agents/dev-junior.md)" "2"
chk "hooks/ bloqueado" "$(probe hooks/pre-tool-gate.sh)" "2"
chk "bin/ bloqueado" "$(probe bin/maestro)" "2"

# ---------------------------------------------------------------------------
echo "-- grant: destrava SÓ o escopo, e só enquanto vale"
# ---------------------------------------------------------------------------
MAESTRO_HOME="$H" "$BIN" consent --grant routing-table --ttl 5m --session cons-1 >/dev/null
chk "routing-table com consent → passa a denylist" "$(probe config/routing-table.yaml)" "0"
chk "roster continua bloqueado (escopo não vaza)" "$(probe agents/dev-junior.md)" "2"
chk "hooks/ continua bloqueado" "$(probe hooks/pre-tool-gate.sh)" "2"
MAESTRO_HOME="$H" "$BIN" consent --grant roster --ttl 5m --session cons-1 >/dev/null
chk "roster com o próprio consent → passa" "$(probe agents/dev-junior.md)" "0"

out=$(MAESTRO_HOME="$H" "$BIN" consent)
grep -q 'ativo: routing-table' <<<"$out" && ok "listagem mostra escopos ativos" || bad "listagem mostra ativos"

# ---------------------------------------------------------------------------
echo "-- revogação e expiração: fail closed"
# ---------------------------------------------------------------------------
MAESTRO_HOME="$H" "$BIN" consent --revoke routing-table >/dev/null
chk "revogado → volta a bloquear" "$(probe config/routing-table.yaml)" "2"
printf 'expires=1\ngranted=x\nsession=cons-1\n' > "$H/consents/roster"
chk "expirado → bloqueia" "$(probe agents/dev-junior.md)" "2"
printf 'lixo sem formato\n' > "$H/consents/roster"
chk "consent malformado → bloqueia (fail closed)" "$(probe agents/dev-junior.md)" "2"

# ---------------------------------------------------------------------------
echo "-- a máquina NUNCA é consentível"
# ---------------------------------------------------------------------------
for scope in hooks bin src gate cli .claude-plugin; do
  MAESTRO_HOME="$H" "$BIN" consent --grant "$scope" >/dev/null 2>&1; rc=$?
  chk "CLI recusa --grant $scope (exit 1)" "$rc" "1"
done
mkdir -p "$H/consents"
for forged in hooks bin src; do
  printf 'expires=9999999999\n' > "$H/consents/$forged"
done
chk "hooks/ com consent FORJADO segue bloqueado" "$(probe hooks/pre-tool-gate.sh)" "2"
chk "bin/ com consent FORJADO segue bloqueado" "$(probe bin/maestro)" "2"
chk "src/ com consent FORJADO segue bloqueado" "$(probe src/cli.ts)" "2"

# ---------------------------------------------------------------------------
echo "-- validação do CLI e auditoria do log"
# ---------------------------------------------------------------------------
MAESTRO_HOME="$H" "$BIN" consent --grant routing-table --ttl 5h >/dev/null 2>&1; rc=$?
chk "TTL acima de 4h é recusado" "$rc" "1"
MAESTRO_HOME="$H" "$BIN" consent --grant escopo-inventado >/dev/null 2>&1; rc=$?
chk "escopo desconhecido é recusado" "$rc" "1"

LOG="$H/logs/routing.jsonl"
grep -q '"event":"consent_grant".*"scope":"routing-table"' "$LOG" \
  && ok "grant auditado com escopo" || bad "grant auditado com escopo"
grep -q '"event":"consent_revoke"' "$LOG" && ok "revoke auditado" || bad "revoke auditado"
grep -q 'config/routing-table' "$LOG" && bad "caminho nunca no log" || ok "caminho nunca no log"
grep -qE '"event":"gate_(pass|warn)".*"scope":"routing-table"' "$LOG" \
  && ok "edição consentida carrega o escopo no evento do gate" \
  || bad "edição consentida carrega o escopo no evento do gate"

# ---------------------------------------------------------------------------
echo "-- consent não é bypass do resto do gate"
# ---------------------------------------------------------------------------
# Com consent válido mas sem decision record, o fluxo normal (warn) responde —
# o evento é gate_warn, não um exit 0 mudo por fora do fluxo.
grep -qE '"event":"gate_warn"' "$LOG" \
  && ok "sem record, edição consentida cai no warn normal" \
  || bad "sem record, edição consentida cai no warn normal"

exit $fail
