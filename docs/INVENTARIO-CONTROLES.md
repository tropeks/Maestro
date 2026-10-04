# Inventário de controles — custo e ganho medidos

Ordem 061, autorizada pela v59 item 4 do INTENT do spock ("enxugar"; o INTENT carimbado no repo é a v6).
**Só leitura:** o documento mede e propõe; **não remove, desliga nem altera nenhum controle.** Cada `sai` ou
`vira opcional` que o Diretor aprovar vira ordem própria. Medido em 2026-10-04.

## Método

- **Disparos** (`L=` ledger, `T=` telemetria local): contagem de eventos de `~/.maestro/logs/routing.jsonl` (`L`) e de
  `~/.maestro/telemetry/logs/*/routing-current.jsonl`, os dois hosts locais (`T`; o push que falha não conta, o dado
  local basta). A janela de datas é a do ledger; a telemetria alcança mais longe (desde 2026-08-12). Só entram
  eventos de sessão real (id UUID): 306 `gate_block` da sessão-fixture `sess-abc123` e os `turno_teto` das sessões
  de medição `med056` e `s56` foram descartados (ver Achados). Controle que **não tem emissor** de evento é
  `sem fonte`; controle com emissor e nenhuma ocorrência é `0`.
- **Custo, tempo (`t=`):** `tools/medir-controles.sh` (somente leitura, em fixtures de sandbox, nunca contra projeto
  real) com o método de `tests/lib/latency.sh`: mediana de 31 amostras, em ms inteiros. A bancada estava **sob carga**
  (load1m×100 = 653, 8 CPUs, sonda do kill-switch 10 ms; o limiar de máquina quieta é 200), então os tempos estão
  inflados e valem como **ordem de grandeza e ranking**, não como orçamento: pelo critério de `latency.sh`, acima do
  limiar o veredito é "inconclusivo", nunca regressão. Guarda que mora dentro de um hook herda o tempo do **caminho do
  hook** que a contém (não é separável); sensor herda o de `post-edit-habits` (uma passada de awk para todos).
- **Custo, manutenção (`m=<p>p/<c>c`):** `p` = patches de `docs/patches/` que tocam o arquivo do controle; `c` = commits
  do `git log` que tocam o arquivo. Arquivo compartilhado (`hooks/lib/habit-sensors.awk`, `hooks/lib/common.sh`,
  `hooks/session-start.sh`) conta inteiro para cada controle que mora nele. Regravação de recibo por controle: **sem
  fonte** (o recibo é sobrescrito, o ledger não guarda a história).
- **Ganho:** `sim — <evidência>` só com ordem, commit, issue ou evento que nomeie a falha; evento de bloqueio
  prova que o controle **agiu**, e vale como ganho quando o evento nomeia a classe da falha. Sem isso, `sem evidência`.
- Só inteiros (ms e contagens). Nada de prompt nem de caminho completo de arquivo.

## Tabela

