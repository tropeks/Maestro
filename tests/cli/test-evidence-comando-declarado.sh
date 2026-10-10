#!/usr/bin/env bash
# ordem 078 — evidence --record --label order-N só executa o comando declarado no `fim:` da ordem N
# (trechos entre crases), e rótulo de área só o de commands.<rótulo>: recusa ANTES de executar.
# Este arquivo: o caso real (vermelho antes) e o caso feliz. O adversarial é o -adversarial.sh.
# MAESTRO_REPO_UNDER_TEST aponta outro checkout (o sandbox do patch); padrão: este repo.
set -u

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="${MAESTRO_REPO_UNDER_TEST:-$HERE}"
BIN="$REPO/bin/maestro"

source "$HERE/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
source "$HERE/tests/lib/fixture-comando-declarado.sh"

echo "-- o caso real: script arbitrário em order-N"
mk_proj real '`bash tests/run-all.sh`'
recusado "order-1 -- bash <script fora do fim> → recusa, não executa, não grava" order-1 -- bash "$SCRIPT"
grep -q 'order-1' <<<"$REC_OUT" && grep -q "$SCRIPT" <<<"$REC_OUT" && grep -q 'bash tests/run-all.sh' <<<"$REC_OUT" \
  && ok "a mensagem cita rótulo, comando recusado e comando declarado" \
  || bad "mensagem sem rótulo/comando recusado/declarado: $REC_OUT"
grep -qi 'fim:' <<<"$REC_OUT" && grep -qi 'Diretor' <<<"$REC_OUT" \
  && ok "a mensagem diz como declarar (editar o fim:, decisão do Diretor)" || bad "mensagem sem o como declarar: $REC_OUT"
"$BIN" evidence --check --label order-1 --project "$P" >/dev/null 2>&1
chk_rc=$?
(( chk_rc != 0 )) && ok "sem recibo: evidence --check não passa" || bad "evidence --check passou sem recibo"

echo "-- o caso feliz: o comando declarado executa e grava"
aceito "order-1 -- bash tests/run-all.sh → executa e grava" order-1 -- bash tests/run-all.sh
aceito "order-0001 vale a mesma ordem 1 (10#)" order-0001 -- bash tests/run-all.sh
mk_proj espacos '`bash  tests/run-all.sh`'
aceito "fim com espaço duplicado normaliza" order-1 -- bash tests/run-all.sh
mk_proj tab "\`bash	tests/run-all.sh\`"
aceito "fim com tab entre palavras normaliza" order-1 -- bash tests/run-all.sh
mk_proj dois '`bash tests/cli/test-x.sh` sai 1 antes e 0 depois; `bash tests/run-all.sh` sai 0'
aceito "fim com dois comandos entre crases: o segundo vale" order-1 -- bash tests/run-all.sh

echo "-- rótulo de área: só o comando declarado em .maestro.yaml"
mk_proj area '`bash tests/run-all.sh`'
recusado "suite -- script arbitrário → recusa" suite -- bash "$SCRIPT"
aceito "suite -- comando declarado → executa e grava" suite -- bash tests/run-all.sh

echo "-- rótulo livre segue como hoje"
rec qualquer -- echo ok
(( REC_RC == 0 )) && grep -q 'evidência gravada' <<<"$REC_OUT" && ok "rótulo livre: echo ok grava" || bad "rótulo livre mudou: $REC_OUT"

exit "$fail"
