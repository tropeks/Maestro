<!-- maestro-order v1
id: 040
ts: 2026-09-22T06:33:40-03:00
epoch: 1790069620
head: 921e41381ccdb2f0ec693bb2ad7f7f4f0f01f109
branch: docs/040-encerramento-v1
frozen: vendor/ src/ bin/ hooks/ lib/ config/routing-table.yaml agents/
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
-->
# Ordem 040 — encerramento do v1: a Fase 2 sai por escrito e o Resultado fecha

## A decisão que a autoriza

Decisão do Capitão, registrada na Ponte (`01M325G8FJKQ4AW1HAXMBD8AWE`, escolha
`encerra_v1`), 2026-09-22: **o Maestro v1 ENCERRA ao fechar a 039.** A Fase 2 —
multiusuário/QM e MCP dinâmico — fica registrada como **destravada pelo gatilho medido**
(0,2% de override em 481 decisões) e vira projeto próprio ou wishlist: **não entra no v1**.

## Sequência, e por que ela importa

Esta ordem roda **depois** da 039 pousar em `main`. As duas emendam o INTENT, e a 039 já
carrega um `--bump` (v4 → v5); rodar as duas em paralelo faria duas versões de direção
disputarem o mesmo arquivo. Aqui o bump é o seguinte (v5 → v6), sobre o tip que a 039
deixar.

## O que entra

**1. Emenda ao INTENT, duas seções:**

- **Fora de escopo** ganha a Fase 2 nomeada, com a data e o id da decisão. O texto de hoje
  já diz que ela está destravada e fora do v1; passa a dizer também **onde ela mora** —
  projeto próprio ou wishlist — para ninguém reabrir por engano achando que é dívida.
- **Resultado**: o bullet 9 (gatilho da Fase 2) sai de "DISPARADO" para
  **cumprido-e-encerrado**, com o número que o fechou ao lado.

**2. `maestro intent --bump`** (v5 → v6), e `maestro intent --check` confirmando.

**3. `ENCERRAMENTO-v1.md`** — curto, e com três seções só:

- **Os bullets do Resultado, medidos.** A tabela que já existe no carimbo CUMPRIDO (v4),
  atualizada com o que mudou depois dela: o sensor `route_fix` da 030, o número de campo
  da 031, e os dois bullets que fecham por MECANISMO e não por número — dito por extenso,
  como está no INTENT.
- **O que fica de dívida.** As issues abertas, as dívidas declaradas (o gêmeo em
  `cmd-order.sh`, `route_fix` fora de `EVENTS`, o `{1,200}` do gate-report, o
  `installed_plugins.json`, bubblewrap+socat da 023), e as ordens não-terminais que
  sobrarem. Cada uma com endereço, não com adjetivo.
- **Onde a Fase 2 mora.** O gatilho medido, a decisão que a manteve fora, e o destino
  (projeto próprio ou wishlist).

## Limites

- **Não abre nada novo.** Palavra do Capitão: depois disto, nada sem ordem dele.
- Não mexe em código: esta ordem é direção e documento. Se algo de código aparecer no
  caminho, vira ordem própria — e ela precisa de ordem dele para existir.
- Não reescreve a história: o carimbo CUMPRIDO da v4 fica; o v6 acrescenta, não apaga.

## Prova exigida

- `maestro intent --check` reporta **v6**, 6/6 seções, sem `hash_bump_pendente`.
- O `ENCERRAMENTO-v1.md` cita, para cada bullet do Resultado, ONDE o número foi medido —
  e nenhum número novo é inventado aqui: tudo sai do INTENT, do CHANGELOG ou do ledger.
- A lista de dívida bate com a realidade no dia do encerramento: `maestro order --list`
  para as ordens, `gh issue list` para as issues.
- Toda ordem viva marcada para revisão de plano depois do bump é comportamento esperado da
  E22, não regressão — dito no relatório para ninguém tratar como quebra.
- Suíte verde; `doctor` sem mudança de veredito.

## Contrato de execução
- Trabalhe APENAS no branch `docs/040-encerramento-v1`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ src/ bin/ hooks/ lib/ config/routing-table.yaml agents/
- Prove com o ledger: `maestro evidence --record --label order-40 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 040` (você não fecha a própria ordem).
accepted_at: 2026-09-22T08:44:03-03:00
accepted_session: desconhecido
accepted_tree: c358a0f2c3b4b7247c2ddd3607756dcc922d2ce0
accepted_intent: 6
