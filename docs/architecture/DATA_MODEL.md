---
covers:
  - config/routing-table.yaml
  - hooks/lib/common.sh
  - agents/**
reviewed: b13eed1
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


#### Emenda E25 (S-2502) — `preamble:` (tamanho do bloco injetado)

```yaml
preamble: lean        # full (default) | standard | lean
```

Escolhe QUANTO do preâmbulo do SessionStart este projeto recebe. `full` é o default e a
**ausência da chave produz saída byte a byte idêntica** à de antes da emenda — nenhum
projeto existente muda de comportamento. `standard` omite a seção `## Rotas (intenção →
workflow) e workflows`; `lean` omite também `## Heurísticas de execução` e `## Roster`.
Valor fora do enum é tratado como `full` e DITO na injeção (perfil de projeto é dado do
usuário, mas silêncio aqui seria esconder que o preâmbulo mudou de tamanho).

É uma troca declarada pelo dono do projeto: `lean` compra contexto vendendo qualidade de
roteamento — o modelo perde o catálogo de rotas e as heurísticas de tiering. Uso legítimo:
repo onde o jeito de trabalhar está assentado e o diretor é sempre o mesmo. O que sai
NUNCA sai calado: o cabeçalho (que não trunca) nomeia o tier e o que ficou de fora, com o
ponteiro para `config/routing-table.yaml` e `agents/`. Medida de referência (2026-09-09,
repo do Maestro): `full` 7165B · `## Rotas` 1038B · `## Heurísticas` 1891B · `## Roster`
254B.

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

#### Emenda v1.10 (issue #6, 2026-09-12) — `.maestro/**` sai do fingerprint
`bin/maestro-wtree` passa a montar o index temporário com `git add -A -- ':(exclude).maestro/**'`
em vez de `git add -A` cru (mesma forma de pathspec de exclusão já usada em
`bin/maestro:1699` para o drift de docs canônicos). Causa: projeto que segue E15
(work order versionada) e E22 (`INTENT.md` versionado) **rastreia** `.maestro/`
— não é `.gitignore` — então o `git add -A` sem exclusão enxergava o próprio
carimbo que `maestro order --accept` grava em `.maestro/orders/NNN.md`
(`accepted_at`/`accepted_session`/`accepted_tree`). O ciclo era circular:
aceitar a ordem escrevia no disco, o fingerprint ao vivo (§8) divergia do
`wtree_after` congelado no recibo, e a leitura seguinte do ledger relatava
"conteúdo mudou desde a prova" — **o aceite invalidava o recibo que o
autorizou**. Caso real: NetForge, ordem 016 (2026-09-12), suíte de ~8 minutos
re-rodada só para provar código byte-idêntico.

`.maestro/` não entra no que a suíte prova — é estado de governança. A
exclusão vale para TODO consumidor de `bin/maestro-wtree` (este campo `wtree`
do decision record e o `wtree_before`/`wtree_after` do ledger de evidência,
§8): mudança dentro de `.maestro/` (nova ordem, carimbo de aceite, edição do
INTENT) nunca move o fingerprint; as propriedades 1–3 do cabeçalho de
`bin/maestro-wtree` continuam valendo integralmente para todo o resto da
árvore. Teste: `tests/cli/test-order.sh` (issue #6) — reproduz o caso do
NetForge (recibo verde, `--accept` depois, leitura direta do ledger exige
`VÁLIDA`), provado FALHANDO contra o `bin/maestro-wtree` anterior a esta
emenda e PASSANDO com a exclusão aplicada.

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



#### Emenda v1.9 (E25/S-2501) — o descarte também é desfecho

O enum de `outcome` passa a `accepted | rework | reverted | killed`, e ganha um campo
acompanhante:

| campo | tipo | validação |
|---|---|---|
| `kill_reason` | string | ≤120 chars (mesmo teto do `reason`, §3), não-vazia; **existe SSE `outcome == "killed"`** — nos dois sentidos: sem ele o `killed` é erro de schema, e com qualquer outro desfecho ele é campo extra |

`killed` significa *decidimos não construir isto*. Os três valores anteriores pressupõem
entrega — por isso `killed` **não passa** pelo gate de prova de delegação (E23a) nem pelo
de verificações por área (E23b) e **não grava** `delegation_proof` nem `verifications`: os
dois gates existem porque o ACEITE afirma que a entrega serve, e aqui não há entrega.
`--suite` é recusado pelo mesmo motivo (não se roda suíte do que não se escreveu).

Desfecho é last-wins, então a remoção é parte do contrato: gravar `accepted`/`rework`/
`reverted` sobre um record morto **apaga** `kill_reason`. Sem isso, o record de quem
mudou de ideia e construiu ficaria com um campo órfão e o doctor reprovaria justamente
quem fez tudo certo — o mesmo erro que a correção de 2026-08-24 fechou para `outcome`.

`kill_reason` vive SÓ no record, como `wtree` (v1.4) e `brief`/`flags` (v1.7): o log
recebe `outcome=killed` e nada mais. O §4 **não ganha campo**, mas ganha o valor: o enum
da chave `outcome` na tabela de regex passa a incluir `killed`, e essa tabela é a fonte
declarada do `_maestro_set_key_regex` — restaurá-la sem o valor novo devolveria o
`killed` ao descarte silencioso do `log_event`, e o sinal de descarte do `retro`, que lê
o log, zeraria sem avisar ninguém. O porquê é síntese do diretor, não
colagem do prompt, e o teto de 120 chars é o guardião mecânico contra vazar contexto
bruto. `# classification: confidential` — inalterado.

Onde o kill SOBREVIVE à sessão (o record expira em 4h) é a seção `## Fora de escopo` do
`.maestro/INTENT.md` (§13). O comando **aponta** para lá e não escreve: o INTENT é
versionado e o hash do corpo é contrato — escrita automática viraria `--bump` em contador
de saves, exatamente o que o E22 proibiu.

### 4. Log — `~/.maestro/logs/routing.jsonl` (append-only)

Uma linha por evento. Hooks emitem SOMENTE o vocabulário fechado via `log_event` do
`common.sh`; o CLI serializa com `JSON.stringify` — nunca texto livre concatenado
(proteção contra JSONL malformado, review Opus). **Vocabulário de eventos (20,
sincronizado com `common.sh::_maestro_event_valid` em 2026-09-19):** `decision` ·
`gate_pass` · `gate_warn` · `gate_block` · `override_manual` · `killswitch` ·
`session_end` · `habit_warn` · `consent_grant` · `consent_revoke` · `outcome` ·
`conduct` · `budget_warn` · `order_create` · `order_accept` · `upgrade` ·
`delegation` · `intent` · `verify` · `route_fix`. Evento fora da lista é descartado com aviso no
stderr; incluir um novo exige emenda AQUI, em `common.sh` e em `src/cli.ts`
(`EVENTS`, senão o summary do `maestro log` joga evento real em `unknownEvent`).

```json
{"ts":"...","event":"decision","session_id":"abc123","workflow":"fix","mode":"subagent","agents":["golang-pro"],"project":"remedix"}
{"ts":"...","event":"gate_block","session_id":"def456","tool":"Edit","file_ext":".go"}
{"ts":"...","event":"override_manual","session_id":"def456","cmd":"review"}
{"ts":"...","event":"route_fix","session_id":"def456","axis":"mode"}
```
`# classification: confidential` — só metadados; `file_ext` sim, caminho completo NÃO (pode conter nome de cliente).

**Emenda (ordem 030) — `route_fix`: o sensor do bullet invérificável do INTENT v3.**
O Resultado do INTENT v3 promete "zero correção manual do modo/modelo escolhido",
mas não existia sensor — a correção em linguagem natural ("não, faz direto", "usa
haiku nessa") não deixava rastro em nenhum dos eventos existentes (o
`override_manual` só vê prompt que começa com `/`). `route_fix` fecha essa lacuna,
em `hooks/user-prompt-submit.sh` (o único hook que vê o prompt), estendendo o MESMO
programa jq que já isola `cmd` — o prompt continua sem sair dali.

Duas âncoras deliberadas contra falso positivo (**"um sensor que conta demais é
pior que nenhum"**, por isso o viés aqui é para NÃO emitir):
1. **Âncora mecânica** — só conta se JÁ existe um decision record válido
   (`maestro_record_valid`) NESTA sessão. Sem record, nenhum prompt é correção.
2. **Vocabulário FECHADO, nunca classificador** (ADR-002, INTENT "Fora de
   escopo" — nada de heurística de texto livre): o jq testa só pertencimento a
   um dos alfabetos JÁ existentes no log_event — `mode` (`direct|subagent|multi`),
   `workflow` (os 8 valores de `_maestro_set_key_regex`) e os nomes de
   `agents/*.md`. O GATILHO é CONTRADIÇÃO: o valor citado no prompt precisa
   DIFERIR do gravado no record — mencionar o mesmo valor que já está decidido
   não emite nada. Token ambíguo (≥2 valores distintos do mesmo alfabeto no
   mesmo prompt) também não emite — "emita o que tiver certeza, ou não emita".

Chave nova: `axis` (`^(mode|agents|workflow)$`) — NUNCA a frase, NUNCA um trecho,
NUNCA hash que permita reconstruir o prompt. Modelo (`haiku|sonnet|opus`), citado
no prompt mas sem campo próprio no decision record (§3), é cruzado contra o
`model:` do frontmatter de cada `agents/*.md` já decidido e reportado sob o MESMO
eixo `agents` — é dali que o modelo realmente vem; sem correspondência conhecida
(roster ilegível), o sensor fica mudo em vez de inventar contradição.
`maestro retro` ganha a linha "-- correção de rota" ao lado de "-- decisões" /
override, para o bullet passar a ter número na mesma tabela que já se lê.

**Débito declarado, no mesmo padrão da emenda v1.19 (ordem 021):** o `EVENTS` de
`src/cli.ts` (o `maestro log --summary` do CLI Bun) ainda NÃO lista `route_fix` —
essa metade fica fora deste changeset (fora do escopo dado à ordem 030, e
`src/` não é território de bash). Efeito enquanto durar: `route_fix` conta como
`unknownEvent` nesse summary específico do CLI; o `hooks/lib/common.sh` (fonte de
verdade do hook) e o `maestro retro` (bash, lote desta ordem) já reconhecem o
evento por completo.

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

#### Chaves tipadas — tabela canônica (25, sincronizada com `common.sh::_maestro_set_key_regex`)

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
| `outcome` | `^(accepted\|rework\|reverted\|killed)$` | E10 · `killed` E25 |
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
| `axis` | `^(mode\|agents\|workflow)$` | ordem 030 |

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

**Emenda 2026-09-08 (worktree):** a chave é do PROJETO, não do diretório. Uma git
worktree (`.git` é ARQUIVO, não diretório) resolve para o repositório principal via
`git rev-parse --git-common-dir`, de modo que brief, recibo de evidência e estado de
ordem são os MESMOS dos dois lados. Sem isso, ordem provada dentro de uma worktree
ficava invisível do repo principal e `order --status` respondia `em_execucao / prova
NENHUMA` para uma ordem já aceita — o relatório mudava conforme o diretório corrente.
Submódulo também tem `.git` como arquivo, mas seu `--git-common-dir` NÃO termina em
`/.git`, então continua sendo projeto próprio. Só a worktree paga o fork extra; o
caso comum mantém o NFR de <100ms do session-start.

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
load1m_x100=<int> / ncpu=<int>   # issue #11 (ordem 005) — carga no momento do record
inconclusive=<int>               # issue #11 — nº de asserções INCONCLUSIVO sob carga
probe_ms=<int>                   # ordem 016 PR1 — sonda de baseline (capacidade, não carga)
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

#### Emenda (issue #11, ordem 005) — o recibo passa a guardar a CARGA

Antes desta emenda, o recibo provava conteúdo + exit + comando, mas nada sobre a
condição da máquina durante a corrida — e `ARCHITECTURE.md §NFRs` exige load de 1min
ABSOLUTO ≤ 2,0 (mesmo limiar de `tests/lib/latency.sh`) para uma medição de latência
valer. Caso real: recibo gravado a load 12,12 foi lido como `VÁLIDA — exit 0, conteúdo
byte-idêntico ao provado`, sem ressalva; o diretor recusou, o CLI não tinha como saber.

Três campos novos, **todos aditivos, no FIM do arquivo** (para `cmd_match` não sair da
janela do leitor — ver armadilha da janela abaixo):
- `load1m_x100` / `ncpu`: carga de 1min ×100 (inteiro — `CLAUDE.md` proíbe float em
  métrica; mesma técnica de `tests/lib/latency.sh`: remove o ponto do formato de 2 casas
  que `/proc/loadavg` sempre usa no Linux) e nº de CPUs, lidos no momento em que o
  `--record` grava o recibo (não sourceado de `tests/lib/latency.sh`: `bin/` não depende
  de `tests/`; o limiar de 200 — load 2,00 — é duplicado com comentário de proveniência).
- `inconclusive`: quantas linhas da saída do comando citam a palavra `inconclusivo`
  (case-insensitive) — o vocabulário do próprio protocolo compartilhado de medição de
  latência (`MAESTRO_LATENCY_VERDICT=inconclusivo`, `tests/lib/latency.sh`, emitido por
  `tests/hooks/test-gate.sh` e `test-guarda-destrutiva.sh` como `INCONCLUSIVO sob carga`).
  A saída do comando roda por um `tee` para isto ser contável sem acoplar o ledger ao
  FORMATO exato da linha de um teste específico. Resolve o 3º item da issue #11: "exit 0
  limpo" e "exit 0 com N medições dispensadas por carga" eram indistinguíveis no ledger.

A leitura qualifica `VÁLIDA` em vez de tratar carga como binário: `VÁLIDA (load 1.8)`
quando dentro do limiar; `VÁLIDA, mas fora do limiar de medição (load 12.1)` quando não
— nos dois casos ainda é `VÁLIDA` (conteúdo/exit/comando continuam provados; só a
medição de LATÊNCIA embutida na suíte é que fica suspeita); e um sufixo `N medição(ões)
INCONCLUSIVA(S) sob carga durante a corrida` quando `inconclusive > 0`, em VÁLIDA e em
VENCIDA. Recibo anterior a esta emenda não tem os três campos: qualificação fica muda
(não dá pra qualificar carga que não foi medida) — mesmo padrão de tolerância do E23b.

**Decisão de versionamento (item 4 da ordem 005, por MEDIÇÃO, não preferência):**
campo aditivo e opcional não merece schema novo SE o leitor atual (pré-emenda) ignorar
campo desconhecido. Provado por experimento: um recibo com os 3 campos novos, lido pelo
leitor de `bin/maestro` do `main` em `3b300bc` (SEM esta emenda), retornou
`VÁLIDA — exit 0 há 0min, conteúdo byte-idêntico ao provado` — idêntico ao que o leitor
velho já dizia sem os campos, porque o awk do leitor casa por NOME de campo (`/^epoch=/`
etc.) e ignora em silêncio qualquer linha que não bata em nenhum padrão. Decisão:
**continua `maestro-evidence-v1`**, sem migração. Regressão automatizada (a mesma lógica
do leitor pré-005, congelada como referência) em `tests/cli/test-order-issue11.sh`.

**Armadilha da janela verificada e fechada nesta emenda:** o leitor fazia
`awk -F= 'NR>12 { exit }` — a janela já vinha com headroom de 3 linhas (9 campos
pré-005 + 3 de folga), e os 3 campos novos, por serem exatamente 3, ocupam esse
headroom TODO: chegam a 12 linhas, zero folga sobrando. Alargada para `NR>20` no mesmo
patch (`docs/patches/005-issue11-recibo-com-carga.patch`) — mesmo número já usado alhures
no repo para "cabeçalho com headroom" (`_order_field`/`_maestro_order_stamp_ok`, ordem
004) — com comentário no código explicando a conta, para o PRÓXIMO campo não cair fora
da janela em silêncio outra vez.

#### Emenda (issue #6, 2026-09-12) — `wtree atual`/`wtree_after` não veem `.maestro/`
`bin/maestro-wtree` (§3 emenda v1.10) exclui `.maestro/**` do fingerprint em
ambas as pontas desta comparação — gravação (`wtree_before`/`wtree_after`) e
leitura (`wtree atual`). Bookkeeping do próprio Maestro sob `.maestro/`
(carimbo de `order --accept`, edição de ordem/INTENT) deixa de contar como
"conteúdo mudou desde a prova". Não foi preciso um campo novo nem uma
equivalência extra contra `accepted_tree` (§9): a árvore que `order --accept`
grava em `accepted_tree` já É o `wtree_after` do recibo que autorizou o
aceite (`_order_proof_tree`, `bin/maestro`), e com `.maestro/` fora do
fingerprint essa igualdade sobrevive ao próprio carimbo — decidido "não
coube" na ordem 003 (issue #6), com prova em `tests/cli/test-order.sh`.
`# classification: confidential` (paths derivados + hashes locais)

#### Emenda v1.17 (ordem 016 PR1, 2026-09-17) — `probe_ms`: sonda de baseline

Causa: carga (`load1m_x100`, emenda anterior) mede CONTENÇÃO, não CAPACIDADE — duas
máquinas na mesma carga podem ter pisos de execução muito diferentes. Medido em
2026-09-16, mesma máquina e mesma janela, com o teto de latência forçado alto para não
mascarar: `gate_pass` deu min 92ms antes do E24 (`4051dc4`) e 79ms depois (`c73ad3d`) —
idêntico, sem regressão de código. O modelo de custo documentado (`tests/lib/latency.sh`)
diz ~12ms para o caminho que passa; nesta forge o MÍNIMO observado é 79ms. Conclusão:
esta forge é ~6x mais lenta por invocação que o runner da CI de referência, e nada no
recibo dizia isso.

Campo novo, **aditivo, no FIM** (mesma regra das emendas anteriores — `cmd_match` nunca
sai da janela do leitor): `probe_ms=<int>`, a MEDIANA de N invocações NO-OP do hook
`hooks/pre-tool-gate.sh` pelo caminho do kill-switch (`MAESTRO_OFF=1`), medidas no INÍCIO
da corrida — o piso já documentado no modelo de custo ("~3ms bash+source de
`lib/common.sh`, custo do kill-switch sozinho"): mesmo binário, mesmo interpretador,
mesmo `source`, zero trabalho além disso. `lib/cmd-evidence.sh` (`_ev_cmd_measure_probe`)
mede; `lib/core-evidence.sh` (`_ev_write`/`_ev_read_vars`) é o dono do formato, como
sempre. Schema **continua** `maestro-evidence-v1`, sem migração — recibo anterior a esta
emenda não tem a linha, e o leitor (velho ou novo) ignora em silêncio o que não casa por
nome, mesmo tratamento da emenda anterior (`load1m_x100`/`ncpu`/`inconclusive`).

**Escopo desta emenda é só medir e gravar — nenhum enforcement muda.** O teto de
latência (`maestro_latency_report`, `tests/lib/latency.sh`) continua decidido exatamente
como antes desta emenda, com o `× FOLGA` binário e o portão de carga; `probe_ms` também
passa a ser impresso ao lado de min/mediana/max/teto/load no relatório de latência dos
testes de hook (mesmo arquivo). A hipótese de que a RAZÃO medição÷sonda cancela carga e
isola capacidade — o que justificaria um teto calibrado por sonda no lugar da folga
binária — é do PR 2 desta ordem, condicionada à CI publicar `SONDA_REF`; esta emenda não
a assume.

### 9. Work order — `<projeto>/.maestro/orders/NNN-slug.md` (E15, VERSIONADO)

Primeiro artefato do Maestro que vive NO repo do projeto de propósito (o segundo é a
direção, §13): a ordem atravessa clone e máquina via git. Carimbo
`<!-- maestro-order v1 -->` com id/ts/epoch/head/branch/frozen/budget_*/doc/
author_session; corpo markdown livre (objetivo, critérios, Ask-First) + contrato de
execução gerado. Estado NUNCA gravado — derivado: branch existe (git) · provada
(recibo §8 com wtree_after == árvore do tip do branch; branch AUSENTE usa a
árvore que o recibo CONGELOU, sem tip pra comparar — emenda v1.16) · aceita
(`accepted_at` anexado pelo diretor via --accept, que exige provada) ·
absorvida (`absorbed_by` anexado via `--accept --absorbed-by`, que exige a
ABSORVENTE já provada/aceita — emenda v1.11) · adiada (`deferred_by` escrito
à mão no cabeçalho — SUSPENSA, distinta de absorvida: volta, e continua
visível — emenda v1.14). Log:
`order_create`/`order_accept` com `n` (id) — nunca título/caminho (absorção
reaproveita `order_accept`; §4 não ganha vocábulo novo; adiar não passa por
`log_event`).

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

