#!/usr/bin/env bash
# ordem 063 itens 4 e 5 — permissões por janela e as três medidas novas do painel:
#   7. ações do Capitão  = decisões origin 'spock' (ponte.db) + commits em caminhos protegidos (git);
#   8. retrabalho        = turnos devolvidos, turnos encerrados sem relato (ponte.db) e recibos
#                          regravados no mesmo rótulo (campo `regravacoes` do recibo, ledger);
#   9. custo por ordem   = inteiros (campo `tokens` ou `custo_centavos` do recibo, ledger).
# Fonte que falta é FALHA nomeada (exit 3), nunca zero nem estimativa; nenhuma saída fala em tempo
# do Capitão.
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
export PATH="$tmp/bin:$PATH" MAESTRO_BASELINE_LAB_SSH=lab-fake
export MAESTRO_PONTE_DB="$tmp/ponte.db"

CORTE=1791083700
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# --- git: commits em caminhos protegidos e fora deles, antes e depois do corte
git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
commit() { # <epoch> <caminho> <mensagem>
  mkdir -p "$P/$(dirname "$2")"; echo "$3" >> "$P/$2"; git -C "$P" add -A
  GIT_AUTHOR_DATE="@$1 +0000" GIT_COMMITTER_DATE="@$1 +0000" git -C "$P" commit -qm "$3"
}
commit $((CORTE-9000)) a.txt "base"
commit $((CORTE-8000)) hooks/h.sh "feat(040): hook"
commit $((CORTE-7000)) lib/x.sh "fix(041): lib"
commit $((CORTE-6000)) docs/d.md "docs(041): fora dos caminhos protegidos"
commit $((CORTE+1000)) src/z.ts "feat(050): src"
commit $((CORTE+2000)) bin/b "chore: bin sem ordem"

# --- ledger: três ordens com carimbo (40 e 41 antes; 50 depois), recibo com regravacoes e tokens
KEY=$(source "$REPO/hooks/lib/project-state.sh"; b=$(maestro_brief_file "$P"); b="${b##*/}"; echo "${b%.md}")
add() { # <id> <aceita-epoch> <regravacoes|-> <tokens|->
  local id="$1" s3; s3=$(printf '%03d' "$1")
  printf '<!-- maestro-order v1\nid: %s\nts: x\nepoch: 1790000000\n-->\n# o\n' "$s3" > "$P/.maestro/orders/$s3-x.md"
  printf 'schema=maestro-order-state-v1\nid=%s\noutcome=aceita\naccepted_at=%s\n' "$id" "$(date -d "@$2" +%Y-%m-%dT%H:%M:%S%z)" > "$MAESTRO_HOME/order-state/$KEY-$s3"
  { printf 'schema=maestro-evidence-v1\nlabel=order-%s\nepoch=%s\nexit=0\n' "$id" "$(($2-100))"
    [[ "$3" == - ]] || printf 'regravacoes=%s\n' "$3"
    [[ "$4" == - ]] || printf 'tokens=%s\n' "$4"; } > "$MAESTRO_HOME/evidence/$KEY-order-$id"
}
add 40 $((CORTE-5000)) 1 1000; add 41 $((CORTE-4000)) 0 2000; add 50 $((CORTE+5000)) 2 3000

