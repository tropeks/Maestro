<!-- maestro-order v1
id: 058
ts: 2026-10-03T21:33:53-03:00
epoch: 1791074033
head: ff78ce3703a471704a6540c0dd9fbd355d9f2b51
branch: order/058-etapa-0-painel-de-linha-de-base
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 058 — Etapa 0: painel de linha de base, só leitura

> Ordem do Capitão, 2026-10-03, **Etapa 0 do plano v2 da fábrica** (`/home/rcosta00/dev/spock/.maestro/INTENT.md`, seção "Direção 2026-10-03 - plano v2 da fábrica", INTENT v58; textos em `docs-ops/fabrica/` no Enterprise). **Proposta de ordem: só enfileira com a aprovação do Capitão.** Quem executa não fecha a própria ordem — `maestro order --accept` é do Diretor.

## Por quê
Antes de mexer na fábrica, medir. A crítica do Codex apontou que o gargalo medido hoje não é falta de paralelismo: é despacho esquecido, rebase por carimbo, ruído de permissão e CPU saturada. Sem linha de base não há como provar que nenhuma etapa seguinte melhorou algo.

## Contrato — **somente leitura**
Entregar o painel de linha de base como **ferramenta nova e autônoma** (`tools/baseline.sh`, arquivo novo fora das zonas protegidas `hooks/`, `bin/`, `src/`; integrá-la ao CLI como `maestro baseline` é patch futuro, fora desta ordem). Saída em markdown e em JSON, para o repo indicado por `--project` (e `--all` para a carteira), lendo só: o ledger e os registros de ordem (`~/.maestro/`), o `git` do repo, a telemetria e o `routing.jsonl` do Maestro e o estado do `lab-ci` e dos runners **por comandos de leitura**. **Nada é escrito fora do arquivo de saída; nada é alterado em projeto, runner ou ledger.**
Métricas:
1. por ordem, **idade em cada estado** (aberta, em execução, provada, aceita) e **tempo parado em "pronta"** (provada e não aceita);
2. **tempo da CI verde até o merge**;
3. **rebases e conflitos por causa** (carimbo, ordem concorrente, outra);
4. **permissões por turno**, e quais (a partir do `routing.jsonl` e dos registros de gate);
5. **CPU, memória e fila de runner** (carga e CPUs do `lab-ci`, runners ativos, jobs na fila);
6. **timeouts** (turno, teste, runner).
**Regra de honestidade:** métrica sem fonte legível vira "sem fonte" no painel e entra no relatório; **nunca se estima nem se inventa**.
**Gate da Etapa 0:** o painel grava um **snapshot "antes"** datado e commit-ado como referência; a comparação futura é com os **próximos 10 aceites** (o painel sabe listar quais são e recalcular as mesmas métricas só para eles).

## Critérios de aceite (com oráculo; modelo da Etapa 1)
- [oráculo: `bash tools/baseline.sh --project . --format json | jq -e '.metricas | length == 6'`] seis métricas presentes, cada uma com valor ou "sem fonte".
- [oráculo: `bash tests/cli/test-baseline-so-leitura.sh`] roda sobre um repo de fixture e prova que **nenhum arquivo** do repo, do ledger e dos runners mudou (hash antes e depois iguais).
- [oráculo: `bash tests/cli/test-baseline-sem-fonte.sh`] métrica sem fonte aparece como "sem fonte", sem número.
- [oráculo: `bash tests/run-all.sh`] suíte do Maestro verde.
- [humano] o snapshot "antes" é lido pelo Diretor e declarado referência.

## Prova
`maestro evidence --record --label order-58 -- bash tests/run-all.sh` no tip do branch.

Depende de: nada.

## Decisões do Diretor — turno 2

Registradas em 03/10 após o turno 1. Valem como contrato desta ordem; o executor não as reabre sem
prova nova. **Continua somente leitura**: nenhuma escrita em projeto, ledger, runner, banco ou `lab-ci`.

1. **Métrica 5 (CPU, memória, fila de runner): a fonte é o alias ssh `lab-ci`.** O host padrão é
   `MAESTRO_BASELINE_LAB_SSH=lab-ci` (variável de ambiente, com esse valor se ausente). **Só comandos
   de leitura**, a lista fechada: `uptime`, `nproc`, `free`, `systemctl list-units` filtrado por
   runners, e a contagem de jobs. Nada fora dessa lista; nenhum `systemctl` que altere estado, nenhum
   `sudo`. ssh que falhe ou estoure o timeout curto → a métrica vira **"sem fonte"**, nunca estimada.
2. **Métrica 2 (CI verde até o merge): `gh` só leitura.** São permitidos `gh run list` e `gh pr list`
   do repo, e **mais nada** do `gh` (nada de `gh pr merge`, `gh api` com método de escrita, `gh run
   rerun`). É a **única chamada à internet** da ordem. Sem `gh` autenticado, ou falha → "sem fonte".
3. **Métrica 4 (permissões por turno): somar as permissões da Ponte**, que são o ruído real de hoje,
   **por run e por projeto**. Fonte: **GET de leitura na API local do ponte-daemon** ou **leitura do
   banco em modo read-only** (abrir com `mode=ro`/`immutable`, nunca escrita). Complementa o
   `routing.jsonl` e os registros de gate, não os substitui. Sem acesso → "sem fonte".
4. **Ordens legadas fora da mediana.** As ordens 1 a 32 sem aceite registrado (sem carimbo de aceite
   válido) inflam o tempo parado em "pronta". O painel as separa numa **linha própria** ("legadas sem
   carimbo": quantidade e a lista de ids) **fora da mediana** da métrica 1. A mediana é só das ordens
   com carimbo.
5. **Regravar o snapshot "antes"** com as decisões 1 a 4 aplicadas e gravar o recibo **`order-58` no tip
   exato**. O snapshot **só passa a referência quando o Diretor ler o regravado**: o executor **não o
   declara referência** (o critério `[humano]` continua em aberto até lá).

**Sobre "rede":** o `gh` (internet) é a única chamada externa. O ssh para `lab-ci` é a LAN e o GET da
Ponte é `localhost`; ambos só leitura. `tools/baseline.sh` é ferramenta autônoma fora do runtime do
plugin, então a regra de "sem rede em runtime" do plugin não se aplica a ela. Se o Diretor entender a
"única rede" como excluindo o ssh, o ssh vira "sem fonte" e a métrica 5 fica para outro turno.

## Turno

- fatia: turno 2 — aplicar as decisões 1 a 5 ao painel (lab-ci por ssh só leitura, gh só leitura, permissões da Ponte, linha das ordens legadas fora da mediana) e regravar o snapshot "antes"
- fim: os quatro critérios com oráculo saem 0 com as métricas 2, 4 e 5 vindas das novas fontes (ou "sem fonte" explícita); snapshot "antes" regravado e commitado; recibo order-58 no tip; relatório lista as métricas "sem fonte"
- teto: 4
- fora: qualquer escrita em projeto, ledger, runner, banco ou lab-ci; declarar o snapshot como referência (é do Diretor); despacho automático (Etapa 2); integrar ao CLI; editar hooks/bin/src
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/058-etapa-0-painel-de-linha-de-base`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-58 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 058` (você não fecha a própria ordem).
accepted_at: 2026-10-03T23:46:54-03:00
accepted_session: desconhecido
accepted_tree: f2643688991226829620a07b84ef22077c722031
accepted_intent: 6
