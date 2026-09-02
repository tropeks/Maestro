---
covers:
  - bin/maestro
  - hooks/*.sh
---
# API_SPEC.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.1 — 2026-08-08 (emendas review Opus)
**Consome:** ARCHITECTURE.md, DATA_MODEL.md | **Consumido por:** security-architect, vibe-code

> Sem HTTP. As "APIs" do Maestro são dois contratos: **CLI** (`maestro-decide` e utilitários)
> e **I/O de hooks** do Claude Code (stdin JSON / exit codes). Authz: N/A (ADR-005, local
> single-user). Rate limit: N/A.

---

## 1. Contrato de hooks (Claude Code)

Todos os hooks: primeira linha checa `MAESTRO_OFF=1` → exit 0 imediato (kill-switch).
Entrada: JSON no stdin (formato nativo do Claude Code). Saída: exit code + stdout/stderr.

### `hooks/session-start.sh` — evento SessionStart
- **Lê:** `$CLAUDE_PROJECT_DIR/.maestro.yaml` (se existir), `config/routing-table.yaml`, índice do roster.
- **Emite (stdout → contexto):** bloco `<maestro-routing>` com: **o `session_id` literal da sessão** (para o Claude passar ao CLI), tabela de rotas, heurísticas de execução, lista de agentes (nome + 1 linha + modelo), instrução canônica: *"antes de editar código, registre a decisão com `maestro-decide --session <id>`"*.
- **Também:** limpa decision records expirados (TTL 4h) e **recompila a política do gate** (`~/.maestro/gate-policy.sh`) a partir do YAML — fonte de verdade única.
- **Erros:** qualquer falha → exit 0 com stderr logado (degrada, nunca bloqueia sessão).
- **Orçamento:** saída ≤ **8.000 bytes** (proxy determinístico de ~2k tokens). Truncamento em ordem: heurísticas → índice do roster → nunca a instrução canônica nem o session_id.
- **Emenda E7 (S-707/S-709):** emite também `## Mote de execução` (`config/execution-ethos.md`) e `## Estilo de comunicação com o usuário` (`config/communication-style.md`) — teto de 2.000 bytes por arquivo; ausente → seção omitida em silêncio. No orçamento cedem ANTES de tudo, nesta ordem: estilo primeiro, mote depois — referência de comportamento, não instrução de ação.
- **Emenda E19 (S-1901):** ANTES de ler tabela e roster, `update_step` roda a checagem de
  atualização (`hooks/lib/update-check.sh`): `git fetch` com timeout (`MAESTRO_UPDATE_TIMEOUT`,
  5s) no máximo uma vez por intervalo, depois só git local. Estado `available` +
  `auto_upgrade` (default ligado) → `merge --ff-only` e **re-exec do hook novo** com
  `MAESTRO_UPDATE_REEXEC=1`, `MAESTRO_UPDATED_FROM/TO` e `CLAUDE_SESSION_ID` (o stdin já foi
  consumido) — a injeção sai inteira da versão nova, com a linha `atualizado agora: vX → vY`.
  Sem auto: linha `atualização: vX → vY (N commit(s) no origin) — maestro upgrade aplica`.
  Bloqueado (árvore suja/à frente/branch): linha nomeando a máquina de desenvolvimento.
  Rede falha, snooze vigente, em dia ou desligado: **nenhuma linha** — o estado fica em
  `$MAESTRO_HOME/update-state` (DATA_MODEL §10) e é o doctor que fala. A linha mora no
  cabeçalho (nunca trunca). Desliga com `MAESTRO_NO_UPDATE_CHECK=1` ou `update_check: false`.
  **S-1810 (v1.11.1):** dentro do intervalo, se HEAD e `origin/main` são os mesmos SHAs
  da última checagem `current`, o hook reaproveita o estado com dois `rev-parse`
  (`reason=fast-path`) — custo medido ~50ms sobre a sessão sem checagem (era ~150ms).
  Leitura de estado/config sem `sed`: lookups em bash puro.
  **S-1904 (v1.12.1):** o fetch leva `--tags` — máquina que só segue `main` recebe a tag
  da release junto, e o doctor compara o retrato com a tag certa.

### `hooks/pre-tool-gate.sh` — evento PreToolUse, matcher `Edit|Write|MultiEdit`
- **Dependência declarada:** `jq` (parsing de stdin; validado pelo doctor). Fixtures adversariais em `tests/fixtures/`.
- **`post-edit-habits.sh` (E9, PostToolUse em Edit|Write|MultiEdit):** roda os habit
  sensors no arquivo editado e, com achado, emite `<maestro-habit>` (≤3 achados + ≤2
  guias capados em 700B) no stderr com exit 2 — feedback ao agente, NUNCA bloqueio
  (a edição já aconteceu). Cooldown de 15min por (arquivo, smell) em
  `$MAESTRO_HOME/sessions/`. Limpo/degradação → exit 0. Kill-switch idem aos demais.
- **Lê do stdin:** `tool_name`, `tool_input.file_path`, `session_id`.
- **Lógica:**
  1. **denylist por caminho** (repo do plugin, `agents/`, `config/routing-table.yaml`, `.github/workflows/`, configs executáveis) → block sempre (exit 2), mesmo com decisão registrada
  2. allowlist caminho+extensão de não-código (compilada de `routing-table.yaml::gate`) → exit 0
  3. existe `~/.maestro/sessions/<session_id>.json` válido e **não expirado (TTL 4h)** → exit 0 + log `gate_pass`
  4. senão → conforme `gate.mode` na config: **`warn`** (exit 0 + log `gate_warn` + mensagem) ou **`block`** (exit 2). Default inicial: `warn`; promoção a `block` após 1 semana de dados.
- **Latência:** < 50ms.

### `hooks/user-prompt-submit.sh` — evento UserPromptSubmit (ADR-008)
- Prompt inicia com `/` → log `override_manual` com **apenas o nome do comando** (vocabulário fechado). Sempre exit 0; nunca altera o prompt.

### `hooks/session-end.sh` — evento SessionEnd (S-1811, v1.11.1)
- **Lê:** `session_id` do stdin (regex; `CLAUDE_SESSION_ID` como fallback) e o decision
  record `$MAESTRO_HOME/sessions/<id>.json`, só por presença: `workflow` presente →
  `decided=yes`; `outcome` ∈ accepted|rework|reverted → `settled=yes`.
- **Emite:** uma linha `session_end` no log com `session_id`, `decided`, `settled` — nada
  do record (brief, flags, reason) sai. Nada em stdout (`exec 1>&2`).
- **Erros:** sempre exit 0 — stdin vazio/lixo/id fora do tipo, kill-switch, lib ausente,
  home inescrevível: sem evento, sem ruído. Sem `jq`, sem Bun, sem rede.
- **Consumidor:** `maestro retro` imprime `sessões encerradas · sem decisão · decididas
  sem desfecho` (E18 fase 2: a variável que faltava para medir sessões sem `outcome`).
- **Emenda E20 (S-2001):** depois do evento, se a máquina optou (`telemetry_remote`),
  publica os `routing*.jsonl` no barramento (DATA_MODEL §11) via
  `hooks/lib/telemetry-sync.sh`: uma vez por intervalo, teto de tempo por operação de
  git (`MAESTRO_TELEMETRY_TIMEOUT`, 10s), lock não bloqueante, falha silenciosa e
  registrada em `telemetry-state`. Nunca muda o exit 0. `MAESTRO_NO_TELEMETRY=1` desliga.

### `maestro telemetry` (E20/S-2002)
- `--status` (default): estado legível a partir de `telemetry-state` ou "desligada". Exit 0
  (2 se o último push falhou).
- `--push`: publica agora (ignora o intervalo). Exit 0 publicou/sem novidade, 1 desligada,
  2 falhou.
- `--pull`: deixa o clone `~/.maestro/telemetry` em dia e lista os hosts. Exit 0/1/2.
- `--remote <url>`: grava `telemetry_remote` no config.yaml (liga); `--off` remove (desliga).
- `maestro retro --all`: pull + agrega os logs dos outros hosts (nunca o próprio, que já
  está local) e imprime `-- por máquina: <id> (<HOST>): N decisões · …`; desligada → avisa
  e segue só local. Sem `--all`, saída inalterada.
- Doctor: `check_telemetry` — sem remoto → ok "local"; último push falhou, ou sem push
  bem-sucedido há mais de 7 dias → warn com `maestro telemetry --push`. Envelope ganha
  `telemetry.{result,host}`.

### `hooks/gate-report.sh` — evento Stop (E21/S-2101, v1.13.0)
- **Só dentro do herdr** (`HERDR_ENV=1` + `HERDR_PANE_ID` tipado); fora, no-op absoluto.
- **Lê:** o decision record da sessão (regex, presença + enums). Gate pendente = workflow
  plan-gated (`feature`/`refactor`) com `approach: pendente` no brief → `plan`; `ship` sem
  `outcome` → `ship`. Sem gate: apaga o arquivo do pane (resolvido por outro caminho) e sai.
- **Escreve:** `$MAESTRO_HOME/herdr/gates/<pane>` (`:` vira `_`), chave=valor: `gate`,
  `session`, `project` (basename do projeto), `ts`, `message` — a pergunta regida em uma
  linha (`gate plan · <projeto> · <essência> — Aprovo o plano? (aprovo | ajusta: …)` /
  `gate ship · … — Shipo agora? (shipa | espera)`). Só a essência do brief sai; `reason`
  nunca.
- **Reporta (best-effort):** `herdr pane report-agent … --state blocked --message …`, 2s
  de teto. Para o Claude Code a autoridade de estado é a leitura de tela do herdr, então
  o report pode ser ignorado — o arquivo é o canal garantido; o forwarder (Legatus vNext)
  prefere o arquivo ao scrape da tela.
- **Resposta do humano:** `user-prompt-submit.sh` apaga o arquivo do pane e chama
  `pane release-agent` (mesmo teto). Sempre exit 0; nada em stdout (Stop hook com JSON no
  stdout vira decisão do Claude Code).

### `hooks/log-stop.sh` — evento Stop (opcional, v1.1)
- Fecha o ciclo no log (`event: session_end`), computa contagens da sessão.

## 2. Contrato do CLI

### `maestro-decide`
```
maestro-decide --session <session_id>          # OBRIGATÓRIO — valor injetado pelo SessionStart
               --workflow <fix|feature|refactor|ship|audit|custom>
               --mode <direct|subagent|multi>
               [--agents a,b,c] [--reason "..."]
               [--depth standard|deep|day-zero] [--profile prototipo|piloto|produto]
               [--brief "essencia: ...\nimpacto: ...\napproach: ..."]
```
- Valida contra `routing-table.yaml` (workflow precisa existir; `mode≠direct` exige `--agents`; agentes precisam existir no roster). `--reason` truncado em **120 caracteres** com aviso (mitigação de vazamento de prompt).
- **E17/S-1701 — regência:** `--depth` default `standard`; `--profile` **obrigatório
  SSE `--depth day-zero`** (presente com outro `depth` é erro de validação). `--brief`
  exige os três marcadores `essencia:`/`impacto:`/`approach:` — cada um ≤200 chars
  (truncado com aviso, precedente `--reason`), soma ≤700; `approach: pendente` é aceito
  (o approach real chega depois via `maestro conduct`). **Recusa decide-time (exit 1):**
  quando o `--workflow` resolve para `gate: plan` na routing table (`feature`,
  `refactor`) e `--brief` está ausente ou incompleto — o CLI já parseia `gate` da
  routing table para esta checagem; o pre-tool-gate permanece workflow-agnóstico (NFR
  <50ms preservado, nenhuma leitura de routing table no hot path do gate). Verificação é
  **presença + formato**, nunca qualidade — greppável, não julgada. Limitação declarada:
  a allowlist do gate (`.md`, `docs/`) segue liberando edição sem decision record — sessão
  doc-only, inclusive `--depth day-zero`, não é bloqueada por brief ausente (DATA_MODEL §3
  v1.7).
  ```
  $ maestro-decide --session abc123 --workflow feature --mode subagent --agents dev-pleno
  maestro: validation: workflow 'feature' (gate: plan) exige --brief com essencia:/impacto:/approach: (fix: adicione --brief ou use --workflow fix/custom)
  $ maestro-decide --session abc123 --workflow feature --mode subagent --agents dev-pleno \
      --depth deep --brief $'essencia: gate de regência no decide\nimpacto: aprovador le 3 linhas, nao o diff\napproach: pendente'
  ok: record gravado (depth=deep, brief=3/3 marcadores, approach=pendente)
  ```
- Grava decision record (com `expires_at` = ts+4h) + linha `decision` no JSONL via `JSON.stringify` (nunca concatenação manual). Idempotente por sessão — o re-decide preserva o `flags[]` existente do record anterior, fazendo merge mesmo quando workflow/mode mudam (S-1708).
- **Exit codes:** 0 ok · 1 validação (mensagem clara no stderr, inclui a recusa de brief plan-gated) · 2 ambiente quebrado (instrui `maestro doctor`).

### `maestro status`
- Mostra: decisão da sessão corrente, kill-switch, últimos 5 eventos do log.

### `maestro log [--summary]`
- `--summary`: agrega o JSONL → taxa de decisões automáticas vs. `override_manual`, distribuição de modelos por tarefa (o instrumento do baseline do brief).

### `maestro brief` (E8/S-801)
- Bash puro (sem Bun — o antídoto do cold start não pode depender de runtime).
- Sem flag: lê com veredito de freshness (`FRESCO`/`STALE — N commit(s)`/fora de
  git) e imprime a narrativa. Brief ausente é informativo, exit 0.
- `--write` (narrativa via stdin ou `--file`, cap 16KB) e `--auto` (esqueleto
  determinístico do git) carimbam ts/epoch/HEAD/wtree(S-701)/session e gravam
  atômico em `$MAESTRO_HOME/briefs/` (DATA_MODEL §7). `--path` só o caminho.
- Exit: 0 ok · 1 validação (narrativa vazia, flag/session malformada) · 2 ambiente.

### `maestro habits` (E9/S-903)
- Os mesmos sensores do hook pós-edição (motor único `hooks/lib/habit-sensors.awk`),
  sobre o diff vs HEAD + untracked (default), `--all` (repo inteiro, exige git) ou
  caminhos explícitos. Respeita `habits:` do `.maestro.yaml`.
- Achado sai como `arquivo:linha: smell — detalhe`, com os guias dos smells distintos
  ao final (sensor + guia, sempre juntos). Exit: 0 limpo · 1 achados · 2 ambiente.
- **S-905 (catraca):** `--baseline` grava `.maestro-habits.tsv` (smell → contagem,
  versionado no projeto). Com o arquivo presente, `--all` compara e reprova (exit 1)
  APENAS smell acima do baseline; igual passa; melhora imprime o convite a regravar.
  Escopos diff/caminho ignoram o baseline (a régua é do repo inteiro).

### `maestro consent` · `maestro outcome` · `maestro retro` (E10)
- `consent --grant <routing-table|roster|ops> [--ttl 1min–4h]` / `--revoke` / sem flag
  lista. `routing-table`/`roster` levantam a denylist do gate; `ops` (S-1006) rebaixa o
  BLOQUEIO do pre-bash-guard para aviso auditado quando TODAS as categorias são
  operacionais (privilege_escalation, container_destructive, kubectl_delete) — destruição
  de dados bloqueia integral mesmo com consent. hooks/bin/src jamais consentíveis
  (ADR-003 v1.2). Fail closed; auditado.
- `outcome --session <id> <accepted|rework|reverted> [--suite pass|fail]` — fecha a
  decisão com o desfecho (DATA_MODEL §3 v1.5). Exige record existente.
- `retro [--days N]` — relatório determinístico de calibração (override rate, gates,
  smells, desfechos, workflows sem uso) + critério codificado de promoção warn→block.
  Consumidor: `/maestro:retro`, que propõe e (com consentimento) aplica diffs, com
  suíte + eval-on-diff como exame antes do commit.
  **Emenda E18/S-1801 (2026-09-01):** a linha de decisões sai como `override
  roteável: M · não-roteável: K`; a taxa, o sinal ≥20% e a promoção warn→block
  usam só M (comandos que casam com alvo `skill:` de binding ou nome de workflow,
  derivados da routing table; tabela ilegível degrada para a contagem antiga com
  aviso).


### `maestro docs` (E16)
- Veredito por doc canônico: FRESCO ou `STALE — N commit(s)` desde
  max(último commit no doc, `reviewed:`); quitação por emenda OU re-atestado.
  `--baseline`/`--check` = catraca (só drift novo reprova). Acusa ausente/sem
  covers/fan-out. Sensor `doc-governed` no habit hook faz o reforço tardio.

### `maestro order` (E15)
**Emenda E18/S-1802 (2026-09-01):** o label canônico de evidência é `order-<n>` SEM zeros (o nome do arquivo `NNN.md` é acolchoado, o label não); a sugestão no contrato da ordem é derivada da mesma fórmula do leitor, e o leitor tolera recibo gravado como `order-00n` — avalia ambos os candidatos até um provar.

- `--create --title t [--branch b] [--frozen "a/ b/"] [--budget-*] [--project d]`
  (corpo via stdin) · `--list` · `--status N` · `--accept N`. Estado derivado de
  git + ledger (§8) + aceite; `--accept` exige `provada` (exit 1 sem prova). O
  session-start compila frozen zones de ordens pendentes na política do gate:
  autônomo bloqueia na zona, direto avisa; aceite descongela.

### `maestro decide` — flags de orçamento (E14)
- `--max-steps N` (1–500) · `--max-min N` (1–1440) · `--max-cents N` (1–100000): caps
  inteiros gravados em `budget` (DATA_MODEL §3 v1.6). O gate avisa UMA vez por cap
  estourado (steps por contador próprio; minutes pelo ts do record) e NUNCA bloqueia;
  `status` exibe; `retro` conta `budget_warn` na janela.

### `maestro conduct` (E17/S-1702)
```
maestro conduct --session <session_id>
                [--flag "sev|decisao|tradeoff|mitigacao"]...   # repetível, append
                [--approach "..."]
```
- Verbo de MUTAÇÃO do decision record (precedente: mesmo padrão de `maestro outcome`,
  roda pós-decide). Exige record existente para a sessão — sem record, exit 1.
- `--flag`: quatro campos separados por `|`, na ordem `sev|decisao|tradeoff|mitigacao`.
  `sev ∈ {critical|high|medium|low}` (fora do enum → exit 1); `decisao`/`tradeoff`/
  `mitigacao` truncados em **120 caracteres** com aviso (mesmo teto do `reason`). Cada
  `--flag` é um append em `flags[]` (DATA_MODEL §3 v1.7) — nunca substitui as anteriores.
- `--approach`: substitui `brief.approach` do record (≤200 chars, truncado com aviso).
  É o único jeito de sair de `approach: pendente` — o `decide` não reescreve brief depois
  de gravado.
- **Regra de soberania:** flag que contesta decisão já coberta por um ADR existente é
  responsabilidade do DIRETOR fechar citando o ADR (`--flag "medium|...|...|fechado por
  ADR-003"`, por exemplo) — o CLI não interpreta o conteúdo da flag, só valida forma;
  a sessão nunca reabre uma decisão de ADR sozinha.
- Grava evento `conduct` no vocabulário fechado do log (chave `session_id`, jamais o
  texto de `--flag`/`--approach` — mesma fronteira do `reason` no §4 do DATA_MODEL).
- `maestro doctor` valida o schema de `flags[]` a cada rodada (sev fechado, campos sob
  teto) e emite **WARN** (nunca reprova) quando um record tem `outcome` (S-1001)
  registrado com `brief.approach` ainda `"pendente"` — desfecho fechado sem approach é
  partitura incompleta, não erro estrutural.
  ```
  $ maestro conduct --session abc123 --flag "high|cache local sem TTL|pode servir dado velho|TTL de 5min adicionado" --approach "cache com TTL curto; revisitar se latência subir"
  ok: 1 flag registrada (sev=high); approach atualizado
  $ maestro doctor
  ...
  warn: record abc123 tem outcome=accepted com brief.approach=pendente
  ```
- **Exit codes:** 0 ok · 1 validação (record ausente, sev fora do enum, sem `--flag`/
  `--approach`) · 2 ambiente quebrado.

### `maestro evidence` (E13)
- `--record [--label l] -- <cmd>`: roda o comando no projeto e grava o recibo
  (DATA_MODEL §8); o exit do CLI espelha o do comando. Leitura (default) imprime
  VÁLIDA/VENCIDA nomeando o motivo; `--check` sai 1 quando não-válida.
- Consumidor: `outcome --suite pass` cita evidência válida ou avisa "palavra de honra"
  (`suite_evidence` no record). Live-dispatch E2E em `tests/e2e/` (tier manual/pago).

### `maestro graph` (E11)
- Freshness do grafo graphify sem carimbo: mtime de `graphify-out/graph.json` vs último
  commit. `--check` sai 1 apenas em STALE (gatilho de `bin/maestro-graph-refresh`, a
  rotina de operador via crontab — único lugar onde `claude` headless é aceitável; hooks
  seguem sem rede). A injeção emite a linha `grafo:` na seção `## Projeto` só quando o
  grafo existe; STALE manda desconfiar, nunca consultar.

### `maestro upgrade` (E19/S-1902)
- `maestro upgrade`: fetch forçado (ignora o intervalo) e `merge --ff-only` para
  `origin/main`. Em dia → mensagem, exit 0. Bloqueado → explica o motivo (à frente:
  "máquina de desenvolvimento: git push, não pull"; suja; branch; merge em andamento),
  exit 1. Aplicou → evento `upgrade` (`via=manual`), imprime `vX → vY (N commit(s))`, o
  delta do `CHANGELOG.md` entre as duas versões, a linha de rollback, e faz `exec
  bin/maestro doctor --ci` no binário NOVO (só quando o clone atualizado é o próprio
  plugin). Falha de ambiente (não é clone git, sem `origin`, sem `origin/main` conhecido)
  → `die env`, exit 2.
- `--check [--force]`: só mede e imprime uma linha; nunca aplica. Exit 0 em dia/desligado,
  1 disponível/bloqueado, 2 falhou. Sem `--force` honra o intervalo (não vai à rede) e a
  linha DIZ isso: `em dia (vX) — cache do último fetch; --force consulta o origin`; fetch
  falho também é confessado na linha (v1.11.2, achado do Legatus: afirmação sobre o remoto
  sem consultar o remoto contrariava o princípio "silêncio nunca é atualizado"). No doctor,
  "último fetch há Nh" conta a partir de `fetched`, nunca de `checked`.
- `--rollback`: `git reset --keep <prev>` para o SHA gravado pelo último upgrade
  (recusa se perderia alteração local, e recusa — `diverged` — se houver commit local
  depois do upgrade: a ferramenta não desfaz trabalho de gente); evento `upgrade` com
  `via=rollback`; o estado gravado depois é o MEDIDO de novo; exit 1 sem upgrade
  registrado.
- Concorrência: o merge só acontece se o HEAD ainda é o que foi medido; outra sessão
  chegando antes devolve `raced` sem tocar o `prev` do rollback. `check_upstream` do
  doctor honra `MAESTRO_UPDATE_REPO` (a mesma costura da lib).
- `--snooze`: adia o aviso da versão remota atual (24h → 48h → 7 dias, escalonado por
  versão); não muda o estado.
- `--set chave=valor`: `update_check` (true|false), `auto_upgrade` (true|false),
  `update_interval_hours` (1..720) em `$MAESTRO_HOME/config.yaml`.
- `update_check: false` e `MAESTRO_NO_UPDATE_CHECK=1` desligam só a checagem automática:
  o comando manual sempre roda (`UPD_MANUAL=1`). Costuras de teste: `MAESTRO_UPDATE_REPO`,
  `MAESTRO_UPDATE_REMOTE`, `MAESTRO_UPDATE_BRANCH`, `MAESTRO_UPDATE_INTERVAL`.

### `maestro doctor`
**Checagem S-1709 (E17):** `doctor` compara `meta.repository.revision` de `docs/assets/architecture.json` (quando o projeto o declara) com o commit da última tag git — divergência é warn acionável ("regenere com archify"), ausência é skip; nunca falha o doctor.

- Valida: schemas YAML/JSON, hooks registrados no settings do Claude Code, permissões, versão de Bun.
- **Emenda E7 (S-705/S-706):** grava o envelope `maestro.capabilities.v1` e o snapshot de
  resolução de bindings em `$MAESTRO_HOME` (DATA_MODEL §6); detecta
  `binding-resolution-drift` (aviso) e divergência do vendor/ contra
  `config/vendor.sha256` (falha de validação). `decide|status|log` sem Bun degradam
  citando o envelope ("último doctor: <ts>"; ≥24h = "envelope velho").
- **Emenda E7 (S-710):** compara a cópia do plugin registrada em
  `$MAESTRO_PLUGINS_DIR` (default `~/.claude/plugins`) com este repo e avisa
  `instalação do plugin` quando os arquivos de comportamento divergem — nunca falha; o
  fato vai ao envelope em `install.{registered,divergent,repo_is_live}`. A severidade segue
  quem executa: com marketplace `source: directory` apontando para o repo, a cópia em cache
  é inerte e a linha é `ok`.
- **Emenda S-2101 (v1.13.0):** hooks esperados passam a ser 6 (Stop).
- **Emenda S-1811 (v1.11.1):** hooks esperados passam a ser 5 (SessionEnd).
- **Emenda E9:** hooks esperados passam a ser 4 (PostToolUse do habit hook);
  todo sensor do motor precisa de guia em `config/habit-guides/` (`fail_val` sem).
- **Emenda E8:** valida cabeçalho e epoch de todo brief em `$MAESTRO_HOME/briefs/`
  (malformado é warn nomeando o arquivo); o SessionStart emite a seção `## Projeto`
  (ponteiro do brief + freshness barata por HEAD + `memória:` do
  `memory_container` + cobrança S-803) — nunca a narrativa, só a garantia.
- **Emenda E19 (S-1903):** `check_update_state` lê `$MAESTRO_HOME/update-state` — disponível
  → warn com `maestro upgrade`; falhou, ou último fetch bem-sucedido há mais de 7 dias →
  warn ("silêncio não é 'atualizado'"); bloqueado → ok nomeando a máquina de
  desenvolvimento; ausente → ok ("a primeira sessão verifica"). `check_upstream` (sem rede):
  commits à frente de `origin/main` sem push e `main` sem upstream viram warn. O envelope
  `capabilities.json` ganha `update.{result,local,remote}`. Nunca falha o doctor.

## 3. Envelope de erro (CLI)

stderr, uma linha, prefixo fixo: `maestro: <categoria>: <mensagem> (fix: <ação>)`
Categorias: `config`, `validation`, `env`. Nunca stack trace em uso normal (`--debug` habilita).

## Flags para o orchestrator

Nenhuma.
