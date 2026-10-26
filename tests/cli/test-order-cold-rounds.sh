#!/usr/bin/env bash
# ordem 084 — limite de rodadas: terceiro --cold-record após dois devolve sai 1 com "escala ao Diretor".
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/entry-fixture.sh"
source "$REPO/tests/lib/declare-order.sh"
source "$REPO/tests/lib/cold-fixture.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
cold_setup

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

entry_project pr
entry_order "rodadas" "$TURNO_ALTO
$CRIT_OK"
cold_findings "$tmp/dv" "P2 achado"
cold_findings "$tmp/p1" "P1 achado grave"
cold_findings "$tmp/ap" "nada"

out=$(cold_record 1 aprova "$tmp/p1"); rc=$?
[[ $rc -eq 1 ]] && ok "aprova com P1 é recusado" || bad "P1 (rc $rc): $out"
out=$(cold_record 1 devolve "$tmp/dv"); rc=$?
[[ $rc -eq 0 ]] && ok "devolve 1 aceito" || bad "devolve 1 (rc $rc): $out"
out=$(cold_record 1 devolve "$tmp/dv"); rc=$?
[[ $rc -eq 0 ]] && ok "devolve 2 aceito" || bad "devolve 2 (rc $rc): $out"
out=$(cold_record 1 devolve "$tmp/dv"); rc=$?
[[ $rc -eq 1 ]] && grep -q 'escala ao Diretor' <<<"$out" && ok "terceira revisão: exit 1, escala ao Diretor" || bad "3ª (rc $rc): $out"
out=$(cold_record 1 aprova "$tmp/ap"); rc=$?
[[ $rc -eq 1 ]] && ok "também a aprova depois de dois devolve é recusada" || bad "aprova após 2 (rc $rc): $out"
exit $fail
