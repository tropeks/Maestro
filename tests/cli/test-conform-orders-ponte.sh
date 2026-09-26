#!/usr/bin/env bash
# ordem 042 — famílias (d) ordens, (e) daemon (ponte) e (f) CLAUDE.md de
# `maestro conform --check`: um fixture por código, cada um disparando
# EXATAMENTE aquele código e só ele, exit 1. Cobre também a degradação sem
# `sqlite3` no PATH (`ponte-unreadable`, exit 1, sem crash — Prova exigida).
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

prep_ponte() { local slug; slug="$(basename "$1")"; slug="${slug,,}"; slug="${slug//_/-}"; conform_fixture_ponte_db "$DB" "$slug" 1; }

run_conform() { # <dir> <home> [db] → grava OUT/RC/CODES
  OUT=$(env MAESTRO_HOME="$2" MAESTRO_PONTE_DB="${3:-$DB}" "$BIN" conform --check "$1" 2>/dev/null)
  RC=$?
  CODES=$(printf '%s\n' "$OUT" | awk -F'\t' 'NF{print $1}' | sort -u)
  CASE_DIR="$1"; CASE_HOME="$2"; CASE_DB="${3:-$DB}"
}

assert_only() { # <nome> <código-esperado>
  local name="$1" want="$2" pj
  [[ "$RC" -eq 1 ]] && ok "$name: exit 1" || bad "$name: exit 1 (rc=$RC)"
  [[ "$CODES" == "$want" ]] && ok "$name: só $want dispara" || bad "$name: esperava só '$want', veio '$CODES'"
  conform_check_json_parity "$BIN" "$CASE_DIR" "$CASE_HOME" "$CASE_DB" "$OUT"; pj=$?
  case $pj in
    0) ok "$name: --json válido e bate com o texto" ;;
    2) echo "PENDENTE  $name: jq ausente — pulando validação de --json" ;;
    *) bad "$name: --json inválido ou diverge do texto" ;;
  esac
}

# --- order-no-headless: ordem não-terminal sem a linha de execução headless -
D="$TMP/f-order-no-headless"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-onh"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
mkdir -p "$D/.maestro/orders"
cat > "$D/.maestro/orders/001-teste.md" <<'EOF'
<!-- maestro-order v1
id: 001
ts: 2020-01-01T00:00:00-03:00
epoch: 1577836800
head: none
branch: feat/001-teste
intent_version: 1
intent_hash: none
author_session: fixture
-->
# Ordem 001 — teste

Sem seção de execução headless nenhuma.
EOF
git -C "$D" add -A && git -C "$D" commit -q -m "ordem sem headless"
run_conform "$D" "$H"
assert_only "order-no-headless" "order-no-headless"

# --- ordem com a linha headless (título, negrito OU blockquote) NÃO dispara -
D="$TMP/f-order-with-headless"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-owh"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
mkdir -p "$D/.maestro/orders"
cat > "$D/.maestro/orders/001-teste.md" <<'EOF'
<!-- maestro-order v1
id: 001
ts: 2020-01-01T00:00:00-03:00
epoch: 1577836800
head: none
branch: feat/001-teste
intent_version: 1
intent_hash: none
author_session: fixture
-->
# Ordem 001 — teste

> **Execução headless, prova pelo CI.** Roda sem humano, prova no CI.
EOF
git -C "$D" add -A && git -C "$D" commit -q -m "ordem com headless"
run_conform "$D" "$H"
[[ "$CODES" != *"order-no-headless"* ]] && ok "ordem com blockquote+negrito não dispara order-no-headless" \
  || bad "ordem com a linha headless disparou mesmo assim — $CODES"

# --- claude-md-missing -------------------------------------------------------
D="$TMP/f-claude-md-missing"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-cmm"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
rm -f "$D/CLAUDE.md"
run_conform "$D" "$H"
assert_only "claude-md-missing" "claude-md-missing"