| controle | efeito | disparos | custo | ganho | proposta |
|---|---|---|---|---|---|
| hook:session-start | registra e injeta contexto: bloco de roteamento, compila a política do gate, limpa decision records expirados | sem fonte | t=258ms m=6p/31c | sem evidência | fica — é a entrada do produto, uma vez por sessão; sem ele nenhum outro hook tem política |
| hook:pre-tool-gate | bloqueia Edit, Write e MultiEdit sem decisão de roteamento, em caminho do plugin ou em zona congelada; registra gate_pass | L=10152 T=15933 2026-09-06..2026-10-04 | t=127ms m=3p/12c | sim — 152 gate_block em sessão real (ledger) e 1 frozen_zone em 2026-09-25 | fica — é o trilho central; 127 ms por edição sob carga alta, ver Método |
| hook:pre-bash-guard | bloqueia comando destrutivo e escrita em self_paths por Bash; avisa em modo warn | L=1110 T=1848 2026-09-03..2026-10-04 | t=44ms m=1p/4c | sim — gate_block cmd=accept x6 (2026-09-25..2026-10-02): o executor tentou aceitar a própria ordem | fica — barato (44 ms) e com bloqueios nomeados por classe |
| hook:pre-agent | registra delegation phase=started por disparo de subagente | L=681 T=681 2026-09-08..2026-10-03 | t=40ms m=0p/1c | sim — é a prova de delegação que o outcome accepted exige (E23a); 681 started no ledger | fica — sem ele a prova de delegação some |
| hook:pre-director-ask | registra o marcador director_ask que libera o Stop | L=175 T=175 2026-09-19..2026-10-03 | t=53ms m=0p/1c | sim — ordem 029: 175 director_ask no ledger liberam o Stop contra evidência, não contra prosa | fica — é a metade do gate-report |
| hook:user-prompt-submit | registra override_manual e route_fix (só o nome do comando, nunca o prompt) | L=456 T=484 2026-09-07..2026-10-03 | t=47ms m=0p/4c | sem evidência | fica — alimenta a métrica principal (ADR-008) e o retro; nunca bloqueia |
| hook:post-edit-habits | avisa o smell achado na edição, com o guia | L=1087 T=1562 2026-09-06..2026-10-04 | t=97ms m=2p/7c | sim — ordem 045 pagou a dívida que os sensores apontavam (oversized-function 6, deep-nesting 10; merge 762c316) | fica — o aviso é o que sustenta o ganho dos sensores |
| hook:session-end | registra session_end com decided e settled | L=226 T=228 2026-09-03..2026-10-04 | t=125ms m=0p/3c | sem evidência | vira opcional — só o retro lê; 125 ms ao fechar a sessão; não bloqueia nem avisa |
| hook:subagent-stop | registra delegation phase=received | L=22432 T=22432 2026-09-08..2026-10-04 | t=33ms m=0p/1c | sem evidência | vira opcional — 22432 received contra 681 started: o funil está inflado (Achado 1); ordem própria decide se conserta ou desliga |
| hook:gate-report | bloqueia o Stop com gate humano pendente sem director.ask; registra a paráfrase | L=0 T=0 2026-09-03..2026-10-04 | t=24ms m=0p/6c | sim — ordens 025, 029 e 038 (c918dcd, 5de7f1d) nasceram de rodada que terminava sem perguntar ao Diretor | fica — transporte da Ponte; 0 bloqueio na janela, ver Achado 3 |
| hook:stop-turno | bloqueia o Stop da ordem em curso sem recibo válido no tip | L=0 T=0 2026-09-03..2026-10-04 | t=13ms m=2p/2c | sem evidência | fica — 13 ms; nenhum disparo real na janela (Achado 3) |
| guarda:self_paths-write-edit | bloqueia Write e Edit em caminho do próprio plugin | sem fonte | t=127ms m=1p/1c | sem evidência | fica — protege hooks/ do próprio agente; o evento não se distingue do gate de decisão (Achado 2) |
| guarda:self_paths-bash | bloqueia escrita por Bash ou python em self_paths | L=1 T=1 2026-10-03..2026-10-03 | t=44ms m=1p/4c | sim — gate_block cmd=self_path_write em 2026-10-03 (ledger); ordem 047 | fica — um disparo real, custo dentro do pre-bash-guard |
| guarda:destrutiva | bloqueia (modo block) ou avisa (modo warn) comando destrutivo, por classe | L=1109 T=1847 2026-09-03..2026-10-04 | t=44ms m=1p/4c | sim — 284 gate_block Bash por classe (rm_recursive, privilege_escalation, git_reset_hard, sql_drop, git_clean e outras) | fica — o dano evitado por comando não é registrado, só a classe |
| guarda:gate-de-decisao | bloqueia Edit e Write sem decision record da sessão | L=152 T=450 2026-09-08..2026-10-04 | t=127ms m=3p/12c | sim — 152 gate_block em sessão real (ledger) | fica — é a razão de existir do pre-tool-gate |
| guarda:politica-compilada | registra a política do gate compilada por sessão (E26) | sem fonte | t=sem fonte m=6p/31c | sim — a978175: a política era global e dois gerentes se corrompiam calados | fica — sem rastro no ledger (Achado 2) |
| guarda:consent | registra concessão temporária e escopada que relaxa a guarda | L=76 T=92 2026-09-06..2026-10-02 | t=sem fonte m=sem fonte | sem evidência | fica — 46 grants e 30 revokes mostram uso real; nada nomeia falha evitada |
| guarda:gate-plan | avisa — a instrução injetada manda parar e pedir aprovo antes de editar feature ou refactor | sem fonte | t=24ms m=0p/6c | sem evidência | fica — é gate humano do Diretor; sem rastro no ledger (Achado 2) |
| guarda:gate-ship | avisa — a instrução injetada manda parar e pedir shipa antes de publicar | sem fonte | t=24ms m=0p/6c | sem evidência | fica — é gate humano do Diretor; sem rastro no ledger (Achado 2) |
| guarda:kill-switch | registra nada: sai 0 antes de qualquer trabalho quando MAESTRO_OFF=1 | sem fonte | t=15ms m=4p/21c | sem evidência | fica — é fronteira inviolável do CLAUDE.md e o piso de custo de todo hook |
| guarda:zona-congelada | bloqueia Write em caminho congelado da ordem (frozen) | L=1 T=1 2026-09-25..2026-09-25 | t=127ms m=3p/12c | sim — gate_block cmd=frozen_zone em 2026-09-25 (ledger) | fica — um disparo real |
| sensor:oversized-file | avisa arquivo acima do teto de linhas | L=314 T=422 2026-09-06..2026-10-04 | t=sem fonte m=0p/10c | sim — patches 050 e 056 e commit 40f5516 dividiram arquivo acima do teto | fica — o sensor mais disparado; custo na mesma passada de awk |
| sensor:oversized-function | avisa função acima do teto de linhas | L=141 T=227 2026-09-06..2026-10-03 | t=sem fonte m=0p/10c | sim — ordem 045 (oversized-function 6, merge 762c316) | fica — ganho provado |
| sensor:deep-nesting | avisa aninhamento acima do teto | L=195 T=338 2026-09-06..2026-10-04 | t=sem fonte m=0p/10c | sim — ordem 045 (deep-nesting 10, merge 762c316) | fica — ganho provado |
| sensor:type-escape | avisa escape de tipo (any, cast forçado) | L=106 T=177 2026-09-08..2026-10-04 | t=sem fonte m=0p/10c | sem evidência | fica — dispara com regularidade; falta medir se o aviso muda a edição seguinte |
| sensor:debug-leftover | avisa resto de depuração (console.log, set -x) | L=101 T=108 2026-09-08..2026-10-03 | t=sem fonte m=0p/10c | sem evidência | fica — dispara com regularidade; custo marginal zero |
| sensor:swallowed-error | avisa erro engolido | L=49 T=67 2026-09-10..2026-10-01 | t=sem fonte m=0p/10c | sem evidência | fica — guarda falha silenciosa, que custa caro quando passa |
| sensor:too-many-params | avisa função com parâmetros demais | L=37 T=52 2026-09-10..2026-10-03 | t=sem fonte m=0p/10c | sem evidência | fica — dispara com regularidade; custo marginal zero |
| sensor:test-gap | avisa código novo sem teste correspondente | L=29 T=34 2026-09-10..2026-10-03 | t=sem fonte m=2p/7c | sem evidência | fica — mora em post-edit-habits.sh; 29 disparos |
| sensor:empty-impl | avisa implementação vazia | L=9 T=12 2026-09-12..2026-09-28 | t=sem fonte m=0p/10c | sem evidência | fica — baixo volume, custo marginal zero |
| sensor:skipped-test | avisa teste pulado | L=5 T=7 2026-09-13..2026-09-28 | t=sem fonte m=0p/10c | sem evidência | fica — baixo volume, mas teste pulado esconde regressão |
| sensor:risky-shortcut | avisa atalho arriscado | L=5 T=5 2026-09-18..2026-09-26 | t=sem fonte m=0p/10c | sem evidência | fica — baixo volume, custo marginal zero |
| sensor:dead-code | avisa código morto | L=5 T=15 2026-09-10..2026-10-03 | t=sem fonte m=0p/10c | sem evidência | fica — baixo volume; o código morto da idade (legado:teto-de-idade) escapou dele |
| sensor:doc-governed | avisa edição de arquivo coberto por doc canônico | L=4 T=4 2026-09-10..2026-09-28 | t=sem fonte m=2p/7c | sem evidência | vira opcional — 4 disparos em 28 dias; o drift de docs já tem `maestro docs --check` |
| sensor:slop-comment | avisa comentário de slop | L=3 T=3 2026-09-27..2026-09-28 | t=sem fonte m=0p/10c | sem evidência | vira opcional — 3 disparos, ambos num único par de dias, sem ganho nomeado |
| sensor:lint-suppression | avisa supressão de lint | L=2 T=2 2026-09-28..2026-09-28 | t=sem fonte m=0p/10c | sem evidência | vira opcional — 2 disparos num único dia; o lint do projeto já barra |
| sensor:regencia | avisa quando a regência (conduct) deixou flag aberta | L=82 T=89 2026-09-08..2026-10-04 | t=sem fonte m=2p/7c | sem evidência | fica — 82 disparos; mora em post-edit-habits.sh |
| sensor:catraca-baseline | bloqueia — `habits --all` reprova só o que excede o baseline (.maestro-habits.tsv) | sem fonte | t=113ms m=3p/11c | sim — ordem 045 pagou a dívida (762c316); 3ebb4b1 e bb1aced barraram crescimento acima do teto | fica — ganho real, mas gerou 3 patches (045-habits-protegidos, 050-habits-catraca, 056-habits-catraca), cada um com recibos regravados (por controle: sem fonte); a ordem que executar mexe na forma, não na existência |
| verificacao:por-area-E23b | bloqueia aceite e outcome accepted quando a área tocada exige rótulo sem recibo válido | L=39 T=39 2026-09-06..2026-09-30 | t=62ms m=2p/2c | sim — 15 eventos verify com faltas (ledger): recibo exigido ausente | vira opcional — no Maestro os dois rótulos exigidos são `suite`, o mesmo recibo que o aceite já prova; mantém para projeto que declara área própria (billing, tenant-isolation) |
| verificacao:recibos-de-evidencia | registra recibo de execução amarrado a conteúdo, com veredito único (060) | sem fonte | t=130ms m=5p/7c | sim — ordem 060: recibo VENCIDO no evidence saía provada no aceite (CHANGELOG, Unreleased) | fica — é a base do aceite; 488 recibos locais, o custo é o patch por mudança de critério |
| verificacao:aceite-direcao-E22 | bloqueia o aceite quando a direção do projeto mudou depois da ordem | L=374 T=383 2026-09-05..2026-10-04 | t=sem fonte m=1p/5c | sem evidência | fica — o ledger só conta aceites concluídos; as recusas não deixam rastro (Achado 2) |
| verificacao:aceite-prova-ed25519 | bloqueia o aceite sem prova de identidade do Diretor, quando MAESTRO_ACCEPT_REQUIRE_PROOF está ligado | sem fonte | t=sem fonte m=0p/1c | sem evidência | fica — barra o executor fechar a própria ordem; sem rastro de recusa (Achado 2) |
| verificacao:aceite-validacao-050 | bloqueia o aceite com estado de validação pendente | L=0 T=0 2026-09-03..2026-10-04 | t=sem fonte m=1p/1c | sem evidência | fica — 0 order_validate na janela; recente demais para decidir, reavaliar |
| verificacao:conform-check | registra as lacunas do projeto para entrar no método; sai 1 com lacuna | L=19 T=19 2026-10-03..2026-10-04 | t=234ms m=1p/2c | sim — 13 de 19 execuções saíram rc=1 com lacunas reais (ledger conform) | fica — sob demanda, fora do caminho de hook |
| verificacao:doctor | avisa instalação quebrada (hooks, dependências, schemas, permissões) | sem fonte | t=2475ms m=sem fonte | sem evidência | fica — 2475 ms sob carga, mas sob demanda; não emite evento |
| verificacao:evals | avisa regressão da tabela de roteamento contra os casos de tests/eval | sem fonte | t=sem fonte m=0p/12c | sem evidência | fica — roda sob demanda, fora do caminho de hook; não emite evento |
| legado:teto-de-idade | registra nada: `maxage` e MAESTRO_EVIDENCE_MAX_AGE são lidos em lib/cmd-evidence.sh e nenhum veredito os usa | sem fonte | t=sem fonte m=sem fonte | sem evidência | sai — depois da 060 a idade é só informação impressa; código sem leitor; ordem própria remove (toca lib/, patch protegido) |
| legado:deferred_by | registra o estado `adiada`: congela o recibo e não cobra aceite | sem fonte | t=sem fonte m=3p/2c | sim — a ordem 013 nasceu de ordem real adiada (vitali 004); ponte-daemon 010 e vitali 004 ainda carregam o campo | fica — ainda tem leitor em status, order-json e session-start; só a idade morreu |

