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

## Turno

- fatia: o painel das seis métricas sobre o repo do Maestro e o snapshot "antes", com os dois testes
- fim: os quatro critérios com oráculo saem 0; snapshot "antes" commitado; relatório lista as métricas "sem fonte"
- teto: 4
- fora: qualquer escrita em projeto, ledger ou runner; despacho automático (Etapa 2); integrar ao CLI; editar hooks/bin/src
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/058-etapa-0-painel-de-linha-de-base`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-58 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 058` (você não fecha a própria ordem).
