#!/usr/bin/env bash
# tests/eval/laya-spike-m1.sh — M1 (desfecho): pares outcome<-decision do log,
# perguntas tipadas, medição e escrita do TSV. Sourced por laya-spike.sh — nunca
# executado direto (usa $HERE/$ENGINE/$PY/$THREADS/die()/skip() do chamador).
# ---------------------------------------------------------------------------
# M1 — desfecho. Deriva os pares outcome<-decision do log real (m1-pairs.jq),
# monta as perguntas tipadas, chama o motor, escreve laya-m1.tsv.
# ---------------------------------------------------------------------------
m1_pairs_json() {
  local log="$1"
  [[ -f "$log" ]] || { printf '[]'; return 0; }
  jq -R 'fromjson? // empty' "$log" 2>/dev/null | jq -rsf "$HERE/m1-pairs.jq"
}

# Constrói o JSONL de entrada do motor a partir do array de pares (stdin: JSON array).
m1_engine_input() {
  jq -c '
    to_entries[] | {
      id: ("m1-" + (.key | tostring)),
      state: {
        project: .value.project, workflow: .value.workflow, mode: .value.mode,
        agents: .value.agents, tool: .value.tool, file_ext: .value.file_ext
      },
      questions: {
        outcome: {
          type: "choice",
          instructions: "Given the routing metadata (project, workflow, mode, agents, and the tool/file most recently touched in this session), what was the outcome of this decision?",
          criteria: {
            accepted: "merged with no rework requested",
            rework: "required a correction before being accepted",
            killed: "abandoned, never merged"
          }
        }
      },
      true_label: .value.outcome
    }'
}

# Preenche $work/joined.json (truth x predição x correct) para os pares do
# log. Assume que o chamador já confirmou dependências e n>0 — é o miolo
# comum de m1_run() e report_run(), para NUNCA chamar o motor duas vezes pelo
# mesmo corpus.
m1_measure() {
  local pairs="$1" work="$2"
  printf '%s' "$pairs" | m1_engine_input >"$work/input.jsonl"
  printf '%s' "$pairs" | jq -c 'to_entries[] | {id: ("m1-" + (.key|tostring)), true_label: .value.outcome}' \
    >"$work/truth.jsonl"

  jq -c '{id, state, questions}' "$work/input.jsonl" \
    | LAYA_TORCH_THREADS="$THREADS" "$PY" "$ENGINE" --predict \
      >"$work/predictions.jsonl" 2>"$work/predict.stderr"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    cat "$work/predict.stderr" >&2
    die "laya_engine.py --predict falhou em M1 (rc=$rc)"
  fi

  # NUNCA `jq -s arq1 arq2`: -s concatena os DOIS arquivos num array só (sem
  # separar por origem) — bug já pago aqui mesmo (ver laya-spike-m2.sh). O
  # join certo é --slurpfile (variável separada) + -s só no arquivo principal.
  jq -L "$HERE" --slurpfile truth "$work/truth.jsonl" -s '
    import "laya-lib" as lib;
    ($truth | map({(.id): .}) | add) as $truthmap
    | (map(select(.error | not))) as $preds
    | $preds | map(
        .id as $id
        | ($truthmap[$id].true_label) as $t
        | {
            id: $id,
            true_label: $t,
            predicted: .answers.outcome.choice,
            confidence: .answers.outcome.confidence,
            correct: (if .answers.outcome.choice == $t then 1 else 0 end)
          }
      )
  ' "$work/predictions.jsonl" >"$work/joined.json"
}

m1_run() {
  local out="${1:-$HERE/laya-m1.tsv}"
  local pairs; pairs=$(m1_pairs_json "$LOG")
  local n; n=$(printf '%s' "$pairs" | jq 'length')
  [[ "$n" != "0" ]] || skip "log sem pares M1 utilizáveis ($LOG)"

  local dep; dep=$(check_deps)
  [[ "$dep" == "ok" ]] || skip "${dep#skip: }"

  local work; work=$(mktemp -d) || die "mktemp falhou"

  m1_measure "$pairs" "$work"
  _m1_write_tsv "$work/joined.json" "$out"
  printf 'M1: %s registros -> %s\n' "$(jq length "$work/joined.json")" "$out"
  # `rm` explícito, NUNCA `trap ... RETURN`: o trap não é local à função — ele
  # sobrescreve o de quem chamou e dispara de novo no retorno DELE, com $work
  # fora de escopo (medido: `report_run` estourou "work: unbound variable"
  # porque o trap de m2_run/machine_cost ficou ativo até o retorno de main()).
  rm -rf "$work"
}

_m1_write_tsv() {
  local joined="$1" out="$2"
  jq -L "$HERE" -r '
    import "laya-lib" as lib;
    . as $rows
    | (length) as $n
    | (map(select(.true_label == "accepted")) | length) as $acc_n
    | (map(select(.true_label == "rework"))   | length) as $rew_n
    | (map(select(.true_label == "killed"))   | length) as $kil_n
    | ($acc_n / $n) as $base_rate
    | (lib::accuracy($rows)) as $acc
    | (map(select(.true_label == "rework")) | if length == 0 then null else (map(select(.predicted == "rework")) | length) / length end) as $recall_rework
    | "# tests/eval/laya-m1.tsv — M1 (desfecho), ordem 034/028. n=\($n) (accepted \($acc_n) · rework \($rew_n) · killed \($kil_n)).",
      "# base_rate(accepted) = \($base_rate) — acurácia SEM esta linha ao lado é resultado proibido (regra 028).",
      "# acuracia_geral = \($acc)",
      "# recall_rework (n=\($rew_n)) = \($recall_rework)",
      "# killed (n=\($kil_n)): contagem apenas — pequeno demais para derivar recall/precision (regra 028).",
      "# Colunas: id\ttrue_label\tpredicted\tconfidence\tcorrect",
      (["id","true_label","predicted","confidence","correct"] | @tsv),
      ($rows[] | [.id, .true_label, .predicted, .confidence, .correct] | @tsv)
  ' "$joined" >"$out"
}
