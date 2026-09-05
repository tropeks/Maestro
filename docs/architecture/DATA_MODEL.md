---
covers:
  - config/routing-table.yaml
  - hooks/lib/common.sh
  - agents/**
reviewed: 1929a80
---
# DATA_MODEL.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.8 — 2026-09-05 (emendas E22/E23: §13 direção versionada, §9 ordem carimbada, §3 `delegation_proof`/`verifications`, §4 vocabulário completo, §8 `cmd_match`, §2 `verifications`/`commands`/`habits_ignore`, §10 `update_channel`)
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
`docs` (E16): lista inline dos DOCS CANÔNICOS do projeto. Cada doc declara no
frontmatter YAML `covers:` (globs git das áreas que governa) e opcionalmente
`reviewed: <sha>` (re-atesta frescor sem edição). Drift em `.maestro-docs.tsv`
(versionado, catraca).
`habits` (E9): lista inline de sensores ativos do habit hook (`[a, b]`; `[]` =
desligado no projeto; ausente = todos) — vale para o hook pós-edição E para
`maestro habits`.
`.maestro-habits.tsv` (E9/S-905, raiz do projeto, VERSIONADO): baseline da catraca
anti-slop — `smell\tcontagem` por linha, comentários com `#`. Só desce por
`maestro habits --baseline`; subir exige editar o arquivo (visível em review).

#### Emenda E23b (S-2302) — `verifications:` e `commands:`

O perfil passa a declarar QUE PROVA cada área do repo exige de quem a tocar:

```yaml
verifications:                 # área → o que ela exige de quem a tocar
  auth:
    paths: [src/auth/, migrations/]     # prefixos de caminho (git-relativos)
    labels: [suite, tenant-isolation]   # rótulos de recibo (§8) exigidos
  billing:
    paths: src/billing/                 # lista separada por espaço também vale
    labels: suite
commands:                      # comando canônico por rótulo (opcional)
  suite: bash tests/run-all.sh
```

Parser único em `hooks/lib/verifications.sh` (bash+awk; sem yq, sem Bun, sem jq —
a lib é sourceável por hook). Lista em flow (`[a, b]`) ou separada por espaço,
**uma linha só** (flow multi-linha e bloco `- item` são ignorados); comentário
` #…` removido; aspas saem só em par (item com aspa solta é descartado — o parser
não suporta valor com espaço). Nome de área `^[a-z0-9][a-z0-9._-]{0,31}$`, path
`^[A-Za-z0-9._/-]{1,80}$`, rótulo com a mesma regra do `--label` do evidence
(`^[a-z][a-z0-9-]{0,23}$`); item fora da regra é descartado em silêncio. **Área sem
path válido é ignorada** — prefixo nenhum casa nada, logo ela não governa área
alguma. Cabeçalho de área com nome torto zera o cursor: o `paths:` dele não é
creditado à área anterior. Qualquer chave na coluna 0 fecha o bloco. Config
malformada, lib ausente ou projeto sem `verifications:` degradam para "nada
exigido"; nunca derrubam quem chama. `commands.<rótulo>` é comparado como string e
hasheado (§8) — **jamais executado por esta lib**.

Áreas TOCADAS = `paths` que casam por **prefixo** com os caminhos do diff. Duas
pontas (`base`..`tip`) para a ordem (`--accept`); com `tip` vazio, working tree +
index + arquivos novos não-ignorados contra a base (default `merge-base main|master
HEAD`, nesta ordem). Sem git, sem base ou sem declaração → nada tocado.

#### Emenda E23d (S-2304) — `habits_ignore:` e o corpo de heredoc

```yaml
habits_ignore: [tests/fixtures/, vendor-golden/]   # E23d
```

`habits_ignore`: lista inline (`[a/, b/]`) ou separada por espaço de PREFIXOS de
caminho, relativos à raiz do projeto, que ficam fora do escopo `--all` de
`maestro habits` (e portanto do `--baseline`, que é o mesmo escopo — régua e
leitura da régua têm de ver o mesmo conjunto, senão a catraca mede uma coisa e
cobra outra). Default VAZIO. Entrada que não case `^[A-Za-z0-9._/-]{1,120}$` é
descartada em silêncio (perfil de projeto é dado do usuário, não contrato).
Caminho pedido explicitamente na linha de comando é sensoriado mesmo casando o
prefixo. Quantos arquivos saíram do escopo é DITO na saída (`habits_ignore: N
arquivo(s) fora do escopo (.maestro.yaml)`) — filtro que esconde em silêncio é
armadilha. Uso legítimo: árvore que existe para ser feia (payload de terceiro,
golden gerado); NÃO é lugar de calar smell de código vivo.

**Regra de heredoc do motor de sensores (E9 + E23d).** Em arquivo `sh|bash|zsh`
(decidido pela extensão), o corpo de heredoc é DADO. Abertura = `<<` ou `<<-`
seguido de delimitador `[A-Za-z_][A-Za-z0-9_]*` nu, entre aspas simples/duplas ou
escapado com `\`, precedido de espaço ou tab — o que exclui `<<<` (here-string) e
`a<<b` (shift). Fechamento = linha igual ao delimitador; com `<<-`, tabs à esquerda
são do idioma e não contam; a linha tolera aspas/parênteses finais, para o heredoc
escrito dentro de string citada (`run_cmd 'cat <<EOF … EOF'`) — sem essa válvula o
sensor ficaria cego do ponto de abertura até o fim do arquivo, que é pior que
fechar cedo demais. Linhas do corpo (e a do delimitador de fechamento) não
alimentam sensor nenhum e são descontadas de `oversized-function`; continuam
contando para `oversized-file`, que é tamanho de arquivo mesmo. A linha que ABRE é
código e é sensoriada normalmente. Em outras extensões nada muda.

Baseline do próprio Maestro depois do sensor novo: `deep-nesting 10 ·
oversized-file 12 · oversized-function 6 · skipped-test 1` — `dead-code`,
`lint-suppression` e `slop-comment` zeraram e saíram do arquivo, então qualquer
ocorrência nova dos três reprova contra baseline 0.
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

#### Emenda v1.6 (E14/S-1401) — orçamento declarado no record
`budget: {steps?, minutes?, cents?}` — caps INTEIROS ≥1 (float em custo é proibido),
AND-of-caps, todos opcionais. `steps` e `minutes` são medidos pelo gate (aviso ÚNICO por
cap, warn-only — orçamento é sinal de deriva, nunca trava); `cents` é declarativo (nenhum
hook enxerga custo real) e existe para o retro correlacionar custo × desfecho.

#### Emenda v1.7 (E17/S-1701..S-1702) — regência no record

Quatro campos novos, todos escritos por `maestro decide` (os três primeiros) ou por
`maestro conduct` (`flags[]` e a atualização do `approach:` de `brief`):

```json
{
  "depth": "deep",
  "profile": "piloto",
  "brief": "essencia: <o que é>; impacto: <o que representa>; approach: pendente",
  "flags": [
    {"sev": "high", "decisao": "...", "tradeoff": "...", "mitigacao": "..."}
  ]
}
```

| campo | tipo | validação |
|---|---|---|
| `depth` | enum | `standard \| deep \| day-zero`; opcional, default `standard` |
| `profile` | enum | `prototipo \| piloto \| produto`; **obrigatório SSE `depth == day-zero`**, rejeitado (erro de schema) se presente com outro `depth` |
| `brief` | string | contém 3 marcadores: `essencia: ...` (≤200 chars), `impacto: ...` (≤200 chars), `approach: ...` (≤200 chars, ou `"pendente"` no `decide` — só passa a exigir preenchido quando `outcome` é gravado; doctor emite WARN nomeando o record, nunca reprova) |
| `brief` (total) | — | soma dos 3 marcadores ≤700 chars; **obrigatório** (os 3 marcadores presentes) quando o workflow do record é `gate: plan` na routing table (`feature`, `refactor`) — recusado em decide-time, não em warn |
| `flags[].sev` | enum | `critical \| high \| medium \| low` |
| `flags[].decisao` \| `.tradeoff` \| `.mitigacao` | string | ≤120 chars cada (precedente `reason` ≤120, §3) |

Cross-rules validadas pelo doctor: `profile` sem `depth: day-zero` é erro de schema (o
inverso — `day-zero` sem `profile` — já é recusado no `decide`, decide-time, antes de
chegar ao doctor); `flags[]` vazio é válido (nenhuma flag levantada); severidade fora do
enum reprova nomeando o índice do array. `brief`/`flags` nunca aparecem no `~/.maestro/
logs/routing.jsonl` (§4 intocado) — vivem só no record, mesma fronteira do `wtree` (v1.4)
e do `reason`.

**Atualização explícita da política de conteúdo (o record continua `confidential` e a
proibição de texto do prompt do usuário PERMANECE — v1.4 não é revogada por esta
emenda).** `brief` e `flags` são a única exceção declarada e DELIMITADA a essa proibição:
não são colagem do prompt, são **síntese escrita pelo diretor** — a mesma relação que já
existe entre a sessão e o `reason` ≤120 (§3), agora com forma tripartida e caps maiores
porque o conteúdo é regência, não metadado de roteamento. O teto continua sendo o guardião
mecânico contra vazamento de contexto bruto: quem tenta colar um parágrafo de prompt no
`--brief` esbarra no corte de 200/700 chars antes de qualquer revisão humana. Truncamento
segue o precedente do `reason`: corta e avisa, nunca falha silenciosamente.
`# classification: confidential` — a exceção NÃO reclassifica o record; síntese do diretor
continua confidencial pelo mesmo motivo do resto do arquivo (revela estrutura de decisão
do projeto).

Persistência do dissenso (S-1708): `flags[]` sobrevive ao re-decide da mesma sessão — `maestro decide` faz merge do array existente no record novo (o decide preserva, não valida; o schema do doctor segue autoritativo). O log continua recebendo só `flags_n` (contagem): o conteúdo vive exclusivamente no record.

#### Emenda v1.8 (E23a/S-2301 + E23b/S-2302) — o que foi PROVADO no aceite

Dois campos novos, ambos opcionais, ambos enum fechado, ambos **só existem junto de
`outcome`** (validado pelo `record_schema_ok`, mesmo precedente de `outcome_ts`/
`suite`) e escritos exclusivamente por `maestro outcome accepted`:

| campo | valores | quando é gravado |
|---|---|---|
| `delegation_proof` | `started` \| `none` | record com `mode ∈ subagent\|multi`: `started` = havia ≥1 `delegation phase=started` da sessão no log; `none` = aceito com `--unproven`. Em `mode: direct` o campo é **omitido** (não há delegação a provar) |
| `verifications` | `cited` \| `missing` | o changeset toca área com verificação obrigatória (§2): `cited` = todos os rótulos exigidos tinham recibo VÁLIDA; `missing` = o aceite passou por `--unproven`. Changeset que não toca área declarada **não grava o campo** — ausência significa "nada era exigido", não "não verificado" |

`rework`/`reverted` não passam pelos gates e não gravam nenhum dos dois: só o
aceite afirma que a entrega serve. Os dois estão no `RECORD_FIELDS` do doctor desde
o mesmo commit — campo fora da lista reprovaria justamente o record de quem provou.


### 4. Log — `~/.maestro/logs/routing.jsonl` (append-only)

Uma linha por evento. Hooks emitem SOMENTE o vocabulário fechado via `log_event` do
`common.sh`; o CLI serializa com `JSON.stringify` — nunca texto livre concatenado
(proteção contra JSONL malformado, review Opus). **Vocabulário de eventos (19,
sincronizado com `common.sh::_maestro_event_valid` em 2026-09-05):** `decision` ·
`gate_pass` · `gate_warn` · `gate_block` · `override_manual` · `killswitch` ·
`session_end` · `habit_warn` · `consent_grant` · `consent_revoke` · `outcome` ·
`conduct` · `budget_warn` · `order_create` · `order_accept` · `upgrade` ·
`delegation` · `intent` · `verify`. Evento fora da lista é descartado com aviso no
stderr; incluir um novo exige emenda AQUI, em `common.sh` e em `src/cli.ts`
(`EVENTS`, senão o summary do `maestro log` joga evento real em `unknownEvent`).

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
`gate_mode`, `n` — a lista canônica de HOJE é a tabela ao fim deste §4); par que não
casa com o tipo é rejeitado com aviso, nunca reescrito.
Nenhuma chave aceita `/` — garantia estrutural contra vazamento de caminho. `reason` vive
só no decision record (§3), nunca no log.
Rotação: por tamanho (10MB) ou mensal, arquivo `routing-YYYY-MM.jsonl`.

**Emenda E15:** eventos `order_create`/`order_accept` (chave `n` = id); gate_block/
warn de zona congelada carrega `cmd=frozen_zone`; a política compilada ganha
`MAESTRO_GATE_ORDER_FROZEN` (7ª variável).

**Emenda E14:** evento `budget_warn` com chave `cap` (`steps|minutes`) — um por cap
por sessão, nunca por edição.

**Emenda E10:** eventos `consent_grant`/`consent_revoke`/`outcome` no vocabulário,
com chaves `scope` (`^[a-z][a-z-]{2,23}$`), `outcome` (enum) e `suite` (enum);
`gate_pass`/`gate_warn` de edição consentida carregam `scope`. Consentimentos vivem
em `$MAESTRO_HOME/consents/<escopo>` (`expires=<epoch>`, `granted`, `session`) —
estado local, jamais no log além dos eventos.

**Emenda E9:** evento `habit_warn` entra no vocabulário fechado, com a chave
`smell` (`^[a-z][a-z-]{2,23}$` — categoria, nunca caminho/linha) e `n`
(contagem de achados). Um evento por emissão do hook, nunca por achado.

**Emenda E17 (S-1702):** evento novo `conduct` — chaves `session_id`, `flags_n` (inteiro) e `approach` (yes|no). O conteúdo de brief/flags JAMAIS entra no log (só contagens e metadados, como todo o vocabulário).

**Emenda S-1811 (v1.11.1):** `session_end` passa a ser emitido (`hooks/session-end.sh`)
com `session_id`, `decided` (yes|no — havia decision record) e `settled` (yes|no — havia
`outcome`). Só presença e enum; nada do conteúdo do record entra no log.

**Emenda E19 (S-1901):** evento novo `upgrade` — chaves `from` e `to` (versão do
plugin, `^[0-9]+(\.[0-9]+){1,3}$`) e `via` (`auto|manual|rollback`). Um evento por
APLICAÇÃO (ff-only ou rollback), nunca por checagem: a checagem é estado local (§10), não
telemetria. SHA, URL do remoto e caminho do clone jamais entram no log.

**Emenda E23a (S-2301):** evento novo `delegation` com a chave nova `phase ∈
planned|started|received|accepted` — o funil que prova que a delegação aconteceu.
Reaproveita `session_id`, `agents` e `n`:

```json
{"ts":"...","event":"delegation","session_id":"abc123","phase":"planned","agents":["dev-pleno"]}
{"ts":"...","event":"delegation","phase":"started","session_id":"abc123","agents":["dev-pleno"]}
{"ts":"...","event":"delegation","phase":"received","session_id":"abc123","agents":["dev-pleno"]}
{"ts":"...","event":"delegation","phase":"accepted","session_id":"abc123","n":"7"}
```

| fase | emissor | quando |
|---|---|---|
| `planned` | `src/cli.ts` (`decide`) | record com `agents`, logo após o evento `decision` |
| `started` | `hooks/pre-agent.sh` | PreToolUse `Agent\|Task` — o disparo real |
| `received` | `hooks/subagent-stop.sh` | `SubagentStop` — o subagente voltou |
| `accepted` | `cmd_order --accept` | aceite do diretor (`n` = id da ordem) |

`agents` sai do `subagent_type`/`agent_type` do payload, sem o prefixo `maestro:` e
só se casar `^[a-z0-9-]+$` — o nome precisa ser o MESMO que o `--agents` do decide
grava, senão o funil não casaria `planned` com `started`. Fora do tipo, o evento sai
sem a chave: degradar o metadado é aceitável, inventar não. O `prompt`/`description`
do Task **nunca** é lido para log (ADR-008 integralmente preservado).

**Emenda E23c (S-2303):** o evento `upgrade` ganha a chave `channel`
(`^(stable|main)$`), emitida nas três vias (`via=auto|manual|rollback`). Continua um
evento por APLICAÇÃO; SHA e nome de tag jamais entram no log.

**Emenda E22 (S-2201):** evento novo `intent`, com `n` (versão da direção) e
`via=manual`, emitido só nas MUTAÇÕES (`intent --init`, `intent --bump`) — leitura
não loga. Nunca o título, o hash ou o caminho.

**Emenda E23b (S-2302):** evento novo `verify`, com `n` = número de verificações
obrigatórias FALTANTES no changeset. Nunca rótulo, área ou caminho.

#### Chaves tipadas — tabela canônica (24, sincronizada com `common.sh::_maestro_set_key_regex`)

Nenhuma regex admite `/`: garantia estrutural contra vazamento de caminho, reforçada
por uma checagem explícita de `*/*` no `log_event`.

| chave | regex | origem |
|---|---|---|
| `session_id` | `^[A-Za-z0-9_-]{1,64}$` | E2 |
| `workflow` | `^(fix\|feature\|refactor\|ship\|audit\|custom)$` | E2 |
| `mode` | `^(direct\|subagent\|multi)$` | E2 |
| `agents` | `^[a-z0-9-]+(,[a-z0-9-]+)*$` (sai como array JSON) | E2 |
| `tool` | `^[A-Za-z]{1,32}$` | E2 |
| `file_ext` | `^\.[A-Za-z0-9]{1,12}$` | E2 |
| `cmd` | `^[a-z0-9:_-]{1,48}$` | ADR-008 |
| `project` | `^[A-Za-z0-9._-]{1,48}$` | E2 (basename, nunca caminho) |
| `gate_mode` | `^(warn\|block)$` | E2 |
| `smell` | `^[a-z][a-z-]{2,23}$` | E9 |
| `scope` | `^[a-z][a-z-]{2,23}$` | E10 |
| `outcome` | `^(accepted\|rework\|reverted)$` | E10 |
| `suite` | `^(pass\|fail)$` | E10 |
| `cap` | `^(steps\|minutes)$` | E14 |
| `n` | `^[0-9]{1,9}$` | E9/E15/E22/E23 |
| `flags_n` | `^[0-9]{1,9}$` | E17 |
| `approach` | `^(yes\|no)$` | E17 |
| `from` | `^[0-9]+(\.[0-9]+){1,3}$` | E19 |
| `to` | `^[0-9]+(\.[0-9]+){1,3}$` | E19 |
| `via` | `^(auto\|manual\|rollback)$` | E19 (o `intent` usa `manual`) |
| `decided` | `^(yes\|no)$` | S-1811 |
| `settled` | `^(yes\|no)$` | S-1811 |
| `phase` | `^(planned\|started\|received\|accepted)$` | E23a |
| `channel` | `^(stable\|main)$` | E23c |

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
cmd_match=yes|no|free            # E23b — o comando rodado é o DECLARADO?
```

