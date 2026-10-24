<!-- maestro-order v1
id: 083
ts: 2026-10-23T22:46:32-03:00
epoch: 1792806392
head: 88a27b05c62ed44dc44c220436bead707dac990d
branch: order/083-testes-da-fase-1-fixam-block
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 083 — Testes da fase 1 fixam block

## Origem
Cartão R1 do Capitão, item 6 (decisão Ponte 01M5NMF64W, 23/10/2026): a fase 1 do gate está encerrada, e o painel reprovou (as decisões espontâneas caíram de 72% para 13%). Pelo `docs/fase1/ROLLBACK.md`, passo 1, o `gate.mode` volta a `block`. Isso já está no branch base desta ordem: patches 904 (`config/routing-table.yaml`, linha 3) e 905 (versão 1.25.0), aplicados pelo botão, commits 3bee841 e 88a27b0, PR #54. A CI do PR #54 (job "suíte + doctor") reprovou em 8 casos de 6 arquivos, que ainda fixam a sombra:

- `tests/hooks/test-fase1-guarda-sombra.sh`: "gate.mode não é warn" e "sem o rollback ao lado do modo"
- `tests/hooks/test-gate.sh`: "política real: código SEM decisão → exit 0 (sombra: gate.mode warn)", esperado 0, obtido 2
- `tests/hooks/test-session-start.sh`: "7 valores batem com config/routing-table.yaml"
- `tests/hooks/test-env-leak-guard.sh`: "test-session-start.sh falha com o ambiente LIMPO também", consequência do anterior
- `tests/cli/test-order.sh`: "direct na zona → avisa e passa" e "multi pós-aceite → passa", esperado 0, obtido 2
- `tests/hooks/test-order-048-papercuts.sh`: "sob carga: esperava rc 0 + INCONCLUSIVO" (rc=1); pode ser instabilidade, não assuma

## Turno
- fatia: só `tests/`. A suíte passa a provar o modo `block` de agora, não a sombra:
  1. Para cada caso acima, diga no relato, com `arquivo:linha`, se ele fixa a sombra (então passa a esperar o comportamento de `block`, ou se aposenta se só provava a sombra) ou se é um defeito à parte.
  2. `test-fase1-guarda-sombra.sh`: a guarda da sombra vira guarda do encerramento. Afirme `block` e que o comentário da linha 3 cita a decisão e o rollback. **Não** enfraqueça a guarda para "qualquer modo".
  3. Casos que esperavam "avisa e passa" em `warn` passam a esperar a recusa de `block` (rc 2) **e** mantêm um caso que prove o `warn` quando a política o diz explicitamente (fixture), para o caminho da sombra não ficar sem teste.
  4. Se o conserto exigir mudar `config/`, `hooks/`, `bin/`, `lib/` ou o comentário da `routing-table`, **PARE e reporte**: vira patch pelo botão.
  5. `test-order-048-papercuts.sh`: rode 3 vezes no tip base. Se ele falhar também em `c07db58`, o defeito não é desta ordem: reporte e não conserte.
- fim: os 6 arquivos com rc 0, um por um (o run grava o recibo de trabalho com eles); a suíte inteira, `bash tests/run-all.sh`, como recibo order-83, roda o Diretor no host; a CI do PR verde no job "suíte + doctor".
- teto: 1 · 60 min · 100 turnos
- limite de CI e revisões: 2 rodadas de CI; sem revisão por mutação (só teste). P3 vira lista, não rodada.
- fora: tudo fora de `tests/`; o `ci.yml`; outros testes que não estejam na lista.
- relatório: pela Ponte (`director_report`), com a classificação dos 8 casos, o antes e o depois de cada um e o id da CI do PR.
- depende de: o branch `fase1/gate-block` (PR #54), que é a base deste branch.

> **Log e escrita:** sob bwrap, a /tmp do run não persiste entre chamadas: log de suíte e saídas vão para docs/research/work/ da worktree (gitignored); escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera por laço até a linha rc= no log; só depois se relata. Depois do push, NUNCA espere a CI: relate com o id do run e pare. O Diretor redespacha com a CI terminada.

## Contrato de execução
- Trabalhe APENAS no branch `order/083-testes-da-fase-1-fixam-block`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-83 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 083` (você não fecha a própria ordem).

## Adendo do Diretor (rodada 2, 24/10)
A suíte inteira no host (`bash tests/run-all.sh`, recibo order-83, exit 1) tem **1 FAIL**, causado por esta ordem: `tests/cli/test-habits-cli.sh`, "veredito é 'dentro da catraca'". O motivo é `AVISO catraca: slop acima do baseline — oversized-file: 14 > baseline 13`: o `tests/cli/test-order.sh` passou de 400 para **409 linhas** com o conserto da rodada 1. Os outros 5 arquivos e os 8 casos estão aceitos como relatados.

- fatia: só `tests/cli/test-order.sh` volta a ter no máximo 400 linhas, **sem perder caso**. Os casos novos (recusa em block, fixture warn, `domain_path` pós-aceite) ficam. Junte linhas sem apagar asserção. **Não** mexa na régua, na baseline nem em `test-habits-cli.sh`.
- fim: `wc -l tests/cli/test-order.sh` ≤ 400; `bash tests/cli/test-order.sh` rc 0; `bash tests/cli/test-habits-cli.sh` rc 0. A suíte inteira roda o Diretor no host.
- teto: 1 · 20 min · 40 turnos
- relatório: pela Ponte, com o antes e o depois do `wc -l` e os rc dos dois testes.
accepted_at: 2026-10-24T01:42:32-03:00
accepted_session: desconhecido
accepted_tree: bbbafa2e953ccc13d92e172c7b7a5cfd8ee9c782
accepted_intent: 6
