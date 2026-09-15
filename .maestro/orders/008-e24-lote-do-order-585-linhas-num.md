<!-- maestro-order v1
id: 008
ts: 2026-09-15T09:48:37-03:00
epoch: 1789476517
head: 9061af6b71139a373aaebd8f1d249a728c2b3a8c
branch: refactor/008-e24-lote-order
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: 33638b86912af8924bebf2b5259752c061ca6bd2
absorbed_at: 2026-09-15T11:32:46-03:00
absorbed_session: desconhecido
-->
# Ordem 008 — E24 lote do order: 585 linhas numa funcao so — o lote que decide se o metodo escala



## Contrato de execução
- Trabalhe APENAS no branch `refactor/008-e24-lote-order`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-8 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 008` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 5. **É o lote que decide se o E24 escala.**

LARGADA CRONOMETRADA: 2026-09-15T09:48:37-03:00. A duração é entregável: o prazo
da dívida (2026-09-27) é PROVISÓRIO e se recalcula no dia em que este lote
fechar — o número novo é dito em voz alta ainda que seja igual.

## O alvo não é o que o plano supunha

Medido, não estimado. A seção `order` (E15), `bin/maestro:1986-2573`, **não são
587 linhas para mover**. É:

- **uma única função**, `cmd_order()`, com **585 linhas**;
- **13 funções aninhadas** dentro dela;
- a maior, `_order_intent_gate()`, com **294 linhas** — 5x o teto de 60;
- todas fechando sobre os LOCAIS de `cmd_order`: `$oid` (37 usos), `$proj` (36),
  `$sid` (18), `$odir` (14).

Palavras do supervisor no gate: *"585 linhas numa função com 13 aninhadas que
fecham sobre locais não é mover arquivo, é desfazer acoplamento — e era
exatamente a incógnita."*

Os lotes anteriores moveram texto. Este desfaz acoplamento, e é por isso que ele
é a prova do método.

## O critério real

**Se `_order_intent_gate` não sair decomposta em funções com nome de domínio, o
lote NÃO cumpriu — por mais que o arquivo encolha.** O tamanho do arquivo é o
sintoma; a decomposição é o objetivo (a dívida do E24 é `oversized-function`).

Ordem de trabalho: menores primeiro. `_order_field` (6 linhas) firma a convenção
de passagem de estado **antes de ela custar caro**; `_order_intent_gate` por
último, já sob a convenção provada.

## A catraca VAI SUBIR, e isso se declara antes

O sensor tem ponto cego: o detector de função está ancorado na coluna 0
(`hooks/lib/habit-sensors.awk:182`), então **função indentada é invisível**. Por
isso ele acusa `cmd_order` com 132 linhas quando ela tem 585, e não reporta
nenhuma das 13 aninhadas.

Içá-las para escopo de módulo as torna VISÍVEIS. A contagem de
`oversized-function` vai subir neste lote. **Não é regressão — é o ponto cego
fechando.** Exigência do supervisor: isso vai POR ESCRITO NO PR, com o número
medido, antes do merge. *"Declarar antes que a catraca sobe, e quanto, é a
diferença entre dívida e surpresa."*

O defeito do detector está registrado na issue #25 e NÃO se conserta aqui — lote
existe para mover e decompor código, não para consertar a régua.

## O gatilho que o supervisor vai cobrar

**Mais de DUAS alterações de teste: PARE e chame o humano.** Razão dele, textual:
*"teste que muda para acomodar refactor é o refactor mudando o que o teste
provava."*

Cobertura existente, no ciclo real: `tests/cli/test-order.sh`,
`test-order-issue6.sh`, `test-order-issue12.sh`, `test-order-issue13.sh`,
`test-order-006-habits-debt.sh`.

Outros gatilhos de reversão: qualquer mudança de veredito do `doctor`; módulo
que não fique ≤400 linhas com funções ≤60 sem inventar helper sem domínio.

## Contrato de execução
- Trabalhe APENAS no branch `refactor/008-e24-lote-order`; NUNCA no main.
- Zonas CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
  `lib/` é denylisted desde o Lote 0 — o módulo é ARQUIVO COMPLETO no patch.
- Diretiva `# shellcheck source=lib/cmd-order.sh` obrigatória. E ATENÇÃO:
  `shellcheck --severity=error` NÃO pega erro de sintaxe dentro do módulo
  sourceado, nem com a diretiva (verificado no Lote 1). O gate de sintaxe é
  `bash -n` no módulo.
- Gates locais antes do push: `shellcheck`, `bash -n`, `maestro habits --all`,
  suíte completa. Use `git clone` para a cópia patchada, NUNCA `git archive`
  (cópia sem `.git` faz `habits --all` sair 2 e inventa falhas espúrias).
- Prove com o ledger: `maestro evidence --record --label order-8 -- bash tests/run-all.sh`.
- Direção vigente: INTENT v2, Prioridade 5.
- Absorva ANTES de commitar governança.
- Registre a HORA DE CHEGADA. A duração é entregável.