## Lista proposta

Uma linha por controle da tabela, com a mesma proposta. Nada abaixo foi executado.

- `hook:session-start` — fica — entrada do produto; sem ele nenhum outro hook tem política
- `hook:pre-tool-gate` — fica — trilho central, com bloqueios reais no ledger
- `hook:pre-bash-guard` — fica — barato e com bloqueios nomeados por classe
- `hook:pre-agent` — fica — é a prova de delegação que o outcome accepted exige
- `hook:pre-director-ask` — fica — metade do gate-report, 175 liberações
- `hook:user-prompt-submit` — fica — alimenta a métrica principal e o retro; nunca bloqueia
- `hook:post-edit-habits` — fica — o aviso sustenta o ganho dos sensores
- `hook:session-end` — vira opcional — só o retro lê; 125 ms ao fechar; não bloqueia nem avisa
- `hook:subagent-stop` — vira opcional — funil inflado (22432 received contra 681 started); ordem própria decide conserto ou desligamento
- `hook:gate-report` — fica — transporte da Ponte; 0 bloqueio na janela
- `hook:stop-turno` — fica — 13 ms; nenhum disparo real na janela
- `guarda:self_paths-write-edit` — fica — protege hooks/ do próprio agente; evento não distingue do gate de decisão
- `guarda:self_paths-bash` — fica — um disparo real, custo dentro do pre-bash-guard
- `guarda:destrutiva` — fica — dano evitado por comando não é registrado, só a classe
- `guarda:gate-de-decisao` — fica — razão de existir do pre-tool-gate
- `guarda:politica-compilada` — fica — sem rastro no ledger; a978175 prova o ganho
- `guarda:consent` — fica — uso real (46 grants, 30 revokes); nada nomeia falha evitada
- `guarda:gate-plan` — fica — gate humano do Diretor; sem rastro no ledger
- `guarda:gate-ship` — fica — gate humano do Diretor; sem rastro no ledger
- `guarda:kill-switch` — fica — fronteira inviolável do CLAUDE.md e piso de custo
- `guarda:zona-congelada` — fica — um disparo real
- `sensor:oversized-file` — fica — o mais disparado; custo na mesma passada de awk
- `sensor:oversized-function` — fica — ganho provado na ordem 045
- `sensor:deep-nesting` — fica — ganho provado na ordem 045
- `sensor:type-escape` — fica — dispara com regularidade; falta medir a resposta ao aviso
- `sensor:debug-leftover` — fica — dispara com regularidade; custo marginal zero
- `sensor:swallowed-error` — fica — guarda falha silenciosa
- `sensor:too-many-params` — fica — dispara com regularidade; custo marginal zero
- `sensor:test-gap` — fica — 29 disparos
- `sensor:empty-impl` — fica — baixo volume, custo marginal zero
- `sensor:skipped-test` — fica — baixo volume, teste pulado esconde regressão
- `sensor:risky-shortcut` — fica — baixo volume, custo marginal zero
- `sensor:dead-code` — fica — baixo volume; o código morto da idade escapou dele
- `sensor:doc-governed` — vira opcional — 4 disparos em 28 dias; o drift de docs já tem `maestro docs --check`
- `sensor:slop-comment` — vira opcional — 3 disparos em dois dias, sem ganho nomeado
- `sensor:lint-suppression` — vira opcional — 2 disparos num dia; o lint do projeto já barra
- `sensor:regencia` — fica — 82 disparos
- `sensor:catraca-baseline` — fica — ganho real; o custo é de forma (3 patches e recibos regravados), não de existência
- `verificacao:por-area-E23b` — vira opcional — no Maestro os rótulos exigidos são `suite`, o recibo que o aceite já prova; mantém para projeto com área própria
- `verificacao:recibos-de-evidencia` — fica — base do aceite
- `verificacao:aceite-direcao-E22` — fica — recusas não deixam rastro
- `verificacao:aceite-prova-ed25519` — fica — barra o executor fechar a própria ordem
- `verificacao:aceite-validacao-050` — fica — 0 disparos; recente demais para decidir
- `verificacao:conform-check` — fica — 13 de 19 execuções acharam lacuna real
- `verificacao:doctor` — fica — sob demanda, fora do caminho de hook
- `verificacao:evals` — fica — sob demanda, fora do caminho de hook
- `legado:teto-de-idade` — sai — código sem leitor depois da 060; ordem própria remove
- `legado:deferred_by` — fica — ainda tem leitor e uso real; só a idade morreu

