#!/usr/bin/env bash
# ordem 016 PR1 — tests/lib/latency.sh:maestro_latency_probe.
#
# O que se prova aqui NÃO é "a sonda vale X ms" (o valor é da máquina, varia
# por definição — é o que a ordem existe para medir). O que se prova é que a
# sonda É MEDIDA pelo caminho certo: N invocações reais do binário passado,
# cada uma com MAESTRO_OFF=1 no ambiente (o caminho do kill-switch), e que o
# resultado (PROBE_MS) é um inteiro não-negativo — nunca float (CLAUDE.md).
#
# Determinismo sem depender da velocidade desta máquina: em vez de medir o
# hook real e checar um número, o "hook" é um STUB que GRAVA num arquivo
# toda vez que é chamado com MAESTRO_OFF=1 — contar as linhas desse arquivo
# prova que a função chamou o binário exatamente N vezes pelo caminho do
# kill-switch, sem depender de quão rápida é a máquina.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/tests/lib/latency.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- stub: só grava "off" quando chamado com MAESTRO_OFF=1; senão sai 1 -----
CNT_FILE="$tmp/off-count"
: > "$CNT_FILE"
STUB="$tmp/stub-hook.sh"
cat > "$STUB" <<EOF
#!/usr/bin/env bash
if [[ "\${MAESTRO_OFF:-0}" == "1" ]]; then
  printf 'off\n' >> "$CNT_FILE"
  exit 0
fi
exit 1
EOF
chmod +x "$STUB"

echo "-- maestro_latency_probe: N invocações pelo caminho do kill-switch"
MAESTRO_LATENCY_PROBE_N=5
maestro_latency_probe "$STUB"
n_off=$(wc -l < "$CNT_FILE" | tr -d ' ')
if [[ "$n_off" == "5" ]]; then
  ok "chamou o stub 5x, todas com MAESTRO_OFF=1 (caminho do kill-switch)"
else
  bad "esperava 5 chamadas com MAESTRO_OFF=1, contei $n_off"
fi
if [[ "$PROBE_MS" =~ ^[0-9]+$ ]]; then
  ok "PROBE_MS é inteiro não-negativo ($PROBE_MS) — nenhum float (CLAUDE.md)"
else
  bad "PROBE_MS não é inteiro: '$PROBE_MS'"
fi

echo "-- maestro_latency_probe: default N=11 quando não sobrescrito"
: > "$CNT_FILE"
( unset MAESTRO_LATENCY_PROBE_N
  # shellcheck source=tests/lib/latency.sh
  source "$REPO/tests/lib/latency.sh"
  maestro_latency_probe "$STUB" )
n_off=$(wc -l < "$CNT_FILE" | tr -d ' ')
[[ "$n_off" == "11" ]] && ok "default N=11 (sem override)" || bad "default esperava 11, contei $n_off"

echo "-- maestro_latency_probe: se o binário nunca honra MAESTRO_OFF, cada chamada falha, mas a função não trava"
FAILBIN="$tmp/fail-hook.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAILBIN"
chmod +x "$FAILBIN"
MAESTRO_LATENCY_PROBE_N=3 maestro_latency_probe "$FAILBIN"
[[ "$PROBE_MS" =~ ^[0-9]+$ ]] && ok "PROBE_MS continua inteiro mesmo com binário que sempre falha ($PROBE_MS)" \
  || bad "PROBE_MS quebrou com binário que falha: '$PROBE_MS'"

echo "-- maestro_latency_report: a sonda aparece impressa ao lado do que já se imprime"
MAESTRO_LATENCY_PROBE_N=3
maestro_latency_probe "$STUB"
maestro_latency_read_load
out=$(maestro_latency_report "caso-fake" 10 20 30 50)
if grep -qE "sonda ${PROBE_MS}ms" <<<"$out"; then
  ok "relatório imprime 'sonda ${PROBE_MS}ms' ao lado de min/mediana/max/teto/load"
else
  bad "relatório não imprime a sonda (saída: $out)"
fi
grep -q "load ${MAESTRO_LATENCY_LOAD1M}/${MAESTRO_LATENCY_NCPU} CPUs" <<<"$out" \
  && ok "load continua impresso ao lado (não regrediu)" || bad "load sumiu do relatório"

exit $fail
