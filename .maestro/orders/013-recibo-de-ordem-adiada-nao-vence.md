<!-- maestro-order v1
id: 013
ts: 2026-09-16T06:43:32-03:00
epoch: 1789551812
head: 03f8056925287900d2feaf2109fe2dc1cd3ef31f
branch: fix/013-recibo-de-ordem-adiada
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: 6d8bf07e1fd15c8dcec9fcec8f19aca7c317933a
absorbed_at: 2026-09-16T09:31:48-03:00
absorbed_session: desconhecido
-->
# Ordem 013 — recibo de ordem adiada nao vence: deferred_by congela idade, arvore e ratchet



## Contrato de execução
- Trabalhe APENAS no branch `fix/013-recibo-de-ordem-adiada`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-13 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 013` (você não fecha a própria ordem).

## Por que esta ordem existe

**Quinto sintoma do mesmo defeito.** Caso real, em campo: o Vitali tem a ordem
004 acusando `VENCIDA` **todo dia** por algo que o Capitão **adiou por decisão**.
O gerente de lá inventou `deferred_by:` no cabeçalho porque o modelo não tem a
palavra — e nada lê esse campo.

A família, para quem ler depois:

| # | sintoma | estado |
|---|---|---|
| #6 | o carimbo de aceite invalidava a prova que o autorizou | corrigida |
| #12 | ordem absorvida não tinha estado terminal | corrigida |
| #13 | qualquer `.md` virava ordem pendente | corrigida |
| #18 | duas fontes discordando do estado da ordem | aberta |
| #20 | ordem recusada por DECISÃO não tem desfecho | aberta |
| **esta** | **recibo de ordem ADIADA vence todo dia** | — |

Todas dizem a mesma coisa: **o modelo não representa estados que o trabalho real
tem**, e quem paga é humano interrompido por cobrança impossível.

## O trabalho

Ordem com `deferred_by:` no cabeçalho — dentro das 20 linhas que `_order_field`
lê:

1. **O recibo dela não vence por IDADE.** O TTL existe para prova envelhecer
   enquanto o trabalho anda; trabalho adiado não anda.
2. **Não vence por MUDANÇA DE ÁRVORE.** O conteúdo mudar não invalida a prova de
   um trabalho que foi deliberadamente parado — invalidaria se ele fosse
   retomado, e retomar é tirar o `deferred_by`.
3. **Não conta como reprovação no ratchet** nem na contagem de pendentes.
4. A leitura DIZ o estado: `ADIADA por <quem> — prova congelada em <árvore>`.
   Nunca `VENCIDA`, que é mentira sobre um trabalho que ninguém abandonou.

`deferred_by` exige **quem adiou**, pelo mesmo motivo que `killed` exige razão
(E25/S-2501) e `absorbed_by` exige absorvente provada: adiar é desfecho, e
desfecho sem autor não se audita.

## Relação com a issue #20 — são distintas, e a distinção importa

A #20 pede estado terminal para ordem **recusada** (decidido NÃO fazer, nunca
volta). Esta trata ordem **adiada** (decidido fazer DEPOIS, volta).

Recusada é terminal; adiada é **suspensa**. Confundir as duas faria a ordem
adiada sumir da fila, que é o oposto do que se quer — ela deve continuar
visível, sem cobrar aceite nem acusar prova vencida.

Se o executor concluir que as duas devem compartilhar mecanismo, isso é decisão
de desenho: **PARE e reporte** antes de escolher.

## Contrato de execução
- Branch `fix/013-recibo-de-ordem-adiada`; NUNCA no main.
- CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
- Campo novo no cabeçalho da ordem é CONTRATO: emenda no `DATA_MODEL.md` no
  MESMO changeset, e o Vitali e os outros projetos leem esse cabeçalho —
  mudar a forma do que já existe é PARAR e chamar.
- Teste: ordem com `deferred_by` não acusa VENCIDA por idade nem por árvore
  mudada; ordem SEM o campo continua vencendo exatamente como hoje (a regressão
  que importa).
- Gates locais antes do push; `git clone` para cópia patchada.
- Prove com o ledger: `maestro evidence --record --label order-13 -- bash tests/run-all.sh`.
