#!/usr/bin/env bash
# E11 — grafo graphify com freshness: helper, injeção, CLI e a rotina de refresh.
# Invariante central: grafo velho NUNCA é apresentado como consultável — o
# veredito é honesto ou não existe. A rotina só roda claude headless em grafo
# STALE, com teto por rodada e lock; claude aqui é um FAKE que grava a chamada.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
REFRESH="$REPO/bin/maestro-graph-refresh"
HOOK="$REPO/hooks/session-start.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

mkproj() { # mkproj <dir> [com-grafo] [stale]
  mkdir -p "$1"; git -C "$1" init -q
  echo x > "$1/a.py"; git -C "$1" add -A
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm x
  if [[ "${2:-}" == "grafo" ]]; then
    mkdir -p "$1/graphify-out"; echo '{}' > "$1/graphify-out/graph.json"
    [[ "${3:-}" == "stale" ]] && touch -d "3 hours ago" "$1/graphify-out/graph.json"
  fi
}

echo "-- maestro graph: os quatro estados"
P="$tmp/fresco"; mkproj "$P" grafo
out=$("$BIN" graph --project "$P"); grep -q 'FRESCO' <<<"$out" && ok "fresco → FRESCO" || bad "fresco → FRESCO ($out)"
"$BIN" graph --check --project "$P"; chk "--check fresco → exit 0" "$?" "0"
P2="$tmp/velho"; mkproj "$P2" grafo stale
out=$("$BIN" graph --project "$P2"); grep -q 'STALE — 1 commit' <<<"$out" && ok "stale conta commits" || bad "stale conta commits ($out)"
"$BIN" graph --check --project "$P2"; chk "--check stale → exit 1 (gatilho da rotina)" "$?" "1"
P3="$tmp/semgrafo"; mkproj "$P3"
out=$("$BIN" graph --project "$P3"); grep -q 'ausente' <<<"$out" && ok "ausente é dito, com convite opcional" || bad "ausente ($out)"
"$BIN" graph --check --project "$P3"; chk "--check ausente → exit 0 (gerar é decisão humana)" "$?" "0"
P4="$tmp/nogit"; mkdir -p "$P4/graphify-out"; echo '{}' > "$P4/graphify-out/graph.json"
out=$("$BIN" graph --project "$P4"); grep -q 'sem git' <<<"$out" && ok "sem git não finge frescor" || bad "sem git ($out)"

echo "-- injeção: a linha do grafo na seção Projeto"
run_hook() { printf '{"session_id":"g"}' | CLAUDE_PROJECT_DIR="$1" MAESTRO_HOME="$tmp/h" bash "$HOOK" 2>/dev/null; }
run_hook "$P"  | grep -q 'grafo: FRESCO.*ANTES de ler código' && ok "fresco → manda consultar antes de ler" || bad "fresco na injeção"
run_hook "$P2" | grep -q 'grafo: STALE.*NÃO confie' && ok "stale → manda desconfiar e atualizar" || bad "stale na injeção"
run_hook "$P3" | grep -q '^grafo:' && bad "ausente → nenhuma linha (graphify é opcional)" || ok "ausente → nenhuma linha"

echo "-- rotina: só roda claude em grafo STALE, com teto e lock"
SHIM="$tmp/shim"; mkdir -p "$SHIM"
cat > "$SHIM/claude" <<'FAKE'
#!/usr/bin/env bash
echo "$PWD" >> "${FAKE_LOG:?}"
# o update de verdade rejuvenesce o grafo; o fake também, para o pós-check passar
touch graphify-out/graph.json 2>/dev/null || :
exit 0
FAKE
chmod +x "$SHIM/claude"
export FAKE_LOG="$tmp/chamadas"
MAESTRO_HOME="$tmp/h" MAESTRO_GRAPH_ROOTS="$tmp" MAESTRO_CLAUDE_BIN="$SHIM/claude" "$REFRESH"
chk "claude chamado exatamente 1x (só o stale)" "$(grep -c . "$FAKE_LOG" 2>/dev/null || echo 0)" "1"
grep -q "velho" "$FAKE_LOG" && ok "e foi no projeto certo" || bad "e foi no projeto certo"
grep -q 'FRESCO' <<<"$("$BIN" graph --project "$P2")" && ok "pós-rotina: grafo rejuvenescido" || bad "pós-rotina"
RLOG="$tmp/h/logs/graph-refresh.log"
grep -q 'ok: velho atualizado e FRESCO' "$RLOG" && ok "log de operação registra o desfecho" || bad "log de operação"
grep -q 'rodada encerrada: 1' "$RLOG" && ok "contagem da rodada no log" || bad "contagem da rodada"

echo "-- rotina: teto por rodada e degradações"
for i in 1 2 3 4 5; do mkproj "$tmp/lote$i" grafo stale; done
: > "$FAKE_LOG"
MAESTRO_HOME="$tmp/h" MAESTRO_GRAPH_ROOTS="$tmp" MAESTRO_CLAUDE_BIN="$SHIM/claude" MAESTRO_GRAPH_MAX=2 "$REFRESH"
chk "teto MAESTRO_GRAPH_MAX=2 respeitado" "$(grep -c . "$FAKE_LOG")" "2"
grep -q 'teto de 2' "$RLOG" && ok "quem ficou de fora é anunciado" || bad "quem ficou de fora é anunciado"
: > "$FAKE_LOG"
MAESTRO_HOME="$tmp/h" MAESTRO_GRAPH_ROOTS="$tmp/nao-existe" MAESTRO_CLAUDE_BIN="$SHIM/claude" "$REFRESH"; rc=$?
chk "raiz inexistente → exit 0, zero chamadas" "$rc-$(grep -c . "$FAKE_LOG")" "0-0"
MAESTRO_HOME="$tmp/h" MAESTRO_GRAPH_ROOTS="$tmp" MAESTRO_CLAUDE_BIN="/bin/nao-existe" "$REFRESH"; rc=$?
chk "claude ausente → exit 0 (rotina nunca falha barulhento)" "$rc" "0"
grep -q 'claude ausente' "$RLOG" && ok "ausência registrada no log de operação" || bad "ausência registrada"

echo "-- rotina falha/timeout: grafo intocado"
cat > "$SHIM/claude" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
chmod +x "$SHIM/claude"
mkproj "$tmp/quebra" grafo stale
before=$(stat -c %Y "$tmp/quebra/graphify-out/graph.json")
MAESTRO_HOME="$tmp/h" MAESTRO_GRAPH_ROOTS="$tmp" MAESTRO_CLAUDE_BIN="$SHIM/claude" MAESTRO_GRAPH_MAX=9 "$REFRESH"
chk "update que falha não toca o grafo" "$(stat -c %Y "$tmp/quebra/graphify-out/graph.json")" "$before"
grep -q 'falha/timeout em quebra' "$RLOG" && ok "falha nomeada no log" || bad "falha nomeada no log"

exit $fail
