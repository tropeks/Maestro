#!/usr/bin/env bash
# S-102: com MAESTRO_OFF=1, nenhum hook produz efeito e todos saem 0.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
tmp=$(mktemp -d); export MAESTRO_HOME="$tmp"
fail=0
for h in session-start pre-tool-gate user-prompt-submit; do
  out=$(MAESTRO_OFF=1 "$REPO/hooks/$h.sh" </dev/null 2>&1); rc=$?
  if [[ $rc -ne 0 || -n "$out" ]]; then echo "FAIL $h (rc=$rc out='$out')"; fail=1; else echo "ok   $h silencioso com kill-switch"; fi
done
[[ -e "$tmp/logs/routing.jsonl" ]] && { echo "FAIL log escrito com kill-switch"; fail=1; }
rm -rf "$tmp"; exit $fail
