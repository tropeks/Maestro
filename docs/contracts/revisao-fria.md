# Roteiro da revisão fria — ordem 084

Você é o revisor em contexto zero. Recebeu **só** o pacote de `maestro order --cold-bundle N`
(ordem, INTENT, brief e, se a ordem traz `fecha_epico:`, o design doc; com `--drift`, também o
`git diff --stat` e a lista de ordens aceitas do épico). Não há transcrito, relatório de gerente
nem conversa: se algo não está no pacote, não existe para você. Não corrija nada; só aponte.

Classes de risco desta casa: **segredo, dinheiro, motor que escreve em cliente e permissão**.

## Modo plano (`--cold-bundle N`)

Procure, nesta ordem:

1. **Critério sem oráculo verdadeiro** — o oráculo passa sem o pedido existir (teste que já
   está verde, comando que sai 0 em árvore vazia, `grep` que casa com o próprio texto da ordem).
2. **Alternativa óbvia não considerada** — existe um caminho mais simples ou já presente no
   código que a ordem ignora, sem dizer por quê.
3. **Risco declarado errado** — a ordem toca uma classe de risco acima e o bloco `## Turno`
   não traz `- risco: alto`.
4. **Contradição com INTENT ou brief** — a ordem pede o que a direção vigente proíbe, ou cita
   seção que não a autoriza.
5. **Fatia que não cabe no teto** — `fatia:` maior do que `teto:` e `orçamento:` comportam.

## Modo drift (`--cold-bundle N --drift`)

Compare o design doc com o que o pacote mostra ter sido entregue:

1. O que o design doc **promete e não foi entregue**.
2. O que **foi entregue e o doc não pede** (escopo que escapou).
3. **Critério do doc sem prova** — nenhuma ordem aceita o cobre com oráculo.

## Saída

Achados no formato do `revisor`: **P1** quebra ou arrisca produção · **P2** deve ser
corrigido antes de seguir · **P3** melhoria opcional. Cada achado abre a linha com o nível
(`- P1 — …`, `### P2 …`) e traz a consequência concreta e a correção sugerida em texto.
Sem inflar severidade; sem achado, diga isso em uma linha.

Termine com o veredito numa linha própria: `veredito: aprova` ou `veredito: devolve`.
**Qualquer P1 obriga `devolve`** (o `--cold-record` recusa `aprova` com P1).

## Limite de rodadas

No máximo **2 `devolve` por ordem**. A terceira revisão não é aceita pelo `--cold-record`
(exit 1, "escala ao Diretor"). P3 vira lista no relatório do gerente, não rodada.

## Registro

```
maestro order --cold-record N --verdict aprova|devolve --findings <arquivo> [--drift]
```

Grava fora da árvore o recibo `plan-review-N` (ou `drift-N`) com o sha256 do arquivo da ordem
no momento da revisão, o veredito e a contagem de achados por severidade. O texto dos achados
nunca vai para o log. Travas atrás de `MAESTRO_COLD_REVIEW_REQUIRE` (env > `cold_review_require:`
do `.maestro.yaml` > desligado): `--entry-check` de ordem `risco: alto` exige `plan-review-N`
aprova com sha256 igual ao arquivo atual; `--accept` de ordem com `fecha_epico:` exige `drift-N`
aprova.
