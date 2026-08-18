#!/usr/bin/env bash
# S-202 + S-204: testes do CLI (src/cli.ts).
# Verifica exit codes, envelope de erro (API_SPEC §3), schema do decision record
# (DATA_MODEL §3), idempotência por sessão, truncamento de --reason e a agregação
# de `log --summary` sobre um JSONL sintético.
# Isolado: MAESTRO_HOME em mktemp -d. NUNCA toca em ~/.maestro real.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
CLI="$REPO/src/cli.ts"

tmp=$(mktemp -d)
export MAESTRO_HOME="$tmp/state"
# E7/S-701: ancora o "projeto corrente" num diretório SEM git — senão o decide
# carimbaria `wtree` do repo Maestro e as asserções de schema exato abaixo
# dependeriam do estado do working tree de quem roda a suíte. O caminho feliz
# do wtree tem teste próprio (test-wtree.sh, com fixture git controlado).
mkdir -p "$tmp/no-git-proj"
export CLAUDE_PROJECT_DIR="$tmp/no-git-proj"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
chk_grep() { # chk_grep <desc> <arquivo> <regex>
  if grep -qE "$3" "$2"; then ok "$1"; else bad "$1 (regex '$3' não casou)"; fi
}

OUT="$tmp/out"; ERR="$tmp/err"; rc=0
run() { bun "$CLI" "$@" >"$OUT" 2>"$ERR"; rc=$?; }

command -v bun >/dev/null || { echo "FAIL bun ausente (necessário no E2)"; exit 1; }
command -v jq  >/dev/null || { echo "FAIL jq ausente (dependência declarada)"; exit 1; }

# ---------------------------------------------------------------------------
echo "-- decide: caminho feliz + schema do record"
# ---------------------------------------------------------------------------
run decide --session sess-A --workflow fix --mode subagent \
    --agents golang-pro --reason "bug em Go, 1 modulo"
chk "decide válido sai 0" "$rc" "0"
REC="$MAESTRO_HOME/sessions/sess-A.json"
[[ -f "$REC" ]] && ok "record criado em sessions/<session_id>.json" \
                || bad "record criado em sessions/<session_id>.json"
jq -e . "$REC" >/dev/null 2>&1 && ok "record é JSON válido" || bad "record é JSON válido"

keys=$(jq -c 'keys_unsorted' "$REC" 2>/dev/null)
chk "record tem exatamente os campos do DATA_MODEL §3 (sem extras)" "$keys" \
    '["session_id","ts","expires_at","workflow","mode","agents","reason"]'
chk "session_id gravado" "$(jq -r .session_id "$REC")" "sess-A"
chk "workflow gravado"   "$(jq -r .workflow   "$REC")" "fix"
chk "mode gravado"       "$(jq -r .mode       "$REC")" "subagent"
chk "agents é array"     "$(jq -r '.agents|type' "$REC")" "array"
chk "agents[0]"          "$(jq -r '.agents[0]' "$REC")" "golang-pro"
chk_grep "ts em ISO-8601 com offset" "$REC" '"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}"'
ts_e=$(date -d "$(jq -r .ts "$REC")" +%s)
ex_e=$(date -d "$(jq -r .expires_at "$REC")" +%s)
chk "expires_at = ts + 4h (14400s)" "$((ex_e - ts_e))" "14400"

echo "-- decide: linha decision no JSONL"
LOG="$MAESTRO_HOME/logs/routing.jsonl"
[[ -f "$LOG" ]] && ok "routing.jsonl criado" || bad "routing.jsonl criado"
chk "1 linha no log" "$(wc -l < "$LOG")" "1"
jq -e . "$LOG" >/dev/null 2>&1 && ok "linha do log é JSON válido" || bad "linha do log é JSON válido"
chk "event=decision"          "$(jq -r .event "$LOG")" "decision"
chk "log: session_id"         "$(jq -r .session_id "$LOG")" "sess-A"
chk "log: agents como array"  "$(jq -r '.agents|type' "$LOG")" "array"
chk "log NÃO contém reason (sem texto de prompt)" "$(jq -r 'has("reason")' "$LOG")" "false"
if grep -q '"/' "$LOG"; then bad "log sem caminho de arquivo"; else ok "log sem caminho de arquivo"; fi
# E3: com agents/*.md instalado, o decide acima já validou 'golang-pro' contra o
# roster real. O que esta asserção provava — instalação SEM roster avisa em vez
# de falhar — vira um caso explícito, com plugin root vazio e MAESTRO_HOME
# separado (para não mexer nas contagens de record/log deste bloco).
sem_roster=$(mktemp -d)
MAESTRO_HOME="$tmp/sem-roster" MAESTRO_PLUGIN_ROOT="$sem_roster" \
  MAESTRO_ROUTING_TABLE="$REPO/config/routing-table.yaml" \
  run decide --session sess-R --workflow fix --mode subagent --agents nome-qualquer
