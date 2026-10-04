#!/usr/bin/env bash
# ordem 063 item 1 — janela e população iguais nos dois lados do corte da v59
# (2026-10-04T00:15:00-03:00 = epoch 1791083700). A MESMA regra de população vale
# antes e depois: carimbo de aceite válido, sem as legadas (ids 1..32 sem carimbo).
# O painel imprime a regra e o N de cada lado; com N pequeno (<3) não compara.
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
git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm base
# ssh e gh que funcionam (a fonte existe; o foco aqui é a população)
printf '#!/usr/bin/env bash\nprintf " 10:00:00 up 1 day, load average: 0,50, 0,40, 0,30\\n8\\n"\nprintf "total used free shared buff avail\\nMem.: 16000 4000 8000 100 4000 8000\\n"\nprintf "actions.runner.x.service loaded active running Runner\\n---\\n1\\n"\n' > "$tmp/bin/ssh"
printf '#!/usr/bin/env bash\ncase "$1 $2" in "pr list") echo "[]";; "run list") echo "[]";; *) exit 9;; esac\n' > "$tmp/bin/gh"
chmod +x "$tmp/bin/ssh" "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MAESTRO_BASELINE_LAB_SSH=lab-fake
export MAESTRO_PONTE_DB="$tmp/ponte.db"
sqlite3 "$MAESTRO_PONTE_DB" "CREATE TABLE manager_run(run_id TEXT, project TEXT, order_ref TEXT, created_at TEXT);
  CREATE TABLE decision(kind TEXT, project TEXT, order_ref TEXT, tool_name TEXT, created_at TEXT);"
: > "$MAESTRO_HOME/logs/routing.jsonl"

KEY=$(source "$REPO/hooks/lib/project-state.sh"; b=$(maestro_brief_file "$P"); b="${b##*/}"; echo "${b%.md}")
CORTE=1791083700
# add <id> <aceita-epoch|-> <provada-epoch>: ordem com carimbo (ou sem) e recibo
add() {
  local id="$1" ac="$2" pr="$3" s3; s3=$(printf '%03d' "$1")
  printf '<!-- maestro-order v1\nid: %s\nts: x\nepoch: 1790000000\n-->\n# o\n' "$s3" > "$P/.maestro/orders/$s3-x.md"
  if [[ "$ac" != - ]]; then
    printf 'schema=maestro-order-state-v1\nid=%s\noutcome=aceita\naccepted_at=%s\n' "$id" "$(date -d "@$ac" +%Y-%m-%dT%H:%M:%S%z)" > "$MAESTRO_HOME/order-state/$KEY-$s3"
  fi
  printf 'schema=maestro-evidence-v1\nlabel=order-%s\nepoch=%s\nexit=0\n' "$id" "$pr" > "$MAESTRO_HOME/evidence/$KEY-order-$id"
}
# antes do corte: 40, 41, 42 (paradas 100, 200, 300); depois: 50, 51, 52 (paradas 1000, 2000, 3000)
add 40 $((CORTE-5000)) $((CORTE-5100)); add 41 $((CORTE-4000)) $((CORTE-4200)); add 42 $((CORTE-3000)) $((CORTE-3300))
add 50 $((CORTE+5000)) $((CORTE+4000)); add 51 $((CORTE+6000)) $((CORTE+4000)); add 52 $((CORTE+7000)) $((CORTE+4000))
# legada (id<=32 sem carimbo) e ordem >32 sem carimbo: fora da população dos DOIS lados
add 7 - $((CORTE-100)); add 60 - $((CORTE+100))

j=$(bash "$TOOL" --project "$P" --format json 2>/dev/null)
jq -e '.metricas[0].janela.corte_epoch==1791083700' <<<"$j" >/dev/null && ok "corte da v59 (epoch 1791083700)" || bad "corte: $(jq -c '.metricas[0].janela' <<<"$j")"
jq -e '.metricas[0].janela.antes.n==3 and .metricas[0].janela.depois.n==3' <<<"$j" >/dev/null && ok "N de cada lado: 3 e 3" || bad "N dos lados: $(jq -c '.metricas[0].janela' <<<"$j")"
jq -e '.metricas[0].janela.antes.ids==[40,41,42] and .metricas[0].janela.depois.ids==[50,51,52]' <<<"$j" >/dev/null && ok "ordens de cada lado pela data do aceite" || bad "ids dos lados"
jq -e '.metricas[0].janela.antes.mediana_parada_em_pronta_s==200 and .metricas[0].janela.depois.mediana_parada_em_pronta_s==2000' <<<"$j" >/dev/null \
  && ok "mediana de cada lado sobre a mesma regra (200 e 2000)" || bad "medianas: $(jq -c '.metricas[0].janela' <<<"$j")"
jq -e '(.metricas[0].janela.regra|test("carimbo de aceite")) and (.metricas[0].janela.regra|test("legadas"))' <<<"$j" >/dev/null \
  && ok "a regra de população está escrita no painel" || bad "sem a regra de população"
jq -e '[.metricas[0].ordens[]|select(.id==7 or .id==60)|.lado]==["fora","fora"]' <<<"$j" >/dev/null && ok "legada e sem carimbo ficam fora dos dois lados" || bad "legada/sem carimbo entrou num lado"
jq -e '.metricas[0].janela.antes.ids|index(7)|not' <<<"$j" >/dev/null && ok "legada fora da mediana" || bad "legada na mediana"
jq -e '.metricas[0].janela.comparacao|test("^comparado")' <<<"$j" >/dev/null && ok "com N>=3 nos dois lados, compara" || bad "comparação: $(jq -c '.metricas[0].janela.comparacao' <<<"$j")"

m=$(bash "$TOOL" --project "$P" --format md 2>/dev/null)
grep -q 'regra de população' <<<"$m" && grep -q 'N antes: 3' <<<"$m" && grep -q 'N depois: 3' <<<"$m" \
  && ok "markdown imprime a regra e o N de cada lado" || bad "markdown sem regra/N"

# N pequeno num lado: o painel avisa e NÃO compara
rm -f "$MAESTRO_HOME/order-state/$KEY-052" "$MAESTRO_HOME/order-state/$KEY-051"
j2=$(bash "$TOOL" --project "$P" --format json 2>/dev/null)
jq -e '.metricas[0].janela.depois.n==1 and .metricas[0].janela.depois.n_pequeno==true and (.metricas[0].janela.comparacao|test("^não comparado"))' <<<"$j2" >/dev/null \
  && ok "N pequeno: diz que é pequeno e não compara" || bad "N pequeno: $(jq -c '.metricas[0].janela' <<<"$j2")"

# borda: aceite exatamente no corte pertence ao "antes" (depois = estritamente depois da v59)
add 43 "$CORTE" $((CORTE-10))
j3=$(bash "$TOOL" --project "$P" --format json 2>/dev/null)
jq -e '.metricas[0].janela.antes.ids|index(43)!=null' <<<"$j3" >/dev/null && ok "aceite no instante do corte fica no antes" || bad "borda do corte"

exit $fail
