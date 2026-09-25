#!/usr/bin/env bash
# ordem 042 — família (b) .maestro.yaml de `maestro conform --check`: um
# fixture por código (`yaml-missing`/`yaml-no-verifications`/
# `yaml-label-no-command`/`yaml-lab-unmarked`/`yaml-lab-only-area`), cada um
# disparando EXATAMENTE aquele código e só ele, exit 1.
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

run_case() { # <nome> <dir> → grava OUT/RC/CODES (ponte/brief já resolvidos)
  local name="$1" dir="$2" slug home
  slug="$(basename "$dir")"; slug="${slug,,}"; slug="${slug//_/-}"
  conform_fixture_ponte_db "$DB" "$slug" 1
  home="$TMP/home-$name"; mkdir -p "$home"
  conform_write_brief "$BIN" "$home" "$dir"
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

# --- yaml-missing ------------------------------------------------------------
D="$TMP/f-yaml-missing"; conform_fixture_golden "$D"
rm -f "$D/.maestro.yaml"
run_case yaml-missing "$D"
assert_only "yaml-missing" "yaml-missing"

# --- yaml-no-verifications ---------------------------------------------------
D="$TMP/f-yaml-no-verifications"; conform_fixture_golden "$D"
cat > "$D/.maestro.yaml" <<'EOF'
docs: [docs/GUIA.md]
EOF
run_case yaml-no-verifications "$D"
assert_only "yaml-no-verifications" "yaml-no-verifications"

# --- yaml-label-no-command ----------------------------------------------------
D="$TMP/f-yaml-label-no-command"; conform_fixture_golden "$D"
cat > "$D/.maestro.yaml" <<'EOF'
docs: [docs/GUIA.md]
verifications:
  core:
    paths: [src/]
    labels: [suite]
EOF
run_case yaml-label-no-command "$D"
assert_only "yaml-label-no-command" "yaml-label-no-command"

# --- yaml-lab-unmarked: rótulo docker, sem entrar em lab: --------------------
D="$TMP/f-yaml-lab-unmarked"; conform_fixture_golden "$D"
cat > "$D/.maestro.yaml" <<'EOF'
docs: [docs/GUIA.md]
verifications:
  core:
    paths: [src/]
    labels: [suite, e2e]
commands:
  suite: "true"
  e2e: docker compose run e2e
EOF
run_case yaml-lab-unmarked "$D"
assert_only "yaml-lab-unmarked" "yaml-lab-unmarked"

# --- yaml-lab-only-area: único rótulo da área é lab --------------------------
D="$TMP/f-yaml-lab-only-area"; conform_fixture_golden "$D"
cat > "$D/.maestro.yaml" <<'EOF'
docs: [docs/GUIA.md]
verifications:
  core:
    paths: [src/]
    labels: [suite]
commands:
  suite: docker compose run suite
lab: [suite]
EOF
run_case yaml-lab-only-area "$D"
assert_only "yaml-lab-only-area" "yaml-lab-only-area"

if (( fail == 0 )); then echo "OK: test-conform-yaml"; else echo "FALHOU: test-conform-yaml" >&2; fi
exit $fail
