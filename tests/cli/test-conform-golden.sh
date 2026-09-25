#!/usr/bin/env bash
# ordem 042 — `maestro conform --check`: projeto CONFORME (exit 0, stdout
# vazio de lacunas) e a prova de não-escrita (Prova exigida da ordem).
#
# `bin/` está na denylist do gate (o despacho de `conform` só existe hoje em
# docs/patches/042-conform-bin-maestro-despachante.patch). A sandbox
# (tests/lib/conform-sandbox.sh, molde da ordem 027) aplica o patch numa
# CÓPIA de bin/maestro e symlinka lib/hooks/agents/src/config do repo real —
# o teste roda de verdade AGORA (patch na sandbox) e continua rodando depois
# que o Capitão aplicar o patch no repo (a sandbox detecta o mecanismo já
# presente e não reaplica).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/conform-sandbox.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v sqlite3 >/dev/null 2>&1 || { echo "PENDENTE  sqlite3 ausente — teste exige sqlite3 para o fixture do ponte.db"; exit 0; }
command -v jq      >/dev/null 2>&1 || { echo "PENDENTE  jq ausente — teste exige jq para validar o --json"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
conform_sandbox_build "$REPO" "$TMP" || { echo "FAIL sandbox: não montou (patch ausente/quebrado)"; exit 1; }
BIN="$CONFORM_BIN"

P="$TMP/golden"; mkdir -p "$P"
conform_fixture_golden "$P"

SLUG="$(basename "$P")"; SLUG="${SLUG,,}"; SLUG="${SLUG//_/-}"
DB="$TMP/ponte.db"
conform_fixture_ponte_db "$DB" "$SLUG" 1

HOME1="$TMP/home"; mkdir -p "$HOME1"
conform_write_brief "$BIN" "$HOME1" "$P"

export MAESTRO_HOME="$HOME1" MAESTRO_PONTE_DB="$DB"

# ---------------------------------------------------------------------------
# 1. AC: conforme → exit 0, stdout vazio de lacunas.
# ---------------------------------------------------------------------------
OUT=$("$BIN" conform --check "$P" 2>/dev/null); RC=$?
[[ $RC -eq 0 ]] && ok "exit 0 no projeto conforme" || bad "exit 0 no projeto conforme (rc=$RC)"
[[ -z "$OUT" ]] && ok "stdout vazio de lacunas" || bad "stdout vazio de lacunas — veio: $OUT"

# ---------------------------------------------------------------------------
# 2. --json: conforme:true, lacunas:[], schema válido por jq.
# ---------------------------------------------------------------------------
J=$("$BIN" conform --check --json "$P" 2>/dev/null); RCJ=$?
[[ $RCJ -eq 0 ]] && ok "exit 0 também no modo --json" || bad "exit 0 no --json (rc=$RCJ)"
if echo "$J" | jq -e . >/dev/null 2>&1; then
  ok "--json produz JSON válido"
  [[ "$(echo "$J" | jq -r '.conforme')" == "true" ]] && ok "conforme:true" || bad "conforme != true — $J"
  [[ "$(echo "$J" | jq '.lacunas | length')" == "0" ]] && ok "lacunas:[] vazio" || bad "lacunas não vazio — $J"
  [[ "$(echo "$J" | jq -r '.project')" == "$SLUG" ]] && ok "project é o slug/basename, nunca caminho absoluto" \
    || bad "project não é o basename esperado — $J"
else
  bad "--json não é JSON válido: $J"
fi

# ---------------------------------------------------------------------------
# 3. Prova de não-escrita: hash da árvore do fixture, do ponte.db fixture e
#    de MAESTRO_HOME (fora do log) idênticos antes/depois de duas rodadas.
# ---------------------------------------------------------------------------
tree_hash() { ( cd "$1" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum ) | sha256sum; }
TH1=$(tree_hash "$P"); DBH1=$(sha256sum "$DB" | awk '{print $1}')
HOME1LS=$(find "$HOME1" -type f | grep -v '/logs/' | sort)

"$BIN" conform --check "$P" >/dev/null 2>/dev/null
"$BIN" conform --check --json "$P" >/dev/null 2>/dev/null

TH2=$(tree_hash "$P"); DBH2=$(sha256sum "$DB" | awk '{print $1}')
HOME2LS=$(find "$HOME1" -type f | grep -v '/logs/' | sort)

[[ "$TH1" == "$TH2" ]] && ok "árvore do fixture não mudou" || bad "árvore do fixture MUDOU"
[[ "$DBH1" == "$DBH2" ]] && ok "ponte.db fixture não mudou" || bad "ponte.db fixture MUDOU"
[[ "$HOME1LS" == "$HOME2LS" ]] && ok "MAESTRO_HOME (fora do log) não mudou" || bad "MAESTRO_HOME MUDOU"

# ---------------------------------------------------------------------------
# 4. `chmod 0444` no ponte.db não quebra o comando (só precisa ler).
# ---------------------------------------------------------------------------
chmod 0444 "$DB"
OUT2=$("$BIN" conform --check "$P" 2>/dev/null); RC2=$?
chmod 0644 "$DB"
[[ $RC2 -eq 0 && -z "$OUT2" ]] && ok "ponte.db chmod 0444 não quebra (ainda conforme)" \
  || bad "ponte.db chmod 0444 quebrou — rc=$RC2 out=$OUT2"

if (( fail == 0 )); then echo "OK: test-conform-golden"; else echo "FALHOU: test-conform-golden" >&2; fi
exit $fail
