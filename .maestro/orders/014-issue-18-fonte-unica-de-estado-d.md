<!-- maestro-order v1
id: 014
ts: 2026-09-16T09:31:59-03:00
epoch: 1789561919
head: 513591acdad8c9e05c338532e2de8e34592c26ae
branch: fix/014-status-json
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: 9c819f5ca8d335c6984e7d625494268d0b10a192
absorbed_at: 2026-09-16T11:50:42-03:00
absorbed_session: desconhecido
-->
# Ordem 014 — issue 18: fonte unica de estado da ordem — --status --json para o supervisor ler em vez de recalcular



## Contrato de execução
- Trabalhe APENAS no branch `fix/014-status-json`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-14 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 014` (você não fecha a própria ordem).

## Por que esta ordem existe

Fecha a **issue #18**, e ela subiu na fila por um argumento de dívida crescente:
**cada estado novo que o Maestro cria aumenta o buraco.**

O supervisor mora em repo próprio e **recalcula** a derivação de estado da ordem
por conta. Como a derivação vive aqui e evolui aqui, as duas leituras divergem —
e a que interrompe humano é a que erra.

Histórico medido nesta sessão, e é o argumento inteiro:

| estado | criado em | o supervisor conhece? |
|---|---|---|
| `aberta`, `em_execucao`, `provada`, `aceita` | original | sim |
| `absorvida` | ordem 004 (issue #12) | **não** |
| `adiada` | ordem 013 | **não** |

**Catorze interrupções** nesta sessão cobrando aceite de ordem que já tinha
estado terminal — sete antes de `absorvida` existir (issue #12, já corrigida) e
sete depois, porque o consumidor não a conhece. **Zero ações possíveis em todas.**

## O trabalho

`maestro order --status N --json` (ou `--porcelain`, decida e justifique)
devolvendo o estado derivado em forma legível por máquina: `id`, `estado`,
`branch`, `prova`, `direção`, e o que mais o consumidor precise para **não
recalcular nada**.

O critério de sucesso não é "existe uma flag": é **o consumidor conseguir parar
de derivar**. Se a saída não carregar tudo o que a ronda precisa, ele vai
continuar recalculando e a divergência volta.

Precedente do próprio repo: `hooks/lib/habit-sensors.awk` é **sensor único, dois
momentos**, e o comentário do `cmd_habits` diz por quê — *"divergência entre eles
seria dois vocabulários de smell"*. Aqui são dois vocabulários de **estado**.

## TRAVA DE CONTRATO

A saída em JSON **nasce contrato** no instante em que o supervisor a consumir:
outros projetos vão ler o mesmo. Portanto:

1. **Nome dos campos e forma do objeto** são contrato desde o primeiro commit.
   Emenda no `DATA_MODEL.md` no MESMO changeset (a última emenda real é a
   **v1.14**, da ordem 013 — confira no arquivo, não confie nesta linha).
2. **O conjunto de estados** é contrato: `aberta`, `em_execucao`, `provada`,
   `aceita`, `absorvida`, `adiada`. Acrescentar ou renomear é PARAR e chamar.
3. **Estado novo no futuro** deve aparecer no JSON sem quebrar consumidor antigo
   — diga como garantiu isso, porque é o defeito que esta ordem existe para não
   repetir.

## O teste

- A saída é JSON válido (`jq` parseia) para **cada um dos seis estados**.
- O estado no JSON **é idêntico** ao que o modo texto imprime — mesma fonte,
  nunca duas derivações.
- Campo novo acrescentado ao JSON **não quebra** um leitor que só conhece os
  antigos (a ordem 005 provou esse tipo de coisa por medição em
  `tests/cli/test-order-issue11.sh`; o mesmo método serve).
- Sabote e prove que o teste reprova.

## Contrato de execução
- **Use git worktree próprio** (liberado na ordem 012; a 013 estreou sem atrito):
  `git worktree add -q /tmp/wt-014 -b fix/014-status-json main`.
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
  Vale no worktree — a autoproteção reconhece worktree desde a 012.
- Gates locais antes do push; `git clone` para cópia patchada, nunca `git archive`.
- Prove com o ledger: `maestro evidence --record --label order-14 -- bash tests/run-all.sh`.
- Direção vigente: INTENT v2.
- **`git add -A` dentro de branch de ordem de teste come o arquivo da ordem** —
  use `git add <arquivo>` nominal (armadilha paga na ordem 013).
