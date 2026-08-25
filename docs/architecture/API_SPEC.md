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

### `hooks/log-stop.sh` — evento Stop (opcional, v1.1)
- Fecha o ciclo no log (`event: session_end`), computa contagens da sessão.

## 2. Contrato do CLI

### `maestro-decide`
```
maestro-decide --session <session_id>          # OBRIGATÓRIO — valor injetado pelo SessionStart
               --workflow <fix|feature|refactor|ship|audit|custom>
               --mode <direct|subagent|multi>
               [--agents a,b,c] [--reason "..."]
```
- Valida contra `routing-table.yaml` (workflow precisa existir; `mode≠direct` exige `--agents`; agentes precisam existir no roster). `--reason` truncado em **120 caracteres** com aviso (mitigação de vazamento de prompt).
- Grava decision record (com `expires_at` = ts+4h) + linha `decision` no JSONL via `JSON.stringify` (nunca concatenação manual). Idempotente por sessão.
- **Exit codes:** 0 ok · 1 validação (mensagem clara no stderr) · 2 ambiente quebrado (instrui `maestro doctor`).

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

### `maestro graph` (E11)
- Freshness do grafo graphify sem carimbo: mtime de `graphify-out/graph.json` vs último
  commit. `--check` sai 1 apenas em STALE (gatilho de `bin/maestro-graph-refresh`, a
  rotina de operador via crontab — único lugar onde `claude` headless é aceitável; hooks
  seguem sem rede). A injeção emite a linha `grafo:` na seção `## Projeto` só quando o
  grafo existe; STALE manda desconfiar, nunca consultar.

### `maestro doctor`
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
- **Emenda E9:** hooks esperados passam a ser 4 (PostToolUse do habit hook);
  todo sensor do motor precisa de guia em `config/habit-guides/` (`fail_val` sem).
- **Emenda E8:** valida cabeçalho e epoch de todo brief em `$MAESTRO_HOME/briefs/`
  (malformado é warn nomeando o arquivo); o SessionStart emite a seção `## Projeto`
  (ponteiro do brief + freshness barata por HEAD + `memória:` do
  `memory_container` + cobrança S-803) — nunca a narrativa, só a garantia.

## 3. Envelope de erro (CLI)

stderr, uma linha, prefixo fixo: `maestro: <categoria>: <mensagem> (fix: <ação>)`
Categorias: `config`, `validation`, `env`. Nunca stack trace em uso normal (`--debug` habilita).

## Flags para o orchestrator

Nenhuma.
