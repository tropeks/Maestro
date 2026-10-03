<!-- maestro-order v1
id: 048
ts: 2026-10-02T23:05:47-03:00
epoch: 1790993147
head: 41213f0a454bd6c2060d9faa41f91e36ad450047
branch: order/048-papercuts-do-fluxo-recibo-de-sui
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 048 — papercuts do fluxo: recibo de suite por ordem, latencia do session-start sob load e conform no vocabulario de eventos

## A decisão que a autoriza

Decisão do Diretor em 02/10 (INTENT v6, Prioridade 3 — trilho onde o trilho alcança): os papercuts
48 e 49 do `~/.maestro/papercuts.md` e a pendência do brief (`conform` fora do vocabulário de
eventos) travam o fluxo de hoje e entram numa ordem só.

## O que entrega

1. **Recibo de suíte por ordem.** O rótulo `suite` é UM por projeto: a 2ª ordem provada deixa a 1ª
   VENCIDA (045×046). O recibo passa a ser por ordem (`suite-N`) ou a chave inclui o branch, de modo
   que duas ordens provadas em paralelo não se vencem. Quem lê (`order --status`/`--accept`,
   `outcome --suite`, `evidence --check`) resolve a chave certa; `suite` sem sufixo segue valendo na
   `main` e como fallback (nenhum recibo existente quebra).
2. **Latência do session-start sob load.** `tests/hooks/test-session-start.sh` usa o portão de carga de
   `tests/lib/latency.sh` (fonte única): acima do limiar o estouro do NFR de overhead é
   "inconclusivo sob carga", nunca FAIL; abaixo, o teto segue estrito.
3. **`conform` no vocabulário de eventos** de `hooks/lib/common.sh` (e `EVENTS` em `src/cli.ts`, junto
   de `turno_teto` e `route_fix`, se faltarem): `conform --check` deixa de imprimir "evento invalido
   descartado".

## Ask-First

- Se o formato do recibo mudar de forma que um recibo antigo deixe de ser lido, PARE e reporte.
- Se o recibo por ordem exigir tocar `hooks/` além do vocabulário de eventos, diga qual linha e por quê.

## Como sai

`tests/` e `docs/` direto no branch. `bin/`, `hooks/`, `src/`, `lib/` são autoprotegidas — saem num
**UM patch** em `docs/patches/048-*.patch`, feito em clone sandbox FORA do repo, testado antes e depois,
aplicado pelo Capitão com um `git apply`. Emendas no MESMO changeset: API_SPEC (chave do recibo),
DATA_MODEL (se o schema mudar), CHANGELOG.

## Prova exigida

- Vermelho antes / verde depois para cada um dos três itens (saída colada no relatório).
- Item 1: duas ordens com recibo próprio, gravadas em sequência, ambas VÁLIDAS; recibo `suite` legado
  continua lido.
- Item 2: com load acima do limiar o teste sai inconclusivo (rc 0 com marca), com load baixo o teto
  estrito reprova; item 3: `conform --check` sem a mensagem no stderr.
- Suíte verde; `habits` dentro da catraca (função nova acima de 60 linhas reprova); recibos `order-48` e
  `suite-48` no tip exato, árvore limpa.

## Turno
- fatia: os três consertos em sandbox, com teste vermelho antes
- fim: `bash tests/run-all.sh` sai 0 no sandbox com o patch aplicado
- teto: 6
- fora: aplicar o patch (é do Capitão), aceitar a ordem e girar o cache
- relatório: ENGINEERING_SPEC, "O turno da ordem e o relatório de fim de turno"

## Contrato de execução
- Trabalhe APENAS no branch `order/048-papercuts-do-fluxo-recibo-de-sui`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-48 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 048` (você não fecha a própria ordem).
