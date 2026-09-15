<!-- maestro-order v1
id: 009
ts: 2026-09-15T13:28:37-03:00
epoch: 1789489717
head: a17acd722f3c6d91f72e2caad05e890c3b85ba0c
branch: refactor/009-e24-evidence-habits-retro
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: 87eb6d43d17d64a4ca6e7c82fd60c91e9a82c187
absorbed_at: 2026-09-15T17:08:37-03:00
absorbed_session: desconhecido
-->
# Ordem 009 — E24 lote encadeado: evidence, habits e retro — e o evidence vira dono do formato do recibo



## Contrato de execução
- Trabalhe APENAS no branch `refactor/009-e24-evidence-habits-retro`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-9 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 009` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 5. **Três lotes numa ordem só**, por decisão do supervisor,
e a razão é o número que o lote do `order` produziu: o gargalo é o **custo fixo
do ciclo**, não a dificuldade. Três lotes separados custariam três ciclos para o
mesmo trabalho.

LARGADA CRONOMETRADA: ver `ts:` no cabeçalho. A duração é entregável.

Razões do encadeamento, do supervisor:
1. o gargalo é o ciclo, não a dificuldade — três ciclos para o mesmo trabalho é
   desperdício medido, não suposto;
2. os três são da **mesma família** (leem e escrevem o mesmo ledger), então a
   convenção de passagem de estado firmada no primeiro vale de graça nos outros;
3. **o critério de saída NÃO muda**: `maestro habits` limpo em CADA módulo novo,
   medido um a um, nunca no conjunto.

## Os alvos

| seção | linhas em bin/maestro |
|---|---|
| `evidence` (E13) | 2061-2288, 227 |
| `retro` (E10) | 2861-3075, 214 |
| `habits` (E9) | 3075-3291, 216 |

## O acoplamento que já foi encontrado — e a decisão sobre ele

**Não é chamada de função. É duplicação de conhecimento**, que é pior porque não
aparece em grafo de dependência nenhum:

- `evidence` (`bin/maestro:2175`, `:2217`) escreve e lê o formato do recibo:
  `wtree_before=`, `wtree_after=`, `exit=`;
- `retro` (`:3034-3042`) varre `$MAESTRO_HOME/evidence/*` e faz
  `grep -q '^exit=0$'` POR CONTA PRÓPRIA, sem chamar nada do `evidence`.

Palavras do supervisor: *"duplicação de conhecimento que não aparece em grafo de
dependência é a pior classe de acoplamento que existe, porque nem uma ferramenta
nem uma revisão a enxergam; só a descobre quem mexe. É literalmente o defeito que
abriu esta sessão, com o filtro duplicado entre hook e CLI."*

**DECISÃO: opção 1 — `lib/core-evidence.sh` é o DONO do formato do recibo.** O
`retro` passa a usar o leitor do módulo em vez de reimplementar.

Argumento histórico que decidiu: o recibo ganhou `load1m_x100`, `ncpu` e
`inconclusive` na ordem 005, há dois dias. **O `retro` não sabe de nenhum dos
três.** Ele já conta errado — só não reprova porque olha um campo só.

## DECLARAÇÃO OBRIGATÓRIA: este lote carrega trabalho do vizinho

O bloco de leitura do ledger no `cmd_retro` (`bin/maestro:3034-3042`, **9
linhas**) sai do `retro` e vira responsabilidade do `core-evidence`. Isso é
trabalho do `retro` sendo pago pelo lote do `evidence`.

**Declare isso na tabela de descida da régua**, com a quantidade, para não
atribuir ao `evidence` uma dívida que era do vizinho. Palavras do supervisor:
*"medição que mente a favor é do mesmo tipo de defeito que estamos fechando."*

## O TESTE QUE PROVA A POSSE — exigência do supervisor

Depois que `_ev_read` existir: **acrescente um campo novo ao recibo num teste e
prove que o `retro` o enxerga SEM NINGUÉM TOCAR NO `retro`.**

*"Se não passar, o dono do formato não é dono de verdade."*

Este teste é o entregável central da ordem. Sem ele, a opção 1 é reorganização
de arquivo com discurso de arquitetura.

## Travas, porque encadear aumenta o raio

- **Gatilho de reversão: DUAS alterações de teste no TOTAL da ordem**, não por
  módulo. Estourou no segundo? **PARE com o primeiro já bom e chame o humano.**
- **Acoplamento não previsto**: se ao decompor aparecer dependência que esta
  ordem não mapeou, é sinal de que a fronteira está errada — **PARE e reporte
  ANTES de escolher onde cortar**. Foi assim que a duplicação acima apareceu.
- Qualquer mudança de veredito do `doctor` é gatilho.

## Contrato de execução
- Trabalhe APENAS no branch `refactor/009-e24-evidence-habits-retro`; NUNCA no main.
- Zonas CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
- Convenção de passagem de estado: a firmada no lote do `order` — parâmetro
  posicional, nada de fechamento sobre local de outra função.
- `shellcheck --severity=error` NÃO pega erro de sintaxe em módulo sourceado. O
  gate de sintaxe é `bash -n` no módulo.
- Cópia patchada com `git clone`, NUNCA `git archive`.
- Prove com o ledger: `maestro evidence --record --label order-9 -- bash tests/run-all.sh`.
- Direção vigente: INTENT v2, Prioridade 5.
- Registre a HORA DE CHEGADA.
