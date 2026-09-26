#!/usr/bin/env bash
# Ordem 042 — `roster: false` no frontmatter tira o agente da injeção.
#
# O Conformador é chamado sob demanda (Capitão ou Diretor), nunca pelo
# roteamento: o envelope promete que ele fica FORA do roster injetado. Sem
# `experts:` no .maestro.yaml o session-start injeta o roster INTEIRO (S-303),
# então a exclusão tem de morar no próprio agente — um marcador declarativo,
# não uma lista de nomes no hook. Decisão do Diretor 01M3DREC88ACBKHK5250RWVWH4.
#
# Isolamento: MAESTRO_HOME, CLAUDE_PROJECT_DIR e agents/ sempre em mktemp -d.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# mk_agent <dir> <nome> [linha-extra-de-frontmatter]
mk_agent() {
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: aciona %s\nmodel: sonnet\ntools: Read\n%s---\ncorpo\n' \
    "$2" "$2" "${3:+$3$'\n'}" >"$1/$2.md"
}

AG="$SANDBOX/agents"
mk_agent "$AG" dev-pleno
mk_agent "$AG" sob-demanda 'roster: false'
mk_agent "$AG" explicito 'roster: true'

IN="$SANDBOX/in.json"
printf '{"session_id":"ses_042","hook_event_name":"SessionStart"}' >"$IN"

run() { # <conteúdo-do-.maestro.yaml|-> → OUT, RC
  local p; p=$(mktemp -d "$SANDBOX/proj.XXXXXX")
  [[ "$1" == "-" ]] || printf '%s\n' "$1" >"$p/.maestro.yaml"
  OUT=$(env MAESTRO_HOME="$(mktemp -d "$SANDBOX/home.XXXXXX")" CLAUDE_PROJECT_DIR="$p" \
        MAESTRO_AGENTS_DIR="$AG" bash "$HOOK" <"$IN" 2>/dev/null)
  RC=$?
}
listed() { printf '%s\n' "$OUT" | sed -n 's/^- \([a-z0-9-]*\) (.*/\1/p' | sort | tr '\n' ' '; }

echo "-- 1. projeto sem experts: roster inteiro, menos quem declara roster: false"
run -
[[ $RC -eq 0 ]] && ok "exit 0" || bad "exit 0 (rc=$RC)"
L=$(listed)
[[ " $L" != *" sob-demanda "* ]] && ok "roster: false fica fora da injeção" \
  || bad "roster: false injetado mesmo assim — listados: $L"
[[ " $L" == *" dev-pleno "* ]] && ok "agente sem a chave continua injetado" \
  || bad "agente sem a chave sumiu — listados: $L"
[[ " $L" == *" explicito "* ]] && ok "roster: true continua injetado" \
  || bad "roster: true sumiu — listados: $L"

echo "-- 2. experts: nomeando o agente não o traz de volta"
run 'experts: [dev-pleno, sob-demanda]'
L=$(listed)
[[ " $L" != *" sob-demanda "* ]] && ok "experts: não reinjeta roster: false" \
  || bad "experts: reinjetou roster: false — listados: $L"

echo "-- 3. o roster REAL: conformador fora da injeção"
if [[ -f "$REPO/agents/conformador.md" ]]; then
  AG="$REPO/agents"; run -
  L=$(listed)
  [[ " $L" != *" conformador "* ]] && ok "conformador fora do roster injetado" \
    || bad "conformador injetado — listados: $L"
else
  echo "PENDENTE  agents/conformador.md ausente (patch 042 não aplicado)"
fi

if (( fail == 0 )); then echo "OK: test-roster-declarativo"; else echo "FALHOU: test-roster-declarativo" >&2; exit 1; fi
