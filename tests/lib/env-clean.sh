#!/usr/bin/env bash
# tests/lib/env-clean.sh — fonte ÚNICA da lista de MAESTRO_* que um teste
# precisa varrer do ambiente do processo pai antes de invocar hook/CLI, para
# que "sem a variável" signifique sem a variável de verdade.
#
# Causa (E26/S-2601 + ordem 002/ponta 1): a sessão real exporta MAESTRO_* de
# propósito (é o escopo por sessão funcionando como projetado — ex.:
# MAESTRO_GATE_POLICY). `env VAR=VAL ... "$@" bash "$HOOK"` SEM `-u`, ou
# qualquer chamada direta ao hook/CLI sem limpar o ambiente antes, HERDA esse
# resto — o caso "sem a variável" deixa de existir de verdade, e as asserções
# sobre caminho/comportamento PADRÃO caem só fora da CI (runner virgem).
#
# Lista levantada com `grep -ohP 'MAESTRO_[A-Z_]+' hooks/session-start.sh
# hooks/pre-tool-gate.sh hooks/lib/common.sh`.
#
# NÃO entram (de propósito): MAESTRO_NO_UPDATE_CHECK e as
# MAESTRO_TELEMETRY_*/MAESTRO_UPDATE_* que tests/run-all.sh e os testes de
# update/telemetria usam — são a rede de segurança de E19 (sem rede em
# runtime) e têm que SOBREVIVER herdadas, senão os hooks tentariam checar
# update/telemetria de verdade durante a suíte.
#
# Duas frentes de uso:
#   1. um teste isolado que compõe `env VAR=VAL ... bash "$HOOK"`:
#      `maestro_env_clean_flags` monta o array MAESTRO_UNSET_FLAGS de `-u VAR`
#      para entrar ANTES dos overrides do caso (`env "${MAESTRO_UNSET_FLAGS[@]}"
#      VAR=VAL ... bash "$HOOK"`).
#   2. um teste que chama hook/CLI DIRETO (sem `env` por invocação) ou o
#      tests/run-all.sh, que despacha um arquivo de teste por `bash`:
#      `maestro_env_clean_inherit` faz `unset` no PRÓPRIO shell, uma vez, no
#      início — toda chamada seguinte (e todo subprocesso filho) já nasce sem
#      a fuga.
#
# Sourceável, não é enumerado como teste: o nome não casa com o glob
# `test-*.sh` que tests/run-all.sh usa para tests/hooks|cli, e tests/lib/ só
# roda `test-*.sh` (mesmo glob, outro diretório).
MAESTRO_LEAK_VARS=(
  MAESTRO_AGENTS_DIR MAESTRO_DEBUG MAESTRO_ETHOS_FILE MAESTRO_GATE_ALLOW_EXT
  MAESTRO_GATE_ALLOW_PATHS MAESTRO_GATE_DENY_PATHS MAESTRO_GATE_DENY_SELF
  MAESTRO_GATE_MAX_PATH MAESTRO_GATE_MODE MAESTRO_GATE_ORDER_FROZEN
  MAESTRO_GATE_POLICY MAESTRO_GATE_STDIN_TIMEOUT MAESTRO_HOME
  MAESTRO_INJECTION_BUDGET MAESTRO_LOCK_TRIES MAESTRO_LOG_DIR
  MAESTRO_LOG_FILE MAESTRO_LOG_MAX_BYTES MAESTRO_OFF MAESTRO_PLUGIN_ROOT
  MAESTRO_ROUTING_TABLE MAESTRO_SESSIONS_DIR MAESTRO_STYLE_FILE
  MAESTRO_TTL_SECONDS MAESTRO_UPDATED_FROM MAESTRO_UPDATED_TO
  MAESTRO_UPDATE_REEXEC
)

# maestro_env_clean_flags → preenche MAESTRO_UNSET_FLAGS com (-u VAR)... para
# uso em `env "${MAESTRO_UNSET_FLAGS[@]}" VAR=VAL ... bash "$HOOK"`.
maestro_env_clean_flags() {
  MAESTRO_UNSET_FLAGS=()
  local _v
  for _v in "${MAESTRO_LEAK_VARS[@]}"; do MAESTRO_UNSET_FLAGS+=(-u "$_v"); done
}

# maestro_env_clean_inherit → remove as MAESTRO_LEAK_VARS do PRÓPRIO shell,
# para quem chama hook/CLI direto ou despacha subprocessos que herdam o
# ambiente (tests/run-all.sh).
maestro_env_clean_inherit() {
  unset "${MAESTRO_LEAK_VARS[@]}"
}
