---
covers:
  - hooks/**
  - bin/**
  - src/**
---
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
**Emenda v1.2 (E10/S-1005, pedido do Romulo 2026-08-23):** consentimento humano
explícito (`maestro consent --grant <escopo> --ttl ≤4h`) levanta a denylist de
autoproteção **só para DADOS** — escopos `routing-table` e `roster` — **nunca para a
máquina** (hooks/, bin/, src/, .claude-plugin/ não têm escopo mapeado no gate: nenhum
arquivo de consentimento, forjado ou não, os destrava). Fail closed (malformado/expirado
bloqueia); auditado no log (`consent_grant`/`consent_revoke` + `scope` no evento do gate);
consent não dispensa o decision record — só a denylist é levantada. Consumidor canônico:
`/maestro:retro`, que aplica diffs de calibração com aval, examina no eval-on-diff e revoga
ao final. **S-1006 (2026-08-25):** o escopo `ops` estende o mesmo contrato ao
pre-bash-guard — infra (sudo/docker/kubectl) rebaixa bloqueio→aviso auditado; qualquer
categoria de destruição de dados mantém o bloqueio integral mesmo com consent.
**Emenda v1.3 (E14+E15, 2026-08-30):** o gate ganhou dois trilhos warn-only além do
decision record: avisos de ORÇAMENTO (caps declarados no record — passo/janela — um aviso
por cap, nunca bloqueio) e ZONAS CONGELADAS de work orders (compiladas na política pelo
SessionStart; autônomo bloqueia dentro da zona, humano é avisado — a assimetria do S-502).
O gate.mode foi promovido a `block` em 2026-08-29 com prova comportamental (live E2E).

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
**Status:** **Aceito** (v1.3 — 2026-08-09, após o spike S-601 e a descoberta do titular).
**Decisão:** **supermemory** (MCP, conta `tropeks@gmail.com`). Único sistema de memória.

**O erro que este ADR cometeu até aqui:** a Open Question #2 do brief enquadrou a escolha
como *"claude-mem ou GBrain?"* e **nunca mencionou o supermemory** — que já era o
incumbente, conectado, populado, com containers por projeto e regras de uso escritas no
`~/.claude/CLAUDE.md` global do Romulo (*"minha memória de longo prazo compartilhada entre
todas as máquinas e projetos"*). Um spike inteiro comparou os dois candidatos errados.

**Por que supermemory vence os dois:**

| | supermemory | gbrain | claude-mem |
|---|---|---|---|
| já em uso | **sim**, meses de conteúdo | não | não |
| alcance | **todas as máquinas** (VPS, Legatus) | só uma | só uma |
| integração | MCP | MCP | **6 hooks**, 3 deles do Maestro |
| custo | grátis até 1M tok/mês · Pro US$ 19 | US$ 0 (self-host) | US$ 0 |
| latência imposta ao Maestro | **nenhuma** | nenhuma | ~700 ms/evento |

- **claude-mem foi reprovado por medição:** 6 hooks (não 5 como a doc diz), incluindo
  PreToolUse; ~700 ms por evento com o worker de pé ou parado (o custo é o wrapper,
  `$SHELL -lc` + node por evento). PreToolUse/PostToolUse disparam a cada tool call:
  ~86 s de latência serial numa sessão de 60 chamadas, contra um gate de 7 ms.
- **gbrain foi reprovado por utilidade medida.** Recuperação local com 120 parágrafos
  reais dos docs deste repo: **melhor caso 5/14 (36%) em recall@1** entre cinco modelos
  (`granite-embedding:278m`, `bge-m3`, `embeddinggemma`, `snowflake-arctic-embed2`,
  `nomic-embed-text`). A diferença entre o pior e o melhor modelo é pequena, o que indica
  que o gargalo é a tarefa — pergunta curta e coloquial contra parágrafo técnico denso —,
  não o provedor. Trocar para embedding hospedado encareceria sem resolver. Some-se que
  ele recusou os quatro caminhos documentados para persistir a config de embedding
  (`reinit-pglite`, `migrate`, `init --force`, `config set`).
- **supermemory resolve um problema mais fácil por construção:** guarda memória
  *destilada e escrita para ser recuperada* (título padronizado, 1 memória por desfecho),
  não prosa arbitrária. A disciplina anti-spam do CLAUDE.md global não é só higiene de
  cota — é o que faz a recuperação funcionar.

**Conflito assumido conscientemente:** o brief §7 exige residência local (*"tudo local na
máquina do usuário"*) e o supermemory é cloud. O Romulo optou pela nuvem porque o valor
dele é atravessar máquinas — que é o que um homelab com VPS e Legatus precisa. O brief
está desatualizado em relação à prática; prevalece a prática, registrado aqui.

**Consequência:** nenhum sistema de memória se integra ao Maestro por hook. O Maestro não
tem componente de memória — a memória é do ambiente do Romulo, e o Maestro não a toca.

---|---|---|---|
| UserPromptSubmit | 734 ms | 24 ms | 30× |
| PreToolUse | 679 ms | 7 ms | 97× |
| PostToolUse | 721 ms | — | — |

- claude-mem registra **6 hooks** (Setup, SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop) — **os três do Maestro entre eles**. A leitura inicial da documentação dizia 5 e não incluía PreToolUse.
- A latência é **idêntica com o worker de pé ou parado**: não é o serviço, é o wrapper, que faz `$SHELL -lc 'echo $PATH'` + `node` a cada evento. É estrutural, não bug transitório.
- PreToolUse e PostToolUse disparam a **cada tool call**: numa sessão de 60 chamadas são ~86 s de latência serial adicionada, à frente do gate de 7 ms do Maestro. Isso viola de frente a NFR "overhead dos hooks < 100 ms, percebido zero no fluxo".
- Ponto a favor do claude-mem, medido: **falhou aberto** (exit 0) com o worker parado, e a injeção de SessionStart custa 56 bytes — custo de contexto zero.

**gbrain, verificado no spike:** **zero hooks registrados** (`settings.json` intocado), MCP stdio responde ao `initialize`, e `init --pglite --no-embedding` sobe sem chave e sem rede.

**Ressalva honesta:** `gbrain init --pglite` **exige** provedor de embedding e falha sem ele; só `--no-embedding` roda keyless, com recuperação degradada (grafo + keyword, sem busca semântica). Embeddings locais existem como receita (Ollama, llama.cpp llama-server) mas nenhum dos dois está instalado nesta máquina. Ou seja, a objeção de "memória sai da máquina" é **redutível, não eliminada**: escolher entre recuperação degradada, instalar Ollama local, ou aceitar chave hospedada. **Essa escolha continua do Romulo.**

**Consequência:** claude-mem não é ruim — é incompatível com uma camada cujo valor é trilho determinístico imperceptível. Reverter é um edit aqui e `npx claude-mem install`.

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
