<!-- maestro-order v1
id: 006
ts: 2026-09-14T14:54:50-03:00
epoch: 1789408490
head: b3c3243c2a0d2274e80cd64e1c3b67b0e3c5ed74
branch: refactor/006-e24-nucleo-e-adaptadores
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
-->
# Ordem 006 — E24: nucleo, adaptadores e configuracao — o arquivo que audita os outros passa a ser auditado



## Contrato de execução
- Trabalhe APENAS no branch `refactor/006-e24-nucleo-e-adaptadores`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-6 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 006` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 5 — "contexto contido: o Maestro não pode causar o inchaço
que combate". O E24 estava proposto desde 2026-09-05 com critério de entrada
"E23 provado em uso por ≥1 semana". Cumprido: nove dias, e os dois sinais foram
observados ao vivo nesta sessão — `delegação PROVADA no log` e o `verify`
recusando de verdade com `sem verificação obrigatória: suite`.

## O achado que dá urgência, e a ironia dele

`bin/maestro` **não é sensoriado**. O hook e o CLI só olham arquivo com extensão
reconhecida (`base="${f##*/}"; ext="${base##*.}"` e `[[ "$ext" != "$base" ]] ||
continue`) — e `bin/maestro` não tem ponto no nome. O maior arquivo do repo, dez
vezes o teto de 400 linhas, é o ÚNICO isento da catraca anti-slop, por acidente
de nomenclatura.

Medido hoje contra o que o épico registrou em 05/09:

| arquivo | no épico | hoje | delta |
|---|---|---|---|
| `bin/maestro` | 4043 | **4380** | +337 |
| `hooks/session-start.sh` | 787 | **902** | +115 |
| `src/cli.ts` | 1271 | 1271 | 0 |

As +337 linhas do `bin/maestro` são os patches das ordens 003, 004 e 005 — os
consertos da família "prova que parece prova". **Cada conserto honesto engordou
o arquivo que o E24 existe para dividir, sem que nada acusasse.**

## Decisões do supervisor (2026-09-14) — implementar, não reabrir

**Item 1 — detectar por SHEBANG, não por nome.** Consertar só `bin/maestro`
deixaria o próximo executável sem ponto isento pelo mesmo acidente. Corrigir a
classe, não a instância.

**Item 2 — dívida DECLARADA com prazo, nunca baseline absorvido.** Palavras do
supervisor: *"absorver é exatamente 'prova que parece prova', a família que você
acabou de fechar; o teto desce a cada lote que sai, e a conta fica visível."*

**Item 4 — módulos em caminho NÃO-denylisted, com patch pequeno que só os
sourceia. Sem janela de edição direta em `bin/`.** Razão do supervisor: *"a
denylist existe para que ninguém escreva às cegas na ferramenta que audita as
outras. Janela de edição direta compraria conveniência pagando com a única
guarda que este repo tem sobre si mesmo."* O revisor lê arquivo novo, não diff
de 5 KB.

**Itens 6 a 9 aprovados:** um comando por lote com a suíte como gate entre eles,
nunca "divide tudo e roda no fim"; `src/cli.ts` é frente separada
(`typescript-pro`), não compete com a do bash; `hooks/` fica fora — o épico diz
"hooks continuam bash puro" e eles têm NFR de latência que um split ameaça; e o
**arquiteto planeja**, por H4: decisão estrutural, cross-sistema, cara de
reverter, no repo que audita os outros.

## Contrato de execução
- Trabalhe APENAS no branch `refactor/006-e24-nucleo-e-adaptadores`; NUNCA no main.
- Zonas CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/`, `hooks/` e `src/` não se editam: patch em `docs/patches/`.
- Um comando por lote; a suíte é o gate ENTRE lotes, não no fim.
- Gates locais antes do push: `shellcheck -x -P SCRIPTDIR --severity=error`,
  `bash -n`, `maestro habits --all`, suíte completa. Uma execução de CI por lote.
- Prove com o ledger: `maestro evidence --record --label order-6 -- bash tests/run-all.sh`.
- Direção vigente: INTENT v2, Prioridade 5.
- Absorva ANTES de commitar governança.
