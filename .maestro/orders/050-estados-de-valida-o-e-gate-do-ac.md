<!-- maestro-order v1
id: 050
ts: 2026-10-03T12:39:24-03:00
epoch: 1791041964
head: 41213f0a454bd6c2060d9faa41f91e36ad450047
branch: order/050-estados-de-valida-o-e-gate-do-ac
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 050 — Estados de validação e gate do aceite

> Ordem do Capitão, 2026-10-03, do pacote da INTENT v56 (spock, seção "Direção 2026-10-03 - a linha de produção"; estende a v55). Esta peça é o **plano**: quem executa não fecha a própria ordem — `maestro order --accept` é do Diretor, e só depois da validação verde (v55 ponto 4).

## Por quê
v55 pontos 1 a 4: o desenvolvimento não espera a CI; o que depende da CI é validação; reprovada vai para o reparo; aceite só com validação verde. Hoje o estado da ordem termina em `provada` e o `--accept` não olha validação.

## Contrato
1. `_order_status` ganha `em_validacao`, `validada` e `reprovada`, **derivados de recibos por árvore** (nunca autodeclarados), entre `provada` e `aceita`. `provada` = recibo local verde no tip (como hoje).
2. `maestro order --validate <id>` grava o pedido no registro fora da árvore, com a árvore provada.
3. Recibo de validação (tipo `validation`, com a árvore) gravado no ledger pelo runner; verde na MESMA árvore do pedido → `validada`; vermelho → `reprovada`. Árvore mudou depois → a validação anterior deixa de valer (mesma regra do recibo local).
4. `reprovada` sem novo tip provado é o sinal de **reparo**; novo tip com recibo local verde volta a `provada`.
5. `--accept` só passa a partir de `validada`, atrás de `MAESTRO_ACCEPT_REQUIRE_VALIDATION` (mesmo padrão da ordem 041). Flag desligada: comportamento de hoje byte a byte (golden). Projeto sem `validation:` no `.maestro.yaml` mantém `provada → aceita`.
6. `order --list`, `--status` (inclui `--json`) e `conform` conhecem os estados novos.
7. O critério de fim do turno de desenvolvimento (ordem 046) continua sendo o recibo local no tip; a validação não entra nele.
8. Arquivos protegidos do Maestro (`hooks/`, `bin/`, `src/`) não são editados pelo executor: a mudança sai como patch em `docs/patches/` e o Capitão aplica (ou sob o consentimento escopado da ordem M5, quando existir).

## Prova
Testes: validada, reprovada, árvore mudada, flag desligada (golden idêntico), projeto sem `validation:`. `maestro evidence --record --label order-50 -- bash tests/run-all.sh`.

Depende de: ordem 49 (numeração) só pela sequência do pacote, não pelo código.

## Turno

- fatia: o derivado dos três estados, `--validate` e o gate do `--accept` atrás da flag
- fim: testes dos casos acima verdes; golden com flag desligada idêntico; `bash tests/run-all.sh` sai 0
- teto: 5
- fora: revisada/integrada/expedida (ordem M2), o runner da lab, o daemon e qualquer edição em hooks/bin/src
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/050-estados-de-valida-o-e-gate-do-ac`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-50 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 050` (você não fecha a própria ordem).