chk "roster vazio: decide não falha, só avisa" "$rc" "0"
chk_grep "aviso de roster vazio no stderr" "$ERR" 'roster vazio'
rm -rf "$sem_roster"

# ---------------------------------------------------------------------------
echo "-- decide: idempotência por sessão"
# ---------------------------------------------------------------------------
run decide --session sess-A --workflow refactor --mode direct
chk "segunda decisão para a mesma sessão sai 0" "$rc" "0"
chk "continua havendo 1 record por sessão" \
    "$(ls "$MAESTRO_HOME/sessions" | wc -l)" "1"
chk "record sobrescrito (workflow atualizado)" "$(jq -r .workflow "$REC")" "refactor"
chk "record de mode=direct não tem agents" "$(jq -r 'has("agents")' "$REC")" "false"
chk "record de mode=direct sem reason quando não informado" "$(jq -r 'has("reason")' "$REC")" "false"
chk "campos de mode=direct" "$(jq -c 'keys_unsorted' "$REC")" \
    '["session_id","ts","expires_at","workflow","mode"]'
chk "log é append-only (2 linhas após 2 decisões)" "$(wc -l < "$LOG")" "2"
chk_grep "saída avisa que a decisão foi atualizada" "$OUT" 'decisão atualizada'

# ---------------------------------------------------------------------------
echo "-- decide: truncamento de --reason em 120 chars"
# ---------------------------------------------------------------------------
long=$(printf 'x%.0s' $(seq 1 200))
run decide --session sess-B --workflow fix --mode direct --reason "$long"
chk "decide com reason longo sai 0" "$rc" "0"
chk "reason truncado em 120 chars" \
    "$(jq -r '.reason|length' "$MAESTRO_HOME/sessions/sess-B.json")" "120"
chk_grep "aviso de truncamento no stderr" "$ERR" 'reason truncado em 120'
run decide --session sess-B2 --workflow fix --mode direct --reason "$(printf 'a\nb\tc')"
chk "reason com quebra de linha vira uma linha só" \
    "$(jq -r .reason "$MAESTRO_HOME/sessions/sess-B2.json")" "a b c"
chk "record permanece em uma única linha" \
    "$(wc -l < "$MAESTRO_HOME/sessions/sess-B2.json")" "1"

# ---------------------------------------------------------------------------
echo "-- decide: exit codes de validação (API_SPEC §2/§3)"
# ---------------------------------------------------------------------------
env_re='^maestro: (config|validation|env): .+ \(fix: .+\)$'

expect_err() { # expect_err <desc> <rc esperado> <categoria> -- <args...>
  local desc="$1" want="$2" cat="$3"; shift 4
  run "$@"
  if [[ "$rc" != "$want" ]]; then bad "$desc (rc=$rc, esperado $want)"; return; fi
  if ! grep -qE "^maestro: $cat: " "$ERR"; then
    bad "$desc (categoria != $cat: $(head -1 "$ERR"))"; return
  fi
  if ! grep -qE "$env_re" "$ERR"; then bad "$desc (envelope fora do formato)"; return; fi
  if grep -qE '^\s+at |Error:' "$ERR"; then bad "$desc (stack trace em uso normal)"; return; fi
  ok "$desc"
}

