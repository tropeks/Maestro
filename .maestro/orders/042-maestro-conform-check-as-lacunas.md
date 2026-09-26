<!-- maestro-order v1
id: 042
ts: 2026-09-25T18:06:30-03:00
epoch: 1790370390
head: 818064323d078dda72732f4989d21d91c434de43
branch: feat/042-conform-check
frozen: vendor/ src/ hooks/
intent_version: 6
intent_hash: 31205cc5
author_session: 2c956cd6-dea6-490a-9273-9e8077483f27
-->
# Ordem 042 — maestro conform --check: as lacunas para o projeto entrar no metodo e rodar headless, e o Conformador que as fecha

## A decisão que a autoriza

Pedido do Capitão em 25/09, com o desenho aprovado no item 17 de `~/dev/spock/docs/WISHLIST.md`
(esteira de projeto; primeiro caso: SmartQuotation). No mesmo dia, o Capitão ajustou o
escopo do Conformador: é especialista **chamado sob demanda** e tem **uma função só**. O
v1 está encerrado (`docs/ENCERRAMENTO-v1.md` §5: "nada novo sem ordem do Capitão"). Esta é
a ordem dele. Como é comando novo, a emenda do EPICS entra no MESMO changeset (CLAUDE.md:
"nada fora dele sem emenda").

Direção: INTENT v6 §Prioridades 4 (prova mecânica antes de declaração) e §Prioridades 3
(trilho onde o trilho alcança). Hoje, "o projeto está pronto para rodar headless" é
declaração: ninguém confere.

## Parte A — `maestro conform --check [<dir>]`

Comando determinístico, **sem LLM e sem rede**, que lista o que falta para um projeto entrar
no método e rodar headless. `<dir>` é opcional (o default é o toplevel do git do cwd).

**As seis famílias de lacuna, com código estável** (o vocabulário é fechado e vai para o
API_SPEC):

| família | códigos | regra |
|---|---|---|
| (a) INTENT | `intent-missing` · `intent-sections` · `intent-hash` | `.maestro/INTENT.md` existe, tem as 6 seções (Problema, Público, Resultado, Prioridades, Limites, Fora de escopo) e o `hash:` do cabeçalho bate com o corpo (reuse `_intent_valid`/`_intent_body_hash` de `lib/core-intent.sh`, sem reimplementar) |
| (b) `.maestro.yaml` | `yaml-missing` · `yaml-no-verifications` · `yaml-label-no-command` · `yaml-lab-unmarked` · `yaml-lab-only-area` | existem `verifications:` e cada rótulo tem `commands:`. Um rótulo que só roda na lab (comando com `docker`, `compose` ou `--context lab`) tem de estar declarado na chave nova `lab: [rótulo, …]`. Uma área cujos rótulos são TODOS lab não tem prova headless, porque o run headless não entra na lab |
| (c) frescor | `brief-missing` · `brief-stale` · `readme-stale` · `doc-stale` | brief em `~/.maestro/briefs/` (resolva o caminho pela função de `lib/cmd-brief.sh`, sem recalcular o nome). O `ts:` do brief, o último commit do README e o de cada doc de `docs:` do yaml não são anteriores ao `ts:` do INTENT |
| (d) ordens | `order-no-headless` | cada ordem **não terminal** (estado lido de `maestro order --status N --json` e da derivação que já existe, sem recalcular) tem a seção de execução headless: uma linha que começa por `Execução headless`, em título ou em negrito (a convenção das ordens 022–024 do vitali) |
| (e) daemon | `ponte-unregistered` · `ponte-no-policy` · `ponte-unreadable` | linha em `manager_definition` de `~/.ponte/ponte.db` para o slug do projeto (a regra de `slugifyProjectName` do daemon: minúsculas, `_`→`-`), com `manager_model_policy`, `tool_allowlist` e `risk_policy` não nulos. Abra **somente em read-only** (`sqlite3 -readonly` ou URI `mode=ro`). Se faltar `sqlite3` ou o banco, sai `ponte-unreadable`: é lacuna, não crash e não aprovação |
| (f) CLAUDE.md | `claude-md-missing` | `CLAUDE.md` na raiz |

**Saída texto:** uma lacuna por linha, `<código>\t<alvo>\t<fix>`. O alvo é relativo ao
projeto (`docs/API_SPEC.md`, `ordem 023`, `rótulo e2e`). A ordem das linhas é estável,
por família e depois por alvo. **Saída `--json`** para a persona consumir:
`{"project":…,"conforme":bool,"lacunas":[{"codigo","familia","alvo","fix"}]}`.

**Exit:** `0` só com zero lacunas · `1` com lacuna · `2` para erro de uso (dir inexistente,
flag desconhecida). O stdout do exit 0 também é estável.

**Não escreve nada, em lugar nenhum:** nem no projeto, nem em `~/.maestro/`, nem no
`ponte.db`. O único rastro permitido é o `log_event conform` com metadado (`n_lacunas`,
`familias`, `rc`). No log não entra caminho nem nome de doc.

