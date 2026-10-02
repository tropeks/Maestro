<!-- maestro-order v1
id: 044
ts: 2026-10-02T07:04:09-03:00
epoch: 1790935449
head: a6f9ae16c1b5bf47e6e16935742341a416bb9820
branch: order/044-recibo-de-ordem-empilhada-o-cari
intent_version: 6
intent_hash: 31205cc5
author_session: 78325be8-9ba2-4a68-b281-22a419b849cb
-->
# Ordem 044 — recibo de ordem empilhada: o carimbo da anterior, commitado na main, nao vence o recibo

## O defeito
O carimbo de aceite da ordem A é commitado em `.maestro/orders/` na main. Isso quebra o
fast-forward dos branches empilhados sobre A; o rebase traz o carimbo para o tip e invalida
o recibo da B: `wtree_after` (`.maestro` congelado do index de quando foi gravado) ≠
`<branch>^{tree}` (`.maestro` de agora).

## O conserto
`lib/core-tree.sh`: `maestro_tree_same` compara árvores sem a entrada `.maestro`, nos dois
lados, falha fechada. Aplicado nos 5 comparadores (status, gate de verificações,
`--absorbed-by main`, `evidence --label`). `bin/` não muda (autoproteção); recibos antigos valem.

## Prova exigida
- `tests/cli/test-order-044-recibo-empilhado.sh`: vermelho antes (3 leitores), verde depois;
  controle negativo: conteúdo fora de `.maestro/` ainda vence o recibo.
- Suíte verde; recibo no tip; emenda DATA_MODEL v1.23 no mesmo changeset.

## Contrato de execução
- Trabalhe APENAS no branch `order/044-recibo-de-ordem-empilhada-o-cari`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-44 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 044` (você não fecha a própria ordem).

> **Execução headless:** a prova é o teste em sandbox (`tests/cli/test-order-044-recibo-empilhado.sh`) mais a suíte, sem humano no laço. Nenhuma chamada externa.
accepted_at: 2026-10-02T08:24:43-03:00
accepted_session: desconhecido
accepted_tree: 17b772dba895a5a921eba0e61919d4231e114edf
accepted_intent: 6
