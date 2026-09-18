<!-- maestro-order v1
id: 022
ts: 2026-09-18T12:54:29-03:00
epoch: 1789746869
head: d2051a0343df01d8551827ca9defc6a849aecde9
branch: fix/022-migracao-carimbo-so-arquivo
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 022 — migracao do carimbo so-arquivo: accept grava o registro em vez de parar



## Contrato de execução
- Trabalhe APENAS no branch `fix/022-migracao-carimbo-so-arquivo`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-22 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 022` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v3, Prioridade 4. A ordem 021 tirou o estado terminal da árvore de
trabalho, mas **só para quem foi carimbado depois dela**. Ordem fechada ANTES do
patch continua vivendo só no arquivo — e continua morrendo no próximo
`git checkout`.

### A lacuna, medida no Agenda_Studio (2026-09-18)

```
~/.maestro/order-state/Agenda_Studio-7da5612c-012 … -017   ← existem
                                              -018, -019   ← AUSENTES
```

As 018 e 019 foram fechadas antes do patch. Ao rodar
`maestro order --accept N --absorbed-by main` para migrá-las, o comando
respondeu **"já absorvida — nada a fazer"** e **não gravou o registro**
(`lib/cmd-order.sh:231`).

Resultado: **não existe comando para migrar uma ordem terminal só-por-arquivo.**
Ela lê certo hoje — a precedência da 021 faz o arquivo contar quando não há
registro — e morre no próximo checkout, exatamente como antes.

A 021 cobriu a migração para **LEITURA**. Não cobriu a **CURA**.

## O conserto — decisão do diretor

Quando a ordem **já é terminal por arquivo** e o **registro está ausente**, o
`accept` **grava o registro** em vez de parar. Vale para os dois desfechos:
`absorvida` (`lib/cmd-order.sh:231`) e `aceita` (o ramo logo acima, mesma
função).

Duas bordas que decidem a qualidade:

- **Cura não é reescrita.** Se a ordem já é terminal E o registro existe, o
  comportamento de hoje ("nada a fazer") continua. O comando não pode virar um
  jeito de recarimbar ordem fechada.
- **O registro gravado reflete o ARQUIVO**, não o momento da migração: quem
  absorveu, quando, contra qual árvore. Se algum campo não existir no arquivo,
  diga o que você põe no lugar e por quê.

## COMECE EXTRAINDO — decisão do diretor, 2026-09-18

`lib/cmd-order.sh` está em **400 linhas exatas**, no teto do sensor
`oversized-file`, margem zero. Esta ordem toca esse arquivo.

Regra: **a próxima ordem que tocar nele começa extraindo
`lib/cmd-order-accept.sh`**, no molde de `lib/cmd-order-json.sh` (ordem 014).
Extraia PRIMEIRO, confirme a suíte verde **com a extração sozinha**, e só então
escreva o conserto. Não decomponha mais nada além do necessário.

## Prova exigida

- **Cura**: ordem terminal só por arquivo, sem registro → `accept` grava o
  registro → `git checkout` no arquivo → **continua terminal**. Tem de FALHAR
  contra o código atual; mostre as duas pontas.
- **Não-reescrita**: ordem terminal COM registro → `accept` diz "nada a fazer" e
  **não altera** o registro (compare o conteúdo antes/depois).
- Os dois desfechos, `absorvida` e `aceita`.
- **Extração limpa**: a suíte passa com a extração aplicada e SEM o conserto,
  provando que a extração não mudou comportamento.
- **Ordens 001–022 deste repo, antes e depois: nenhuma muda de estado.**
- **Agenda_Studio 018 e 019** — LEITURA APENAS, nunca escreva naquele repo:
  descreva o que o comando faria nelas com o patch. Não execute a migração lá.
- Suíte completa verde em cópia patchada; `habits` por arquivo, um a um
  (`cmd-order.sh` tem de CAIR de 400 com a extração); `doctor` sem mudança de
  veredito.
- Recibo `maestro evidence --record --label order-22 -- bash tests/run-all.sh`.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-022 -b fix/022-migracao-carimbo-so-arquivo main`.
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
  `tests/` e `docs/` se editam direto.
- **Regrave o patch imediatamente após cada edit** e verifique com `git apply` a
  partir do patch salvo, nunca do arquivo editado ao vivo.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`. **Commite.**
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`.
- **`{1,N}` grande em regex bash custa ~O(N²)** (issue #42) — use `+` e corte
  depois, em aritmética.
- `bash -n` por arquivo é o gate de sintaxe.
- **Sem carga sintética** — confirme se o NetForge tem run vivo na lab.
- Grave o essencial em `docs/patches/022-NOTAS.md`.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 022`.
accepted_at: 2026-09-18T14:23:35-03:00
accepted_session: desconhecido
accepted_tree: ae37fd4cac46cac760e9085e36534ffacd68bc07
accepted_intent: 3
