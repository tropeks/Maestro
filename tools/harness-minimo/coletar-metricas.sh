#!/usr/bin/env bash
# tools/harness-minimo/coletar-metricas.sh — o COLETOR de métricas por run (ordem 077, seção 4).
#
# Devolve UM objeto JSON com SÓ inteiros (custo em centavos; nada de float) e a palavra
# "ausente" onde a fonte não existe: ausente fica ausente, nunca zero. O agente não se avalia:
# o aceite e as regressões vêm de números que o APARELHO mediu por fora; aqui só se juntam.
#
# Fontes (todas opcionais; sem a flag, o campo sai "ausente"):
#   --stream ARQ            saída de `claude -p --output-format stream-json` (um JSON por linha) ou
#                           de `--output-format json` (um JSON só): o `result` dá os quatro contadores
#                           de tokens, `total_cost_usd` e `num_turns`; as mensagens dão as chamadas
#                           de ferramenta e o uso do director_report.
#   --cotacao-milesimos N   BRL por USD ×1000 (5432 = R$ 5,432), registrada pelo aparelho no dia.
#   --aceite-rc N           rc do comando do recibo da ORDEM ORIGINAL, rodado por fora na árvore final.
#   --passavam-base ARQ     nomes (um por linha) dos testes que PASSAVAM na base.
#   --falham-fim ARQ        nomes (um por linha) dos testes que FALHAM no fim.
#   --parede-ms N           spawn → saída do `claude`.
#   --ponte-db ARQ --project P --order-ref R [--desde ISO] [--ate ISO]
#                           decisões da Ponte do run, lidas do ponte.db com mode=ro: permission,
#                           report e ask (kind `question`); espera = Σ (resolved_at − created_at).
#   --arvore DIR --base-commit H   arquivos/linhas tocados e commits, a partir da base.
#   --relancamentos N | --bloqueios-stop N | --humano-fora-da-ponte N   contagens que o lançador anota.
set -u

stream="" cot="" aceite="" passavam="" falham="" parede="" db="" proj="" oref="" desde="" ate=""
arvore="" basec="" relanc="" stopb="" humfora=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || { echo "coletar-metricas: flag '$1' sem valor" >&2; exit 2; }
  case "$1" in
    --stream) stream="$2" ;;
    --cotacao-milesimos) cot="$2" ;;
    --aceite-rc) aceite="$2" ;;
    --passavam-base) passavam="$2" ;;
    --falham-fim) falham="$2" ;;
    --parede-ms) parede="$2" ;;
    --ponte-db) db="$2" ;;
    --project) proj="$2" ;;
    --order-ref) oref="$2" ;;
    --desde) desde="$2" ;;
    --ate) ate="$2" ;;
    --arvore) arvore="$2" ;;
    --base-commit) basec="$2" ;;
    --relancamentos) relanc="$2" ;;
    --bloqueios-stop) stopb="$2" ;;
    --humano-fora-da-ponte) humfora="$2" ;;
    *) echo "coletar-metricas: flag desconhecida '$1'" >&2; exit 2 ;;
  esac
  shift 2
done
command -v jq >/dev/null || { echo "coletar-metricas: jq ausente" >&2; exit 2; }

AUS='"ausente"'
inteiro() { [[ "$2" =~ ^[0-9]+$ ]] || { echo "coletar-metricas: $1 deve ser inteiro (veio '$2')" >&2; exit 2; }; }
# valor → JSON: inteiro vira ele mesmo; vazio vira "ausente".
j() { if [[ -z "$1" ]]; then printf '%s' "$AUS"; else printf '%s' "$1"; fi; }
for par in "cotacao-milesimos:$cot" "aceite-rc:$aceite" "parede-ms:$parede" "relancamentos:$relanc" "bloqueios-stop:$stopb" "humano-fora-da-ponte:$humfora"; do
  [[ -z "${par#*:}" ]] || inteiro "${par%%:*}" "${par#*:}"
done

# ---- stream: tokens, custo, turnos, ferramentas ----
t_in="" t_out="" t_cr="" t_cc="" usd_c="" brl_c="" turnos="" ferr="" rep=""
if [[ -n "$stream" ]]; then
  [[ -f "$stream" ]] || { echo "coletar-metricas: stream '$stream' não existe" >&2; exit 2; }
  res=$(jq -sc '[.[] | select(type=="object" and .type=="result")] | last // empty' "$stream" 2>/dev/null)
  if [[ -n "$res" ]]; then
    campo() { jq -r "$1 | if . == null then \"\" else (floor|tostring) end" <<<"$res"; }
    t_in=$(campo '.usage.input_tokens');            t_out=$(campo '.usage.output_tokens')
    t_cr=$(campo '.usage.cache_read_input_tokens'); t_cc=$(campo '.usage.cache_creation_input_tokens')
    turnos=$(campo '.num_turns')
    usd_c=$(jq -r 'if .total_cost_usd == null then "" else ((.total_cost_usd * 100) | round | tostring) end' <<<"$res")
    if [[ -n "$cot" ]]; then
      brl_c=$(jq -r --argjson c "$cot" 'if .total_cost_usd == null then "" else ((.total_cost_usd * $c / 10) | round | tostring) end' <<<"$res")
    fi
  fi
  ferr=$(jq -sc '[.[] | select(type=="object" and .type=="assistant") | .message.content[]? | select(.type=="tool_use")] | length' "$stream" 2>/dev/null)
  rep=$(jq -sc '[.[] | select(type=="object" and .type=="assistant") | .message.content[]? | select(.type=="tool_use" and ((.name // "") | test("director_report$|director[.]report$")))] | length' "$stream" 2>/dev/null)