VÁLIDA exige: wtree atual == wtree_after (conteúdo byte-idêntico ao provado), before ==
after (árvore parada durante a corrida), exit 0, idade < teto (`MAESTRO_EVIDENCE_MAX_AGE`,
default 86400s). Falha também é recibo — exit é dado. Estado local (classe do brief),
jamais no log; consumidores: `outcome --suite` (cita ou avisa), `verify`, `order
--accept`, deslop, retro, doctor.

#### Emenda E23b (S-2302) — o recibo casa o comando declarado

`cmd_match`: `yes` = o comando executado (argv unido por espaço) é idêntico a
`commands.<rótulo>` do `.maestro.yaml` (§2); `no` = há declaração e o comando difere
(a gravação já avisa na hora); `free` = não há declaração. O schema **continua**
`maestro-evidence-v1`: a linha é opcional e o leitor é tolerante — recibo anterior ao
E23b é lido como `free` e segue valendo.

VÁLIDA passa a exigir também `cmd_match ≠ no` **e**, quando existe `commands.<rótulo>`
hoje, `cmd_hash` igual aos 16 hex de sha256 do comando declarado (`maestro_verif_hash`,
a MESMA fórmula do recibo — derivação em dois lugares viraria falso "VENCIDA"). O hash
sempre foi gravado; até o E23b nunca era comparado, e era por isso que
`maestro evidence --record -- true` valia como prova da suíte. Com declaração no
projeto, a linha de VENCIDA traz o comando exato para regravar.
`# classification: confidential` (paths derivados + hashes locais)