# --- ponte.db de fixture
mkponte() { # [sem-origin]
  rm -f "$MAESTRO_PONTE_DB"
  local orig="origin TEXT,"; [[ "${1:-}" == sem-origin ]] && orig=""
  sqlite3 "$MAESTRO_PONTE_DB" "
  CREATE TABLE manager_run(run_id TEXT, project TEXT, order_ref TEXT, state TEXT, created_at TEXT);
  CREATE TABLE decision(id TEXT, kind TEXT, $orig project TEXT, order_ref TEXT, tool_name TEXT, created_at TEXT);
  CREATE TABLE manager_event(event_id TEXT, type TEXT, project TEXT, order_ref TEXT, run_id TEXT, created_at TEXT);
  CREATE TABLE director_inbox(seq INTEGER, created_at TEXT, ref_kind TEXT, ref_id TEXT, state TEXT);"
  local c="id,kind,${orig:+origin,}project,order_ref,created_at" o="${orig:+'spock',}"
  # decisões do Capitão (spock): 2 antes (uma da ordem 40, uma sem ordem), 1 depois (ordem 50)
  sqlite3 "$MAESTRO_PONTE_DB" "
  INSERT INTO decision($c) VALUES ('d1','question',${o}'proj','order/040-x','$(iso $((CORTE-5000)))');
  INSERT INTO decision($c) VALUES ('d2','question',${o}'proj',NULL,'$(iso $((CORTE-3000)))');
  INSERT INTO decision($c) VALUES ('d3','question',${o}'proj','order/050-x','$(iso $((CORTE+3000)))');
  INSERT INTO decision($c) VALUES ('d4','question',${o}'outro','order/001-x','$(iso $((CORTE+3000)))');"
  [[ -n "$orig" ]] && sqlite3 "$MAESTRO_PONTE_DB" "
  INSERT INTO decision(id,kind,origin,project,order_ref,tool_name,created_at) VALUES ('d5','permission','gerente','proj','order/050-x','Bash','$(iso $((CORTE+5500)))');
  INSERT INTO decision(id,kind,origin,project,order_ref,tool_name,created_at) VALUES ('d6','permission','gerente','proj','order/040-x','Edit','$(iso $((CORTE-4900)))');"
  sqlite3 "$MAESTRO_PONTE_DB" "
  INSERT INTO manager_run VALUES ('r1','proj','order/040-x','failed','$(iso $((CORTE-5000)))');
  INSERT INTO manager_run VALUES ('r2','proj','order/041-x','cancelled','$(iso $((CORTE-4000)))');
  INSERT INTO manager_run VALUES ('r3','proj','order/050-x','teto','$(iso $((CORTE+4000)))');
  INSERT INTO manager_run VALUES ('r4','proj','order/050-x','accepted','$(iso $((CORTE+5000)))');
  INSERT INTO manager_run VALUES ('r5','proj','order/051-x','working','$(iso $((CORTE+6000)))');
  INSERT INTO manager_event VALUES ('e1','manager.review_requested','proj','order/041-x','r2','$(iso $((CORTE-3900)))');
  INSERT INTO manager_event VALUES ('e2','manager.review_requested','proj','order/050-x','r4','$(iso $((CORTE+5000)))');
  INSERT INTO director_inbox VALUES (1,'$(iso $((CORTE-5000)))','order','order/040-x','returned');
  INSERT INTO director_inbox VALUES (2,'$(iso $((CORTE-4000)))','run','r2','returned');
  INSERT INTO director_inbox VALUES (3,'$(iso $((CORTE+4000)))','order','order/050-x','returned');
  INSERT INTO director_inbox VALUES (4,'$(iso $((CORTE+4500)))','order','order/050-x','done');"
}
mkponte

run() { err=$(bash "$TOOL" "$@" 2>&1 >"$tmp/out"); rc=$?; j=$(<"$tmp/out"); }

run --project "$P" --format json
[[ $rc -eq 0 ]] && ok "fontes presentes: exit 0" || bad "rc=$rc err=$err"
jq -e '.metricas|length==9 and ([.[].id]==[1,2,3,4,5,6,7,8,9])' <<<"$j" >/dev/null && ok "nove métricas (seis + três novas)" || bad "métricas: $(jq -c '[.metricas[]|{id,status}]' <<<"$j")"

# 7. ações do Capitão
jq -e '.metricas[6] | .status=="ok"
  and .antes=={ponte:2, git:2, total:4} and .depois=={ponte:1, git:2, total:3}' <<<"$j" >/dev/null \
  && ok "ações do Capitão: antes 2+2=4, depois 1+2=3 (decisões spock + commits em caminhos protegidos)" || bad "m7: $(jq -c '.metricas[6]' <<<"$j")"
jq -e '.metricas[6].por_ordem | (map({(.ordem|tostring):.total})|add)=={"40":2,"41":1,"50":2} and (map(select(.ordem==40))[0]|.ponte==1 and .git==1)' <<<"$j" >/dev/null \
  && ok "ações do Capitão por ordem quando atribuível (40, 41, 50)" || bad "m7 por ordem: $(jq -c '.metricas[6].por_ordem' <<<"$j")"
jq -e '.metricas[6].sem_ordem=={ponte:1, git:1}' <<<"$j" >/dev/null && ok "ações sem ordem atribuível contadas à parte" || bad "m7 sem ordem: $(jq -c '.metricas[6].sem_ordem' <<<"$j")"

# 8. retrabalho
jq -e '.metricas[7] | .status=="ok"
  and .turnos_devolvidos.antes==2 and .turnos_devolvidos.depois==1
  and .turnos_sem_relato.antes==1 and .turnos_sem_relato.depois==1
  and .recibos_regravados.antes==1 and .recibos_regravados.depois==2' <<<"$j" >/dev/null \
  && ok "retrabalho: devolvidos 2/1, sem relato 1/1, regravados 1/2" || bad "m8: $(jq -c '.metricas[7]' <<<"$j")"

# 9. custo por ordem, inteiros
jq -e '.metricas[8] | .status=="ok" and (.por_ordem|map({(.ordem|tostring):.tokens})|add)=={"40":1000,"41":2000,"50":3000}
  and .total_tokens_antes==3000 and .total_tokens_depois==3000' <<<"$j" >/dev/null \
  && ok "custo por ordem em inteiros (tokens)" || bad "m9: $(jq -c '.metricas[8]' <<<"$j")"
