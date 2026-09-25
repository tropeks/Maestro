#!/usr/bin/env bash
# ordem 042 — família (a) INTENT de `maestro conform --check`: um fixture por
# código (`intent-missing`/`intent-sections`/`intent-hash`), cada um disparando
# EXATAMENTE aquele código e só ele, exit 1. Ver tests/cli/test-conform-golden.sh
# para o molde da sandbox (patch em cópia de bin/maestro, PENDENTE se faltar
# sqlite3/jq).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/conform-sandbox.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v sqlite3 >/dev/null 2>&1 || { echo "PENDENTE  sqlite3 ausente"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
conform_sandbox_build "$REPO" "$TMP" || { echo "FAIL sandbox: não montou"; exit 1; }
BIN="$CONFORM_BIN"
DB="$TMP/ponte.db"

# roda o conform num fixture isolado, com ponte/brief já resolvidos (para que
# SÓ a família intent apareça) — grava CODES com os códigos únicos encontrados.
run_case() { # <nome> <dir> → grava OUT/RC/CODES
  local name="$1" dir="$2" slug home
  slug="$(basename "$dir")"; slug="${slug,,}"; slug="${slug//_/-}"
  conform_fixture_ponte_db "$DB" "$slug" 1
  home="$TMP/home-$name"; mkdir -p "$home"
  conform_write_brief "$BIN" "$home" "$dir"
  # `env` explícito: `VAR=v OUT=$(...)` sem um "comando" de verdade depois do
  # último `=` vira atribuição NO SHELL ATUAL (não exportada) — o subshell do
  # `$(...)` cairia de volta no HOME real. `env` força ambiente temporário de
  # verdade para o processo filho.
  OUT=$(env MAESTRO_HOME="$home" MAESTRO_PONTE_DB="$DB" "$BIN" conform --check "$dir" 2>/dev/null)
  RC=$?
  CODES=$(printf '%s\n' "$OUT" | awk -F'\t' 'NF{print $1}' | sort -u)
  CASE_DIR="$dir"; CASE_HOME="$home"
}

assert_only() { # <nome> <código-esperado>
  local name="$1" want="$2" pj
  [[ "$RC" -eq 1 ]] && ok "$name: exit 1" || bad "$name: exit 1 (rc=$RC)"
  [[ "$CODES" == "$want" ]] && ok "$name: só $want dispara" || bad "$name: esperava só '$want', veio '$CODES'"
  conform_check_json_parity "$BIN" "$CASE_DIR" "$CASE_HOME" "$DB" "$OUT"; pj=$?
  case $pj in
    0) ok "$name: --json válido e bate com o texto" ;;
    2) echo "PENDENTE  $name: jq ausente — pulando validação de --json" ;;
    *) bad "$name: --json inválido ou diverge do texto" ;;
  esac
}

# --- intent-missing: sem .maestro/INTENT.md ---------------------------------
D="$TMP/f-intent-missing"; conform_fixture_golden "$D"
rm -f "$D/.maestro/INTENT.md"
run_case intent-missing "$D"
assert_only "intent-missing" "intent-missing"

# --- intent-sections: seção vazia, hash recalculado p/ o corpo já truncado --
D="$TMP/f-intent-sections"; conform_fixture_golden "$D"
F="$D/.maestro/INTENT.md"
sed -i '/^problema de teste$/d' "$F"
NEWHASH=$(sed '1,/^-->$/d' "$F" | sha256sum | head -c 8)
sed -i "s/^hash: .*/hash: $NEWHASH/" "$F"
run_case intent-sections "$D"
assert_only "intent-sections" "intent-sections"

# --- intent-hash: corpo editado SEM recalcular o hash carimbado -------------
D="$TMP/f-intent-hash"; conform_fixture_golden "$D"
sed -i 's/problema de teste/problema de teste MUDOU/' "$D/.maestro/INTENT.md"
run_case intent-hash "$D"
assert_only "intent-hash" "intent-hash"

if (( fail == 0 )); then echo "OK: test-conform-intent"; else echo "FALHOU: test-conform-intent" >&2; fi
exit $fail
