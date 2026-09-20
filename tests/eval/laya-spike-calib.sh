#!/usr/bin/env bash
# tests/eval/laya-spike-calib.sh — Brier/ECE antes-depois do refit de
# temperatura (split holdout) e custo de máquina (p50/p95, disco, RSS, carga).
# Sourced por laya-spike.sh — nunca executado direto.
# ---------------------------------------------------------------------------
# Calibração — Brier/ECE antes e depois do refit de temperatura, split
# holdout. M1: split estratificado por classe (accepted/rework; killed fica
# de fora do AJUSTE — n=3 não sustenta fit nenhum — mas entra na leitura
# descritiva). M2: n=15, sem split honesto — a ordem manda marcar
# não-conclusivo OU não fazer. Este harness NÃO FAZ (decisão explícita,
# registrada aqui): 15 casos partidos ao meio deixam ~7 por lado, faixas de
# confiança ficam vazias por construção, e a "melhora" apareceria por ruído
# de amostra, não por sinal — o que violaria "medido, não estimado" na
# direção oposta (mediria ruído e chamaria de calibração).
# ---------------------------------------------------------------------------
calibracao_run() {
  local m1_joined="$1" out="$2"
  # laya-lib.jq opera sobre `.confidence` — aqui ele recebe `p_pred`
  # (probabilities[predicted], o posterior real), NUNCA entropy_confidence
  # (índice de entropia do laya, que não é probabilidade — corrigido depois
  # da 1a rodada publicada ter medido esse índice como se fosse confiança).
  jq -L "$HERE" -s '
    import "laya-lib" as lib;
    (.[0] | map({id, true_label, correct, confidence: .p_pred})) as $rows
    | (lib::split_stratified($rows | map(select(.true_label != "killed")); "id"; "true_label")) as $split
    | ($rows | map(select(.true_label == "killed"))) as $killed
    | ($split.teste + $killed) as $teste_full
    | (lib::best_temperature($split.ajuste)) as $T
    | (lib::apply_temperature($teste_full; $T)) as $teste_depois
    | {
        T: $T,
        ajuste_n: ($split.ajuste | length),
        teste_n: ($teste_full | length),
        antes: { brier: lib::brier($teste_full), ece: lib::ece_table($teste_full; 15) },
        depois: { brier: lib::brier($teste_depois), ece: lib::ece_table($teste_depois; 15) }
      }
  ' "$m1_joined" >"$out.json"
  [[ $? -eq 0 ]] || die "cálculo de calibração falhou — ver jq acima"

  jq -r '
    "# tests/eval/laya-calibracao.tsv — ordem 034/028. Split holdout estratificado por classe (M1); temperatura ajustada SÓ no split de ajuste, medida SÓ no split de teste.",
    "# conf_media/faixas são sobre p_pred = probabilities[predicted] (posterior real) — NÃO o índice de entropia do laya (ver laya_engine.py).",
    "# temperatura ajustada (T) = \(.T) · ajuste_n=\(.ajuste_n) · teste_n=\(.teste_n)",
    "# brier ANTES  = \(.antes.brier) · ece ANTES  = \(.antes.ece.ece)",
    "# brier DEPOIS = \(.depois.brier) · ece DEPOIS = \(.depois.ece.ece)",
    "# coluna jev: VAZIA — a ordem 028 não rodou ainda; espaço reservado para o lado a lado.",
    "# Colunas: fase\tfaixa_lo\tfaixa_hi\tn\tconf_media\tacerto_observado_laya\tacerto_observado_jev\tconclusiva",
    (["fase","faixa_lo","faixa_hi","n","conf_media","acerto_observado_laya","acerto_observado_jev","conclusiva"] | @tsv),
    (.antes.ece.rows[]  | ["antes",  .lo, .hi, .n, .conf_media, .acerto_observado, "", .conclusiva] | @tsv),
    (.depois.ece.rows[] | ["depois", .lo, .hi, .n, .conf_media, .acerto_observado, "", .conclusiva] | @tsv)
  ' "$out.json" >"$out"
  rm -f "$out.json"
}

# ---------------------------------------------------------------------------
# Custo de máquina — p50/p95 por pergunta, disco por checkpoint, pico de RSS.
# Threads fixas e impressas. Carga na largada relatada, nunca maquiada
# (papercut da forge: uptime > 2.00 -> espera até 15 min, senão relata como
# está).
# ---------------------------------------------------------------------------
# Espera até 15 min se a carga (1min) estiver acima de 2.00 na largada;
# relata a carga OBSERVADA, nunca maquiada (papercut da forge).
_machine_cost_wait_load() {
  local load1; load1=$(awk '{print $1}' /proc/loadavg)
  local waited=0
  while awk -v l="$load1" 'BEGIN{exit !(l>2.0)}' && [[ $waited -lt 900 ]]; do
    sleep 30; waited=$((waited+30))
    load1=$(awk '{print $1}' /proc/loadavg)
  done
  printf 'carga na largada (1min) = %s (esperou %ss)\n' "$load1" "$waited"
}

