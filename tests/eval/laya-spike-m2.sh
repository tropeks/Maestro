#!/usr/bin/env bash
# tests/eval/laya-spike-m2.sh — M2 (roteamento): casos de cases.yaml via
# prescribe.ts --json, perguntas por eixo, medição e escrita do TSV. Sourced por
# laya-spike.sh — nunca executado direto.
# ---------------------------------------------------------------------------
# M2 — roteamento. cases.yaml via prescribe.ts --json (prompt + expected +
# ambiguous — sem tocar no parser YAML de novo). Três perguntas por caso:
# workflow, mode, agents (agents é single-choice — ver nota no cabeçalho do
# TSV; casos com 2 agentes esperados contam certo se o motor acertar QUALQUER
# um dos dois, limitação documentada, não escondida).
# ---------------------------------------------------------------------------
_m2_workflow_criteria() {
  awk '
    /^workflows:/ {f=1; next}
    f && /^[a-z]/ {exit}
    f && /^  [a-z_]+:/ {
      line=$0; sub(/^  /,"",line); split(line,parts,":");
      name=parts[1];
      steps="?";
      if (match($0, /steps: \[[^]]*\]/)) {
        steps=substr($0, RSTART+8, RLENGTH-9); gsub(/,/, "+", steps); gsub(/ /,"",steps)
      }
      if (steps == "") steps="(nenhum passo catalogado)"
      printf "%s\t%s\n", name, steps
    }
  ' "$REPO/config/routing-table.yaml"
}

_m2_agent_criteria() {
  local f nm ds
  for f in "$REPO"/agents/*.md; do
    [[ -e "$f" ]] || continue
    nm=$(awk -F': *' '/^name:/{print $2; exit}' "$f")
    ds=$(awk -F': *' '/^description:/{sub(/^description: */,""); print; exit}' "$f")
    printf '%s\t%s\n' "$nm" "$ds"
  done
  printf 'nenhum\tnenhum agente do roster — passo é skill pesada ou fica no contexto principal\n'
}