### 9. Work order — `<projeto>/.maestro/orders/NNN-slug.md` (E15, VERSIONADO)

Primeiro artefato do Maestro que vive NO repo do projeto de propósito (o segundo é a
direção, §13): a ordem atravessa clone e máquina via git. Carimbo
`<!-- maestro-order v1 -->` com id/ts/epoch/head/branch/frozen/budget_*/doc/
author_session; corpo markdown livre (objetivo, critérios, Ask-First) + contrato de
execução gerado. Estado NUNCA gravado — derivado: branch existe (git) · provada
(recibo §8 com wtree_after == árvore do tip do branch) · aceita (`accepted_at`
anexado pelo diretor via --accept, que exige provada). Log: `order_create`/
`order_accept` com `n` (id) — nunca título/caminho.

#### Emenda E22 (S-2202) — a ordem cita a direção que a autorizou

O carimbo ganha `intent_version:` e `intent_hash:`, gravados no `--create` quando há
direção CITÁVEL (§13); ausentes quando não há — ordem sem carimbo de direção NUNCA é
acusada de desatualizada (o que não foi prometido não pode estar quebrado). O aceite
ganha `accepted_intent: <versão vigente no aceite>`, anexado junto de `accepted_at`/
`accepted_session`/`accepted_tree`.

