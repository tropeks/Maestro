#!/usr/bin/env bash
# ordem 048 — três papercuts do fluxo:
#  1. recibo de suíte POR ORDEM (suite-N): duas ordens provadas em sequência
#     ficam ambas VÁLIDAS; `suite` legado segue lido como fallback;
#  2. test-session-start.sh usa o portão de carga de tests/lib/latency.sh:
#     sob carga o estouro do NFR é inconclusivo (rc 0 com marca), em máquina
#     quieta o teto é estrito (reprova);
#  3. `conform` no vocabulário de eventos: `conform --check` não imprime
#     "evento invalido descartado" e o evento chega ao log.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

# ------------------------------------------------------------------ item 1
echo "-- 1. recibo de suíte por ordem"
P="$tmp/proj"; mkdir -p "$P/src/auth"
git -C "$P" init -qb main
cat > "$P/.maestro.yaml" <<'YAML'
verifications:
  auth:
    paths: [src/auth/]
    labels: [suite]
commands:
  suite: true
YAML
echo a > "$P/src/auth/jwt.py"
G add -A; G commit -qm base
for t in um dois tres; do
  "$BIN" order --create --title "ordem $t" --project "$P" <<< "objetivo" >/dev/null
done
G add -A; G commit -qm ordens

prove() { # <n> <slug> <rótulo-do-recibo-da-suíte>
  G checkout -qb "order/00$1-$2" main
  echo "entrega $1" >> "$P/src/auth/jwt.py"
  G add -A; G commit -qm "entrega $1"
  "$BIN" evidence --record --label "order-$1" --project "$P" -- true >/dev/null
  "$BIN" evidence --record --label "$3" --project "$P" -- true >/dev/null
}
prove 1 ordem-um suite-1
prove 2 ordem-dois suite-2
prove 3 ordem-tres suite   # legado: sem sufixo
G checkout -q main

for n in 1 2 3; do
  out=$("$BIN" order --status "$n" --project "$P" 2>&1)
  grep -q 'suite: VÁLIDA' <<<"$out" \
    && ok "ordem $n: recibo da suíte VÁLIDA (2 ordens + 1 legado em sequência)" \
    || bad "ordem $n: recibo da suíte não está VÁLIDA ($(grep 'suite:' <<<"$out"))"
done

