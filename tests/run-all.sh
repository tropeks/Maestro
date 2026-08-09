#!/usr/bin/env bash
# Runner da suíte. Isola o estado em tmpdir: a suíte NUNCA escreve no ~/.maestro real
# (review P2-8) — cada teste ainda isola o seu próprio, isto é a rede de segurança.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUITE_HOME=$(mktemp -d)
export MAESTRO_HOME="$SUITE_HOME"
trap 'rm -rf "$SUITE_HOME"' EXIT

fail=0
run() { echo "== $1"; bash "$1" || fail=1; }

for t in "$ROOT"/tests/hooks/test-*.sh; do [[ -e "$t" ]] && run "$t"; done
for t in "$ROOT"/tests/cli/test-*.sh;   do [[ -e "$t" ]] && run "$t"; done

echo "== doctor"
"$ROOT/bin/maestro" doctor || fail=1

if [[ $fail -eq 0 ]]; then echo "SUITE OK"; else echo "SUITE COM FALHAS" >&2; fi
exit $fail
