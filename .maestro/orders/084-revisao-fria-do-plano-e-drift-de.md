<!-- maestro-order v1
id: 084
ts: 2026-10-25T22:20:49-03:00
epoch: 1792977649
head: 23f49b61f9da6d353be228a8328518763d4f9234
branch: order/084-revisao-fria
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 084 — Revisão fria do plano e recibo de drift de épico

## Origem
Ordem do Capitão, 26/10/2026. Autoriza: INTENT do posto (`/home/rcosta00/dev/spock/.maestro/INTENT.md`),
v58 Etapa 1 (contrato de entrada: ordem que não passa não entra na fila) e v56 estação "revisar"
(revisor em turno headless). As classes de risco são as da linha 14 da matriz "Quem decide":
segredo, dinheiro, motor que escreve em cliente e permissão. Base de código: ordem 059
(`lib/core-order-entry.sh`) e ordem 060 (veredito único de prova).

## Por quê
O gerente especifica e desenvolve a mesma ordem: quem revisa o plano é quem o escreveu. O
`--entry-check` confere forma (Turno, oráculo, dependências), não mérito. E o aceite é ordem a
ordem: o desvio acumulado de um épico contra o seu design doc não é medido por ninguém.

## Contrato
1. **Campos novos no bloco Turno**, ambos opcionais: `- risco: alto|baixo` (ausente = `baixo`) e
   `- fecha_epico: <caminho do design doc>`. O esqueleto do `--create` (flag da 059 ligada) passa a
   trazer `- risco: baixo`.
2. **Pacote do revisor, `maestro order --cold-bundle N [--drift]`**: imprime em stdout, e só isso,
   o pacote que o revisor recebe: o arquivo da ordem (sem adendos de rodada e sem relatórios), o
   INTENT do projeto, o brief, o design doc (se `fecha_epico:`) e o roteiro fixo de
   `docs/contracts/revisao-fria.md`. Com `--drift`, acrescenta o `git diff --stat` e a lista de
   ordens aceitas desde a primeira que cita o mesmo design doc. Nada de transcrito, relatório de
   gerente ou conversa entra no pacote: é isso que faz o contexto zero ser mecânico.
3. **Roteiro fixo `docs/contracts/revisao-fria.md`** (novo). Plano: critério sem oráculo verdadeiro
   (passa sem o pedido existir), alternativa óbvia não considerada, risco das classes acima não
   declarado, contradição com INTENT ou brief, fatia que não cabe no teto. Drift: o que o design doc
   promete e não foi entregue, o que foi entregue e o doc não pede, critério do doc sem prova. Saída
   P1/P2/P3 no formato do `revisor` e veredito `aprova|devolve`; P1 obriga `devolve`.
4. **Recibo, `maestro order --cold-record N --verdict aprova|devolve --findings <arquivo> [--drift]`**:
   grava fora da árvore, como os recibos de validação (050), o rótulo `plan-review-<n>` ou
   `drift-<n>` com o sha256 do arquivo da ordem no momento da revisão, o veredito e a contagem de
   achados por severidade. Nunca grava o texto dos achados no log (só metadado, regra do CLAUDE.md).
5. **Travas, atrás de `MAESTRO_COLD_REVIEW_REQUIRE`** (env > `cold_review_require:` do
   `.maestro.yaml` > desligado, precedência da 041): (f) no `--entry-check`, ordem `risco: alto`
   exige `plan-review-<n>` com `aprova` e sha256 igual ao arquivo atual (plano mudou, revisão nova);
   (g) no `--accept`, ordem com `fecha_epico:` exige `drift-<n>` com `aprova`. Desligada, o
   comportamento é byte a byte o de hoje.
6. **Limite de rodadas:** no máximo 2 `devolve` por ordem; a terceira revisão não é aceita pelo
   `--cold-record` (exit 1, motivo "escala ao Diretor"). P3 vira lista no relatório, não rodada.
7. **EPICS:** emenda E29 com as stories desta ordem, no mesmo changeset (anti-scope-creep).
8. Arquivos protegidos (`bin/`, `hooks/`, `agents/`) não são editados pelo executor: o roteamento
   do CLI para as ações novas sai como patch em `docs/patches/`. A lógica fica em
   `lib/core-order-cold.sh` (novo). O `revisor` não muda: o pacote é a entrada dele.

## Critérios de aceite
- [oráculo: `bash tests/cli/test-order-cold-bundle.sh`] o pacote traz ordem, INTENT, brief e roteiro, e nada além (fixture com relatório e adendo: nenhum dos dois aparece).
- [oráculo: `bash tests/cli/test-order-cold-entry.sh`] com a flag ligada: `risco: alto` sem recibo reprova; com `devolve` reprova; com `aprova` e sha diferente reprova; com `aprova` e sha igual passa; `risco: baixo` passa sem recibo.
- [oráculo: `bash tests/cli/test-order-cold-drift.sh`] `--accept` de ordem com `fecha_epico:` reprova sem `drift-<n>` e passa com `aprova`.
- [oráculo: `bash tests/cli/test-order-cold-off.sh`] flag desligada: `--entry-check`, `--accept` e `--create` saem iguais aos de hoje (comparação byte a byte com a fixture).
- [oráculo: `bash tests/cli/test-order-cold-rounds.sh`] terceiro `--cold-record` após dois `devolve` sai 1 com "escala ao Diretor".
- [oráculo: `bash tests/run-all.sh`] suíte do Maestro verde, catraca do `habits` incluída.
- [humano] o Diretor lê o `revisao-fria.md` e roda o pacote de uma ordem real de risco alto antes do aceite.

## Turno
- fatia: `lib/core-order-cold.sh`, `docs/contracts/revisao-fria.md`, os cinco testes, a emenda E29 no EPICS e o patch de roteamento em `docs/patches/`
- fim: `bash -c 'for t in bundle entry drift off rounds; do bash tests/cli/test-order-cold-$t.sh || exit 1; done; bash tests/run-all.sh'` sai 0 no tip do branch (os seis critérios com oráculo); patch pronto em `docs/patches/`, não aplicado; o relatório diz o que o Capitão aplica pelo botão
- teto: 3
- orçamento: 90 min · 150 turnos
- risco: baixo
- limite de CI e revisões: 2 rodadas de CI; P3 vira lista, não rodada
- fora: rodar o revisor (é do despachante, Spock hoje, daemon na Etapa 2); mudar `agents/revisor.md`; qualquer mudança no ponte-daemon; ligar a flag em projeto
- relatório: pela Ponte (`director_report`), formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido
- depende de: 059 e 060 (aceitas)

## Depois do aceite (não é desta ordem)
- Spock liga `cold_review_require: true` primeiro no NetForge e no ponte-daemon, e roda o revisor
  com `claude -p --agent revisor` sobre o `--cold-bundle`, sem outro contexto.
- Gate de avaliação: nos próximos 10 aceites de risco alto, contar P1 de plano pegos antes do turno
  de código contra o custo dos turnos de revisor. Sem P1 em 10, a trava volta a ser opcional.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run, /tmp/claude-<uid>/<cwd codificado>, nunca /tmp solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera por laço até a linha rc= no log; só depois se relata.

## Contrato de execução
- Trabalhe APENAS no branch `order/084-revisao-fria`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-84 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 084` (você não fecha a própria ordem).
