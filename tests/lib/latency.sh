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
# CARGA: acima de um limiar de carga (load average de 1 min, ver decisão do
# supervisor abaixo), estouro de teto não é FAIL, é "inconclusivo sob carga"
# — a regra do diretor (medição inválida sem load ao lado; sob carga, o
# veredito nunca é regressão) virando código.
#
# O TETO EM SI DEPENDE DA CARGA — isto não é detalhe, é o que faz o NFR
# continuar sendo cobrado: a FOLGA existe para tolerar CONTENÇÃO, então só
# pode valer quando há contenção medida. Se a folga valesse sempre (inclusive
# em máquina quieta, como a CI), o teto de facto viraria 2x o orçamento em
# TODO lugar e o NFR de <50ms deixaria de ser cobrado em qualquer máquina —
# um hook que regredisse para perto de 2x o orçamento passaria "ok" até na CI
# quieta, onde não há carga nenhuma para culpar. Por isso:
#   load ABAIXO do limiar (máquina quieta, o caso da CI) → teto = orçamento,
#     ESTRITO. Mediana acima disso é FAIL de verdade — sem carga para culpar,
#     é regressão de código, não de escalonamento.
#   load ACIMA do limiar (forge) → teto = orçamento × FOLGA. Abaixo disso é
#     ok; acima é inconclusivo, nunca fail.
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

# --- limiar de carga: load average de 1 min, ABSOLUTO, ×100 -----------------
# Decisão do supervisor (2026-09-12): limiar de carga para medição de latência
# válida é load average de 1 minuto ≤ 2,00 NESTA FORGE DE 8 CPUS — um número
# ABSOLUTO, não por CPU. CLAUDE.md proíbe float em métrica; comparação em
# aritmética inteira de bash. /proc/loadavg sempre formata o load com 2 casas
# decimais no kernel Linux ("7.84"), então remover o ponto dá o valor ×100
# direto ("784"); 2.00 de limiar vira 200.
#
# A ARMADILHA QUE ESTE NÚMERO PRECISA CONTINUAR EVITANDO: "generalizar" para
# por-CPU (2,0 ÷ 8 = 0,25/CPU) parece mais "correto" e é justamente o que NÃO
# fazer. O runner da CI tem 4 CPUs, não 8. No PR #5 ele mediu load 0.88/4 CPUs
# e 1.05/4 CPUs — 0,22 e 0,2625 por CPU. Um limiar por-CPU de 0,25 faria a
# SEGUNDA medição (0,2625) cair ACIMA do limiar, a CI passaria a reportar
# "inconclusivo", e o teto ESTRITO — o único lugar onde o NFR de latência é
# de fato cobrado — seria desligado em silêncio na máquina de referência. Com
# limiar absoluto de 2,0 a CI (0,88–1,05 absoluto) fica folgadamente na faixa
# "quieta", e o NFR continua sendo cobrado lá.
#
# Evidência que sustenta o número 2,0: a CI (referência de "quieta") mediu
# min≈mediana entre 0,88 e 1,05 de load ABSOLUTO (PR #5, 4 CPUs); esta forge,
# sob a mesma carga de trabalho concorrente que motivou o portão de carga
# (ordem 002/ponta 3, comentário no topo do arquivo), mostrou load 6–10 —
# mediana 2 a 4x maior que o pico já observado como "quieto". 2,0 fica acima
# do que já foi medido como quieto e bem abaixo do que já foi medido como
# saturado — não é ponto médio arbitrário, é a fronteira entre os dois
# regimes já observados. Override por ambiente é o que permite provar, em
# máquina carregada, que o portão ainda reprova latência de verdade quando a
# carga é forçada a contar como "normal" (limiar alto).
: "${MAESTRO_LATENCY_LOAD1M_LIMIAR_X100:=200}"

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
# (string, ex. "7.84"), MAESTRO_LATENCY_NCPU e MAESTRO_LATENCY_OVER (1 = load
# absoluto de 1 min acima do limiar declarado; 0 = máquina não saturada).
# MAESTRO_LATENCY_NCPU NÃO entra mais na conta do limiar (o limiar é
# absoluto, não por CPU — ver comentário de proveniência acima) — mantido de
# propósito só porque maestro_latency_report e os chamadores (test-gate.sh,
# test-guarda-destrutiva.sh) usam para exibir "load X/N CPUs" no diagnóstico,
# informação útil para quem lê o log mesmo não entrando mais no cálculo.
maestro_latency_read_load() {
  local loadavg load_x100
  read -r loadavg < /proc/loadavg
  MAESTRO_LATENCY_LOAD1M="${loadavg%% *}"
  MAESTRO_LATENCY_NCPU=$(nproc 2>/dev/null || echo 1)
  # remove o ponto decimal ("7.84" → "784"; "0.84" → "084"); 10# força base
  # decimal para "084" não ser lido como octal inválido.
  load_x100="${MAESTRO_LATENCY_LOAD1M/./}"
  load_x100=$((10#$load_x100))
  if (( load_x100 > MAESTRO_LATENCY_LOAD1M_LIMIAR_X100 )); then MAESTRO_LATENCY_OVER=1; else MAESTRO_LATENCY_OVER=0; fi
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
