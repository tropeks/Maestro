#!/usr/bin/env bash
# ordem 077 — tools/harness-minimo/listas-da-suite.sh roda a suíte completa numa árvore e grava a lista dos
# testes que PASSAM e a dos que FALHAM (nomes ordenados, sem repetição; contagens inteiras). Árvore de
# fixture com um run-all.sh falso: um arquivo com 2 ok e 1 FAIL, outro com 1 ok, outro que sai 1 sem
# nenhuma linha FAIL. Controles negativos: árvore sem suíte e uso inválido saem 2; a árvore não muda; e o
# ambiente herdado (HERDR_ENV) NÃO chega à suíte (causa dos 8 FAIL da base).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/harness-minimo/listas-da-suite.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

[[ -x "$TOOL" ]] || { bad "listas-da-suite.sh não existe ou não é executável"; exit 1; }

T="$tmp/arvore"; mkdir -p "$T/tests"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "== $PWD/tests/cli/test-a.sh"' \
  'echo "ok   alfa"' \
  'echo "ok   beta"' \
  'echo "FAIL gama"' \
  'echo "== $PWD/tests/cli/test-b.sh"' \
  'echo "ok   alfa"' \
  'echo "== $PWD/tests/hooks/test-c.sh"' \
  'echo "linha solta sem prefixo"' \
  '[[ -z "${HERDR_ENV:-}" ]] && echo "ok   ambiente limpo" || echo "FAIL ambiente vazou"' \
  'echo "ok   alfa"' \
  'echo "ok   alfa"' \
  'exit 1' > "$T/tests/run-all.sh"
antes=$(cd "$T" && find . -type f | sort | xargs sha256sum | sha256sum)

S="$tmp/saida"
out=$(HERDR_ENV=1 bash "$TOOL" "$T" "$S" 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "o script sai 0 mesmo com a suíte vermelha (ele mede, não julga)" || bad "saiu $rc: $out"

[[ -f "$S/passam.txt" && -f "$S/falham.txt" ]] && ok "grava passam.txt e falham.txt" || bad "listas não gravadas"
[[ "$(cat "$S/passam.txt" 2>/dev/null)" == "$(printf '%s\n' \
  "tests/cli/test-a.sh::alfa" "tests/cli/test-a.sh::beta" "tests/cli/test-b.sh::alfa" \
  "tests/hooks/test-c.sh::alfa" "tests/hooks/test-c.sh::ambiente limpo")" ]] \
  && ok "passam: nomes 'arquivo::teste', caminho relativo, ordenados, sem repetição" || bad "passam.txt: $(cat "$S/passam.txt" 2>/dev/null)"
[[ "$(cat "$S/falham.txt" 2>/dev/null)" == "tests/cli/test-a.sh::gama" ]] \
  && ok "falham: só as linhas FAIL" || bad "falham.txt: $(cat "$S/falham.txt" 2>/dev/null)"
grep -q 'HERDR_ENV' "$S/falham.txt" 2>/dev/null && bad "HERDR_ENV vazou para a suíte" || ok "o ambiente herdado não chega à suíte (env -i)"
[[ "$(cat "$S/suite.rc" 2>/dev/null)" == 1 ]] && ok "suite.rc guarda o rc da suíte (1)" || bad "suite.rc: $(cat "$S/suite.rc" 2>/dev/null)"
[[ -s "$S/suite.log" ]] && ok "suite.log guardado" || bad "suite.log ausente"
grep -qx 'passam=5' <<<"$out" && grep -qx 'falham=1' <<<"$out" && ok "contagens inteiras impressas (passam=5, falham=1)" || bad "contagens: $out"
grep -qE '^(passam|falham)=[0-9]+$' <<<"$out" && ! grep -qE '[0-9]\.[0-9]' <<<"$out" && ok "só inteiros" || bad "float na saída"

depois=$(cd "$T" && find . -type f | sort | xargs sha256sum | sha256sum)
[[ "$antes" == "$depois" ]] && ok "a árvore medida não mudou" || bad "a árvore mudou"

bash "$TOOL" "$tmp/nao-existe" "$tmp/s2" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "árvore sem tests/run-all.sh sai 2" || bad "árvore inválida saiu $rc"
bash "$TOOL" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "uso inválido sai 2" || bad "uso inválido saiu $rc"

exit $fail
