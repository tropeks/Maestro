#!/usr/bin/env bash
# ordem 042 — `maestro conform`: uso (exit 2), e paridade texto/--json quando
# há VÁRIAS lacunas de famílias diferentes ao mesmo tempo (mesmos códigos, na
# MESMA ordem — por família e depois por alvo, LC_ALL=C).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/conform-sandbox.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v sqlite3 >/dev/null 2>&1 || { echo "PENDENTE  sqlite3 ausente"; exit 0; }
command -v jq      >/dev/null 2>&1 || { echo "PENDENTE  jq ausente"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
conform_sandbox_build "$REPO" "$TMP" || { echo "FAIL sandbox: não montou"; exit 1; }
BIN="$CONFORM_BIN"

export MAESTRO_HOME="$TMP/home"; mkdir -p "$MAESTRO_HOME"

# ---------------------------------------------------------------------------
# 1. Uso: exit 2 — flag desconhecida, --check ausente, <dir> inexistente.
# ---------------------------------------------------------------------------
"$BIN" conform >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "sem --check: exit 2" || bad "sem --check: esperava exit 2"

"$BIN" conform --check --bogus >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "flag desconhecida: exit 2" || bad "flag desconhecida: esperava exit 2"

"$BIN" conform --check "$TMP/nao-existe-mesmo" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "<dir> inexistente: exit 2" || bad "<dir> inexistente: esperava exit 2"

"$BIN" conform --check "$TMP/a" "$TMP/b" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "argumento extra: exit 2" || bad "argumento extra: esperava exit 2"

# ---------------------------------------------------------------------------
# 2. Paridade texto/--json com várias lacunas de famílias diferentes.
# ---------------------------------------------------------------------------
D="$TMP/multi"; conform_fixture_golden "$D"
rm -f "$D/CLAUDE.md"
sed -i '/^problema de teste$/d' "$D/.maestro/INTENT.md"
F="$D/.maestro/INTENT.md"
NEWHASH=$(sed '1,/^-->$/d' "$F" | sha256sum | head -c 8)
sed -i "s/^hash: .*/hash: $NEWHASH/" "$F"
DB="$TMP/ponte.db"
sqlite3 "$DB" "CREATE TABLE manager_definition (project_slug TEXT PRIMARY KEY, manager_model_policy TEXT, tool_allowlist TEXT, risk_policy TEXT);"
export MAESTRO_PONTE_DB="$DB"
# sem brief e sem cadastro no ponte: brief-missing + intent-sections +
# claude-md-missing + ponte-unregistered — quatro famílias diferentes.

TXT=$("$BIN" conform --check "$D" 2>/dev/null)
JSN=$("$BIN" conform --check --json "$D" 2>/dev/null)

if echo "$JSN" | jq -e . >/dev/null 2>&1; then
  ok "--json válido com múltiplas lacunas"
else
  bad "--json inválido: $JSN"
fi

CODES_TXT=$(printf '%s\n' "$TXT" | awk -F'\t' 'NF{print $1}')
CODES_JSN=$(echo "$JSN" | jq -r '.lacunas[].codigo')
[[ "$CODES_TXT" == "$CODES_JSN" ]] && ok "texto e --json listam as MESMAS lacunas, na MESMA ordem" \
  || bad "ordem/códigos divergem — texto:[$CODES_TXT] json:[$CODES_JSN]"

N=$(printf '%s\n' "$CODES_TXT" | grep -c .)
[[ "$N" -ge 3 ]] && ok "cenário multi-família tem >= 3 lacunas (teste vale a pena)" \
  || bad "cenário multi-família com poucas lacunas ($N) — reforce o fixture"

ALVOS_TXT=$(printf '%s\n' "$TXT" | awk -F'\t' '{print $2}')
ALVOS_JSN=$(echo "$JSN" | jq -r '.lacunas[].alvo')
[[ "$ALVOS_TXT" == "$ALVOS_JSN" ]] && ok "alvos batem entre texto e --json" \
  || bad "alvos divergem — texto:[$ALVOS_TXT] json:[$ALVOS_JSN]"

if (( fail == 0 )); then echo "OK: test-conform-usage"; else echo "FALHOU: test-conform-usage" >&2; fi
exit $fail
