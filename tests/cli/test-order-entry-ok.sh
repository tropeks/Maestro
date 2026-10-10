#!/usr/bin/env bash
# ordem 059 — contrato de entrada: a ordem COMPLETA passa no `--entry-check`.
# Completa = commitada no branch, ## Turno válido, critérios com oráculo ou
# [humano], dependência aceita, INTENT válido e .maestro.yaml. Cobre também o
# esqueleto do --create atrás de MAESTRO_ENTRY_REQUIRE.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/entry-fixture.sh"
source "$REPO/tests/lib/declare-order.sh"
entry_pendente

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# --- (1) completa, sem dependência ----------------------------------------
entry_project p1
entry_order "completa" "$TURNO_OK
$CRIT_OK"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
out=$(entry_chk 1); rc=$?
[[ $rc -eq 0 ]] && ok "(1) ordem completa: exit 0" || bad "(1) ordem completa reprovou (rc $rc): $out"
grep -q 'passa nas 5 checagens' <<<"$out" && ok "(1) diz que passou" || bad "(1) sem a linha de aprovação: $out"
[[ -z "$(G status --porcelain)" ]] && ok "(1) --entry-check não escreve nada na árvore" || bad "(1) sujou a árvore"
"$BIN" order --list --project "$P" 2>&1 | grep -q 'enfileir' && bad "(1) enfileirou algo" || ok "(1) nada enfileirado"

# --- (2) dependência ACEITA satisfaz (d) ----------------------------------
entry_project p2
entry_order "base" "$TURNO_OK
$CRIT_OK"
OF1=$(ls "$P"/.maestro/orders/001-*.md); G add -A; G commit -qm "ordem 1"
declare_order "$P" 1 'true'   # ordem 078: o record de order-1 só executa o declarado no fim:
B1=$(grep '^branch:' "$OF1" | awk '{print $2}')
G checkout -qb "$B1"; echo b >> "$P/f.txt"; G add -A; G commit -qm entrega
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
"$BIN" order --accept 1 --project "$P" --session s1 --intent-reviewed >/dev/null 2>&1
G checkout -q main
entry_order "dependente" "depende_de: 001
$TURNO_OK
$CRIT_OK"
OF2=$(ls "$P"/.maestro/orders/002-*.md); entry_commit_on_branch "$OF2"
out=$(entry_chk 2); rc=$?
[[ $rc -eq 0 ]] && ok "(2) dependência aceita: exit 0" || bad "(2) dependência aceita reprovou (rc $rc): $out"

# --- (3) esqueleto do --create atrás de MAESTRO_ENTRY_REQUIRE -------------
entry_project p3
printf '' | "$BIN" order --create --title "sem flag" --project "$P" --session s0 >/dev/null
grep -q 'Critérios de aceite' "$P"/.maestro/orders/001-*.md && bad "(3) flag desligada gerou a seção" || ok "(3) flag desligada: --create como hoje (sem a seção)"
printf '' | MAESTRO_ENTRY_REQUIRE=1 "$BIN" order --create --title "com flag" --project "$P" --session s0 >/dev/null
F=$(ls "$P"/.maestro/orders/002-*.md)
grep -q '^## Critérios de aceite' "$F" && grep -q 'oráculo:' "$F" && grep -q '\[humano\]' "$F" \
  && ok "(3) flag ligada: esqueleto traz a seção, o oráculo e o [humano]" || bad "(3) esqueleto incompleto"
printf 'entry_require: on\n' >> "$P/.maestro.yaml"
printf '' | "$BIN" order --create --title "via yaml" --project "$P" --session s0 >/dev/null
grep -q '^## Critérios de aceite' "$P"/.maestro/orders/003-*.md && ok "(3) entry_require: no yaml liga o esqueleto" || bad "(3) yaml não ligou"
printf '' | MAESTRO_ENTRY_REQUIRE=0 "$BIN" order --create --title "env vence" --project "$P" --session s0 >/dev/null
grep -q 'Critérios de aceite' "$P"/.maestro/orders/004-*.md && bad "(3) env=0 não venceu o yaml" || ok "(3) env vence o yaml"

exit $fail
