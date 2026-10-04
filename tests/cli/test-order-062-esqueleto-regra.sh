#!/usr/bin/env bash
# ordem 062 (C) — o esqueleto do `## Turno` emitido por `order --create` traz a
# regra de log e escrita (blockquote, não rótulo): a ordem 082 do daemon só
# aprova leitura sem pedir dentro de /tmp/claude-<uid>/<cwd codificado>.
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

REGRA='> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run, /tmp/claude-<uid>/<cwd codificado>, nunca /tmp solto; escrita só com Edit ou Write.'

printf '> **Execução headless:** prova em sandbox.\n' | "$BIN" order --create --title "sem turno" --project "$P" --session s0 >/dev/null
F=$(ls "$P"/.maestro/orders/001-*.md 2>/dev/null | head -1)
[[ -n "$F" ]] || { bad "ordem 001 não criada"; exit 1; }

grep -qF -- "$REGRA" "$F" && ok "esqueleto traz a linha da regra, exata" || bad "esqueleto sem a regra exata"
grep -qF '/tmp/claude-<uid>/<cwd codificado>' "$F" && ok "cita a pasta do run" || bad "sem /tmp/claude-<uid>"
grep -qF 'escrita só com Edit ou Write' "$F" && ok "cita Edit/Write" || bad "sem Edit/Write"
n=$(grep -cF -- '**Log e escrita:**' "$F"); [[ "$n" == "1" ]] && ok "regra aparece uma vez" || bad "regra $n vez(es)"

# a regra vem DEPOIS do último rótulo, dentro do ## Turno
awk '/^- relatório:/{r=NR} /Log e escrita/{l=NR} END{exit !(r>0 && l>r)}' "$F" && ok "regra depois dos cinco rótulos" || bad "regra fora de ordem"

# os cinco rótulos seguem preenchíveis (placeholder → valor) e o conform não acusa a linha
fill() { awk -v a="$1" -v b="$2" '{ if (index($0, a) == 1) print b; else print }' "$F" > "$F.n" && mv "$F.n" "$F"; }
fill '- fatia:'     '- fatia: um turno'
fill '- fim:'       '- fim: bash tests/x.sh'
fill '- teto:'      '- teto: 2'
fill '- fora:'      '- fora: nada'
fill '- relatório:' '- relatório: ENGINEERING_SPEC'
out=$("$BIN" conform --check "$P" 2>/dev/null | grep -E "order-no-(turno|relatorio)" || true)
[[ -z "$out" ]] && ok "conform: cinco rótulos preenchidos, linha da regra não acusada" || bad "conform acusa ($out)"

# corpo que já traz ## Turno não duplica nada
printf '## Turno\n- fatia: a\n- fim: b\n- teto: 1\n- fora: c\n- relatório: d\n' | "$BIN" order --create --title "com turno" --project "$P" --session s0 >/dev/null
F2=$(ls "$P"/.maestro/orders/002-*.md | head -1)
n=$(grep -c '^## Turno' "$F2"); [[ "$n" == "1" ]] && ok "corpo com ## Turno não duplica o bloco" || bad "bloco duplicado ($n)"
grep -qF '**Log e escrita:**' "$F2" && bad "regra injetada em corpo que já tinha Turno" || ok "corpo próprio fica como veio"

exit $fail