# a escrita com o rótulo por ordem respeita o comando declarado (commands.suite)
ef=$(ls "$MAESTRO_HOME"/evidence/*-suite-1 2>/dev/null | head -1)
grep -q '^cmd_match=yes$' "$ef" 2>/dev/null \
  && ok "suite-1 casa commands.suite declarado (cmd_match=yes)" \
  || bad "suite-1 não herdou commands.suite ($(grep cmd_match "$ef" 2>/dev/null))"

# o leitor sem --label, no branch da ordem, resolve suite-N (nunca outro)
G checkout -q order/001-ordem-um
"$BIN" evidence --check --label suite --project "$P" >/dev/null 2>&1 \
  && ok "evidence --check --label suite no branch da ordem 1 resolve suite-1" \
  || bad "evidence --check --label suite no branch da ordem 1"
G checkout -q main

# o gate de aceite usa o MESMO leitor: com suite-2 VÁLIDO no tip, o aceite da ordem 2 PASSA (rc 0)
err=$("$BIN" order --accept 2 --project "$P" 2>&1); rc=$?
[[ $rc -eq 0 ]] && grep -q '^accepted_at: ' "$P"/.maestro/orders/002-*.md \
  && ok "aceite da ordem 2 passa (rc 0, carimbo gravado) com suite-2 VÁLIDO" \
  || bad "aceite da ordem 2 com suite-2 VÁLIDO (rc=$rc: $err)"

# P2-2: só `order/NNN-` vira suite-N; fix/2fa-login e release/1.20.0 leem o legado
for br in fix/2fa-login release/1.20.0 order/005-sem-recibo-proprio; do
  G checkout -q -b "$br" main
  echo "x $br" >> "$P/src/auth/jwt.py"; G add -A; G commit -qm "x"
  "$BIN" evidence --record --label suite --project "$P" -- true >/dev/null
  "$BIN" evidence --check --label suite --project "$P" >/dev/null 2>&1 \
    && ok "branch $br lê o suite legado (não prende em suite-N alheio)" \
    || bad "branch $br leu recibo de outra ordem ($("$BIN" evidence --label suite --project "$P"))"
  G checkout -q main
done

# P2-1: suite-N VENCIDO -> a recusa manda gravar suite-N -> regravo -> VÁLIDA
G checkout -q order/001-ordem-um
echo "mais" >> "$P/src/auth/jwt.py"; G add -A; G commit -qm "mais 1"
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
G checkout -q main
err=$("$BIN" order --accept 1 --project "$P" 2>&1 >/dev/null)
grep -q 'suite: VENCIDA.*--label suite-1 -- true' <<<"$err" \
  && ok "hint de recusa manda gravar suite-1 (rótulo da ordem)" || bad "hint de recusa ($err)"
G checkout -q order/001-ordem-um
"$BIN" evidence --record --label suite-1 --project "$P" -- true >/dev/null
G checkout -q main
"$BIN" order --status 1 --project "$P" 2>&1 | grep -q 'suite: VÁLIDA' \
  && ok "regravado suite-1 -> VÁLIDA (ciclo fecha)" || bad "ciclo VENCIDA->hint->regrava não fechou"

# P3a: --label suite-N explícito checa o hash contra commands.suite
G checkout -q order/001-ordem-um
sed -i 's/^  suite: true/  suite: echo outro/' "$P/.maestro.yaml"
"$BIN" evidence --check --label suite-1 --project "$P" 2>&1 | grep -q 'comando do recibo ≠ commands' \
  && ok "suite-N explícito compara o hash com commands.suite" || bad "suite-N explícito não checou o hash do comando"
G checkout -q -- .maestro.yaml
G checkout -q main

# ------------------------------------------------------------------ item 2
echo "-- 2. session-start: portão de carga"
SS_TEST="$REPO/tests/hooks/test-session-start.sh"
grep -q 'tests/lib/latency.sh' "$SS_TEST" \
  && ok "test-session-start.sh faz source de tests/lib/latency.sh" \
  || bad "test-session-start.sh não usa tests/lib/latency.sh"
# orçamento 0 ms: nenhuma mediana cabe. Limiar 0 → sempre "sob carga".
out=$(MAESTRO_LATENCY_N=3 MAESTRO_SESSION_START_BUDGET_MS=0 MAESTRO_LATENCY_LOAD1M_LIMIAR_X100=0 bash "$SS_TEST" 2>&1); rc=$?
[[ $rc -eq 0 ]] && grep -qi 'inconclusivo' <<<"$out" \
  && ok "sob carga: estouro do NFR é inconclusivo (rc 0 com marca)" \
  || bad "sob carga: esperava rc 0 + INCONCLUSIVO (rc=$rc)"
# limiar altíssimo → "máquina quieta": teto estrito reprova
out=$(MAESTRO_LATENCY_N=3 MAESTRO_SESSION_START_BUDGET_MS=0 MAESTRO_LATENCY_LOAD1M_LIMIAR_X100=99999999 bash "$SS_TEST" 2>&1); rc=$?
[[ $rc -ne 0 ]] && grep -q 'FAIL.*NFR' <<<"$out" \
  && ok "sem carga: teto estrito reprova o NFR" \
  || bad "sem carga: esperava FAIL do NFR (rc=$rc)"

# ------------------------------------------------------------------ item 3
echo "-- 3. conform no vocabulário de eventos"
C="$tmp/conf"; mkdir -p "$C"; git -C "$C" init -qb main
err=$("$BIN" conform --check "$C" 2>&1 >/dev/null)
grep -q 'evento invalido' <<<"$err" \
  && bad "conform --check ainda imprime 'evento invalido descartado'" \
  || ok "conform --check sem 'evento invalido' no stderr"
grep -h '"event":"conform"' "$MAESTRO_HOME"/logs/routing*.jsonl 2>/dev/null | grep -q '"n_lacunas"' \
  && ok "o evento conform chega ao log com n_lacunas" \
  || bad "evento conform não está no log"
grep -q '"turno_teto"' "$REPO/src/cli.ts" && grep -q '"route_fix"' "$REPO/src/cli.ts" && grep -q '"conform"' "$REPO/src/cli.ts" \
  && ok "EVENTS em src/cli.ts lista conform, turno_teto e route_fix" \
  || bad "EVENTS em src/cli.ts incompleto"

exit $fail
