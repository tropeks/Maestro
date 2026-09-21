<!-- maestro-order v1
id: 033
work_project: ponte-daemon
ts: 2026-09-20T06:58:44-03:00
epoch: 1789898324
head: dd6288b19692d54cf507748fd71d568cf744392d
branch: order/033-director-report-project
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
-->
# Ordem 033 — director.report aceita ordem de outro projeto — o Diretor conduz tres repos e o relato so cabe num



> Ordem pequena, do Diretor, 2026-09-20, por decisão do Capitão. Nasceu de um papercut real:
> um relato de fim de etapa foi **recusado** e teve de sair em prosa.

## 1. O sintoma, medido

Rodando de uma sessão do projeto `enterprise`, relatar o fim de etapa de uma ordem do
`ponte-daemon`:

```
director_report(order_ref="order/023-enroll-app-redirect", ...)
→ 403 forbidden
  "order_ref order/023-enroll-app-redirect não pertence ao projeto enterprise — relato recusado"
```

O relato foi perdido: virou prosa no transcript, que **não** é canal, não abre revisão e não deixa
rastro no ledger do Diretor.

## 2. Por que isso dói agora, e não doía antes

A ordem 014 nasceu para o **gerente**, e gerente é um por projeto: `order_ref` sem `project` era
inequívoco. Hoje o **Diretor** conduz `Enterprise`, `ponte-app` e `ponte-daemon` na mesma sessão —
a Fase 4 da 002, a ordem 004 e a ordem 023 fecharam todas na mesma rodada. A premissa de "uma
sessão, um projeto" deixou de valer para quem mais usa a ferramenta.

A assimetria fecha o caso: **`director.ask` já aceita `project`** e resolve sem ambiguidade;
`director.report` não tem o campo. A mesma dupla de ferramentas, duas regras.

## 3. O que esta ordem entrega

`director.report` ganha **`project` opcional**, com a mesma forma e a mesma validação do
`director.ask` (slug canônico, `^[a-z0-9-]{1,40}$` — emenda A22-01).

- **Omitido:** comportamento de hoje, inteiro. O projeto é o da sessão. Nada muda para o gerente.
- **Presente:** o relato é gravado contra esse projeto, e `order_ref` é resolvido **nele**.
- **Presente e o projeto não existe:** recusa nomeada, com a mesma forma de erro que o
  `director.ask` já usa. Não inventa projeto.

**O código mora no `ponte-daemon`** (a ferramenta MCP `DirectorReport`, ao lado de `DirectorAsk`,
que já faz isso certo) — a ordem é rastreada aqui porque a convenção do canal é do Maestro, mas
o executor trabalha no repo do daemon, em branch próprio a partir do `main`.

## 4. Limites

- **Não mexer no `director.ask`** nem na resolução de `order_ref` por id do ledger (ordens 015/016).
- **Não afrouxar a checagem.** Sem `project`, a recusa de ordem alheia **continua** — o conserto é
  dar o campo, não remover a validação. Um relato gravado no projeto errado é pior que um relato
  recusado.
- Ordem pequena: nada de refactor do caminho de relato.

## 5. Critérios de aceite

1. `director.report` sem `project` se comporta exatamente como hoje — teste que prova a
   não-regressão do gerente.
2. `director.report` com `project` grava o relato nesse projeto e resolve `order_ref` nele.
3. `project` inexistente ou fora do slug canônico: recusa nomeada, mesma forma do `director.ask`.
4. O par `ask`/`report` tem a **mesma** validação do campo — teste que compara os dois caminhos,
   para não divergirem de novo.
5. `API_SPEC` §5 emendado: o campo entra no contrato da ferramenta.
6. Suíte verde e evidência no ledger.

## Contrato de execução
- Trabalhe APENAS no branch `order/033-director-report-project`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-33 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 033` (você não fecha a própria ordem).
accepted_at: 2026-09-21T00:42:33-03:00
accepted_session: desconhecido
accepted_tree: 65e38fc7cd4731a83a910ac68a68f5861df40e9c
accepted_intent: 4
