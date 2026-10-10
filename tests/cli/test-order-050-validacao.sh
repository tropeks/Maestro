#!/usr/bin/env bash
# ordem 050 — estados de validação (em_validacao/validada/reprovada) e o gate
# do `--accept` atrás de MAESTRO_ACCEPT_REQUIRE_VALIDATION.
#   v55 pontos 1 a 4: o desenvolvimento não espera a CI; o que depende da CI é
#   validação; reprovada vai para o reparo; aceite só com validação verde.
#   Contrato: estados DERIVADOS de recibos por árvore (nunca autodeclarados);
#   `order --validate N` grava o pedido fora da árvore; recibo `validation-N`
#   verde na MESMA árvore → validada, vermelho → reprovada; árvore mudou →
#   a validação anterior deixa de valer; flag desligada = comportamento de hoje.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/declare-order.sh"

# lib/ está na denylist de autoproteção do gate: a mudança sai como patch em
# docs/patches/050-estados-de-validacao.patch e o Capitão aplica. Mecanismo
# ausente → PENDENTE (nunca reprova); presente → cobra de verdade.
if [[ ! -f "$REPO/lib/core-order-validation.sh" ]]; then
  echo "PENDENTE  ordem 050: aplique docs/patches/050-estados-de-validacao.patch (git apply) e rode de novo"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
G() { git -C "$P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
state() { "$BIN" order --status 1 --json --project "$P" 2>&1 | grep -o '"estado":"[a-z_]*"' | head -1 | cut -d'"' -f4; }
want() { # <rótulo> <estado esperado>
  local got; got=$(state)
  [[ "$got" == "$2" ]] && ok "$1: $2" || bad "$1: esperado '$2', obtido '$got'"
}

mk() { # <n> <com-validation:1|0> → projeto $P com a ordem 1 PROVADA no tip (recibo local verde)
  P="$tmp/p$1"; mkdir -p "$P"
  git -C "$P" init -q -b main
  echo a > "$P/f.txt"
  if [[ "$2" == 1 ]]; then printf 'validation:\n  command: bash tests/run-all.sh\n' > "$P/.maestro.yaml"; fi
  G add -A; G commit -qm base
  "$BIN" order --create --title "Ordem teste" --project "$P" --session s0 >/dev/null <<'BODY'
## Objetivo
Teste.
BODY
  G add -A; G commit -qm "ordem 1"
  declare_order "$P" 1 'true'   # ordem 078: o record de order-1 só executa o declarado no fim:
  G checkout -qb "$(grep '^branch:' "$P"/.maestro/orders/001-*.md | awk '{print $2}')"
  echo b >> "$P/f.txt"; G add -A; G commit -qm entrega
  "$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
}
validation_receipt() { # <true|false> — o runner grava `validation-1` na árvore do tip
  "$BIN" evidence --record --label validation-1 --project "$P" -- "$1" >/dev/null 2>&1 || :
}

# --- (1) validada ---------------------------------------------------------
mk 1 1
want "(1) com validation: e sem pedido" provada
out=$("$BIN" order --validate 1 --project "$P" --session s1 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "(1) --validate grava o pedido (rc 0)" || bad "(1) --validate rc=$rc ($out)"
want "(1) pedido sem recibo de validação" em_validacao
grep -q 'em_validacao' <<<"$("$BIN" order --list --project "$P" 2>&1)" && ok "(1) --list mostra em_validacao" || bad "(1) --list não mostra em_validacao"
validation_receipt true
want "(1) recibo verde na mesma árvore" validada
js=$("$BIN" order --status 1 --json --project "$P" 2>&1)
grep -q '"pede_aceite":true' <<<"$js" && ok "(1) validada pede aceite no --json" || bad "(1) validada sem pede_aceite ($js)"

# --- (2) reprovada e reparo -----------------------------------------------
mk 2 1
"$BIN" order --validate 1 --project "$P" --session s1 >/dev/null 2>&1
validation_receipt false
want "(2) recibo vermelho" reprovada
out=$("$BIN" order --status 1 --project "$P" 2>&1)
grep -q 'REPARO' <<<"$out" && ok "(2) --status sinaliza REPARO" || bad "(2) --status sem sinal de reparo ($out)"
"$BIN" order --validate 1 --project "$P" >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && ok "(2) --validate de reprovada recusa (reparo, não pedido novo)" || bad "(2) --validate de reprovada passou"
# novo tip SEM recibo local → em_execucao; com recibo local verde → provada
echo c >> "$P/f.txt"; G add -A; G commit -qm reparo
want "(2) novo tip sem recibo local" em_execucao
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
want "(2) novo tip com recibo local verde volta a" provada

# --- (3) árvore mudou depois: a validação anterior deixa de valer ----------
mk 3 1
"$BIN" order --validate 1 --project "$P" --session s1 >/dev/null 2>&1
validation_receipt true
want "(3) antes de mudar a árvore" validada
echo d >> "$P/f.txt"; G add -A; G commit -qm mexe
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
want "(3) árvore mudou (recibo local novo, pedido e validação velhos)" provada

# --- (4) gate do --accept atrás da flag -----------------------------------
mk 4 1
"$BIN" order --validate 1 --project "$P" --session s1 >/dev/null 2>&1
MAESTRO_ACCEPT_REQUIRE_VALIDATION=1 "$BIN" order --accept 1 --project "$P" --session s1 >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && ok "(4) flag ligada + em_validacao: --accept recusa" || bad "(4) flag ligada + em_validacao aceitou"
validation_receipt false
MAESTRO_ACCEPT_REQUIRE_VALIDATION=1 "$BIN" order --accept 1 --project "$P" --session s1 >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && ok "(4) flag ligada + reprovada: --accept recusa" || bad "(4) flag ligada + reprovada aceitou"
validation_receipt true
MAESTRO_ACCEPT_REQUIRE_VALIDATION=1 "$BIN" order --accept 1 --project "$P" --session s1 >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 ]] && ok "(4) flag ligada + validada: --accept passa" || bad "(4) flag ligada + validada recusou (rc $rc)"
want "(4) depois do aceite" aceita