jq -e '[.. | numbers | select(. != floor)] | length==0' <<<"$j" >/dev/null && ok "nenhum float no painel" || bad "float no painel"

# permissões por janela (item 4)
jq -e '.metricas[3].ponte.permissoes_por_run | all(.[]; has("lado")) ' <<<"$j" >/dev/null \
  && ok "permissões por run trazem o lado da janela" || bad "m4 sem lado: $(jq -c '.metricas[3].ponte' <<<"$j")"
jq -e '.metricas[3].ponte.permissoes_por_projeto | all(.[]; has("lado")) and length>=1' <<<"$j" >/dev/null \
  && ok "permissões por projeto cortadas por lado" || bad "m4 por projeto"

jq -e '(.metricas[3].ponte.permissoes_por_projeto | map({(.lado):.n}) | add)=={"antes":1,"depois":1}
  and (.metricas[3].ponte.permissoes_por_run | map(select(.n>0) | {(.run):.lado}) | add)=={"r1":"antes","r4":"depois"}' <<<"$j" >/dev/null \
  && ok "permissões: 1 antes (r1) e 1 depois (r4) da v59" || bad "m4 janela: $(jq -c '.metricas[3].ponte' <<<"$j")"

# sem a palavra "minutos" (e sem tempo estimado) para o Capitão
m=$(bash "$TOOL" --project "$P" --format md 2>/dev/null)
if grep -qi 'minuto' <<<"$m$j"; then bad "a saída fala em minutos"; else ok "nenhuma saída contém 'minutos'"; fi

# --- fonte que falta é FALHA nomeada, exit 3
add 41 $((CORTE-4000)) - 2000            # recibo sem o campo regravacoes
run --project "$P" --format json
[[ $rc -eq 3 ]] && grep -q 'regravacoes' <<<"$err" && grep -q 'order-41' <<<"$err" \
  && jq -e '.metricas[7].status=="FALHA" and .metricas[7].recibos_regravados.status=="FALHA" and .metricas[7].turnos_devolvidos.antes==2' <<<"$j" >/dev/null \
  && ok "regravacoes ausente: FALHA nomeada (recibo e campo), exit 3, as outras contagens preservadas" || bad "regravacoes: rc=$rc err=$err m8=$(jq -c '.metricas[7]' <<<"$j")"
add 41 $((CORTE-4000)) 0 -               # recibo sem custo
run --project "$P" --format json
[[ $rc -eq 3 ]] && grep -qE 'tokens|custo_centavos' <<<"$err" && jq -e '.metricas[8].status=="FALHA" and (.metricas[8].falhas[0].motivo|test("41"))' <<<"$j" >/dev/null \
  && ok "custo ausente: FALHA nomeada, exit 3 (não zero, não estimado)" || bad "custo: rc=$rc err=$err m9=$(jq -c '.metricas[8]' <<<"$j")"
add 41 $((CORTE-4000)) 0 2.5             # float não é inteiro: recusado
run --project "$P" --format json
[[ $rc -eq 3 ]] && jq -e '.metricas[8].status=="FALHA"' <<<"$j" >/dev/null && ok "custo não inteiro (float) é FALHA, nunca aceito" || bad "float aceito: rc=$rc"
add 41 $((CORTE-4000)) 0 2000

# ponte.db sem a coluna origin: FALHA nomeada (arquivo/tabela/coluna), sem escrever no banco
mkponte sem-origin
run --project "$P" --format json
[[ $rc -eq 3 ]] && grep -q 'origin' <<<"$err" && grep -q 'ponte.db' <<<"$err" && jq -e '.metricas[6].status=="FALHA"' <<<"$j" >/dev/null \
  && ok "ponte.db sem decision.origin: FALHA nomeada, exit 3" || bad "sem origin: rc=$rc err=$err"
mkponte

# git ilegível: a parte git das ações do Capitão é FALHA
mv "$P/.git" "$tmp/git.off"
run --project "$P" --format json
[[ $rc -eq 3 ]] && jq -e '.metricas[6].status=="FALHA"' <<<"$j" >/dev/null && ok "git ilegível: ações do Capitão FALHA, exit 3" || bad "git off: rc=$rc"
mv "$tmp/git.off" "$P/.git"

# população vazia com fontes presentes: sem dado, exit 0 (não FALHA)
rm -f "$MAESTRO_HOME"/order-state/* "$MAESTRO_HOME"/evidence/*
run --project "$P" --format json
[[ $rc -eq 0 ]] && jq -e '.metricas[8].status=="sem dado" and .metricas[7].recibos_regravados.status=="sem dado"' <<<"$j" >/dev/null \
  && ok "sem ordens na população: custo e regravados 'sem dado', exit 0" || bad "vazio: rc=$rc err=$err m9=$(jq -c '.metricas[8]' <<<"$j")"

exit $fail
