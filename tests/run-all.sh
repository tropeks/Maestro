#!/usr/bin/env bash
set -u
fail=0
for t in "$(dirname "$0")"/hooks/test-*.sh; do
  echo "== $t"; bash "$t" || fail=1
done
"$(dirname "$0")/../bin/maestro" doctor || fail=1
exit $fail
