# PROJECT_BRIEF.md
**Projeto:** Maestro (nome provisório — roteador MoE de ferramental Claude Code) | **Skill:** office-hours | **Versão:** 2.0 — 2026-08-08
**Consome:** conversa de discovery (office-hours) | **Consumido por:** system-architect, security-architect, architect-orchestrator

> Status: **Validado** (aguardando aprovação G0 para Lock)
> ⚠️ As seções deste documento são localizadas por NOME, não por número (contrato §2).
> Idioma: pt-BR (termos técnicos em inglês) — contrato §7.

---

## 1. Problem Statement

**O problema real (não a solução proposta):**

O roteador do ferramental é hoje o próprio usuário. O ambiente Claude Code do Romulo acumulou 4-5 fontes de skills (superpowers, gstack, ~15 skills próprias de arquitetura, task-observer candidato, sistemas de memória concorrentes), e cada decisão de "qual expert acionar agora" exige invocação manual dele — frequentemente pelo telefone via RC, onde digitar comandos é o maior atrito. Além disso, o modelo tenta executar trabalho de código diretamente quando o padrão eficiente é delegar a subagentes, exigindo correção de rumo manual em praticamente toda tarefa.

**Exemplo concreto:**

Romulo, do telefone, pede "corrige o bug do login". O Claude Code começa a editar arquivos direto no contexto principal. Romulo interrompe: "faz via subagentes". Depois lembra que deveria ter rodado planejamento antes, digita o comando de plan. Ao final, QA e review só rodam se ele lembrar de invocá-los. Cada tarefa carrega 1-2 intervenções de roteamento que deveriam ser automáticas.

---

## 2. Target Users

### Persona primária
- **Nome / cargo:** Romulo — analista sênior de infra de TI, construtor solo de portfólio SaaS
- **Workflow atual:** Claude Code com RC ativado (acompanha do telefone); invocação manual de skills/comandos; superpowers + comandos gstack + skills próprias + shrimp task-manager
- **Conforto com tecnologia:** Alto
- **Autoridade de decisão:** Usuário final = comprador = sponsor (projeto pessoal)

Sem personas secundárias na v1.

---

## 3. Core Capabilities (Day 1)

1. **Roteamento de intenção:** dado um comando em linguagem natural, o sistema decide sozinho o workflow (plan → build → review → QA vs. investigate → fix → review, etc.) e o dispara, sem o usuário digitar comandos de skill.
2. **Política de execução decidida pelo orquestrador:** para cada tarefa, o roteador decide o modo de execução — direto (tarefa trivial ou impossível de delegar), subagente único, ou múltiplos subagentes — e atribui a um **perfil de agente de um roster definido** (ex.: `dev-junior` em Haiku para tarefas mecânicas, `dev-pleno` em Sonnet para implementação, `engenheiro` em Sonnet/Opus para arquitetura e review, `qa` com browser). Cada perfil é um agente Claude Code (`.claude/agents/*.md`) com system prompt, ferramentas e modelo próprios. Custo proporcional à complexidade; a decisão é do sistema, não lembrada pelo usuário.
3. **Ativação seletiva de experts (MoE):** só a porção pertinente do ferramental entra em contexto — descrições curadas formam o gate; corpo da skill só carrega quando ativado.
4. **Gates aprováveis do telefone:** plano e ship pausam para aprovação humana via RC; o restante flui autônomo.
5. **Routing table por projeto:** um profile no repositório (tipo de projeto, pipeline aplicável) condiciona quais experts existem naquele contexto.

---

## 4. Explicitly Out of Scope (v1)

- QM / multi-usuário (irmão e parceiro herdam só na fase 2+)
- Publicação como plugin público / marketplace
- Telemetria e analytics de uso
- Task-observer embutido (auto-evolução das skills — candidato à v2 como "treino do gate")
- **Reescrever os packs upstream** — superpowers e gstack são dependências vendorizadas, nunca absorvidas/forkeadas profundamente
- Camada MCP dinâmica `activate(domínio, projeto)` — fase 2, como módulo do [[orchestrator]]

---

## 5. Constraints & Context

