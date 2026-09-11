#!/usr/bin/env bash
# Runner da suíte. Isola o estado em tmpdir: a suíte NUNCA escreve no ~/.maestro real
# (review P2-8) — cada teste ainda isola o seu próprio, isto é a rede de segurança.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Ordem 002 / ponta 1: rodar a suíte de DENTRO de uma sessão real herdava
# MAESTRO_* que a sessão exporta de propósito (MAESTRO_GATE_POLICY do E26/
# S-2601 é o caso que expôs isto) — cada arquivo de teste isolado mentia
# dezenas de FAIL, e a própria suíte dava verde por um motivo ERRADO: o
# MAESTRO_HOME de tmpdir abaixo mascarava a fuga, não a eliminava. Limpa o
# PRÓPRIO ambiente do runner ANTES de despachar qualquer arquivo de teste —
# so a suíte rodando aqui dentro fica equivalente ao runner virgem da CI.
source "$ROOT/tests/lib/env-clean.sh"
maestro_env_clean_inherit

SUITE_HOME=$(mktemp -d)
export MAESTRO_HOME="$SUITE_HOME"
# E19: a suíte nunca toca a rede — o teste do update usa remoto file:// e liga por conta própria.
export MAESTRO_NO_UPDATE_CHECK=1
trap 'rm -rf "$SUITE_HOME"' EXIT

fail=0
run() { echo "== $1"; bash "$1" || fail=1; }

for t in "$ROOT"/tests/hooks/test-*.sh; do [[ -e "$t" ]] && run "$t"; done
# tests/lib/ (E23b): teste de biblioteca sourceável — não é hook nem CLI, e a
# enumeração é por diretório, então sem esta linha o arquivo existiria sem nunca
# rodar (a CI só o veria no shellcheck).
for t in "$ROOT"/tests/lib/test-*.sh;   do [[ -e "$t" ]] && run "$t"; done
for t in "$ROOT"/tests/cli/test-*.sh;   do [[ -e "$t" ]] && run "$t"; done

echo "== doctor"
"$ROOT/bin/maestro" doctor || fail=1

if [[ $fail -eq 0 ]]; then echo "SUITE OK"; else echo "SUITE COM FALHAS" >&2; fi
exit $fail