### Os três candidatos de partida

1. **Código morto da idade** — `legado:teto-de-idade` **sai**; `legado:deferred_by` **fica** (o estado `adiada` tem leitor
   em `lib/cmd-order-status.sh`, `lib/cmd-order-json.sh`, `lib/core-order-state.sh` e `hooks/session-start.sh`, e duas
   ordens de outros projetos ainda o carregam). O que morreu foi só o teto de idade.
2. **Verificação por área** — `verificacao:por-area-E23b` **vira opcional**: no `.maestro.yaml` do Maestro as duas áreas
   exigem o rótulo `suite`, que já é o recibo do aceite; nada a mais é cobrado aqui.
3. **Catraca do `habits`** — `sensor:catraca-baseline` **fica**: barrou crescimento real, mas gerou 3 patches só para
   caber sob o teto (`045-habits-protegidos`, `050-habits-catraca`, `056-habits-catraca`).

## Achados

1. **O funil de delegação está inflado.** `hook:subagent-stop` registrou 22432 `delegation received` contra 681
   `started` (33 por 1) em 128 sessões, com picos de 4677 num dia (2026-09-28); isso é 56 por cento dos 39471 eventos do
   ledger (arquivo de 5681015 bytes). `maestro delegation` conta esse funil, então o `received` não é confiável.
