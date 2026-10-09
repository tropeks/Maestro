#!/usr/bin/env bash
# ordem 077 — tools/harness-minimo/coletar-metricas.sh: com `result`/stream e ponte.db de FIXTURE, devolve
# SÓ inteiros, mostra ausência como "ausente" (nunca zero) e aponta a regressão num par de listas montado
# de propósito. Controles negativos: sem fonte tudo é ausente; o ponte.db não é alterado (mode=ro).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/harness-minimo/coletar-metricas.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

[[ -x "$TOOL" ]] || { bad "coletar-metricas.sh não existe ou não é executável"; exit 1; }

# --- stream de fixture: 2 chamadas de ferramenta (uma é o director_report) e o result ---
S="$tmp/stream.jsonl"
{
  echo '{"type":"system","subtype":"init"}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"x"},{"type":"tool_use","name":"mcp__ponte__director_report","input":{}}]}}'
  echo '{"type":"result","subtype":"success","num_turns":7,"total_cost_usd":1.2345,"duration_ms":999,"usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":3000,"cache_creation_input_tokens":400}}'
} > "$S"

out=$(bash "$TOOL" --stream "$S" --cotacao-milesimos 5400 --aceite-rc 0 --parede-ms 12345)
rc=$?
[[ $rc -eq 0 ]] && ok "coleta com stream sai 0" || bad "coleta com stream saiu $rc"
chk() { # $1=rótulo $2=filtro jq → true
  [[ "$(jq -r "$2" <<<"$out")" == "true" ]] && ok "$1" || bad "$1 — saída: $out"
}
chk "tokens: os quatro contadores, inteiros"  '.tokens == {entrada:100, saida:200, cache_leitura:3000, cache_criacao:400}'
chk "custo em centavos inteiros (USD 123, BRL 667)"  '.custo == {usd_centavos:123, brl_centavos:667}'
chk "turnos, ferramentas e director_report"   '.extras.turnos_modelo == 7 and .extras.chamadas_ferramenta == 2 and .extras.uso_director_report == 1'
chk "aceite sim quando o recibo sai 0"        '.aceite == 1'
chk "parede em ms"                            '.parede_ms == 12345'
# nada de float em lugar nenhum: todo número da saída é inteiro
chk "só inteiros: nenhum número fracionário"  '[.. | numbers | select(. != floor)] | length == 0'

# aceite não: rc 1 do recibo
out=$(bash "$TOOL" --aceite-rc 1)
chk "aceite não quando o recibo sai ≠ 0" '.aceite == 0'

# --- ausência é ausência, nunca zero ---
out=$(bash "$TOOL")
chk "sem fontes: tokens ausentes"        '.tokens | to_entries | all(.value == "ausente")'
chk "sem fontes: custo ausente"          '.custo.usd_centavos == "ausente" and .custo.brl_centavos == "ausente"'
chk "sem fontes: aceite, parede e espera ausentes" '.aceite == "ausente" and .parede_ms == "ausente" and .espera_humano_ms == "ausente"'
chk "sem fontes: regressões ausentes"    '.regressoes == "ausente"'
chk "sem fontes: ponte ausente"          '.intervencoes.ponte == "ausente"'

# result sem o campo de cache → ausente naquele contador, os outros intactos
echo '{"type":"result","num_turns":1,"usage":{"input_tokens":5,"output_tokens":6}}' > "$tmp/parcial.json"
out=$(bash "$TOOL" --stream "$tmp/parcial.json")
chk "contador faltando fica ausente, não zero" '.tokens.cache_leitura == "ausente" and .tokens.entrada == 5 and .custo.usd_centavos == "ausente"'

# --- regressões: o par montado de propósito ---
printf 'T-a\nT-b\nT-c\nT-d\n' > "$tmp/passavam"
printf 'T-c\nT-d\nT-novo\n' > "$tmp/falham"
out=$(bash "$TOOL" --passavam-base "$tmp/passavam" --falham-fim "$tmp/falham")
chk "regressão = passava na base E falha no fim (T-c, T-d)" '.regressoes == {contagem:2, nomes:["T-c","T-d"]}'
: > "$tmp/falham-vazia"
out=$(bash "$TOOL" --passavam-base "$tmp/passavam" --falham-fim "$tmp/falham-vazia")
chk "nenhuma falha no fim → 0 regressões (medido, não ausente)" '.regressoes == {contagem:0, nomes:[]}'

# --- ponte.db de fixture, lido em mode=ro ---
DB="$tmp/ponte.db"
sqlite3 "$DB" "CREATE TABLE decision (id TEXT PRIMARY KEY, kind TEXT, project TEXT, order_ref TEXT, status TEXT, created_at TEXT, resolved_at TEXT);
INSERT INTO decision VALUES
 ('d1','permission','exp-harness-054','order/054-fixture','resolved','2026-10-10T10:00:00.000Z','2026-10-10T10:00:02.000Z'),
 ('d2','permission','exp-harness-054','order/054-fixture','resolved','2026-10-10T10:05:00.000Z','2026-10-10T10:05:01.500Z'),
 ('d3','report','exp-harness-054','order/054-fixture','resolved','2026-10-10T10:30:00.000Z','2026-10-10T10:30:10.000Z'),
 ('d4','question','exp-harness-054','order/054-fixture','open','2026-10-10T10:31:00.000Z',NULL),
 ('d5','permission','outro-projeto','order/054-fixture','resolved','2026-10-10T10:00:00.000Z','2026-10-10T10:09:00.000Z'),
 ('d6','gate','exp-harness-054','order/054-fixture','resolved','2026-10-10T10:00:00.000Z','2026-10-10T10:59:00.000Z');"
antes=$(sha256sum "$DB" | cut -d' ' -f1)
out=$(bash "$TOOL" --ponte-db "$DB" --project exp-harness-054 --order-ref order/054-fixture)
depois=$(sha256sum "$DB" | cut -d' ' -f1)
chk "ponte: conta permission/report/ask do project+order_ref da fixture (gate e outro projeto fora)" \
  '.intervencoes.ponte == {permission:2, report:1, ask:1, total:4, sem_resposta:1}'
chk "ponte: espera = Σ aberta→resolvida em ms (2000+1500+10000)" '.espera_humano_ms == 13500'
[[ "$antes" == "$depois" ]] && ok "ponte.db intacto (leitura mode=ro)" || bad "ponte.db mudou"
out=$(bash "$TOOL" --ponte-db "$DB" --project exp-harness-054 --order-ref order/054-fixture --desde 2026-10-10T10:20:00.000Z)
chk "ponte: --desde recorta a janela do run" '.intervencoes.ponte == {permission:0, report:1, ask:1, total:2, sem_resposta:1}'

# --- uso inválido ---
bash "$TOOL" --parede-ms 1.5 >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "número não inteiro é recusado (rc 2)" || bad "float aceito (rc $rc)"
bash "$TOOL" --nao-existe 1 >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "flag desconhecida é recusada (rc 2)" || bad "flag desconhecida aceita (rc $rc)"

exit $fail