#### Emenda v1.11 (issue #12, 2026-09-14) — `absorbed_by`/`absorbed_tree` e o terceiro estado terminal

Causa: `_order_status` tinha UM caminho terminal, `accepted_at`, e ele exige
prova no tip do branch DAQUELA ordem. Ordem cujo trabalho foi absorvido por
outra fica sem branch nem recibo próprios — `aberta` (ou `em_execucao`) para
sempre, cobrando um aceite que o modelo torna impossível. Dois casos reais,
duas portas: NetForge 018 absorvida DENTRO da 016 (absorção por outra ordem);
Maestro 001/002 absorvidas pelo MAIN via PR (#4, #5, #10), hoje carimbadas à
mão (`absorbed_by: main` em `d394a47`) só como documentação — o CLI ignorava
o campo.

`maestro order --accept N --absorbed-by <M|main>` grava, no CABEÇALHO da
ordem N (dentro das 20 linhas que `_order_field` lê — mesma janela e mesma
garantia contra `absorbed_by:` escrito à mão no corpo virar campo por
acidente; ao contrário de `accepted_at`/`accepted_tree`, que são anexados ao
FINAL do arquivo e lidos por grep sem janela):

```
absorbed_by: <id numérico de 1-3 dígitos | "main">
absorbed_tree: <árvore (sha) que a ABSORVENTE provou>
absorbed_at: <timestamp>
absorbed_session: <session_id de quem carimbou>
```

**Condição de recusa (sem brecha):** a absorção só grava se a ABSORVENTE já
está, ela mesma, provada no momento do carimbo — nunca a ordem que está sendo
absorvida.
- `--absorbed-by M`: a ordem M precisa derivar `provada` ou `aceita` (mesma
  leitura de `_order_status`); qualquer outro estado — inclusive `aberta` ou
  `em_execucao` — recusa com `die validation`. Autoabsorção (`M == N`) e M
  inexistente também recusam.
- `--absorbed-by main`: exige recibo (`maestro evidence --record --label
  main`) com `exit=0` **e** `wtree_after` == árvore do tip ATUAL de `main` —
  a mesma equação de frescor que já protege `order-N`/`accepted_tree` (§8).
  `main` que andou depois do recibo (ou que nunca teve recibo) recusa; não há
  como reaproveitar um recibo velho, então "absorver pelo main" nunca vira
  atalho para pular a suíte.
- Ordem já `aceita` não aceita `--absorbed-by` por cima; ordem já `absorvida`
  é no-op idempotente (repete a mensagem, não regrava).

**Estado derivado `absorvida`**, terceiro caminho terminal, DISTINTO de
`aceita`: quem audita precisa ver a diferença entre a ordem que provou o
PRÓPRIO trabalho (`aceita`) e a ordem que foi provada JUNTO de outra
(`absorvida`) — a leitura de `--status`/`--list` não funde as duas. `absorbed_by`
entra no MESMO teste de exclusão que `accepted_at` nos dois laços de
`hooks/session-start.sh` (frozen zones e contagem de `ordens: N pendente(s)`):
ordem absorvida não tem trabalho próprio em andamento e não deve continuar
congelando caminho nem gerando cutucão de aceite pendente.

Log: reaproveita `order_accept` (chave `n`) e `delegation phase=accepted` —
nenhum vocábulo novo em §4; quem audita distingue aceita de absorvida pelo
campo gravado no ARQUIVO da ordem, não pelo tipo de evento no ledger.
`# classification: public` (a ordem é conteúdo do repo do usuário)

#### Emenda v1.14 (ordem 013) — `deferred_by` e o estado SUSPENSO (distinto de absorvida)

Causa: `_order_status` tinha um caminho terminal (`absorbed_by`, v1.11) mas
nenhum caminho SUSPENSO. Ordem cujo trabalho o Capitão adiou POR DECISÃO
ficava presa em `aberta`/`em_execucao` para sempre e o recibo (`--status`) lia
o veredito genérico de `maestro evidence`, que VENCE por idade (o TTL do
recibo, `MAESTRO_EVIDENCE_MAX_AGE`) e por mudança de árvore (o branch andando
sem prova nova) — os dois sinais existem para trabalho que ANDA; adiado não
anda, e a leitura acusava `VENCIDA` todo dia sobre um trabalho que ninguém
abandonou. Caso real: ordem 004 do projeto Vitali, `deferred_by:` escrito à
mão no cabeçalho pelo gerente de lá porque o modelo não tinha a palavra — e
nada lia o campo.

**Distinção que decide o desenho:** `absorbed_by` é TERMINAL (o trabalho foi
provado em outro lugar; a ordem nunca mais anda). `deferred_by` é SUSPENSO — o
trabalho foi adiado por decisão e VOLTA; retomar é remover o campo e seguir o
fluxo normal. Confundir os dois faria a ordem adiada sumir da fila (o
comportamento de `absorvida`), o oposto do desejado: ela continua VISÍVEL em
`--list`/`--status`, só sem cobrar aceite nem acusar prova vencida enquanto o
campo existir. Não compartilha mecanismo com o pedido da issue #20 (estado
terminal para ordem RECUSADA, decidido NÃO fazer — nunca volta) pelo mesmo
motivo.