Derivações novas, também NÃO gravadas: *direção desatualizada* = versão atual do
INTENT > `intent_version` da ordem — muda o que `--status`/`--list` dizem e faz o
`--accept` exigir `--intent-reviewed`; *direção editada sem bump* = mesma versão com
`intent_hash` diferente — vira nota no `--status`, nunca alarme (o remédio é
`maestro intent --bump`).

Os leitores de cabeçalho (`_order_field` no CLI, awk das frozen zones no
session-start) passam a varrer **20 linhas** em vez de 14: o cabeçalho cresceu, a
garantia é a mesma — parar antes do corpo, onde `branch:`/`frozen:` escritos à mão
pelo humano não podem virar campo.

#### Emenda E23b (S-2302) — o aceite exige a verificação da área tocada

Além de `provada`, o `--accept` exige o conjunto de rótulos das áreas que o branch
tocou (`merge-base(main|master, branch)`..`branch`, §2): por rótulo, recibo com
`exit=0`, `wtree_after` == árvore do tip do branch e `cmd_match ≠ no`. Nenhum campo
novo no arquivo da ordem — o estado segue 100% derivado. Ordem que não toca área
declarada segue exatamente na regra anterior (o recibo `order-N` prova).
`# classification: public` (a ordem é conteúdo do repo do usuário)

