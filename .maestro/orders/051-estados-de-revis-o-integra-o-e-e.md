<!-- maestro-order v1
id: 051
ts: 2026-10-03T12:39:24-03:00
epoch: 1791041964
head: 41213f0a454bd6c2060d9faa41f91e36ad450047
branch: order/051-estados-de-revis-o-integra-o-e-e
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 051 — Estados de revisão, integração e expedição

> Ordem do Capitão, 2026-10-03, do pacote da INTENT v56 (spock, seção "Direção 2026-10-03 - a linha de produção"; estende a v55). Esta peça é o **plano**: quem executa não fecha a própria ordem — `maestro order --accept` é do Diretor, e só depois da validação verde (v55 ponto 4).

## Por quê
A linha tem sete estações; o enum só conhece até a aceitação. Cada estação precisa de estado derivado de recibo, com a mesma regra da validação.

## Contrato
1. Estados `revisada`, `integrada`, `expedida` e `devolvida` (reparo vindo de qualquer estação, com a estação de origem e o motivo) no `_order_status`.
2. `order --review`, `--integrate` e `--ship` gravam o recibo da estação (tipo, árvore, quem, quando) no registro fora da árvore. Regra única: o recibo vale para uma árvore; árvore nova invalida.
3. Ordem: `provada → em_validacao → validada → revisada → aceita → integrada → expedida`. Nenhuma estação aceita peça sem o recibo da anterior. **Conflito de integração** grava `devolvida` (origem: integrar) e o **aceite se mantém** (decisão do Capitão na v56).
4. `--accept` passa a exigir `revisada` atrás de flag própria (`MAESTRO_ACCEPT_REQUIRE_REVIEW`), desligada = comportamento da M1.
5. `--list`, `--status --json` e `conform` conhecem os estados. Arquivos protegidos do Maestro (`hooks/`, `bin/`, `src/`) não são editados pelo executor: a mudança sai como patch em `docs/patches/` e o Capitão aplica (ou sob o consentimento escopado da ordem M5, quando existir).

## Prova
Testes por estado e por transição inválida; flag desligada idêntica à M1. `maestro evidence --record --label order-51 -- bash tests/run-all.sh`.

Depende de: ordem 50 (Maestro) aceita.

## Turno

- fatia: o enum estendido e os três comandos gravando recibo
- fim: testes de transição verdes; `bash tests/run-all.sh` sai 0
- teto: 5
- fora: o revisor headless (ordem M3), a estação de integração real (daemon D4) e qualquer edição em hooks/bin/src
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/051-estados-de-revis-o-integra-o-e-e`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-51 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 051` (você não fecha a própria ordem).
