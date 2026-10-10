#!/usr/bin/env bash
# ordem 078 — adversarial: tudo o que NÃO é o comando declarado é recusado sem executar e sem gravar.
# (a) cadeias de shell, (b) argumento com espaço, (c) número da ordem, (d) fim sem crases / sem Turno,
# (e) kill-switch e MAESTRO_HOME trocado, (f) fim editado sem commit; mais as áreas (suite-N incluso).
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

mk_proj adv '`bash tests/run-all.sh`'

echo "-- (a) cadeias não são o comando declarado"
recusado "run-all; script" order-1 -- bash -c "bash tests/run-all.sh; bash $SCRIPT"
recusado "run-all && script" order-1 -- bash -c "bash tests/run-all.sh && bash $SCRIPT"
recusado "run-all | script" order-1 -- bash -c "bash tests/run-all.sh | bash $SCRIPT"
recusado "palavras extras no fim" order-1 -- bash tests/run-all.sh "&&" bash "$SCRIPT"
recusado "caminho absoluto no lugar do relativo (sem expandir)" order-1 -- bash "$P/tests/run-all.sh"
recusado "sem aspas removidas: palavra com aspas literais" order-1 -- bash '"tests/run-all.sh"'

echo "-- (b) argumento com espaço dentro"
recusado "bash \"tests/run-all.sh x\"" order-1 -- bash "tests/run-all.sh x"

echo "-- (c) número da ordem"
aceito "order-0001 e order-1 valem a mesma ordem" order-0001 -- bash tests/run-all.sh
recusado "order-999 (inexistente) → recusa" order-999 -- bash tests/run-all.sh
grep -qi 'não existe\|inexistente' <<<"$REC_OUT" && ok "order-999: a mensagem diz que a ordem não existe" || bad "order-999 sem motivo: $REC_OUT"

echo "-- (d) fim sem crases e ordem sem ## Turno"
mk_proj prosa 'bash tests/run-all.sh sai 0, em prosa'
recusado "fim sem crases → recusa (fecha para negado)" order-1 -- bash tests/run-all.sh
grep -q 'crases' <<<"$REC_OUT" && ok "a mensagem diz que faltam as crases" || bad "sem menção às crases: $REC_OUT"
mk_proj semturno 'x'
OF=$(ls "$P"/.maestro/orders/001-*.md)
awk '/^## Turno/ { skip = 1 } !skip { print }' "$OF" > "$tmp/sem-turno.md" && cp "$tmp/sem-turno.md" "$OF"
G add -A; G commit -qm "ordem sem turno"
recusado "ordem sem bloco ## Turno → recusa" order-1 -- bash tests/run-all.sh

echo "-- (e) sem atalho para o agente"
mk_proj atalho '`bash tests/run-all.sh`'
export MAESTRO_OFF=1
recusado "MAESTRO_OFF=1 não libera" order-1 -- bash "$SCRIPT"
unset MAESTRO_OFF
H0="$MAESTRO_HOME"; export MAESTRO_HOME="$tmp/home-outro"
recusado "MAESTRO_HOME trocado não libera" order-1 -- bash "$SCRIPT"
export MAESTRO_HOME="$H0"
recusado "flag --force não existe como atalho" order-1 --force -- bash "$SCRIPT"

echo "-- (f) o run edita o fim: sem commitar"
mk_proj edita '`bash tests/run-all.sh`'
OF=$(ls "$P"/.maestro/orders/001-*.md)
sed -i "s|^- fim: .*|- fim: \`bash $SCRIPT\`|" "$OF"
recusado "fim editado na árvore, sem commit → recusa" order-1 -- bash "$SCRIPT"
grep -qi 'commit' <<<"$REC_OUT" && ok "a mensagem diz que o fim: editado não está commitado" || bad "sem menção ao commit: $REC_OUT"

echo "-- o fim: que vale é o do commit-base (fim_commit)"
NOBASE=1 mk_proj sembase '`bash tests/run-all.sh`'
recusado "sem fim_commit → recusa mesmo com o comando certo" order-1 -- bash tests/run-all.sh
grep -q 'fim_commit' <<<"$REC_OUT" && grep -q 'order --baseline' <<<"$REC_OUT" \
  && ok "a mensagem diz que falta o fim_commit e como gravar" || bad "sem menção ao fim_commit/baseline: $REC_OUT"