| Dimensão | Valor |
|---|---|
| **Tamanho do time** | Solo (execução via agentes Claude Code) |
| **Preferências de stack** | Mecanismos nativos do Claude Code: hooks (bash/TS), skills, plugin format; Bun onde precisar de runtime |
| **Orçamento** | Bootstrap (custo = tokens) |
| **Prazo** | Começar imediatamente; sem deadline — "no tempo que o agente precisar", em fases entregáveis |
| **Preferência de hosting** | Local (`~/.claude/`), versionado em git próprio |
| **Sistemas existentes a integrar** | superpowers, gstack (com `--prefix`), skills próprias de arquitetura, shrimp task-manager, sistema de memória (a definir: claude-mem ou GBrain) |

---

## 6. Business Model

- **Modelo de receita:** Ferramenta interna (multiplicador de produtividade do portfólio SaaS)
- **Multi-tenancy necessário:** Não — decisão explícita: single-user para sempre na v1 (contrato §7)
- **Superfície de billing:** N/A

---

## 7. Data Sensitivity Profile

- [x] **Credenciais de autenticação** (o ambiente contém tokens/chaves dos projetos — a ferramenta não os trata, mas os hooks executam no mesmo ambiente)
- [x] **Dados confidenciais de negócio** (código-fonte dos SaaS do portfólio)
- [ ] Demais categorias: não se aplicam — a ferramenta não trata PII, saúde, financeiro ou dados de terceiros

**Estimativa de volume (Ano 1):** N/A (configuração + logs locais, <100MB)
**Requisitos de residência de dados:** tudo local na máquina do usuário

---

## 8. Worst-Case Scenarios

**Se o roteador errar:** workflow errado disparado → tokens queimados e retrabalho — mitigado por gates humanos nos pontos caros (plano, ship).
**Se um hook mal configurado bloquear:** trabalho travado → exigir kill-switch trivial (variável de ambiente ou flag que desativa o Maestro inteiro).
**Se subagentes autônomos agirem sem gate:** ação destrutiva (força-push, drop, rm) → política tipo `/careful`/`/guard` do gstack ativa por default em fluxos autônomos.

---

## 9. Success Criteria

**Meta de 3 meses:**
- Intervenções manuais de roteamento: de ~100% das tarefas para **<20%**
- Comandos de skill digitados por sessão: de vários para **0-1**
- Modo de execução (direto/subagente + modelo): **0 correções manuais** — decisão do orquestrador, com custo de tokens visivelmente menor (Haiku/Sonnet no lugar de Opus onde couber)

**Meta de 12 meses:**
- Fase 2 iniciada: camada dinâmica por projeto integrada ao [[orchestrator]]

**Anti-metas:**
- Cobertura total de todos os comandos dos packs — só os experts realmente usados entram
- Perfeição do roteador antes de usar — ship cedo, ajustar routing table com uso real

---

## Baseline & Measurement

> Obrigatória para Lock. Aproximado é aceitável.

| Métrica do processo ATUAL | Valor de partida | Fonte / confiança |
|---|---|---|
| Tarefas exigindo correção de rumo manual | ~100% (1-2 intervenções/tarefa) | relatado pelo usuário |
| Correção "faz via subagentes" | toda tarefa de código | relatado pelo usuário |
| Invocação de skills | 100% manual, digitada (frequentemente do telefone) | relatado pelo usuário |

**Como mediremos depois:** o próprio hook do Maestro loga (JSONL local) cada roteamento automático vs. intervenção manual — o número sai de graça da operação.

---

## Stakeholder & Political Risk Map

| Stakeholder | Papel | Ganha ou PERDE poder? | Risco de sabotagem | Ciente? |
|---|---|---|---|---|
| Romulo | sponsor + usuário único | ganha alavancagem | — | SIM |

**Risco político real (interno):** meta-tooling competindo por tempo com os SaaS que geram valor (Agenda Studio, SmartQuotation, etc.). **Mitigação:** fases curtas e entregáveis; a Fase 1 precisa pagar-se em dias, não semanas.

---

## AI Opportunity Map