Campo novo no CABEÇALHO da ordem (dentro das 20 linhas que `_order_field` lê —
mesma janela e mesma garantia contra corpo escrito à mão virar campo por
acidente), escrito à mão pelo humano (não há flag de CLI que o grave; ao
contrário de `absorbed_by`, adiar não é um veredito mecânico sobre uma prova):

```
deferred_by: <quem decidiu adiar>
```

`deferred_by` **exige quem adiou**, pelo mesmo motivo que `killed` exige
`kill_reason` (§3, emenda v1.9) e `absorbed_by` exige a absorvente provada:
adiar é desfecho, e desfecho sem autor não se audita. A exigência é a mesma
técnica de `absorbed_by`: campo AUSENTE ou vazio não ativa nada — `_order_status`
só deriva `adiada` quando `_order_field` devolve um valor não-vazio; ordem SEM
o campo segue vencendo exatamente como antes desta emenda.

**Estado derivado `adiada`**, verificado logo depois de `absorbed_by` (antes
de `absorbed_by` só porque `absorbed_by` já é terminal e ganha — a ordem
nunca tem os dois; a leitura testa `accepted_at` → `absorbed_by` → `deferred_by`
→ branch/recibo, nessa ordem). A leitura de `--status` NUNCA diz `VENCIDA`
para uma ordem adiada — diz `ADIADA por <deferred_by> — prova congelada em
<árvore>`, onde `<árvore>` é o `wtree_after` do recibo JÁ gravado para o
rótulo da ordem (`_order_deferred_tree`, núcleo puro em
`lib/core-order-state.sh`), nunca comparado ao tip ATUAL do branch — essa
comparação é exatamente o que "venceria" o recibo por mudança de árvore, e
uma ordem suspensa não tem tip para comparar (retomar é tirar o campo antes
de o branch andar de novo). Sem recibo gravado ainda, a leitura diz "sem
recibo gravado ainda (nada a congelar)" — nunca `NENHUMA`/`VENCIDA`. O bloco
de verificação por área obrigatória (§9, Emenda E23b) também não roda para
`adiada` pelo mesmo motivo: compararia o mesmo tip.

