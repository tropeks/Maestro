<!-- maestro-order v1
id: 015
ts: 2026-09-16T11:31:42-03:00
epoch: 1789569102
head: 72071c6429a220a6f3a7f7919455162a3c506b93
branch: refactor/015-e24-intent-brief-docs
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
-->
# Ordem 015 — E24 ordem C: intent, brief e docs — a familia da direcao e dos documentos



## Contrato de execução
- Trabalhe APENAS no branch `refactor/015-e24-intent-brief-docs`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-15 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 015` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 5. Terceira ordem encadeada do E24, pela mesma razão
medida: o gargalo é o **custo fixo do ciclo**, não a dificuldade — três seções
numa ordem custaram 37min contra 1h43 de uma sozinha.

| seção | linhas |
|---|---|
| `intent` (E22) | 208 |
| `brief` (E8) | 157 |
| `docs` (E16) | 150 |
| **total** | **515** |

Mesma família: as três leem e escrevem **documento de governança** —
`.maestro/INTENT.md`, o brief de projeto e os docs canônicos. A convenção de
passagem de estado firmada na primeira vale de graça nas outras.

Estado do E24: `bin/maestro` em **2692**, de 4456 na largada. Depois desta
ordem, ~2177. Restam então duas: `consent`+`conduct`+`graph` (209) e o `upgrade`
sozinho (233).

## CRITÉRIO DE SAÍDA — e ele agora vale para TODA ordem que toque lib/

`maestro habits` limpo em **CADA módulo novo, medido um a um**: ≤400 linhas,
nenhuma função >60, nome de domínio em toda função nova.

**Lição da ordem 014, paga em um ciclo:** eu vinha escrevendo este critério só
nas ordens de lote do E24, como se fosse regra do épico. **Não é — é regra da
régua.** Na 014, `lib/cmd-order.sh` foi de 321 para 486 linhas e cruzou o teto;
a catraca reprovou a suíte inteira. A régua não distingue se a linha veio de um
split ou de uma feature.

Se um módulo não couber, **crie módulo próprio** em vez de decompor o vizinho no
mesmo changeset — decompor faria esta ordem pagar dívida que não é dela e
misturaria duas mudanças, e depois ninguém diz qual pagou o quê.

## TRAVA DE CONTRATO

As três seções tocam artefato que **outros projetos leem**:

1. **`.maestro/INTENT.md`** — as seis seções obrigatórias, o carimbo
   (`version`, `hash`, `ts`, `head`), e a regra de que o hash é do corpo SEM o
   carimbo. Mudar forma ou semântica é PARAR e chamar.
2. **O brief de projeto** — o envelope e os campos que o SessionStart injeta.
3. **Os docs canônicos e a catraca de drift** (`.maestro-docs.tsv`) — a forma do
   baseline e o significado de "só desce".
4. **Texto de recusa** de qualquer um dos três: outros projetos e o supervisor
   leem esses textos para saber o que falta.

Reordenar, renomear função interna, mover bloco: seu. Mudar forma, campo,
regra ou texto de recusa: dele.

## Travas herdadas
- **Gatilho: DUAS alterações de teste no TOTAL da ordem.** Estourou na terceira
  seção? PARE com as duas boas e chame.
- **Acoplamento não mapeado: PARE e reporte ANTES de cortar.** Precedente: a
  ordem 010 parou ao encontrar o núcleo de verificação chamado por três módulos
  que já tinham saído — e é por isso que a 011 existiu com desenho humano.
- Qualquer mudança de veredito do `maestro doctor`.
- Trava procedimental cruzada marca a medição como **CONTAMINADA**: o lote não
  conta na descida da régua nem na cadência do prazo. Precedente: ordem 009.

## Contrato de execução
- **Worktree próprio**: `git worktree add -q /tmp/wt-015 -b refactor/015-e24-intent-brief-docs main`.
  A autoproteção reconhece worktree desde a ordem 012 — `bin/`, `hooks/`, `src/`
  e `lib/` continuam bloqueados lá dentro.
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
- Convenção: parâmetro posicional, nenhuma função fechando sobre local de outra.
  Referência viva: `lib/core-order-state.sh`, `lib/core-evidence.sh`.
- `declare -g` para estado global de módulo sourceado de dentro de função.
- Tab não serve como separador multivalor (`read` o trata como IFS whitespace);
  use `\x1f`.
- Vigie `>/dev/null 2>&1` mascarando `command not found` — foi o modo de falha
  dos bugs das ordens 009 e 010.
- `git add -A` em branch de ordem de teste COME o arquivo da ordem; use `git add`
  nominal (armadilha da ordem 013).
- `git clone` para cópia patchada, nunca `git archive`.
- Emenda de `DATA_MODEL`: descubra a MAIOR versão
  (`grep -oE "Emenda v1\.[0-9]+" | sort -t. -k2 -n | tail -1`), não a última
  linha — a numeração é global e a posição é por seção.
- Prove com o ledger: `maestro evidence --record --label order-15 -- bash tests/run-all.sh`.
- Registre a HORA DE CHEGADA.
accepted_at: 2026-09-16T15:34:58-03:00
accepted_session: desconhecido
accepted_tree: f3b18020f8a917b55e2de8814d1db70512102344
accepted_intent: 2
