#!/usr/bin/env bash
# ordem 059 — compatibilidade: ordem antiga SEM `## Critérios de aceite` não
# quebra --list/--status; só o --entry-check a reprova, com motivo. Com a flag
# MAESTRO_ENTRY_REQUIRE desligada, --create sai como hoje.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/entry-fixture.sh"
entry_pendente

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

entry_project pa
entry_order "ordem antiga" "Objetivo livre, sem critérios nem Turno."
G add -A; G commit -qm "ordem antiga"
OF=$(ls "$P"/.maestro/orders/001-*.md)

out=$("$BIN" order --list --project "$P" 2>&1); rc=$?
[[ $rc -eq 0 ]] && grep -q 'ordem antiga' <<<"$out" && ok "--list segue funcionando (rc 0)" || bad "--list quebrou (rc $rc): $out"
out=$("$BIN" order --status 1 --project "$P" 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "--status segue funcionando (rc 0)" || bad "--status quebrou (rc $rc): $out"
out=$("$BIN" order --status 1 --json --project "$P" 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "--status --json segue funcionando (rc 0)" || bad "--status --json quebrou (rc $rc): $out"

out=$("$BIN" order --entry-check 1 --project "$P" 2>&1); rc=$?
[[ $rc -eq 1 ]] && grep -q '(c).*Critérios de aceite' <<<"$out" && ok "--entry-check reprova a antiga com motivo (c)" || bad "--entry-check na antiga (rc $rc): $out"
grep -q '(b)' <<<"$out" && ok "--entry-check também aponta o Turno ausente (b)" || bad "sem motivo (b): $out"

# o validador só lê: a ordem antiga não mudou
G diff --quiet && [[ -z "$(G status --porcelain)" ]] && ok "ordem antiga intacta depois do --entry-check" || bad "--entry-check alterou a árvore"

# flag desligada: --create idêntico ao de hoje (sem a seção)
printf '' | "$BIN" order --create --title "nova" --project "$P" --session s0 >/dev/null
grep -q 'Critérios de aceite' "$P"/.maestro/orders/002-*.md && bad "flag desligada mudou o --create" || ok "flag desligada: --create sem a seção (como hoje)"

# ordem inexistente → erro de validação, não crash
out=$("$BIN" order --entry-check 42 --project "$P" 2>&1); rc=$?
[[ $rc -eq 1 ]] && ok "--entry-check de ordem inexistente: rc 1" || bad "ordem inexistente (rc $rc): $out"

exit $fail
