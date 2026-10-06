#!/usr/bin/env bash
# tools/fase1-painel.sh — painel de medição dos 7 dias da Fase 1 (sombra), auditoria de 05/10, seção 7, item 4.
# SOMENTE LEITURA: lê o ledger do Maestro, o banco da Ponte em modo `mode=ro` e o reflog do git.
# Só inteiros (contagens e percentuais inteiros), só metadados. Sem rede.
# Uso: tools/fase1-painel.sh [--inicio ISO8601] [--dias N] [--baseline-dias N]
#   --inicio  data de início da sombra (default: a 1ª linha de docs/fase1/INICIO)
# Fontes (env, para teste): MAESTRO_HOME (ledger em logs/routing.jsonl), PONTE_DB (default ~/.ponte/ponte.db),
#   FASE1_REPOS (lista de repos para o reflog; default: git worktree list do repo deste script).
# Fonte esperada ausente → FALHA nomeada em stderr, a seção sai marcada e o exit é 3 (nunca "sem dado" calado).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
inicio=""; dias=7; bdias=14
while (( $# )); do
  case "$1" in
    --inicio) inicio="${2:-}"; shift 2 ;;
    --dias) dias="${2:-}"; shift 2 ;;
    --baseline-dias) bdias="${2:-}"; shift 2 ;;
    *) echo "uso: tools/fase1-painel.sh [--inicio ISO8601] [--dias N] [--baseline-dias N]" >&2; exit 2 ;;
  esac
done
[[ -n "$inicio" ]] || { [[ -r "$HERE/docs/fase1/INICIO" ]] && read -r inicio < "$HERE/docs/fase1/INICIO"; }
[[ -n "$inicio" ]] || { echo "fase1-painel: informe --inicio ou escreva a data em docs/fase1/INICIO" >&2; exit 2; }
[[ "$dias" =~ ^[0-9]+$ && "$bdias" =~ ^[0-9]+$ ]] || { echo "fase1-painel: --dias e --baseline-dias são inteiros" >&2; exit 2; }
t0=$(date -d "$inicio" +%s 2>/dev/null) || { echo "fase1-painel: data de início inválida: $inicio" >&2; exit 2; }
t1=$((t0 + dias * 86400)); tb=$((t0 - bdias * 86400)); agora=$(date +%s)
command -v jq >/dev/null || { echo "fase1-painel: FALHA jq ausente" >&2; exit 3; }
MH="${MAESTRO_HOME:-$HOME/.maestro}"; LEDGER="$MH/logs/routing.jsonl"; DB="${PONTE_DB:-$HOME/.ponte/ponte.db}"
falhas=0
loc() { date -d "@$1" +%Y-%m-%dT%H:%M:%S; }        # ts do ledger é horário local
utc() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S; }      # created_at da Ponte é UTC
dia_s() { date -d "@$1" +%Y-%m-%d; }

read -r -d '' AB_JQ <<'EOF'
(map(select(.session_id != null)) | group_by(.session_id)) as $g
| [ $g[] | . as $ev
    | { dec: ([ $ev[] | select(.event=="decision") | .ts ] | sort | .[0]),
        semdec: ([ $ev[] | select((.event=="gate_block" or .event=="gate_warn") and (.tool=="Edit" or .tool=="Write" or .tool=="MultiEdit") and (.cmd==null)) | .ts ] | sort | .[0]),
        mode: ([ $ev[] | select(.event=="decision") | .mode ] | .[0]) } ] as $s
| ($s | map(select(.dec != null or .semdec != null))) as $cod
| ($cod | map(select(.dec != null and (.semdec == null or .dec < .semdec)))) as $esp
| ($s | map(select(.mode != null))) as $dc
| ($dc | map(select(.mode=="subagent" or .mode=="multi"))) as $sm
| [ ($cod|length), ($esp|length), (if ($cod|length)>0 then (($esp|length)*100/($cod|length)|floor) else -1 end),
    ($dc|length), ($sm|length), (if ($dc|length)>0 then (($sm|length)*100/($dc|length)|floor) else -1 end) ] | @tsv
