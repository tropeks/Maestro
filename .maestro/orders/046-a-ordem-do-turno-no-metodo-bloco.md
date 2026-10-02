<!-- maestro-order v1
id: 046
ts: 2026-10-02T09:17:38-03:00
epoch: 1790943458
head: 10d514eb3d058408024bcdb1fe9bd6f9d35bd425
branch: order/046-a-ordem-do-turno-no-metodo-bloco
frozen: vendor/ src/
intent_version: 6
intent_hash: 31205cc5
author_session: 78325be8-9ba2-4a68-b281-22a419b849cb
-->
# Ordem 046 — a ordem do turno no metodo: bloco Turno, relatorio fixo de fim de turno, conform --check exigindo os dois e Stop com criterio mecanico e teto

## A decisão que a autoriza

Prioridade 3 do INTENT v6, confirmada pelo Capitão em 02/10: **trilho onde o trilho alcança,
honra declarada onde ele não alcança.** Hoje o turno do gerente acaba por cansaço ou por
desistência: a ordem diz o QUE entregar, mas não diz o que cabe num turno, quando o turno
está terminado, nem em que formato ele se reporta. O fim de turno é honra pura. Esta ordem
leva ao trilho o que o trilho alcança (presença do bloco, presença dos rótulos do relatório,
teto de insistência) e **declara por escrito** o que ele não alcança (se o conteúdo é
verdadeiro, se a fatia estava bem cortada).

## O que entrega

1. **Bloco `## Turno` na ordem.** Seção obrigatória em toda ordem nova, com quatro rótulos,
   uma linha cada: `fatia:` (o que cabe num turno), `fim:` (critério MECÂNICO de término — um
   comando ou predicado que sai 0/1, nunca "quando estiver bom"), `teto:` (rodadas máximas,
   inteiro) e `fora:` (o que este turno NÃO faz). `maestro order --create` passa a emitir o
   esqueleto; ordem antiga continua legível e vira lacuna no `conform`, nunca erro.
2. **Relatório fixo de fim de turno.** Cinco rótulos, nesta ordem, no fim da última mensagem
   da rodada: `feito:`, `provado:` (o comando e o rc, ou "não provado"), `aberto:`,
   `decisão:` (o que exige o Diretor, ou "nenhuma") e `próximo:`. O formato mora numa seção
   do ENGINEERING_SPEC e é citado pela ordem; não cresce a injeção do SessionStart (teto
   8000 B, hoje 7456 B).
3. **`maestro conform --check` exige os dois.** Dois códigos novos, na família das ordens:
   `order-no-turno` (ordem sem o bloco, ou com rótulo faltando, ou `teto:` não inteiro) e
   `order-no-relatorio` (a ordem não cita o contrato do relatório). Mesmo molde dos códigos
   existentes: texto/JSON, ordenação estável, exit 1 se houver lacuna, só `log_event conform`.
4. **Stop de turno: o critério é o RECIBO no tip, lido do ledger.** Decisão do Capitão: recibo
   verde no tip. É mecânico sem executar comando: o hook lê o ledger e compara o hash do
   recibo (`wtree_after`) com a árvore do tip atual — a MESMA comparação do `order --status`
   (`maestro_tree_same`, ordem 044). Há ordem em curso com bloco Turno E a evidência dela não
   é VÁLIDA no tip → `decision:block` com a LISTA DO QUE FALTA: qual recibo (`order-N`, e o
   exigido pela área) está ausente ou vencido. **Presença dos rótulos do relatório (item 2) é
   checagem ADICIONAL**: entra na mesma lista de faltas, nunca é o critério — sozinha não
   bloqueia, e recibo válido libera mesmo sem ela. **Teto duro:** no máximo `teto:` bloqueios
   por ordem (o da ordem, limitado a **3 por sessão**, aprovado), contados em arquivo por
   sessão; atingido, libera e registra `turno_teto` (metadado). Reentrada
   (`stop_hook_active`) libera na hora. Qualquer falha (ledger ilegível, ordem não resolvida,
   sem git) degrada para exit 0 sem stdout: **o hook nunca prende o gerente** (INTENT
   Prioridade 1 vence a 3).
   **Orçamento (decisão do Capitão):** o NFR de 50 ms vale para o caminho COMUM — sem ordem
   em curso, zero fork de `git`, exit imediato. O Stop de turno com ordem em curso roda uma
   vez por turno e pode gastar até **2 s**, MEDIDO e declarado (p50/p95 na ARCHITECTURE,
   NFRs), com teste de teto. **Hook novo ou gate-report.sh: decide a medição** — se a
   comparação de hash dentro do gate-report.sh empurra o caminho comum de 50 ms, vira hook
   irmão; a ordem registra os números que decidiram.

