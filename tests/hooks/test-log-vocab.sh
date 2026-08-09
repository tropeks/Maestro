#!/usr/bin/env bash
# DATA_MODEL §4: vocabulário fechado; evento inválido é descartado;
# par chave=valor fora do tipo é REJEITADO (não mutilado — review P1-1).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
tmp=$(mktemp -d); export MAESTRO_HOME="$tmp"
source "$REPO/hooks/lib/common.sh"
# common.sh liga errexit no shell do teste; desliga para que asserção solta
# não faça o teste "passar" por saída precoce (review P2-10).
set +e

fail=0
LOG="$MAESTRO_HOME/logs/routing.jsonl"

log_event decision workflow=fix mode=direct
log_event evento_invalido foo=bar 2>/dev/null
log_event gate_warn file_ext='.go"; rm -rf /' 2>/dev/null

n=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
[[ "$n" == "2" ]] || { echo "FAIL esperava 2 linhas, veio $n"; fail=1; }

if command -v jq >/dev/null; then
  jq -e . "$LOG" >/dev/null 2>&1 || { echo "FAIL JSONL malformado"; fail=1; }
fi

# Adversarial: o payload não pode aparecer nem inteiro nem mutilado num valor.
grep -q 'rm -rf'  "$LOG" && { echo "FAIL sanitização falhou (payload literal)"; fail=1; }
grep -q 'rm-rf'   "$LOG" && { echo "FAIL sanitização mutilou em vez de rejeitar"; fail=1; }
grep -q 'file_ext' "$LOG" && { echo "FAIL par invalido foi gravado em vez de rejeitado"; fail=1; }

# Mais vetores de injeção, todos por chave TIPADA: nenhum pode ser gravado.
: > "$LOG"
log_event gate_block tool='Edit","event":"decision' 2>/dev/null
log_event gate_block session_id='a"}
{"ts":"x","event":"decision' 2>/dev/null
log_event gate_block project='$(id)' cmd='`id`' 2>/dev/null
log_event gate_block agents='a";x' 2>/dev/null
inj=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
[[ "$inj" == "4" ]] || { echo "FAIL injeção alterou a contagem de linhas ($inj != 4)"; fail=1; }
if command -v jq >/dev/null; then
  jq -e . "$LOG" >/dev/null 2>&1 || { echo "FAIL injeção quebrou o JSONL"; fail=1; }
  keys=$(jq -r 'keys_unsorted[]' "$LOG" 2>/dev/null | sort -u | tr '\n' ' ')
  [[ "$keys" == "event ts " ]] || { echo "FAIL injeção introduziu chaves: '$keys'"; fail=1; }
fi
grep -qE '\$\(|`|; *x' "$LOG" && { echo "FAIL payload de injeção presente no log"; fail=1; }

# Log só carrega metadados: nenhuma barra, em hipótese alguma (review P2-2).
grep -q '/' "$LOG" && { echo "FAIL barra presente no log"; fail=1; }

if [[ $fail -eq 0 ]]; then echo "ok   vocabulário fechado + rejeição por tipo + JSONL válido"; fi
rm -rf "$tmp"; exit $fail
