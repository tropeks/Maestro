# ARCHITECTURE.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.1 — 2026-08-08 (emendas review Opus)
**Consome:** PROJECT_BRIEF.md | **Consumido por:** security-architect, architect-orchestrator, vibe-code

---

## Visão geral

O Maestro é uma camada de roteamento e política sobre o Claude Code: um **plugin local** composto de hooks determinísticos, uma routing table declarativa, um roster de agentes e wrappers curados sobre packs upstream (superpowers, gstack). Ele não substitui nada — decide *o que* ativar, *quem* executa e *com qual modelo*.

```
[Usuário (RC/terminal)] --(prompt natural)--> [Claude Code sessão]
[SessionStart hook] --(injeta)--> [routing table + profile do projeto + roster]
[Claude sessão] --(decide via routing table)--> [maestro-decide CLI] --(grava)--> [decision record]
[PreToolUse hook] --(verifica decision record)--> [permite/bloqueia Edit|Write]
[Claude sessão] --(Task tool)--> [subagentes do roster (.claude/agents/*.md, model por perfil)]
[Todos os hooks] --(metadados)--> [~/.maestro/logs/routing.jsonl]
```

---

## ADRs

### ADR-001 — Formato de distribuição: plugin Claude Code local
**Status:** Aceito.
**Contexto:** precisa empacotar hooks + agents + skills-wrapper + config juntos, versionado, instalável.
**Decisão:** estrutura de **plugin do Claude Code** num repo git próprio (`maestro/`), instalado localmente (marketplace pessoal `/plugin marketplace add <repo>` ou symlink). Single-user.
**Alternativas:** pasta solta em `~/.claude/` (rejeitada: sem versionamento coeso nem caminho pra fase 2); MCP server (rejeitada na v1: complexidade sem ganho — vira fase 2 no orchestrator).
**Consequências:** upgrade/rollback via git; caminho natural para publicação futura.

### ADR-002 — Roteamento de intenção: LLM da sessão guiado por routing table declarativa
**Status:** Aceito.
**Contexto:** interpretar comando natural → workflow é probabilístico; brief exige "trilhos determinísticos, IA nas bordas".
**Decisão:** a decisão é do **Claude da própria sessão**, guiado por uma routing table (YAML) injetada no SessionStart. Sem classificador separado, sem chamada extra de modelo.
**Alternativas:** classificador Haiku dedicado (rejeitado v1: latência+custo+infra); regex/keywords determinístico (rejeitado: exatamente a rigidez que motivou o projeto).
**Consequências:** qualidade do roteamento = qualidade da routing table; erros são corrigíveis editando YAML (e, na v2, sugeridos pelo task-observer a partir dos logs).

### ADR-003 — Gate estrutural: decisão registrada antes de editar código
**Status:** Aceito.
**Contexto:** não dá pra impor "sempre subagentes" (há tarefas triviais e tarefas não-delegáveis); mas pular a *decisão* é o que causa a dor atual.
**Decisão:** hook **PreToolUse** intercepta `Edit|Write|MultiEdit` em arquivos de código e exige que exista um **decision record** da sessão (gravado via `maestro-decide`). Sem record → bloqueia com mensagem instruindo a decidir. `MAESTRO_OFF=1` desativa tudo.
**Alternativas:** bloquear edição direta sempre (rejeitado pelo usuário no G0); só instruir via prompt (rejeitado: é o status quo que falha).
**Consequências:** overhead de 1 comando por tarefa; auditabilidade total; o log do gate É o instrumento de medição do baseline.
**Emenda v1.1 (review Opus):** o gate é honestamente **anti-descuido/best-effort** — cobre Edit/Write/MultiEdit mas não Bash (`tee`, `git apply`, redirecionamentos); escapes são medidos, não perseguidos na v1. Rollout: **modo warn na primeira semana** de dogfood (loga sem bloquear), decisão warn vs. block com dados reais. Decision record tem **TTL de 4h** (limpo no SessionStart e no doctor) para não sobreviver a `--resume`. A política do gate (allowlist/denylist) é **por caminho + extensão**, com denylist explícita protegendo o próprio Maestro (plugin, roster, routing table), `.github/workflows/` e configs executáveis — o roteador não reescreve as próprias regras.

### ADR-008 — Sinal observável de override manual
**Status:** Aceito (v1.1, review Opus).
**Contexto:** a métrica principal (% de override manual) não era produzida por nenhum caminho observável.
**Decisão:** hook **UserPromptSubmit** detecta prompt iniciando com `/` (invocação manual de comando de workflow) e loga `override_manual` contendo **apenas o nome do comando** — vocabulário fechado, nunca o texto do prompt. `edits_per_decision` também é derivada (contagem de `gate_pass` por decision record) para detectar um record único liberando sessão inteira.
**Consequências:** métrica sai de evento determinístico; custo ~zero (prefixo-match em bash).

