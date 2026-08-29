# DATA_MODEL.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.3 — 2026-08-09 (emenda E4/S-401: `version: 2` + bloco `bindings`)
**Consome:** PROJECT_BRIEF.md, ARCHITECTURE.md | **Consumido por:** security-architect, vibe-code

> Sem banco de dados. O "modelo de dados" do Maestro são **arquivos locais com schema fixo**.
> Tenancy: N/A (single-user, ADR-006). Dinheiro: N/A.

---

## Entidades (arquivos)

### 1. `config/routing-table.yaml` (repo do plugin — versionado)

```yaml
version: 1
workflows:                    # catálogo de fluxos disparáveis
  fix:        {steps: [investigate, implement, review], gate: none}
  feature:    {steps: [plan, implement, review, qa], gate: plan}      # gate humano no plano
  refactor:   {steps: [plan, implement, review], gate: plan}
  ship:       {steps: [gstack-ship], gate: ship}                      # gate humano no ship
  audit:      {steps: [gstack-cso], gate: none}
routes:                       # intenção → workflow (lidas pelo Claude, não por regex)
  - intent: "correção de bug, erro, quebrou, não funciona"
    workflow: fix
  - intent: "nova funcionalidade, feature, adicionar, criar tela"
    workflow: feature
  - intent: "melhorar estrutura, dívida técnica, limpar"
    workflow: refactor
execution_heuristics:         # orientam a decisão modo/executor (julgamento do Claude)
  - "edição ≤2 arquivos sem plano → mode: direct"
  - "feature nova ou >3 arquivos → mode: subagent(s) com plano"
  - "tarefa mecânica/repetitiva → dev-junior (haiku)"
  - "decisão de arquitetura ou review → engenheiro/revisor"
  - "linguagem detectada → especialista correspondente"
```
`# classification: confidential` (revela estrutura do workflow pessoal; sem PII)

#### Emenda v1.3 (E4 / S-401) — `version: 2` e o bloco `bindings`

O exemplo acima é o schema **v1**. Na v2 o arquivo ganha um bloco `bindings`
obrigatório e os `steps` voltam a ser **nomes de etapa**: `gstack-ship` e
`gstack-cso` deixaram de ser step (o nome da ferramenta vazava para dentro do
fluxo) e viraram `ship` e `audit`, com a ferramenta declarada no binding.

```yaml
version: 2
workflows:
  fix:      {steps: [investigate, implement, review], gate: none}
  ship:     {steps: [ship], gate: ship}
bindings:                     # step → o que EXECUTA o step
  investigate: skill:systematic-debugging
  plan:        native:plan-mode
  implement:   agent:dev-pleno
  review:      [skill:requesting-code-review, agent:revisor]
  ship:        skill:gstack-ship
```

**Gramática.** Um step mapeia para 1 ou 2 alvos (escalar ou lista inline):

| forma | significa | resolvido em |
|---|---|---|
| `skill:<nome>` | skill do superpowers ou `/gstack-*` | `~/.claude/skills/<n>/SKILL.md`, `~/.claude/plugins/cache/*/*/*/skills/<n>/SKILL.md`, `<projeto>/.claude/skills/…` |
| `agent:<nome>` | agente do roster (DATA_MODEL §5) | `agents/<nome>.md` no repo do plugin |
| `native:<nome>` | recurso nativo do Claude Code | **vocabulário fechado: `plan-mode`** — native novo exige emenda aqui |

Regex do nome: `[A-Za-z0-9][A-Za-z0-9._-]{0,47}`. Com **2 alvos a ordem é fixa
e semântica**: `<método/ferramenta> + <quem executa>` — o `skill:` diz COMO, o
`agent:` diz QUEM. Alvo que não casa com a gramática é descartado pelo hook
(com aviso no stderr) e **reprovado** pelo doctor.

**Eixos separados.** O binding fixa *o que roda*; `execution_heuristics` decide
*quem/qual modelo roda*. Por isso `agent:` só aparece no binding quando o papel
é fixo independentemente de linguagem e tamanho (review→revisor, qa→qa,
implement→dev-pleno como default residual); em `investigate` e `plan` o
executor fica com as heurísticas.

**Curadoria** (decisão do orquestrador, E4): *método vem do superpowers ·
execução vem do roster · ferramenta pesada vem do gstack*.

