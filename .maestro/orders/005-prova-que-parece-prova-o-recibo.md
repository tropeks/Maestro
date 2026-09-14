<!-- maestro-order v1
id: 005
ts: 2026-09-14T13:01:05-03:00
epoch: 1789401665
head: 3b300bced7efd9ab8b69994c3aa200d367dec183
branch: fix/005-prova-que-parece-prova
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: fcd81054daaa0dce52f0f9a14bc0908bf7297757
absorbed_at: 2026-09-14T14:31:29-03:00
absorbed_session: desconhecido
-->
# Ordem 005 — prova que parece prova: o recibo sem carga (#11) e o warn-only que esconde a catraca (#9)



## Contrato de execução
- Trabalhe APENAS no branch `fix/005-prova-que-parece-prova`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-5 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 005` (você não fecha a própria ordem).

## Por que esta ordem existe

Fecha a família que as ordens 003 e 004 começaram. O supervisor nomeou o fio
comum: **os dois defeitos são prova que parece prova e não é.** A #6 destruía a
prova ao carimbá-la; a #12 e a #13 contavam como pendente o que já terminara, e
como ordem o que nunca foi. Estas duas fazem o mesmo por outro ângulo — dizem
"válido" e "aviso" quando a realidade é outra.

O E24 fica para depois: mexe em `bin/` e `src/` logo após três patches
aplicados ali à mão, e o `main` precisa assentar um ciclo antes.

## Issue #11 — o recibo não guarda a carga

Desde o PR #10, `ARCHITECTURE.md §NFRs` exige load de 1 min ≤ 2,0 para que uma
medição de latência valha. Mas o recibo grava `schema, label, ts, epoch,
cmd_hash, exit, wtree_before, wtree_after, cmd_match` — **e nenhuma carga.**

Caso real desta sessão: recibo gravado a **load 12,12** foi lido como
`VÁLIDA — exit 0, conteúdo byte-idêntico ao provado`. O diretor o recusou,
corretamente; o CLI não tinha como saber. A condição que o invalida não é nada
que ele registre — a regra vira verificável por conversa, não por leitura, que
é o oposto do desenho do ledger.

Entrega: gravar `load1m` e `ncpu` (inteiros ×100 — o `CLAUDE.md` proíbe float em
métrica); a leitura qualifica `VÁLIDA (load 1.8)` contra `VÁLIDA, mas fora do
limiar de medição (load 12.1)`. E avaliar o terceiro item da issue: **contar
quantas asserções saíram `inconclusivo`**. Um `exit 0` com três medições
dispensadas por carga não é a mesma prova que um `exit 0` limpo, e hoje os dois
são indistinguíveis no ledger.

## Issue #9 — "warn-only" esconde o que reprova a CI

`hooks/post-edit-habits.sh:227` imprime `Warn-only — a edição valeu; considere
resolver ANTES de seguir`, mesma redação de `EPICS.md:198-199`. A frase é
verdadeira para aquele hook, que não pode bloquear edição já feita. Mas o MESMO
achado alimenta `maestro habits --all` — catraca com baseline versionado
(`.maestro-habits.tsv`, E9/S-905) — que **reprova com exit 1** e derruba a CI.

Caso real desta sessão, pago em minuto de Actions: um arquivo de teste foi de
399 para 418 linhas, cruzou o teto de 400, virou o 13º acima do baseline de 12.
O PostToolUse disse "warn-only"; a CI do PR #8 ficou vermelha em `suíte +
doctor`; foi preciso um segundo run depois da correção.

Entrega: a mensagem diz a verdade inteira e — o item que mais paga — **o aviso
dispara quando a edição CRUZA o baseline**, não só quando encontra achado.
Cruzar de 12 para 13 é qualitativamente diferente de editar arquivo que já era
grande, e é o instante em que o agente precisa saber. Nota em `EPICS.md`
ligando os dois mecanismos, para quem lê o contrato e não a mensagem.

## Restrição de execução

`bin/` e `hooks/` estão na denylist de autoproteção (ADR-003 v1.2): tudo sai
como patch em `docs/patches/`, e quem aplica é o Capitão. Se os dois patches
tocarem linhas vizinhas, declare a ORDEM de aplicação — foi o que a 004 teve de
fazer com 13 antes de 12.

Contrato: campo novo no recibo é schema. Decidir explicitamente se campo
opcional mantém `maestro-evidence-v1` ou exige `v2`, e emendar o `DATA_MODEL.md`
no MESMO changeset.

Teste, como nas 003 e 004: detecta o MECANISMO, reporta `PENDENTE` sem o patch,
cobra de verdade com ele — e prova o terceiro estado, sabotando o mecanismo
para mostrar que REPROVA.

## Contrato de execução
- Trabalhe APENAS no branch `fix/005-prova-que-parece-prova`; NUNCA no main.
- Zonas CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/` e `hooks/` não se editam: patch em `docs/patches/`.
- Gates locais ANTES do push: `shellcheck -x -P SCRIPTDIR --severity=error`,
  `bash -n`, `maestro habits --all`, suíte completa. Uma execução de CI, no tip.
- Prove com o ledger: `maestro evidence --record --label order-5 -- bash tests/run-all.sh`.
- Direção vigente: INTENT v2, Prioridade 4.
- Absorva ANTES de commitar governança: commitar `.maestro/` move o `main` e
  vence o recibo `label main` — lição paga nesta sessão.
