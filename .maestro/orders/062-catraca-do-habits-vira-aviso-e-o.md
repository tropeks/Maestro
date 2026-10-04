<!-- maestro-order v1
id: 062
ts: 2026-10-04T15:28:14-03:00
epoch: 1791138494
head: 4333629409cdec596c4a4ff10a5a3355ef8ff499
branch: order/062-catraca-do-habits-vira-aviso-e-o
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 062 — catraca do habits vira aviso e o turno de recibos grava so order-N

## Por quê

**Decisão do Capitão no gate de 04/10**, na linha da v59 ("enxugar"; o INTENT carimbado no repo é a v6, a base).
Duas decisões, uma ordem:

**A. A catraca do `habits` deixa de bloquear e passa a avisar.** `oversized-file`, `oversized-function` e
`deep-nesting` **acima do baseline** avisam e entram no relatório, mas **não reprovam a suíte nem o aceite**.
**Motivo medido:** a catraca gerou **3 patches protegidos de puro retrabalho** — `045-habits-protegidos`,
`050-habits-catraca` e `056-habits-catraca` — todos para devolver arquivo ou função a baixo do teto sem mudar
comportamento, cada um com um turno de recibos regravado. Controle que custa três ordens de retrabalho e nunca
evitou falha de comportamento não precisa bloquear; precisa ser visto.

**B. O turno de recibos grava só `order-N`.** `suite-N` (ordem 048) e `suite` (legado, para a CLI da frota
até o giro do cache, regra de 03/10) deixam de ser exigidos **onde o aceite não os pede**. Hoje cada ordem
roda a suíte completa três vezes (`order-N`, `suite-N`, `suite`: ~42 min) para provar o mesmo conteúdo.

## O que entrega

### A. Catraca vira aviso

1. **Onde a catraca bloqueia hoje (mapear primeiro, colar):** `maestro habits --all` sai **rc 1** com
   `CATRACA: slop novo acima do baseline — …` (`lib/cmd-habits.sh`, `_habits_check_baseline`); a suíte falha
   porque `tests/cli/test-habits-cli.sh` e `tests/cli/test-order-006-habits-debt.sh` exigem rc 0 no repo do
   Maestro; o CI roda `./bin/maestro habits --all` como passo (`.github/workflows/ci.yml:141`). Confirme se o
   aceite lê a catraca por outro caminho além da suíte (`order --accept`, `conform`, `doctor`).
2. **Só a comparação com o baseline vira aviso**, para os três sensores (`oversized-file`,
   `oversized-function`, `deep-nesting`): a saída passa a `AVISO catraca: slop acima do baseline — …`, com os
   mesmos números de hoje, e o **rc é 0**. O aviso aparece no relatório do `habits` e o relatório de fim de
   turno o cita quando existir. O caminho "dívida declarada VENCEU" da catraca segue a mesma regra (aviso).
3. **O que NÃO muda:** a detecção dos smells em si (`habits <arquivo>`, `--all` sobre arquivo com smell fora do
   baseline, os rc que o teste de linha 145 afirma) e o `habits --baseline` (a régua continua só descendo ao ser
   regravada). Se `--all` sair 1 por smell que **não** é comparação de baseline, **continua** saindo 1: só a
   catraca vira aviso. Mapeie e cole qual rc vem de qual causa antes de mexer.
4. **Teste que falha antes:** `tests/cli/test-order-062-catraca-aviso.sh` monta um repo de fixture com um
   arquivo acima do teto de 400 linhas e uma função acima de 60 linhas **além do baseline** e afirma:
   `habits --all` sai **0**, a saída tem `AVISO catraca` com os três sensores nomeados, e **nenhum**
   `CATRACA:` bloqueante. **Vermelho hoje** (rc 1), saída colada; verde depois.
5. Os testes existentes que afirmam rc 1 **da catraca** são ajustados ao contrato novo e listados no
   relatório, um a um. Os que afirmam rc 1 de smell **não** mudam.
6. O passo do CI (`ci.yml`, em `.github/`, fora das zonas protegidas) segue rodando `habits --all`: passa a
   mostrar o aviso sem reprovar o job.

### B. Turno de recibos só `order-N`

1. **Mapear onde o aceite pede cada rótulo (colar):** `.maestro.yaml` declara `verifications.hooks` e
   `verifications.cli` com `labels: [suite]`; `_order_verif_report` resolve `suite-N` e cai em `suite`
   (ordem 048). Ordem que toca `hooks/`, `bin/` ou `src/` o aceite exige a verificação `suite`; ordem só de
   `docs/`/`tests/` não exige nenhum rótulo além do `order-N`.
2. **Onde o aceite não pede `suite`/`suite-N` (ordens sem área tocada), o turno de recibos grava só
   `order-N`.** Os blocos "Turno de recibos" e o contrato de execução das ordens novas, o esqueleto do
   `order --create` e a regra do brief deixam de listar `suite-N` e `suite` como obrigatórios.
3. **Onde o aceite PEDE a verificação `suite` (ordem que toca `hooks/`, `bin/`, `src/`):** PARE antes de
   mudar (Ask-First). O desenho em aberto, para o Diretor escolher com o custo de cada um:
   (i) o recibo **`order-N` satisfaz o rótulo `suite`** quando seu comando é o declarado em `commands.suite`
   (`cmd_match`), então um recibo só prova as duas coisas — é uma mudança de contrato do leitor de recibo;
   (ii) manter `suite-N` só nessas ordens. Não implemente nenhum dos dois sem a escolha.
