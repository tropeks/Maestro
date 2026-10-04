<!-- maestro-order v1
id: 063
ts: 2026-10-04T17:13:48-03:00
epoch: 1791144828
head: 587d78799e7fb0317989257f88c4233fc9e97c86
branch: order/063-painel-do-gate-mesma-populacao-a
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 063 — painel do gate: mesma populacao antes e depois, falha alta e tres medidas novas

## Por quê

Decisão do Capitão de 04/10, depois da 062. O painel de linha de base da 058 (`tools/baseline.sh`) foi feito
para provar que **nenhuma etapa seguinte melhorou algo sem número**. Três defeitos tiram o valor dessa prova:

1. **Não compara a mesma população.** O snapshot "antes" (`docs/baseline/antes-2026-10-03.*`) e o "depois"
   olham conjuntos de ordens diferentes, com regras de seleção diferentes: a diferença entre eles não diz se
   a fábrica melhorou ou se a amostra mudou.
2. **"sem fonte" silencioso.** Quando uma fonte **que devia existir** some (ledger ilegível, git, `gh`, ssh ao
   `lab-ci`, API da Ponte), o painel imprime "sem fonte" e sai 0. Quem lê não distingue "não há dado" de
   "o instrumento quebrou". Um painel que mente por omissão é pior que nenhum.
3. **Mede o que é fácil, não o que o Capitão paga:** falta o tempo do Capitão, o retrabalho e o custo por ordem.

## O que entrega

Tudo em `tools/baseline.sh` (fora das zonas protegidas), mais testes e docs. **Continua somente leitura**: nenhuma
escrita em projeto, ledger, runner, banco ou `lab-ci`.

1. **Janela e população iguais nos dois lados.**
   - A janela "depois" começa **depois da v59: 2026-10-04T00:15:00-03:00 (epoch `1791083700`)**; o "antes" é o que
     vem antes dela.
   - A **população** é definida por **uma regra explícita, escrita no painel e aplicada igual nas duas fatias**:
     ordens com **carimbo de aceite válido**, por projeto, **sem as legadas** (ids 1 a 32 sem carimbo, que a 058 já
     separa em linha própria). Se uma ordem entra num lado por uma regra, a mesma regra vale no outro.
   - O painel imprime **N de cada lado** e a regra usada; com N pequeno ele diz isso em vez de comparar medianas
     como se fossem firmes.
2. **Falha alto, com código de saída, quando uma fonte esperada some.**
   - Três estados por métrica, nunca misturados: **ok**; **sem dado** (a fonte existe e não tem registro na
     janela — legítimo, exit 0); **FALHA** (a fonte esperada não existe, não abre ou estourou o timeout).
   - **FALHA → stderr** com a fonte e o motivo, e o painel sai com **código 3** (o 2 segue sendo uso inválido,
     como hoje). O painel parcial ainda é impresso, com a métrica marcada FALHA, para o resultado não se perder.
   - Fontes esperadas: o ledger e `routing.jsonl`, o `git` do repo, `gh` (internet, só leitura), o ssh ao
     `lab-ci` (**quando** `MAESTRO_BASELINE_LAB_SSH` está definido, padrão `lab-ci`) e a API/banco da Ponte.
3. **`gh` também no `--all`.** Hoje `gh pr list`/`gh run list` só rodam com `--project` (precisam da raiz do repo).
   No `--all` cada chave do ledger tem de resolver para um repo, e o `gh` roda por repo, só leitura. Chave que
   não resolve para um caminho é **FALHA nomeada** (a chave e por quê), não pulo silencioso.
4. **Permissões cortadas por janela.** A métrica 4 (permissões por turno, da Ponte) passa a sair **antes** e
   **depois** da janela da v59, por run e por projeto, e não mais um agregado só.
5. **Três medidas novas**, cada uma com fonte declarada e, se faltar a fonte, o estado FALHA ou "sem dado"
   conforme o item 2 (nunca estimada):
   - **Minutos do Capitão:** `captain_ask` no ledger (a pergunta e a resposta; minutos = soma dos intervalos
     pergunta→resposta onde o par é legível, em minutos inteiros) **e** os **patches aplicados por ele**,
     contados no **git** (commits `… patch protegido`, que são o `git apply` do Capitão), por ordem.
   - **Retrabalho:** **turnos devolvidos** (bloqueio do Stop de turno e ordem reenfileirada), **recibos
     regravados** (gravações do mesmo rótulo na mesma ordem além da primeira) e **turnos sem relatório**
     (`turno_timeout` e fim de turno sem os 5 rótulos). **Se a fonte de uma dessas não existe no ledger** (ex.:
     nenhum evento de gravação de recibo), o painel diz `sem instrumento`, lista no relatório e a ordem **não
     acrescenta log** (isso é `hooks/`, outra ordem): vira achado com a proposta mínima de instrumento.
   - **Custo por ordem:** em **inteiros** (tokens ou centavos; **nunca float**, regra do projeto), por ordem, da
     telemetria/ledger local onde houver registro; sem registro, `sem instrumento` como acima.