fi

# ---- regressões: passavam na base ∩ falham no fim ----
reg='"ausente"'
if [[ -n "$passavam" && -n "$falham" ]]; then
  [[ -f "$passavam" && -f "$falham" ]] || { echo "coletar-metricas: lista de testes não existe" >&2; exit 2; }
  nomes=$(comm -12 <(sort -u "$passavam") <(sort -u "$falham") | jq -R . | jq -sc .)
  reg=$(jq -nc --argjson n "$nomes" '{contagem: ($n|length), nomes: $n}')
fi

# ---- Ponte: decisões do run (somente leitura) ----
interv='"ausente"'; espera=""
if [[ -n "$db" ]]; then
  [[ -f "$db" && -n "$proj" && -n "$oref" ]] || { echo "coletar-metricas: --ponte-db pede arquivo existente, --project e --order-ref" >&2; exit 2; }
  command -v sqlite3 >/dev/null || { echo "coletar-metricas: sqlite3 ausente" >&2; exit 2; }
  esc() { printf '%s' "${1//\'/\'\'}"; }
  filtro="project='$(esc "$proj")' AND order_ref='$(esc "$oref")' AND kind IN ('permission','report','question')"
  [[ -n "$desde" ]] && filtro="$filtro AND created_at >= '$(esc "$desde")'"
  [[ -n "$ate" ]] && filtro="$filtro AND created_at <= '$(esc "$ate")'"
  linhas=$(sqlite3 -readonly -separator '|' "file:${db}?mode=ro" \
    "SELECT kind, COUNT(*), SUM(CASE WHEN resolved_at IS NULL THEN 1 ELSE 0 END),
            COALESCE(SUM(CASE WHEN resolved_at IS NOT NULL THEN CAST(ROUND((julianday(resolved_at)-julianday(created_at))*86400000) AS INTEGER) ELSE 0 END),0)
       FROM decision WHERE $filtro GROUP BY kind;") || { echo "coletar-metricas: leitura do ponte.db falhou" >&2; exit 1; }
  p=0 r=0 a=0 sem=0 esp=0
  while IFS='|' read -r k n s w; do
    [[ -n "$k" ]] || continue
    case "$k" in permission) p=$n ;; report) r=$n ;; question) a=$n ;; esac
    sem=$((sem + s)); esp=$((esp + w))
  done <<<"$linhas"
  interv=$(jq -nc --argjson p "$p" --argjson r "$r" --argjson a "$a" --argjson s "$sem" \
    '{permission:$p, report:$r, ask:$a, total:($p+$r+$a), sem_resposta:$s}')
  espera=$esp
fi

# ---- árvore: arquivos, linhas, commits ----
arq="" lin="" commits=""
if [[ -n "$arvore" ]]; then
  [[ -n "$basec" ]] || { echo "coletar-metricas: --arvore pede --base-commit" >&2; exit 2; }
  git -C "$arvore" add -A -N 2>/dev/null
  num=$(git -C "$arvore" diff --numstat "$basec" 2>/dev/null) || num=""
  arq=$(printf '%s\n' "$num" | awk 'NF{n++} END{print n+0}')
  lin=$(printf '%s\n' "$num" | awk 'NF && $1 != "-"{s+=$1+$2} END{print s+0}')
  commits=$(git -C "$arvore" rev-list --count "${basec}..HEAD" 2>/dev/null)
fi

jq -nc \
  --argjson aceite "$(j "$([[ -n "$aceite" ]] && { [[ "$aceite" == 0 ]] && echo 1 || echo 0; })")" \
  --argjson regressoes "$reg" \
  --argjson parede "$(j "$parede")" \
  --argjson espera "$(j "$espera")" \
  --argjson tin "$(j "$t_in")" --argjson tout "$(j "$t_out")" --argjson tcr "$(j "$t_cr")" --argjson tcc "$(j "$t_cc")" \
  --argjson usd "$(j "$usd_c")" --argjson brl "$(j "$brl_c")" \
  --argjson interv "$interv" --argjson humfora "$(j "$humfora")" --argjson stopb "$(j "$stopb")" \
  --argjson ferr "$(j "$ferr")" --argjson turnos "$(j "$turnos")" --argjson rep "$(j "$rep")" \
  --argjson arq "$(j "$arq")" --argjson lin "$(j "$lin")" --argjson commits "$(j "$commits")" \
  --argjson relanc "$(j "$relanc")" \
  '{aceite:$aceite, regressoes:$regressoes, parede_ms:$parede, espera_humano_ms:$espera,
    tokens:{entrada:$tin, saida:$tout, cache_leitura:$tcr, cache_criacao:$tcc},
    custo:{usd_centavos:$usd, brl_centavos:$brl},
    intervencoes:{ponte:$interv, humano_fora_da_ponte:$humfora, bloqueios_stop:$stopb},
    extras:{chamadas_ferramenta:$ferr, turnos_modelo:$turnos, uso_director_report:$rep,
            arquivos_tocados:$arq, linhas_tocadas:$lin, commits:$commits, relancamentos:$relanc}}'
