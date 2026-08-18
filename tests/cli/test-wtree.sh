#!/usr/bin/env bash
# E7 / S-701 — bin/maestro-wtree (fingerprint de conteúdo) + carimbo no decision
# record + freshness no status + schema do doctor.
# Isolado: MAESTRO_HOME e os repos-fixture vivem em mktemp -d. NUNCA toca no
# ~/.maestro real nem depende do estado do repo Maestro (CLAUDE_PROJECT_DIR é
# sempre explícito aqui — determinismo primeiro).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WTREE="$REPO/bin/maestro-wtree"
CLI="$REPO/src/cli.ts"

tmp=$(mktemp -d)
export MAESTRO_HOME="$tmp/state"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v bun >/dev/null || { echo "FAIL bun ausente (necessário no E2)"; exit 1; }
command -v git >/dev/null || { echo "FAIL git ausente (necessário para o fixture)"; exit 1; }
command -v jq  >/dev/null || { echo "FAIL jq ausente (dependência declarada)"; exit 1; }

# ---------------------------------------------------------------------------
echo "-- wtree: propriedades do fingerprint"
# ---------------------------------------------------------------------------
proj="$tmp/proj"
mkdir -p "$proj"
git -C "$proj" init -q
git -C "$proj" config user.email t@t && git -C "$proj" config user.name t
echo 'v1' > "$proj/a.txt"

h1=$(bash "$WTREE" "$proj"); rc=$?
chk "exit 0 dentro de repo" "$rc" "0"
[[ "$h1" =~ ^[0-9a-f]{40}$ ]] && ok "saída é hash de 40 hex" || bad "saída é hash de 40 hex ('$h1')"

h2=$(bash "$WTREE" "$proj")
chk "P1 determinismo: mesmo conteúdo → mesmo hash" "$h2" "$h1"

echo 'novo' > "$proj/b.txt"
h3=$(bash "$WTREE" "$proj")
[[ "$h3" != "$h1" ]] && ok "P2 arquivo novo não-rastreado muda o hash" \
                     || bad "P2 arquivo novo não-rastreado muda o hash"

git -C "$proj" add -A && git -C "$proj" commit -qm snap
h4=$(bash "$WTREE" "$proj")
chk "P1' commit do mesmo conteúdo NÃO muda o hash" "$h4" "$h3"

echo 'ignorado' > "$proj/c.log"
echo '*.log' > "$proj/.gitignore"
h5=$(bash "$WTREE" "$proj")   # .gitignore novo muda; c.log não conta
echo 'ignorado2' >> "$proj/c.log"
h6=$(bash "$WTREE" "$proj")
chk "P2' arquivo dentro do .gitignore não afeta o hash" "$h6" "$h5"

git -C "$proj" status --porcelain > "$tmp/porcelain"
grep -q 'c.log' "$tmp/porcelain" && bad "P3 index real intocado" || ok "P3 index real intocado (staging do usuário preservado)"

nogit="$tmp/nogit"; mkdir -p "$nogit"
bash "$WTREE" "$nogit" >/dev/null 2>&1; rc=$?
chk "fora de repo → exit 3 (degradação silenciosa)" "$rc" "3"

# ---------------------------------------------------------------------------
echo "-- decide: carimbo do wtree no record (DATA_MODEL §3 emenda v1.4)"
# ---------------------------------------------------------------------------
run() { CLAUDE_PROJECT_DIR="$1" bun "$CLI" "${@:2}" >"$tmp/out" 2>"$tmp/err"; rc=$?; }

run "$proj" decide --session wt-A --workflow fix --mode direct
chk "decide em repo git sai 0" "$rc" "0"
REC="$MAESTRO_HOME/sessions/wt-A.json"
w=$(jq -r '.wtree // empty' "$REC")
[[ "$w" =~ ^[0-9a-f]{40}$ ]] && ok "record carimbado com wtree (40 hex)" || bad "record carimbado com wtree ('$w')"
chk "wtree do record = wtree do script (mesma fonte)" "$w" "$(bash "$WTREE" "$proj")"
chk "wtree é o ÚLTIMO campo (ordem estável do record)" \
    "$(jq -r 'keys_unsorted | last' "$REC")" "wtree"

run "$nogit" decide --session wt-B --workflow fix --mode direct
chk "decide fora de git sai 0 (nunca é erro de fluxo)" "$rc" "0"
chk "record fora de git NÃO tem o campo wtree" \
    "$(jq -r 'has("wtree")' "$MAESTRO_HOME/sessions/wt-B.json")" "false"

# log: o vocabulário do JSONL fica intocado — wtree é do RECORD, nunca do log
grep -q 'wtree' "$MAESTRO_HOME/logs/routing.jsonl" \
  && bad "wtree NÃO vaza para o routing.jsonl" \
  || ok  "wtree NÃO vaza para o routing.jsonl (DATA_MODEL §4 intocado)"

# ---------------------------------------------------------------------------
echo "-- status: freshness de conteúdo"
# ---------------------------------------------------------------------------
run "$proj" status --session wt-A
grep -q 'conteúdo  : inalterado desde a decisão' "$tmp/out" \
  && ok "status: conteúdo inalterado → 'inalterado'" \
  || bad "status: conteúdo inalterado → 'inalterado'"

echo 'mudou' >> "$proj/a.txt"
run "$proj" status --session wt-A
grep -q 'ALTERADO desde a decisão' "$tmp/out" \
  && ok "status: conteúdo alterado → aviso de decisão stale" \
  || bad "status: conteúdo alterado → aviso de decisão stale"

run "$nogit" status --session wt-A
grep -q 'não verificável' "$tmp/out" \
  && ok "status fora de git → 'não verificável' (sem fingir certeza)" \
  || bad "status fora de git → 'não verificável'"

run "$nogit" status --session wt-B
grep -q 'conteúdo' "$tmp/out" \
  && bad "status de record sem wtree não inventa linha de conteúdo" \
  || ok  "status de record sem wtree não inventa linha de conteúdo"

# ---------------------------------------------------------------------------
echo "-- doctor: schema aceita wtree válido e reprova malformado"
# ---------------------------------------------------------------------------
"$REPO/bin/maestro" doctor >"$tmp/doc" 2>&1
grep -qE 'ok +decision records' "$tmp/doc" \
  && ok "doctor: records com wtree passam no schema" \
  || bad "doctor: records com wtree passam no schema"

jq '.wtree = "nao-e-um-hash"' "$REC" > "$MAESTRO_HOME/sessions/wt-bad.json"
"$REPO/bin/maestro" doctor >"$tmp/doc" 2>&1
grep -q 'wt-bad' "$tmp/doc" \
  && ok "doctor: wtree malformado é reprovado nomeando o record" \
  || bad "doctor: wtree malformado é reprovado nomeando o record"
rm -f "$MAESTRO_HOME/sessions/wt-bad.json"

exit $fail
