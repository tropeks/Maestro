#!/usr/bin/env bash
# ordem 063 item 2 — três estados por métrica, nunca misturados: ok, sem dado
# (fonte presente, janela vazia: exit 0) e FALHA (fonte esperada ausente, ilegível
# ou estourou o timeout: stderr com a fonte e o motivo, painel parcial impresso, exit 3).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/baseline.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
# stubs que funcionam; cada cenário os quebra por variável
cat > "$tmp/bin/ssh" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_SSH:-ok}" == hang ]] && { sleep 30; exit 0; }
[[ "${STUB_SSH:-ok}" == fail ]] && exit 255
printf ' 10:00:00 up 1 day, load average: 0,50, 0,40, 0,30\n8\n'
printf 'total used free shared buff avail\nMem.: 16000 4000 8000 100 4000 8000\n'
printf 'actions.runner.x.service loaded active running Runner\n---\n1\n'
STUB
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_GH:-ok}" == fail ]] && { echo "gh: not logged in" >&2; exit 4; }
case "$1 $2" in "pr list") echo '[]';; "run list") echo '[]';; *) exit 9;; esac
STUB
chmod +x "$tmp/bin/ssh" "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MAESTRO_BASELINE_LAB_SSH=lab-fake MAESTRO_BASELINE_SSH_TIMEOUT=1

# mundo saudável e VAZIO (janela sem registro): fontes presentes, nenhum dado
export MAESTRO_HOME="$tmp/home"
mkdir -p "$MAESTRO_HOME"/{order-state,evidence,logs}; : > "$MAESTRO_HOME/logs/routing.jsonl"
export MAESTRO_PONTE_DB="$tmp/ponte.db"
sqlite3 "$MAESTRO_PONTE_DB" "CREATE TABLE manager_run(run_id TEXT, project TEXT, order_ref TEXT, state TEXT, created_at TEXT);
  CREATE TABLE decision(kind TEXT, origin TEXT, project TEXT, order_ref TEXT, tool_name TEXT, created_at TEXT);
  CREATE TABLE manager_event(event_id TEXT, type TEXT, project TEXT, order_ref TEXT, run_id TEXT, created_at TEXT);
  CREATE TABLE director_inbox(seq INTEGER, created_at TEXT, ref_kind TEXT, ref_id TEXT, state TEXT);"
P="$tmp/proj"; mkdir -p "$P/.maestro/orders"
git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm base

run() { # <args...> → $j (stdout) $err (stderr) $rc
  err=$(bash "$TOOL" "$@" 2>&1 >"$tmp/out"); rc=$?; j=$(<"$tmp/out")
}

# --- sem dado: tudo presente, nada na janela → exit 0, nunca FALHA
run --project "$P" --format json
[[ $rc -eq 0 ]] && ok "sem dado (fontes presentes, janela vazia): exit 0" || bad "sem dado deu rc=$rc: $err"
jq -e '[.metricas[]|.status]|all(.=="ok" or .=="sem dado")' <<<"$j" >/dev/null && ok "nenhuma métrica FALHA quando só falta registro" || bad "FALHA indevida: $(jq -c '[.metricas[]|{id,status}]' <<<"$j")"
jq -e '.metricas[0].status=="sem dado"' <<<"$j" >/dev/null && ok "métrica 1: sem dado (ledger legível e vazio)" || bad "métrica 1: $(jq -c '.metricas[0]' <<<"$j")"
[[ -z "$err" ]] && ok "sem dado não escreve em stderr" || bad "stderr indevido: $err"

# --- ledger ilegível (order-state vira arquivo, não diretório)
rm -rf "$MAESTRO_HOME/order-state"; : > "$MAESTRO_HOME/order-state"
run --project "$P" --format json
[[ $rc -eq 3 ]] && ok "ledger ilegível: exit 3" || bad "ledger ilegível deu rc=$rc"
grep -q 'ledger' <<<"$err" && grep -q 'order-state' <<<"$err" && ok "stderr nomeia o ledger" || bad "stderr: $err"
jq -e '.metricas[0].status=="FALHA" and (.metricas[0].falhas[0].fonte|test("ledger"))' <<<"$j" >/dev/null && ok "métrica 1 marcada FALHA no painel parcial" || bad "painel: $(jq -c '.metricas[0]' <<<"$j")"
jq -e '.metricas|length==9' <<<"$j" >/dev/null && ok "painel parcial ainda tem as nove métricas" || bad "painel parcial truncado"
rm -f "$MAESTRO_HOME/order-state"; mkdir -p "$MAESTRO_HOME/order-state"

