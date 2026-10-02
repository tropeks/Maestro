#!/usr/bin/env bash
# ordem 044 — o carimbo de aceite commitado na main não pode vencer o recibo
# de uma ordem EMPILHADA.
#
# Caso real: a ordem B nasce sobre o branch da A; o aceite da A grava o
# carimbo em .maestro/orders/ e ele é commitado na main; o branch da B é
# rebaseado sobre a main para voltar a fast-forward. O rebase traz o carimbo
# para dentro de `B^{tree}` — e o recibo da B (gravado antes) tem uma árvore
# com o .maestro de antes. Os dois lados descrevem o MESMO conteúdo provado;
# só o bookkeeping de governança (.maestro/**, fora do que o recibo prova —
# issue #6 / DATA_MODEL §3 v1.10) mudou. O recibo tem de seguir VÁLIDO.
#
# Cobre os três leitores: `order --status`, `order --status --json` e o
# `evidence --label` lido direto — e dois controles negativos (mudança de
# conteúdo FORA de .maestro/ ainda vence o recibo).
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
echo a > "$P/f.txt"
G add -A; G commit -qm base

for n in A B; do
  "$BIN" order --create --title "Ordem $n" --project "$P" --session dir-1 >/dev/null <<'BODY'
## Objetivo
Empilhada.
BODY
done
G add -A; G commit -qm "ordens 1 e 2"
OA=$(ls "$P"/.maestro/orders/001-*.md); BA=$(grep '^branch:' "$OA" | awk '{print $2}')
OB=$(ls "$P"/.maestro/orders/002-*.md); BB=$(grep '^branch:' "$OB" | awk '{print $2}')

# A: entrega + recibo.   B: nasce SOBRE A, entrega + recibo.
G checkout -qb "$BA"; echo a2 >> "$P/f.txt"; G add -A; G commit -qm "entrega A"
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
G checkout -qb "$BB"; echo b2 > "$P/g.txt"; G add -A; G commit -qm "entrega B"
"$BIN" evidence --record --label order-2 --project "$P" -- true >/dev/null

# Aceite da A + carimbo COMMITADO na main (o defeito); A entra na main; B é
# rebaseado sobre a main (fast-forward volta a ser possível).
G checkout -q main
"$BIN" order --accept 1 --project "$P" --session dir-1 >/dev/null
G add -A; G commit -qm "ordem(001): aceite registrado"
G merge -q --no-ff -m "merge A" "$BA" 2>/dev/null || G merge -q -m "merge A" "$BA"
G checkout -q "$BB"
G rebase -q --onto main "$BA" "$BB" 2>/dev/null || { bad "fixture: rebase de B sobre a main falhou"; exit 1; }

if [[ "$(G show "$BB:.maestro/orders/$(basename "$OA")" | grep -c '^accepted_at:')" -ge 1 ]]; then
  ok "fixture: tip de B contém o carimbo da A (a árvore mudou só em .maestro/)"
else
  bad "fixture: o carimbo da A não chegou ao tip de B"
fi

out=$("$BIN" order --status 2 --project "$P" 2>&1)
grep -qi 'provada' <<<"$out" && ok "order --status 2: recibo da B segue provada após o carimbo da A" \
  || bad "order --status 2: recibo da B venceu pelo carimbo da A (obtido: $(head -5 <<<"$out" | tr '\n' '|'))"

js=$("$BIN" order --status 2 --json --project "$P" 2>&1)
grep -q '"estado":"provada"' <<<"$js" && ok "order --status --json: estado provada" \
  || bad "order --status --json: não é provada (obtido: $js)"

out=$("$BIN" evidence --label order-2 --project "$P" 2>&1)
grep -q 'VÁLIDA' <<<"$out" && ok "evidence --label order-2 (lido direto no checkout de B): VÁLIDA" \
  || bad "evidence --label order-2: venceu (obtido: $out)"

# Controle negativo 1: conteúdo FORA de .maestro/ muda → recibo VENCE.
echo mexeu >> "$P/g.txt"; G add -A; G commit -qm "mexe no conteudo"
out=$("$BIN" order --status 2 --project "$P" 2>&1)
grep -qi 'provada' <<<"$out" && bad "controle: conteúdo mudou e a ordem segue provada (recibo não venceu)" \
  || ok "controle: conteúdo mudou fora de .maestro/ → recibo vence"
out=$("$BIN" evidence --label order-2 --project "$P" 2>&1)
grep -q 'VENCIDA' <<<"$out" && ok "controle: evidence --label vence com conteúdo novo" \
  || bad "controle: evidence --label ainda VÁLIDA com conteúdo novo (obtido: $out)"

exit "$fail"
