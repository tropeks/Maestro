---
description: "Varre o codebase com os habit sensors e paga a dívida de slop em lotes revisáveis, com agentes tierizados e a suíte como gate entre lotes"
argument-hint: "[caminho] [--dry]"
---

# /maestro:deslop — pagar a dívida de slop, do jeito certo

Você vai varrer o projeto com os habit sensors (E9) e corrigir os achados em
lotes. Regra de ouro herdada dos guias: **corrigir o design, nunca burlar a
métrica** — quebrar uma função só para calar o sensor é o anti-padrão que este
comando existe para combater. Argumentos recebidos: `$ARGUMENTS`.

## 1. Levantamento (sempre, mesmo em --dry)

1. Registre a decisão: `maestro decide --session <session_id da injeção> --workflow custom --mode multi --reason "deslop sweep"`.
2. Rode `maestro habits --all` (restrinja ao caminho dos argumentos, se houver).
   Se a saída disser "dentro da catraca" com 0 achados, reporte e PARE — não
   invente trabalho.
3. Monte a tabela de triagem e **mostre ao usuário antes de qualquer edição**:

| classe | smells | executor | política |
|---|---|---|---|
| Mecânica | debug-leftover · dead-code · slop-comment · skipped-test · lint-suppression | dev-junior (haiku) | fix direto; critério objetivo |
| Julgamento | oversized-function/file · deep-nesting · too-many-params · swallowed-error · empty-impl · type-escape · risky-shortcut | especialista da linguagem do alvo (H5) ou dev-pleno | fix COM teste no mesmo lote; extração por responsabilidade, não por contagem |
| Falso positivo honesto | ex.: print() de CLI intencional | ninguém | proponha ajuste de `habits:` no `.maestro.yaml` — NUNCA supressão inline (dispararia lint-suppression) |

Se `--dry`: entregue a tabela com contagens e o plano de lotes, e pare aqui.

## 2. Execução em lotes (pipeline, não enxame)

- **Lote = grupo de arquivos independentes** (sem import mútuo direto), no
  máximo ~5 arquivos. Antes de agrupar, rode `maestro graph`: se o grafo estiver
  FRESCO, monte os lotes por CONSULTA (`graphify query "quais arquivos dependem
  de X?"`) em vez de palpite — independência verificada é o que evita lote
  quebrando a suíte. STALE ou ausente → agrupe pelo conhecimento da sessão,
  como antes. Paralelize os agentes DENTRO do lote (um agente por
  arquivo ou por grupo coeso); NUNCA dois agentes no mesmo arquivo.
- Ordem: lotes mecânicos primeiro (baratos, destravam o diff), depois os de
  julgamento.
- Entre lotes, **a suíte do projeto é o gate**: rode-a; se quebrar, reverta o
  lote inteiro (`git checkout -- <arquivos>`) e reporte o porquê — lote quebrado
  não se "ajeita" em cima.
- Fim de cada lote verde: commit do lote (mensagem: `deslop: <classe> — <n>
  achado(s) em <arquivos>`), e `maestro habits --baseline` **no mesmo commit**
  — a catraca desce junto com a dívida.

## 3. Fechamento

1. `maestro habits --all` final: deve sair "dentro da catraca" com o baseline
   menor que o inicial.
2. Dispare o **revisor** (read-only) sobre o diff acumulado do sweep; achados
   dele viram um lote extra ou pendência explícita — nunca silêncio.
3. Reporte: achados iniciais → corrigidos / reconfigurados / restantes (com
   motivo), baseline antes → depois, commits criados. Atualize o brief do
   projeto (`maestro brief --write`) com o estado pós-sweep.

Gates humanos: este comando NÃO pusha nem abre PR por conta própria — commit
local é o teto (diretriz Spock: push/PR só com a onda verificada e conforme o
fluxo do projeto).
