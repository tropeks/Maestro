#!/usr/bin/env bash
# ordem 046 — a ordem do turno no método.
#   (1) `conform --check` exige o bloco `## Turno` e o contrato do relatório;
#   (2) `order --create` emite o esqueleto;
#   (3) `order --turno-check` é o critério do Stop: recibo VÁLIDO no tip (lido
#       do ledger, mesma comparação do `order --status`), rótulos do relatório
#       só como checagem ADICIONAL, teto duro de bloqueios, válvula --turno-livre.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q -b main
echo a > "$P/f.txt"; G add -A; G commit -qm base

TURNO_OK='## Turno
- fatia: contrato e teste vermelho
- fim: bash tests/x.sh
- teto: 2
- fora: o hook
- relatório: ENGINEERING_SPEC, relatório de turno'
HEADLESS='> **Execução headless:** prova em sandbox.'

mk() { # <título> <corpo> — cria a ordem pelo CLI
  printf '%s\n' "$2" | "$BIN" order --create --title "$1" --project "$P" --session s0 >/dev/null
}
conform_lines() { "$BIN" conform --check "$P" 2>/dev/null | grep -E "order-no-(turno|relatorio)" ; }

# --------------------------------------------------------------- (1) conform
mk "sem turno" "$HEADLESS"
mk "completa" "$HEADLESS
$TURNO_OK"
mk "sem fim" "$HEADLESS
$(printf '%s\n' "$TURNO_OK" | grep -v '^- fim:')"
mk "teto ruim" "$HEADLESS
$(printf '%s\n' "$TURNO_OK" | sed 's/^- teto: 2/- teto: abc/')"
mk "sem relatorio" "$HEADLESS
$(printf '%s\n' "$TURNO_OK" | grep -v '^- relatório:')"

out=$(conform_lines)
has() { grep -qE "$1" <<<"$out"; }
has 'order-no-turno.*ordem 001'     && ok "conform: ordem sem ## Turno → order-no-turno" || bad "conform: 001 sem order-no-turno"
has 'order-no-relatorio.*ordem 001' && ok "conform: ordem sem Turno → order-no-relatorio" || bad "conform: 001 sem order-no-relatorio"
has 'ordem 002' && bad "conform: ordem COMPLETA acusada ($(grep 'ordem 002' <<<"$out" | head -1))" || ok "conform: ordem completa conforme"
has 'order-no-turno.*ordem 003'     && ok "conform: sem rótulo fim: → order-no-turno" || bad "conform: 003 sem order-no-turno"
has 'order-no-turno.*ordem 004'     && ok "conform: teto não inteiro → order-no-turno" || bad "conform: 004 sem order-no-turno"
has 'order-no-relatorio.*ordem 005' && ok "conform: sem relatório: → order-no-relatorio" || bad "conform: 005 sem order-no-relatorio"
has 'order-no-turno.*ordem 005'     && bad "conform: 005 acusada de order-no-turno por engano" || ok "conform: 005 só falta o relatório"

# --------------------------------------------------------------- (2) --create
printf '' | "$BIN" order --create --title "esqueleto" --project "$P" --session s0 >/dev/null
OF6=$(ls "$P"/.maestro/orders/006-*.md)
ok_skel=1
for l in '## Turno' 'fatia:' 'fim:' 'teto:' 'fora:' 'relatório:'; do grep -q -- "$l" "$OF6" || ok_skel=0; done
(( ok_skel )) && ok "create: esqueleto traz ## Turno e os 5 rótulos" || bad "create: esqueleto incompleto"
conform_lines | grep -q 'order-no-turno.*ordem 006' \
  && ok "create: esqueleto com placeholder ainda é lacuna (não finge preenchido)" || bad "create: placeholder passou como preenchido"

# --------------------------------------------------------------- (3) --turno-check
G add -A; G commit -qm "ordens"
OA=$(ls "$P"/.maestro/orders/002-*.md); BA=$(grep '^branch:' "$OA" | awk '{print $2}')
chk() { "$BIN" order --turno-check --project "$P" "$@"; }