`deferred_by` entra no MESMO teste de exclusão que `accepted_at`/`absorbed_by`
no laço de contagem de `ordens: N pendente(s)` de `hooks/session-start.sh`
(mesma técnica da emenda v1.11): ordem adiada não gera cutucão de aceite
pendente enquanto o campo existir. Ao contrário de `absorbed_by`, **não**
entra no laço de frozen zones — zona congelada por uma ordem suspensa continua
protegida (o trabalho pode ser retomado a qualquer momento; congelar evita
outro agente pisar no meio-tempo), decisão que fica registrada aqui para quem
ler depois e cogitar estender a exclusão.

Log: nenhum vocábulo novo em §4 — `deferred_by` é escrito à mão, fora do CLI,
e não passa por `log_event`.
`# classification: public` (a ordem é conteúdo do repo do usuário)

#### Emenda v1.15 (ordem 014, issue #18) — `--status --json`: fonte única de estado para o supervisor

Causa: o supervisor mora em repo próprio e **recalculava** a derivação de
estado da ordem por conta — a derivação vive aqui e evolui aqui, então as
duas leituras divergiam, e a que interrompe humano é a que erra. Medido
nesta sessão: catorze interrupções cobrando aceite de ordem que já tinha
estado terminal — sete antes de `absorvida` existir (issue #12, já
corrigida) e sete depois, porque o consumidor externo não conhecia o campo.
Cada estado novo que o Maestro cria (`absorvida`, ordem 004; `adiada`, ordem
013) alargava o buraco. Precedente do próprio repo:
`hooks/lib/habit-sensors.awk` é **sensor único, dois momentos** — divergência
entre eles seria dois vocabulários de smell; aqui são dois vocabulários de
**estado**.

`maestro order --status N --json` (decisão sobre `--porcelain`: **JSON**,
não KV/porcelain — o vocabulário de dado de máquina já estabelecido neste
arquivo é JSON em toda parte que importa, `session.json` §3, `routing.jsonl`
§4, o recibo de evidência §8; `--porcelain` não tem precedente no CLI do
Maestro e a saída tem estrutura aninhada — `prova`/`direcao`/`verificacao`
são objetos, não pares chave=valor linha a linha). **Zero dependência
nova**: emitido por `printf`/concatenação de string em bash puro
(`_order_json_field`/`_order_json_bool`/`_order_json_esc`, este último
escapando `\`/`"`/controle — necessário porque `deferred_by` é **escrito à
mão** pelo humano, v1.14, e não passa pela mesma validação de regex que
`branch`/ids).

**Módulo próprio, carregado sob demanda.** A emissão JSON mora em
`lib/cmd-order-json.sh`, não em `lib/cmd-order.sh` — vocabulário `cmd-` do
E24 (texto e JSON são dois ADAPTADORES do mesmo núcleo, responsabilidade
distinta o bastante pra ter nome próprio; núcleo `core-order-state.sh`
continua sendo o único que sabe DERIVAR). Motivo medido, não estético: o
patch original engordava `lib/cmd-order.sh` de 347 para 486 linhas e cruzava
o teto de `oversized-file` (400, `hooks/lib/habit-sensors.awk`) — a catraca
`maestro habits --all` reprova (exit 1) o que sobe acima do baseline, e a
régua não sobe pra acomodar linha nova. `lib/cmd-order.sh` ganha só
`_order_json_lib_load` (~15 linhas, molde de `_order_lib_load`/
`_verif_lib_load`, I-2): módulo ausente derruba SÓ o comando `--json` com
`die env`, nunca o CLI inteiro; `--status` SEM `--json` nunca soube que
`cmd-order-json.sh` existe — o `source` só roda dentro do braço `--json` do
despacho. `maestro habits lib/cmd-order.sh lib/cmd-order-json.sh` sai limpo
(nenhuma função >60 linhas, nenhum arquivo >400) — medido um a um, não só
"a soma cabe".

**Mesma fonte, nunca duas derivações**: `_order_action_status_json` lê os
MESMOS predicados de `core-order-state.sh` que `_order_action_status` (texto)
lê — `_order_status`, `_order_evidence_match`/`_order_proof_tree`,
`_order_deferred_tree`, `_order_moved_since_accept`, `_order_intent_stale`,
`_order_verif_areas`/`_order_verif_report` — e, no caminho de fallback de
prova (estado `provada`/`aberta`/`em_execucao`), a MESMA invocação de
`maestro evidence --label ... --project ...` que o texto já chamava. O campo
`estado` no JSON é literal e exclusivamente o retorno de `_order_status`; o
teste (`tests/cli/test-order-014-status-json.sh`) prova, para os SEIS
estados do contrato, que o valor de `estado` no JSON é byte-idêntico ao que
o modo texto imprime, e sabota (numa cópia) uma segunda derivação injetada
só no caminho JSON para provar que a MESMA asserção reprova.

**Forma do objeto** (chave → tipo; `null` é valor válido, nunca string
vazia):

