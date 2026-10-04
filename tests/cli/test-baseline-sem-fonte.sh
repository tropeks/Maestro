#!/usr/bin/env bash
# ordens 058 e 063 — regra de honestidade: fonte esperada que some NUNCA vira número nem
# "sem fonte" calado: a métrica vira FALHA (fonte e motivo, exit 3), sem número estimado.
# Fixture vazia (sem ledger, sem routing.jsonl, sem Ponte, gh e ssh falhando). Controle:
# com a fonte presente o mesmo campo vira número. (Janela vazia = "sem dado": test-baseline-falha-alta.)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/baseline.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"
unset MAESTRO_BASELINE_LAB_SSH
# ssh, gh e banco da Ponte indisponíveis: fontes externas falham, nunca estimadas
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nexit 255\n' > "$tmp/bin/ssh"; cp "$tmp/bin/ssh" "$tmp/bin/gh"; chmod +x "$tmp/bin/ssh" "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MAESTRO_PONTE_DB="$tmp/nao-existe.db"
P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm base

j=$(bash "$TOOL" --project "$P" --format json 2>/dev/null); rc=$?
[[ $rc -eq 3 ]] && ok "fontes esperadas ausentes: exit 3" || bad "esperava exit 3, veio $rc"
jq -e '.metricas|length==9' <<<"$j" >/dev/null && ok "nove métricas presentes" || bad "esperava 9 métricas"

for i in 0 1 3 4 5 6 7 8; do # 1 (ledger), 2 (gh), 4 (routing e Ponte), 5 (ssh), 6 (routing), 7 a 9 (Ponte, git, ledger)
  jq -e ".metricas[$i].status==\"FALHA\" and (.metricas[$i].falhas|length)>0" <<<"$j" >/dev/null && ok "métrica $((i+1)): FALHA com fonte e motivo" \
    || bad "métrica $((i+1)) deveria ser FALHA: $(jq -c ".metricas[$i]" <<<"$j")"
done
jq -e '.metricas[5].teste=="sem fonte" or .metricas[5].status=="FALHA"' <<<"$j" >/dev/null && ok "métrica 6: sem número estimado" || bad "métrica 6"

# nenhum número em métrica FALHA: só id e texto
nnum=$(jq '[.metricas[] | select(.status=="FALHA") | del(.id) | .. | numbers] | length' <<<"$j")
[[ "$nnum" -eq 0 ]] && ok "nenhum número em métrica FALHA" || bad "número vazou em métrica FALHA ($nnum)"

m=$(bash "$TOOL" --project "$P" --format md 2>/dev/null)
grep -q '^## Falhas' <<<"$m" && grep -q '1\. idade por estado' <<<"$m" \
  && ok "o relatório lista as falhas" || bad "relatório sem a seção de falhas"

# controle: a mesma métrica 4 com fonte (routing e Ponte presentes) vira número
mkdir -p "$MAESTRO_HOME/logs"
{ echo '{"ts":"2026-01-01T10:00:00-03:00","event":"decision","session_id":"s","project":"proj"}'
  echo '{"ts":"2026-01-01T10:01:00-03:00","event":"gate_block","cmd":"rm_recursive","session_id":"s"}'; } > "$MAESTRO_HOME/logs/routing.jsonl"
sqlite3 "$MAESTRO_PONTE_DB" "CREATE TABLE manager_run(run_id TEXT, project TEXT, order_ref TEXT, created_at TEXT);
  CREATE TABLE decision(kind TEXT, project TEXT, order_ref TEXT, tool_name TEXT, created_at TEXT);"
j2=$(bash "$TOOL" --project "$P" --format json 2>/dev/null)
jq -e '.metricas[3].status=="ok" and (.metricas[3].permissoes|type)=="number"' <<<"$j2" >/dev/null \
  && ok "controle: com fonte, a métrica 4 vira número" || bad "controle negativo falhou: $(jq -c '.metricas[3]' <<<"$j2")"

exit $fail
