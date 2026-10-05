#!/usr/bin/env bash
# ordem 067 item 3 — seções 8 (parcela recibos_regravados) e 9 (custo) do painel leem os campos que o
# `maestro evidence --record` grava: inteiro entra na conta; `ausente` ou inexistente fica fora da soma e
# dentro de n_sem_dado (nunca zero, nunca FALHA); sem nenhum dado a parcela sai "sem dado" (exit 0);
# FALHA só onde a fonte falha: campo presente e inválido (float, texto) ou ledger ilegível (exit 3).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/baseline.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
P="$tmp/proj"
mkdir -p "$P/.maestro/orders" "$MAESTRO_HOME"/{order-state,evidence,logs} "$tmp/bin"
: > "$MAESTRO_HOME/logs/routing.jsonl"
printf '#!/usr/bin/env bash\nprintf " 10:00:00 up 1 day, load average: 0,50, 0,40, 0,30\\n8\\n"\nprintf "total used free shared buff avail\\nMem.: 16000 4000 8000 100 4000 8000\\n"\nprintf "actions.runner.x.service loaded active running Runner\\n---\\n1\\n"\n' > "$tmp/bin/ssh"
printf '#!/usr/bin/env bash\ncase "$1 $2" in "pr list") echo "[]";; "run list") echo "[]";; *) exit 9;; esac\n' > "$tmp/bin/gh"
chmod +x "$tmp/bin/ssh" "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MAESTRO_BASELINE_LAB_SSH=lab-fake MAESTRO_PONTE_DB="$tmp/ponte.db"
sqlite3 "$MAESTRO_PONTE_DB" "
  CREATE TABLE manager_run(run_id TEXT, project TEXT, order_ref TEXT, state TEXT, created_at TEXT);
  CREATE TABLE decision(id TEXT, kind TEXT, origin TEXT, project TEXT, order_ref TEXT, tool_name TEXT, created_at TEXT);
  CREATE TABLE manager_event(event_id TEXT, type TEXT, project TEXT, order_ref TEXT, run_id TEXT, created_at TEXT);
  CREATE TABLE director_inbox(seq INTEGER, created_at TEXT, ref_kind TEXT, ref_id TEXT, state TEXT);"

CORTE=1791083700
git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm base
KEY=$(source "$REPO/hooks/lib/project-state.sh"; b=$(maestro_brief_file "$P"); b="${b##*/}"; echo "${b%.md}")

# add <id> <aceita-epoch> [linha de campo do recibo]...  — recibo sem campo = ordem antiga
add() {
  local id="$1" at="$2" s3; s3=$(printf '%03d' "$1"); shift 2
  printf '<!-- maestro-order v1\nid: %s\nts: x\nepoch: 1790000000\n-->\n# o\n' "$s3" > "$P/.maestro/orders/$s3-x.md"
  printf 'schema=maestro-order-state-v1\nid=%s\noutcome=aceita\naccepted_at=%s\n' "$id" "$(date -d "@$at" +%Y-%m-%dT%H:%M:%S%z)" > "$MAESTRO_HOME/order-state/$KEY-$s3"
  { printf 'schema=maestro-evidence-v1\nlabel=order-%s\nepoch=%s\nexit=0\n' "$id" "$((at-100))"
    local l; for l in "$@"; do printf '%s\n' "$l"; done; } > "$MAESTRO_HOME/evidence/$KEY-order-$id"
}
run() { err=$(bash "$TOOL" "$@" 2>&1 >"$tmp/out"); rc=$?; j=$(<"$tmp/out"); }

# antes: 40 (com dado), 41 (antiga, sem campo); depois: 50 (com dado), 51 (campos ausente), 52 (antiga)
add 40 $((CORTE-5000)) regravacoes=2 tokens=1000 custo_centavos=250
add 41 $((CORTE-4000))
add 50 $((CORTE+5000)) regravacoes=0 tokens=3000
add 51 $((CORTE+6000)) regravacoes=ausente tokens=ausente custo_centavos=ausente custo_fonte=ausente
add 52 $((CORTE+7000))

run --project "$P" --format json
[[ $rc -eq 0 ]] && ok "campo ausente/inexistente não é FALHA: exit 0" || bad "rc=$rc err=$err"
jq -e '.metricas[7].recibos_regravados | .status=="ok" and .antes==2 and .depois==0
  and .n.antes=={populacao:2,n_com_dado:1,n_sem_dado:1} and .n.depois=={populacao:3,n_com_dado:1,n_sem_dado:2}
  and .n_com_dado==2 and .n_sem_dado==3 and .populacao==5' <<<"$j" >/dev/null \
  && ok "seção 8: ok, soma só de quem tem dado (2 antes, 0 depois), N declarado por lado" || bad "m8: $(jq -c '.metricas[7].recibos_regravados' <<<"$j")"