2. **Controles sem rastro no ledger** (não provam ganho; `sem fonte`): `guarda:gate-plan`, `guarda:gate-ship`,
   `guarda:politica-compilada`, `guarda:kill-switch`, `hook:session-start`, a catraca do `habits`,
   `verificacao:recibos-de-evidencia`, `verificacao:doctor`, `verificacao:evals`. Dois têm rastro **ambíguo**:
   `guarda:self_paths-write-edit` e `guarda:gate-de-decisao` emitem o mesmo `gate_block`, sem distinguir a causa; e
   as **recusas** do aceite (E22, Ed25519, 050) não emitem evento — só o aceite concluído (`order_accept`) deixa rastro.
   Ordem 061 não acrescenta log (Ask-First); se o Diretor quiser medir, é ordem própria.
3. **Emissor sem ocorrência na janela:** `gate_block` de paráfrase e `director_ask` sem socket (gate-report),
   `turno_timeout` (stop-turno), `order_validate` (050) e `budget_warn` (pre-tool-gate) têm código que emite e **0**
   ocorrências no ledger e na telemetria local. Pode ser controle sadio (nada a barrar) ou morto; o número sozinho
   não decide.
4. **O ledger real está sujo de teste.** 306 `gate_block` de Edit vêm da sessão-fixture `sess-abc123` (2026-09-17,
   dois minutos) e os 12 `turno_teto` vêm das sessões de medição `med056` e `s56`: a suíte ou uma medição gravou no
   `~/.maestro` real. Descartados das contagens acima; sem o filtro, o gate de decisão apareceria com 458 bloqueios
   em vez de 152 e o stop-turno com 12 disparos em vez de 0.
5. **Custo por chamada sob carga.** `hook:session-start` (258 ms), `hook:pre-tool-gate` (127 ms, a cada edição),
   `hook:session-end` (125 ms) e `hook:post-edit-habits` (97 ms, a cada edição) são os caros; o piso do kill-switch
   é 15 ms. Repetir `tools/medir-controles.sh` em máquina quieta antes de decidir qualquer corte por tempo.
6. **Custo de manutenção concentrado.** `bin/maestro` aparece em 14 patches, `hooks/session-start.sh` em 6 patches e
   31 commits, `hooks/lib/common.sh` em 4 patches e 21 commits: o custo está no despachante e na entrada, não nos
   sensores (`hooks/lib/habit-sensors.awk`: 0 patches, 10 commits para os 13 sensores).

## Como repetir

```bash
bash tools/medir-controles.sh        # tempo por chamada, em sandbox (N=31)
bash tests/cli/test-inventario-controles.sh
```
