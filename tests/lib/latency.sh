#!/usr/bin/env bash
# tests/lib/latency.sh — fonte ÚNICA do protocolo de medição de latência de
# hook usado por test-guarda-destrutiva.sh e test-gate.sh (o comentário do
# próprio código de ambos já dizia que compartilhavam o método; agora
# compartilham o arquivo).
#
# Causa (ordem 002/ponta 3): o critério de aprovação era o MÍNIMO de uma
# execução de N=31/25 amostras, escolhido como estimador do custo de código
# numa máquina compartilhada. Medido sob load 1.91→10 em 8 CPUs:
# `perigo(bloqueia)` deu min 57–71ms contra teto de 50ms; `rotina(passa)`
# oscilou de min 23ms para 37ms no MESMO código; o caso de 16KB estourou o
# próprio teto em 1 de 5. O mínimo se move com a carga — deixou de estimar o
# que se propunha.
#
# Por que MEDIANA SOZINHA NÃO BASTA: a mediana é MAIS sensível à carga que o
# mínimo, não menos — o mínimo aproxima o caso sem contenção, a mediana
# reflete a contenção típica. Sob load 10/8 CPUs, min ficou em 57–71ms mas a
# mediana subiu a 99–108ms, estourando até a guarda de regressão pré-existente
# (mediana < 2x orçamento). Por isso o critério novo é mediana + PORTÃO DE
# CARGA: acima de um limiar de carga por CPU, estouro de teto não é FAIL, é
# "inconclusivo sob carga" — a regra do diretor (medição inválida sem load ao
# lado; sob carga, o veredito nunca é regressão) virando código.
#
# O TETO EM SI DEPENDE DA CARGA — isto não é detalhe, é o que faz o NFR
# continuar sendo cobrado: a FOLGA existe para tolerar CONTENÇÃO, então só
# pode valer quando há contenção medida. Se a folga valesse sempre (inclusive
# em máquina quieta, como a CI), o teto de facto viraria 2x o orçamento em
# TODO lugar e o NFR de <50ms deixaria de ser cobrado em qualquer máquina —
# um hook que regredisse para perto de 2x o orçamento passaria "ok" até na CI
# quieta, onde não há carga nenhuma para culpar. Por isso:
#   carga por CPU ABAIXO do limiar (máquina quieta, o caso da CI) → teto =
#     orçamento, ESTRITO. Mediana acima disso é FAIL de verdade — sem carga
#     para culpar, é regressão de código, não de escalonamento.
#   carga por CPU ACIMA do limiar (forge) → teto = orçamento × FOLGA. Abaixo
#     disso é ok; acima é inconclusivo, nunca fail.
#
# Sourceável, não é enumerado como teste: "latency.sh" não casa com o glob
# `test-*.sh` que tests/run-all.sh usa em tests/hooks|lib|cli (mesmo
# precedente de tests/lib/env-clean.sh).
set -u

# --- N: amostras por caso ---------------------------------------------------
# Unificado em 31 — o maior dos dois valores pré-existentes (guarda-destrutiva
# já usava 31; gate usava 25). Mais amostras só estabilizam a mediana; o custo
# é uma invocação de hook a mais por amostra, irrelevante perto do tempo total
# da suíte. Override por ambiente previsto para depuração pontual.
: "${MAESTRO_LATENCY_N:=31}"

# --- FOLGA: teto da mediana SOB CARGA = orçamento × FOLGA -------------------
# NÃO é número novo: é a guarda de regressão que os dois testes já tinham
# (mediana < 2x orçamento), que já havia pego o bug do `${v#*pat}` custando
# 634ms no caminho de 22KB do gate. A ordem 002/ponta 3 promove essa guarda de
# "regressão" a CRITÉRIO DE APROVAÇÃO (no lugar do mínimo de 1 execução) — o
# número em si não muda, o papel dele muda. MAS só se aplica quando há
# contenção medida (maestro_latency_read_load acima do limiar); em máquina
# quieta o teto é o orçamento puro (ver maestro_latency_report).
: "${MAESTRO_LATENCY_FOLGA:=2}"

# --- limiar de carga por CPU, ×100 ------------------------------------------
# CLAUDE.md proíbe float em métrica; comparação em aritmética inteira de bash.
# /proc/loadavg sempre formata o load com 2 casas decimais no kernel Linux
# ("7.84"), então remover o ponto dá o valor ×100 direto ("784"); 1.00 de
# limiar vira 100. O valor 1.00 é a convenção clássica de administração Unix:
# load average == número de CPUs é 100% de utilização; abaixo disso a máquina
# não está saturada. Evidência da ordem 002: com load 1.91–4.08/8 CPUs
# (0.24–0.51 por CPU, ABAIXO do limiar) o MÍNIMO já não era confiável
# (57–71ms contra teto de 50ms) — por isso o critério muda para mediana. Com
# load ~10/8 CPUs (1.25 por CPU, ACIMA do limiar) a própria mediana subiu a
# 99–108ms, quase 2x o orçamento — acima do limiar a máquina está saturada e
# a medição deixa de estimar o custo do código. Override por ambiente é o que
# permite provar, em máquina carregada, que o portão ainda reprova latência
# de verdade quando a carga é forçada a contar como "normal" (limiar alto).
: "${MAESTRO_LATENCY_LOAD_PER_CPU_X100:=100}"

