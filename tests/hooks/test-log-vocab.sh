#!/usr/bin/env bash
# DATA_MODEL §4: vocabulário fechado; evento inválido é descartado; valores sanitizados.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
tmp=$(mktemp -d); export MAESTRO_HOME="$tmp"
source "$REPO/hooks/lib/common.sh"
log_event decision workflow=fix mode=direct
log_event evento_invalido foo=bar 2>/dev/null
log_event gate_warn file_ext='.go"; rm -rf /' 2>/dev/null
n=$(wc -l < "$MAESTRO_HOME/logs/routing.jsonl")
fail=0
[[ "$n" == "2" ]] || { echo "FAIL esperava 2 linhas, veio $n"; fail=1; }
if command -v jq >/dev/null; then
  jq -e . "$MAESTRO_HOME/logs/routing.jsonl" >/dev/null 2>&1 || { echo "FAIL JSONL malformado"; fail=1; }
fi
grep -q 'rm -rf' "$MAESTRO_HOME/logs/routing.jsonl" && { echo "FAIL sanitização falhou"; fail=1; }
[[ $fail -eq 0 ]] && echo "ok   vocabulário fechado + sanitização + JSONL válido"
rm -rf "$tmp"; exit $fail
