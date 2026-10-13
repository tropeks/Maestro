<!-- maestro-order v1
id: 082
ts: 2026-10-13T05:51:06-03:00
epoch: 1791881466
head: ce4f3b1e7056e038bb813b77f9edc60f78669d39
branch: order/082-teste-072-sem-root-n-o-depende-d
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 082 — Teste 072 sem root não depende do modo do /usr/share do runner

## Origem
Pedido do Spock em 13/10/2026. A CI do `main` do Maestro está vermelha desde 08/10 (runs 37690126931, 37692880368, 37694174138, 37812070224 e 38371191764, esta no `main` em `ce4f3b1`) por **um único caso**: `tests/cli/test-order-072-install-managed-mods.sh:54`, "sem root não instala". O teste espera rc 2 com `sudo` na saída, mas no runner do GitHub o `/usr/share` tem modo 777, e o instalador recusa antes com `/usr/share tem modo 777 (gravável por grupo ou outros)`, também rc 2. O comportamento do instalador está certo, recusando nos dois casos; o teste é que depende do ambiente. Com a suíte vermelha, o job "aprovar (mover a tag stable)" é pulado e o release v1.23.0 não move o `stable`.

## Turno
- fatia: só o teste. O caso 7 deixa de depender do modo dos diretórios reais do sistema:
  1. Leia o instalador e diga no relato, com `arquivo:linha`, a ordem das recusas (largura do destino, modo dos pais, root).
  2. Escolha a forma que prove a recusa por falta de root **sem** passar pela recusa de modo: um destino absoluto cujos pais existam e não sejam graváveis por grupo ou outros na forge **e** no runner, ou, se o instalador permitir, uma raiz de teste. **Não** troque a expectativa por "qualquer rc 2", porque aí o caso deixaria de provar o root.
  3. Se a forma certa exigir mudar o instalador (`bin/`, `lib/`, `hooks/`), **PARE e reporte**: vira outra ordem, com patch protegido.
  4. Mantenha o caso "sem root nada foi criado".
- fim: `bash tests/cli/test-order-072-install-managed-mods.sh` rc 0 (o run grava o recibo de trabalho com ele); a suíte inteira, `bash tests/run-all.sh` como recibo order-82, roda o Diretor fora do sandbox no tip; a CI do PR verde no job "suíte + doctor".
- teto: 1 · 45 min · 80 turnos
- limite de CI e revisões: 2 rodadas de CI; sem revisão independente (só teste). PR em rascunho até a CI.
- fora: o instalador e qualquer arquivo fora de `tests/`; outros testes; o `ci.yml`.
- relatório: pela Ponte (`director_report`), com a ordem das recusas lida, a forma escolhida, o antes/depois do caso 7 e o id da CI do PR.
- depende de: nada além do `main`.

> **Log e escrita:** sob bwrap a /tmp do run não persiste entre chamadas: log de suíte e saídas vão para docs/research/work/ da worktree (gitignored); escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera por laço até a linha rc= no log; só depois se relata. Depois do push NUNCA espere a CI: relate com o id do run e pare. O Diretor redespacha com a CI terminada.

## Contrato de execução
- Trabalhe APENAS no branch `order/082-teste-072-sem-root-n-o-depende-d`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-82 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 082` (você não fecha a própria ordem).
accepted_at: 2026-10-13T06:20:20-03:00
accepted_session: desconhecido
accepted_tree: e3e24edae32ccd9b87bfdab27ba817652fef4667
accepted_intent: 6
