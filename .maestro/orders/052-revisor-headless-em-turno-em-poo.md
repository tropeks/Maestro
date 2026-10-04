<!-- maestro-order v1
id: 052
ts: 2026-10-03T12:39:24-03:00
epoch: 1791041964
head: 41213f0a454bd6c2060d9faa41f91e36ad450047
branch: order/052-revisor-headless-em-turno-em-poo
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 052 — Revisor headless em turno, em pool

> Ordem do Capitão, 2026-10-03, do pacote da INTENT v56 (spock, seção "Direção 2026-10-03 - a linha de produção"; estende a v55). Esta peça é o **plano**: quem executa não fecha a própria ordem — `maestro order --accept` é do Diretor, e só depois da validação verde (v55 ponto 4).

## Por quê
O revisor é uma pane única: a fila de revisão espera a pane e o dono dela. Quebra o acoplamento (a) da v56. A matriz aprovada põe a revisão num **setor com pool de revisores em turno, compartilhado entre projetos**.

## Contrato
1. `maestro order --review-run <id>` dispara a revisão como turno `claude -p` headless, com bloco Turno (fatia/fim/teto/fora/relatório) gerado a partir da ordem e da árvore a revisar.
2. O revisor lê só: a ordem, o diff da árvore contra o merge-base, o brief e o INTENT. Read-only; achado priorizado, sem corrigir.
3. Resultado vira **recibo de revisão** na árvore (verde = sem achado bloqueante; vermelho = achados; vermelho devolve a ordem ao reparo). Relatório de formato fixo.
4. Paralelo: vários `--review-run` ao mesmo tempo, sem pane e sem lock global; o limite do pool é configurável (`review.pool` no `.maestro.yaml`) e a fila de entrada é a do daemon (ordem D1).
5. Compartilhado entre projetos: o revisor não carrega estado de projeto entre turnos.
6. Arquivos protegidos do Maestro (`hooks/`, `bin/`, `src/`) não são editados pelo executor: a mudança sai como patch em `docs/patches/` e o Capitão aplica (ou sob o consentimento escopado da ordem M5, quando existir).

## Prova
Teste com revisor simulado (sem chamada de modelo real): verde grava recibo verde, achado grava vermelho, dois em paralelo não se atrapalham. `maestro evidence --record --label order-52 -- bash tests/run-all.sh`.

Depende de: ordem 51 (Maestro) aceita.

## Turno

- fatia: o comando, o contrato do turno do revisor e o recibo
- fim: testes com revisor simulado verdes; `bash tests/run-all.sh` sai 0
- teto: 4
- fora: a fila e o pool no daemon (D1/D2), e qualquer chamada real a modelo
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Paralelismo:** esta ordem corre em paralelo com outras, independente da 050. Subagentes são permitidos DENTRO do turno para fatias independentes (cada um com escopo de arquivos disjunto, relatando em ESTADO). No máximo UMA suíte pesada (`bash tests/run-all.sh`) por vez, sozinha neste worktree — duas suítes no mesmo worktree se contaminam (`test-order-041`), e a forge segura no máximo uma corrida longa por vez entre as ordens em paralelo; antes de rodar, confira `pgrep -fa run-all`.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**: heredoc, `tee` e redirecionamento no Bash são barrados pelo guard (ordem 047).

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/052-revisor-headless-em-turno-em-poo`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-52 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 052` (você não fecha a própria ordem).