jq -e '.metricas[7].recibos_regravados.por_ordem | map({(.ordem|tostring):.n}) | add == {"40":2,"50":0}' <<<"$j" >/dev/null \
  && ok "seção 8: por ordem só 40 e 50 (ausente não vira linha com zero)" || bad "m8 por ordem"
jq -e '.metricas[8] | .status=="ok" and .n_com_dado==2 and .n_sem_dado==3 and .populacao==5
  and .n.antes=={populacao:2,n_com_dado:1,n_sem_dado:1} and .n.depois=={populacao:3,n_com_dado:1,n_sem_dado:2}
  and .total_tokens_antes==1000 and .total_tokens_depois==3000
  and .total_centavos_antes==250 and .total_centavos_depois==0
  and (.por_ordem | map(.ordem) | sort)==[40,50]' <<<"$j" >/dev/null \
  && ok "seção 9: ok, N declarado por lado, soma só das ordens com dado" || bad "m9: $(jq -c '.metricas[8]' <<<"$j")"
jq -e '[.metricas[8].por_ordem[] | select(.ordem==50) | .centavos] == [null]' <<<"$j" >/dev/null \
  && ok "seção 9: custo sem fonte fica null na ordem, nenhum zero no lugar de ausência" || bad "m9 null: $(jq -c '.metricas[8].por_ordem' <<<"$j")"
jq -e '[.. | numbers | select(. != floor)] | length==0' <<<"$j" >/dev/null && ok "nenhum float no painel" || bad "float no painel"

# população só de ordens antigas e ausente → "sem dado", exit 0, N declarado
rm -f "$MAESTRO_HOME"/evidence/*; rm -f "$P"/.maestro/orders/*; rm -f "$MAESTRO_HOME"/order-state/*
add 41 $((CORTE-4000)); add 52 $((CORTE+7000)) regravacoes=ausente tokens=ausente
run --project "$P" --format json
[[ $rc -eq 0 ]] && ok "só ordens sem dado: exit 0" || bad "rc=$rc err=$err"
jq -e '.metricas[7].recibos_regravados | .status=="sem dado" and .n_com_dado==0 and .n_sem_dado==2' <<<"$j" >/dev/null \
  && ok "seção 8: sem dado com N declarado (0 com dado, 2 sem)" || bad "m8 sem dado: $(jq -c '.metricas[7].recibos_regravados' <<<"$j")"
jq -e '.metricas[8] | .status=="sem dado" and .n_com_dado==0 and .n_sem_dado==2 and .populacao==2' <<<"$j" >/dev/null \
  && ok "seção 9: sem dado com N declarado, nunca zero" || bad "m9 sem dado: $(jq -c '.metricas[8]' <<<"$j")"

# campo presente e inválido → FALHA nomeada, exit 3
for bad_line in 'regravacoes=2.5' 'regravacoes=muitas'; do
  add 60 $((CORTE+8000)) "$bad_line"
  run --project "$P" --format json
  [[ $rc -eq 3 ]] && grep -q 'regravacoes' <<<"$err" && grep -q 'order-60' <<<"$err" \
    && jq -e '.metricas[7].recibos_regravados.status=="FALHA"' <<<"$j" >/dev/null \
    && ok "seção 8: '$bad_line' é FALHA nomeada, exit 3" || bad "m8 inválido ($bad_line): rc=$rc err=$err"
done
for bad_line in 'tokens=2.5' 'custo_centavos=1,5' 'tokens=lots'; do
  add 60 $((CORTE+8000)) "$bad_line"
  run --project "$P" --format json
  [[ $rc -eq 3 ]] && grep -qE 'tokens|custo_centavos' <<<"$err" && grep -q 'order-60' <<<"$err" \
    && jq -e '.metricas[8].status=="FALHA"' <<<"$j" >/dev/null \
    && ok "seção 9: '$bad_line' é FALHA nomeada, exit 3" || bad "m9 inválido ($bad_line): rc=$rc err=$err"
done

# ledger ilegível → FALHA
rm -rf "$MAESTRO_HOME/evidence"; printf 'x' > "$MAESTRO_HOME/evidence"
run --project "$P" --format json
[[ $rc -eq 3 ]] && jq -e '.metricas[8].status=="FALHA" and .metricas[7].recibos_regravados.status!="ok"' <<<"$j" >/dev/null \
  && ok "ledger ilegível: FALHA nas seções 8 e 9, exit 3" || bad "ledger ilegível: rc=$rc m9=$(jq -c '.metricas[8]' <<<"$j")"

exit $fail
