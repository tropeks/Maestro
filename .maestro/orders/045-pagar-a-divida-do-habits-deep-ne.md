<!-- maestro-order v1
id: 045
ts: 2026-10-02T07:25:31-03:00
epoch: 1790936731
head: 2fe7d8ef7f05e989aeb6cb9eb545b17c20951c7a
branch: order/045-pagar-a-divida-do-habits-deep-ne
intent_version: 6
intent_hash: 31205cc5
author_session: 78325be8-9ba2-4a68-b281-22a419b849cb
-->
# Ordem 045 — pagar a divida do habits: deep-nesting 11 para 10 e oversized-function 13 para 6, antes de 09/10

## A decisão que a autoriza
Decisão do Diretor em 02/10, no relato da ordem 044: prorrogar UMA vez, por 7 dias, o prazo
da dívida declarada em `.maestro-habits.tsv` (de 29/09 para 09/10 23:59:59-03:00) e abrir
esta ordem para pagá-la. A dívida vencida derrubava `habits --all` na suíte (2 asserções),
na main limpa, sem relação com a 044.

## O que entrega
Levar `deep-nesting` de 11 para ≤10 e `oversized-function` de 13 para ≤6, decompondo (não só
movendo) as funções, no molde da ordem 015. Descer a régua no mesmo commit
(`maestro habits --baseline`). `bin/` e `hooks/` seguem por patch em `docs/patches/`,
aplicado por mão humana. Sem segunda prorrogação.

## Prova exigida
- `maestro habits --all` sai 0 com os dois alvos atingidos; suíte verde; recibo no tip.
- Nenhuma função nova acima do teto; testes existentes inalterados.

> **Execução headless:** a prova é `maestro habits --all` mais a suíte, sem humano no laço
> até a aplicação dos patches de `bin/`/`hooks/`. Nenhuma chamada externa.

## Contrato de execução
- Trabalhe APENAS no branch `order/045-pagar-a-divida-do-habits-deep-ne`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-45 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 045` (você não fecha a própria ordem).