EOF

ledger_janela() { jq -c --arg a "$(loc "$1")" --arg b "$(loc "$2")" 'select(.ts[0:19] >= $a and .ts[0:19] < $b)' "$LEDGER"; }
ab() { ledger_janela "$1" "$2" | jq -s -r "$AB_JQ"; }
pq() { sqlite3 -readonly "file:$DB?mode=ro" "$1" 2>/dev/null; }

secao_ponte() { # <de> <ate> → "prompts allow deny"
  local de a b; de="$(utc "$1")"; a="$(utc "$2")"
  b="d.created_at >= '$de' and d.created_at < '$a'"
  local p al dn
  p=$(pq "select count(*) from decision d where d.kind='permission' and $b") || return 1
  al=$(pq "select count(*) from decision d join decision_resolution r on r.decision_id=d.id where d.kind='permission' and $b and r.choice='allow'")
  dn=$(pq "select count(*) from decision d join decision_resolution r on r.decision_id=d.id where d.kind='permission' and $b and r.choice='deny'")
  echo "${p:-0} ${al:-0} ${dn:-0}"
}

reflog_resets() { # <de> <ate> → nº de entradas `reset:` no reflog dos repos, na janela
  local a b n=0 r c repos
  a="$(loc "$1")"; b="$(loc "$2")"
  if [[ -n "${FASE1_REPOS:-}" ]]; then repos="$FASE1_REPOS"; else repos=$(git -C "$HERE" worktree list 2>/dev/null | awk '{print $1}'); fi
  for r in $repos; do
    c=$(git -C "$r" reflog show --date=format:%Y-%m-%dT%H:%M:%S --format='%cd|%gs' HEAD 2>/dev/null \
        | awk -F'|' -v a="$a" -v b="$b" '$1>=a && $1<b && $2 ~ /^reset:/ {n++} END{print n+0}')
    n=$((n + c))
  done
  echo "$n"
}

por_dia() { echo $(( $1 / ($2 > 0 ? $2 : 1) )); }
veredito() { # <valor> <minimo> <n> → PASS|FAIL|INSUFICIENTE
  [[ "$3" -ge 10 && "$1" -ge 0 ]] || { echo INSUFICIENTE; return; }
  (( $1 >= $2 )) && echo PASS || echo FAIL
}

estado="AGUARDANDO INÍCIO"; dia_atual=0
if (( agora >= t0 && agora < t1 )); then dia_atual=$(( (agora - t0) / 86400 + 1 )); estado="EM ANDAMENTO (dia $dia_atual de $dias)"; fi
(( agora >= t1 )) && estado="ENCERRADA"

echo "# Fase 1 — painel dos $dias dias (sombra)"; echo
echo "- **Início:** $(dia_s "$t0") · **fim:** $(dia_s "$t1") · **estado:** $estado"
echo "- **Baseline:** os $bdias dias antes do início ($(dia_s "$tb") a $(dia_s "$t0"))"
echo "- **Rollback:** \`docs/fase1/ROLLBACK.md\`"; echo

echo "## 1. Prompts e negações nativos (Ponte, \`decision.kind=permission\`)"; echo
if [[ ! -r "$DB" ]] || ! command -v sqlite3 >/dev/null; then
  echo "- **FALHA:** banco da Ponte ou sqlite3 indisponível ($DB)"; echo "fase1-painel: FALHA fonte: ponte.db" >&2; falhas=1