### 10. Auto-update — `~/.maestro/config.yaml` · `update-state` · `update-snoozed` (E19)

Config **por máquina** (não por projeto — atualizar o plugin é decisão de quem opera o
box), flat, `chave: valor`, valor só `[A-Za-z0-9_.-]`, nada avaliado:
```yaml
update_check: true            # false desliga a checagem automática (o CLI manual segue)
auto_upgrade: true            # false = só avisa na injeção; aplicar é `maestro upgrade`
update_interval_hours: 24     # 1..720 — intervalo mínimo entre fetches
update_channel: stable        # E23c: stable (default) | main — stable é a tag que só a CI verde move
```
Env vence config: `MAESTRO_NO_UPDATE_CHECK=1`, `MAESTRO_AUTO_UPGRADE=0|1`,
`MAESTRO_UPDATE_INTERVAL` (segundos), `MAESTRO_UPDATE_TIMEOUT` (segundos, 5),
`MAESTRO_UPDATE_CHANNEL` (`stable|main`).

**Emenda E23c (S-2303) — `update_channel`.** Valor fora de `stable|main` (ou ausente)
resolve para `stable`, o canal seguro, e o doctor emite warn acionável. Escrita por
`maestro upgrade --set update_channel=stable|main`; `maestro upgrade --channel …`
sobrepõe só na chamada (não grava o arquivo). No canal `stable` o ref-candidato é
`refs/tags/stable` — a tag móvel que a CI reaponta depois de shellcheck + suíte verdes
numa tag `v*` — e o fetch traz `+refs/tags/stable*:refs/tags/stable*` e
`+refs/tags/v*:refs/tags/v*` (forçado porque a tag anda; curinga porque tag ausente não
pode virar "rede falhou"). Canal `main` = comportamento anterior, intacto.