# p50/p95 de latência por pergunta, numa chamada só do motor (n perguntas,
# threads fixas e impressas). Escreve lat.stderr em $work para
# _machine_cost_peak_rss ler depois.
_machine_cost_latency() {
  local work="$1" n=20 i
  for ((i = 0; i < n; i++)); do
    printf '{"id":"lat-%d","state":{"project":"p","workflow":"fix","mode":"direct"},"questions":{"outcome":{"type":"choice","instructions":"outcome?","criteria":{"accepted":"a","rework":"b","killed":"c"}}}}\n' "$i"
  done >"$work/lat-input.jsonl"

  LAYA_TORCH_THREADS="$THREADS" "$PY" "$ENGINE" --predict \
    <"$work/lat-input.jsonl" >"$work/lat-out.jsonl" 2>"$work/lat.stderr"
  local rc=$?
  [[ $rc -eq 0 ]] || { cat "$work/lat.stderr" >&2; die "medição de latência falhou (rc=$rc)"; }

  jq -r '.latency_ms' "$work/lat-out.jsonl" | sort -n >"$work/lats.txt"
  local cnt; cnt=$(wc -l <"$work/lats.txt" | tr -d ' ')
  local p50_idx p95_idx
  p50_idx=$(awk -v c="$cnt" 'BEGIN{i=int(c*0.50); if (i<1) i=1; print i}')
  p95_idx=$(awk -v c="$cnt" 'BEGIN{i=int(c*0.95); if (i<1) i=1; print i}')
  printf 'latência por pergunta (n=%s, threads=%s): p50=%sms p95=%sms\n' \
    "$cnt" "$THREADS" "$(sed -n "${p50_idx}p" "$work/lats.txt")" "$(sed -n "${p95_idx}p" "$work/lats.txt")"
}

# A linha de peak_rss é JSON puro (json.dumps), mas o stderr do processo pode
# ter avisos de terceiro (tqdm/huggingface_hub) ANTES dela — pega só a ÚLTIMA
# linha que é JSON válido com a chave certa, via jq (regex ingênua já
# quebrou aqui: json.dumps põe espaço depois do ":").
_machine_cost_peak_rss() {
  local work="$1" n="$2"
  local peak_rss
  peak_rss=$(tac "$work/lat.stderr" | while IFS= read -r ln; do
    printf '%s' "$ln" | jq -r 'select(has("peak_rss_kb")) | .peak_rss_kb' 2>/dev/null && break
  done)
  printf 'pico de RSS do processo (medição da latência, %s perguntas) = %s KB\n' "$n" "${peak_rss:-desconhecido}"
}

# Disco por checkpoint no bundle convaiinnovations/laya — medido no disco
# real, não no número já citado na ordem.
_machine_cost_disk() {
  local cache="${HF_HOME:-$HOME/.cache/huggingface}"
  local eng_dir; eng_dir=$(find "$cache/hub" -maxdepth 1 -type d -name '*convaiinnovations--laya*' 2>/dev/null | head -1)
  if [[ -z "$eng_dir" ]]; then
    printf 'disco por checkpoint: diretório não encontrado em %s/hub\n' "$cache"
    return 0
  fi
  local snap; snap=$(find "$eng_dir/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
  [[ -n "$snap" ]] || { printf 'disco por checkpoint: sem snapshot em %s\n' "$eng_dir"; return 0; }
  printf 'disco por checkpoint (bundle convaiinnovations/laya, %s):\n' "$snap"
  printf '  english (raiz)      = %s\n' "$(du -shL "$snap/model.safetensors" 2>/dev/null | cut -f1)"
  [[ -d "$snap/multilingual" ]]    && printf '  multilingual         = %s\n' "$(du -shL "$snap/multilingual" 2>/dev/null | cut -f1)"
  [[ -d "$snap/typed-decisions" ]] && printf '  typed-decisions      = %s\n' "$(du -shL "$snap/typed-decisions" 2>/dev/null | cut -f1)"
  printf '  total (%s)  = %s\n' "$(basename "$eng_dir")" "$(du -shL "$eng_dir" 2>/dev/null | cut -f1)"
}

# ---------------------------------------------------------------------------
# Custo de máquina — p50/p95 por pergunta, disco por checkpoint, pico de RSS.
# Threads fixas e impressas. Carga na largada relatada, nunca maquiada.
# ---------------------------------------------------------------------------
machine_cost() {
  local dep; dep=$(check_deps)
  [[ "$dep" == "ok" ]] || skip "${dep#skip: }"

  _machine_cost_wait_load

  local work; work=$(mktemp -d) || die "mktemp falhou"

  _machine_cost_latency "$work"
  _machine_cost_peak_rss "$work" 20
  _machine_cost_disk
  # `rm` explícito, não `trap ... RETURN` — ver nota em laya-spike-m1.sh.
  rm -rf "$work"
}
