#!/usr/bin/env bash
# ordem 084 — trava (g) do --accept: fecha_epico exige drift-N aprova.
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
entry_project pd
mkdir -p "$P/docs"; echo "# design doc" > "$P/docs/ep.md"; G add -A; G commit -qm doc
entry_order "fecha" "$TURNO_OK
- fecha_epico: docs/ep.md
$CRIT_OK"
OF=$(ls "$P"/.maestro/orders/001-*.md); G add -A; G commit -qm "ordem 1"
declare_order "$P" 1 'true'
B=$(grep '^branch:' "$OF" | awk '{print $2}')
G checkout -qb "$B"; echo b >> "$P/f.txt"; G add -A; G commit -qm entrega
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
cold_findings "$tmp/ap" "sem achados"

out=$("$BIN" order --accept 1 --project "$P" --session s1 --intent-reviewed 2>&1); rc=$?
[[ $rc -ne 0 ]] && grep -q 'drift-1' <<<"$out" && ok "accept sem drift-1 reprova" || bad "sem drift (rc $rc): $out"

cold_record 1 aprova "$tmp/ap" --drift >/dev/null
out=$("$BIN" order --accept 1 --project "$P" --session s1 --intent-reviewed 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "accept com drift-1 aprova passa" || bad "com drift (rc $rc): $out"
exit $fail