expect_err "sem --session → 1/validation"            1 validation -- decide --workflow fix --mode direct
expect_err "--session inválido → 1/validation"       1 validation -- decide --session "s/../x" --workflow fix --mode direct
expect_err "--session sem valor → 1/validation"      1 validation -- decide --session --workflow fix
expect_err "sem --workflow → 1/validation"           1 validation -- decide --session s9 --mode direct
expect_err "workflow inexistente → 1/validation"     1 validation -- decide --session s9 --workflow nope --mode direct
expect_err "sem --mode → 1/validation"               1 validation -- decide --session s9 --workflow fix
expect_err "mode inválido → 1/validation"            1 validation -- decide --session s9 --workflow fix --mode turbo
expect_err "subagent sem --agents → 1/validation"    1 validation -- decide --session s9 --workflow fix --mode subagent
expect_err "multi sem --agents → 1/validation"       1 validation -- decide --session s9 --workflow fix --mode multi
expect_err "multi com 1 agente → 1/validation"       1 validation -- decide --session s9 --workflow fix --mode multi --agents solo
expect_err "nome de agente inválido → 1/validation"  1 validation -- decide --session s9 --workflow fix --mode subagent --agents "Bad Name"
expect_err "direct com --agents → 1/validation"      1 validation -- decide --session s9 --workflow fix --mode direct --agents golang-pro
expect_err "flag desconhecida → 1/validation"        1 validation -- decide --session s9 --workflow fix --mode direct --turbo
expect_err "subcomando inexistente → 1/validation"   1 validation -- explodir
expect_err "sem subcomando → 1/validation"           1 validation --

chk "nenhum record criado por comando inválido" \
    "$(ls "$MAESTRO_HOME/sessions" | grep -c '^s9' || true)" "0"

echo "-- decide: ambiente quebrado → 2"
empty=$(mktemp -d)
MAESTRO_PLUGIN_ROOT="$empty" run decide --session s9 --workflow fix --mode direct
chk "routing-table ausente → rc 2" "$rc" "2"
chk_grep "categoria config no envelope" "$ERR" '^maestro: config: .+ \(fix: .*doctor.*\)$'
printf 'workflows: [\n' > "$empty/bad.yaml"
MAESTRO_ROUTING_TABLE="$empty/bad.yaml" run decide --session s9 --workflow fix --mode direct
chk "routing-table ilegível → rc 2" "$rc" "2"
rm -rf "$empty"

# ---------------------------------------------------------------------------
echo "-- status"
# ---------------------------------------------------------------------------
run status --session sess-A
chk "status sai 0" "$rc" "0"
chk_grep "status mostra kill-switch"    "$OUT" 'kill-switch : inativo'
chk_grep "status mostra a decisão"      "$OUT" 'workflow  : refactor'
chk_grep "status mostra validade"       "$OUT" 'válida por mais'
chk_grep "status mostra últimos eventos" "$OUT" 'Últimos 5 eventos'

MAESTRO_OFF=1 run status --session sess-A
chk_grep "status reflete kill-switch ativo" "$OUT" 'kill-switch : ATIVO'

run status --session sess-inexistente
chk "status de sessão sem record sai 0" "$rc" "0"
chk_grep "status orienta a registrar decisão" "$OUT" 'Nenhuma decisão registrada'

cat > "$MAESTRO_HOME/sessions/sess-old.json" <<'J'
{"session_id":"sess-old","ts":"2020-01-01T00:00:00-03:00","expires_at":"2020-01-01T04:00:00-03:00","workflow":"fix","mode":"direct"}
J
run status --session sess-old
chk_grep "status detecta record expirado" "$OUT" 'EXPIRADA'

echo "-- status/log degradam sem log"
empty_home=$(mktemp -d)
MAESTRO_HOME="$empty_home" run status
chk "status sem estado algum sai 0" "$rc" "0"
chk_grep "status avisa que o log não existe" "$OUT" 'log ainda não existe'
MAESTRO_HOME="$empty_home" run log
chk "log inexistente sai 0" "$rc" "0"
chk_grep "log avisa ausência do arquivo" "$OUT" 'ainda não existe'
MAESTRO_HOME="$empty_home" run log --summary
chk "log --summary sem log sai 0" "$rc" "0"
rm -rf "$empty_home"

