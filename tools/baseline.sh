#!/usr/bin/env bash
# tools/baseline.sh — painel de linha de base da fábrica (ordem 058, Etapa 0 do plano v2).
# SOMENTE LEITURA: lê o ledger (~/.maestro), o git do repo, o routing.jsonl e, por ssh
# com comandos de leitura, o lab-ci. Escreve apenas em stdout ou no --out indicado.
# Regra de honestidade: métrica/campo sem fonte legível vira "sem fonte"; nunca se estima.
#
# Uso: tools/baseline.sh --project <dir> [--format md|json] [--out ARQ]
#                        [--since EPOCH --next N]   # só os N próximos aceites após EPOCH
#      tools/baseline.sh --all [--format ...]       # carteira (chaves do ledger)
# Ambiente: MAESTRO_HOME (ledger), MAESTRO_BASELINE_LAB_SSH (host do lab-ci; sem ele,
#           a métrica 5 é "sem fonte"), MAESTRO_BASELINE_NOW (epoch fixo, p/ teste).
set -u
SF='sem fonte'
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=../hooks/lib/project-state.sh
source "$REPO_ROOT/hooks/lib/project-state.sh"
HOME_M="${MAESTRO_HOME:-$HOME/.maestro}"
NOW="${MAESTRO_BASELINE_NOW:-$(date +%s)}"

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

ISO() { date -d "@$1" +%Y-%m-%dT%H:%M:%S%z 2>/dev/null; }
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

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

