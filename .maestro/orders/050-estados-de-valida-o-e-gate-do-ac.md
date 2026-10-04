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

## Reparo

Achado na suíte completa do tip da 050 (`5fc35bf`): ela reprova **só** na catraca do `habits`:
`oversized-file: 14 > baseline 13; oversized-function: 7 > baseline 6`. A 050 trouxe **um** de cada,
medidos com `maestro habits --all` no worktree da ordem:

- **oversized-file:** `lib/core-order-state.sh` — **403 linhas** (teto 400). Estava em 398 antes da 050
  (a 048 já o tinha espremido sob a catraca); a 050 acrescentou 5 linhas.
- **oversized-function:** `lib/cmd-order.sh:332` — **62 linhas** (teto 60), o despachante do `order`
  que a 050 alargou para ligar `--validate`.

**A régua não sobe.** `.maestro-habits.tsv` fica como está: o reparo divide o que entrou, no molde da
ordem 045 (decompor sem mudar comportamento).

1. `core-order-state.sh` ≤ 400: mover para `lib/core-order-validation.sh` (já nasceu na 050) ou para
   `core-order-terminal.sh` a função/bloco que a 050 colocou em `core-order-state.sh`, no molde do que a
   048 fez com `_order_receipt_file`. Margem de pelo menos 3 linhas para a próxima ordem não estourar.
2. `cmd-order.sh:332` ≤ 60: extrair o ramo do `--validate` (e o que mais a 050 colou no `case`) para
   uma função própria no arquivo de validação, deixando o despachante ≤ 60 linhas.
3. **Comportamento idêntico**, provado: `tests/cli/test-order-050-validacao.sh` e os testes `test-order*`
   passam como antes; a saída de erros do despachante não muda; nenhum caso novo.

`lib/` é autoprotegida: a correção sai como **patch NOVO** em `docs/patches/050-habits-catraca.patch`
(o `050-estados-de-validacao.patch` já aplicado **não** é editado), feito em clone sandbox FORA do repo
a partir do tip do branch, testado antes e depois e aplicado pelo Capitão com UM `git apply`.

**Prova do reparo:** `maestro habits` no sandbox com o patch: `oversized-file` 13 e `oversized-function`
6 (iguais ao baseline, nenhum acima); suíte completa `SUITE OK` sozinha no worktree; recibos `order-50`,
`suite-50` e `suite` (legado) no tip final, depois do patch aplicado. Roda **depois da 056** (um turno
ativo por vez).

## Turno de recibos

O Capitão aplicou o patch do reparo da catraca da 050 em `4b2a0c8` (tip do branch, árvore limpa). Os
recibos anteriores da 050 foram gravados com a catraca vermelha e estão **VENCIDOS** neste tip. Este turno
**só grava a prova**, com o patch aplicado:

1. Confirme árvore limpa e o tip (`git status --short` vazio, `git rev-parse --short HEAD` = `4b2a0c8`
   ou o que o Capitão tiver por cima) e a carga (`uptime`, `pgrep -fa run-all` vazio: **uma suíte pesada
   por vez**, sozinha neste worktree).
2. Confirme `maestro habits` **antes** das corridas: `oversized-file` 13 e `oversized-function` 6, iguais
   ao baseline (a régua não sobe). Se ainda houver slop acima do baseline, PARE e relate — não grave
   recibo sobre catraca vermelha.
3. Grave, **um de cada vez e em sequência** (cada um roda a suíte completa):
   `maestro evidence --record --label order-50 -- bash tests/run-all.sh`, depois `--label suite-50`,
   depois `--label suite` (rótulo legado, até a frota girar). Use o `bin/maestro` do worktree.
4. `maestro order --status 50` diz **VÁLIDA** no tip.
5. Se a suíte reprovar por **teste quebrado pelo patch**, **não conserte**: cole a saída exata do FAIL e
   relate (causa e o que o teste esperava). Código e patch não mudam neste turno.

## Turno

- fatia: gravar os recibos no tip com o patch aplicado
- fim: suite completa sozinha com SUITE OK, recibos order-50, suite-50 e suite gravados, habits na catraca, `maestro order --status 50` VÁLIDA
- teto: 2
- fora: mudar código, salvo teste quebrado pelo patch, que vira relato; aplicar patch; tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Revisão de subagente:** a revisão (revisor read-only) termina em ARQUIVO em `~/.maestro/briefs/` — o relato do turno cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**: heredoc, `tee` e redirecionamento no Bash são barrados pelo guard (ordem 047) e nunca contam como escrita.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/050-estados-de-valida-o-e-gate-do-ac`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-50 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 050` (você não fecha a própria ordem).