c=$(chk --session sA 2>&1); rc=$?
[[ $rc -eq 0 && -z "$c" ]] && ok "check: fora de branch de ordem → libera, stdout vazio" || bad "check: main bloqueou/falou (rc=$rc: $c)"

G checkout -qb "$BA"; echo b >> "$P/f.txt"; G add -A; G commit -qm entrega
c=$(chk --session sB 2>&1); rc=$?
[[ $rc -eq 1 ]] && grep -q 'order-2' <<<"$c" && grep -qi 'ausente' <<<"$c" \
  && ok "check: sem recibo → bloqueia e lista o recibo ausente" || bad "check: sem recibo (rc=$rc: $c)"

"$BIN" evidence --record --label order-2 --project "$P" -- true >/dev/null
c=$(chk --session sC 2>&1); rc=$?
[[ $rc -eq 0 && -z "$c" ]] && ok "check: recibo VÁLIDA no tip → libera" || bad "check: recibo válido bloqueou (rc=$rc: $c)"

printf 'texto sem rotulos\n' > "$tmp/rel.txt"
c=$(chk --session sD --report-file "$tmp/rel.txt" 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "check: recibo válido + relatório SEM rótulos → NÃO bloqueia (rótulo é adicional)" || bad "check: rótulo virou critério (rc=$rc: $c)"

echo c >> "$P/f.txt"; G add -A; G commit -qm "mexe"
c=$(chk --session sE --report-file "$tmp/rel.txt" 2>&1); rc=$?
[[ $rc -eq 1 ]] && grep -qi 'vencid' <<<"$c" && ok "check: recibo VENCIDA → bloqueia" || bad "check: vencida (rc=$rc: $c)"
grep -q 'feito' <<<"$c" && ok "check: lista também os rótulos faltantes quando já bloqueia" || bad "check: não listou rótulos ($c)"

# teto: ordem 002 declara teto 2 → 2 bloqueios, o 3º libera
chk --session sT >/dev/null 2>&1; r1=$?
chk --session sT >/dev/null 2>&1; r2=$?
c=$(chk --session sT 2>&1); r3=$?
[[ $r1 -eq 1 && $r2 -eq 1 && $r3 -eq 0 ]] && grep -qi 'teto' <<<"$c" \
  && ok "check: teto 2 → bloqueia 2×, a 3ª libera dizendo que o teto foi atingido" || bad "check: teto (rc=$r1,$r2,$r3: $c)"
chk --session sU >/dev/null 2>&1; chk --session sU >/dev/null 2>&1; chk --session sV >/dev/null 2>&1; rv=$?
[[ $rv -eq 1 ]] && ok "check: contador é por sessão" || bad "check: contador vazou entre sessões (rc=$rv)"

# válvula
"$BIN" order --turno-livre 2 --project "$P" --session s0 >/dev/null 2>&1
grep -q '^turno_livre:' "$OA" && ok "válvula: --turno-livre grava o carimbo na ordem" || bad "válvula: sem carimbo"
chk --session sW >/dev/null 2>&1; rw=$?
[[ $rw -eq 0 ]] && ok "válvula: ordem turno-livre nunca bloqueia" || bad "válvula: bloqueou mesmo livre"
"$BIN" order --status 2 --project "$P" 2>&1 | grep -qi 'turno-livre' \
  && ok "válvula: visível no --status" || bad "válvula: --status não mostra"

# ordem antiga (sem bloco) nunca bloqueia o Stop — vira lacuna no conform
G checkout -q main
OB=$(ls "$P"/.maestro/orders/001-*.md); BB=$(grep '^branch:' "$OB" | awk '{print $2}')
G checkout -qb "$BB"
chk --session sX >/dev/null 2>&1; rx=$?
[[ $rx -eq 0 ]] && ok "check: ordem sem bloco Turno → libera (lacuna é do conform)" || bad "check: ordem antiga bloqueou"

exit "$fail"