```json
{
  "id": "014",
  "estado": "aberta|em_execucao|provada|aceita|absorvida|adiada",
  "branch": "order/014-...", "branch_existe": true, "branch_tip": "abc1234",
  "arquivo": "<caminho gravado no cabeçalho>",
  "terminal": false, "suspensa": false,
  "pede_aceite": true, "motivo": "revisar e aceitar",
  "direcao": {"ordem": "2", "atual": "2", "desatualizada": false, "hash_bump_pendente": false},
  "verificacao": [{"rotulo": "backend", "estado": "VÁLIDA"}],
  "absorvido_por": null, "adiado_por": null,
  "prova": {"estado": "valida", "detalhe": "VÁLIDA na aceitação — ...", "arvore": "<sha ou null>"}
}
```

`direcao`/`verificacao` são `null` exatamente quando o bloco correspondente
do texto (`_order_show_context`) não seria impresso (sem `intent_version`
carimbado; `adiada`, que pula verificação pelo mesmo motivo do texto — E23b
compararia com o tip atual, o que "venceria" o recibo congelado). `prova.estado`
é um vocabulário PEQUENO e DISTINTO do `estado` do topo (`valida|vencida|
nenhuma|absorvida|adiada|desconhecida`) — não é uma segunda leitura de
`estado`, é a leitura já existente do veredito de `maestro evidence`
(`VÁLIDA`/`VENCIDA`/`NENHUMA`) rebaixada para minúsculo ASCII.

**`pede_aceite`/`terminal`/`suspensa`/`motivo` são o que fecha a issue**: sem
eles, o supervisor teria de reimplementar o mapeamento "estado → preciso
interromper o humano?" toda vez que um estado novo nascer aqui — exatamente
o defeito medido. São computados pelo MESMO `case "$st" in ...)` que
`_order_show_next` (texto) usa para decidir a mensagem de "próximo": mesma
fonte, fan-out em campos estruturados, não uma segunda regra.

**Garantia de compatibilidade com estado futuro (o que esta emenda promete
e o que NÃO promete):**
1. Campo NOVO é sempre **aditivo** — nunca removido nem renomeado; provado
   por medição (mesmo método da ordem 005, `tests/cli/test-order-issue11.sh`
   item 4): o teste injeta uma chave top-level desconhecida no objeto e
   mostra que um leitor que só lê `id`/`estado`/`branch` continua recebendo
   a mesma resposta — JSON é aberto por natureza, leitor que ignora chave
   que não conhece nunca quebra.
2. **O CONJUNTO de valores de `estado` é contrato** (item 2 da trava desta
   ordem) — um SÉTIMO valor de `estado` exige emenda própria aqui, PARAR e
   chamar; esta emenda não abre exceção. O que ELA garante é que um
   consumidor escrito contra os campos `pede_aceite`/`terminal`/`suspensa`
   (em vez de contra a string crua de `estado`) sobrevive a um estado
   FUTURO sem mudança nenhuma — porque esses três campos são computados
   AQUI, no Maestro, pela mesma emenda que introduzir o estado novo, não
   recalculados pelo consumidor. Um consumidor que insiste em ler `estado`
   como string terá de tratar valor desconhecido explicitamente (é a
   recomendação: decidir por `pede_aceite`, não por comparação de string).
3. **O que NÃO foi garantido — dito, não inventado**: não há checagem
   automática (doctor/schema) que IMPEÇA um estado novo de nascer em
   `_order_status` sem que `_order_action_status_json` também o cubra —
   ambos vivem na mesma função Bash de um jeito que um `case` esquecido
   simplesmente cai no `*)` genérico (`motivo="aguardando execução"`,
   `pede_aceite=0`) em vez de falhar ruidosamente. Ordens futuras que
   introduzirem estado (mesma trava desta ordem: PARAR e chamar) devem
   ATUALIZAR `_order_action_status_json` no mesmo changeset que atualiza
   `_order_status`/`_order_show_next` — o teste dos seis estados reprovaria
   se o novo estado divergisse de texto para JSON, mas não reprova sozinho
   se o `case` do JSON simplesmente não ganhar um braço novo e cair no
   default (`aguardando execução`/`pede_aceite:false`) para um estado que na
   verdade deveria pedir aceite. É dívida CONHECIDA, não uma garantia
   mecânica — fica registrada aqui para quem abrir a próxima ordem de
   estado.

`--json` só se aplica a `--status N` (decidido NÃO estender a `--list` nesta
ordem — fora do escopo da issue #18, que é sobre UMA ordem por consulta;
`--list --json` fica para quando houver consumidor real). Log: nenhum
vocábulo novo em §4 — `--status` (com ou sem `--json`) é leitura pura, nunca
loga.
`# classification: public` (a ordem é conteúdo do repo do usuário)

#### Emenda v1.16 (ordem 017) — `provada` sem branch: a árvore CONGELADA, não o tip

Causa: `_order_status` tinha só o teste `git rev-parse --verify` pra decidir
se o branch existe, e "branch ausente" tem dois sentidos opostos que o código
só conhecia um. Nunca criado (nada começou) e mergeado-e-DELETADO (tudo
terminou, fim normal de toda ordem — apagar branch mergeado é o caminho
feliz) caíam no MESMO `printf 'aberta'`. Caso real, medido no vulcan
(2026-09-16): `.maestro/orders/002-lab-como-ambiente-de-prova-cript.md`, com
recibo válido gravado e branch já apagado, lia `estado":"aberta"` —
"reabre a cada merge" quando na verdade nunca fechou, e o único sinal de que
o trabalho existiu (o recibo) desaparecia da leitura assim que o branch
sumia. **Não é o hash da árvore absorvente**: `absorbed_tree` é só IMPRESSO,
nunca comparado, nos três lugares em que aparece (`lib/cmd-order-json.sh`,
`lib/cmd-order.sh` × 2) — não há invariante de árvore ali para violar.

**O invariante que esta emenda instala:** ordem com prova no ledger nunca lê
`aberta`. O recibo é durável — sobrevive ao branch, ao worktree e ao
checkout, é o artefato que este projeto criou para SER a prova.

**Decisão do diretor: NÃO abre estado novo no enum.** Um sétimo valor de
`estado` é mudança de contrato para todo consumidor que faz `switch` nele —
o supervisor e o `watcher.ts` do ponte-daemon, que hoje já erram com os
valores que CONHECEM (mandam aceitar ordem `absorvida`); somar um valor que
eles não conhecem pioraria um consumidor já quebrado, não consertaria nada.
`provada`, com `pede_aceite:true`/`motivo:"revisar e aceitar"`, já É a ação
certa aqui, e todo consumidor já sabe lidar com ela — reaproveita em vez de
inventar.

**`provada` passa a ter DOIS critérios, e nenhum dos dois é mais frouxo que
o outro** — o recibo sempre precisa existir e ter `exit=0`; o que muda é
CONTRA O QUE ele é conferido:
- **branch vivo** (comportamento de antes desta emenda, inalterado):
  `wtree_after` do recibo == árvore do tip ATUAL do branch (`_order_evidence_match`).
- **branch ausente** (nunca existiu OU foi apagado — o mesmo teste
  `git rev-parse --verify` cobre os dois; a distinção entre eles é feita
  pela PRESENÇA do recibo, não por outro sinal): não há tip vivo pra
  comparar, então vale a árvore que o recibo CONGELOU (`wtree_after`, sem
  comparação nenhuma) — `_order_evidence_frozen_tree`, núcleo puro em
  `lib/core-order-state.sh`. **Isto não afrouxa a prova**: o gate continua
  sendo `exit=0` no recibo, com o mesmo rigor de `_order_evidence_match`
  (recibo com falha, ou nenhum recibo, continua `aberta`, nunca `provada`);
  só o alvo da comparação muda, porque não há tip pra comparar depois que o
  branch some. Sem recibo nenhum (nunca começou), `aberta` continua certo —
  o invariante não se aplica a quem nunca produziu prova.