m2_engine_input() {
  local wf_json agents_json
  wf_json=$(_m2_workflow_criteria | jq -Rs '
    split("\n") | map(select(length > 0) | split("\t")) | map({(.[0]): .[1]}) | add')
  agents_json=$(_m2_agent_criteria | jq -Rs '
    split("\n") | map(select(length > 0) | split("\t")) | map({(.[0]): .[1]}) | add')

  bun "$PRESCRIBE" --json | jq -c --argjson wf "$wf_json" --argjson ag "$agents_json" '
    .verdicts[] | {
      id: .id,
      prompt: .prompt,
      ambiguous: .ambiguous,
      expected: .expected,
      questions: {
        workflow: {type: "choice", instructions: "Qual workflow melhor descreve o pedido em `message`?", criteria: $wf},
        mode: {type: "choice", instructions: "O pedido pede um agente do roster sozinho (subagent), vários em paralelo (multi), ou fica no contexto principal (direct)?",
               criteria: {direct: "contexto principal, sem delegar a um agente do roster", subagent: "um agente do roster especialista executa sozinho", multi: "dois ou mais agentes do roster em paralelo"}},
        agents: {type: "choice", instructions: "Qual agente do roster deve executar o trabalho PRINCIPAL (investigação/implementação) do pedido em `message`? Use nenhum se não for trabalho de agente do roster.", criteria: $ag}
      }
    }'
}

m2_run() {
  local out="${1:-$HERE/laya-m2.tsv}"
  local dep; dep=$(check_deps)
  if [[ "$dep" != "ok" ]]; then
    skip "${dep#skip: }"
  fi

  local work; work=$(mktemp -d) || die "mktemp falhou"

  m2_engine_input >"$work/cases.jsonl"
  jq -c '{id, state: .prompt, questions}' "$work/cases.jsonl" \
    | LAYA_TORCH_THREADS="$THREADS" "$PY" "$ENGINE" --predict \
      >"$work/predictions.jsonl" 2>"$work/predict.stderr"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    cat "$work/predict.stderr" >&2
    die "laya_engine.py --predict falhou em M2 (rc=$rc)"
  fi

  # NUNCA `jq -s arq1 arq2`: -s concatena os DOIS arquivos num array só, sem
  # separar por origem (medido: quebrou o join na primeira tentativa — o
  # fix é --slurpfile para um lado e -s só no arquivo principal).
  jq --slurpfile cases "$work/cases.jsonl" -s '
    (($cases | map({(.id): .}) | add)) as $casesmap
    | (map(select(.error | not))) as $preds
    | [ $preds[] as $p
        | $casesmap[$p.id] as $c
        | ("workflow" | . as $axis
           | {case_id: $p.id, axis: $axis, ambiguous: $c.ambiguous,
              expected: $c.expected.workflow, predicted: $p.answers.workflow.choice,
              confidence: $p.answers.workflow.confidence,
              correct: (if $p.answers.workflow.choice == $c.expected.workflow then 1 else 0 end)}),
          ("mode" | . as $axis
           | {case_id: $p.id, axis: $axis, ambiguous: $c.ambiguous,
              expected: $c.expected.mode, predicted: $p.answers.mode.choice,
              confidence: $p.answers.mode.confidence,
              correct: (if $p.answers.mode.choice == $c.expected.mode then 1 else 0 end)}),
          ("agents" | . as $axis
           | ($c.expected.agents // []) as $exp_ag
           | {case_id: $p.id, axis: $axis, ambiguous: $c.ambiguous,
              expected: (if ($exp_ag|length)==0 then "nenhum" else ($exp_ag | join(",")) end),
              predicted: $p.answers.agents.choice,
              confidence: $p.answers.agents.confidence,
              correct: (if (($exp_ag|length)==0 and $p.answers.agents.choice=="nenhum") or ($exp_ag | index($p.answers.agents.choice) != null) then 1 else 0 end)})
      ]
  ' "$work/predictions.jsonl" >"$work/joined.json"

  _m2_write_tsv "$work/joined.json" "$out"
  printf 'M2: %s registros (3 eixos x 15 casos) -> %s\n' "$(jq length "$work/joined.json")" "$out"
  # `rm` explícito, não `trap ... RETURN` — ver nota em laya-spike-m1.sh.
  rm -rf "$work"
}

_m2_write_tsv() {
  local joined="$1" out="$2"
  jq -r '
    . as $rows
    | (map(select(.axis=="workflow")) ) as $wf
    | (map(select(.axis=="mode"))     ) as $md
    | (map(select(.axis=="agents"))   ) as $ag
    | (map(select(.ambiguous == true) | .case_id) | unique) as $amb_ids
    | def rate(xs): if (xs|length)==0 then null else (xs | map(.correct) | add) / (xs|length) end;
      "# tests/eval/laya-m2.tsv — M2 (roteamento), ordem 034/028. n=15 casos x 3 eixos.",
      "# n=15: calibração por faixa é INDICATIVA, não conclusiva (regra 028) — leia junto com o n.",
      "# concordância workflow = \(rate($wf)) (n=\($wf|length))",
      "# concordância mode     = \(rate($md)) (n=\($md|length))",
      "# concordância agents   = \(rate($ag)) (n=\($ag|length)) — single-choice: conta certo se acertar QUALQUER agente esperado (limite do desenho, ver laya-spike.sh)",
      "# casos ambiguous:true  = \($amb_ids | join(", "))  — bloco à parte abaixo, confiança alta aqui é excesso de confiança (o sinal mais informativo do experimento)",
      "# Colunas: case_id\taxis\tambiguous\texpected\tpredicted\tconfidence\tcorrect",
      (["case_id","axis","ambiguous","expected","predicted","confidence","correct"] | @tsv),
      ($rows[] | select(.ambiguous != true) | [.case_id,.axis,.ambiguous,.expected,.predicted,.confidence,.correct] | @tsv),
      "# --- ambiguous:true (bloco à parte) ---",
      ($rows[] | select(.ambiguous == true) | [.case_id,.axis,.ambiguous,.expected,.predicted,.confidence,.correct] | @tsv)
  ' "$joined" >"$out"
}