# --- routing.jsonl ausente
rm -f "$MAESTRO_HOME/logs/routing.jsonl"
run --project "$P" --format json
[[ $rc -eq 3 ]] && grep -q 'routing.jsonl' <<<"$err" && jq -e '.metricas[3].status=="FALHA" and .metricas[5].status=="FALHA"' <<<"$j" >/dev/null \
  && ok "routing.jsonl ausente: exit 3, fonte em stderr, métricas 4 e 6 FALHA" || bad "routing: rc=$rc err=$err"
: > "$MAESTRO_HOME/logs/routing.jsonl"

# --- gh que falha
STUB_GH=fail run --project "$P" --format json
[[ $rc -eq 3 ]] && grep -q 'gh' <<<"$err" && jq -e '.metricas[1].status=="FALHA"' <<<"$j" >/dev/null \
  && ok "gh falha: exit 3, stderr nomeia o gh, métrica 2 FALHA" || bad "gh: rc=$rc err=$err"

# --- ssh que falha e que estoura o timeout
STUB_SSH=fail run --project "$P" --format json
[[ $rc -eq 3 ]] && grep -q 'lab-fake' <<<"$err" && jq -e '.metricas[4].status=="FALHA"' <<<"$j" >/dev/null \
  && ok "ssh falha: exit 3, stderr nomeia o host, métrica 5 FALHA" || bad "ssh falha: rc=$rc err=$err"
STUB_SSH=hang run --project "$P" --format json
[[ $rc -eq 3 ]] && grep -qi 'timeout' <<<"$err" && jq -e '.metricas[4].status=="FALHA"' <<<"$j" >/dev/null \
  && ok "ssh estoura o timeout: exit 3, motivo timeout" || bad "ssh timeout: rc=$rc err=$err"

# --- banco da Ponte ausente
mv "$MAESTRO_PONTE_DB" "$tmp/ponte.off"
run --project "$P" --format json
[[ $rc -eq 3 ]] && grep -qi 'ponte' <<<"$err" && jq -e '.metricas[3].status=="FALHA"' <<<"$j" >/dev/null \
  && ok "Ponte ausente: exit 3, fonte nomeada, métrica 4 FALHA" || bad "ponte: rc=$rc err=$err"
mv "$tmp/ponte.off" "$MAESTRO_PONTE_DB"

# --- chave do --all sem repo resolvido: FALHA nomeada (a chave e o motivo), nunca pulo silencioso
KEYX="orfao-deadbeef"
printf 'schema=maestro-order-state-v1\nid=1\noutcome=aceita\naccepted_at=2026-10-05T10:00:00-03:00\n' > "$MAESTRO_HOME/order-state/$KEYX-001"
export MAESTRO_BASELINE_REPOS="$tmp/nenhum"; mkdir -p "$tmp/nenhum"
run --all --format json
[[ $rc -eq 3 ]] && grep -q "$KEYX" <<<"$err" && grep -qi 'repo' <<<"$err" && ok "--all: chave sem repo → exit 3 com a chave nomeada em stderr" || bad "--all sem repo: rc=$rc err=$err"
jq -e --arg k "$KEYX" '[.metricas[1].falhas[]|select(.fonte|contains($k))]|length>=1' <<<"$j" >/dev/null && ok "--all: FALHA nomeada no painel" || bad "painel --all: $(jq -c '.metricas[1]' <<<"$j")"

# --- md: FALHA aparece em seção própria
STUB_GH=fail run --project "$P" --format md
grep -q '^## Falhas' <<<"$j" && ok "markdown tem a seção Falhas" || bad "markdown sem a seção Falhas"

exit $fail
