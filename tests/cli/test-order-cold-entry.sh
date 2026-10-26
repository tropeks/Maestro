#!/usr/bin/env bash
# ordem 084 — trava (f) do --entry-check: risco alto exige plan-review aprova com o sha atual.
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

export MAESTRO_COLD_REVIEW_REQUIRE=1
entry_project pe
entry_order "alto" "$TURNO_ALTO
$CRIT_OK"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
cold_findings "$tmp/ap" "sem achados"
cold_findings "$tmp/dv" "P2 achado qualquer"

out=$(entry_chk 1); rc=$?
[[ $rc -eq 1 ]] && grep -q 'plan-review-1' <<<"$out" && ok "risco alto sem recibo reprova" || bad "sem recibo (rc $rc): $out"

cold_record 1 devolve "$tmp/dv" >/dev/null
out=$(entry_chk 1); rc=$?
[[ $rc -eq 1 ]] && grep -q 'devolve' <<<"$out" && ok "devolve reprova" || bad "devolve (rc $rc): $out"

cold_record 1 aprova "$tmp/ap" >/dev/null
echo "- mudança no plano" >> "$OF"; G add -A; G commit -qm muda
out=$(entry_chk 1); rc=$?
[[ $rc -eq 1 ]] && grep -q 'sha256' <<<"$out" && ok "aprova com sha diferente reprova" || bad "sha (rc $rc): $out"

cold_record 1 aprova "$tmp/ap" >/dev/null
out=$(entry_chk 1); rc=$?
[[ $rc -eq 0 ]] && ok "aprova com sha igual passa" || bad "aprova+sha (rc $rc): $out"

entry_project pl
entry_order "baixo" "$TURNO_BAIXO
$CRIT_OK"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
out=$(entry_chk 1); rc=$?
[[ $rc -eq 0 ]] && ok "risco baixo passa sem recibo" || bad "baixo (rc $rc): $out"
exit $fail
