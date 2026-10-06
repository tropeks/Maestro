<!-- maestro-order v1
id: 053
ts: 2026-10-03T12:39:25-03:00
epoch: 1791041965
head: 41213f0a454bd6c2060d9faa41f91e36ad450047
branch: order/053-consentimento-de-patch-por-escop
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
deferred_by: spock 2026-10-06 regra da subtracao
-->
# Ordem 053 — Consentimento de patch por escopo, hash e validade

> Ordem do Capitão, 2026-10-03, do pacote da INTENT v56 (spock, seção "Direção 2026-10-03 - a linha de produção"; estende a v55). Esta peça é o **plano**: quem executa não fecha a própria ordem — `maestro order --accept` é do Diretor, e só depois da validação verde (v55 ponto 4).

## Por quê
Arquivo protegido do Maestro (`hooks/`, `bin/`, `src/`) só muda com o Capitão presente na ação aprovada; a esteira para. Quebra o acoplamento (d) da v56. Decisão do Capitão: o Capitão aprova **uma vez, por escopo, com hash do diff e validade**, e a estação aplica sozinha dentro dele; fora do escopo continua parando.

## Contrato
1. Estende `maestro consent` (S-1005) com consentimento de **patch**: lista fechada de arquivos, hash do diff aprovado, validade (data/hora de fim) e a ordem a que serve.
2. A estação aplica o patch sozinha **só se** os arquivos tocados ⊆ escopo, o hash do diff bate e a validade não venceu. Qualquer divergência: para, relata, não aplica.
3. Cada aplicação e cada recusa grava auditoria no ledger (quem, ordem, hash, resultado).
4. O consentimento é do Capitão e só dele: nenhum agente cria, estende ou renova.
5. Esta ordem **mexe em arquivo protegido**: a própria entrega sai como patch em `docs/patches/` e **para no aval do Capitão** — é a única do pacote que depende dele para ser aplicada.

## Prova
Testes em sandbox: dentro do escopo aplica; arquivo fora, hash diferente e validade vencida recusam, cada um por motivo distinto. `maestro evidence --record --label order-53 -- bash tests/run-all.sh`.

Depende de: nada (pode correr em paralelo com M1 a M3).

## Turno

- fatia: o desenho do escopo/hash/validade e a suíte em sandbox, até o patch pronto
- fim: testes de sandbox verdes e patch pronto em docs/patches; aplicar é do Capitão
- teto: 4
- fora: aplicar o patch e qualquer consentimento real em arquivo protegido
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Paralelismo:** esta ordem corre em paralelo com outras, independente da 050. Subagentes são permitidos DENTRO do turno para fatias independentes (cada um com escopo de arquivos disjunto, relatando em ESTADO). No máximo UMA suíte pesada (`bash tests/run-all.sh`) por vez, sozinha neste worktree — duas suítes no mesmo worktree se contaminam (`test-order-041`), e a forge segura no máximo uma corrida longa por vez entre as ordens em paralelo; antes de rodar, confira `pgrep -fa run-all`.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**: heredoc, `tee` e redirecionamento no Bash são barrados pelo guard (ordem 047).

> **Parada no aval do Capitão:** o turno termina no patch pronto e testado em sandbox. NÃO aplique o patch, NÃO conceda consentimento real em arquivo protegido e NÃO siga para a próxima fatia sem o aval do Capitão por escrito. Relate e pare.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/053-consentimento-de-patch-por-escop`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-53 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 053` (você não fecha a própria ordem).
