<!-- maestro-order v1
id: 004
ts: 2026-09-14T09:43:30-03:00
epoch: 1789389810
head: c74b3070c5fc06ebb4ae09f94b9c311b48fb2c37
branch: fix/004-modelo-de-estados-da-ordem
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: ba6da2694df2154efc9f3fc854ba22e140912561
absorbed_at: 2026-09-14T12:58:00-03:00
absorbed_session: desconhecido
-->
# Ordem 004 — o modelo de estados da ordem: absorvida termina, e nem todo .md e ordem (issues 12 e 13)



## Contrato de execução
- Trabalhe APENAS no branch `fix/004-modelo-de-estados-da-ordem`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-4 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 004` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 4 — "prova mecânica antes de declaração". As duas issues
que esta ordem fecha atacam o mesmo ponto: o Maestro não sabe distinguir
estados e formas que o trabalho real tem, e por isso cobra o que não existe e
conta o que não é.

Custo já pago, e mensurável: as ordens 001 e 002 foram entregues, provadas e
mergeadas (PRs #4, #5, #10) e seguem sem estado terminal. O cutucão
"provada e sem aceite" disparou SEIS vezes em três dias, cobrando um aceite que
o modelo torna impossível.

## Issue #12 — a ordem absorvida não termina

`_order_status` (`bin/maestro:2075-2077`) tem um único caminho terminal,
`accepted_at`, e ele exige prova no tip do branch DAQUELA ordem
(`_order_proof_tree`, `:2101-2115`). Branch mesclado e apagado é
indistinguível de branch que nunca existiu.

Duas portas de entrada, ambas com caso real:
- absorção por OUTRA ordem — NetForge 018 dentro da 016;
- absorção pelo MAIN via PR — Maestro 001 e 002, já carimbadas
  `absorbed_by: main` em `d394a47` (documentação; o CLI ainda ignora o campo).

Entrega: `maestro order --accept N --absorbed-by <M|main>` grava
`absorbed_by`/`absorbed_tree`, o verify aceita a árvore da absorvente como
prova, e o estado derivado vira terminal e DISTINTO de `aceita` — quem audita
precisa ver a diferença entre provar o próprio trabalho e ser provado junto de
outro. A absorvente tem de estar ela mesma provada no carimbo: absorver não
pode virar porta dos fundos para aceitar sem prova.

## Issue #13 — nem todo `.md` em `.maestro/orders/` é ordem

`hooks/session-start.sh:467` e `:727` iteram sobre `*.md` e tratam todo arquivo
como ordem; a única exclusão é `grep -q '^accepted_at: '`.

Em ordem de gravidade:
1. **Comportamento do gate.** O laço da linha 467 acumula o campo `frozen` de
   cada arquivo não-aceito para montar as zonas congeladas da sessão. Um `.md`
   solto com `frozen:` nas 20 primeiras linhas entra na política. Não afrouxa o
   gate — só congela caminho que ninguém decidiu congelar, e a origem é
   praticamente irrastreável.
2. A contagem `ordens: N pendente(s)` infla com rollback, duplicata e absorvida,
   e alimenta a injeção do SessionStart e o cutucão do supervisor.
3. `absorbed_by` não é honrado (depende da #12).
4. Id duplicado conta duas vezes; nada valida unicidade.

Caso real: Vitali, doc `Rollback — ordem 002`, cutucão repetido cinco vezes.

Entrega: os dois laços exigem carimbo de ordem válido (`<!-- maestro-order v1`
+ `id:` bem-formado) antes de considerar o arquivo; `absorbed_by` entra no mesmo
teste de exclusão que `accepted_at`; `maestro order --list` acusa id duplicado
em vez de listar as duas entradas calado. E decidir explicitamente o que fazer
com `.md` que não é ordem: ignorar em silêncio foi o que produziu o caso do
Vitali — cinco cutucões sem causa visível.

## Restrição de execução — tudo sai como patch

`bin/` e `hooks/` estão na denylist de autoproteção do gate (ADR-003 v1.2), e
`maestro consent` não a levanta para a MÁQUINA. Verificado ao vivo na ordem 003.
Logo: as correções de `bin/maestro` e `hooks/session-start.sh` saem como patch
em `docs/patches/`, e quem aplica é o Capitão. Testes vão em `tests/`, que é
editável.

Lição da 003, que é contrato desta ordem: **teste novo não pode exigir patch já
aplicado.** Ele detecta o MECANISMO e reporta `PENDENTE` enquanto o patch não
entrou, cobrando de verdade depois — senão o PR nasce impossível de mergear.

## Contrato de execução
- Trabalhe APENAS no branch `fix/004-modelo-de-estados-da-ordem`; NUNCA no main.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- `bin/` e `hooks/` não se editam: patch em `docs/patches/`.
- Gates locais ANTES do push (ordem de economia de CI do supervisor, 2026-09-13):
  `shellcheck -x -P SCRIPTDIR --severity=error`, `bash -n`, `maestro habits --all`,
  suíte completa. Uma execução de CI por ordem, no tip final.
- Prove com o ledger: `maestro evidence --record --label order-4 -- bash tests/run-all.sh`.
- Direção vigente na criação: INTENT v2, Prioridade 4.
- Contrato mudou? Emenda no MESMO changeset (DATA_MODEL para o campo novo).
- O aceite é do diretor: `maestro order --accept 004`.