mk 5 1
MAESTRO_ACCEPT_REQUIRE_VALIDATION=1 "$BIN" order --accept 1 --project "$P" --session s1 >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && ok "(4) flag ligada + provada (sem pedido): --accept recusa" || bad "(4) flag ligada + provada aceitou"
printf 'accept_require_validation: on\n' >> "$P/.maestro.yaml"
"$BIN" order --accept 1 --project "$P" --session s1 >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && ok "(4) a mesma flag pelo .maestro.yaml também recusa" || bad "(4) flag do yaml não valeu"

# --- (5) flag desligada: comportamento de hoje (golden) --------------------
mk 6 1                       # com validation:, flag DESLIGADA, em_validacao
"$BIN" order --validate 1 --project "$P" --session s1 >/dev/null 2>&1
out_off=$("$BIN" order --accept 1 --project "$P" --session s1 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "(5) flag desligada: --accept passa de em_validacao" || bad "(5) flag desligada recusou (rc $rc)"
mk 7 0                       # SEM validation: — o fluxo antigo
out_old=$("$BIN" order --accept 1 --project "$P" --session s1 2>&1)
[[ "$out_off" == "$out_old" ]] && ok "(5) golden: saída do --accept idêntica com flag desligada" \
  || bad "(5) golden diverge: '$out_off' vs '$out_old'"

# --- (6) projeto sem validation: -------------------------------------------
mk 8 0
want "(6) sem validation:" provada
"$BIN" order --validate 1 --project "$P" >/dev/null 2>&1; rc=$?
[[ $rc -ne 0 ]] && ok "(6) --validate sem validation: recusa" || bad "(6) --validate sem validation: passou"
want "(6) --validate recusado não muda o estado" provada
MAESTRO_ACCEPT_REQUIRE_VALIDATION=1 "$BIN" order --accept 1 --project "$P" --session s1 >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 ]] && ok "(6) flag ligada mas sem validation:: provada → aceita como hoje" || bad "(6) recusou (rc $rc)"

# --- (7) conform conhece os estados novos ----------------------------------
mk 9 1
"$BIN" order --validate 1 --project "$P" --session s1 >/dev/null 2>&1
out=$("$BIN" conform --check --project "$P" 2>&1); rc=$?
grep -qi 'syntax error\|unbound\|command not found\|10#' <<<"$out" \
  && bad "(7) conform estourou sobre em_validacao: $(head -3 <<<"$out" | tr '\n' '|')" \
  || ok "(7) conform lê ordem em_validacao sem estourar"

exit $fail
