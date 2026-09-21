#!/usr/bin/env bash
# ordem 036 — T1: compara o golden ANTES (tests/fixtures/order036-golden-BEFORE.json,
# capturado no código de HEAD, sem nenhuma linha desta ordem) contra o DEPOIS
# (recapturado com bash tests/fixtures/order036-golden-capture.sh, código
# desta ordem aplicado). Gatilho de reversão do §9 do desenho: para QUALQUER
# ordem SEM `work_project` (é o caso de TODAS as ~118 ordens reais desta
# máquina — nenhuma tinha o campo antes desta ordem), os campos
# estado/pede_aceite/terminal/suspensa/branch/branch_existe/direcao/
# verificacao têm de sair IDÊNTICOS. Ordem nova aparecida entre as duas
# capturas (outra sessão viva na máquina) não é regressão — compara só a
# INTERSEÇÃO de (proj,id).
set -u
command -v jq >/dev/null 2>&1 || { echo "PENDENTE  jq ausente — T1 exige jq"; exit 0; }
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BEFORE="$REPO/tests/fixtures/order036-golden-BEFORE.json"
AFTER="${1:-/tmp/order036-AFTER.json}"
[[ -f "$BEFORE" ]] || { echo "FAIL  $BEFORE ausente — rode a captura ANTES do changeset primeiro"; exit 1; }
[[ -f "$AFTER"  ]] || { echo "FAIL  $AFTER ausente — rode: bash tests/fixtures/order036-golden-capture.sh > $AFTER"; exit 1; }

fail=0
n_compared=0
while IFS=$'\t' read -r proj id before_campos; do
  after_campos=$(jq -c --arg proj "$proj" --arg id "$id" '.[] | select(.proj==$proj and .id==$id) | .campos' "$AFTER" 2>/dev/null)
  [[ -n "$after_campos" && "$after_campos" != "null" ]] || { echo "AVISO  $proj/$id sumiu do AFTER (outra sessão pode ter mexido) — pulando"; continue; }
  n_compared=$((n_compared+1))
  if [[ "$before_campos" == "$after_campos" ]]; then
    :
  else
    fail=1
    echo "FAIL  $proj/$id divergiu:"
    echo "  antes : $before_campos"
    echo "  depois: $after_campos"
  fi
done < <(jq -r '.[] | [.proj, .id, (.campos|tojson)] | @tsv' "$BEFORE")

echo "T1: $n_compared ordens comparadas (proj,id em interseção)"
if (( fail == 0 )); then
  echo "T1 golden: OK — nenhuma ordem sem work_project mudou estado/pede_aceite/terminal/suspensa/branch/branch_existe/direcao/verificacao"
else
  echo "T1 golden: FALHOU — ver divergências acima" >&2
fi
exit $fail