### ADR-004 — Roster de agentes com hierarquia de senioridade e especialização por linguagem
**Status:** Aceito.
**Contexto:** tiering de custo (Haiku↔Opus) + especialização por linguagem do portfólio (Go, Python, TS/React, SQL).
**Decisão:** agentes nativos `.claude/agents/*.md` com `model` no frontmatter e ferramentas mínimas por papel (padrão VoltAgent). Roster inicial: `dev-junior` (haiku), `dev-pleno` (sonnet), `engenheiro` (sonnet, opus sob demanda), `qa` (sonnet+browser), `revisor` (sonnet, read-only), + especialistas `golang-pro`, `python-pro`, `typescript-pro`, `postgres-pro` vendorizados/curados de wshobson e VoltAgent.
**Alternativas:** instalar coleção inteira (rejeitado: polui o gate — o problema que o Maestro resolve).
**Consequências:** ~9 agentes; prompts upstream adaptados carregam atribuição de licença no cabeçalho.

### ADR-005 — Autenticação/autorização
**Status:** Aceito.
**Decisão:** **N/A** — ferramenta local single-user; a superfície de auth é a da própria máquina/conta Claude. Nenhum segredo próprio; hooks herdam o ambiente. (Registrado para destravar security-architect.)

### ADR-006 — Multi-tenancy
**Status:** Aceito. **Decisão:** single-user para sempre na v1 (explícito, contrato §7). Fase 2 (QM/multi-usuário) revisita.

### ADR-007 — Sistema de memória único
**Status:** **Proposto** (Open Question do brief).
**Decisão provisória:** testar **claude-mem** primeiro (instalação por projeto, não global), por integração via hooks — mesmo mecanismo do Maestro. GBrain fica como alternativa se claude-mem conflitar com os hooks do Maestro (ambos usam SessionStart/PostToolUse — ordem de execução a validar no spike da Fase 1).
**Flag:** decisão final trava no fim da Fase 1.

---

## Componentes

| Componente | Responsabilidade | Depende de | Modo de falha | Nota |
|---|---|---|---|---|
| `hooks/session-start` | injetar routing table + profile + roster resumido | config YAML | falha → sessão sem Maestro (degrada, não bloqueia) | bash/TS |
| `hooks/pre-tool-gate` | exigir decision record antes de Edit/Write em código | decision record | falso positivo bloqueia trabalho → kill-switch | < 50ms |
| `bin/maestro-decide` | gravar decision record (workflow, modo, agente, modelo) | — | — | 1 linha JSON |
| `config/routing-table.yaml` | mapear intenção → workflow → perfil | — | tabela ruim = roteamento ruim | editável, versionada |
| `.maestro.yaml` (por repo) | profile do projeto (linguagens, pipeline, experts ativos) | — | ausente → defaults globais | opt-in por projeto |
| `agents/*.md` | roster (senioridade + linguagem) | — | — | ferramentas mínimas por papel |
| `logs/routing.jsonl` | metadados de cada decisão/bloqueio | hooks | — | base do baseline; sem conteúdo de prompt |
| wrappers de packs | descrições curadas, gstack `--prefix` | packs vendorizados | drift upstream | atualização manual deliberada |

## AI Touchpoints

| Caso de uso | Classe de modelo | Ponto de entrada | Gate de confiança | Fallback | Custo |
|---|---|---|---|---|---|
| Interpretação de intenção → workflow/modo/agente | o Claude da sessão (sem chamada extra) | routing table injetada | gates humanos em plano e ship | usuário invoca comando manualmente (sempre disponível) | zero adicional |
| Sugestão de ajuste da routing table (v2) | Sonnet batch | logs JSONL | aprovação humana (task-observer) | edição manual do YAML | baixo |

Sem outros usos de IA. `ai-architect` **não é necessário** — o AI Touchpoint é trivial e já especificado aqui. (Flag ao orchestrator.)

## Security Touchpoints

| Decisão | Implicação | Dono downstream |
|---|---|---|
| Hooks executam bash no ambiente do usuário | supply chain: só código do repo próprio roda; packs vendorizados são pinados por commit | security-architect |
| Logs JSONL | nunca logar conteúdo de prompt/código — só metadados (intent classificada, workflow, agente, timestamp) | security-architect |
| Agentes com ferramentas mínimas | revisores read-only; só dev-* têm Write/Bash | security-architect |
| Kill-switch `MAESTRO_OFF=1` | recuperação garantida de hook defeituoso | — |
| Guardas destrutivos em fluxo autônomo | política tipo `/careful` ativa quando modo = subagentes autônomos | security-architect |

## NFRs

- Overhead dos hooks: < 100ms por invocação (percebido zero no fluxo)
- Injeção do SessionStart: ≤ ~2k tokens (routing table + roster resumido) — o Maestro não pode causar o inchaço que combate
- Zero dependência de rede em runtime (tudo local)

## Flags para o orchestrator

- ADR-007 (memória) em status Proposto — trava no fim da Fase 1.
- `ai-architect` dispensado (AI touchpoint trivial, especificado acima).
- `ux-architect` dispensado (sem UI — interface é o próprio Claude Code/RC).
- `devops-homelab` dispensado (nada a deployar; roda na máquina local).
