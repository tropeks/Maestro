#!/usr/bin/env bash
# ordem 042 — família (c) frescor de `maestro conform --check`: um fixture
# por código (`brief-missing`/`brief-stale`/`readme-stale`/`doc-stale`), cada
# um disparando EXATAMENTE aquele código e só ele, exit 1.
#
# `readme-stale`/`doc-stale` são forjados com a DATA DO COMMIT (git
# author/committer date), não com o relógio real — é essa data que
# `git log --format=%ct` lê, e é ela que a família compara contra o `ts:` do
# INTENT. `brief-stale` é forjado editando `epoch:`/`ts:` do brief já
# gravado (sem reimplementar a chave `maestro_brief_file`).
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

prep_ponte() { # <dir> — cadastra o slug com política completa
  local slug; slug="$(basename "$1")"; slug="${slug,,}"; slug="${slug//_/-}"
  conform_fixture_ponte_db "$DB" "$slug" 1
}

run_conform() { # <dir> <home> → grava OUT/RC/CODES
  OUT=$(env MAESTRO_HOME="$2" MAESTRO_PONTE_DB="$DB" "$BIN" conform --check "$1" 2>/dev/null)
  RC=$?
  CODES=$(printf '%s\n' "$OUT" | awk -F'\t' 'NF{print $1}' | sort -u)
  CASE_DIR="$1"; CASE_HOME="$2"
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

# --- brief-missing: nunca escrito --------------------------------------------
D="$TMP/f-brief-missing"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-bm"; mkdir -p "$H"
run_conform "$D" "$H"
assert_only "brief-missing" "brief-missing"

# --- brief-stale: brief existe, mas epoch/ts bem antes do ts: do INTENT -----
D="$TMP/f-brief-stale"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-bs"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
BF=$(find "$H/briefs" -type f -name '*.md' | head -1)
sed -i 's/^epoch: .*/epoch: 100000/' "$BF"
sed -i 's/^ts: .*/ts: 1970-01-02T00:00:00Z/' "$BF"
run_conform "$D" "$H"
assert_only "brief-stale" "brief-stale"

# --- readme-stale: README com a última mudança ANTES do ts: do INTENT ------
D="$TMP/f-readme-stale"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-rs"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
echo "# projeto de teste (rev)" > "$D/README.md"
GIT_AUTHOR_DATE="2019-06-01T00:00:00-03:00" GIT_COMMITTER_DATE="2019-06-01T00:00:00-03:00" \
  git -C "$D" commit -q -am "readme antigo (data forjada p/ teste)"
run_conform "$D" "$H"
assert_only "readme-stale" "readme-stale"

# --- doc-stale (doc existente, stale): docs/GUIA.md antigo -------------------
D="$TMP/f-doc-stale"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-ds"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
echo "# guia (rev)" > "$D/docs/GUIA.md"
GIT_AUTHOR_DATE="2019-06-01T00:00:00-03:00" GIT_COMMITTER_DATE="2019-06-01T00:00:00-03:00" \
  git -C "$D" commit -q -am "guia antigo (data forjada p/ teste)"
run_conform "$D" "$H"
assert_only "doc-stale" "doc-stale"

# --- doc-stale (variante: doc declarado que não existe no disco) ------------
D="$TMP/f-doc-missing-decl"; conform_fixture_golden "$D"; prep_ponte "$D"
H="$TMP/home-dm"; mkdir -p "$H"
conform_write_brief "$BIN" "$H" "$D"
sed -i 's#docs: \[docs/GUIA.md\]#docs: [docs/GUIA.md, docs/NAO-EXISTE.md]#' "$D/.maestro.yaml"
git -C "$D" commit -q -am "declara doc inexistente"
run_conform "$D" "$H"
[[ "$RC" -eq 1 ]] && ok "doc-missing-declarado: exit 1" || bad "doc-missing-declarado: exit 1 (rc=$RC)"
[[ "$CODES" == "doc-stale" ]] && ok "doc-missing-declarado: só doc-stale dispara (doc ausente é doc-stale)" \
  || bad "doc-missing-declarado: esperava só doc-stale, veio '$CODES'"
[[ "$OUT" == *"NAO-EXISTE.md"* ]] && ok "doc-missing-declarado: alvo nomeia o doc ausente" \
  || bad "doc-missing-declarado: alvo não nomeia o doc — $OUT"

if (( fail == 0 )); then echo "OK: test-conform-fresh"; else echo "FALHOU: test-conform-fresh" >&2; fi
exit $fail