# ---------------------------------------------------------------------------
echo "-- log --summary sobre JSONL sintético"
# ---------------------------------------------------------------------------
synth=$(mktemp -d); mkdir -p "$synth/logs" "$synth/sessions"
cat > "$synth/logs/routing.jsonl" <<'J'
{"ts":"2026-08-01T10:00:00-03:00","event":"decision","session_id":"a","workflow":"fix","mode":"subagent","agents":["golang-pro"]}
{"ts":"2026-08-01T10:01:00-03:00","event":"gate_pass","session_id":"a","tool":"Edit","file_ext":".go"}
{"ts":"2026-08-01T10:02:00-03:00","event":"gate_pass","session_id":"a","tool":"Edit","file_ext":".go"}
{"ts":"2026-08-01T10:03:00-03:00","event":"gate_pass","session_id":"a","tool":"Write","file_ext":".go"}
{"ts":"2026-08-01T10:04:00-03:00","event":"gate_warn","session_id":"a","tool":"Edit","file_ext":".ts"}
{"ts":"2026-08-01T11:00:00-03:00","event":"decision","session_id":"a","workflow":"fix","mode":"direct"}
{"ts":"2026-08-01T12:00:00-03:00","event":"decision","session_id":"b","workflow":"feature","mode":"multi","agents":["golang-pro","typescript-pro"]}
{"ts":"2026-08-01T12:01:00-03:00","event":"gate_pass","session_id":"b","tool":"Edit","file_ext":".ts"}
{"ts":"2026-08-01T12:02:00-03:00","event":"gate_pass","session_id":"b","tool":"Edit","file_ext":".ts"}
{"ts":"2026-08-01T12:03:00-03:00","event":"gate_warn","session_id":"b","tool":"Edit","file_ext":".go"}
{"ts":"2026-08-01T12:04:00-03:00","event":"gate_block","session_id":"b","tool":"Edit","file_ext":".yaml"}
{"ts":"2026-08-01T13:00:00-03:00","event":"override_manual","session_id":"b","cmd":"ship"}
{"ts":"2026-08-01T13:30:00-03:00","event":"killswitch","session_id":"b"}
{"ts":"2026-08-01T14:00:00-03:00","event":"session_end","session_id":"b","n":7}
{"ts":"2026-08-01T14:01:00-03:00","event":"evento_inventado","session_id":"b"}
isto nao e json
J
MAESTRO_HOME="$synth" run log --summary
chk "log --summary sai 0" "$rc" "0"
chk_grep "conta decisões (3)"                  "$OUT" 'decisões registradas \(decision\) : 3'
chk_grep "conta override_manual (1)"           "$OUT" 'override_manual\): 1'
chk_grep "taxa automática 75% (3/4)"           "$OUT" 'taxa de roteamento automático   : 75% \(3/4\)'
chk_grep "taxa de override 25%"                "$OUT" 'taxa de override manual         : 25%'
chk_grep "nome do comando no override"         "$OUT" '/ship: 1'
chk_grep "gate_pass = 5"                       "$OUT" 'gate_pass  : 5'
chk_grep "gate_warn = 2"                       "$OUT" 'gate_warn  : 2'
chk_grep "gate_block = 1"                      "$OUT" 'gate_block : 1'
chk_grep "edits_per_decision = 1,67 (5/3, ADR-008)" "$OUT" 'edits_per_decision : 1,67'
chk_grep "sessão a: 3 gate_pass / 2 decisões"  "$OUT" 'a: 3 gate_pass / 2 decisão\(ões\) = 1,50'
chk_grep "distribuição de mode: direct"        "$OUT" 'direct +1 +33%'
chk_grep "distribuição de mode: subagent"      "$OUT" 'subagent +1 +33%'
chk_grep "distribuição de mode: multi"         "$OUT" 'multi +1 +33%'
chk_grep "distribuição de workflow"            "$OUT" 'feature +1'
chk_grep "agentes: golang-pro 2"               "$OUT" 'golang-pro +2'
chk_grep "agentes: typescript-pro 1"           "$OUT" 'typescript-pro +1'
chk_grep "linha inválida contabilizada"        "$OUT" '1 linha\(s\) inválida\(s\)'
chk_grep "evento fora do vocabulário sinalizado" "$OUT" '1 evento\(s\) fora do vocabulário'
chk_grep "outros eventos"                      "$OUT" 'killswitch=1  session_end=1'
if grep -q 'isto nao e json' "$OUT"; then bad "linha inválida não é ecoada"; else ok "linha inválida não é ecoada"; fi

MAESTRO_HOME="$synth" run log --limit 3
chk "log --limit 3 sai 0" "$rc" "0"
chk "log --limit 3 imprime 3 eventos" "$(grep -c '^  2026-' "$OUT")" "3"
MAESTRO_HOME="$synth" run log --limit 0
chk "log --limit inválido → 1" "$rc" "1"
rm -rf "$synth"

# ---------------------------------------------------------------------------
echo "-- isolamento"
# ---------------------------------------------------------------------------
if [[ "$MAESTRO_HOME" == "$tmp/state" ]]; then
  ok "estado confinado ao mktemp -d (nunca ~/.maestro)"
else
  bad "estado confinado ao mktemp -d"
fi

exit $fail
