#!/usr/bin/env bash
# ordem 058 — tools/baseline.sh é SOMENTE LEITURA: sobre um repo de fixture, um ledger
# de fixture e um "runner" (ssh falso) nada muda — hash antes e depois iguais — e o
# único comando que chega ao runner é de leitura. Controle negativo: o detector de hash
# de fato enxerga uma escrita.
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
git -C "$P" init -q -b main
git -C "$P" config user.email t@t; git -C "$P" config user.name t
printf '<!-- maestro-order v1\nid: 001\nts: x\nepoch: 1700000000\n-->\n# o\n' > "$P/.maestro/orders/001-x.md"
git -C "$P" add -A; git -C "$P" commit -qm "ordem 001"
git -C "$P" checkout -q -b order/001-x
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm "feat"
git -C "$P" checkout -q main

KEY=$(source "$REPO/hooks/lib/project-state.sh"; b=$(maestro_brief_file "$P"); b="${b##*/}"; echo "${b%.md}")
printf 'schema=maestro-order-state-v1\nid=1\noutcome=aceita\naccepted_at=2023-11-14T20:00:00-03:00\n' > "$MAESTRO_HOME/order-state/$KEY-001"
printf 'schema=maestro-evidence-v1\nlabel=order-1\nepoch=1700001800\nexit=0\nregravacoes=0\ntokens=1\n' > "$MAESTRO_HOME/evidence/$KEY-order-1"
{ echo '{"ts":"2026-01-01T10:00:00-03:00","event":"decision","session_id":"s1","project":"proj"}'
  echo '{"ts":"2026-01-01T10:01:00-03:00","event":"gate_warn","tool":"Edit","session_id":"s1"}'
  echo '{"ts":"2026-01-01T10:02:00-03:00","event":"turno_teto","session_id":"s1","n":"1"}'
} > "$MAESTRO_HOME/logs/routing.jsonl"

# ssh falso: registra o comando e responde como um lab-ci; qualquer coisa fora da lista de leitura = veneno
cat > "$tmp/bin/ssh" <<'STUB'
#!/usr/bin/env bash
cmd="${*: -1}"
printf '%s\n' "$cmd" >> "$STUB_LOG"
printf ' 10:00:00 up 1 day,  3 users,  load average: 0,50, 0,40, 0,30\n8\n'
printf '               total       usada       livre    compart.  buff/cache  disponível\n'
printf 'Mem.:          16000        4000        8000         100        4000        8000\n'
printf 'actions.runner.x.service loaded active running GitHub Actions Runner\n---\n1\n'
STUB
# gh falso: só aceita "pr list" e "run list"; qualquer outra coisa = veneno (rc 9 e registro)
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list")  echo '[{"number":1,"mergedAt":"2026-01-01T10:10:00Z","headRefOid":"abc"}]' ;;
  "run list") echo '[{"headSha":"abc","updatedAt":"2026-01-01T10:00:00Z"}]' ;;
  *) exit 9 ;;
esac
STUB
chmod +x "$tmp/bin/ssh" "$tmp/bin/gh"
export STUB_LOG="$tmp/ssh.log" GH_LOG="$tmp/gh.log"; : > "$STUB_LOG"; : > "$GH_LOG"
export PATH="$tmp/bin:$PATH" MAESTRO_BASELINE_LAB_SSH="lab-fake"
export MAESTRO_BASELINE_REPOS="$tmp"   # o --all resolve a chave do ledger para $tmp/proj (063)

# banco da Ponte de fixture (aberto pelo painel só em modo read-only)
export MAESTRO_PONTE_DB="$tmp/home/ponte.db"
PN=$(basename "$P")
sqlite3 "$MAESTRO_PONTE_DB" "
  CREATE TABLE manager_run(run_id TEXT, project TEXT, order_ref TEXT, created_at TEXT, state TEXT);
  CREATE TABLE decision(kind TEXT, project TEXT, order_ref TEXT, tool_name TEXT, created_at TEXT, origin TEXT);
  CREATE TABLE manager_event(event_id TEXT, type TEXT, project TEXT, order_ref TEXT, run_id TEXT, created_at TEXT);
  CREATE TABLE director_inbox(seq INTEGER, created_at TEXT, ref_kind TEXT, ref_id TEXT, state TEXT);
  INSERT INTO manager_run(run_id,project,order_ref,created_at) VALUES('r1','$PN','order/001-x','2026-01-01T00:00:00Z'),('r2','$PN','order/001-x','2026-01-02T00:00:00Z');
  INSERT INTO decision(kind,project,order_ref,tool_name,created_at) VALUES('permission','$PN','order/001-x','Bash','2026-01-01T01:00:00Z'),
    ('permission','$PN','order/001-x','Bash','2026-01-01T02:00:00Z'),('permission','$PN','order/001-x','Edit','2026-01-02T01:00:00Z'),
    ('question','$PN','order/001-x',NULL,'2026-01-02T01:00:00Z');"

snap() { # hash de tudo que não pode mudar: repo (com .git), ledger, runner
  ( cd "$tmp" && find proj home bin -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64 )
}

before=$(snap)
j=$(bash "$TOOL" --project "$P" --format json 2>/dev/null); rc1=$?
m=$(bash "$TOOL" --project "$P" --format md 2>/dev/null);   rc2=$?
a=$(bash "$TOOL" --all --format json 2>/dev/null);          rc3=$?
w=$(bash "$TOOL" --project "$P" --format json --since 1 --next 10 2>/dev/null); rc4=$?
after=$(snap)