# Modelo de custo (medido isoladamente, documentado nos dois testes que usam
# este helper): ~3ms bash+source de lib/common.sh (piso: custo do kill-switch
# sozinho); ~8ms o fork de jq lendo o payload — caminho que PASSA: ~12ms;
# caminho de BLOQUEIO (jq+date do decision record + log_event com stat/flock):
# ~32ms; +5ms de análise léxica de um comando de 8KB (o teto de análise). É
# esse modelo que justifica os orçamentos vigentes (50ms geral, 80ms para o
# payload de 16KB) — o helper não os redefine, só os aplica com o critério novo.

# maestro_latency_measure <binário-do-hook> <arquivo-de-stdin>
# Preenche MED / MIN / MAX (ms). $EPOCHREALTIME é builtin — `date +%s%N`
# forkaria duas vezes por amostra e mediria mais o fork do que o hook.
maestro_latency_measure() {
  local bin="$1" input="$2" n="$MAESTRO_LATENCY_N" i t0 t1 ts=()
  for i in 1 2 3; do "$bin" < "$input" >/dev/null 2>&1; done   # aquece
  for ((i = 0; i < n; i++)); do
    t0="${EPOCHREALTIME/./}"
    "$bin" < "$input" >/dev/null 2>&1
    t1="${EPOCHREALTIME/./}"
    ts+=( $(( (t1 - t0) / 1000 )) )
  done
  local sorted
  mapfile -t sorted < <(printf '%s\n' "${ts[@]}" | sort -n)
  MED="${sorted[$((n / 2))]}"; MIN="${sorted[0]}"; MAX="${sorted[$((n - 1))]}"
}

# maestro_latency_read_load — lê /proc/loadavg e nproc UMA VEZ (fora do laço
# de medição, que não pode ter fork extra). Preenche MAESTRO_LATENCY_LOAD1M
# (string, ex. "7.84"), MAESTRO_LATENCY_NCPU e MAESTRO_LATENCY_OVER (1 = carga
# por CPU acima do limiar declarado; 0 = máquina não saturada).
maestro_latency_read_load() {
  local loadavg load_x100 limiar_x100
  read -r loadavg < /proc/loadavg
  MAESTRO_LATENCY_LOAD1M="${loadavg%% *}"
  MAESTRO_LATENCY_NCPU=$(nproc 2>/dev/null || echo 1)
  # remove o ponto decimal ("7.84" → "784"; "0.84" → "084"); 10# força base
  # decimal para "084" não ser lido como octal inválido.
  load_x100="${MAESTRO_LATENCY_LOAD1M/./}"
  load_x100=$((10#$load_x100))
  limiar_x100=$(( MAESTRO_LATENCY_LOAD_PER_CPU_X100 * MAESTRO_LATENCY_NCPU ))
  if (( load_x100 > limiar_x100 )); then MAESTRO_LATENCY_OVER=1; else MAESTRO_LATENCY_OVER=0; fi
}

# maestro_latency_report <nome> <min> <med> <max> <orcamento_ms>
# Imprime a linha de diagnóstico (min/max continuam impressos — deixam de ser
# critério, seguem úteis) e preenche MAESTRO_LATENCY_VERDICT em
# {ok, inconclusivo, fail}, e MAESTRO_LATENCY_TETO / MAESTRO_LATENCY_TETO_MOTIVO
# com o teto que DE FATO valeu nesta execução (para o chamador poder citá-lo
# nas próprias mensagens, sem recalcular).
#
# O teto depende da carga (maestro_latency_read_load já lido antes de chamar):
#   máquina quieta (MAESTRO_LATENCY_OVER=0) → teto = orçamento, ESTRITO.
#     Mediana acima disso é FAIL — sem carga para culpar, é regressão de
#     verdade. É como o NFR de <orçamento continua sendo cobrado (na CI, que
#     roda em runner quieto).
#   máquina sob carga (MAESTRO_LATENCY_OVER=1) → teto = orçamento × FOLGA.
#     Abaixo é ok; acima é "inconclusivo", nunca "fail" — chamador decide se
#     trata inconclusivo como ok ou como terceira categoria de saída; isso é
#     decisão de cada teste/CI, não deste helper.
maestro_latency_report() {
  local nome="$1" min="$2" med="$3" max="$4" lim="$5"
  if (( MAESTRO_LATENCY_OVER == 1 )); then
    MAESTRO_LATENCY_TETO=$(( lim * MAESTRO_LATENCY_FOLGA ))
    MAESTRO_LATENCY_TETO_MOTIVO="com folga ${MAESTRO_LATENCY_FOLGA}x — carga acima do limiar"
  else
    MAESTRO_LATENCY_TETO="$lim"
    MAESTRO_LATENCY_TETO_MOTIVO="estrito — máquina quieta"
  fi
  printf '     %-24s min=%sms  mediana=%sms  max=%sms  (orçamento %sms, teto %sms [%s], load %s/%s CPUs)\n' \
    "$nome" "$min" "$med" "$max" "$lim" "$MAESTRO_LATENCY_TETO" "$MAESTRO_LATENCY_TETO_MOTIVO" \
    "$MAESTRO_LATENCY_LOAD1M" "$MAESTRO_LATENCY_NCPU"
  if (( med < MAESTRO_LATENCY_TETO )); then
    MAESTRO_LATENCY_VERDICT=ok
  elif (( MAESTRO_LATENCY_OVER == 1 )); then
    MAESTRO_LATENCY_VERDICT=inconclusivo
  else
    MAESTRO_LATENCY_VERDICT=fail
  fi
}
