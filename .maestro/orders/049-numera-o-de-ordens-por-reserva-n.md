<!-- maestro-order v1
id: 049
ts: 2026-10-03T12:39:23-03:00
epoch: 1791041963
head: 41213f0a454bd6c2060d9faa41f91e36ad450047
branch: order/049-numera-o-de-ordens-por-reserva-n
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 049 — Numeração de ordens por reserva no ledger

> Ordem do Capitão, 2026-10-03, do pacote da INTENT v56 (spock, seção "Direção 2026-10-03 - a linha de produção"; estende a v55). Esta peça é o **plano**: quem executa não fecha a própria ordem — `maestro order --accept` é do Diretor, e só depois da validação verde (v55 ponto 4).

## Por quê
`maestro order --create` numera pelo que está em `.maestro/orders/` da árvore onde roda, não pelo ledger nem pelos branches. Ordem que existe só em branch ou em outro worktree é invisível: a 070 e a 072 colidiram no ponte-daemon, e a 006 saiu duplicada no Enterprise. Quebra o acoplamento (c) da v56 (numeração central na árvore).

## Contrato
1. `--create` **reserva** o número no registro fora da árvore (`~/.maestro/order-state/`), com lock atômico, e carimba no cabeçalho. O número é o maior entre: arquivos da árvore, todos os worktrees do repo (`git worktree list`), todos os branches locais e remotos (`.maestro/orders/` em cada um) e as reservas já gravadas.
2. Duas criações simultâneas nunca recebem o mesmo número; colisão detectada depois (dois arquivos com o mesmo id) é **erro** em `--list`/`--status`/`conform`, nunca ordem duplicada silenciosa.
3. Reserva não consumida (ordem não commitada) expira por validade explícita e `--list` a mostra; sem expirar sozinha em silêncio.
4. Compatível: sem mudança de formato do arquivo da ordem nem do carimbo; ordens antigas continuam derivando o mesmo estado.
5. Arquivos protegidos do Maestro (`hooks/`, `bin/`, `src/`) não são editados pelo executor: a mudança sai como patch em `docs/patches/` e o Capitão aplica (ou sob o consentimento escopado da ordem M5, quando existir). Aqui o trabalho cabe em `lib/`; se o despacho em `bin/maestro` mudar, vai em patch.

## Prova
- Teste que reproduz a 070/072: dois worktrees, uma ordem só em branch, `--create` nos dois; os números diferem.
- Teste de corrida: dois `--create` em paralelo, números distintos.
- Suíte do Maestro verde: `maestro evidence --record --label order-49 -- bash tests/run-all.sh`.

## Turno

- fatia: reserva atômica e a leitura de worktrees/branches, com os dois testes de colisão
- fim: testes novos vermelhos antes e verdes depois; `bash tests/run-all.sh` sai 0
- teto: 4
- fora: estados de validação (ordem M1), migração de ordens antigas e qualquer edição em hooks/bin/src
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/049-numera-o-de-ordens-por-reserva-n`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-49 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 049` (você não fecha a própria ordem).
