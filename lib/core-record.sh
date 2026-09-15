#!/usr/bin/env bash
# maestro lib/core-record.sh — API_SPEC §1/§2 + DATA_MODEL §3, extraído de
# bin/maestro na ordem 010 (E24, ledger e record).
#
# DONO da leitura/validação do decision record: idade/expiração (fonte de
# verdade `expires_at`, fallback mtime — review P2-3) e schema DATA_MODEL §3
# (via `RECORD_FIELDS`, que continua em bin/maestro — CONTRATO consumido por
# cinco repositórios, fora do escopo desta ordem). `check_records` é o que o
# `doctor` chama para validar e limpar TTL; nada aqui muda formato de campo,
# evento ou rótulo.
#
# Sourced por bin/maestro (via _record_lib_load, I-2) DENTRO do mesmo
# processo — nenhum fork. `now_epoch` (fallback de `date +%s` sem
# hooks/lib/common.sh, deliberado: o doctor precisa funcionar mesmo sem a lib
# de hooks) continua em bin/maestro porque `check_habits_debt` também depende
# dela e roda ANTES deste módulo ser carregado — RECORD_FIELDS, MAESTRO_HOME,
# MAESTRO_TTL_SECONDS, now_epoch, report, has e join_semi já no escopo.
# Convenção (firmada no lote do `order`, E24): parâmetro posicional, nenhuma
# função fecha sobre local de outra.

record_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0\n'
}

record_expired() { # 0 = expirado; fonte de verdade expires_at, fallback mtime (review P2-3)
  local f="$1" exp='' epoch now
  now=$(now_epoch)
  if has jq; then exp=$(jq -r '.expires_at // empty' "$f" 2>/dev/null || true); fi
  if [[ -n "$exp" ]] && epoch=$(date -d "$exp" +%s 2>/dev/null); then
    [[ $now -ge $epoch ]]
  else
    [[ $((now - $(record_mtime "$f"))) -ge $MAESTRO_TTL_SECONDS ]]
  fi
}

record_schema_ok() { # DATA_MODEL §3, sem campos extras
  local f="$1"
  jq -e --arg fields "$RECORD_FIELDS" '
    (type == "object")
    and (.session_id  | type == "string") and (.session_id | length > 0)
    and (.ts          | type == "string")
    and (.expires_at  | type == "string")
    and (.workflow    | type == "string")
    and (.mode as $m | ["direct","subagent","multi"] | index($m) != null)
    and ((keys - ($fields | split(" "))) | length == 0)
    and (((.reason // "") | length) <= 120)
    and (if has("agents") then (.agents | type == "array") else true end)
    and (if has("wtree") then (.wtree | type == "string" and test("^[0-9a-f]{40}$")) else true end)
    and (if has("outcome") then (.outcome as $o | ["accepted","rework","reverted","killed"] | index($o) != null) else true end)
    and (if has("outcome_ts") then (.outcome_ts | type == "string") else true end)
    and (if has("suite") then (.suite as $s | ["pass","fail"] | index($s) != null) else true end)
    and (if (has("outcome_ts") or has("suite")) then has("outcome") else true end)
    and (if has("kill_reason") then ((.outcome // "") == "killed"
      and (.kill_reason | type == "string" and length > 0 and length <= 120)) else true end)
    and (if (.outcome // "") == "killed" then has("kill_reason") else true end)
    and (if has("budget") then (.budget | type == "object"
      and ((keys - ["steps","minutes","cents"]) | length == 0)
      and (all(.[]; type == "number" and . == floor and . >= 1))) else true end)
    and (if has("suite_evidence") then (.suite_evidence as $e | ["cited","none"] | index($e) != null) else true end)
    and (if has("delegation_proof") then (has("outcome") and (.delegation_proof as $d | ["started","none"] | index($d) != null)) else true end)
    and (if has("verifications") then (has("outcome") and (.verifications as $v | ["cited","missing"] | index($v) != null)) else true end)
    and (if has("depth") then (.depth as $d | ["standard","deep","day-zero"] | index($d) != null) else true end)
    and (if has("profile") then (.profile as $p | ["prototipo","piloto","produto"] | index($p) != null) else true end)
    and (has("profile") == ((.depth // "") == "day-zero"))
    and (if has("brief") then (.brief | type == "string" and length <= 700
      and test("essencia:") and test("impacto:") and test("approach:")) else true end)
    and (if has("flags") then (.flags | type == "array"
      and all(.[]; type == "object"
        and ((keys - ["sev","decisao","tradeoff","mitigacao"]) | length == 0)
        and (all(.[]; type == "string" and length <= 120))
        and (if has("sev") then (.sev as $s | ["critical","high","medium","low"] | index($s) != null) else true end)))
      else true end)
  ' "$f" >/dev/null 2>&1
}

check_records() { # API_SPEC §1/§2 + DATA_MODEL §3: doctor valida schema e limpa TTL
  local dir="$MAESTRO_HOME/sessions"
  if [[ ! -d "$dir" ]]; then
    report ok "decision records: nenhum diretório de sessões ainda"
    return
  fi
  shopt -s nullglob
  local files=("$dir"/*.json)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    report ok "decision records: nenhum registrado"
    return
  fi
  if ! has jq; then
    report skip "decision records: schema DATA_MODEL §3" "requer jq (${#files[@]} record(s) não verificados)"
    return
  fi
  local kept=0 removed=0 bad=() pending=() f sid
  for f in "${files[@]}"; do
    if record_expired "$f"; then
      rm -f "$f" && removed=$((removed + 1))
      continue
    fi
    if record_schema_ok "$f"; then
      kept=$((kept + 1))
      # E17/S-1702: outcome fechado com o approach do brief ainda pendente é
      # sinal de regência incompleta — nunca falha o doctor, só avisa.
      # E25/S-2501: `killed` fica de fora — cobrar o approach de quem descartou é
      # pedir o plano de execução do que se decidiu não executar, e o kill de
      # feature quase sempre tem o approach pendente (é por isso que se mata).
      if jq -e '(has("outcome")) and (.outcome != "killed")
                and ((.brief // "") | contains("approach: pendente"))' \
           "$f" >/dev/null 2>&1; then
        pending+=("$(basename -- "$f")")
      fi
    else
      bad+=("$(basename -- "$f")")
    fi
  done
  if [[ ${#bad[@]} -gt 0 ]]; then
    report fail_val "decision records: schema DATA_MODEL §3" \
      "inválido(s): ${bad[*]} (fix: remova o(s) arquivo(s) em \$MAESTRO_HOME/sessions)"
  else
    report ok "decision records: $kept válido(s), $removed expirado(s) removido(s)"
  fi
  for f in "${pending[@]}"; do
    sid="${f%.json}"
    report warn "record $sid: outcome registrado com approach pendente (rode maestro conduct --approach)"
  done
}
