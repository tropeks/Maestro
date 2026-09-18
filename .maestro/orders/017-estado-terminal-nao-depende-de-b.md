<!-- maestro-order v1
id: 017
ts: 2026-09-16T18:59:55-03:00
epoch: 1789595995
head: aa91b8f123465b6809bb25fb84bdc7071db42df3
branch: fix/017-estado-terminal-nao-depende-de-branch
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: desconhecido
-->
# Ordem 017 — estado terminal nao depende de branch existir: ausente distingue nunca existiu de absorvido



## Contrato de execução
- Trabalhe APENAS no branch `fix/017-estado-terminal-nao-depende-de-branch`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-17 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 017` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 4 — "prova mecânica antes de declaração". O estado da
ordem é o dado que o supervisor e outros projetos leem para decidir se
interrompem um humano. Hoje ele **mente na direção mais cara**: diz `aberta`
para trabalho que já terminou.

### O sintoma, medido no vulcan (2026-09-16)

```
.maestro/orders/002-lab-como-ambiente-de-prova-cript.md
  id: 002   branch: order/006-lab-prova
  absorbed_by: AUSENTE     accepted_at: AUSENTE
→ "estado":"aberta"  "branch_existe":false  "terminal":false
```

A ordem 002 do vulcan "reabre a cada merge" — na verdade nunca fechou, e o
único sinal de que existiu desaparece quando o branch some.

Contraste, no mesmo repo: a ordem 001 tem `accepted_at:` e lê
`aceita · terminal: true`, com `branch_existe: true` — ela ainda nem foi limpa.

### A CAUSA, e ela não é a que se supõe

**Não é o hash da árvore absorvente.** `absorbed_tree` aparece em três lugares
(`lib/cmd-order-json.sh:54`, `lib/cmd-order.sh:202` e a gravação em `:264`) e
nos três é apenas IMPRESSO. Nunca é comparado com nada, então não há invariante
de árvore para violar. E `_order_status` já testa `accepted_at` e `absorbed_by`
ANTES de tudo (`lib/core-order-state.sh:61-64`): os dois já fazem short-circuit
e já são terminais.

A causa é este ramo, em `lib/core-order-state.sh:65-68`:

```bash
br=$(_order_field "$f" branch)
if [[ -z "$br" ]] || ! git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1; then
  printf 'aberta'; return 0
fi
```

**"O branch não existe" tem dois significados opostos, e o código só conhece
um:**

| o que aconteceu | o que o código conclui |
|---|---|
| o branch nunca foi criado — nada começou | `aberta` ✔ |
| o branch mergeou e foi DELETADO — tudo terminou | `aberta` ✘ |

Deletar branch mergeado é o fim normal de toda ordem. Ou seja: o caminho feliz
do projeto rebaixa a ordem para "nada começou".

## O INVARIANTE que esta ordem instala

> **Ordem com prova no ledger nunca lê `aberta`.**

É testável e não depende de nada efêmero. O recibo é durável: ele sobrevive ao
branch, ao worktree e ao checkout — é justamente o artefato que este projeto
criou para ser a prova. `_order_evidence_candidates` (já existe em
`lib/core-order-state.sh`) é como se acha o recibo de uma ordem pelo id.

Derivação alvo, quando o branch está ausente:

- **sem recibo nenhum** → `aberta`. Continua certo: nada começou.
- **com recibo** → NÃO é `aberta`. Trabalho aconteceu, o branch sumiu, e não há
  carimbo terminal: isso é uma ordem que precisa de DECISÃO HUMANA, e o estado
  tem de dizer isso em voz alta em vez de fingir que ela é nova.

## TRAVA DE CONTRATO — pare e chame

O estado da ordem é lido de fora: pelo supervisor, pelo `watcher.ts` do
ponte-daemon, e por qualquer projeto que rode `maestro order --status N --json`.

1. **Nome de campo e forma do objeto JSON não mudam.** Campo novo é sempre
   ADITIVO (DATA_MODEL §9, emenda v1.15).
2. **Valor NOVO no enum de `estado` é mudança de contrato.** Se o seu desenho
   precisar de um valor novo, ele exige emenda no `DATA_MODEL` **no MESMO
   changeset** — e a numeração da emenda é GLOBAL com posição POR SEÇÃO:
   descubra a MAIOR com
   `grep -oE "Emenda v1\.[0-9]+" docs/architecture/DATA_MODEL.md | sort -t. -k2 -n | tail -1`,
   nunca a última linha do arquivo. Erro já cometido duas vezes neste projeto.
3. Se você concluir que o tratamento certo exige valor novo no enum, **PARE e
   chame ANTES de escrever a emenda**. Acrescentar estado é decisão de modelo,
   não de implementação — foi assim que `absorvida` (ordem 004) e `adiada`
   (ordem 013) entraram, cada uma com desenho humano.
4. `terminal` e `pede_aceite` no JSON são o que consumidor externo lê para
   decidir se interrompe humano. Seja explícito no relatório sobre o que cada um
   passa a valer nos casos novos.

## Fora desta ordem

A **coerência id↔branch↔recibo** — a 002 do vulcan declara `branch:
order/006-lab-prova` e há recibo `vulcan-…-order-6` ao lado de `order-2`, e
nenhum dos dois lados reclama. É defeito real e é ordem SEPARADA, por decisão do
diretor: duas mudanças, dois PRs. Se você tropeçar nisso, **relate e siga** —
não conserte aqui.

## Prova exigida

- Teste que reproduz o caso do vulcan: ordem com recibo, branch ausente, sem
  carimbo → **não** lê `aberta`. Esse teste tem de FALHAR contra o código atual;
  mostre as duas pontas, vermelha e verde.
- Teste do caso legítimo: ordem sem recibo e sem branch → segue `aberta`.
- Teste de que `aceita` e `absorvida` continuam terminais com o branch deletado.
- Suíte completa verde.
- `maestro habits` limpo em cada arquivo tocado, medido um a um
  (`lib/core-order-state.sh` está em 179/400 — há folga, mas confira).
- `maestro doctor` sem mudança de veredito.
- Recibo: `maestro evidence --record --label order-17 -- bash tests/run-all.sh`.
- Confira as ordens 001–016 DESTE repo antes e depois: nenhuma pode mudar de
  estado por causa desta mudança. Se alguma mudar, é achado — relate antes de
  seguir.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-017 -b fix/017-estado-terminal-nao-depende-de-branch main`.
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
  `tests/` se edita direto.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`.
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`, nunca `f; return $?`.
  (Armadilha paga na ordem 015.)
- `bash -n` por arquivo é o gate de sintaxe; `shellcheck --severity=error` não
  pega sintaxe em módulo sourceado.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 017`.
accepted_at: 2026-09-17T10:39:37-03:00
accepted_session: desconhecido
accepted_tree: 07c08ebf846988a3635f32b317bba30e66f18134
accepted_intent: 3