# --- ponte-unregistered: slug não cadastrado ---------------------------------
D="$TMP/f-ponte-unregistered"; conform_fixture_golden "$D"
H="$TMP/home-pu"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
DB_EMPTY="$TMP/ponte-empty.db"
sqlite3 "$DB_EMPTY" "CREATE TABLE manager_definition (project_slug TEXT PRIMARY KEY, manager_model_policy TEXT, tool_allowlist TEXT, risk_policy TEXT);"
run_conform "$D" "$H" "$DB_EMPTY"
assert_only "ponte-unregistered" "ponte-unregistered"

# --- ponte-no-policy: cadastrado, mas risk_policy NULL ----------------------
D="$TMP/f-ponte-no-policy"; conform_fixture_golden "$D"
H="$TMP/home-pnp"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
DB_NOPOL="$TMP/ponte-nopolicy.db"
SLUG="$(basename "$D")"; SLUG="${SLUG,,}"; SLUG="${SLUG//_/-}"
conform_fixture_ponte_db "$DB_NOPOL" "$SLUG" 0
run_conform "$D" "$H" "$DB_NOPOL"
assert_only "ponte-no-policy" "ponte-no-policy"

# --- worktree: o slug é o do repo principal, não o do diretório do worktree -
# (E15, molde de maestro_brief_file). Sem isto, conform num worktree acusa
# ponte-unregistered do nome do worktree mesmo com o projeto cadastrado.
D="$TMP/f-wt-main"; conform_fixture_golden "$D"; prep_ponte "$D"
W="$TMP/f-wt-outro-nome"
git -C "$D" worktree add -q "$W" -b wt-teste >/dev/null 2>&1
H="$TMP/home-wt"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$W"
run_conform "$W" "$H"
[[ "$CODES" != *"ponte-unregistered"* ]] && ok "worktree: slug do repo principal (sem ponte-unregistered falso)" \
  || bad "worktree: ponte-unregistered falso pelo nome do worktree — $OUT"

# --- ponte-unreadable: banco ausente -----------------------------------------
D="$TMP/f-ponte-unreadable"; conform_fixture_golden "$D"
H="$TMP/home-pun"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
run_conform "$D" "$H" "$TMP/nao-existe.db"
assert_only "ponte-unreadable" "ponte-unreadable"

# --- degradação: sem sqlite3 no PATH → ponte-unreadable, exit 1, sem crash --
NOPATH="$TMP/nopathbin"; mkdir -p "$NOPATH"
for c in bash awk grep sed git find sort head tail tr cut date printf mktemp \
         basename dirname readlink cat wc mv cp mkdir env sha256sum rm chmod; do
  p=$(type -P "$c" 2>/dev/null); [[ -n "$p" ]] && ln -sf "$p" "$NOPATH/$c"
done
D="$TMP/f-nopath"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-nopath"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
OUT=$(env -i PATH="$NOPATH" HOME="$HOME" MAESTRO_HOME="$H" MAESTRO_PONTE_DB="$DB" "$BIN" conform --check "$D" 2>&1)
RC=$?
[[ "$RC" -eq 1 ]] && ok "sem sqlite3 no PATH: exit 1 (nunca crash)" || bad "sem sqlite3 no PATH: exit 1 (rc=$RC) — $OUT"
[[ "$OUT" == *"ponte-unreadable"* ]] && ok "sem sqlite3 no PATH: ponte-unreadable presente" \
  || bad "sem sqlite3 no PATH: ponte-unreadable ausente — $OUT"
[[ "$OUT" != *"command not found"*"sqlite3"* ]] && ok "sem sqlite3 no PATH: sem erro cru vazando" \
  || bad "sem sqlite3 no PATH: vazou erro cru — $OUT"

if (( fail == 0 )); then echo "OK: test-conform-orders-ponte"; else echo "FALHOU: test-conform-orders-ponte" >&2; fi
exit $fail