`update-state` (reescrito atômico a cada checagem; é o que o doctor lê — silêncio na
injeção nunca é "atualizado"):
```
schema=maestro-update-state-v1
checked=<epoch>  fetched=<epoch do último fetch OK>  fetch=ok|failed|skipped
channel=stable|main                                   (E23c; ausente = estado pré-E23c, leia como main)
result=disabled|current|available|blocked|failed|no-stable
reason=<config|ahead|dirty|branch|in-progress|not-a-repo|no-remote|no-remote-ref|no-stable-tag|upgraded|rolled-back>
local=<versão>  remote=<versão>  behind=<n>  ahead=<n>  dirty=0|1  branch=<nome>
local_sha=<HEAD medido>  remote_sha=<commit do ref-candidato do canal: refs/tags/stable
ou origin/main>   (S-1810: se ambos batem na sessão seguinte e o intervalo não venceu,
`reason=fast-path` — dois rev-parse, sem medição; o fast path só reaproveita a medição
quando o `channel` gravado é o corrente — canal trocado é outro ref-candidato)
prev=<sha do HEAD anterior ao último upgrade — alvo do --rollback>
head=<sha que o upgrade produziu — o rollback recusa (`diverged`) se o HEAD já não for este>
upgraded=<epoch>
```
`result=no-stable` (E23c) = canal `stable` e o remoto ainda não tem a tag: **não é
falha** (o fetch pode ter ido bem) e **não é update**. Nada é aplicado; a injeção avisa
"auto-update parado" e o doctor diz `warn` explicando — e é o fail-safe certo: canal de aprovação
quebrado deixa a máquina parada na versão que ela já provou, nunca a empurra para uma
não provada.
Motivos que só a API devolve (nunca gravados como `result`): `raced` — o HEAD mudou entre
a medição e o merge (outra sessão aplicou primeiro; `prev` fica intacto), `locked` — seção
crítica ocupada, `diverged` — commit local depois do upgrade (rollback é manual), `merge` —
ff-only recusado.
`update-snoozed`: uma linha `<sha remoto> <until-epoch> <nível 1..3>` — cala só o aviso
daquela versão; versão nova no origin volta a avisar. `update.lock`: `flock -n` do fetch e
do merge (dois SessionStart simultâneos: o segundo pula, nunca espera); sem `flock`,
lock de diretório (`update.lock.d`, mkdir atômico, órfão >120s é removido) com o mesmo
contrato. Sem `timeout`, um watchdog em bash mata o fetch no mesmo teto — fetch sem
limite não existe.
`# classification: confidential` (SHA e versões locais — jamais no log além de `from`/`to`)