# ---- métrica 1: idade por estado (lista de ordens) --------------------------------
# Emite um JSON array: [{id,aberta,execucao,provada,aceita}] com "sem fonte" nos ausentes.
orders_json() { # <chave> <raiz|""> → array JSON
  local k="$1" r="$2" f id n ab ex pr ac sf ev ref cre s3
  local rows=()
  declare -A ids=()
  for sf in "$HOME_M"/order-state/"$k"-[0-9]*; do
    [[ -f "$sf" ]] || continue
    n="${sf##*-}"; ids[$((10#$n))]=1
  done
  if [[ -n "$r" ]]; then
    for f in "$r"/.maestro/orders/[0-9]*.md; do
      [[ -f "$f" ]] || continue
      n="${f##*/}"; n="${n%%-*}"; ids[$((10#$n))]=1
    done
  fi
  for id in $(printf '%s\n' "${!ids[@]}" | sort -n); do
    s3=$(printf '%03d' "$id")
    ab="$SF" ex="$SF" pr="$SF" ac="$SF"
    f=""
    [[ -n "$r" ]] && f=$(ls "$r"/.maestro/orders/"$s3"-*.md 2>/dev/null | head -1)
    if [[ -n "$f" ]]; then
      n=$(sed -n 's/^epoch: //p' "$f" | head -1)
      [[ "$n" =~ ^[0-9]+$ ]] && ab="$n"
    fi
    sf="$HOME_M/order-state/$k-$s3"
    if [[ -f "$sf" && "$(field "$sf" outcome)" == aceita ]]; then
      n=$(field "$sf" accepted_at)
      n=$(date -d "$n" +%s 2>/dev/null) && [[ -n "$n" ]] && ac="$n"
    fi
    ev="$HOME_M/evidence/$k-order-$id"
    if [[ -f "$ev" && "$(field "$ev" exit)" == 0 ]]; then
      n=$(field "$ev" epoch)
      [[ "$n" =~ ^[0-9]+$ ]] && pr="$n"
    fi
    if [[ -n "$r" && "$ab" != "$SF" ]]; then
      ref=$(git -C "$r" for-each-ref --format='%(refname)' "refs/heads/order/$s3-*" "refs/remotes/origin/order/$s3-*" 2>/dev/null | head -1)
      cre=$(git -C "$r" log --diff-filter=A --format=%H -1 -- ".maestro/orders/$s3-*" 2>/dev/null)
      if [[ -n "$ref" && -n "$cre" ]]; then
        n=$(git -C "$r" log --reverse --format=%ct "$cre..$ref" 2>/dev/null | head -1)
        [[ "$n" =~ ^[0-9]+$ ]] && ex="$n"
      fi
    fi
    rows+=("$(jq -nc --argjson id "$id" --arg ab "$ab" --arg ex "$ex" --arg pr "$pr" --arg ac "$ac" '
      def v: if test("^[0-9]+$") then tonumber else . end;
      {id:$id, aberta:($ab|v), execucao:($ex|v), provada:($pr|v), aceita:($ac|v)}')")
  done
  if [[ ${#rows[@]} -eq 0 ]]; then echo '[]'; return; fi
  printf '%s\n' "${rows[@]}" | jq -sc '.'
}

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

if [[ $all -eq 1 ]]; then
  keys=$(for p in "$HOME_M"/order-state/*-[0-9]*; do
    [[ -f "$p" ]] || continue
    b="${p##*/}"; echo "${b%-*}"
  done | sort -u)
  ORDERS_JSON=$(for k in $keys; do orders_json "$k" "" | jq -c --arg k "$k" 'map(. + {projeto:$k})'; done | jq -sc 'add // []')
else
  ORDERS_JSON=$(orders_json "$key" "$root")
fi
apply_window

m1=$(jq -c --argjson now "$NOW" --arg sf "$SF" '
  # intervalo negativo = marcos fora de ordem (recibo regravado, relógio): sem fonte, não número
  def d(a;b): if (a|type)=="number" and (b|type)=="number" and b >= a then (b-a) else $sf end;
  # recibo regravado depois do aceite (aceita < provada) não diz quando ficou pronta: sem fonte
  def pronta: if (.provada|type)!="number" then $sf
    elif (.aceita|type)=="number" then (if .aceita >= .provada then .aceita - .provada else $sf end)
    else $now - .provada end;
  { id:1, nome:"idade por estado e tempo parado em pronta (segundos)",
    ordens: map(. + {
      idade_aberta_s: d(.aberta; .execucao),
      idade_execucao_s: d(.execucao; .provada),
      parada_em_pronta_s: pronta }) }
  | .status = (if (.ordens|length)==0 then $sf else "ok" end)
  | if .status==$sf then .ordens=$sf else . end' <<<"$ORDERS_JSON")

# ---- métrica 2: CI verde → merge ---------------------------------------------
m2=$(jq -nc --arg sf "$SF" '{id:2, nome:"tempo da CI verde até o merge", status:$sf,
  motivo:"nenhum registro local do instante de CI verde (consultar o GitHub é rede; fora do contrato)", valor:$sf}')

# ---- métrica 3: rebases e conflitos ----------------------------------------------
if [[ -n "$root" ]]; then
  rb=$(git -C "$root" reflog show HEAD --format=%gs 2>/dev/null | grep -c '^rebase (start)')
  st=$(git -C "$root" log --all --format=%s 2>/dev/null | grep -ci 'carimbo de aceite')
  m3=$(jq -nc --argjson rb "$rb" --argjson st "$st" --arg sf "$SF" '{id:3, nome:"rebases e conflitos por causa", status:"ok",
    rebases_no_reflog_do_HEAD:$rb, commits_de_carimbo_de_aceite:$st,
    conflitos:$sf, por_causa:{carimbo:$sf, ordem_concorrente:$sf, outra:$sf},
    nota:"o git não registra conflito nem causa; o reflog cobre só este clone"}')
else
  m3=$(jq -nc --arg sf "$SF" '{id:3, nome:"rebases e conflitos por causa", status:$sf, valor:$sf}')
fi

# ---- routing: métricas 4 e 6 ---------------------------------------------------
RJ="$HOME_M/logs/routing.jsonl"
m4="" m6t="$SF"
if [[ -r "$RJ" ]]; then
  ids_json=$(jq -c '[.[].id]' <<<"$ORDERS_JSON" 2>/dev/null || echo '[]')
  m4=$(jq -sc --arg p "$pname" --argjson wf "$win_from" --argjson wt "$win_to" --arg sf "$SF" --argjson all "$all" '
    def t: (.ts | sub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601? // 0);
    map(select(.ts!=null) | select($wt==0 or (t > $wf and t <= $wt))) as $ev
    | ($ev | map(select(.event=="decision" and ($all==1 or .project==$p)) | .session_id) | unique) as $ss
    | [ $ev[] | select(.session_id as $s | $ss | index($s)) | select(.event=="gate_warn" or .event=="gate_block") ] as $g
    | { id:4, nome:"permissões por turno (gate_warn+gate_block)",
        status:(if ($ss|length)==0 then $sf else "ok" end),
        turnos:($ss|length), permissoes:($g|length),
        permissoes_por_turno_x100:(if ($ss|length)>0 then (($g|length)*100/($ss|length)|floor) else $sf end),
        quais:($g | group_by(.cmd // .tool) | map({alvo:(.[0].cmd // .[0].tool), n:length}) | sort_by(-.n)),
        nota:"turno = sessão com decision registrada para o projeto" }
    | if .status==$sf then {id, nome, status, valor:$sf} else . end' "$RJ" 2>/dev/null) || m4=""
  m6t=$(jq -sc --argjson ids "$ids_json" --argjson all "$all" --argjson wf "$win_from" --argjson wt "$win_to" '
    def t: (.ts | sub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601? // 0);
    [ .[] | select(.event=="turno_teto") | select($wt==0 or (t > $wf and t <= $wt)) | select($all==1 or ((.n|tonumber? // -1) as $n | $ids|index($n))) ] | length' "$RJ" 2>/dev/null)
  [[ "$m6t" =~ ^[0-9]+$ ]] || m6t="$SF"
fi
[[ -n "$m4" ]] || m4=$(jq -nc --arg sf "$SF" '{id:4, nome:"permissões por turno", status:$sf, valor:$sf}')
m6=$(jq -nc --arg t "$m6t" --arg sf "$SF" '
  {id:6, nome:"timeouts", turno:(if $t==$sf then $sf else ($t|tonumber) end), teste:$sf, runner:$sf,
   status:(if $t==$sf then $sf else "ok" end),
   nota:"turno = eventos turno_teto casados pelo número da ordem; teste e runner não têm registro"}')

# ---- métrica 5: lab-ci por comandos de leitura ---------------------------------------
lab="${MAESTRO_BASELINE_LAB_SSH:-}"
m5=""
if [[ -n "$lab" ]] && command -v ssh >/dev/null; then
  raw=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$lab" \
    'cat /proc/loadavg; nproc; grep -E "^(MemTotal|MemAvailable):" /proc/meminfo; pgrep -fc Runner.Listener; pgrep -fc Runner.Worker' 2>/dev/null) || raw=""
  mapfile -t L <<<"$raw"
  if [[ ${#L[@]} -ge 6 && "${L[1]}" =~ ^[0-9]+$ ]]; then
    ld=$(awk '{printf "%d", $1*100}' <<<"${L[0]}")
    mt=$(awk '{print int($2/1024)}' <<<"${L[2]}")
    ma=$(awk '{print int($2/1024)}' <<<"${L[3]}")
    m5=$(jq -nc --argjson ld "$ld" --argjson nc "${L[1]}" --argjson mt "$mt" --argjson ma "$ma" \
      --argjson rl "${L[4]:-0}" --argjson rw "${L[5]:-0}" --arg sf "$SF" '
      {id:5, nome:"CPU, memória e fila de runner (lab-ci)", status:"ok", load1m_x100:$ld, ncpu:$nc,
       mem_total_mb:$mt, mem_disponivel_mb:$ma, runners_ativos:$rl, jobs_em_execucao:$rw, jobs_na_fila:$sf,
       nota:"fila exige a API do GitHub (rede); fora do contrato"}')
  fi
fi
[[ -n "$m5" ]] || m5=$(jq -nc --arg sf "$SF" '{id:5, nome:"CPU, memória e fila de runner (lab-ci)", status:$sf, valor:$sf,
  motivo:"MAESTRO_BASELINE_LAB_SSH ausente ou lab-ci inalcançável"}')

# ---- monta a saída ------------------------------------------------------------------
doc=$(jq -nc --arg gen "$(ISO "$NOW")" --argjson now "$NOW" --arg proj "${pname:-carteira}" --arg sel "$sel_note" \
  --argjson m1 "$m1" --argjson m2 "$m2" --argjson m3 "$m3" --argjson m4 "$m4" --argjson m5 "$m5" --argjson m6 "$m6" '
  {schema:"maestro-baseline-v1", gerado_em:$gen, epoch:$now, projeto:$proj, selecao:(if $sel=="" then "todas" else $sel end),
   metricas:[$m1,$m2,$m3,$m4,$m5,$m6]}')

render() {
  if [[ "$fmt" == json ]]; then jq . <<<"$doc"; return; fi
  jq -r '
    def cell: if type=="object" or type=="array" then tojson else tostring end;
    "# Linha de base — \(.projeto)\n\n- gerado em: \(.gerado_em) (epoch \(.epoch))\n- seleção: \(.selecao)\n",
    ( .metricas[] | "## \(.id). \(.nome)\n\n- status: \(.status)",
      ( to_entries | map(select(.key|IN("id","nome","status","ordens")|not)) | .[] | "- \(.key): \(.value|cell)" ),
      ( if (.ordens|type)=="array" and (.ordens|length)>0 then "\n| ordem | aberta→exec (s) | exec→provada (s) | parada em pronta (s) | aceita (epoch) |\n|---|---|---|---|---|",
          (.ordens[] | "| \(.id) | \(.idade_aberta_s) | \(.idade_execucao_s) | \(.parada_em_pronta_s) | \(.aceita) |")
        elif .ordens=="sem fonte" then "- ordens: sem fonte" else empty end ),
      "" )' <<<"$doc"
  echo "## Métricas sem fonte"; echo
  jq -r '.metricas[] | select(.status=="sem fonte") | "- \(.id). \(.nome)"' <<<"$doc"
  jq -r '.metricas[] | select(.status=="ok") | . as $m | [ to_entries[] | select(.value=="sem fonte") | .key ] | select(length>0) | "- \($m.id). \($m.nome): campos sem fonte → \(join(", "))"' <<<"$doc"
}

if [[ -n "$out" ]]; then render >"$out"; else render; fi
