# DATA_MODEL.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.1 — 2026-08-08 (emendas review Opus)
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

### 2. `.maestro.yaml` (raiz de cada repo de projeto — opcional)

```yaml
version: 1
project: remedix
languages: [go, python, typescript]
experts: [golang-pro, python-pro, typescript-pro]   # subconjunto do roster ativo aqui
pipeline: default            # ou nome de workflow custom
notes: "agente Go é o coração; nunca tocar sem testes"
```
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
`# classification: confidential` — **PROIBIDO** campo com texto do prompt do usuário.

### 4. Log — `~/.maestro/logs/routing.jsonl` (append-only)

Uma linha por evento. Eventos (vocabulário fechado): `decision`, `gate_pass`, `gate_warn`, `gate_block`, `override_manual`, `killswitch`, `session_end`. Hooks emitem SOMENTE este vocabulário via `log_event` do `common.sh`; o CLI serializa com `JSON.stringify` — nunca texto livre concatenado (proteção contra JSONL malformado, review Opus).

```json
{"ts":"...","event":"decision","session_id":"abc123","workflow":"fix","mode":"subagent","agents":["golang-pro"],"project":"remedix"}
{"ts":"...","event":"gate_block","session_id":"def456","tool":"Edit","file_ext":".go"}
{"ts":"...","event":"override_manual","session_id":"def456","note":"usuario invocou comando direto"}
```
`# classification: confidential` — só metadados; `file_ext` sim, caminho completo NÃO (pode conter nome de cliente).
Rotação: por tamanho (10MB) ou mensal, arquivo `routing-YYYY-MM.jsonl`.

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

---

## Regras de integridade

- Decision record é **por sessão**: novo `session_id` = nova decisão exigida (evita record velho liberando o gate para sempre).
- Escrita do JSONL é append atômico com `flock -n` (**não bloqueante** — contenção descarta a linha com aviso no stderr; review Opus); falha de escrita **nunca** bloqueia a operação (log é subproduto, não trilho).
- `maestro doctor` valida schema do YAML e dos records; CI do repo do plugin roda o mesmo check.
- Nenhum arquivo do Maestro sai da máquina (residência local, brief §7).

## Flags para o orchestrator

Nenhuma.
