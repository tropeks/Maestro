# tools/lib/baseline-ordens.sh — métrica 1 do painel (ordem 058; população e janela, ordem 063).
# Sourced por tools/baseline.sh, depois de FIN, HOME_M, SF e field(); só define funções e o jq.
# SOMENTE LEITURA: ledger (order-state, evidence) e git do repo.

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

# Programa jq da métrica 1: população (carimbo válido, sem legadas) e os dois lados do corte.
M1_JQ="$FIN"'
  def mediana: (length) as $n | (.[($n-1)/2|floor] + .[$n/2|floor]) / 2 | floor;
  def med($l): ($l|sort) as $v | if ($v|length)==0 then $sf else ($v|mediana) end;
  # intervalo negativo = marcos fora de ordem (recibo regravado, relógio): sem fonte, não número
  def d(a;b): if (a|type)=="number" and (b|type)=="number" and b >= a then (b-a) else $sf end;
  # recibo regravado depois do aceite (aceita < provada) não diz quando ficou pronta: sem fonte
  def pronta: if (.provada|type)!="number" then $sf
    elif (.aceita|type)=="number" then (if .aceita >= .provada then .aceita - .provada else $sf end)
    else $now - .provada end;
  def lado($s): [.ordens[]|select(.lado==$s)] as $o
    | [$o[]|select((.parada_em_pronta_s|type)=="number")|.parada_em_pronta_s] as $v
    | {n:($o|length), ids:($o|map(.id)), n_medida:($v|length), n_pequeno:(($v|length)<3),
       mediana_parada_em_pronta_s:med($v)};
  { id:1, nome:"idade por estado e tempo parado em pronta (segundos)",
    ordens: map(. + {
      idade_aberta_s: d(.aberta; .execucao),
      idade_execucao_s: d(.execucao; .provada),
      parada_em_pronta_s: pronta,
      legada_sem_carimbo: (.id <= 32 and ((.aceita|type)!="number")),
      populacao: ((.aceita|type)=="number") }
      | . + {lado: (if .populacao then (if .aceita <= $corte then "antes" else "depois" end) else "fora" end)}) }
  # ordens 1..32 sem carimbo de aceite válido: linha própria, fora da população
  | ([.ordens[]|select(.legada_sem_carimbo)|.id]) as $lg
  | .legadas_sem_carimbo = {quantidade:($lg|length), ids:$lg}
  | ([.ordens[] | select(.populacao and (.parada_em_pronta_s|type)=="number") | .parada_em_pronta_s]) as $v
  | .mediana_n = ($v|length)
  | .mediana_parada_em_pronta_s = med($v)
  | lado("antes") as $a | lado("depois") as $dp
  | .janela = {corte_epoch:$corte, corte_iso:$corteiso, regra:$regra, antes:$a, depois:$dp,
      comparacao:(if $a.n_pequeno or $dp.n_pequeno
        then "não comparado: N antes=\($a.n), N depois=\($dp.n) (medidas \($a.n_medida) e \($dp.n_medida)); mínimo 3 medidas de cada lado"
        else "comparado: mediana depois \($dp.mediana_parada_em_pronta_s) s, antes \($a.mediana_parada_em_pronta_s) s, diferença \($dp.mediana_parada_em_pronta_s - $a.mediana_parada_em_pronta_s) s" end)}
  | .status = (if (.ordens|length)==0 then "sem dado" else "ok" end)
  | if .status=="sem dado" then {id, nome, status, motivo:"ledger legível, nenhuma ordem registrada"} else . end
  | fin($f; (.status=="ok"))'
