#!/usr/bin/env bash
# ordem 062 (A) — a catraca do `habits` deixa de BLOQUEAR e passa a AVISAR.
#   smell novo acima do baseline (oversized-file, oversized-function, deep-nesting):
#   `habits --all` sai 0, imprime `AVISO catraca: …` nomeando os três sensores e
#   nenhum `CATRACA:` bloqueante. O que NÃO muda: smell sem baseline continua
#   saindo 1 (detecção), `--baseline` grava a régua, a dívida VENCIDA também é aviso.
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
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q -b main
printf 'def soma(a, b):\n    return a + b\n' > "$P/base.py"
G add -A; G commit -qm base
"$BIN" habits --baseline --project "$P" >/dev/null   # régua: nenhum slop

# arquivo > 400 linhas
{ echo 'X = 0'; for i in $(seq 1 450); do echo "v$i = $i"; done; } > "$P/grande.py"
# função > 60 linhas
{ echo 'def longa(x):'; for i in $(seq 1 70); do echo "    y$i = x + $i"; done; echo '    return x'; } > "$P/longa.py"
# indentação funda
printf 'def f(x):\n    if x:\n        if x:\n            if x:\n                if x:\n                    if x:\n                        if x:\n                            return 1\n' > "$P/fundo.py"
G add -A; G commit -qm slop

out=$("$BIN" habits --all --project "$P" 2>&1); rc=$?
chk "slop acima do baseline → rc 0 (aviso, não reprova)" "$rc" "0"
grep -q 'AVISO catraca: slop acima do baseline' <<<"$out" && ok "saída traz 'AVISO catraca'" || bad "sem 'AVISO catraca' ($out)"
for s in oversized-file oversized-function deep-nesting; do
  grep -q "AVISO catraca.*$s: [0-9]* > baseline 0" <<<"$out" && ok "aviso nomeia $s com os números" || bad "aviso sem $s ($out)"
done
grep -q 'CATRACA:' <<<"$out" && bad "sobrou 'CATRACA:' bloqueante ($out)" || ok "nenhum 'CATRACA:' bloqueante"

# controle: sem baseline, a detecção continua reprovando (rc 1)
rm -f "$P/.maestro-habits.tsv"
"$BIN" habits --all --project "$P" >/dev/null 2>&1; rc=$?
chk "controle: sem baseline, smell continua rc 1" "$rc" "1"

# controle: dívida VENCIDA também é aviso
PAST=$(( $(date +%s) - 30*86400 ))
printf '# c\noversized-file\t5\t%d\t0\n' "$PAST" > "$P/.maestro-habits.tsv"
out=$("$BIN" habits --all --project "$P" 2>&1); rc=$?
chk "dívida VENCIDA → rc 0" "$rc" "0"
grep -q 'AVISO catraca: dívida declarada VENCEU' <<<"$out" && ok "vencida vira AVISO catraca" || bad "vencida sem aviso ($out)"

# controle: --baseline continua gravando (a régua só desce quando regravada)
"$BIN" habits --baseline --project "$P" >/dev/null 2>&1; rc=$?
chk "--baseline grava e sai 0" "$rc" "0"
grep -q 'oversized-file	1' "$P/.maestro-habits.tsv" && ok "baseline regravado com a contagem atual" || bad "baseline sem a contagem"
out=$("$BIN" habits --all --project "$P" 2>&1); rc=$?
chk "dentro do baseline → rc 0" "$rc" "0"

exit $fail
