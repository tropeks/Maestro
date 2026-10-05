#!/usr/bin/env bash
# tools/baseline.sh — painel de linha de base da fábrica (ordem 058, Etapa 0 do plano v2;
# ordem 063: mesma população nos dois lados do corte da v59 e falha alta).
# SOMENTE LEITURA: lê o ledger (~/.maestro), o git do repo, o routing.jsonl e, por ssh
# com comandos de leitura, o lab-ci. Escreve apenas em stdout, stderr ou no --out indicado.
#
# Três estados por métrica, nunca misturados:
#   ok        há dado na janela.
#   sem dado  a fonte existe e não tem registro na janela (legítimo; exit 0).
#   FALHA     a fonte esperada não existe, não abre ou estourou o timeout: a fonte e o motivo
#             vão a stderr, o painel parcial ainda sai e o exit é 3 (o 2 é uso inválido).
# Nunca se estima. Campo sem fonte POR CONSTRUÇÃO dentro de uma métrica ok segue "sem fonte".
# Métricas: 1 idade/parada em pronta · 2 CI→merge · 3 rebases · 4 permissões (por janela) · 5 lab-ci ·
#   6 timeouts · 7 ações do Capitão · 8 retrabalho · 9 custo por ordem (7 a 9: lib/baseline-novas.sh;
#   contagens e inteiros, nunca tempo do Capitão). 8 (recibos regravados) e 9 leem os campos que o
#   `maestro evidence --record` grava (ordem 067): ausente/inexistente = "sem dado" com N declarado, não FALHA.
#
# Uso: tools/baseline.sh --project <dir> [--format md|json] [--out ARQ]
#                        [--since EPOCH --next N]   # só os N próximos aceites após EPOCH
#      tools/baseline.sh --all [--format ...]       # carteira (chaves do ledger → repos)
# Ambiente: MAESTRO_HOME (ledger), MAESTRO_BASELINE_LAB_SSH (host do lab-ci; padrão lab-ci),
#           MAESTRO_BASELINE_SSH_TIMEOUT (s, padrão 15), MAESTRO_BASELINE_NOW (epoch fixo, p/ teste),
#           MAESTRO_BASELINE_REPOS (raízes de busca dos repos no --all, separadas por ":"; padrão
#           ~/dev), MAESTRO_BASELINE_CORTE (epoch do corte; padrão a v59, 1791083700).
set -u
SF='sem fonte'
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=../hooks/lib/project-state.sh
source "$REPO_ROOT/hooks/lib/project-state.sh"
HOME_M="${MAESTRO_HOME:-$HOME/.maestro}"
NOW="${MAESTRO_BASELINE_NOW:-$(date +%s)}"
CORTE="${MAESTRO_BASELINE_CORTE:-1791083700}"   # v59: 2026-10-04T00:15:00-03:00
REGRA="ordens com carimbo de aceite válido, por projeto, sem as legadas (ids 1 a 32 sem carimbo); a mesma regra vale antes e depois do corte; lado = data do aceite (antes: até o corte; depois: estritamente depois)"
GH_TIMEOUT=20

project="" all=0 fmt=md out="" since="" next=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="${2:-}"; shift 2 ;;
    --all) all=1; shift ;;
    --format) fmt="${2:-md}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --since) since="${2:-}"; shift 2 ;;
    --next) next="${2:-}"; shift 2 ;;
    *) echo "uso: tools/baseline.sh --project <dir>|--all [--format md|json] [--out ARQ] [--since EPOCH --next N]" >&2; exit 2 ;;
  esac
done
[[ $all -eq 1 || -n "$project" ]] || { echo "baseline: informe --project <dir> ou --all" >&2; exit 2; }
[[ "$fmt" == md || "$fmt" == json ]] || { echo "baseline: --format md|json" >&2; exit 2; }
command -v jq >/dev/null || { echo "baseline: jq ausente" >&2; exit 2; }
[[ "$CORTE" =~ ^[0-9]+$ ]] || { echo "baseline: MAESTRO_BASELINE_CORTE deve ser epoch inteiro" >&2; exit 2; }