mk_proj commitado '`bash tests/run-all.sh`'
OF=$(ls "$P"/.maestro/orders/001-*.md)
sed -i "s|^- fim: .*|- fim: \`bash $SCRIPT\`|" "$OF"; G add -A; G commit -qm "run muda o fim: e commita"
recusado "fim mudou em commit depois do baseline (script novo) → recusa" order-1 -- bash "$SCRIPT"
recusado "fim mudou em commit depois do baseline (comando antigo) → recusa" order-1 -- bash tests/run-all.sh
grep -q 'depois do baseline' <<<"$REC_OUT" && ok "a mensagem diz que o fim: mudou depois do baseline" || bad "sem motivo do baseline: $REC_OUT"
"$BIN" order --baseline 1 --project "$P" >/dev/null 2>&1; chk=$?
(( chk != 0 )) && ok "--baseline RECUSA sobrescrever baseline existente" || bad "--baseline sobrescreveu o baseline"
recusado "baseline recusado não mexe no fim_commit: o novo comando segue recusado" order-1 -- bash "$SCRIPT"
find "$MAESTRO_HOME" -name '*.baseline' -delete   # o Diretor re-despacha: apaga o registro do baseline antigo
"$BIN" order --baseline 1 --project "$P" >/dev/null 2>&1; chk=$?
(( chk == 0 )) && ok "re-despacho (registro apagado) grava o novo fim_commit" || bad "re-despacho falhou rc=$chk"
aceito "re-baseline pelo Diretor regrava o fim_commit: o novo comando passa" order-1 -- bash "$SCRIPT"
sed -i "s|^- fim: .*|- fim: \`bash x\`|" "$OF"
"$BIN" order --baseline 1 --project "$P" >/dev/null 2>&1; chk=$?
(( chk != 0 )) && ok "baseline recusa o arquivo da ordem com edição não commitada" || bad "baseline aceitou arquivo sujo"
"$BIN" order --baseline 77 --project "$P" >/dev/null 2>&1; chk=$?
(( chk != 0 )) && ok "baseline de ordem inexistente é recusado" || bad "baseline de ordem inexistente passou"

echo "-- área: rótulos de commands.<rótulo> e suite-N"
mk_proj areas '`bash tests/run-all.sh`'
for l in suite tenant-isolation billing frontend suite-1; do
  recusado "$l -- script arbitrário → recusa" "$l" -- bash "$SCRIPT"
  aceito "$l -- comando declarado → executa e grava" "$l" -- bash tests/run-all.sh
done
rec suite -- bash "$SCRIPT"
grep -q 'commands.suite' <<<"$REC_OUT" \
  && ok "área: a mensagem cita o comando declarado do .maestro.yaml" || bad "área: mensagem sem a declaração: $REC_OUT"
printf 'commands:\n  suite: bash tests/run-all.sh\n' > "$P/.maestro.yaml"; G add -A; G commit -qm "só suite"
recusado "área sem declaração (billing) → recusa" billing -- bash tests/run-all.sh
aceito "rótulo livre segue como hoje" qualquer -- bash "$SCRIPT"

echo "-- área: o commands.<rótulo> vale o do COMMIT, não o da árvore de trabalho"
printf 'commands:\n  suite: bash %s\n' "$SCRIPT" > "$P/.maestro.yaml"   # o run edita o yaml sem commitar
recusado "suite: yaml editado sem commit declarando o script → recusa" suite -- bash "$SCRIPT"
recusado "suite-1: yaml editado sem commit declarando o script → recusa" suite-1 -- bash "$SCRIPT"
G checkout -q -- .maestro.yaml
aceito "suite: yaml commitado volta a valer" suite -- bash tests/run-all.sh

echo "-- fallback para o HEAD: o run commita um .maestro.yaml próprio e prova o aceite com ele"
mk_proj yamlrun '`bash tests/run-all.sh`'
printf 'commands:\n  suite: bash %s\n' "$SCRIPT" > "$P/.maestro.yaml"; G add -A; G commit -qm "run declara o próprio suite"
aceito "o fallback lê o yaml do HEAD: suite aceita o script do run (brecha que o aceite fecha)" suite -- bash "$SCRIPT"
aceito "recibo order-1 com o comando declarado no tip" order-1 -- bash tests/run-all.sh
ACC=$("$BIN" order --accept 1 --project "$P" --session dir-1 2>&1); chk=$?
(( chk != 0 )) && ok "accept RECUSA: o .maestro.yaml mudou entre o fim_commit e o tip" || bad "accept aceitou com o yaml mudado: $ACC"
grep -q '\.maestro\.yaml' <<<"$ACC" && grep -q 'fim_commit' <<<"$ACC" \
  && ok "a mensagem cita o .maestro.yaml e o fim_commit" || bad "mensagem sem o yaml/fim_commit: $ACC"
mk_proj yamlok '`bash tests/run-all.sh`'
aceito "recibo order-1 no projeto cujo yaml não mudou" order-1 -- bash tests/run-all.sh
ACC=$("$BIN" order --accept 1 --project "$P" --session dir-1 2>&1); chk=$?
(( chk == 0 )) && ok "accept segue passando quando o .maestro.yaml é o do fim_commit" || bad "accept recusou sem motivo (rc=$chk): $ACC"

exit "$fail"
