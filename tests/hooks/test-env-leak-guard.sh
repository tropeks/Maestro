#!/usr/bin/env bash
# Guarda de regressão da ordem 001 (E26/S-2601): a CI rodava em runner virgem
# e ficava verde no MESMO commit em que a suíte local, rodada dentro de uma
# sessão real, dava 8 FAIL. Causa: os helpers `run()`/`gate_rc()` de
# test-gate-policy-escopo.sh e test-session-start.sh chamavam
# `env VAR=VAL ... "$@" bash "$HOOK"` sem `-u` — e `env` sem `-u` HERDA o
# resto do ambiente. Uma sessão real exporta MAESTRO_GATE_POLICY (é o E26
# funcionando como projetado); o caso "sem a variável" nunca a removia de
# verdade, e as asserções sobre o caminho/comportamento PADRÃO caíam só fora
# da CI.
#
# Este teste faz o vazamento acontecer de propósito — exporta no AMBIENTE DO
# PROCESSO PAI um valor errado para cada MAESTRO_* que os hooks-alvo leem — e
# roda as duas suítes corrigidas por baixo. As duas TÊM que continuar OK. Se
# alguém relaxar o `-u` de um helper outra vez (ou adicionar um caso novo sem
# ele), este teste falha ALTO antes que o vazamento volte a passar calado.
#
# Atenção especial a MAESTRO_OFF=1: é o pior vazamento possível — se não for
# removido pelo helper, TODO hook vira no-op e a suíte-alvo passaria vazia
# (0 FAIL por não ter rodado nada). Por isso o valor abaixo também poisona
# MAESTRO_OFF, e a suíte-alvo só conta como "OK de verdade" se ainda tiver
# saída/asserções condizentes com o hook tendo rodado — o que as próprias
# suítes-alvo já verificam internamente (ex.: bloco <maestro-routing>).
#
# Por que um arquivo à parte, e não dentro das próprias suítes ou em
# tests/run-all.sh: cada suíte-alvo só teria como testar a si mesma sob
# vazamento chamando a si mesma recursivamente (confuso e propenso a loop);
# e poisonar o ambiente global de tests/run-all.sh vazaria para as OUTRAS ~20
# suítes de tests/hooks/ que não são objeto desta ordem, produzindo falha
# colateral fora de escopo (e algumas dependem de MAESTRO_* ficarem ausentes
# por razões que nada têm a ver com este bug). Um teste dedicado, que só
# invoca as duas suítes-alvo como subprocesso sob poison local, é cirúrgico.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

TARGETS=(
  "$REPO/tests/hooks/test-gate-policy-escopo.sh"
  "$REPO/tests/hooks/test-session-start.sh"
)

# Valores deliberadamente ERRADOS para cada MAESTRO_* que session-start.sh,
# pre-tool-gate.sh e hooks/lib/common.sh leem do ambiente (mesma lista dos
# MAESTRO_LEAK_VARS declarados nos helpers das duas suítes-alvo). Se algum
# vazar para dentro do hook sem passar pelos overrides do caso de teste, as
# asserções de "caminho/comportamento de sempre" das suítes-alvo caem.
POISON_HOME=$(mktemp -d)
trap 'rm -rf "$POISON_HOME"' EXIT
POISON_ENV=(
  "MAESTRO_AGENTS_DIR=$POISON_HOME/nao-existe-agents"
  "MAESTRO_DEBUG=1"
  "MAESTRO_ETHOS_FILE=$POISON_HOME/nao-existe-ethos.md"
  "MAESTRO_GATE_ALLOW_EXT=.nope"
  "MAESTRO_GATE_ALLOW_PATHS=nope/"
  "MAESTRO_GATE_DENY_PATHS=nope/"
  "MAESTRO_GATE_DENY_SELF=nope/"
  "MAESTRO_GATE_MAX_PATH=1"
  "MAESTRO_GATE_MODE=warn"
  "MAESTRO_GATE_ORDER_FROZEN=nope/"
  "MAESTRO_GATE_POLICY=$POISON_HOME/gate-policy-de-outra-sessao.sh"
  "MAESTRO_GATE_STDIN_TIMEOUT=1"
  "MAESTRO_INJECTION_BUDGET=1"
  "MAESTRO_LOCK_TRIES=1"
  "MAESTRO_LOG_DIR=$POISON_HOME/nao-existe-logs"
  "MAESTRO_LOG_FILE=$POISON_HOME/nao-existe-logs/routing.jsonl"
  "MAESTRO_LOG_MAX_BYTES=1"
  "MAESTRO_PLUGIN_ROOT=$POISON_HOME/nao-existe-plugin"
  "MAESTRO_ROUTING_TABLE=$POISON_HOME/nao-existe-routing.yaml"
  "MAESTRO_SESSIONS_DIR=$POISON_HOME/nao-existe-sessions"
  "MAESTRO_STYLE_FILE=$POISON_HOME/nao-existe-style.md"
  "MAESTRO_TTL_SECONDS=1"
  "MAESTRO_UPDATED_FROM=0.0.0"
  "MAESTRO_UPDATED_TO=0.0.0"
  "MAESTRO_UPDATE_REEXEC=1"
  "MAESTRO_OFF=1"
)

for t in "${TARGETS[@]}"; do
  name=$(basename "$t")
  out=$(env "${POISON_ENV[@]}" bash "$t" 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then
    ok "$name continua OK com MAESTRO_* poisoned no ambiente do processo pai"
  else
    bad "$name vazou MAESTRO_* do ambiente (rc=$rc) — o \`env -u\` do helper regrediu"
    printf '%s\n' "$out" | tail -20 | sed 's/^/    /'
  fi
done

[[ $fail -eq 0 ]] && echo "test-env-leak-guard: OK" || echo "test-env-leak-guard: FALHAS" >&2
exit $fail
