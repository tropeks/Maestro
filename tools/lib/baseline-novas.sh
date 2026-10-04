# tools/lib/baseline-novas.sh — métricas 7, 8 e 9 do painel (ordem 063, turno 2).
# Sourced por tools/baseline.sh depois de FIN, falha(), jarr(), field(), TARGETS, UNRES, ORDERS_JSON,
# PDB, CORTE, HOME_M, ledger_motivo, git_ok e pname/key. Só define funções.
# SOMENTE LEITURA: ponte.db aberto com sqlite3 -readonly, git log, recibos do ledger.
#
# Mapa das fontes (nada aqui cria log novo; fonte que falta é FALHA nomeada, nunca estimativa):
#   7 ações do Capitão  = ponte.db decision WHERE origin='spock' (são os captain_ask)
#                         + git: commits que tocam hooks/ bin/ lib/ src/ .claude-plugin/plugin.json
#                         (só o Capitão aplica patch ali). Contagem; o painel não tem tempo do Capitão.
#   8 retrabalho        = turnos devolvidos      → ponte.db director_inbox.state='returned'
#                         turnos sem relato      → ponte.db manager_run terminal (failed, cancelled, teto)
#                                                  sem manager_event review_requested/completed do run
#                         recibos regravados     → ledger evidence/<chave>-order-<n>, campo regravacoes
#   9 custo por ordem   → ledger evidence/<chave>-order-<n>, campo tokens ou custo_centavos (inteiro)

PROT_PATHS=(hooks bin lib src .claude-plugin/plugin.json)

# ponte_q <sql> → array JSON em stdout; rc≠0 se a consulta somente-leitura falhar
ponte_q() {
  local o
  o=$(sqlite3 -readonly -json "file:$PDB?mode=ro" "$1" 2>/dev/null) || return 1
  if [[ -n "$o" ]]; then printf '%s\n' "$o"; else echo '[]'; fi
}

# ponte_pre: motivo de a Ponte não ser consultável (vazio = ok)
ponte_pre() {
  if [[ ! -r "$PDB" ]]; then echo "banco ausente ou ilegível"
  elif ! command -v sqlite3 >/dev/null; then echo "sqlite3 ausente (necessário para ler a Ponte)"; fi
}

# slug de projeto da Ponte a partir de um rótulo (nome do diretório ou chave do ledger sem o hash)
slug_de() { local s="${1,,}"; echo "${s//_/-}"; }

