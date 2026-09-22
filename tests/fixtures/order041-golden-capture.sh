#!/usr/bin/env bash
# ordem 041 — golden das ordens REAIS do Maestro em `--status --json`
# (estado/pede_aceite/terminal/suspensa), capturado ANTES de tocar em lib/ —
# mesmo padrão do golden T1 da ordem 036 (tests/fixtures/order036-golden-*),
# escopo reduzido ao projeto Maestro (é o único a que esta ordem se aplica —
# `.maestro.yaml`/MAESTRO_ACCEPT_REQUIRE_PROOF continuam DESLIGADOS por
# padrão em qualquer projeto que não opte, então o golden de outros projetos
# não é afetado, mas não há sessão de dogfood para capturá-los aqui).
#
# Uso:
#   bash tests/fixtures/order041-golden-capture.sh > tests/fixtures/order041-golden-BEFORE.json
#   (depois do changeset, comparar com tests/cli/test-order-041-golden.sh)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
PROJ="${MAESTRO_041_GOLDEN_PROJ:-$HOME/dev/Maestro}"

echo '['
first=1
if [[ -d "$PROJ/.maestro/orders" ]]; then
  shopt -s nullglob
  for f in "$PROJ"/.maestro/orders/*.md; do
    id=$(awk -F': ' 'NR>20{exit} $1=="id"{print $2; exit}' "$f" 2>/dev/null)
    [[ "$id" =~ ^[0-9]{1,3}$ ]] || continue
    n=$((10#$id))
    json=$("$BIN" order --status "$n" --project "$PROJ" --json 2>/dev/null)
    [[ -n "$json" ]] || { echo "AVISO: sem json para $id" >&2; continue; }
    reduced=$(jq -c '{estado, pede_aceite, terminal, suspensa}' <<<"$json" 2>/dev/null)
    [[ -n "$reduced" ]] || { echo "AVISO: json inválido para $id" >&2; continue; }
    (( first )) && first=0 || printf ','
    jq -c --arg id "$id" -n --argjson r "$reduced" '{id:$id, campos:$r}'
  done
  shopt -u nullglob
fi
echo ']'
