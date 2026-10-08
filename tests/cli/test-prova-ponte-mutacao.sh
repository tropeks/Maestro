#!/usr/bin/env bash
# Ordem 076 / turno 2: vermelho REAL por mutacao de controle do verificador.
# O mesmo teste do impostor roda contra (a) o verificador que CONFIA no campo `de`
# da mensagem (mutante) e (b) o verificador de verdade. Passa quando o mutante
# deixa o teste VERMELHO com impostores aceitos > 0 e o real o deixa VERDE com 0.
# Sem a mutacao vermelha, o teste do impostor nao provaria nada.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTE="$ROOT/tests/cli/test-prova-ponte-verificador.sh"
MUTANTE="$ROOT/tools/prova-ponte-mods/peer-verifier-mutante-de"

fail=0
FAIL() { echo "FAIL: $*"; fail=1; }

aceitas_de() { # saida -> N de "aceitas=N" (so a linha de resumo)
  local linha
  linha=$(grep -E '^trocas_ok=' <<<"$1" | head -n 1)
  [[ $linha =~ \ aceitas=([0-9]+) ]] && echo "${BASH_REMATCH[1]}" || echo -1
}

[[ -x $MUTANTE || -f $MUTANTE ]] || { FAIL "mutante ausente"; exit 1; }

saida_mut=$(PROVA_VERIF="$MUTANTE" bash "$TESTE" 2>&1)
rc_mut=$?
n_mut=$(aceitas_de "$saida_mut")
saida_real=$(bash "$TESTE" 2>&1)
rc_real=$?
n_real=$(aceitas_de "$saida_real")

echo "verificador | rc | impostores_aceitos"
echo "mutante(de) | $rc_mut | $n_mut"
echo "real        | $rc_real | $n_real"

(( rc_mut != 0 )) || FAIL "mutante nao deixou o teste vermelho (rc=$rc_mut)"
(( n_mut > 0 )) || FAIL "mutante nao teve impostor aceito ($n_mut)"
(( rc_real == 0 )) || FAIL "verificador real nao ficou verde (rc=$rc_real)"
(( n_real == 0 )) || FAIL "verificador real aceitou impostor ($n_real)"

if (( fail == 0 )); then echo "PASS: mutacao do verificador (mutante vermelho, real verde)"; fi
exit $fail