# Programa jq comum: lado pelo epoch e número da ordem de "order/NNN-…" ou "feat(NNN): …"
NOVAS_DEFS='
  def lado: if . <= $corte then "antes" else "depois" end;
  def nref: (capture("^order/0*(?<n>[0-9]+)")? // null) | if . == null then null else (.n|tonumber) end;
  def nsubj: (capture("^[a-z]+\\(0*(?<n>[0-9]+)\\)")? // null) | if . == null then null else (.n|tonumber) end;
  def conta($s): map(select(.lado==$s)) | length;'

m7_acoes_capitao() { # → JSON da métrica 7
  local f=() spock='[]' git_rows=() pre t lbl r sl rows pf7=""
  pre=$(ponte_pre)
  if [[ -n "$pre" ]]; then
    f+=("$(falha "ponte.db" "$pre")")
  else
    [[ $all -eq 0 ]] && { pf7="AND project = '$(slug_de "$pname")'"; pf7="${pf7//[^a-zA-Z0-9_ =\'.-]/}"; }
    if ! spock=$(ponte_q "SELECT project, order_ref, CAST(strftime('%s', created_at) AS INTEGER) AS ts FROM decision WHERE origin='spock' $pf7"); then
      spock='[]'
      f+=("$(falha "ponte.db (tabela decision, coluna origin)" "consulta somente-leitura falhou: banco, tabela decision ou coluna origin ausente/ilegível")")
    fi
  fi
  local gok=0
  for t in "${TARGETS[@]}"; do
    lbl="${t%%|*}"; r="${t#*|}"
    if git_ok "$r"; then
      sl=$(slug_de "$lbl"); [[ $all -eq 1 ]] && sl=$(slug_de "${lbl%-*}") || sl=$(slug_de "$pname")
      rows=$(git -C "$r" log --all --format='%ct%x09%s' -- "${PROT_PATHS[@]}" 2>/dev/null | jq -Rsc --arg p "$sl" \
        'split("\n") | map(select(length>0) | split("\t") | {projeto:$p, ts:(.[0]|tonumber), subj:(.[1:]|join("\t"))})') \
        && { git_rows+=("$rows"); gok=$((gok+1)); } \
        || f+=("$(falha "git ($lbl)" "git log em caminhos protegidos falhou")")
    else
      f+=("$(falha "git ($lbl)" "repo ilegível ou não é um repositório git")")
    fi
  done
  f+=("${UNRES[@]}")
  local commits; commits=$(jarr "${git_rows[@]}" | jq -c 'add // []')
  jq -nc --argjson corte "$CORTE" --argjson sp "$spock" --argjson cm "$commits" --argjson f "$(jarr "${f[@]}")" \
    --argjson pontes "$([[ -z "$pre" ]] && echo true || echo false)" --argjson gok "$gok" "$FIN$NOVAS_DEFS"'
    ( ($sp | map({fonte:"ponte", projeto:.project, ordem:(.order_ref // "" | nref), lado:(.ts|lado)}))
    + ($cm | map({fonte:"git", projeto, ordem:(.subj|nsubj), lado:(.ts|lado)})) ) as $a
    | def tot($s): ($a|map(select(.lado==$s and .fonte=="ponte"))|length) as $p
        | ($a|map(select(.lado==$s and .fonte=="git"))|length) as $g | {ponte:$p, git:$g, total:($p+$g)};
    { id:7, nome:"ações do Capitão (contagem de decisões spock e commits em caminhos protegidos)",
      status:(if ($a|length)==0 then "sem dado" else "ok" end),
      fonte:"ponte.db decision.origin=spock + git log em hooks/ bin/ lib/ src/ .claude-plugin/plugin.json",
      antes:tot("antes"), depois:tot("depois"),
      por_ordem:($a | map(select(.ordem != null)) | group_by([.projeto, .ordem])
        | map({projeto:.[0].projeto, ordem:.[0].ordem,
               ponte:(map(select(.fonte=="ponte"))|length), git:(map(select(.fonte=="git"))|length), total:length})),
      sem_ordem:{ponte:($a|map(select(.ordem==null and .fonte=="ponte"))|length), git:($a|map(select(.ordem==null and .fonte=="git"))|length)} }
    | if .status=="sem dado" then {id, nome, status, motivo:"fontes legíveis, nenhuma ação do Capitão registrada"} else . end
    | fin($f; ($pontes or $gok>0) and ($a|length)>0)'
}

# população com recibo: [{projeto, ordem, lado, regravacoes, tokens, centavos}] (null = campo ausente ou não inteiro)
recibos_json() {
  local rows=() k id ac lado ev v rg tk ce
  while IFS=$'\t' read -r k id ac; do
    [[ -n "$id" ]] || continue
    ev="$HOME_M/evidence/$k-order-$id"
    rg=null tk=null ce=null
    if [[ -f "$ev" ]]; then
      v=$(field "$ev" regravacoes); [[ "$v" =~ ^[0-9]+$ ]] && rg=$((10#$v))
      v=$(field "$ev" tokens); [[ "$v" =~ ^[0-9]+$ ]] && tk=$((10#$v))
      v=$(field "$ev" custo_centavos); [[ "$v" =~ ^[0-9]+$ ]] && ce=$((10#$v))
    fi
    lado=depois; [[ "$ac" -le "$CORTE" ]] && lado=antes
    rows+=("$(jq -nc --arg p "$k" --argjson o "$id" --arg l "$lado" --argjson rg "$rg" --argjson tk "$tk" --argjson ce "$ce" \
      '{projeto:$p, ordem:$o, lado:$l, regravacoes:$rg, tokens:$tk, centavos:$ce}')")
  done < <(jq -r --arg k "$key" '.[] | select((.aceita|type)=="number") | [(.projeto // $k), .id, .aceita] | @tsv' <<<"$ORDERS_JSON")
  jarr "${rows[@]}"
}

m8_retrabalho() { # → JSON da métrica 8
  local f=() pre dev='[]' sr='[]' rec='[]' dev_ok=0 sr_ok=0 rec_ok=0 pfr=""
  pre=$(ponte_pre)
  if [[ -n "$pre" ]]; then
    f+=("$(falha "ponte.db (director_inbox, manager_run, manager_event)" "$pre")")
  else
    [[ $all -eq 0 ]] && { pfr="AND r.project = '$(slug_de "$pname")'"; pfr="${pfr//[^a-zA-Z0-9_ =\'.-]/}"; }
    if dev=$(ponte_q "SELECT ref_kind, ref_id, CAST(strftime('%s', created_at) AS INTEGER) AS ts FROM director_inbox WHERE state='returned'"); then dev_ok=1
    else dev='[]'; f+=("$(falha "ponte.db (tabela director_inbox, coluna state)" "consulta somente-leitura falhou: tabela ou coluna ausente/ilegível")"); fi
    if sr=$(ponte_q "SELECT r.project, r.order_ref, CAST(strftime('%s', r.created_at) AS INTEGER) AS ts FROM manager_run r WHERE r.state IN ('failed','cancelled','teto') $pfr AND NOT EXISTS (SELECT 1 FROM manager_event e WHERE e.run_id = r.run_id AND e.type IN ('manager.review_requested','manager.completed'))"); then sr_ok=1
    else sr='[]'; f+=("$(falha "ponte.db (tabelas manager_run e manager_event)" "consulta somente-leitura falhou: tabela ou coluna ausente/ilegível")"); fi
  fi
  if [[ -n "$ledger_motivo" ]]; then
    f+=("$(falha "ledger (evidence)" "$ledger_motivo")")
  else
    rec=$(recibos_json); rec_ok=1
    local faltam; faltam=$(jq -r '[.[] | select(.regravacoes==null) | "\(.projeto)-order-\(.ordem)"] | join(", ")' <<<"$rec")
    if [[ -n "$faltam" ]]; then
      rec_ok=0
      f+=("$(falha "ledger evidence/<chave>-order-<n> (campo regravacoes)" "recibo sem o campo regravacoes inteiro: $faltam; o recibo é sobrescrito e nenhum evento guarda a regravação (proposta: maestro evidence --record incrementa regravacoes=N no mesmo rótulo)")")
    fi
  fi
  f+=("${UNRES[@]}")
  jq -nc --argjson corte "$CORTE" --argjson dev "$dev" --argjson sr "$sr" --argjson rec "$rec" \
    --argjson dok "$dev_ok" --argjson sok "$sr_ok" --argjson rok "$rec_ok" --argjson npop "$(jq 'length' <<<"$rec")" \
    --argjson f "$(jarr "${f[@]}")" "$FIN$NOVAS_DEFS"'
    def sub_($ok; $rows; $ref): if $ok==0 then {status:"FALHA"}
      else ($rows|length) as $n | {status:(if $n==0 then "sem dado" else "ok" end), antes:($rows|conta("antes")), depois:($rows|conta("depois")),
        por_ordem:($rows | map(select(.ordem != null)) | group_by(.ordem) | map({ordem:.[0].ordem, n:length}))} end;
    ($dev | map({lado:(.ts|lado), ordem:(if .ref_kind=="order" then (.ref_id // "" | nref) else null end)})) as $d
    | ($sr | map({lado:(.ts|lado), ordem:(.order_ref // "" | nref)})) as $s
    | ($rec | map(select(.regravacoes != null))) as $rg
    | { id:8, nome:"retrabalho (turnos devolvidos, turnos sem relato, recibos regravados)",
        status:"ok",
        fonte:"ponte.db director_inbox/manager_run/manager_event + ledger evidence",
        turnos_devolvidos:(sub_($dok; $d; null) + {nota:"director_inbox.state=returned; a tabela não tem projeto: vale a Ponte inteira"}),
        turnos_sem_relato:sub_($sok; $s; null),
        recibos_regravados:(if $rok==0 and ($npop>0) then {status:"FALHA", nota:"sem contagem: ordens da população sem o campo regravacoes (ver falhas); nenhum zero no lugar de ausência"}
          elif $npop==0 then {status:"sem dado"}
          else {status:"ok", antes:($rg|map(select(.lado=="antes")|.regravacoes)|add // 0), depois:($rg|map(select(.lado=="depois")|.regravacoes)|add // 0),
                por_ordem:($rg|map({ordem, n:.regravacoes}))} end) }
    | fin($f; ($dok+$sok+$rok)>0)'
}

m9_custo() { # → JSON da métrica 9
  local f=() rec='[]'
  if [[ -n "$ledger_motivo" ]]; then
    f+=("$(falha "ledger (evidence)" "$ledger_motivo")")
  else
    rec=$(recibos_json)
    local faltam; faltam=$(jq -r '[.[] | select(.tokens==null and .centavos==null) | "\(.projeto)-order-\(.ordem)"] | join(", ")' <<<"$rec")
    [[ -n "$faltam" ]] && f+=("$(falha "ledger evidence/<chave>-order-<n> (campo tokens ou custo_centavos)" "nenhum custo inteiro registrado para: $faltam; nenhuma telemetria local guarda custo por ordem (proposta: maestro evidence --record grava tokens=N ou custo_centavos=N)")")
  fi
  f+=("${UNRES[@]}")
  jq -nc --argjson rec "$rec" --argjson f "$(jarr "${f[@]}")" "$FIN"'
    ($rec | map(select(.tokens != null or .centavos != null))) as $c
    | { id:9, nome:"custo por ordem (inteiros)",
        status:(if ($rec|length)==0 then "sem dado" else "ok" end),
        fonte:"ledger evidence/<chave>-order-<n>, campos tokens ou custo_centavos",
        por_ordem:($c | map({projeto, ordem, lado, tokens, centavos})),
        total_tokens_antes:($c|map(select(.lado=="antes")|.tokens // 0)|add // 0),
        total_tokens_depois:($c|map(select(.lado=="depois")|.tokens // 0)|add // 0),
        total_centavos_antes:($c|map(select(.lado=="antes")|.centavos // 0)|add // 0),
        total_centavos_depois:($c|map(select(.lado=="depois")|.centavos // 0)|add // 0) }
    | if .status=="sem dado" then {id, nome, status, motivo:"ledger legível, nenhuma ordem na população"} else . end
    | fin($f; ($c|length)>0)'
}