### 11. Barramento de telemetria — repo git privado + `~/.maestro/telemetry/` (E20)

Git como transporte (o mesmo trilho do upgrade, das work orders e dos docs): cada máquina
publica SÓ os seus `routing*.jsonl` num repo privado, em `logs/<host-id>/` — um escritor
por arquivo, nunca conflito de merge. Layout do repo:
```
logs/<host-id>/HOST                    # hostname legível (o id é sha256(hostname)[0:8])
logs/<host-id>/routing-current.jsonl   # o routing.jsonl vivo da máquina (espelho)
logs/<host-id>/routing-YYYY-MM.jsonl   # rotacionados (§4), espelhados como estão
```
Branch única `main`. Opt-in por máquina (`telemetry_remote: <url>` no config.yaml §10;
`telemetry_interval_hours`, default 24). Push no SessionEnd (único hook onde alguns
segundos de rede não atrasam ninguém): uma vez por intervalo, cada operação de git com
teto de tempo, sob lock não bloqueante, falha silenciosa e registrada em
`~/.maestro/telemetry-state` (`checked`, `pushed`, `result` ∈
`disabled|pushed|nochange|skipped|failed`, `reason`, `host`, `files`). Push que falhou
deixa o commit local; a rodada seguinte publica o que ficou. `maestro retro --all` puxa
o clone e agrega a união, excluindo o diretório do próprio host (os eventos locais já
estão em `$MAESTRO_LOG_DIR`; contar duas vezes é mentira).
`# classification: confidential` (metadados de roteamento, repo privado; hostnames)

