#!/usr/bin/env bash
# ordem 084 — o pacote do revisor traz ordem, INTENT, brief e roteiro, e nada além.
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

entry_project pb
entry_order "pacote" "$TURNO_OK
$CRIT_OK

## Adendo da rodada 1
SEGREDO-ADENDO

## Relatório do gerente
SEGREDO-RELATORIO"
out=$("$BIN" order --cold-bundle 1 --project "$P" 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && ok "bundle: exit 0" || bad "bundle rc $rc"
grep -q 'fatia: contrato e validador' <<<"$out" && ok "traz a ordem" || bad "sem a ordem"
grep -q '=== INTENT ===' <<<"$out" && grep -qF "$(sed -n 1p "$P/.maestro/INTENT.md")" <<<"$out" && ok "traz o INTENT" || bad "sem o INTENT"
grep -q '=== ROTEIRO ===' <<<"$out" && grep -qF "$(sed -n 1p "$REPO/docs/contracts/revisao-fria.md")" <<<"$out" && ok "traz o roteiro" || bad "sem o roteiro"
grep -q '=== BRIEF ===' <<<"$out" && ok "tem a seção do brief" || bad "sem a seção do brief"
grep -q 'SEGREDO-ADENDO' <<<"$out" && bad "adendo vazou" || ok "sem adendo"
grep -q 'SEGREDO-RELATORIO' <<<"$out" && bad "relatório vazou" || ok "sem relatório"
grep -q '^=== ' <<<"$out" && [[ $(grep -c '^=== ' <<<"$out") -eq 4 ]] && ok "só as quatro seções (ordem, INTENT, brief, roteiro)" || bad "seções inesperadas: $(grep '^=== ' <<<"$out")"
exit $fail
