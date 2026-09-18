<!-- maestro-order v1
id: 018
ts: 2026-09-17T07:39:04-03:00
epoch: 1789641544
head: aa91b8f123465b6809bb25fb84bdc7071db42df3
branch: fix/018-coerencia-id-branch-recibo
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: desconhecido
-->
# Ordem 018 — coerencia id-branch-recibo: tres identificadores sem ninguem reconciliando



## Contrato de execução
- Trabalhe APENAS no branch `fix/018-coerencia-id-branch-recibo`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-18 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 018` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 4 — "prova mecânica antes de declaração". Uma ordem tem
**três identificadores** e nada os reconcilia:

1. o `id:` no cabeçalho do arquivo;
2. o `branch:` declarado no mesmo cabeçalho;
3. o **rótulo do recibo** no ledger.

`_order_evidence_candidates` (`lib/core-order-state.sh:42-45`) deriva o rótulo
**só do id**:

```bash
printf 'order-%s\n'   "$((10#$1))"
printf 'order-%03d\n' "$((10#$1))"
```

O `branch:` nunca entra na conta. Então uma ordem pode declarar um branch de
outra ordem e ninguém percebe — nem o CLI, nem o `doctor`, nem o supervisor.

### O caso real, medido no `~/dev/vulcan` (2026-09-16)

```
.maestro/orders/002-lab-como-ambiente-de-prova-cript.md
  id: 002
  branch: order/006-lab-prova      ← branch de OUTRA ordem
```

E no ledger existem **os dois** recibos, lado a lado:
`vulcan-2835f8be-order-2` e `vulcan-2835f8be-order-6`.

A ordem 002 aponta para trabalho que se prova sob outro rótulo. Os dois lados
estão calados: o `--status` da 002 procura `order-2`/`order-002` e nunca olha
para o branch; nada compara o branch declarado com o id do arquivo.

## O QUE ESTA ORDEM FAZ — e o que ela explicitamente NÃO faz

**FAZ: tornar a incoerência VISÍVEL.** Quando o `branch:` declarado não
corresponde ao `id:` da ordem, isso tem de aparecer — no `--status`, no
`--status --json` e no `doctor`.

**NÃO FAZ: adivinhar qual dos três está certo.** Não renomeie branch, não
mova recibo, não "corrija" o id. Os três identificadores são escritos por mãos
diferentes em momentos diferentes, e escolher um vencedor automaticamente é
inventar verdade. Isto é diagnóstico, não reparo.

Se você se pegar escrevendo código que ESCOLHE entre os três, saiu do escopo.

## O desenho, em uma linha

Um predicado que responde "o `branch:` declarado é coerente com o `id:` desta
ordem?" e um lugar onde a resposta negativa aparece. Nada mais.

Cuidado com o que é convenção e o que é regra: o repo Maestro usa
`refactor/015-…`, `fix/016-…`, `chore/…`; o vulcan usa `order/001-…`. **O
padrão de prefixo varia por projeto e não é contrato.** O que é verificável é o
NÚMERO embutido no nome do branch contra o `id` do arquivo. Se você não
conseguir extrair número do branch com confiança, o veredito é "não sei
dizer", não "incoerente" — falso positivo aqui vira ruído que ninguém lê, e
ruído que ninguém lê é como a #9 nasceu.

## TRAVA DE CONTRATO

O estado da ordem é lido de fora: supervisor, `watcher.ts` do ponte-daemon, e
qualquer projeto que rode `maestro order --status N --json`.

- **Nome de campo e forma do objeto JSON não mudam.** Campo novo é sempre
  ADITIVO (DATA_MODEL §9, emenda v1.15).
- **Nenhum valor novo no enum de `estado`.** Incoerência de identificador não é
  estado da ordem — é um aviso ao lado dela. Se o seu desenho precisar de
  estado novo, você entendeu o problema errado: PARE e chame.
- Emenda do `DATA_MODEL` no MESMO changeset se houver campo novo. A maior é
  **v1.15** hoje — confirme com
  `grep -oE "Emenda v1\.[0-9]+" docs/architecture/DATA_MODEL.md | sort -t. -k2 -n | tail -1`
  — e a posição é POR SEÇÃO, nunca no fim do arquivo. Erro já cometido duas
  vezes aqui.
- **Mudança de veredito do `doctor`: PARE e chame.** Acrescentar um aviso ao
  doctor muda a contagem de checagens; diga no relatório o que muda e espere se
  o VEREDITO (saudável/não) mudar para qualquer projeto.

## Atenção ao ordenamento com a 017

A ordem 017 está mexendo em `_order_status` no MESMO arquivo
(`lib/core-order-state.sh`) para tratar branch ausente. **Ela vai primeiro.**
Antes de começar, confira se a 017 já foi aplicada em `main` e construa em cima
do que estiver lá. Se houver conflito de patch, **relate e pare** — não resolva
conflito adivinhando a intenção da outra ordem.

## Prova exigida

- Teste que reproduz o caso do vulcan: arquivo com `id: 002` e
  `branch: order/006-lab-prova` → a incoerência aparece. Tem de FALHAR contra o
  código atual; mostre as duas pontas.
- Teste do caso coerente: `id: 015` com `branch: refactor/015-…` → silêncio.
  **Nenhum aviso.**
- Teste do caso "não sei dizer": branch sem número extraível → nem coerente nem
  incoerente, e nada de falso positivo.
- **Confira as ordens 001–018 DESTE repo**: quantas acusam incoerência? A
  resposta esperada é ZERO. Se alguma acusar, é achado — relate antes de seguir,
  porque ou o repo tem uma ordem torta ou o seu predicado tem falso positivo.
- Suíte completa verde em cópia patchada.
- `maestro habits` limpo em cada arquivo tocado, um a um.
- `maestro doctor` sem mudança de VEREDITO.
- Recibo: `maestro evidence --record --label order-18 -- bash tests/run-all.sh`.

## Fora desta ordem

Os **guards de PENDENTE ancorados em `bin/maestro`** que o E24 deixou obsoletos
são a ordem **019**, separada de propósito: mudança diferente, blast radius
diferente, PR diferente. Se tropeçar, relate e siga.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-018 -b fix/018-coerencia-id-branch-recibo main`.
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
  `tests/` e `docs/` se editam direto.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`.
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`, nunca `f; return $?`.
- `bash -n` por arquivo é o gate de sintaxe.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 018`.
