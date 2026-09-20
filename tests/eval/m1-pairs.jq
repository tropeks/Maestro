# tests/eval/m1-pairs.jq — deriva o corpus M1 (desfecho) do log real.
#
# Ordem 034 / 028: casa cada `outcome` com a `decision` mais recente da MESMA
# sessão antes dele. O estado entregue ao motor é METADADO apenas — nunca o
# prompt, que não existe no log por fronteira dura (CLAUDE.md "Logs: só
# metadados; jamais prompt"). `tool`/`file_ext` vêm do gate (`gate_pass`/
# `gate_warn`/`gate_block`) mais recente da sessão antes do outcome, se houver.
#
# Uso: jq -R 'fromjson? // empty' routing.jsonl | jq -rsf m1-pairs.jq
# (o `fromjson? // empty` descarta linha malformada — mesma tolerância do
# instrumento (C) de run-eval.sh: JSONL append-only de hooks concorrentes pode
# truncar uma linha, e perder o corpus inteiro por uma linha é pior que ignorá-la.)
#
# Saída: um array JSON de {outcome, project, workflow, mode, agents, tool, file_ext}.
# `n` do corpus é o `length` desse array — não hardcoded em lugar nenhum.
map(select(type == "object" and has("event") and has("session_id")))
| group_by(.session_id)
| map(
    . as $evs
    | reduce range(0; $evs | length) as $i
        ({last_decision: null, last_gate: null, pairs: []};
         $evs[$i] as $e
         | if $e.event == "decision" then
             .last_decision = {
               workflow: $e.workflow,
               mode: $e.mode,
               agents: ($e.agents // []),
               project: $e.project
             }
           elif ($e.event == "gate_pass" or $e.event == "gate_warn" or $e.event == "gate_block") then
             .last_gate = {tool: $e.tool, file_ext: ($e.file_ext // null)}
           elif ($e.event == "outcome" and (.last_decision != null)) then
             .pairs += [{
               outcome: $e.outcome,
               project: .last_decision.project,
               workflow: .last_decision.workflow,
               mode: .last_decision.mode,
               agents: .last_decision.agents,
               tool: (.last_gate.tool // null),
               file_ext: (.last_gate.file_ext // null)
             }]
           else . end
        )
    | .pairs
  )
| add // []
