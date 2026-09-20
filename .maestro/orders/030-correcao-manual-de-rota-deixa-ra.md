<!-- maestro-order v1
id: 030
ts: 2026-09-19T20:26:17-03:00
epoch: 1789860377
head: 441d719fcbae793895c663c452d8cdeb112861e6
branch: feat/030-sensor-correcao-de-rota
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
absorbed_by: main
absorbed_tree: b28960041c29867ab815781a46d37fa40a27762d
absorbed_at: 2026-09-20T01:02:34-03:00
absorbed_session: desconhecido
-->
# Ordem 030 — correcao manual de rota deixa rastro: o bullet 1c sai de inverificavel para medido

## Por que esta ordem existe

O Resultado do INTENT v3 promete, no primeiro bullet: *"zero correção manual do
modo/modelo escolhido"*. Medido hoje: **o bullet é INVERIFICÁVEL, não falso.** Não
existe sensor.

O único sensor vizinho é o `override_manual` (`hooks/user-prompt-submit.sh`), e ele
só dispara em prompt que **começa com `/`** — comando de skill digitado. Correção em
linguagem natural ("não, faz direto", "usa o haiku nessa") não deixa rastro em
nenhum dos 17 tipos de evento do log.

Sem sensor, o bullet não pode ficar verde nem vermelho: ele não pode ser lido. E o
Capitão pediu o encerramento com todos os bullets verdes.

## O que entra

Um sensor que registre que **houve correção de rota**, sem registrar **o que foi
dito**. O evento é o fato; o conteúdo é do humano.

Decisões que o desenho tem de tomar, e justificar no changeset:

- **Onde mora.** `user-prompt-submit.sh` já lê o prompt e já descarta o conteúdo —
  é o único lugar que vê a correção acontecer. Reaproveitar, não inventar hook novo.
- **Como reconhece.** Correção de rota é o humano contradizendo uma decisão JÁ
  registrada nesta sessão. O record existe (`~/.maestro/sessions/<id>.json`, com
  `workflow`/`mode`/`agents`), então o sensor tem âncora: só há correção se já houve
  decisão. Isso limita a superfície e evita o classificador de intenção que o ADR-002
  rejeitou por texto expresso.
- **O que grava.** Evento novo no vocabulário fechado (DATA_MODEL §4), com
  `session_id` e o EIXO corrigido (`mode` · `agents`/modelo · `workflow`) — nunca a
  frase, nunca um pedaço dela.

## Limites duros

- **Jamais o prompt**, nem trecho, nem hash que permita reconstruir (CLAUDE.md;
  README "Hard boundaries"). O `user-prompt-submit.sh` atual é o molde: lê, decide,
  descarta.
- **Observador, nunca gate**: exit 0 sempre, nada em stdout, NFR do hook respeitado.
- Vocabulário fechado: o evento novo entra em `_maestro_event_valid`
  (`hooks/lib/common.sh`) e no DATA_MODEL §4, no MESMO changeset.
- Nenhum classificador de intenção dedicado (ADR-002, "Fora de escopo" do INTENT).

## Prova exigida

- Correção depois de decisão registrada → evento sai, com o eixo, sem conteúdo.
- Prompt normal, sem decisão prévia na sessão → nada sai.
- Prompt que MENCIONA modo/modelo sem corrigir nada → nada sai (o falso positivo é
  o que mata a métrica: um sensor que conta demais é pior que nenhum).
- O evento aparece no `maestro retro`, ao lado do override, para que o bullet 1c
  passe a ter número.
- Suíte verde; `doctor` sem mudança de veredito; catraca de habits dentro do baseline.
- Orçamento da injeção inalterado (esta ordem não injeta nada).

## Contrato de execução
- Trabalhe APENAS no branch `feat/030-sensor-correcao-de-rota`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-30 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 030` (você não fecha a própria ordem).
