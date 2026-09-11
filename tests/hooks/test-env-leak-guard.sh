#!/usr/bin/env bash
# Guarda de regressão da ordem 001 (E26/S-2601), estendida pela ordem 002
# (ponta 1): a CI rodava em runner virgem e ficava verde no MESMO commit em
# que a suíte local, rodada dentro de uma sessão real, dava dezenas de FAIL.
# Causa: helpers que compõem `env VAR=VAL ... "$@" bash "$HOOK"` sem `-u`, ou
# que chamam hook/CLI direto sem limpar o ambiente antes — e `env` sem `-u`
# HERDA o resto do ambiente. Uma sessão real exporta MAESTRO_GATE_POLICY (é o
# E26 funcionando como projetado); o caso "sem a variável" nunca a removia de
# verdade, e as asserções sobre o caminho/comportamento PADRÃO caíam só fora
# da CI.
#
# Este teste faz o vazamento acontecer de propósito — exporta no AMBIENTE DO
# PROCESSO PAI um valor errado para cada MAESTRO_* que os alvos leem — e roda
# as suítes corrigidas por baixo. TODAS TÊM que continuar OK. Se alguém
# relaxar a limpeza de um alvo outra vez (ou adicionar um caso novo sem
# passar por tests/lib/env-clean.sh), este teste falha ALTO antes que o
# vazamento volte a passar calado.
#
# Atenção especial a MAESTRO_OFF=1: é o pior vazamento possível — se não for
# removido pela limpeza, TODO hook vira no-op e a suíte-alvo passaria vazia
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
# invoca as suítes-alvo como subprocesso sob poison local, é cirúrgico.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# Fonte única da lista (ordem 002/ponta 1): tests/lib/env-clean.sh.
source "$REPO/tests/lib/env-clean.sh"

# Só os dois alvos originais da ordem 001: test-gate.sh, test-consent.sh e
# tests/cli/test-order.sh também foram fechados com o mesmo helper nesta
# ordem, mas NÃO entram aqui — test-gate.sh embute o NFR de latência sob
# `min` de 1 amostra (ponta 3, sob investigação à parte) e falha por carga de
# máquina independente de qualquer vazamento; misturar os dois sinais faria
# esta guarda falhar por um motivo que ela não existe para provar. A prova
# de convergência real×limpo desses três arquivos é feita à parte (ver
# relatório da ordem), não recursivamente aqui dentro.
TARGETS=(
  "$REPO/tests/hooks/test-gate-policy-escopo.sh"
  "$REPO/tests/hooks/test-session-start.sh"
)

# Valores deliberadamente ERRADOS para cada MAESTRO_* que session-start.sh,
# pre-tool-gate.sh e hooks/lib/common.sh leem do ambiente (mesma lista de
# MAESTRO_LEAK_VARS de tests/lib/env-clean.sh). Se algum vazar para dentro do
# hook sem passar pelos overrides do caso de teste, as asserções de
# "caminho/comportamento de sempre" das suítes-alvo caem.
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

# Consistência: toda MAESTRO_LEAK_VARS do helper (exceto MAESTRO_HOME — cada
# alvo já recebe o seu próprio MAESTRO_HOME por override explícito, então
# poisoná-la aqui não testaria nada) tem de ter um valor poisoned acima. Se
# tests/lib/env-clean.sh ganhar uma variável nova e este arquivo não for
# atualizado junto, a guarda denuncia o descompasso em vez de ficar cega
# para a variável nova em silêncio.
missing=()
for _v in "${MAESTRO_LEAK_VARS[@]}"; do
  [[ "$_v" == "MAESTRO_HOME" ]] && continue
  printf '%s\n' "${POISON_ENV[@]}" | grep -q "^${_v}=" || missing+=("$_v")
done
if [[ ${#missing[@]} -eq 0 ]]; then
  ok "toda MAESTRO_LEAK_VARS (exceto MAESTRO_HOME) tem valor poisoned aqui"
else
  bad "MAESTRO_LEAK_VARS sem valor poisoned neste teste: ${missing[*]}"
fi

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
