#!/usr/bin/env bash
# Fase 0 da auditoria (05/10): o kill-switch é a LINHA 2 de todo hooks/*.sh — antes de
# qualquer `source`, `cd` ou leitura de stdin — e o `source` de lib/common.sh nunca derruba
# o hook (`if ! source …; then exit 0; fi`). Falha de componente degrada para o fluxo manual.
# Cinco blocos abaixo, na ordem: a linha 2 de cada hook é o kill-switch; nenhum hook faz
# `source …/lib/common.sh` solto (sem o guarda); com MAESTRO_OFF=1 cada hook sai 0 sem imprimir
# nada, MESMO sem lib/ ao lado; com lib/ ausente (insourceável) cada hook ainda sai 0; e
# hooks/lib/transcript.sh abre com a diretiva do shellcheck (a CI não cai por SC2148).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

hooks=("$REPO"/hooks/*.sh)
[[ ${#hooks[@]} -ge 11 ]] && ok "achou ${#hooks[@]} hooks em hooks/*.sh" || bad "esperava pelo menos 11 hooks, achou ${#hooks[@]}"

echo "-- 1: linha 2 é o kill-switch"
re_l2='^\[\[ "\$\{MAESTRO_OFF:-0\}" == "?1"? \]\] && exit 0$'
for h in "${hooks[@]}"; do
  b=$(basename "$h")
  l2=$(sed -n 2p "$h")
  [[ "$l2" =~ $re_l2 ]] && ok "$b: linha 2 é o kill-switch" || bad "$b: linha 2 não é o kill-switch ($l2)"
done

echo "-- 2: nenhum source solto de lib/common.sh"
for h in "${hooks[@]}"; do
  b=$(basename "$h")
  if grep -qE '^source +"[^"]*lib/common\.sh"' "$h"; then
    bad "$b: source de lib/common.sh sem o guarda 'if ! source …; then exit 0; fi'"
  else
    ok "$b: sem source solto de common.sh"
  fi
done

echo "-- 3: MAESTRO_OFF=1 sai 0, mudo, mesmo sem lib/ ao lado"
for h in "${hooks[@]}"; do
  b=$(basename "$h")
  d="$tmp/off-$b"; mkdir -p "$d"; cp "$h" "$d/$b"
  out=$(MAESTRO_OFF=1 bash "$d/$b" </dev/null 2>&1); rc=$?
  [[ $rc -eq 0 && -z "$out" ]] && ok "$b: MAESTRO_OFF=1 → rc 0, silêncio" || bad "$b: MAESTRO_OFF=1 → rc=$rc out='$out'"
done

echo "-- 4: lib/ ausente (insourceável) degrada para exit 0"
for h in "${hooks[@]}"; do
  b=$(basename "$h")
  d="$tmp/nolib-$b"; mkdir -p "$d"; cp "$h" "$d/$b"
  MAESTRO_HOME="$d/home" CLAUDE_PROJECT_DIR="$d" bash "$d/$b" </dev/null >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 ]] && ok "$b: sem lib/ → rc 0" || bad "$b: sem lib/ → rc=$rc (devia degradar para 0)"
done

echo "-- 5: transcript.sh abre com a diretiva do shellcheck"
[[ "$(sed -n 1p "$REPO/hooks/lib/transcript.sh")" == "# shellcheck shell=bash" ]] \
  && ok "transcript.sh:1 = # shellcheck shell=bash" || bad "transcript.sh:1 não é a diretiva do shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$REPO/hooks/lib/transcript.sh" >/dev/null 2>&1 \
    && ok "shellcheck hooks/lib/transcript.sh limpo" || bad "shellcheck hooks/lib/transcript.sh reprova"
else
  ok "(sem shellcheck: checagem pulada)"
fi

exit $fail
