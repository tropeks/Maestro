---
covers:
  - bin/maestro
  - hooks/*.sh
reviewed: b13eed1
---
# API_SPEC.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.2 — 2026-09-05 (emendas E22/E23: hooks `pre-agent`/`subagent-stop`, `maestro intent`, `maestro verify`, `maestro delegation`, canal do `upgrade`)
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
- **Também:** limpa decision records expirados (TTL 4h) e **recompila a política do gate** (`$MAESTRO_GATE_POLICY`, default `~/.maestro/gate-policy.sh`) a partir do YAML — fonte de verdade única.
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
  **S-2303 (E23c):** no canal `stable` (default) o candidato do ff-only é o commit da
  tag `stable`, não o topo do `origin/main`; sem a tag no remoto o estado é `no-stable`
  e a injeção diz `atualização: canal stable, e o origin ainda não tem a tag 'stable' —
  auto-update parado; maestro upgrade --channel main pega o topo` (auto-update parado
  é fato que a sessão precisa saber; silêncio seria a staleness muda do E19).
- **Emenda E22 (S-2203):** a seção `## Projeto` ganha a linha `direção:`, em três
  formas: `INTENT vN (.maestro/INTENT.md) → plano cita a seção da direção que serve` ·
  `INTENT sem carimbo → maestro intent --check` · `nenhuma → maestro intent --init
  (E22)`. Um awk sobre as 8 primeiras linhas do arquivo (só `version:`); nenhum sha256
  no hot path; ponteiro, nunca o conteúdo da direção. Ausência é FATO reportado, nunca
  silêncio. O texto do gate plan passa a cobrar "o plano cita a direção (INTENT vN,
  seção) — sem direção, diga que não há". Ratchet da injeção deliberadamente bumpado
  6930 → 7080 bytes. As frozen zones de ordens pendentes passam a ser lidas em 20
  linhas de cabeçalho (E22/S-2202), não 14.

- **Emenda E25 (S-2501/S-2502):** duas mudanças na injeção.
  (a) A instrução canônica ganha UMA linha ensinando o desfecho do descarte (`maestro
  outcome --session <id> killed --reason "…"`) — sem ela o verbo novo do CLI seria letra
  morta, porque o preâmbulo é o único lugar onde a sessão aprende o vocabulário.
  (b) `.maestro.yaml` passa a aceitar `preamble: full|standard|lean` (DATA_MODEL §2):
  `full` é o default e a ausência da chave produz saída **byte a byte idêntica** à de
  antes; `standard` omite `## Rotas`; `lean` omite também `## Heurísticas` e `## Roster`.
  O corte acontece ANTES do laço de orçamento (é escolha do projeto, não aperto de teto) e
  o cabeçalho — que nunca trunca — nomeia o tier e o que ficou de fora, com ponteiro para
  `config/routing-table.yaml` e `agents/`; valor fora do enum degrada para `full` e o diz.
  Ratchet da injeção bumpado deliberadamente por (a), no mesmo commit, conforme o
  protocolo no cabeçalho de `tests/hooks/test-injection-budget.sh`.

- **Emenda E26 (S-2601):** a política do gate passa a ser gravada em
  `${MAESTRO_GATE_POLICY:-$MAESTRO_HOME/gate-policy.sh}` — **o mesmo caminho que o
  `pre-tool-gate.sh` sempre leu**. Enquanto a escrita ignorava a variável, o arquivo era
  único e global: abrir sessão no projeto B sobrescrevia a política da sessão VIVA do
  projeto A (modo do gate, `MAESTRO_GATE_ORDER_FROZEN` da ordem em execução e
  `MAESTRO_PLUGIN_ROOT`), e A passava a ser policiada pelas regras de B, em silêncio. Sem
  a variável, caminho e conteúdo são byte a byte os de antes — nenhuma instalação muda de
  comportamento por atualizar. Valor aceito: caminho **absoluto, sem espaço nem quebra de
  linha**; torto degrada para o padrão com aviso no stderr. O diretório é criado se
  faltar; o temporário é irmão do destino (o `mv` atômico exige o mesmo sistema de
  arquivos). Motivação: mais de um gerente na mesma máquina, cada um com o seu escopo.

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

### `hooks/pre-agent.sh` — evento PreToolUse, matcher `Agent|Task` (E23a/S-2301)
- **Lê:** os primeiros 4096 bytes do stdin. `session_id` por regex
  (`CLAUDE_SESSION_ID` como fallback) e `subagent_type` do payload
  (`"subagent_type":"([^"]{1,64})"`), sem o prefixo `maestro:`, aceito só se casar
  `^[a-z0-9-]+$`. O `prompt` e a `description` do Task **nunca** são lidos — nem para
  log, nem para decisão.
- **Emite:** `delegation phase=started session_id=<id> [agents=<agente>]`. Sem
  `session_id` tipado não há evento (o funil correlaciona por sessão; logar solto seria
  ruído).
- **Erros:** sempre exit 0 — observador, nunca gate. Kill-switch, stdin em
  tty/vazio/lixo, sessão fora do tipo, lib ausente: sem evento, sem ruído. Nada em
  stdout (stdout de PreToolUse é canal de decisão do Claude Code). Bash puro, sem jq,
  sem Bun, sem rede; NFR <100ms. Registrado em `hooks/hooks.json` com `timeout: 5`.
- **Degradação declarada:** prompt gigante pode empurrar o `subagent_type` para fora da
  janela de 4096 bytes — o evento sai sem `agents`, nunca com pedaço de texto.

### `hooks/subagent-stop.sh` — evento SubagentStop (E23a/S-2301)
- **Lê:** mesma janela e mesma extração de sessão; `agent_type` (ou `subagent_type`,
  por simetria com o PreToolUse) quando o payload traz. Nunca o transcript nem o
  resultado do subagente.
- **Emite:** `delegation phase=received session_id=<id> [agents=<agente>]`. Sempre exit
  0, nada em stdout, `timeout: 5` no `hooks.json`.
- **Doctor:** `check_hooks_registry` passa a exigir **7 eventos** (SessionStart,
  PreToolUse, UserPromptSubmit, PostToolUse, SessionEnd, SubagentStop, Stop) e os dois
  hooks novos entram na contagem de `commands` que precisam resolver para script
  executável.

### `hooks/user-prompt-submit.sh` — evento UserPromptSubmit (ADR-008)
- Prompt inicia com `/` → log `override_manual` com **apenas o nome do comando** (vocabulário fechado). Sempre exit 0; nunca altera o prompt.

### `hooks/session-end.sh` — evento SessionEnd (S-1811, v1.11.1)
- **Lê:** `session_id` do stdin (regex; `CLAUDE_SESSION_ID` como fallback) e o decision
  record `$MAESTRO_HOME/sessions/<id>.json`, só por presença: `workflow` presente →
  `decided=yes`; `outcome` ∈ accepted|rework|reverted|killed → `settled=yes` (**emenda
  E25/S-2501:** `killed` fecha a sessão como qualquer outro desfecho — decidir NÃO
  construir é decisão tomada, não decisão pendente).
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
  plan-gated (`feature`/`refactor`) SEM desfecho e com `approach: pendente` no brief →
  `plan`; `ship` sem desfecho → `ship`. Sem gate: apaga o arquivo do pane (resolvido por
  outro caminho) e sai. **Emenda E25/S-2501:** desfecho aqui inclui `killed`, e a guarda
  vale para os DOIS gates — matar uma feature antes do plano aprovado é o kill mais
  comum, e sem isso o herdr seguiria perguntando "Aprovo o plano?" (no telefone
  inclusive) sobre trabalho já descartado. A essência é extraída **ancorada ao campo
  `brief`**: o record tem outros campos de texto do diretor (`reason`, `kill_reason`) e
  um deles contendo a substring `essencia:` sairia da máquina pela ponte.
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
- **Emenda E23d/S-2304:** no escopo `--all`/`--baseline`, respeita também
  `habits_ignore:` (prefixos relativos à raiz; default vazio). Caminho explícito não é
  filtrado — pedir por nome é decisão de quem pede. Quando algo é filtrado, a saída ganha
  `habits_ignore: N arquivo(s) fora do escopo (.maestro.yaml)` antes do veredito: filtro
  que esconde em silêncio é armadilha. O motor não emite achado em corpo de heredoc de
  arquivo shell — vale igual para o hook `post-edit-habits.sh`, que é o mesmo awk. O
  contrato de exit não muda (0 limpo · 1 achados · 2 ambiente).
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
- `outcome --session <id> <accepted|rework|reverted> [--suite pass|fail] [--unproven]`
  — fecha a decisão com o desfecho (DATA_MODEL §3 v1.5). Exige record existente e `jq`.
  **Emenda E23a/S-2301:** `accepted` com record em `mode ∈ subagent|multi` exige ≥1
  `delegation phase=started` da sessão no log; sem ela, **exit 1** citando `maestro
  delegation --session <id>` e a alternativa `--unproven`, e o record não é tocado. Com
  prova, carimba `delegation_proof: started`; com `--unproven`, `none`. `mode: direct`
  não exige nada e não grava o campo.
  **Emenda E23b/S-2302:** `accepted` também recusa (exit 1, `sem verificação
  obrigatória: …` + o comando de cada rótulo faltante) quando o working tree contra
  `merge-base(main|master, HEAD)` toca área com verificação obrigatória sem recibo
  VÁLIDA. `--unproven` passa e grava `verifications: "missing"`; o caso normal com áreas
  exigidas grava `"cited"`; sem áreas exigidas o campo não existe. `rework`/`reverted`
  nunca são barrados — só o aceite afirma que a entrega serve. O aviso de honra do
  `--suite pass` continua para o rótulo `suite` quando ele não é exigido por área.
  **Emenda E25/S-2501:** o enum vira `accepted|rework|reverted|killed`. `killed` EXIGE
  `--reason "<por quê>"` (≤120 chars, truncado com aviso — precedente do `reason` do
  `decide`) e grava `kill_reason` no record (DATA_MODEL §3 v1.9); `--reason` com outro
  desfecho e `--suite` junto de `killed` são **exit 1**. `killed` não passa pelos gates de
  delegação e de verificação e não grava os campos deles — os dois existem porque o
  ACEITE afirma que a entrega serve, e no descarte não há entrega. Desfecho é last-wins,
  então gravar qualquer outro veredito sobre um record morto **apaga** `kill_reason`. O
  log recebe `outcome=killed` e **nunca** o texto do porquê. A saída aponta a seção `##
  Fora de escopo` do `.maestro/INTENT.md` (E22) como o lugar onde o kill sobrevive à
  sessão — aponta e não escreve: o INTENT é versionado e o hash do corpo é contrato.
- `retro [--days N]` — relatório determinístico de calibração (override rate, gates,
  smells, desfechos, workflows sem uso) + critério codificado de promoção warn→block.
  Consumidor: `/maestro:retro`, que propõe e (com consentimento) aplica diffs, com
  suíte + eval-on-diff como exame antes do commit.
  **Emenda E18/S-1801 (2026-09-01):** a linha de decisões sai como `override
  roteável: M · não-roteável: K`; a taxa, o sinal ≥20% e a promoção warn→block
  usam só M (comandos que casam com alvo `skill:` de binding ou nome de workflow,
  derivados da routing table; tabela ilegível degrada para a contagem antiga com
  aviso).
  **Emenda E25/S-2501 (2026-09-09):** o bloco `-- sinais:` ganha a leitura do descarte —
  com ≥1 `killed` na janela, quantos foram e onde eles sobrevivem (`## Fora de escopo` do
  INTENT); com ZERO e a janela já de calibração (≥14d, ≥10 decisões), o aviso de que nada
  foi descartado — ou o `interrogate` está aprovando tudo, ou o descarte não está sendo
  registrado. A linha `-- desfechos:` não muda: ela já agrupa por `.outcome` e passa a
  mostrar `killed: N` sozinha.


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

**Emenda E22/S-2202 (2026-09-05) — a ordem cita a direção.** `--create` carimba
`intent_version:`/`intent_hash:` quando há direção citável (DATA_MODEL §13) e anuncia
`direção: INTENT vN carimbada na ordem`; sem direção citável cria assim mesmo e imprime
`AVISO: ordem sem direção` com o comando que resolve (`maestro intent --init` quando não
há arquivo, `--check` quando há e está incompleto). O contrato gerado ganha a linha
"Direção vigente na criação: INTENT vN — o plano cita a seção da direção que autoriza
esta ordem". `--status N` mostra `direção : vN` e, se a direção subiu de versão,
`ATENÇÃO: a direção mudou (vA → vB) depois desta ordem — revise o plano contra
.maestro/INTENT.md`; mesma versão com conteúdo outro (edição sem bump) vira nota
apontando `maestro intent --bump`. `--list` marca `[direção mudou]` ao lado do status.
`--accept N` RECUSA (exit 1) sob direção desatualizada, ensinando `--intent-reviewed` —
aceitar sob direção nova é decisão NOVA do diretor, não repetição; com a flag, aceita
dizendo sob qual versão. Todo aceite (inclusive o re-aceite do S-1806) carimba
`accepted_intent: <vN>`. Ordem sem carimbo de direção nunca é acusada.

**Emenda E23b/S-2302 (2026-09-05) — o aceite exige a verificação da área.** `--accept N`
recusa (exit 1) quando o branch toca área com verificação obrigatória (`.maestro.yaml`,
DATA_MODEL §2) sem o conjunto exigido, listando `rótulo: NENHUMA|VENCIDA (motivo)` e o
comando que registra o recibo. Por rótulo: `exit=0`, `wtree_after` == árvore do tip do
branch e `cmd_match ≠ no`. `--status N` ganha `verif   : áreas <…>` e um estado por
rótulo exigido. Ordem que não toca área declarada segue na regra anterior.

**Emenda E23a/S-2301 (2026-09-05):** todo `--accept` emite também `delegation
phase=accepted` com `n` = id da ordem — a última fase do funil.

**Emenda (issue #6, 2026-09-12) — o carimbo do aceite não invalida o próprio
recibo.** `.maestro/` não entra no que a suíte prova — é estado de
governança. `bin/maestro-wtree` (DATA_MODEL §3 emenda v1.10) passa a excluir
`.maestro/**` do fingerprint em `git add -A`, então o `accepted_at`/
`accepted_session`/`accepted_tree` que este mesmo `--accept` grava em
`.maestro/orders/NNN.md` deixa de mover o `wtree_after` comparado na linha
339 e em `maestro evidence` (DATA_MODEL §8). Antes desta emenda, projeto que
rastreia `.maestro/` (E15/E22) via o próprio aceite vencer o recibo que o
autorizou — caso real: NetForge, ordem 016. Prova: `tests/cli/test-order.sh`,
falhando contra o `bin/maestro-wtree` anterior e passando com a exclusão.

### `maestro intent` (E22/S-2201)
```
maestro intent [--show|--check|--init|--bump] [--project d] [--session s]
```
- `--init`: cria `<projeto>/.maestro/INTENT.md` (v1) com o template das seis seções
  VAZIAS e o carimbo `maestro-intent v1` (`version`/`ts`/`head`/`author_session`/`hash`).
  Recusa se já existe (exit 1). O template **não passa** no `--check` de propósito:
  título não é direção.
- `--show` (default): versão, `intent_hash`, carimbo (ts/head/sessão) e o estado de cada
  uma das seis seções (`N linha(s)` ou `VAZIA`), mais a nota "conteúdo editado desde o
  carimbo vN → maestro intent --bump" quando o hash do corpo difere do carimbado. Sem
  arquivo: `sem direção — maestro intent --init`, **exit 0** (trabalhar sem direção é
  legítimo; fingir que há direção não é). Carimbo ilegível: nomeia o defeito e sai 0.
- `--check`: valida carimbo + seis seções não-vazias e lista o que falta (`direção
  INCOMPLETA (N de 6 seções): falta …`). Exit 0 ok · 1 se falta qualquer coisa
  (inclusive arquivo ausente ou carimbo ilegível). Conteúdo editado sem bump é nota, não
  reprovação — quem decide versionar é gente.
- `--bump`: conteúdo mudado → `version+1` com `ts`/`head`/`author_session`/`hash` novos e
  o CORPO copiado byte a byte; conteúdo igual ao do carimbo → recusa (exit 1) explicando
  que a versão é o que as ordens citam. Bump com direção ainda incompleta passa,
  avisando, e diz que "ordens novas nascem citando vN; as antigas passam a pedir revisão
  do plano".
- Escrita atômica (`> tmp && mv -f`). Log: evento `intent` (`n=<versão>`, `via=manual`,
  `session_id` quando informado) só nas MUTAÇÕES (`--init`/`--bump`); leitura não loga.
- **Exit codes:** 0 ok · 1 validação (direção ausente no `--check`/`--bump`, `--init`
  sobre arquivo existente, `--bump` sem mudança, carimbo ilegível no `--bump`, flag
  desconhecida) · 2 ambiente quebrado (não consigo gravar).

### `maestro verify` (E23b/S-2302)
```
maestro verify [--base REF] [--project P] [--check]
```
- Cruza o diff contra a base (default `merge-base main HEAD`, depois `master`; sem git
  ou sem ancestral → "base: nenhuma", comparando só o working tree) com o bloco
  `verifications:` do `.maestro.yaml` e imprime: a base, as áreas tocadas e, por rótulo
  exigido, a linha do `evidence` (VÁLIDA/VENCIDA/NENHUMA nomeando o motivo e o comando
  que registra o recibo — com `commands.<rótulo>` declarado, o comando REAL, não um
  placeholder).
- Projeto sem `verifications:` → uma linha dizendo isso, exit 0 (o Maestro não inventa
  dever para quem não o declarou). Nenhuma área tocada, ou área sem rótulo → idem.
- `--base` com ref inexistente → exit 1 (validação). Sem `--check` é relatório: exit 0
  mesmo faltando prova. `--check` → exit 1 se algum rótulo exigido não está VÁLIDA.
- Log: evento `verify` com `n = <faltantes>` (0 inclusive). Nunca rótulo, área ou
  caminho.

### `maestro delegation` (E23a/S-2301)
```
maestro delegation --session <id> | --all
```
- `--session <id>`: imprime o funil da sessão — `planned` / `started` / `received` /
  `accepted` — contado no `routing.jsonl` **e nos rotacionados** (`routing-*.jsonl`),
  cada linha nomeando quem a emite, mais um veredito: sem delegação registrada ·
  planejada e NÃO disparada · disparada sem retorno · delegação provada. Exit 0.
- `--all`: agrega por sessão as **últimas 20 sessões vistas** no log (ordem de primeira
  aparição), uma tabela por sessão. Exit 0.
- Sem `--session` nem `--all`, ou flag desconhecida: exit 1 com o uso.

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
- **Emenda E23b/S-2302 — o recibo casa o comando.** `--record` grava
  `cmd_match=yes|no|free` (DATA_MODEL §8) e, quando o comando não é o declarado em
  `commands.<rótulo>`, avisa na hora que "este recibo NÃO conta como verificação" — o
  exit do CLI continua sendo o do comando. A leitura reprova `cmd_match=no` ("comando
  diferente do declarado em .maestro.yaml") e `cmd_hash` divergente do sha16 do comando
  declarado hoje; com declaração, a linha de VENCIDA traz o comando exato para regravar.
  Recibo anterior ao E23b (sem a linha) é lido como `free`.

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
  `update_interval_hours` (1..720) e `update_channel` (stable|main) em
  `$MAESTRO_HOME/config.yaml`.
- **Emenda E23c/S-2303 — canal.** `--channel stable|main` sobrepõe o canal **só nesta
  chamada** (via `MAESTRO_UPDATE_CHANNEL` no próprio processo; não escreve o
  `config.yaml` — para gravar, `--set update_channel=…`); valor fora do domínio → exit 1;
  combina com qualquer modo (`--check`, `--rollback`, `--snooze`, sem flag). Canal
  `stable` sem a tag no remoto: `maestro upgrade` e `--check` saem **0** com "canal
  stable: o origin ainda não tem a tag 'stable' — nada a aplicar (a CI a move quando
  shellcheck + suíte passam numa tag `v*`; `maestro upgrade --channel main` segue o topo
  da main)"; `--snooze` responde "nada a adiar". As linhas de estado nomeiam o canal:
  `atualização: em dia (vX, canal stable)`, `atualização: vX → vY disponível (N
  commit(s), canal stable) — maestro upgrade`, `Maestro vX → vY (N commit(s), canal
  stable)`; em dia sem flags, `já é a última versão (tag stable)`. Bloqueio por `ahead`
  no canal `stable` diz "à frente da tag stable (ainda não aprovados pela CI)" em vez de
  "push, não pull". O evento `upgrade` sai com `channel` nas três vias. Costura de teste
  nova: `MAESTRO_UPDATE_CHANNEL`.
- `update_check: false` e `MAESTRO_NO_UPDATE_CHECK=1` desligam só a checagem automática:
  o comando manual sempre roda (`UPD_MANUAL=1`). Costuras de teste: `MAESTRO_UPDATE_REPO`,
  `MAESTRO_UPDATE_REMOTE`, `MAESTRO_UPDATE_BRANCH`, `MAESTRO_UPDATE_INTERVAL`.

### `maestro doctor`
**Checagem S-1709 (E17):** `doctor` compara `meta.repository.revision` de `docs/assets/architecture.json` (quando o projeto o declara) com o commit da última tag git **ou com o pai dele** (rito desde a v1.14.2: o retrato é pinado no commit de release, commitado em seguida, e a tag vai no commit do diagrama — quem está exatamente na tag já tem o retrato certo) — divergência é warn acionável ("regenere com archify"), ausência é skip; nunca falha o doctor.

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
- **Emenda S-2301 (E23a):** hooks esperados passam a ser **7** (SubagentStop).
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
- **Emenda E23c (S-2303):** `check_update_state` aceita `result=no-stable` (**warn**,
  nunca fail — "auto-update parado", com o comando que ignora o canal; `check_upstream`
  também avisa quando o clone ainda não tem a tag) e nomeia o canal nas linhas de `available` e `current`;
  estado sem `channel` é lido como `main`. `check_upstream` abre com o canal e a posição
  do HEAD em relação à tag `stable` (exatamente na tag · N atrás · N à frente · divergiu
  · tag ainda não existe neste clone) e emite warn quando `update_channel` do
  `config.yaml` está fora do domínio — tudo sem rede. `check_release_diagram` passa a
  usar `describe --tags --abbrev=0 --match 'v*'`: `stable` é ponteiro de canal, não
  release, e sem o filtro sequestraria o retrato de arquitetura.

## 3. Envelope de erro (CLI)

stderr, uma linha, prefixo fixo: `maestro: <categoria>: <mensagem> (fix: <ação>)`
Categorias: `config`, `validation`, `env`. Nunca stack trace em uso normal (`--debug` habilita).

## Flags para o orchestrator

Nenhuma.
