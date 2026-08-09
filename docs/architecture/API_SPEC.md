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

### `hooks/pre-tool-gate.sh` — evento PreToolUse, matcher `Edit|Write|MultiEdit`
- **Dependência declarada:** `jq` (parsing de stdin; validado pelo doctor). Fixtures adversariais em `tests/fixtures/`.
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

### `maestro doctor`
- Valida: schemas YAML/JSON, hooks registrados no settings do Claude Code, permissões, versão de Bun.

## 3. Envelope de erro (CLI)

stderr, uma linha, prefixo fixo: `maestro: <categoria>: <mensagem> (fix: <ação>)`
Categorias: `config`, `validation`, `env`. Nunca stack trace em uso normal (`--debug` habilita).

## Flags para o orchestrator

Nenhuma.