else
  read -r bp ba bd < <(secao_ponte "$tb" "$t0") || { echo "fase1-painel: FALHA consulta ao ponte.db" >&2; falhas=1; bp=0 ba=0 bd=0; }
  read -r wp wa wd < <(secao_ponte "$t0" "$t1")
  echo "| | prompts | allow | deny | prompts/dia |"; echo "|---|---|---|---|---|"
  echo "| baseline | ${bp:-0} | ${ba:-0} | ${bd:-0} | $(por_dia "${bp:-0}" "$bdias") |"
  echo "| janela | ${wp:-0} | ${wa:-0} | ${wd:-0} | $(por_dia "${wp:-0}" "$(( dia_atual > 0 ? dia_atual : dias ))") |"
fi; echo

echo "## 2. Incidentes destrutivos"; echo
inc=0
if [[ -r "$HERE/docs/fase1/INCIDENTES.md" ]]; then
  da="$(dia_s "$t0")"; db="$(dia_s "$t1")"
  inc=$(awk -v a="$da" -v b="$db" '/^- [0-9]{4}-[0-9]{2}-[0-9]{2}/ { d=substr($2,1,10); if (d>=a && d<b) n++ } END{print n+0}' "$HERE/docs/fase1/INCIDENTES.md")
fi
rs_b=$(reflog_resets "$tb" "$t0"); rs_w=$(reflog_resets "$t0" "$t1")
echo "- **Incidentes relatados** (\`docs/fase1/INCIDENTES.md\`, uma linha \`- AAAA-MM-DD …\` por incidente): **$inc**"
echo "- Indício, não critério: entradas \`reset:\` no reflog dos repos — baseline $rs_b · janela $rs_w"
if [[ -r "$LEDGER" ]]; then
  exp=$(ledger_janela "$t0" "$t1" | jq -s '[.[] | select(.event=="gate_warn" and (.cmd=="rm_recursive" or .cmd=="git_force_push" or .cmd=="git_reset_hard" or .cmd=="git_discard" or .cmd=="disk_format" or .cmd=="container_destructive"))] | length')
  echo "- Exposição (guard só registra): $exp comandos destrutivos que o guard teria barrado, na janela"
fi; echo

echo "## 3. A/B do gate (ledger)"; echo
if [[ ! -r "$LEDGER" ]]; then
  echo "- **FALHA:** ledger ilegível ($LEDGER)"; echo "fase1-painel: FALHA fonte: ledger" >&2; falhas=1
else
  read -r bc be bpe bd2 bs bps < <(ab "$tb" "$t0"); read -r wc we wpe wd2 ws wps < <(ab "$t0" "$t1")
  echo "| | sessões com código | espontâneas | **% espontâneas** | sessões com decisão | subagent/multi | **% subagent/multi** |"; echo "|---|---|---|---|---|---|---|"
  echo "| baseline | $bc | $be | $bpe | $bd2 | $bs | $bps |"
  echo "| janela | $wc | $we | $wpe | $wd2 | $ws | $wps |"; echo
  piso=${bpe:--1}   # decisão do Capitão (06/10): o piso é o baseline MEDIDO aqui (14 dias antes do início), não 50 nem 58 fixos
  v1=$(veredito "${wpe:--1}" "$piso" "${wc:-0}"); (( piso >= 0 )) || v1=INSUFICIENTE; mn=$(( ${bps:-0} - 5 )); v2=$(veredito "${wps:--1}" "$mn" "${wd2:-0}")
  echo "**Critérios (mínimo de 10 sessões para valer):**"; echo
  echo "- decisões espontâneas ≥ baseline medido (${piso}%): **$v1** (janela ${wpe:--1}%)"
  echo "- fração subagent/multi sem queda > 5 p.p. (≥ ${mn}%): **$v2** (janela ${wps:--1}%)"
  echo "- incidentes destrutivos = 0: **$( (( inc == 0 )) && echo PASS || echo FAIL )** ($inc)"
fi
echo; echo "_Definição: sessão com código = teve decisão ou edição sem decisão; espontânea = a decisão veio antes do primeiro gate sem decisão._"
(( falhas == 0 )) || exit 3
exit 0