4. **Compatível:** nenhum recibo existente (`suite`, `suite-N`, `order-N`) deixa de ser lido; só deixa de ser
   **exigido** onde o aceite não o pede.

### C. O esqueleto do Turno traz a regra de log e escrita

Acréscimo do Capitão em 04/10, depois do rebase sobre `1cf3f16`. **Motivo:** a ordem **082 do daemon** só
aprova **leitura sem pedir** dentro da pasta temporária do próprio run; log de suíte jogado em `/tmp` solto
volta a gerar pedido de permissão (o ruído que a métrica 4 da 058 mede).

1. `_order_turno_skeleton` (`lib/core-order-turno.sh`, hoje 8 linhas) passa a emitir, **depois** dos cinco
   rótulos, uma linha citada (blockquote, não rótulo, para o `conform` e o Stop de turno não a confundirem
   com campo do Turno) com esta regra, em português, exatamente neste conteúdo:
   `> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
   /tmp/claude-<uid>/<cwd codificado>, nunca /tmp solto; escrita só com Edit ou Write.`
   (`<uid>` e `<cwd codificado>` ficam literais no esqueleto: quem escreve a ordem os conhece; o codificado
   é o caminho do diretório de trabalho com `/` trocado por `-`, como as pastas de `/tmp/claude-<uid>/`).
2. **Só o esqueleto muda.** Ordens já escritas não são tocadas; o `conform --check` segue exigindo os mesmos
   cinco rótulos e não acusa a linha nova; `order --create` com corpo que já traz `## Turno` não duplica nada.
3. **Teste que falha antes:** `tests/cli/test-order-062-esqueleto-regra.sh` roda `order --create` num
   projeto de fixture e afirma que a ordem criada contém a linha da regra (a de `/tmp/claude-<uid>` e a de
   Edit/Write), que os cinco rótulos continuam preenchíveis e que `conform --check` não acusa a linha.
   **Vermelho hoje** (o esqueleto não a traz), saída colada; verde depois. O teste do esqueleto da 046
   (`tests/cli/test-order-046-turno.sh`) continua verde ou é ajustado e listado.
4. **Vai no MESMO patch protegido** de A e B (`docs/patches/062-*.patch`): um `git apply` só do Capitão.

## Ask-First

- Se o aceite ou o `doctor` lerem a catraca de um jeito que o aviso quebre (rc/estado esperado), PARE e
  reporte onde antes de seguir.
- Se tirar o bloqueio exigir mudar o **formato** do baseline (`.maestro-habits.tsv`), PARE (DATA_MODEL).
- Item B.3 é decisão do Diretor, como acima. O restante de B (ordens sem área) pode seguir.
- **Toca `lib/`, autoprotegida** (`lib/cmd-habits.sh`, `lib/core-order-turno.sh` para a regra de log do
  esqueleto e, se o esqueleto do `order --create` também mudar, `lib/cmd-order.sh`): a entrega é UM patch em `docs/patches/062-*.patch`, feito em clone sandbox FORA do
  repo, testado antes e depois, aplicado pelo Capitão com um `git apply`. `tests/`, `docs/` e
  `.github/` vão direto no branch.

## Como sai

Teste e ajustes de testes em `tests/`, emendas em `docs/` e `.github/` direto no branch; `lib/` em **UM patch
protegido**. Emendas no mesmo changeset: API_SPEC (`habits`: aviso e rc; recibos exigidos pelo aceite),
ENGINEERING_SPEC (a catraca é aviso; o turno de recibos grava `order-N`; o esqueleto do Turno traz a regra de
log na pasta do run), o comentário de cabeçalho de
`.maestro-habits.tsv` e o CHANGELOG (Changed).

## Prova exigida

- Vermelho antes e verde depois do teste novo, saídas coladas; a lista dos testes ajustados e por quê.
- **Controle:** smell novo (fora do baseline) continua detectado; `habits --baseline` continua só descendo;
  recibos antigos continuam lidos.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-62` no tip com o patch aplicado
  (**só `order-62`**: esta ordem já grava como decide) e `maestro order --status 62` VÁLIDA, se a verificação
  por área da ordem não exigir `suite` — se exigir, o Ask-First B.3 vale e o relatório pede a escolha.

## Turno

- fatia: os testes vermelhos (catraca como aviso e regra de log no esqueleto do Turno), o conserto em `lib/cmd-habits.sh` e `lib/core-order-turno.sh` no sandbox e o mapa de onde o aceite pede `suite`
- fim: `bash tests/cli/test-order-062-catraca-aviso.sh` e `bash tests/cli/test-order-062-esqueleto-regra.sh` saem 1 antes (colado) e 0 depois; `bash tests/run-all.sh` completa no sandbox com o patch aplicado sai 0; patch protegido pronto e `git apply --check` ok no worktree
- teto: 4
- fora: implementar o item B.3 sem a escolha do Diretor; mudar o formato do baseline; remover o sensor ou o baseline; aplicar o patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Escrita só com Edit ou Write, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >`
> ou redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e
> medir. Patch gerado por `git diff` do sandbox para `docs/patches/` é a única saída por redirecionamento
> admitida, e só para esse arquivo. Suíte em segundo plano com espera por laço até a linha `rc=` no log.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/062-catraca-do-habits-vira-aviso-e-o`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-62 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), com a decisão do Capitão de 04/10 (v59, enxugar) como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 062` (você não fecha a própria ordem).
