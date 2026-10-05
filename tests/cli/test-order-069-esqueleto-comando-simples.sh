#!/usr/bin/env bash
# ordem 069 — o esqueleto do `## Turno` emitido por `order --create` traz a linha citada
# "Comando simples" (um comando por chamada de Bash) e a linha "Headless" reescrita (a
# convenção rc= sai: a suíte roda como uma chamada, em segundo plano, e a espera é por Monitor).
# Blockquote, não rótulo: o conform e o Stop de turno não as leem como campo.
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

printf '> **Execução headless:** prova em sandbox.\n' | "$BIN" order --create --title "sem turno" --project "$P" --session s0 >/dev/null
F=$(ls "$P"/.maestro/orders/001-*.md 2>/dev/null | head -1)
[[ -n "$F" ]] || { bad "ordem 001 não criada"; exit 1; }

# a linha nova, com cada cláusula
L=$(grep -F -- '**Comando simples:**' "$F" || true)
n=$(grep -cF -- '**Comando simples:**' "$F"); [[ "$n" == "1" ]] && ok "linha Comando simples aparece uma vez" || bad "linha Comando simples $n vez(es)"
has() { [[ "$L" == *"$2"* ]] && ok "cláusula: $1" || bad "cláusula ausente: $1"; }
has "um comando por chamada de Bash"             'um comando por chamada de Bash'
has "caminho absoluto em vez de cd e &&"         'caminho absoluto em vez de cd e &&'
has "sem pipe para cortar saída"                 'sem pipe para cortar saída'
has "2>&1 permitido"                             '2>&1 é permitido'
has "suíte como uma chamada só"                  'a suíte roda como uma chamada só'
has "suíte em segundo plano (run_in_background)" 'run_in_background'
has "espera por Monitor"                         'Monitor'
has "recibo grava o código de saída"             'o recibo já grava o código de saída'

# Headless: texto novo, sem rc=
H=$(grep -F -- '**Headless:**' "$F" || true)
[[ "$H" == *run_in_background* ]] && ok "Headless traz run_in_background" || bad "Headless sem run_in_background"
[[ "$H" == *Monitor* ]] && ok "Headless traz Monitor" || bad "Headless sem Monitor"
[[ "$H" == *"recibo já grava o código de saída"* ]] && ok "Headless: recibo grava o código de saída" || bad "Headless sem o recibo gravando o código de saída"
[[ "$H" == *"rc="* ]] && bad "Headless ainda menciona rc=" || ok "Headless não menciona mais rc="
n=$(grep -cF -- '**Headless:**' "$F"); [[ "$n" == "1" ]] && ok "Headless aparece uma vez" || bad "Headless $n vez(es)"

# a 062 segue, e a ordem das linhas: rótulos < Log e escrita < Headless < Comando simples
grep -qF -- '**Log e escrita:**' "$F" && ok "a regra da 062 segue no esqueleto" || bad "regra da 062 sumiu"
awk '/^- relatório:/{r=NR} /Log e escrita/{l=NR} /\*\*Headless:\*\*/{h=NR} /\*\*Comando simples:\*\*/{c=NR} END{exit !(r>0 && l>r && h>l && c>h)}' "$F" && ok "linhas na ordem: rótulos, Log e escrita, Headless, Comando simples" || bad "linhas fora de ordem"

# cinco rótulos seguem os mesmos, preenchíveis; conform não acusa nenhuma linha
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
[[ -z "$out" ]] && ok "conform: as linhas não são acusadas" || bad "conform acusa ($out)"

# corpo que já traz ## Turno não duplica nada
printf '## Turno\n- fatia: a\n- fim: b\n- teto: 1\n- fora: c\n- relatório: d\n' | "$BIN" order --create --title "com turno" --project "$P" --session s0 >/dev/null
F2=$(ls "$P"/.maestro/orders/002-*.md | head -1)
grep -qF '**Comando simples:**' "$F2" && bad "linha injetada em corpo que já tinha Turno" || ok "corpo próprio fica como veio"

exit $fail
