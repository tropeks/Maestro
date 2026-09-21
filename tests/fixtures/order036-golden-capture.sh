#!/usr/bin/env bash
# ordem 036 — T1: captura o snapshot golden de `--status --json` de TODAS as
# ordens reais desta máquina (8 projetos, ~118 ordens), usando o `bin/maestro`
# do WORKTREE mas o ~/.maestro (MAESTRO_HOME real, NÃO isolado) e os repos
# reais em ~/dev/<projeto> — leitura pura (order --status --json nunca
# escreve), então é seguro rodar antes E depois do changeset. NÃO faz parte
# de `tests/run-all.sh` (que isola MAESTRO_HOME de propósito): este é o
# gatilho de reversão manual do §9 do desenho da ordem 036, não um teste da
# suíte hermética.
#
# Uso:
#   bash tests/fixtures/order036-golden-capture.sh > tests/fixtures/order036-golden-BEFORE.json
#   (depois do changeset)
#   bash tests/fixtures/order036-golden-capture.sh > /tmp/order036-AFTER.json
#   diff via tests/cli/test-order-036-golden.sh (compara os dois)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

PROJECTS=(Maestro ponte-daemon ponte-app Agenda_Studio EduPACS Enterprise NetForge vitali)

echo '['
first=1
for p in "${PROJECTS[@]}"; do
  d="$HOME/dev/$p"
  [[ -d "$d/.maestro/orders" ]] || continue
  shopt -s nullglob
  for f in "$d"/.maestro/orders/*.md; do
    id=$(awk -F': ' 'NR>20{exit} $1=="id"{print $2; exit}' "$f" 2>/dev/null)
    [[ "$id" =~ ^[0-9]{1,3}$ ]] || continue
    n=$((10#$id))
    json=$("$BIN" order --status "$n" --project "$d" --json 2>/dev/null)
    [[ -n "$json" ]] || { echo "AVISO: sem json para $p/$id" >&2; continue; }
    # extrai só os campos que T1 exige idênticos (exclui `prova`, mudança ESPERADA)
    reduced=$(jq -c '{estado, pede_aceite, terminal, suspensa, branch, branch_existe, direcao, verificacao}' <<<"$json" 2>/dev/null)
    [[ -n "$reduced" ]] || { echo "AVISO: json inválido para $p/$id" >&2; continue; }
    (( first )) && first=0 || printf ','
    jq -c --arg proj "$p" --arg id "$id" -n --argjson r "$reduced" '{proj:$proj, id:$id, campos:$r}'
  done
  shopt -u nullglob
done
echo ']'