### 12. Gate pendente para o runtime — `~/.maestro/herdr/gates/<pane>` (E21)

Escrito pelo Stop hook só dentro do herdr; apagado pelo UserPromptSubmit (resposta do
humano) ou pelo próprio Stop quando o gate já não está pendente. Um arquivo por pane
(`w1:p1` → `w1_p1`), chave=valor:
```
gate=plan|ship
session=<session_id>
project=<basename do projeto>
ts=<epoch>
message=<pergunta regida em uma linha — só a essência do brief; reason nunca>
```
Consumidor: o forwarder (Legatus vNext) prefere este arquivo ao scrape da tela do pane.
Estado local; nunca sai da máquina pelo Maestro (o forwarder envia a `message` ao
Telegram do próprio Capitão — decisão dele, fora deste repo).
`# classification: confidential` (essência do brief)

### 13. Direção do projeto — `<projeto>/.maestro/INTENT.md` (E22, VERSIONADO)

Segundo artefato que vive NO repo do projeto de propósito (o primeiro é a work order,
§9): a direção atravessa clone e máquina via git, e é ela que as ordens citam.

```
<!-- maestro-intent v1
version: 3                    # inteiro ≥1; sobe SÓ por `maestro intent --bump`
ts: 2026-09-05T10:00:00-03:00
head: <sha40|none>            # HEAD no momento do carimbo
author_session: <sid|desconhecido>
hash: <8 hex>                 # do corpo NO carimbo — é o que detecta "mudou de verdade"
-->
# Direção — <nome do projeto>

## Problema · ## Público · ## Resultado · ## Prioridades · ## Limites · ## Fora de escopo
```

Seis seções obrigatórias; a ordem delas DENTRO do arquivo é livre. **Seção com título
e sem nenhuma linha de texto conta como AUSENTE** — título vazio não é direção (por
isso o template do `--init` põe as instruções ANTES da primeira seção: texto dentro de
uma seção a tornaria "preenchida"). `## ` é fronteira de seção; `### ` conta como
texto.

`intent_hash` = 8 hex do sha256 do corpo SEM o carimbo (`sed '1,/^-->$/d'`), a mesma
fórmula no CLI e em quem consome: carimbar não é mudar conteúdo. `--bump` recusa quando
o hash do corpo é igual ao `hash:` do carimbo — **a versão é o número que as ordens
citam, não um contador de saves** — e copia o corpo byte a byte, trocando só o carimbo.
Conteúdo editado sem bump é dito no `--show`/`--status` da ordem, nunca corrigido
sozinho.

Direção CITÁVEL = carimbo legível + seis seções não-vazias; incompleta é lida e
reportada, nunca carimbada numa ordem. O session-start lê só `version:` com awk nas 8
primeiras linhas (nenhum sha256 no hot path); o CLI lê o carimbo com awk até a linha
`-->` (teto de 12 linhas). Escrita atômica (`> tmp && mv -f`). Log: evento `intent` com
`n` (versão) e `via=manual`, só nas mutações — nunca título, hash ou caminho.
`# classification: public` (a direção é conteúdo do repo do usuário)


---

## Regras de integridade

- Decision record é **por sessão**: novo `session_id` = nova decisão exigida (evita record velho liberando o gate para sempre).
- Escrita do JSONL é append atômico com `flock -n` (**não bloqueante** — contenção descarta a linha com aviso no stderr; review Opus); falha de escrita **nunca** bloqueia a operação (log é subproduto, não trilho).
- `maestro doctor` valida schema do YAML e dos records; CI do repo do plugin roda o mesmo check.
- Nenhum arquivo do Maestro sai da máquina (residência local, brief §7) — **exceção única
  (E20, opt-in):** os `routing*.jsonl`, que são metadados por construção (chaves tipadas,
  vocabulário fechado, nenhuma chave aceita `/`), podem ir para o repo privado de
  telemetria §11. Records, briefs, evidência, consentimentos e work orders continuam locais.

## Flags para o orchestrator

Nenhuma.
