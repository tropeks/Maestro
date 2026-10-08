#!/usr/bin/env bash
# Ordem 076 / turno 3: vermelho REAL por mutacao de controle do DIRETOR do mod.
# O mesmo teste do impostor (tools/prova-ponte-mods/maestro-prova/tests) roda contra
# (a) um Diretor que decide por `e.origin.plugin` (o nome que o remetente escreve) e
# (b) o Diretor de verdade. Passa quando o mutante deixa o teste VERMELHO com
# impostores aceitos > 0 e o real o deixa VERDE com 0.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MOD="$ROOT/tools/prova-ponte-mods/maestro-prova"
MUTAR="$ROOT/tools/prova-ponte-mods/mutar-diretor"

fail=0
FAIL() { echo "FAIL: $*"; fail=1; }

command -v claude >/dev/null 2>&1 || { echo "SKIP: claude ausente"; exit 0; }
[[ -f $MUTAR && -d $MOD ]] || { FAIL "mutador ou mod ausente"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

aceitos_de() { # saida -> N de "impostores_aceitos=N" (-1 se a linha nao apareceu)
  local linha
  linha=$(grep -o -E 'impostores_aceitos=[0-9]+' <<<"$1" | head -n 1)
  [[ $linha =~ =([0-9]+) ]] && echo "${BASH_REMATCH[1]}" || echo -1
}

python3 -I "$MUTAR" "$MOD" "$TMP/mutante" || { FAIL "mutador falhou"; exit 1; }

saida_mut=$(claude plugin test "$TMP/mutante" 2>&1)
rc_mut=$?
saida_real=$(claude plugin test "$MOD" 2>&1)
rc_real=$?
n_mut=$(aceitos_de "$saida_mut")
n_real=$(aceitos_de "$saida_real")
# O teste so imprime a contagem quando falha; verde = nenhuma linha = 0 aceitas.
(( rc_real == 0 && n_real == -1 )) && n_real=0

echo "diretor | rc | impostores_aceitos"
echo "mutante(origin.plugin) | $rc_mut | $n_mut"
echo "real                   | $rc_real | $n_real"

(( rc_mut != 0 )) || FAIL "mutante nao deixou o teste vermelho (rc=$rc_mut)"
(( n_mut > 0 )) || FAIL "mutante nao teve impostor aceito ($n_mut)"
(( rc_real == 0 )) || FAIL "Diretor real nao ficou verde (rc=$rc_real)"
(( n_real == 0 )) || FAIL "Diretor real aceitou impostor ($n_real)"

if (( fail != 0 )); then echo "-- saida do mutante:"; echo "$saida_mut"; fi
if (( fail == 0 )); then echo "PASS: mutacao do Diretor (mutante vermelho, real verde)"; fi
exit $fail