[[ $rc1 -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 && $rc4 -eq 0 ]] && ok "as quatro execuções saem 0" || bad "rc: $rc1 $rc2 $rc3 $rc4"
[[ "$before" == "$after" ]] && ok "hash do repo, do ledger e do runner igual antes e depois" || bad "algo mudou (hash difere)"
jq -e '.metricas|length==9' <<<"$j" >/dev/null && ok "nove métricas" || bad "esperava 9 métricas"
jq -e '.metricas[0].ordens[0].parada_em_pronta_s==1000' <<<"$j" >/dev/null \
  && ok "métrica 1 calculada do ledger (aceita - provada = 1000)" || bad "métrica 1 errada: $(jq -c '.metricas[0]' <<<"$j")"
jq -e '.metricas[4].load1m_x100==50 and .metricas[4].ncpu==8' <<<"$j" >/dev/null && ok "métrica 5 lida do runner" || bad "métrica 5 errada"
jq -e '.metricas[3].turnos==1 and .metricas[3].permissoes==1' <<<"$j" >/dev/null && ok "métrica 4 do routing.jsonl" || bad "métrica 4 errada"
[[ -n "$m" ]] && grep -q '^## 6\.' <<<"$m" && ok "saída markdown tem as seis seções" || bad "markdown sem a seção 6"
jq -e '.selecao|test("1 encontrado")' <<<"$w" >/dev/null && ok "--since/--next seleciona os aceites" || bad "janela de aceites errada"

# o runner só recebe comandos de leitura
fora=$(tr ';|' '\n\n' < "$STUB_LOG" | sed 's/^ *//;s/ *$//' | grep -Ev '^(uptime|nproc|free -m|systemctl list-units --no-legend --type=service|grep -i runner|echo ---|pgrep -fc "\[R\]unner.Worker"|true)?$')
if [[ -s "$STUB_LOG" && -z "$fora" ]] && ! grep -Eq 'sudo|>|systemctl (start|stop|restart|enable|disable|kill)' "$STUB_LOG"; then
  ok "ssh só com a lista fechada de leitura"; else bad "comando fora da lista no runner: $fora"; fi

# decisão 1: sem MAESTRO_BASELINE_LAB_SSH o host é lab-ci
: > "$STUB_LOG"; env -u MAESTRO_BASELINE_LAB_SSH bash "$TOOL" --project "$P" --format json >/dev/null 2>&1
grep -q . "$STUB_LOG" && ok "host padrão lab-ci (ssh invocado sem a variável)" || bad "ssh não invocado sem a variável"

# decisão 2: gh só "pr list" e "run list"
[[ -s "$GH_LOG" ]] && ! grep -Evq '^(pr list|run list) ' "$GH_LOG" && ok "gh só com pr list e run list" || bad "gh fora da lista: $(cat "$GH_LOG")"
jq -e '.metricas[1].status=="ok" and .metricas[1].mediana_s==600' <<<"$j" >/dev/null && ok "métrica 2: CI verde→merge = 600 s" || bad "métrica 2 errada: $(jq -c '.metricas[1]' <<<"$j")"

# decisão 3: permissões da Ponte por run e por projeto
jq -e '.metricas[3].ponte.status=="ok" and (.metricas[3].ponte.permissoes_por_run|map({(.run):.n})|add)=={"r1":2,"r2":1}
       and .metricas[3].ponte.permissoes_por_projeto[0].n==3 and (.metricas[3].ponte.quais[0]|.alvo=="Bash" and .n==2)' <<<"$j" >/dev/null \
  && ok "métrica 4: permissões da Ponte por run (2,1), por projeto (3) e quais" || bad "métrica 4 Ponte errada: $(jq -c '.metricas[3].ponte' <<<"$j")"

# decisão 4: ordem legada (id<=32) sem carimbo fica numa linha própria, fora da mediana
jq -e '.metricas[0].legadas_sem_carimbo=={quantidade:0,ids:[]} and .metricas[0].mediana_parada_em_pronta_s==1000' <<<"$j" >/dev/null \
  && ok "legadas: nenhuma na fixture, mediana só das com carimbo" || bad "legadas/mediana: $(jq -c '.metricas[0]|{legadas_sem_carimbo,mediana_parada_em_pronta_s}' <<<"$j")"
printf 'schema=maestro-evidence-v1\nlabel=order-2\nepoch=1700000000\nexit=0\n' > "$MAESTRO_HOME/evidence/$KEY-order-2"
printf '<!-- maestro-order v1\nid: 002\nts: x\nepoch: 1690000000\n-->\n# o\n' > "$P/.maestro/orders/002-y.md"
j3=$(bash "$TOOL" --project "$P" --format json 2>/dev/null)
jq -e '.metricas[0].legadas_sem_carimbo=={quantidade:1,ids:[2]} and .metricas[0].mediana_parada_em_pronta_s==1000 and .metricas[0].mediana_n==1' <<<"$j3" >/dev/null \
  && ok "legada 002 sem carimbo: listada à parte e fora da mediana" || bad "legada vazou na mediana: $(jq -c '.metricas[0]|{legadas_sem_carimbo,mediana_parada_em_pronta_s,mediana_n}' <<<"$j3")"
rm -f "$MAESTRO_HOME/evidence/$KEY-order-2" "$P/.maestro/orders/002-y.md"

# controle negativo: o detector enxerga uma escrita
echo x >> "$P/a"
[[ "$(snap)" != "$before" ]] && ok "controle negativo: o hash detecta escrita" || bad "o detector de hash é cego"

exit $fail
