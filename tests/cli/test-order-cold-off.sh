#!/usr/bin/env bash
# ordem 084 — flag desligada: --entry-check, --accept e --create saem iguais aos de hoje
# (comparação byte a byte: bin/maestro do repo, sem o patch, contra a cópia com o patch).
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
NEW="$BIN"
REAL="$REPO/bin/maestro"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

norm() { sed "s#$tmp/[A-Za-z0-9_./-]*#T#g"; }

# --entry-check: ordem de risco alto + fecha_epico, sem recibo, flag ausente e flag =0
entry_project off1
entry_order "x" "$TURNO_ALTO
- fecha_epico: docs/ep.md
$CRIT_OK"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
for flag in ausente zero; do
  [[ $flag == zero ]] && export MAESTRO_COLD_REVIEW_REQUIRE=0
  a=$("$REAL" order --entry-check 1 --project "$P" 2>&1; echo "rc=$?")
  b=$("$NEW" order --entry-check 1 --project "$P" 2>&1; echo "rc=$?")
  [[ "$a" == "$b" ]] && ok "entry-check igual ($flag)" || bad "entry-check difere ($flag): [$a] vs [$b]"
done
unset MAESTRO_COLD_REVIEW_REQUIRE
grep -q 'rc=0' <<<"$a" && ok "risco alto sem recibo passa com a flag desligada" || bad "flag off barrou: $a"

# --accept: dois projetos idênticos, um por binário
acc() { # <bin> <nome> → saída normalizada do accept
  local b="$1" f br
  entry_project "$2"
  mkdir -p "$P/docs"; echo d > "$P/docs/ep.md"; G add -A; G commit -qm doc
  entry_order "fecha" "$TURNO_OK
- fecha_epico: docs/ep.md
$CRIT_OK"
  f=$(ls "$P"/.maestro/orders/001-*.md); G add -A; G commit -qm o1
  BIN="$b" declare_order "$P" 1 'true'
  br=$(grep '^branch:' "$f" | awk '{print $2}')
  G checkout -qb "$br"; echo b >> "$P/f.txt"; G add -A; G commit -qm ent
  "$b" evidence --record --label order-1 --project "$P" -- true >/dev/null 2>&1
  "$b" order --accept 1 --project "$P" --session s1 --intent-reviewed 2>&1 | norm
  echo "rc=${PIPESTATUS[0]}"
}
a=$(acc "$REAL" ar); b=$(acc "$NEW" an)
[[ "$a" == "$b" ]] && ok "accept igual (flag desligada)" || bad "accept difere: [$a] vs [$b]"
grep -q 'rc=0' <<<"$b" && ok "accept passa sem drift com a flag desligada" || bad "accept off: $b"

# --create: sem a flag da 059, idêntico; com ela, a única diferença é a linha `- risco: baixo`
cr() { # <bin> <nome> <entry_require>
  entry_project "$2"
  printf '' | MAESTRO_ENTRY_REQUIRE="$3" "$1" order --create --title t --project "$P" --session s0 >/dev/null 2>&1
  sed '/^ts:/d;/^epoch:/d;/^head:/d;/^intent_hash:/d;/^branch:/d' "$(ls "$P"/.maestro/orders/001-*.md)"
}
a=$(cr "$REAL" cr1 0); b=$(cr "$NEW" cr2 0)
[[ "$a" == "$b" ]] && ok "create igual (059 desligada)" || bad "create difere"
grep -q 'risco:' <<<"$b" && bad "esqueleto traz risco com a 059 desligada" || ok "create sem risco com a 059 desligada"
a=$(cr "$REAL" cr3 1); b=$(cr "$NEW" cr4 1)
[[ "$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -c '^[<>]')" -eq 1 ]] && grep -q '^- risco: baixo$' <<<"$b" && ok "create com a 059 ligada: só ganha '- risco: baixo'" || bad "create 059 ligada difere além do risco"
exit $fail
