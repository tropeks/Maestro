<!-- maestro-order v1
id: 003
ts: 2026-09-12T14:34:28-03:00
epoch: 1789234468
head: 7a6ac99bf1d077c78800fa6752aa0364930ea3a9
branch: fix/003-wtree-exclui-maestro
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
-->
# Ordem 003 — issue #6: o carimbo de aceite invalida o recibo que o autorizou — wtree exclui .maestro/



## Contrato de execução
- Trabalhe APENAS no branch `fix/003-wtree-exclui-maestro`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-3 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 003` (você não fecha a própria ordem).

## Por que esta ordem existe

Conserta a issue #6 pela saída principal. Autoriza-se pela Prioridade 4 do
INTENT v2 — "prova mecânica antes de declaração": o defeito destrói justamente a
prova, e enquanto ele existir o ritual de recibo pune quem o cumpre.

O defeito é circular: `maestro order --accept N` grava `accepted_at`,
`accepted_session` e `accepted_tree` em `.maestro/orders/NNN.md`
(`bin/maestro:2375`, `:2403`); o fingerprint vem de `git add -A` num index
temporário (`bin/maestro-wtree:43`), que respeita o `.gitignore` e portanto
ENXERGA `.maestro/` em quem segue E15/E22; a validação compara
`w_now != wtree_after` e conclui "conteúdo mudou desde a prova"
(`bin/maestro:2574`). Aceitar a ordem invalida o recibo que autorizou o aceite.

Caso real: NetForge, ordem 016, 2026-09-12, suíte de ~8 minutos re-rodada para
provar código byte-idêntico.

## O trabalho

1. `bin/maestro-wtree` passa a excluir `.maestro/**` do fingerprint — estado de
   governança não é código provado pela suíte. Precedente no próprio repo:
   `bin/maestro:1699` já usa `:(exclude).maestro/**` na lógica de drift de docs.
2. `accepted_tree` como equivalência onde couber: o dado já é gravado e já é
   lido em `bin/maestro:2177-2182`, `:2279`, `:2328` — falta a validação do
   recibo aceitar `w_now == accepted_tree` como equivalente a `wtree_after`.
3. Teste que reproduz o caso do NetForge — grava recibo, carimba o aceite
   depois, e exige que a validação siga VÁLIDA. Tem de FALHAR antes da correção
   e PASSAR depois; sem os dois lados o teste não prova nada.

## Restrição de execução — a denylist barra o alvo

`bin/` está na denylist de autoproteção do gate (ADR-003 v1.2) e `maestro
consent` não a levanta para a MÁQUINA, só para dados. Verificado ao vivo nesta
ordem: `bin/maestro-wtree` e `bin/maestro` respondem "edição bloqueada — este
caminho é protegido pela denylist".

Portanto: a correção de `bin/` sai como **patch** em `docs/patches/`, e quem
aplica é o Capitão. O teste vai em `tests/`, que é editável. O merge do PR é do
Capitão de qualquer forma.

Consequência que o executor tem de resolver, não contornar: o teste não pode
passar contra um `bin/` não corrigido. Prove os dois lados com uma CÓPIA do
`bin/` num diretório temporário — a real sem patch (falha) e a copiada com patch
aplicado (passa) — e diga no relatório exatamente como provou. Não maquie.

## Contrato mudou — emenda no mesmo changeset

O fingerprint é contrato: `DATA_MODEL.md:245-251` (emenda v1.4, E7/S-701) define
o `wtree` e `API_SPEC.md:339` define a leitura do recibo por rótulo. Excluir
`.maestro/` muda o que o fingerprint significa. A emenda vai no MESMO changeset
(CLAUDE.md), citando doc e seção, e deve responder explicitamente à pergunta que
a issue #6 levanta: `.maestro/` entra ou não no que a suíte prova? Hoje a
resposta é acidental — herdada de o diretório estar ou não no `.gitignore` de
cada projeto.

## Contrato de execução
- Trabalhe APENAS no branch `fix/003-wtree-exclui-maestro`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- `bin/` não se edita: patch em `docs/patches/`, aplicação é do Capitão.
- Prove com o ledger: `maestro evidence --record --label order-3 -- bash tests/run-all.sh` no tip do branch, com a forge vazia e o load ao lado.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`), Prioridade 4.
- Medição de latência sem load ao lado é inválida; sob carga o veredito é inconclusivo, nunca regressão.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 003`.