> Default do pipeline: **trilhos determinísticos, IA nas bordas.** Decisão de alocação delegada ao office-hours pelo usuário.

**Onde IA ENTRA (probabilístico):**
- **Interpretação de intenção → seleção de workflow:** feita pelo próprio Claude da sessão, guiado por uma routing table injetada no contexto (SessionStart). Sem classificador separado, sem chamada extra de LLM na v1.
- **Decisão de modo de execução e modelo:** direto vs. subagente(s) e qual tier de modelo (Haiku/Sonnet/Opus) por subtarefa — julgamento do orquestrador, orientado por heurísticas declaradas na routing table (ex.: "edição ≤2 arquivos sem plano = direto"; "feature nova = subagentes com plano").
- Sugestão de ajustes na routing table a partir dos logs de erro de roteamento (v2, terreno do task-observer).

**Onde IA é PROIBIDA (determinístico, hooks):**
- **Gate estrutural de roteamento** — hook PreToolUse exige que exista uma decisão de roteamento registrada antes de edição de código; a decisão em si é IA, mas *pular a decisão* é bloqueado deterministicamente.
- **Injeção da routing table, do profile do projeto e do roster de agentes** — hook SessionStart; conteúdo fixo por configuração, nunca gerado on-the-fly.
- **Gates humanos (plano, ship) e guardas destrutivos** — hooks, nunca julgamento de LLM.
- Kill-switch do sistema.

**Exceções ao default:** nenhuma.

---

## Detected Anti-patterns

- **"Condensar tudo numa ferramenta"** → reframed: *wrap, não rewrite*. Os packs continuam upstream; o Maestro é camada de roteamento + curadoria. Absorver 90k+ linhas de terceiros seria dívida infinita.
- **Meta-work sem fim** → mitigado por fases entregáveis com critério de pagamento rápido (ver Stakeholder Map).
- **Três sistemas de memória em paralelo** (claude-mem, GBrain, memória do orchestrator) → decisão pendente registrada em Open Questions; a v1 escolhe UM.
- **Colisão de namespace** (`office-hours` própria vs. gstack) → resolvida por constraint: gstack sempre com `--prefix`.

---

## Vibe-Code Constraints

- Packs upstream (superpowers, gstack) **vendorizados e nunca editados no lugar** — customização só na camada Maestro (descrições, routing table, wrappers)
- gstack instalado com `--prefix` (comandos `/gstack-*`); skills próprias de arquitetura são canônicas em caso de conflito
- Hooks em bash ou TypeScript conforme convenção de hooks do Claude Code; tudo versionado em repo git próprio
- Kill-switch obrigatório desde o commit 1 (`MAESTRO_OFF=1` desativa todos os hooks)
- **Um único sistema de memória** ativo no ambiente
- Logs de roteamento em JSONL local (base do baseline pós-implantação)

---

## 10. Detected Regulatory Surface

**Definitivamente aplica:** nenhuma regulação — ferramenta de desenvolvimento local, single-user, sem tratamento de dados de terceiros.
**Atenção residual:** higiene de segredos nos logs de roteamento (nunca logar conteúdo de prompt que contenha credenciais — logar só metadados: intenção classificada, workflow disparado, timestamp).

---

## Open Questions

1. Nome definitivo (Maestro é provisório)
2. Sistema de memória único: claude-mem ou GBrain? (testar ambos, matar um — decisão antes da Fase 1 fechar)
3. Formato de distribuição: pasta em `~/.claude/` versionada vs. plugin instalável via marketplace pessoal (afeta a fase 2 com QM)
4. Shrimp task-manager entra na routing table ou fica como está?

---

## Recommended Next Steps

1. **G0:** aprovar este brief (Lock)
2. `system-architect` — arquitetura da camada: estrutura do repo, contrato da routing table, especificação dos hooks (SessionStart, PreToolUse, gates), mecanismo de profile por projeto
3. `security-architect` — curto, focado: superfície dos hooks (execução arbitrária, higiene de logs, guardas destrutivos)
4. Vibe-code da Fase 1 via subagentes — comendo a própria ração desde o primeiro sprint