**Limite de linhas do método:** o comando mora em `lib/cmd-conform.sh`, carregado sob
demanda no molde de `_order_json_lib_load`. O `bin/maestro` ganha só o despacho. Se o
módulo passar de 400 linhas (sensor `oversized-file`), divida em `lib/core-conform-*.sh`.
Não pede baseline novo: o `maestro habits` fica dentro da catraca.

**Emendas no mesmo changeset:** API_SPEC (contrato CLI, os códigos e o JSON), DATA_MODEL
(chave `lab:` do `.maestro.yaml`) e EPICS (story nova do conform).

## Parte B — o envelope `agents/conformador.md`

**Função única:** deixar o projeto conforme ao método até `maestro conform --check` sair
com 0. Não faz mais nada.

- **Só é chamado sob demanda**, pelo Capitão ou pelo Diretor, em caso específico. Não fica
  de plantão, não ronda projeto sozinho e não entra no roteamento automático: fica fora do
  roster injetado e da routing table.
- **Não conduz o office-hours.** O office-hours continua sendo a skill `gstack-office-hours`
  numa sessão à parte. Para projeto novo, o Conformador parte do que ela deixou (design
  doc e rascunho de INTENT em `spock/docs/ideias/<nome>/`). Para projeto existente, parte
  do repo.
- **O ciclo:** rodar `maestro conform --check --json` → fechar lacuna → rodar de novo. Para
  as lacunas de desenho (ARCHITECTURE, SECURITY, DESIGN, prova e deploy), lança o swarm com as
  skills `system-architect`, `security-architect`, `ux-architect`, `ai-architect` e
  `devops-homelab`. Achado do swarm que muda escopo é decisão do Capitão, não dele.
- **Perguntas:** quem chamou define o canal. Se o Capitão chamou em sessão com `/rc`, a
  pergunta sai na própria sessão. Nos outros casos, sai por `director_ask`. As perguntas do
  swarm vão agrupadas numa decisão só.
- **Proibido:** resolver gate, aceitar ordem, fazer merge, fazer ship e escrever no
  `ponte.db`. O cadastro e a política no daemon são do Diretor: as lacunas `ponte-*` viram
  pergunta, não escrita.
- **Termina** quando o check sai com 0 ou quando só sobram lacunas que não são dele. Relata
  por `director_report`: as lacunas fechadas, as que sobraram e com quem estão, e as
  decisões pedidas.

## Ask-First (pare e reporte ao Diretor)

- **Arquivo novo em `agents/`:** a autoproteção (INTENT v6 §Limites) barra `agents/` fora
  de `effort`/`omitClaudeMd`. A liberação do arquivo novo é do Diretor. Não contorne.
- **Subagente não lança subagente.** Se o envelope só servir como persona de sessão
  (`claude --agent`) para poder abrir o swarm, isso vai escrito no envelope e no
  relato. Pedir `Agent` em `tools:` fora do vocabulário é Ask-First.
- Se a Parte B estourar o orçamento ou o limite de linhas, ela sai como **ordem 043** e a
  042 entrega só a Parte A. Decida isso ANTES de começar a Parte B e relate.

## Prova exigida

- **Um fixture por código de lacuna** em `tests/`: cada fixture dispara exatamente um código
  e só ele, com exit 1. Mais um **projeto conforme** com exit 0 e stdout vazio de lacunas.
  O `ponte.db` dos testes é fixture (`MAESTRO_PONTE_DB` ou equivalente), nunca o real.
- **`--json`** validado por schema em todos os fixtures. Texto e JSON listam as mesmas
  lacunas, na mesma ordem.
- **Não escreve:** o hash da árvore do fixture, o do `ponte.db` fixture e o de
  `~/.maestro/` (fora do log) são idênticos antes e depois. Um banco `chmod 0444` não quebra
  o comando.
- **Degradação:** sem `sqlite3` no PATH sai `ponte-unreadable` com exit 1, sem crash.
- **Estado real:** `maestro conform --check ~/dev/NetForge` e `~/dev/vitali`, texto e
  `--json`, com a saída colada no relato. É só leitura: nada é corrigido nesses repos.
- **Parte B:** o envelope passa nos testes de frontmatter do roster (ordem 039). Um teste
  mostra que o Conformador fica fora do roster injetado e da routing table. Outro confere
  que o corpo nomeia as proibições (gate, aceite, merge, ship, `ponte.db`) e os dois canais
  de pergunta.
- Suíte verde; `doctor` sem mudança de veredito; `habits` dentro da catraca; recibo no tip.

## Contrato de execução
- Trabalhe APENAS no branch `feat/042-conform-check`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ src/ hooks/
- Prove com o ledger: `maestro evidence --record --label order-42 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 042` (você não fecha a própria ordem).
accepted_at: 2026-09-26T08:07:51-03:00
accepted_session: desconhecido
accepted_tree: d7b2cdfc962af51e5d4ce3f8a9ec1f9acf41f595
accepted_intent: 6