## O que o trilho NÃO alcança — e fica escrito

O trilho é o RECIBO: o ledger diz, sem LLM e sem honra, se a prova vale no tip. Fica como
**honra declarada** o que ele não alcança: o texto do relatório (um `provado: rc 0` inventado
não é detectável — por isso rótulo é checagem adicional, não critério), se o `fim:` da ordem
foi bem escolhido, e se a fatia coube no turno. O Stop não executa o `fim:` (comando
arbitrário num hook viola a fronteira de hooks/); confere o recibo que o executor gravou.
Entra no ENGINEERING_SPEC como honra declarada, com a válvula `maestro order --turno-livre
<id>` (registrada, visível no `--status`) para a ordem cuja natureza não cabe em turno.

## Ask-First

- O caminho comum (sem ordem em curso) tem de ficar <50 ms e sem fork de `git`; o Stop de
  turno pode ir a 2 s. Se a medição passar de 2 s no caso com ordem em curso, PARE e reporte
  os números antes de escrever o patch.
- Se o hook novo precisar de nova chave no `log_event`: o vocabulário está em
  `hooks/lib/common.sh` (autoprotegido) e já deixa `conform` de fora — diga qual evento
  (`turno_teto`) e proponha o patch único junto, não depois.
- Se o formato do relatório conflitar com o estilo da injeção (Google dev docs, "relatório é
  ESTADO"), o INTENT decide: emenda no mesmo changeset, não improviso.

## Como sai

`tests/` e `docs/` direto, no branch. **`lib/` também é autoprotegida** (`self_paths` do
`config/routing-table.yaml`; o `Write` barrou) — então `lib/`, `hooks/` (Stop, `common.sh`,
`hooks.json`) saem num **UM patch** em `docs/patches/046-*.patch`, aplicado pelo Capitão com um
`git apply`, testado em sandbox antes e depois — o molde da 045. `bin/` não muda: o despacho do
turno vive em `lib/cmd-order.sh`. Emendas
no MESMO changeset: DATA_MODEL (ordem), API_SPEC (conform + hook), ENGINEERING_SPEC
(relatório, honra declarada), INTENT se a Prioridade 3 pedir nota.

## Prova exigida

- **Vermelho antes:** testes de conform (ordem sem `## Turno`, rótulo faltando, `teto:` não
  inteiro, sem citação do relatório) e de hook (ordem em curso SEM recibo válido no tip
  bloqueia com a lista do que falta; recibo VENCIDA bloqueia; com recibo VÁLIDA libera, mesmo
  sem os rótulos; rótulos faltando + recibo válido NÃO bloqueia) falham antes do conserto.
- **Verde depois:** os mesmos passam; bloqueio nº `teto`+1 libera e grava `turno_teto`;
  `stop_hook_active` libera; ledger corrompido libera com exit 0 e stdout vazio; recibo
  gravado antes de um rebase que só moveu `.maestro/` segue VÁLIDA (a 044 vale aqui).
- **Fail-open:** kill-switch `MAESTRO_OFF=1` na primeira linha; sem ordem em curso, o hook
  não bloqueia nada nem forka `git`.
- **Latência, em dois números:** caminho comum <50 ms e zero fork de `git` (teto calibrado da
  ordem 016); Stop de turno com ordem em curso ≤ 2 s, p50/p95 medidos e declarados;
  injeção do SessionStart ≤ 8000 B.
- Suíte verde; `doctor` sem mudança de veredito; `habits` dentro da catraca (a régua fecha em
  6/10 depois da 045 — função nova acima de 60 linhas reprova); recibo `order-46` e `suite`
  no tip exato, árvore limpa.

## Turno

- fatia: contrato escrito (DATA_MODEL/API_SPEC/ENGINEERING_SPEC) e teste vermelho de conform
- fim: `bash tests/cli/test-order-046-turno.sh` sai 1 pelos motivos certos, depois 0
- teto: 6
- fora: o hook Stop e o patch — turno próprio, depois do conform verde
- relatório: ENGINEERING_SPEC, "O turno da ordem e o relatório de fim de turno"

> **Execução headless:** a prova é o conjunto de testes em sandbox (conform e hook) mais a
> suíte, sem humano no laço até a aplicação do patch. Nenhuma chamada externa.

## Contrato de execução
- Trabalhe APENAS no branch `order/046-a-ordem-do-turno-no-metodo-bloco`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ src/
- Prove com o ledger: `maestro evidence --record --label order-46 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 046` (você não fecha a própria ordem).
