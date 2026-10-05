#!/usr/bin/env bash
# ordem 064 — o esqueleto do `## Turno` emitido por `order --create` traz, ao lado da
# linha "Log e escrita" da 062, a regra do headless: nunca encerrar a resposta esperando
# notificação. Blockquote, não rótulo: o conform e o Stop de turno não a leem como campo.
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

REGRA='> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera por laço até a linha rc= no log; só depois se relata.'

printf '> **Execução headless:** prova em sandbox.\n' | "$BIN" order --create --title "sem turno" --project "$P" --session s0 >/dev/null
F=$(ls "$P"/.maestro/orders/001-*.md 2>/dev/null | head -1)
[[ -n "$F" ]] || { bad "ordem 001 não criada"; exit 1; }

grep -qF -- "$REGRA" "$F" && ok "esqueleto traz a linha do headless, exata" || bad "esqueleto sem a regra do headless"
n=$(grep -cF -- '**Headless:**' "$F"); [[ "$n" == "1" ]] && ok "regra aparece uma vez" || bad "regra $n vez(es)"
grep -qF -- '**Log e escrita:**' "$F" && ok "a regra da 062 segue no esqueleto" || bad "regra da 062 sumiu"

# depois dos cinco rótulos e ao lado da 062 (Log e escrita antes da do headless)
awk '/^- relatório:/{r=NR} /Log e escrita/{l=NR} /\*\*Headless:\*\*/{h=NR} END{exit !(r>0 && l>r && h>l)}' "$F" && ok "regra depois dos rótulos e da Log e escrita" || bad "regra fora de ordem"

# cinco rótulos seguem os mesmos, preenchíveis; conform não acusa a linha
fill() { awk -v a="$1" -v b="$2" '{ if (index($0, a) == 1) print b; else print }' "$F" > "$F.n" && mv "$F.n" "$F"; }
for l in fatia fim teto fora relatório; do
  [[ $(grep -c "^- ${l}:" "$F") == 1 ]] && ok "rótulo ${l} único" || bad "rótulo ${l} mudou"
done
fill '- fatia:'     '- fatia: um turno'
fill '- fim:'       '- fim: bash tests/x.sh'
fill '- teto:'      '- teto: 2'
fill '- fora:'      '- fora: nada'
fill '- relatório:' '- relatório: ENGINEERING_SPEC'
out=$("$BIN" conform --check "$P" 2>/dev/null | grep -E "order-no-(turno|relatorio)" || true)
[[ -z "$out" ]] && ok "conform: linha do headless não acusada" || bad "conform acusa ($out)"

# corpo que já traz ## Turno não duplica nada
printf '## Turno\n- fatia: a\n- fim: b\n- teto: 1\n- fora: c\n- relatório: d\n' | "$BIN" order --create --title "com turno" --project "$P" --session s0 >/dev/null
F2=$(ls "$P"/.maestro/orders/002-*.md | head -1)
grep -qF '**Headless:**' "$F2" && bad "regra injetada em corpo que já tinha Turno" || ok "corpo próprio fica como veio"

exit $fail