6. **Snapshot "antes" regravado** com a população e as definições novas, em `docs/baseline/antes-2026-10-04.{md,json}`
   (o de 03/10 fica como histórico). **Só o Diretor o declara referência**, depois de ler: o executor não declara.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-baseline-janela.sh`] fixture com ordens dentro e fora da janela: as duas fatias
  usam a **mesma regra**, o painel imprime a regra e o N de cada lado, e legadas ficam fora da mediana.
- [oráculo: `bash tests/cli/test-baseline-falha-alta.sh`] derrubar uma fonte esperada (ledger ilegível, `gh` que
  falha, ssh que estoura, chave do `--all` sem repo) dá **exit 3**, a fonte nomeada em stderr e a métrica
  FALHA no painel; "sem dado" (fonte presente, janela vazia) dá **exit 0**.
- [oráculo: `bash tests/cli/test-baseline-gh-all.sh`] com `gh` simulado, o `--all` o chama **por repo** e só com
  `gh pr list` e `gh run list`.
- [oráculo: `bash tests/cli/test-baseline-novas-medidas.sh`] as três medidas saem de uma fixture de ledger e de
  git, em inteiros, e a que não tem fonte sai `sem instrumento` (não zero, não vazia).
- [oráculo: `bash tests/cli/test-baseline-so-leitura.sh`] segue verde: nada escrito no repo, ledger e runners.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [humano] o Diretor lê o snapshot regravado, confere a população e declara a referência.

## Ask-First

- Se `captain_ask` ou os patches do Capitão não forem distinguíveis por um critério mecânico no ledger e no git
  (ex.: patch aplicado por outra pessoa), PARE e proponha o critério antes de contar.
- Se uma medida exigir **log novo** (evento que hoje não existe), **não o acrescente**: `sem instrumento` e a
  proposta no relatório.
- Se a regra de população deixar um dos lados com menos de 3 ordens, reporte e **não compare**.
- Rede: **só** `gh pr list`/`gh run list` (internet) e o ssh de leitura ao `lab-ci` (LAN); mais nada.
- `tools/`, `tests/` e `docs/` vão direto no branch; **não há patch protegido**. Se algo exigir `lib/`,
  `hooks/`, `bin/` ou `src/`, PARE.

## Como sai

`tools/baseline.sh`, os testes e o snapshot novo direto no branch. Emendas no mesmo changeset: o contrato do
painel (as seis métricas e as três novas, os três estados, o código 3, a regra de população) onde a 058 o
documentou, e o CHANGELOG (Changed/Added).

## Prova exigida

- Os quatro testes novos vermelhos antes (o painel de hoje não tem janela, nem exit 3, nem as medidas) e verdes
  depois, saídas coladas.
- O snapshot "antes" de 04/10 gerado e commitado, com N de cada lado e a regra.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-63` no tip e `maestro order --status 63` VÁLIDA.

## Turno

- fatia: janela e população iguais nos dois lados, estados ok/sem dado/FALHA com exit 3, e `gh` no `--all` (itens 1 a 3), com os três testes
- fim: os testes `test-baseline-janela`, `test-baseline-falha-alta` e `test-baseline-gh-all` saem 1 antes (colado) e 0 depois; `bash tests/run-all.sh` sai 0
- teto: 4
- fora: as permissões por janela e as três medidas novas (próximo turno, itens 4 e 5), acrescentar log ou hook, editar hooks/lib/bin/src, declarar o snapshot como referência e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write. Nenhum heredoc, `tee`,
> `sed -i`, `python -c`, `cat >` ou redirecionamento para escrever código, teste ou documento.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera **por
> laço** até a linha `rc=` no log; só depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/063-painel-do-gate-mesma-populacao-a`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-63 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), com a decisão do Capitão de 04/10 (v59) como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 063` (você não fecha a própria ordem).
