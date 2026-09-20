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

# NUNCA `jq -s arq1 arq2`: -s concatena os DOIS arquivos num array só, sem
# separar por origem (medido: quebrou o join na primeira tentativa — o fix
# é --slurpfile para um lado e -s só no arquivo principal).
#
# p_pred = probabilities[choice] (posterior real); entropy_confidence é o
# índice de entropia do laya — informativo, NÃO probabilidade (ver docstring
# de laya_engine.py). `def axis_row` evita repetir a mesma forma três vezes
# com só o nome do eixo mudando.
_m2_join() {
  local work="$1"
  jq --slurpfile cases "$work/cases.jsonl" -s '
    def axis_row($axis; $ans; $expected; $ok):
      # NUNCA `.ambiguous_ // null`: `//` trata `false` como "sem valor" e
      # colapsava ambiguous:false para null (medido — a coluna saía em
      # branco). `.ambiguous_` já está sempre presente; sem fallback.
      {case_id: .id, axis: $axis, ambiguous: .ambiguous_,
       expected: $expected, predicted: $ans.choice,
       p_pred: $ans.p_pred, entropy_confidence: $ans.entropy_confidence,
       correct: (if $ok then 1 else 0 end)};
    (($cases | map({(.id): .}) | add)) as $casesmap
    | (map(select(.error | not))) as $preds
    | [ $preds[] as $p
        | $casesmap[$p.id] as $c
        | ($p + {ambiguous_: $c.ambiguous}) as $pc
        | ($c.expected.agents // []) as $exp_ag
        | ($pc | axis_row("workflow"; .answers.workflow; $c.expected.workflow;
             .answers.workflow.choice == $c.expected.workflow)),
          ($pc | axis_row("mode"; .answers.mode; $c.expected.mode;
             .answers.mode.choice == $c.expected.mode)),
          ($pc | axis_row("agents"; .answers.agents;
             (if ($exp_ag|length)==0 then "nenhum" else ($exp_ag | join(",")) end);
             (.answers.agents.choice) as $ag_choice
             | (($exp_ag|length)==0 and $ag_choice=="nenhum")
               or ($exp_ag | index($ag_choice) != null)))
      ]
  ' "$work/predictions.jsonl" >"$work/joined.json"
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

  _m2_join "$work"
  # rc checado explicitamente: o join já quebrou em silêncio uma vez (erro
  # de jq descartado, joined.json saía vazio, "M2: 0 registros" passava
  # como se fosse sucesso) — nunca mais sem checar.
  [[ $? -eq 0 ]] || die "join M2 (cases x predictions) falhou — ver jq acima"

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
      "# p_pred = probabilities[predicted] (posterior real). entropy_confidence = índice de entropia do laya — informativo, NÃO é probabilidade.",
      "# Colunas: case_id\taxis\tambiguous\texpected\tpredicted\tp_pred\tentropy_confidence\tcorrect",
      (["case_id","axis","ambiguous","expected","predicted","p_pred","entropy_confidence","correct"] | @tsv),
      ($rows[] | select(.ambiguous != true) | [.case_id,.axis,.ambiguous,.expected,.predicted,.p_pred,.entropy_confidence,.correct] | @tsv),
      "# --- ambiguous:true (bloco à parte) ---",
      ($rows[] | select(.ambiguous == true) | [.case_id,.axis,.ambiguous,.expected,.predicted,.p_pred,.entropy_confidence,.correct] | @tsv)
  ' "$joined" >"$out"
}
