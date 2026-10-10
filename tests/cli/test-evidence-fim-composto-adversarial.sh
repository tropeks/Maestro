#!/usr/bin/env bash
# ordem 079 — adversarial do bash -c: tudo o que NÃO é `bash` `-c` <exatamente o declarado> é recusado
# sem executar e sem gravar. (a) texto diferente (b) cadeia extra (c) variável (d) outro invólucro
# (e) argumento a mais / sem texto (f) \n, prefixo, parte (g) outra ordem (h) fim: editado/mudado
# (i) rótulo de área. MAESTRO_REPO_UNDER_TEST aponta outro checkout; padrão: este repo.
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

D='cd sub && bash ok.sh'
mk_sub() { mkdir -p "$P/sub"; printf '#!/usr/bin/env bash\ntouch %s\n' "$MARK" > "$P/sub/ok.sh"; }
mk_proj adv "\`$D\`"
mk_sub

echo "-- controle: o declarado exato passa (sem isto, recusar tudo faria o arquivo inteiro passar vazio)"
aceito "controle: bash -c \"<declarado>\" executa e grava" order-1 -- bash -c "$D"

echo "-- (a) texto diferente do declarado"
recusado "uma palavra a mais" order-1 -- bash -c "cd sub && bash ok.sh now"
recusado "uma palavra a menos" order-1 -- bash -c "cd sub && bash"
recusado "uma palavra trocada" order-1 -- bash -c "cd sub && bash other.sh"

echo "-- (b) cadeia extra"
recusado "; script extra" order-1 -- bash -c "$D; bash $SCRIPT"
recusado "&& extra" order-1 -- bash -c "$D && bash $SCRIPT"
recusado "| extra" order-1 -- bash -c "$D | bash $SCRIPT"
recusado "; no começo" order-1 -- bash -c "bash $SCRIPT; $D"

echo "-- (c) variável"
# shellcheck disable=SC2016  # o \$X literal é o ponto do teste
recusado "\$X literal no lugar de ok.sh" order-1 -- bash -c 'cd sub && bash $X'
export CMD="$D"
# shellcheck disable=SC2016
recusado "\$CMD literal (exportado igual ao declarado)" order-1 -- bash -c '$CMD'
unset CMD

echo "-- (d) outro invólucro"
recusado "bash -lc" order-1 -- bash -lc "$D"
recusado "bash -ec" order-1 -- bash -ec "$D"
recusado "bash -xc" order-1 -- bash -xc "$D"
recusado "sh -c" order-1 -- sh -c "$D"
recusado "/bin/bash -c" order-1 -- /bin/bash -c "$D"
recusado "env bash -c" order-1 -- env bash -c "$D"
recusado "FOO=1 bash -c" order-1 -- FOO=1 bash -c "$D"
recusado "bash -c -c" order-1 -- bash -c -c "$D"

echo "-- (e) argumento a mais / sem texto"
recusado "bash -c \"<declarado>\" extra (o \$0)" order-1 -- bash -c "$D" extra
recusado "bash -c sem texto" order-1 -- bash -c

echo "-- (f) quebra de linha, prefixo e parte"
recusado "texto com \\n no lugar de espaço" order-1 -- bash -c "cd sub &&
bash ok.sh"
recusado "texto com \\n no fim" order-1 -- bash -c "$D
"
recusado "texto é prefixo do declarado" order-1 -- bash -c "cd sub"
recusado "texto é parte do declarado" order-1 -- bash -c "bash ok.sh"
recusado "texto é o declarado mais prefixo" order-1 -- bash -c "x $D"

echo "-- (g) o declarado vale só na ordem dele"
"$BIN" order --create --title "Outra" --project "$P" --session dir-1 >/dev/null <<<"## Turno
- fatia: x
- fim: \`bash tests/run-all.sh\`
- teto: 2
- fora: nada
- relatório: v54"
G add -A; G commit -qm "ordem 2"; "$BIN" order --baseline 2 --project "$P" >/dev/null 2>&1
recusado "bash -c do fim: da ordem 1 em order-2" order-2 -- bash -c "$D"
recusado "bash -c do fim: da ordem 1 em order-999 (inexistente)" order-999 -- bash -c "$D"

echo "-- (h) o fim: editado ou mudado continua recusando"
mk_proj edita "\`$D\`"
mk_sub
OF=$(ls "$P"/.maestro/orders/001-*.md)
sed -i "s|^- fim: .*|- fim: \`bash -c x\`|" "$OF"
recusado "fim editado sem commit: o declarado antigo não vale" order-1 -- bash -c "$D"
recusado "fim editado sem commit: o novo não vale" order-1 -- bash -c "x"
mk_proj muda "\`$D\`"
mk_sub
OF=$(ls "$P"/.maestro/orders/001-*.md)
sed -i "s|^- fim: .*|- fim: \`cd sub \&\& bash $SCRIPT\`|" "$OF"; G add -A; G commit -qm "run muda o fim:"
recusado "fim mudado em commit: o antigo não vale" order-1 -- bash -c "$D"
recusado "fim mudado em commit: o novo não vale" order-1 -- bash -c "cd sub && bash $SCRIPT"
NOBASE=1 mk_proj sembase "\`$D\`"
mk_sub
recusado "sem baseline" order-1 -- bash -c "$D"
mk_proj prosa "$D em prosa"
recusado "fim sem crases" order-1 -- bash -c "$D"

echo "-- (i) rótulo de área não ganha o bash -c"
mk_proj area "\`$D\`"
mk_sub
printf 'commands:\n  suite: %s\n' "$D" > "$P/.maestro.yaml"; G add -A; G commit -qm "suite composta"
recusado "suite -- bash -c \"<declarado>\"" suite -- bash -c "$D"
recusado "suite-1 -- bash -c \"<declarado>\"" suite-1 -- bash -c "$D"
recusado "billing -- bash -c \"<declarado>\"" billing -- bash -c "$D"

echo "-- o simples da 078 não regride"
mk_proj simples '`bash tests/run-all.sh`'
aceito "order-1 -- bash tests/run-all.sh" order-1 -- bash tests/run-all.sh
recusado "bash -c com o simples declarado também é um bash -c: texto igual passa, texto diferente não" order-1 -- bash -c "bash tests/run-all.sh; bash $SCRIPT"

exit "$fail"