**Precedente reaproveitado, não reinventado**: a ordem 013 (`adiada`,
emenda v1.14) já tinha enfrentado "recibo válido sem tip vivo para
comparar" — `_order_deferred_tree` varre `_order_evidence_candidates` e lê
`wtree_after` sem jamais comparar com o tip, pelo mesmo motivo por outra
causa (lá é "adiada não anda", aqui é "o branch sumiu"; nos dois casos
comparar com um tip inexistente é que seria o erro — "venceria" o recibo por
mudança de árvore que não pode ser medida). `_order_evidence_frozen_tree`
reusa a MESMA varredura (candidatos + `wtree_after`), mas não é a MESMA
função: `_order_deferred_tree` não exige `exit=0` porque ali o gate já é o
campo `deferred_by` escrito à mão (a árvore é só para EXIBIÇÃO, "sem recibo
gravado ainda" é uma saída válida); aqui o `exit=0` É o gate que decide
`provada` em vez de `aberta` — tem que ser tão rígido quanto
`_order_evidence_match` já é quando o branch existe. Por isso é irmã, não a
mesma função.

`_order_proof_tree` (usado por `_order_json_prova_frag` para `prova.arvore`
no `--status --json`) ganha o mesmo fallback: quando `_order_evidence_match`
devolve vazio por falta de branch, cai para `_order_evidence_frozen_tree` em
vez de deixar `prova.arvore` como `null` — o consumidor externo vê a árvore
provada mesmo sem branch vivo.

**`_order_json_acao_frag` (lib/cmd-order-json.sh) NÃO mudou** — `provada` já
tinha o braço `pede=1; motivo="revisar e aceitar"` no `case`, e `terminal`
continua `false` para `provada` (não é fim de linha: humano ainda decide
aceitar, marcar `absorvida`/`adiada`, ou reabrir o branch). O contrato do
JSON (nome de campo, forma do objeto, CONJUNTO de valores de `estado`) não
mudou nesta emenda — é o caso raro em que a causa (`_order_status`) e o
fallback de exibição (`_order_proof_tree`) bastam, sem tocar o vocabulário
externo.

Prova: `tests/cli/test-order-017-provada-sem-branch.sh` reproduz o caso do
vulcan (recibo válido + branch mergeado-e-apagado + sem carimbo → nunca
`aberta`), o caso legítimo (sem recibo e sem branch → `aberta`), o recibo com
`exit≠0` (continua `aberta`, o gate não afrouxou), `aceita`/`absorvida`
terminais com o branch deletado, e os quatro campos do `--json`
(`estado`/`terminal`/`pede_aceite`/`motivo`/`prova.arvore`) para o caso do
vulcan — mesmo padrão PENDENTE/reprova-de-verdade das ordens 003/004A/013:
sem o patch em `docs/patches/017-estado-terminal-core-order-state.patch`
aplicado, PENDENTE (nunca falha; `lib/` está na denylist de autoproteção do
gate); com o patch, cobra de verdade.
`# classification: public` (a ordem é conteúdo do repo do usuário)

#### Emenda v1.18 (ordem 021) — o carimbo terminal sai da árvore: `~/.maestro/order-state/<slug>-<hash8>-<id>`

Causa: `accepted_at`/`absorbed_by` eram escritos **só no arquivo da ordem, na
árvore de trabalho**, e nunca commitados (`.maestro/orders/*.md` fica `??` ou
`M` neste repo e nos projetos que o Maestro governa — ver `.gitignore`/fluxo
de cada um). Qualquer `git checkout`/`stash`/`reset` que restaure o `HEAD`
apaga o carimbo **em silêncio**, e a ordem volta a `provada`/`aberta`. Medido
no Agenda_Studio (2026-09-18): o diretor fechou as ordens 012–016 como
absorvidas, mergeou o PR, `main` andou, as cinco voltaram a `provada` nos dois
leitores (`maestro order --list` e a ronda da Ponte) — o refechamento
funcionou (`_order_accept_absorb` não disse "já absorvida"), provando que o
carimbo tinha mesmo sumido, não que um leitor estava desatualizado. Mesma
raiz da issue #36 (o carimbo de aceite não atravessa worktree), um degrau
abaixo: lá não atravessa um `checkout`.

**O desenho:** o estado terminal passa a ser gravado **fora da árvore**, em
`maestro_order_state_file` (`hooks/lib/project-state.sh`, ordem 021) —
`~/.maestro/order-state/<slug>-<hash8>-<id-com-3-dígitos>`, MESMA chave djb2
de `maestro_brief_file`/`maestro_evidence_file` (§7/§8: worktree e repo
principal são o MESMO projeto, E15 — propriedade que esta ordem precisa
porque o `checkout` que apaga o carimbo do arquivo roda na MESMA árvore que o
gravou). Chaveado por **ordem** (id), não por rótulo livre como a evidência:
o id já é o identificador estável da ordem dentro do projeto. Formato
chave=valor, schema versionado, escrita atômica (tmp+mv) — MESMA técnica de
`_ev_write` (§8):

```
schema=maestro-order-state-v1
id=<id numérico>
outcome=aceita | absorvida
# aceita:
accepted_at=<timestamp>
accepted_session=<session_id>
accepted_tree=<árvore (sha) provada no aceite>
# absorvida:
absorbed_by=<id numérico | "main">
absorbed_tree=<árvore (sha) que a ABSORVENTE provou>
absorbed_at=<timestamp>
absorbed_session=<session_id de quem carimbou>
```

A árvore entra como **DADO do carimbo** ("foi absorvida/aceita contra esta
árvore"), nunca como condição de validade — não é reconferida depois; é
histórico, igual já era no arquivo.

**Precedência, quando arquivo e registro discordam** (`_order_status`,
`lib/core-order-state.sh`, e os dois leitores de campo irmãos que ela ganha —
`_order_terminal_field_header` para `absorbed_*`, no CABEÇALHO, e
`_order_terminal_field_appended` para `accepted_*`, ANEXADO ao final,
último-vence — MESMA distinção "irmã, não a mesma função" da emenda v1.16,
porque ONDE cada campo vive no arquivo difere): **o registro, quando existe,
É o estado — o arquivo é conveniência de leitura humana, nunca reconferido
contra ele.** Três casos, os três testados:
1. **Arquivo carimbado, registro ausente** (migração — toda ordem carimbada
   antes desta emenda entrar): o carimbo do arquivo **ainda conta**,
   comportamento idêntico a antes desta ordem. Nenhuma ordem já terminal
   "reabre" quando este código entra.
2. **Registro presente, arquivo restaurado** (o defeito que esta ordem
   fecha — o caso do Agenda depois do `checkout`): o registro decide; o
   estado continua terminal mesmo com o arquivo sem carimbo nenhum.
3. **Os dois presentes e concordando** (fluxo normal depois desta ordem,
   `--accept`/`--accept --absorbed-by` gravam os dois na mesma chamada): o
   registro decide, e concorda com o arquivo — nenhuma mudança visível.

Não há caminho de escrita que produza os dois presentes **discordando**
(ambos são gravados na MESMA chamada de `--accept`, mesmo timestamp) — só
adulteração manual do registro produziria isso, fora do escopo desta ordem.

**Escrita:** `_order_accept_absorb`/`_order_accept_own`
(`lib/cmd-order.sh`) chamam `_order_state_write` **depois** do carimbo no
arquivo ter sido gravado com sucesso. Falha na escrita do registro **não
degrada em silêncio** — `die env`, porque silenciar aqui reproduziria
exatamente o defeito que a ordem fecha (o `--accept` pareceria ter
funcionado, mas o estado ficaria vulnerável ao mesmo `checkout` de sempre).
O retry é idempotente: o arquivo já tem o carimbo, então uma nova chamada de
`--accept` recalcula os mesmos valores e tenta gravar o registro de novo (ou
cai no ramo "já absorvida"/"já aceita" se ele colar na primeira tentativa
seguinte).

**Migração:** nenhuma ordem carimbada só no arquivo, em qualquer projeto
desta máquina, precisa de `--accept` de novo — o caso 1 da precedência acima
cobre isso por construção (arquivo carimbado + registro ausente → arquivo
ainda conta). Conferido contra as ordens 012–016 do `~/dev/Agenda_Studio`
(leitura apenas, `maestro order --list --project`): `_order_status`,
patchado, devolve **exatamente o mesmo resultado** que o código sem patch —
nenhuma das cinco muda de estado com esta ordem aplicada (a prova exigida é
"não regride", não "conserta dados que já sumiram do arquivo"). Achado à
parte, não causado por esta ordem: no clone desta máquina, as cinco JÁ
liam `aberta`/`em_execucao` **antes** do patch — o `HEAD` corrente não tem
`absorbed_by` em nenhuma delas (`grep -c '^absorbed_by:'` = 0 nas cinco),
então o carimbo já havia sido perdido por um `checkout` anterior ao desta
sessão. O registro fora da árvore não pode reconstruir um carimbo que nem o
arquivo nem nenhum registro têm mais — só impede a PRÓXIMA perda, a partir do
próximo `--accept` rodado sob este código.

**Contrato externo intocado (TRAVA desta ordem):** nome de campo e forma do
`--status --json` não mudam — `_order_json_acao_frag` não muda, `absorvido_por`
continua o mesmo campo, só a LEITURA por trás dele ganha o fallback
(`_order_terminal_field_header`). Nenhum valor novo no enum de `estado`: esta
emenda muda ONDE o estado mora, não quais estados existem.

**Adendo do diretor, mesmo corte — `--absorbed-by` para de fixar `main`:**
`_order_accept_absorb` (`lib/cmd-order.sh`) tinha a string `'main'` literal
em QUATRO pontos (gatilho, existência, árvore e — o que ninguém enxergava —
o RÓTULO DO RECIBO em `maestro_evidence_file "$proj" main`). Repo cujo
branch padrão é `master` (caso real: NetForge) não tinha caminho nenhum para
fechar uma ordem como absorvida: `--absorbed-by main` recusava ("'main' não
existe"), e `--absorbed-by master` também recusava, pela validação genérica
que só aceita `main` ou id numérico. `_order_default_branch`
(`lib/core-order-state.sh`) resolve o branch padrão de verdade — `origin/HEAD`
→ `init.defaultBranch` LOCAL (só se o branch existir; config desatualizada
não é sinal) → existência direta de `main`/`master` → fallback literal
`main` — **sem rede** (E19). `main` e `master` viram os DOIS apelidos
aceitos para "o branch padrão do repo", sempre resolvidos, nunca fixos; o
carimbo passa a gravar o **nome real** do branch (não o apelido digitado), o
que também resolve o rótulo do recibo pela mesma via. Repo cujo padrão já é
`main` não muda de comportamento (a resolução acha `main` pela via da
existência direta, mesmo sem `origin/HEAD`/config) — quem já grava recibo
com rótulo `main` continua encontrando-o. `absorbed_by: <id numérico de 1-3
dígitos | "main" | "master" | o branch padrão resolvido>` substitui a forma
antiga da emenda v1.11 (`"main"` fixo).

Prova: `tests/cli/test-order-021-estado-fora-da-arvore.sh` — as duas pontas
(vermelha/verde) do teste-que-é-a-ordem (carimba → `git checkout` no arquivo
→ estado continua terminal), nos dois desfechos (`absorvida` e `aceita`); os
três casos de precedência; e a fixture da migração (registro nunca gravado +
arquivo carimbado → segue terminal, nunca `aberta`). `tests/cli/test-order-
021-absorb-default-branch.sh` — repo `main`-default sem regressão, repo
`master`-default (o caso do NetForge) absorvendo com `--absorbed-by main` E
com `--absorbed-by master`, carimbo gravando o branch real. Mesmo padrão
PENDENTE/reprova-de-verdade das ordens 003/004A/013/017: sem os patches em
`docs/patches/021-estado-terminal-*.patch` aplicados, PENDENTE (nunca falha;
`lib/`/`hooks/` estão na denylist de autoproteção do gate); com os patches,
cobram de verdade.
`# classification: public` (a ordem é conteúdo do repo do usuário)

#### Emenda v1.19 (ordem 022) — `--accept` cura o registro ausente quando o carimbo já é terminal por arquivo

**Débito de documentação, registrado antes do conserto**: a ordem 021 tirou o
estado TERMINAL da árvore de trabalho — um registro em
`~/.maestro/order-state/<slug-do-projeto>-<hash8>-<id>` (mesma chave djb2 do
brief/evidência, §7/§8; formato `chave=valor`, schema `maestro-order-state-v1`,
gravado por `_order_state_write`/lido por `_order_terminal_field_header`
(campos do CABEÇALHO: `absorbed_*`) e `_order_terminal_field_appended`
(campos ANEXADOS: `accepted_*`), em `lib/core-order-state.sh`) — mas o próprio
patch da ordem 021 nunca ganhou emenda aqui (o código já cita "DATA_MODEL §9
v1.18" em comentário, forward-reference que ficou pendente). Esta emenda
registra o schema retroativamente, no mínimo necessário para o conserto
abaixo fazer sentido — não é uma auditoria completa da ordem 021, que fica
como débito à parte. **Precedência, já em vigor desde a ordem 021, inalterada
por esta emenda**: registro presente decide sozinho (`outcome=aceita|absorvida`);
registro ausente cai para o carimbo do ARQUIVO (`accepted_at`/`absorbed_by`) —
é essa segunda perna que esta emenda conserta.

**Causa, medida no Agenda_Studio (2026-09-18):** a queda para o arquivo
cobre a LEITURA (ordem que fechou antes do patch da 021 continua lendo o
estado certo hoje), mas não a ESCRITA: `maestro order --accept N
[--absorbed-by M]` sobre uma ordem TERMINAL só-por-arquivo (registro
ausente) caía direto no ramo "já aceita"/"já absorvida — nada a fazer" e
retornava sem gravar o registro. Não havia comando para migrar — a ordem
continuava vulnerável a "reabrir" no próximo `git checkout`/clone/stash que
descartasse a modificação não commitada que é o carimbo do arquivo (a mesma
causa-raiz que a ordem 021 fechou para o carimbo NOVO, um degrau abaixo: aqui
é o carimbo VELHO, que nunca teve registro para começar).

**O conserto:** os dois braços de `--accept` (`_order_accept_own`,
reaceite-sem-movimento; `_order_accept_absorb`, `--absorbed-by`) passam a
checar, quando `_order_status` já deriva terminal a partir do arquivo, se o
registro fora da árvore existe (`_order_state_registrado`, novo predicado em
`lib/cmd-order-accept.sh`). Ausente → CURA: grava o registro imediatamente,
com os valores lidos do PRÓPRIO ARQUIVO (`_order_terminal_field_header`/
`_order_terminal_field_appended`, as mesmas funções de leitura que já existem
— nenhuma segunda derivação) — nunca os do instante da cura. Concretamente:
quem absorveu/aceitou, quando, e contra qual árvore são os que já estavam
carimbados; a `--session` de quem RODOU a cura não entra no registro
(`absorbed_session`/`accepted_session` continuam sendo o autor histórico).
Presente → comportamento de antes, sem mudança: "nada a fazer", registro
intocado. Vale para os dois desfechos terminais, `absorvida` e `aceita`.

**Campo ausente no arquivo grava sentinela, nunca um valor inventado.** Caso
real e não hipotético: emenda v1.11 já documenta `absorbed_by: main`
carimbado À MÃO antes do CLI conhecer o campo (`d394a47`), sem
`absorbed_tree`/`absorbed_at`/`absorbed_session`. A cura grava
`desconhecida` para árvore ausente (mesmo sentinela que `accepted_tree`/
`absorbed_tree` já usam em outros pontos deste arquivo — nunca string vazia)
e `desconhecido` para instante/sessão ausentes — o mesmo vocabulário
"não sei", nunca "agora"/"quem migrou".

**Cura não é reescrita — a garantia que decide a qualidade deste conserto:**
o predicado que abre a cura (`_order_state_registrado` falso) é o MESMO que
faz uma segunda tentativa virar no-op puro — resultado idempotente, registro
byte-a-byte igual entre a primeira gravação e qualquer tentativa seguinte
(inclusive depois de um `git checkout` que apague o carimbo do arquivo: a
partir da cura, o registro é a fonte, e nem precisa mais do arquivo para
continuar terminal).

**Não loga `order_accept`/`delegation phase=accepted`.** A cura não é uma
decisão nova de aceite/absorção — é bookkeeping preenchendo um registro para
uma decisão que já aconteceu no passado (o arquivo já provava isso). Logar
como se fosse um aceite de agora infla `session_end`/estatísticas de
delegação com um evento que não ocorreu na sessão que rodou a cura. Nenhum
vocábulo novo em §4.

**Extração que acompanhou o conserto:** `lib/cmd-order.sh` tocava o teto do
sensor `oversized-file` (400 linhas, margem zero) antes desta ordem —
`_order_accept_absorb`/`_order_accept_own` saíram para `lib/cmd-order-accept.sh`,
módulo próprio carregado sob demanda só na ação `--accept`, mesmo molde e
mesmo motivo medido da emenda v1.15 (`lib/cmd-order-json.sh`, ordem 014):
aceite/absorção é um ADAPTADOR de ESCRITA sobre o núcleo
(`core-order-state.sh`) que `--status`/`--status --json` já leem como
adaptadores de LEITURA. A extração, sozinha, não muda nenhum comportamento —
provada por rodar a suíte completa com só ela aplicada, sem o conserto.

Prova: `tests/cli/test-order-022-cura-registro.sh`, mesmo padrão
PENDENTE/reprova-de-verdade das ordens 003/004A/012/013/017 — carimbo
terminal é INJETADO no arquivo como modificação não commitada sobre uma base
commitada sem carimbo (não pela CLI, que já patchada nunca reproduziria o
registro ausente), reproduzindo as duas pontas: sem o conserto, `--accept`
responde sem gravar e um `git checkout` no arquivo reabre a ordem (vermelho
confirmado contra o código de hoje); com o conserto, `--accept` grava o
registro a partir do arquivo (nunca do instante da cura, inclusive com
sessão de quem carimbou originalmente preservada), o `git checkout` seguinte
não reabre mais nada, e uma segunda tentativa é no-op com o registro
inalterado byte a byte — nos dois desfechos (`absorvida`/`aceita`) e no caso
de campo ausente no carimbo legado (v1.11).
`# classification: public` (a ordem é conteúdo do repo do usuário)

#### Emenda v1.21 (ordem 024 fatia 1) — `fronts`/`measures`: o eixo RECURSO do `mode: multi`

Causa medida (não hipótese): H6 ("frentes independentes que não se bloqueiam →
mode: multi") só exigia disjunção em ARQUIVOS. Seis frentes despachadas juntas
mediram load 17,4 em 8 CPUs, suíte de 8m41s para 9m52s, uma ordem presa 47min
em fila e recibos consecutivos "fora do limiar de medição" — duas frentes
podiam não tocar o mesmo arquivo e ainda assim se destruírem na CPU. Faltava o
eixo RECURSO: **frentes que DECIDEM paralelizam; frentes que MEDEM correm
sozinhas.**

Dois campos novos no decision record, ambos opcionais, ambos escritos por
`maestro decide` (`src/cli.ts`, nunca em bash — mesmo dono de sempre do
record):

```json
{
  "fronts": [["a/", "b/"], ["c/"]],
  "measures": true
}
```

| campo | tipo | validação |
|---|---|---|
| `fronts` | array de arrays de string | só existe com `--fronts` em `mode: multi`; ≥2 frentes, cada frente ≥1 caminho, caminho ≤200 chars. Eixo ARQUIVO: o `decide` RECUSA (decide-time, exit 1) sobreposição de PREFIXO de diretório entre DUAS frentes — duas frentes que disputam o mesmo diretório se destroem na CPU mesmo sem tocar o mesmo arquivo, e é esse buraco que o campo fecha |
| `measures` | `true` (booleano) | marca esta frente como MEDIDORA (roda suíte/benchmark). Só existe `true`; ausência é "não mede" — nunca `false` gravado |

`fronts` é a declaração de UMA decisão orquestradora (`--fronts "a/ b/;c/"`,
frentes separadas por `;`, caminhos por espaço) — não agrega frentes de
sessões diferentes; quem lista todas as frentes de um swarm é quem as
despacha. `measures` é independente de `mode`: uma frente medidora pode ser
`direct`, `subagent` ou `multi` — o que importa é que ela vai rodar algo
sensível a contenção de CPU, não que ela orquestre outras frentes.

**Eixo RECURSO é aviso, nunca recusa (INTENT Prioridades §1).** Com
`--measures`, o `decide` verifica `~/.maestro/sessions/*.json` (mesma fonte
que o E26 já escopa) por outra sessão VIVA e não expirada (`expires_at` no
futuro, fonte de verdade já usada por `record_expired`/`doctor`) — havendo
uma, **avisa** ("frentes que MEDEM correm sozinhas") e segue gravando o
record normalmente; nunca bloqueia. A guarda degrada em SILÊNCIO: sem
`~/.maestro/sessions/`, JSON corrompido ou arquivo ilegível, ela simplesmente
não encontra nada e não avisa — falha de leitura nunca derruba o `decide`.

Os dois campos são ADITIVOS: um record gravado antes desta emenda (sem
`fronts` nem `measures`) continua válido — `record_schema_ok`
(`lib/core-record.sh`) só valida o formato QUANDO o campo existe, mesmo
molde de `depth`/`profile`/`budget`/`flags`. `fronts`/`measures` vivem só no
record, nunca no `~/.maestro/logs/routing.jsonl` (§4 intocado) — nenhum dos
dois é vocabulário fechado de evento, e caminho de diretório do projeto do
usuário não é metadado de roteamento.

Consumidor do eixo RECURSO na leitura ANTES de medir: `maestro evidence
--record` reaproveita a MESMA sonda de carga da issue #11/ordem 005
(`load1m_x100`, `ncpu`, o `load_limiar` de `_ev_cmd_qualifiers`) para avisar,
ANTES de rodar o comando sob prova, quando a carga já está fora do limiar —
API_SPEC §2 (`maestro evidence`). Nenhuma sonda nova; o formato do recibo
(§8) não ganha campo novo por esta emenda.

Prova: `tests/hooks/test-order-024-swarm.sh`.
`# classification: confidential` (mesma classificação do resto do record — os
caminhos de `fronts` revelam estrutura do repo do usuário).

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

#### Emenda v1.12 (E24 Lote 0, ordem 006) — dívida DECLARADA com prazo em `.maestro-habits.tsv`

Causa: `bin/maestro` não era sensoriado — o filtro de `.maestro-habits.tsv` §2
comparava só por EXTENSÃO reconhecida, e `bin/maestro` (sem ponto no nome) era
o único arquivo do repo isento da própria catraca. A detecção passa a ser por
SHEBANG quando a extensão falta (`maestro_lang_ext`, `hooks/lib/common.sh` —
sensor único que hook e CLI sourceiam, I-4): extensão reconhecida devolve sem
ler o arquivo (custo zero no caminho quente); sem extensão, lê só a 1ª linha
(builtin, sem fork) e mapeia `#!.../bash|sh|zsh` → `sh`, `#!.../python*` → `py`.

`.maestro-habits.tsv` ganha colunas 3/4, OPCIONAIS (retrocompatível — linha de
2 colunas lê exatamente como antes):

```
# sensor            contagem  vence_epoch  alvo
oversized-function  23        1791999999   6
```

`vence_epoch` e `alvo` são inteiros (CLAUDE.md proíbe float em métrica de
custo) — valor torto é RECUSADO em silêncio, a linha volta a se comportar
como as de 2 colunas. `maestro habits --all` reprova (`exit 1`) quando
`now > vence_epoch` **e** `contagem > alvo`, mesmo que a contagem esteja
dentro do baseline da coluna 2 — é a única forma de o prazo ser mecânico, não
decorativo. `maestro doctor` avisa (`warn`) a partir de **D-14** do
vencimento, e de novo (com redação diferente) depois de vencido; nunca falha
o `doctor` — quem reprova de verdade é `maestro habits --all` (S-905).

#### Emenda v1.13 (E24 Lote 0, decisão A) — `lib/` entra na autoproteção do gate

`config/routing-table.yaml` (`gate.denylist.self_paths`, §1) é a fonte viva;
`hooks/session-start.sh` a compila em `gate-policy.sh` a cada SessionStart.
Quando o YAML não declara `self_paths` (ausente/corrompido), o hook cai no
fallback embutido (`SELF_FALLBACK`) — que agora inclui `lib/`: os módulos do
split do E24 (`docs/designs/e24-nucleo-e-adaptadores.md`) nascem lá, e sem
isto ~85% do CLI bash migraria para uma zona sem a guarda do ADR-003 v1.2,
vencida por MUDANÇA DE ENDEREÇO em vez de remoção. `hooks/pre-tool-gate.sh`
tem um segundo fallback (env-default na leitura da variável), usado só quando
a política compilada nem chega a DEFINIR `MAESTRO_GATE_DENY_SELF`; a origem
normativa é sempre `session-start.sh` — um lugar só, para não repetir a lição
do filtro de extensão duplicado.

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
