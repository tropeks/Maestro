<!-- maestro-order v1
id: 087
ts: 2026-11-19T22:34:37-03:00
epoch: 1795138477
head: 77c280d1189b5fa588b0b6e32a4934869aad7cbf
branch: order/087-versao-1-26-0-com-o-guarda-que-l
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 087 — versao 1.26.0 com o guarda que le anexos



## Origem
O botão `release_maestro` recusou o main `77c280d`: `tag_ja_existe: v1.25.0 já existe no remoto`. O PR #68 (ordem 086, o guarda lê `~/.ponte/media`) entrou sem subir a versão.

## Fatos
- A versão está em `.claude-plugin/plugin.json` (`1.25.0`).
- O `CHANGELOG.md` registra cada versão no topo.

## Direção
Subir para 1.26.0, só com o que entrou desde a 1.25.0, para o Capitão tocar a release.

## Decisões
1. `.claude-plugin/plugin.json` passa a `1.26.0`.
2. `CHANGELOG.md` ganha a entrada 1.26.0 no topo, no formato das anteriores, com a ordem 086 e o que mais estiver entre a tag `v1.25.0` e o main (`git log v1.25.0..origin/main`).
3. Nada além disso.

## Rollback
Reverter o commit.

## Critérios
- [ ] `.claude-plugin/plugin.json` em `1.26.0`.
- [ ] `CHANGELOG.md` com a entrada 1.26.0, que cita a ordem 086.
- [ ] `bash tests/run-all.sh` sai 0.
- [ ] O diff só toca `.claude-plugin/plugin.json`, `CHANGELOG.md` e esta ordem.

## Turno
- fatia: as decisões 1 a 3
- fim: `bash tests/run-all.sh` sai 0 no tip do branch, com o recibo `order-87` gravado
- teto: 2
- fora: qualquer arquivo além dos dois; tag, release e push (são do Diretor e do Capitão); escrita fora do worktree
- relatório: pela Ponte (`director_report`): de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run, /tmp/claude-<uid>/<cwd codificado>, nunca /tmp solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera por laço até a linha rc= no log; só depois se relata.

## Contrato de execução
- Trabalhe APENAS no branch `order/087-versao-1-26-0-com-o-guarda-que-l`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-87 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 087` (você não fecha a própria ordem).
accepted_at: 2026-11-19T23:36:56-03:00
accepted_session: desconhecido
accepted_tree: 9bfb1391634dd4efb9b0eed4c934339dbb6959d8
accepted_intent: 6