**Validação (`maestro doctor`, AC da S-401 — "cada step referencia comando
existente no ambiente"):**

| falha | classe | exit |
|---|---|---|
| step de workflow sem binding | conteúdo | 1 |
| alvo fora da gramática · `native:` fora do vocabulário | conteúdo | 1 |
| `agent:` sem `agents/<nome>.md` (roster é versionado no repo) | conteúdo | 1 |
| `skill:` não instalada (skill vive fora do repo) | ambiente | 2 |
| `version: >=2` sem bloco `bindings` | conteúdo | 1 |
| binding declarado que nenhum workflow usa | aviso | 0 |
| ambiente sem **nenhuma** raiz de skill (CI limpo) | `skip` honesto | 0 |

**Injeção (S-401 + S-501).** O SessionStart passa a emitir duas seções novas:
`## Bindings` (é o binding que o Claude segue, não o nome solto do step) e
`## Gates humanos`, esta **derivada** de `workflows.*.gate` — `gate: plan` vira
"entre em plan mode, plano em ≤10 linhas, pergunte *Aprovo o plano?*" e
`gate: ship` vira "liste o que vai sair e pergunte *Shipo agora?*". O gate
humano **não é hook novo**: é instrução curta ao modelo, porque quem aprova
está no telefone (brief §3.4). Custo medido da adição: injeção de 1608 → 2310
bytes, teto de 8000 (API_SPEC §1). Na disputa por orçamento, gates e bindings
são os últimos a ceder (são instrução de ação); heurísticas e roster cedem
primeiro (são referência).

### 2. `.maestro.yaml` (raiz de cada repo de projeto — opcional)

```yaml
version: 1
project: remedix
languages: [go, python, typescript]
experts: [golang-pro, python-pro, typescript-pro]   # subconjunto do roster ativo aqui
pipeline: default            # ou nome de workflow custom
memory_container: sm_project_Remedix   # E8/S-802: containerTag do supermemory deste projeto
notes: "agente Go é o coração; nunca tocar sem testes"
```
`memory_container` (`^[A-Za-z0-9._-]{1,64}$`; malformado é omitido) vira a linha
`memória:` da seção `## Projeto` da injeção — o recall com a tag certa deixa de
depender de disciplina.
`habits` (E9): lista inline de sensores ativos do habit hook (`[a, b]`; `[]` =
desligado no projeto; ausente = todos) — vale para o hook pós-edição E para
`maestro habits`.
`.maestro-habits.tsv` (E9/S-905, raiz do projeto, VERSIONADO): baseline da catraca
anti-slop — `smell\tcontagem` por linha, comentários com `#`. Só desce por
`maestro habits --baseline`; subir exige editar o arquivo (visível em review).
`# classification: confidential`

### 3. Decision record — `~/.maestro/sessions/<session_id>.json` (efêmero)

```json
{
  "session_id": "abc123",
  "ts": "2026-08-08T21:03:11-03:00",
  "expires_at": "2026-08-09T01:03:11-03:00",
  "workflow": "fix",
  "mode": "subagent",
  "agents": ["golang-pro"],
  "reason": "bug em código Go, 1 módulo"
}
```
Campos obrigatórios: `session_id`, `ts`, `expires_at` (TTL 4h — review Opus), `workflow`, `mode`. `mode ∈ {direct, subagent, multi}`. `reason` ≤120 chars (truncado pelo CLI). Records expirados são removidos pelo SessionStart e pelo doctor. O campo `gate_pending` foi **removido** (v1.1): gates humanos rodam como passos do workflow (plan mode nativo para `plan`; confirmação explícita em sessão para `ship`), não como estado do record.

**Emenda v1.4 (E7/S-701, 2026-08-17) — campo opcional `wtree`.** Fingerprint de conteúdo
do working tree do projeto no momento da decisão (40 hex, `git write-tree` sobre index
temporário — `bin/maestro-wtree`, padrão adaptado do gstack-wtree/MIT). O TTL diz que a
decisão *envelheceu*; o `wtree` diz que o *conteúdo andou* — `maestro status` compara e
denuncia decisão possivelmente stale. Sempre opcional: sem git/fora de repo o campo é
omitido em silêncio (nunca é erro de fluxo). Formato validado pelo doctor
(`^[0-9a-f]{40}$`). **`wtree` vive SÓ no record — jamais no log (§4 intocado):** é hash
de conteúdo, não caminho nem texto, mas o vocabulário do JSONL só muda por emenda própria.
`# classification: confidential` — **PROIBIDO** campo com texto do prompt do usuário.

#### Emenda v1.5 (E10/S-1001) — desfecho no decision record
`maestro outcome` acrescenta `outcome` (accepted|rework|reverted), `outcome_ts` e
opcionalmente `suite` (pass|fail) ao record da sessão — a variável dependente do
loop de calibração. Last-wins; nunca texto livre.

**Correção (2026-08-24).** Os três campos estavam na emenda mas fora do
`RECORD_FIELDS` do doctor, então a checagem "sem campos extras" reprovava
exatamente o record de quem fechou o loop. Estão dentro agora, e **validados**:
os dois enums são fechados e `outcome_ts`/`suite` só existem com `outcome`
presente — desfecho órfão é erro de schema, não campo opcional.

### 4. Log — `~/.maestro/logs/routing.jsonl` (append-only)

Uma linha por evento. Eventos (vocabulário fechado): `decision`, `gate_pass`, `gate_warn`, `gate_block`, `override_manual`, `killswitch`, `session_end`. Hooks emitem SOMENTE este vocabulário via `log_event` do `common.sh`; o CLI serializa com `JSON.stringify` — nunca texto livre concatenado (proteção contra JSONL malformado, review Opus).

```json
{"ts":"...","event":"decision","session_id":"abc123","workflow":"fix","mode":"subagent","agents":["golang-pro"],"project":"remedix"}
{"ts":"...","event":"gate_block","session_id":"def456","tool":"Edit","file_ext":".go"}
{"ts":"...","event":"override_manual","session_id":"def456","cmd":"review"}
```
`# classification: confidential` — só metadados; `file_ext` sim, caminho completo NÃO (pode conter nome de cliente).

**Emenda v1.2 (E2):** o exemplo de `override_manual` trazia `note` com texto livre, o que
contradiz o ADR-008 (*"apenas o nome do comando — vocabulário fechado, nunca o texto do
prompt"*). Prevalece o ADR-008: a chave é `cmd` e carrega só o nome do comando. As chaves
do log são um **conjunto fechado e tipado**, validado em `common.sh::log_event`
(`session_id`, `workflow`, `mode`, `agents`, `tool`, `file_ext`, `cmd`, `project`,
`gate_mode`, `n`); par que não casa com o tipo é rejeitado com aviso, nunca reescrito.
Nenhuma chave aceita `/` — garantia estrutural contra vazamento de caminho. `reason` vive
só no decision record (§3), nunca no log.
Rotação: por tamanho (10MB) ou mensal, arquivo `routing-YYYY-MM.jsonl`.

**Emenda E10:** eventos `consent_grant`/`consent_revoke`/`outcome` no vocabulário,
com chaves `scope` (`^[a-z][a-z-]{2,23}$`), `outcome` (enum) e `suite` (enum);
`gate_pass`/`gate_warn` de edição consentida carregam `scope`. Consentimentos vivem
em `$MAESTRO_HOME/consents/<escopo>` (`expires=<epoch>`, `granted`, `session`) —
estado local, jamais no log além dos eventos.

**Emenda E9:** evento `habit_warn` entra no vocabulário fechado, com a chave
`smell` (`^[a-z][a-z-]{2,23}$` — categoria, nunca caminho/linha) e `n`
(contagem de achados). Um evento por emissão do hook, nunca por achado.

### 5. Roster — `agents/*.md` (repo do plugin)

Frontmatter obrigatório:
```yaml
name: golang-pro
description: <1 linha — vira o gate MoE; curada, sem colisão com outros agentes>
model: sonnet          # haiku | sonnet | opus
tools: Read, Grep, Glob, Write, Edit, Bash   # mínimas por papel (padrão VoltAgent)
# upstream: wshobson/agents@<commit> (atribuição de licença)
```
`# classification: public` (prompts adaptados de repositórios abertos)

### 6. Estado do doctor — `~/.maestro/capabilities.json` + `bindings-snapshot.tsv` (E7/S-705-706)

Escritos pelo `maestro doctor` a cada rodada; **estado local de diagnóstico, não log**
(o vocabulário do routing.jsonl §4 não os conhece). Consumidores: `delegate()` do
`bin/maestro` (erro sem Bun cita o envelope) e `maestro status` (idade).

```json
{"schema":"maestro.capabilities.v1","generated_at":"…","generated_epoch":1755482621,
 "runtime":{"bun":{"present":true,"version":"1.3.14"},"jq":{"present":true},
            "git":{"present":true,"version":"2.43.0"},"flock":{"present":true}},
 "doctor":{"checks":27,"warns":1,"skips":0,"fail_env":0,"fail_val":0},
 "bindings":{"resolved":9,"skill_roots":3},"roster":{"agents":9},
 "injection":{"bytes":5895,"budget":8000},"install":{"registered":1,"divergent":0,"repo_is_live":true}}
```

`install` (E7/S-710) conta as cópias do plugin registradas no Claude Code e quantas
divergem deste repo, mais `repo_is_live` (o repo é o `${CLAUDE_PLUGIN_ROOT}` vivo, via
marketplace de diretório) — **contadores e bool, nunca caminhos**: o caminho aparece só na linha do
doctor, que não é log. Só fatos (bool/int/string), nunca pass/fail reinterpretado; consumidor decide staleness
por `generated_epoch` (≥24h = velho). Sem jq o envelope não é escrito (skip honesto).
`bindings-snapshot.tsv` é `alvo\tcaminho\tsha256` por linha — base do aviso
`binding-resolution-drift`; contém caminhos locais e por isso vive em `$MAESTRO_HOME`
(mesma classe do `gate-policy.sh`), jamais no log. `config/vendor.sha256` (repo,
versionado) é o manifesto de integridade do vendor/ — divergência reprova o doctor.
`# classification: confidential` (paths locais no snapshot)

### 7. Brief de projeto — `~/.maestro/briefs/<slug>-<hash8>.md` (E8/S-801)

Estado situacional por projeto: a narrativa que poupa a varredura de cold start
("o que estava em curso, decisões abertas, próximo passo"). **Estado local de
trabalho, não memória** (ADR-007 intocado: conhecimento durável é do supermemory)
e **não log** (caminhos e narrativa jamais tocam o routing.jsonl). Chave =
basename saneado + djb2/8hex do caminho absoluto, derivada por
`maestro_brief_file()` (common.sh) — definição ÚNICA, usada por CLI e hook.

```
<!-- maestro-brief v1
ts: 2026-08-20T10:11:12-03:00
epoch: 1755690672
head: <sha40 | none>
wtree: <hash40 (S-701) | none>
session: <id | desconhecido>
-->
<narrativa markdown, escrita pela IA; cap de 16KB no write>
```

Escrito por `maestro brief --write|--auto` (bash puro, atômico tmp+mv). Freshness
em duas camadas: o **hook** compara só `head` + idade (<100ms); o **CLI** também
compara `wtree` — HEAD igual com working tree diferente é dito com todas as letras.
Carimbo ilegível → aviso de regravação, nunca crash. O doctor valida cabeçalho e
`epoch` de todo brief existente.
`# classification: confidential` (narrativa livre + paths locais)

### 8. Ledger de evidência — `~/.maestro/evidence/<slug>-<hash8>-<rótulo>` (E13/S-1301)

Recibo de execução amarrado a conteúdo (padrão gstack-evidence, MIT):

```
schema=maestro-evidence-v1
label=suite
ts=… / epoch=…
cmd_hash=<16 hex do sha256 do comando>
exit=<código>
wtree_before=<hash40|none> / wtree_after=<hash40|none>
```

VÁLIDA exige: wtree atual == wtree_after (conteúdo byte-idêntico ao provado), before ==
after (árvore parada durante a corrida), exit 0, idade < teto (`MAESTRO_EVIDENCE_MAX_AGE`,
default 86400s). Falha também é recibo — exit é dado. Estado local (classe do brief),
jamais no log; consumidores: `outcome --suite` (cita ou avisa), deslop, retro, doctor.
`# classification: confidential` (paths derivados + hashes locais)

---

## Regras de integridade

- Decision record é **por sessão**: novo `session_id` = nova decisão exigida (evita record velho liberando o gate para sempre).
- Escrita do JSONL é append atômico com `flock -n` (**não bloqueante** — contenção descarta a linha com aviso no stderr; review Opus); falha de escrita **nunca** bloqueia a operação (log é subproduto, não trilho).
- `maestro doctor` valida schema do YAML e dos records; CI do repo do plugin roda o mesmo check.
- Nenhum arquivo do Maestro sai da máquina (residência local, brief §7).

## Flags para o orchestrator

Nenhuma.
