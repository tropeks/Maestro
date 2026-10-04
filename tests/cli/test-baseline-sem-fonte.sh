#!/usr/bin/env bash
# ordem 058 — regra de honestidade: métrica sem fonte aparece como "sem fonte", SEM número.
# Fixture vazia (sem ledger, sem routing.jsonl, sem lab-ci) → nada a medir. Controle:
# com a fonte presente o mesmo campo vira número.
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

j=$(bash "$TOOL" --project "$P" --format json 2>/dev/null)
jq -e '.metricas|length==6' <<<"$j" >/dev/null && ok "seis métricas presentes" || bad "esperava 6 métricas"

for i in 0 1 3 4; do # 1, 2 (gh falhou), 4 (sem routing nem Ponte), 5 (ssh falhou)
  jq -e ".metricas[$i].status==\"sem fonte\"" <<<"$j" >/dev/null && ok "métrica $((i+1)): status sem fonte" \
    || bad "métrica $((i+1)) deveria ser sem fonte: $(jq -c ".metricas[$i]" <<<"$j")"
done
# métricas 2 e 5 (CI e lab-ci) e 6 (timeouts de teste/runner) sem fonte por construção
jq -e '.metricas[1].status=="sem fonte" and .metricas[1].valor=="sem fonte"' <<<"$j" >/dev/null && ok "métrica 2 sem fonte, sem número" || bad "métrica 2"
jq -e '.metricas[5].teste=="sem fonte" and .metricas[5].runner=="sem fonte"' <<<"$j" >/dev/null && ok "métrica 6: teste e runner sem fonte" || bad "métrica 6"

# nenhum número em métrica sem fonte: só id e texto
nnum=$(jq '[.metricas[] | select(.status=="sem fonte") | del(.id) | .. | numbers] | length' <<<"$j")
[[ "$nnum" -eq 0 ]] && ok "nenhum número em métrica sem fonte" || bad "número vazou em métrica sem fonte ($nnum)"

m=$(bash "$TOOL" --project "$P" --format md 2>/dev/null)
grep -q '^## Métricas sem fonte' <<<"$m" && grep -q '1\. idade por estado' <<<"$m" \
  && ok "o relatório lista as métricas sem fonte" || bad "relatório sem a seção de sem fonte"

# controle: a mesma métrica 4 com fonte vira número
printf '%s\n' '{"ts":"2026-01-01T10:00:00-03:00","event":"decision","session_id":"s","project":"proj"}' > /dev/null
mkdir -p "$MAESTRO_HOME/logs"
{ echo '{"ts":"2026-01-01T10:00:00-03:00","event":"decision","session_id":"s","project":"proj"}'
  echo '{"ts":"2026-01-01T10:01:00-03:00","event":"gate_block","cmd":"rm_recursive","session_id":"s"}'; } > "$MAESTRO_HOME/logs/routing.jsonl"
j2=$(bash "$TOOL" --project "$P" --format json 2>/dev/null)
jq -e '.metricas[3].status=="ok" and (.metricas[3].permissoes|type)=="number"' <<<"$j2" >/dev/null \
  && ok "controle: com fonte, a métrica 4 vira número" || bad "controle negativo falhou: $(jq -c '.metricas[3]' <<<"$j2")"

exit $fail