ISO() { date -d "@$1" +%Y-%m-%dT%H:%M:%S%z 2>/dev/null; }
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }
falha() { jq -nc --arg f "$1" --arg m "$2" '{fonte:$f, motivo:$m}'; }   # <fonte> <motivo>
motivo_rc() { [[ "$1" -eq 124 ]] && echo "estourou o timeout de ${2}s" || echo "falhou (rc=$1) ou devolveu saída inválida"; }
jarr() { if [[ $# -eq 0 ]]; then echo '[]'; else printf '%s\n' "$@" | jq -sc '.'; fi; }   # JSONs soltos → array
# FALHA com dado parcial: se algo foi medido, mantém o medido e marca FALHA; senão só a falha.
FIN='def fin($f; $got): if ($f|length)==0 then . elif $got then . + {status:"FALHA", falhas:$f} else {id, nome, status:"FALHA", falhas:$f} end;'

# ---- resolve o escopo ------------------------------------------------------------
root="" key="" pname=""
if [[ $all -eq 0 ]]; then
  root=$(cd -P -- "$project" 2>/dev/null && pwd) || { echo "baseline: --project inválido" >&2; exit 2; }
  key=$(maestro_brief_file "$root"); key="${key##*/}"; key="${key%.md}"
  pname="${root##*/}"
  if [[ -f "$root/.git" ]]; then
    c=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    [[ "$c" == */.git ]] && pname="$(basename "${c%/.git}")"
  fi
fi

# ---- ledger: fonte esperada de tudo que é por ordem ------------------------------------
ledger_motivo=""
for d in order-state evidence; do
  [[ -d "$HOME_M/$d" && -r "$HOME_M/$d" && -x "$HOME_M/$d" ]] || ledger_motivo="${ledger_motivo:+$ledger_motivo; }$d ausente ou ilegível"
done

# ---- repos: --project é a raiz; --all resolve cada chave do ledger para um checkout -------------
declare -A REPO_OF=()
TARGETS=()   # "rótulo|raiz" de cada repo a medir
UNRES=()     # falhas nomeadas: chave do ledger sem repo
resolve_repos() {
  local b d kk
  local -a bases=()
  IFS=: read -ra bases <<<"${MAESTRO_BASELINE_REPOS:-$HOME/dev}"
  for b in "${bases[@]}"; do
    for d in "$b"/*/; do
      d="${d%/}"; [[ -d "$d/.git" ]] || continue
      kk=$(maestro_brief_file "$d"); kk="${kk##*/}"; kk="${kk%.md}"
      [[ -n "${REPO_OF[$kk]:-}" ]] || REPO_OF[$kk]="$d"
    done
  done
}

# ---- métrica 1: orders_json e M1_JQ (população e janela) ---------------------------
# shellcheck source=lib/baseline-ordens.sh
source "$HERE/lib/baseline-ordens.sh"

# ---- janela "próximos N aceites" ------------------------------------------------
win_from=0 win_to=0 sel_note=""
apply_window() {
  [[ -n "$since" && -n "$next" ]] || return 0
  ORDERS_JSON=$(jq -c --argjson s "$since" --argjson n "$next" '
    [ .[] | select((.aceita|type)=="number" and .aceita > $s) ] | sort_by(.aceita) | .[:$n]' <<<"$ORDERS_JSON")
  win_from="$since"
  win_to=$(jq -r 'if length>0 then (map(.aceita)|max) else 0 end' <<<"$ORDERS_JSON")
  local got; got=$(jq 'length' <<<"$ORDERS_JSON")
  sel_note="próximos $next aceites após $since: $got encontrado(s)"
  if [[ "$got" -lt "$next" ]]; then
    sel_note="$sel_note (INCOMPLETO: faltam $((next-got)))"
    win_to=$NOW
  fi
}

ORDERS_JSON='[]'
if [[ $all -eq 1 ]]; then
  resolve_repos
  keys=$(for p in "$HOME_M"/order-state/*-[0-9]*; do
    [[ -f "$p" ]] || continue
    b="${p##*/}"; echo "${b%-*}"
  done | sort -u)
  parts=()
  for k in $keys; do
    r="${REPO_OF[$k]:-}"
    if [[ -n "$r" ]]; then TARGETS+=("$k|$r")
    else UNRES+=("$(falha "repo da chave $k" "chave do ledger sem repo: nenhum checkout em ${MAESTRO_BASELINE_REPOS:-~/dev} tem esta chave (defina MAESTRO_BASELINE_REPOS)")"); fi
    parts+=("$(orders_json "$k" "$r" | jq -c --arg k "$k" 'map(. + {projeto:$k})')")
  done
  [[ ${#parts[@]} -gt 0 ]] && ORDERS_JSON=$(printf '%s\n' "${parts[@]}" | jq -sc 'add // []')
else
  TARGETS=("$pname|$root")
  ORDERS_JSON=$(orders_json "$key" "$root")
fi
apply_window

# git do --project: fonte esperada (o --all checa cada repo no laço da métrica 3)
git_ok() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

f1=()
[[ -n "$ledger_motivo" ]] && f1+=("$(falha "ledger (order-state, evidence)" "$ledger_motivo")")
if [[ $all -eq 0 ]] && ! git_ok "$root"; then f1+=("$(falha "git" "repo ilegível ou não é um repositório git")"); fi
f1+=("${UNRES[@]}")
if [[ -n "$ledger_motivo" ]]; then
  m1=$(jq -nc --argjson f "$(jarr "${f1[@]}")" '{id:1, nome:"idade por estado e tempo parado em pronta (segundos)", status:"FALHA", falhas:$f}')
else
  m1=$(jq -c --argjson now "$NOW" --argjson corte "$CORTE" --arg corteiso "$(ISO "$CORTE")" --arg regra "$REGRA" --arg sf "$SF" \
    --argjson f "$(jarr "${f1[@]}")" "$M1_JQ" <<<"$ORDERS_JSON")
fi

# ---- métrica 2: CI verde → merge (gh SÓ leitura: gh pr list e gh run list, por repo) ------
M2_JQ="$FIN"'
  def e: sub("\\.[0-9]+Z$";"Z") | fromdateiso8601;
  def mediana: (length) as $n | (.[($n-1)/2|floor] + .[$n/2|floor]) / 2 | floor;
  [ $prs[] | . as $p
    | ([ $runs[] | select(.headSha==$p.headRefOid) | .updatedAt|e ] | max) as $g
    | select($g != null) | ($p.mergedAt|e) as $m | select($m >= $g)
    | {pr:$p.number, s:($m-$g)} ] as $r
  | ($r | map(.s) | sort) as $v
  | {id:2, nome:"tempo da CI verde até o merge"} as $b
  | if ($r|length)==0 then $b + {status:"sem dado", motivo:"nenhum PR mergeado com run verde casada pelo head"}
    else $b + {status:"ok", prs:($r|length), mediana_s:($v|mediana), max_s:($v|max),
               fonte:"gh pr list + gh run list (só leitura)"} end
  | fin($f; $got>0)'
f2=() GH_PRS=() GH_RUNS=()
gh_repo() { # <rótulo> <raiz> — só gh pr list e gh run list, na raiz do repo
  local lbl="$1" r="$2" p rr rc
  p=$(cd "$r" 2>/dev/null && timeout "$GH_TIMEOUT" gh pr list --state merged --limit 100 --json number,mergedAt,headRefOid 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]] || ! jq -e 'type=="array"' <<<"$p" >/dev/null 2>&1; then
    f2+=("$(falha "gh pr list ($lbl)" "$(motivo_rc "$rc" "$GH_TIMEOUT")")"); return
  fi
  rr=$(cd "$r" 2>/dev/null && timeout "$GH_TIMEOUT" gh run list --status success --limit 200 --json headSha,updatedAt 2>/dev/null); rc=$?
  if [[ $rc -ne 0 ]] || ! jq -e 'type=="array"' <<<"$rr" >/dev/null 2>&1; then
    f2+=("$(falha "gh run list ($lbl)" "$(motivo_rc "$rc" "$GH_TIMEOUT")")"); return
  fi
  GH_PRS+=("$p"); GH_RUNS+=("$rr")
}
if command -v gh >/dev/null; then
  for t in "${TARGETS[@]}"; do gh_repo "${t%%|*}" "${t#*|}"; done
else
  f2+=("$(falha "gh" "gh ausente do PATH (única chamada à internet; só gh pr list e gh run list)")")
fi
f2+=("${UNRES[@]}")
m2=$(jq -nc --argjson prs "$(jarr "${GH_PRS[@]}" | jq -c 'add // []')" --argjson runs "$(jarr "${GH_RUNS[@]}" | jq -c 'add // []')" \
  --argjson got "${#GH_PRS[@]}" --argjson f "$(jarr "${f2[@]}")" --arg sf "$SF" "$M2_JQ")
# sem repo algum medido e sem falha: a carteira é vazia (nada a medir)
if [[ ${#TARGETS[@]} -eq 0 && ${#UNRES[@]} -eq 0 ]]; then
  m2=$(jq -nc '{id:2, nome:"tempo da CI verde até o merge", status:"sem dado", motivo:"nenhum repo no escopo"}')
fi

# ---- métrica 3: rebases e conflitos (git de cada repo) ----------------------------------
rb=0 st=0 got3=0 f3=()
for t in "${TARGETS[@]}"; do
  r="${t#*|}"
  if git_ok "$r"; then
    got3=$((got3+1))
    rb=$((rb + $(git -C "$r" reflog show HEAD --format=%gs 2>/dev/null | grep -c '^rebase (start)')))
    st=$((st + $(git -C "$r" log --all --format=%s 2>/dev/null | grep -ci 'carimbo de aceite')))
  else
    f3+=("$(falha "git (${t%%|*})" "repo ilegível ou não é um repositório git")")
  fi
done
f3+=("${UNRES[@]}")
m3=$(jq -nc --argjson rb "$rb" --argjson st "$st" --argjson got "$got3" --argjson f "$(jarr "${f3[@]}")" --arg sf "$SF" "$FIN"'
  {id:3, nome:"rebases e conflitos por causa", status:(if $got>0 then "ok" else "sem dado" end),
   rebases_no_reflog_do_HEAD:$rb, commits_de_carimbo_de_aceite:$st,
   conflitos:$sf, por_causa:{carimbo:$sf, ordem_concorrente:$sf, outra:$sf},
   nota:"o git não registra conflito nem causa; o reflog cobre só este clone"}
  | if .status=="sem dado" then {id, nome, status, motivo:"nenhum repo no escopo"} else . end
  | fin($f; $got>0)')

# ---- routing: métricas 4 e 6 ---------------------------------------------------
RJ="$HOME_M/logs/routing.jsonl"
r4="" m6t="" f4=() f6=()
if [[ ! -r "$RJ" ]]; then
  f4+=("$(falha "routing.jsonl" "arquivo ausente ou ilegível")"); f6+=("$(falha "routing.jsonl" "arquivo ausente ou ilegível")")
else
  ids_json=$(jq -c '[.[].id]' <<<"$ORDERS_JSON" 2>/dev/null || echo '[]')
  r4=$(jq -sc --arg p "$pname" --argjson wf "$win_from" --argjson wt "$win_to" --argjson all "$all" '
    def t: (.ts | sub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601? // 0);
    map(select(.ts!=null) | select($wt==0 or (t > $wf and t <= $wt))) as $ev
    | ($ev | map(select(.event=="decision" and ($all==1 or .project==$p)) | .session_id) | unique) as $ss
    | [ $ev[] | select(.session_id as $s | $ss | index($s)) | select(.event=="gate_warn" or .event=="gate_block") ] as $g
    | { id:4, nome:"permissões por turno (gate_warn+gate_block)",
        status:(if ($ss|length)==0 then "sem dado" else "ok" end),
        turnos:($ss|length), permissoes:($g|length),
        permissoes_por_turno_x100:(if ($ss|length)>0 then (($g|length)*100/($ss|length)|floor) else null end),
        quais:($g | group_by(.cmd // .tool) | map({alvo:(.[0].cmd // .[0].tool), n:length}) | sort_by(-.n)),
        nota:"turno = sessão com decision registrada para o projeto" }
    | if .status=="sem dado" then {id, nome, status, motivo:"routing.jsonl sem decision na janela"} else . end' "$RJ" 2>/dev/null) \
    || { r4=""; f4+=("$(falha "routing.jsonl" "JSON inválido: a leitura falhou")"); }
  m6t=$(jq -sc --argjson ids "$ids_json" --argjson all "$all" --argjson wf "$win_from" --argjson wt "$win_to" '
    def t: (.ts | sub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601? // 0);
    [ .[] | select(.event=="turno_teto") | select($wt==0 or (t > $wf and t <= $wt)) | select($all==1 or ((.n|tonumber? // -1) as $n | $ids|index($n))) ] | length' "$RJ" 2>/dev/null)
  [[ "$m6t" =~ ^[0-9]+$ ]] || { m6t=""; f6+=("$(falha "routing.jsonl" "JSON inválido: a leitura falhou")"); }
fi
if [[ -n "$m6t" ]]; then
  m6=$(jq -nc --argjson t "$m6t" --arg sf "$SF" '
    {id:6, nome:"timeouts", turno:$t, teste:$sf, runner:$sf, status:"ok",
     nota:"turno = eventos turno_teto casados pelo número da ordem; teste e runner não têm registro"}')
else
  m6=$(jq -nc --argjson f "$(jarr "${f6[@]}")" '{id:6, nome:"timeouts", status:"FALHA", falhas:$f}')
fi

# ---- métrica 4 (complemento): permissões da Ponte, banco aberto em modo read-only ----------
PDB="${MAESTRO_PONTE_DB:-$HOME/.ponte/ponte.db}"
pf=""; [[ $all -eq 0 ]] && pf="AND r.project = '${pname,,}'"; pf="${pf//[^a-zA-Z0-9_ =\'.-]/}"
# permissões cortadas pela janela da v59: o lado é o do instante em que o RUN foi criado
PONTE_SQL="
  WITH runs AS (
    SELECT run_id, project, order_ref, created_at,
           CASE WHEN CAST(strftime('%s', created_at) AS INTEGER) <= $CORTE THEN 'antes' ELSE 'depois' END AS lado,
           LEAD(created_at) OVER (PARTITION BY project, order_ref ORDER BY created_at) AS prox
    FROM manager_run r WHERE 1=1 $pf),
  perm AS (
    SELECT r.run_id, r.project, r.lado, d.tool_name
    FROM runs r JOIN decision d ON d.kind='permission' AND d.project=r.project AND d.order_ref=r.order_ref
      AND d.created_at >= r.created_at AND (r.prox IS NULL OR d.created_at < r.prox))
  SELECT 'run' AS tipo, run_id AS chave, project, lado, count(perm.run_id) AS n FROM runs LEFT JOIN perm USING(run_id, project, lado) GROUP BY run_id
  UNION ALL SELECT 'projeto', project, project, lado, count(*) FROM perm GROUP BY project, lado
  UNION ALL SELECT 'ferramenta', coalesce(tool_name,'?'), '', lado, count(*) FROM perm GROUP BY tool_name, lado"
PONTE_JQ='
  . as $p | { fonte:"ponte.db (sqlite3 -readonly, mode=ro)", status:"ok",
    corte_epoch:$corte,
    runs:($p|map(select(.tipo=="run"))|length),
    permissoes_por_run:($p|map(select(.tipo=="run")|{run:.chave, projeto:.project, lado, n})),
    permissoes_por_projeto:($p|map(select(.tipo=="projeto")|{projeto:.chave, lado, n})),
    quais:($p|map(select(.tipo=="ferramenta")|{alvo:.chave, lado, n})|sort_by(-.n)) }'
ponte_falha="" pontej=""
if [[ ! -r "$PDB" ]]; then ponte_falha="banco ausente ou ilegível"
elif ! command -v sqlite3 >/dev/null; then ponte_falha="sqlite3 ausente (necessário para ler a Ponte)"
else
  pontej=$(sqlite3 -readonly -json "file:$PDB?mode=ro" "$PONTE_SQL" 2>/dev/null) \
    || ponte_falha="consulta somente-leitura falhou (banco corrompido ou esquema inesperado)"
fi
if [[ -n "$ponte_falha" ]]; then
  f4+=("$(falha "ponte.db" "$ponte_falha")")
  ponte=$(jq -nc --arg m "$ponte_falha" '{status:"FALHA", motivo:$m}')
elif [[ -z "$pontej" ]]; then
  ponte=$(jq -nc '{status:"sem dado", motivo:"ponte.db legível, sem runs do projeto"}')
else
  ponte=$(jq -c --argjson corte "$CORTE" "$PONTE_JQ" <<<"$pontej" 2>/dev/null) || {
    f4+=("$(falha "ponte.db" "saída da consulta ilegível")"); ponte=$(jq -nc '{status:"FALHA", motivo:"saída da consulta ilegível"}'); }
fi
[[ -n "$r4" ]] || r4=$(jq -nc '{id:4, nome:"permissões por turno (gate_warn+gate_block)"}')
m4=$(jq -c --argjson po "$ponte" --argjson f "$(jarr "${f4[@]}")" '
  . + {ponte:$po}
  | if ($f|length)>0 then . + {status:"FALHA", falhas:$f}
    elif .status=="ok" or $po.status=="ok" then .status="ok" | del(.motivo)
    else .status="sem dado" end' <<<"$r4")

# ---- métrica 5: lab-ci por comandos de leitura ---------------------------------------
lab="${MAESTRO_BASELINE_LAB_SSH:-lab-ci}"
SSH_TIMEOUT="${MAESTRO_BASELINE_SSH_TIMEOUT:-15}"
m5="" raw="" f5=""
if command -v ssh >/dev/null; then
  # lista fechada de leitura: uptime, nproc, free, systemctl list-units (filtrado por runners), contagem de jobs
  raw=$(timeout "$SSH_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout=5 "$lab" \
    'uptime; nproc; free -m; systemctl list-units --no-legend --type=service | grep -i runner; echo ---; pgrep -fc "[R]unner.Worker"; true' 2>/dev/null) \
    || f5="ssh $lab $(motivo_rc $? "$SSH_TIMEOUT")"
else
  f5="ssh ausente do PATH"
fi
if [[ -z "$f5" ]]; then
  ld=$(grep -o 'load average[s]*: *[0-9]*[.,][0-9]*' <<<"$raw" | head -1 | grep -o '[0-9]*[.,][0-9]*$' | tr ',' '.')
  nc=$(grep -E '^[0-9]+$' <<<"$raw" | head -1)
  mt=$(awk '/^Mem/{print $2; exit}' <<<"$raw")
  ma=$(awk '/^Mem/{print $7; exit}' <<<"$raw")
  ru=$(sed '/^---$/,$d' <<<"$raw" | grep -ci 'runner.*\.service')
  jw=$(sed -n '/^---$/,$p' <<<"$raw" | grep -E '^[0-9]+$' | head -1)
  if [[ -n "$ld" && "$nc" =~ ^[0-9]+$ && "$mt" =~ ^[0-9]+$ && "$ma" =~ ^[0-9]+$ && "$jw" =~ ^[0-9]+$ ]]; then
    ldx=$(awk -v l="$ld" 'BEGIN{printf "%d", l*100}')
    m5=$(jq -nc --argjson ld "$ldx" --argjson nc "$nc" --argjson mt "$mt" --argjson ma "$ma" \
      --argjson ru "$ru" --argjson jw "$jw" --arg sf "$SF" --arg lab "$lab" '
      {id:5, nome:"CPU, memória e fila de runner (lab-ci)", status:"ok", host:$lab, load1m_x100:$ld, ncpu:$nc,
       mem_total_mb:$mt, mem_disponivel_mb:$ma, runners_ativos:$ru, jobs_em_execucao:$jw, jobs_na_fila:$sf,
       nota:"jobs em execução = pgrep Runner.Worker; a fila é do GitHub e não é lida (só gh run list e gh pr list)"}')
  else
    f5="ssh $lab devolveu saída não reconhecida"
  fi
fi
[[ -n "$m5" ]] || m5=$(jq -nc --arg f "ssh $lab" --arg m "${f5#ssh $lab }" '{id:5, nome:"CPU, memória e fila de runner (lab-ci)", status:"FALHA", falhas:[{fonte:$f, motivo:$m}]}')

# ---- métricas 7 a 9 (ações do Capitão, retrabalho, custo por ordem): ver lib/baseline-novas.sh -----
# shellcheck source=lib/baseline-novas.sh
source "$HERE/lib/baseline-novas.sh"
m7=$(m7_acoes_capitao)
m8=$(m8_retrabalho)
m9=$(m9_custo)

# ---- monta a saída ------------------------------------------------------------------
doc=$(jq -nc --arg gen "$(ISO "$NOW")" --argjson now "$NOW" --arg proj "${pname:-carteira}" --arg sel "$sel_note" \
  --argjson m1 "$m1" --argjson m2 "$m2" --argjson m3 "$m3" --argjson m4 "$m4" --argjson m5 "$m5" --argjson m6 "$m6" \
  --argjson m7 "$m7" --argjson m8 "$m8" --argjson m9 "$m9" '
  {schema:"maestro-baseline-v3", gerado_em:$gen, epoch:$now, projeto:$proj, selecao:(if $sel=="" then "todas" else $sel end),
   metricas:[$m1,$m2,$m3,$m4,$m5,$m6,$m7,$m8,$m9]}')

render() {
  if [[ "$fmt" == json ]]; then jq . <<<"$doc"; return; fi
  jq -r '
    def cell: if type=="object" or type=="array" then tojson else tostring end;
    def lado($n; $l): "- N \($n): \($l.n) (medidas \($l.n_medida)\(if $l.n_pequeno then ", N pequeno" else "" end)) · mediana da parada em pronta: \($l.mediana_parada_em_pronta_s) s · ordens: \($l.ids|tojson)";
    "# Linha de base — \(.projeto)\n\n- gerado em: \(.gerado_em) (epoch \(.epoch))\n- seleção: \(.selecao)\n",
    ( .metricas[] | "## \(.id). \(.nome)\n\n- status: \(.status)",
      ( to_entries | map(select(.key|IN("id","nome","status","ordens","janela")|not)) | .[] | "- \(.key): \(.value|cell)" ),
      ( if .janela then
          "- regra de população: \(.janela.regra)",
          "- corte (v59): \(.janela.corte_iso) (epoch \(.janela.corte_epoch))",
          lado("antes"; .janela.antes), lado("depois"; .janela.depois),
          "- comparação: \(.janela.comparacao)" else empty end ),
      ( if (.ordens|type)=="array" and (.ordens|length)>0 then "\n| ordem | lado | aberta→exec (s) | exec→provada (s) | parada em pronta (s) | aceita (epoch) |\n|---|---|---|---|---|---|",
          (.ordens[] | "| \(.id) | \(.lado) | \(.idade_aberta_s) | \(.idade_execucao_s) | \(.parada_em_pronta_s)\(if .legada_sem_carimbo then " (legada)" else "" end) | \(.aceita) |")
        else empty end ),
      "" )' <<<"$doc"
  echo "## Falhas"; echo
  jq -r '[.metricas[] | select(.status=="FALHA") | . as $m | .falhas[] | "- \($m.id). \($m.nome): FALHA — \(.fonte): \(.motivo)"] | if length==0 then "nenhuma" else .[] end' <<<"$doc"
  echo; echo "## Sem dado"; echo
  jq -r '[.metricas[] | select(.status=="sem dado") | "- \(.id). \(.nome)"] | if length==0 then "nenhuma" else .[] end' <<<"$doc"
  echo; echo "## Campos sem fonte por construção"; echo
  jq -r '[.metricas[] | select(.status=="ok") | . as $m | [ to_entries[] | select(.value=="sem fonte") | .key ] | select(length>0) | "- \($m.id). \($m.nome): \(join(", "))"] | if length==0 then "nenhum" else .[] end' <<<"$doc"
}

if [[ -n "$out" ]]; then render >"$out"; else render; fi

# FALHA alto: a fonte e o motivo em stderr, exit 3 (o painel parcial já saiu acima)
nfalha=$(jq '[.metricas[] | select(.status=="FALHA")] | length' <<<"$doc")
if [[ "$nfalha" -gt 0 ]]; then
  jq -r '.metricas[] | select(.status=="FALHA") | . as $m | .falhas[] | "baseline: FALHA métrica \($m.id) — fonte: \(.fonte) — \(.motivo)"' <<<"$doc" >&2
  exit 3
fi
exit 0
