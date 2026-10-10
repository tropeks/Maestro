#!/usr/bin/env bash
# ordem 079 — o fim: composto (`cd sub && bash ok.sh`) vale como `bash -c '<texto>'` em order-N:
# exatamente `bash`, `-c` e UM argumento igual (espaços normalizados) a um declarado do commit-base.
# Este arquivo: o caso real e o feliz. O adversarial é o -adversarial.sh.
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

# mk_sub → sub/ok.sh no projeto $P: deixa o marcador (prova que o composto executou)
mk_sub() { mkdir -p "$P/sub"; printf '#!/usr/bin/env bash\ntouch %s\n' "$MARK" > "$P/sub/ok.sh"; }

echo "-- o caso real: fim composto com && declarado"
mk_proj composto '`cd sub && bash ok.sh`'
mk_sub
aceito "order-1 -- bash -c \"cd sub && bash ok.sh\" → executa e grava" order-1 -- bash -c "cd sub && bash ok.sh"
aceito "espaços duplicados dentro do texto normalizam" order-1 -- bash -c "cd  sub  &&  bash ok.sh"
aceito "tab dentro do texto normaliza" order-1 -- bash -c "cd	sub &&	bash ok.sh"
aceito "espaços nas pontas normalizam" order-1 -- bash -c "  cd sub && bash ok.sh  "
aceito "order-0001 vale a mesma ordem 1 (10#)" order-0001 -- bash -c "cd sub && bash ok.sh"

echo "-- fim declarado com espaço duplicado e dois comandos"
mk_proj duplo '`cd  sub  &&  bash ok.sh`'
mk_sub
aceito "declarado com espaços duplicados: o texto normalizado vale" order-1 -- bash -c "cd sub && bash ok.sh"
mk_proj dois '`bash tests/run-all.sh` sai 0; `cd sub && bash ok.sh` sai 0'
mk_sub
aceito "dois comandos entre crases: o composto (segundo) vale" order-1 -- bash -c "cd sub && bash ok.sh"
aceito "dois comandos entre crases: o simples (primeiro) segue valendo" order-1 -- bash tests/run-all.sh

echo "-- a mensagem de recusa lembra o bash -c"
mk_proj msg '`cd sub && bash ok.sh`'
mk_sub
rec order-1 -- bash "$SCRIPT"
grep -q "bash -c '<texto>'" <<<"$REC_OUT" \
  && ok "a recusa lembra que o composto vale como bash -c '<texto>'" || bad "recusa sem o lembrete do bash -c: $REC_OUT"

exit "$fail"
