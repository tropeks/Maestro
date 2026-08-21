# EPICS.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.1 — 2026-08-08 (emendas review Opus)
**Consome:** PROJECT_BRIEF.md, ARCHITECTURE.md | **Consumido por:** architect-orchestrator, sessões de vibe-code

> Capacidade assumida: solo + agentes, sem deadline, fases que se pagam em dias (brief).
> Corte por capacidade: se apertar, corta-se na ordem E5 → E4 → especialistas extras do E3.

---

## Épicos

### E1 — Esqueleto do plugin + kill-switch (P0, S)
Fundação instalável: sem ela nada existe; com ela já dá pra dogfood.
- **S-101:** repo `maestro` com estrutura de plugin (plugin.json, hooks/, agents/, config/, bin/), instalável via marketplace local. *AC: `/plugin` lista o Maestro; sessão nova carrega sem erro.*
- **S-102:** `MAESTRO_OFF=1` curto-circuita todos os hooks. *AC: com a env setada, nenhum hook produz efeito (teste automatizado).*
- **S-103:** `maestro doctor` valida instalação. *AC: detecta hook não registrado e YAML inválido.*

### E2 — Injeção + gate estrutural (P0, M) — o coração
- **S-201:** hook SessionStart injeta routing table + profile + índice do roster (≤2k tokens). *AC: bloco `<maestro-routing>` visível no contexto; falha de leitura degrada sem bloquear.*
- **S-202:** `maestro-decide` grava decision record validado. *AC: exit codes conforme API_SPEC; record por session_id.*
- **S-203:** hook PreToolUse com política compilada (caminho+extensão, denylist de autoproteção), TTL 4h, **modo warn por default**. *AC: editar .go sem decisão → warn logado (block após promoção); editar routing-table.yaml via agente → block sempre; editar .md → passa; latência <50ms; jq validado pelo doctor.*
- **S-204:** logs JSONL (vocabulário fechado, flock -n, JSON.stringify no CLI), sem conteúdo de prompt. *AC: `maestro log --summary` agrega decisões, warns, escapes e override_manual; fixtures adversariais de stdin passam.*
- **S-205:** hook UserPromptSubmit detecta comando `/` e loga `override_manual` (só o nome do comando). *AC: métrica principal derivável do log (ADR-008).*
- **Dependências:** E1.

### E3 — Roster v1 (P0, M)
- **S-301:** perfis de senioridade: `dev-junior` (haiku), `dev-pleno` (sonnet), `engenheiro`, `revisor` (read-only), `qa`. *AC: frontmatter com model+tools mínimas; Task tool consegue invocar cada um.*
- **S-302:** especialistas de linguagem vendorizados/adaptados: `golang-pro`, `python-pro`, `typescript-pro`, `postgres-pro` (upstream pinado por commit + atribuição). *AC: descrições reescritas ≤1 linha, sem colisão de gatilho entre si.*
- **S-303:** `.maestro.yaml` por projeto filtra o roster ativo. *AC: em repo com `experts: [golang-pro]`, só ele aparece na injeção.*
- **Dependências:** E2 (injeção).

### E4 — Routing table v1 + curadoria dos packs (P1, M)
- **S-401:** routing-table.yaml com os 5 workflows (fix, feature, refactor, ship, audit) mapeando steps para superpowers/gstack-prefix/skills próprias. *AC: cada step referencia comando existente no ambiente.*
- **S-402:** heurísticas de execução escritas e testadas em 10 tarefas reais. *AC: ≥8/10 roteadas sem correção manual (medido no log).*
- **S-403:** gstack reinstalado com `--prefix`; descrições conflitantes curadas. *AC: `office-hours` própria dispara sem ambiguidade.*
- **Dependências:** E2, E3.

### E5 — Gates humanos + guardas (P1, S)
- **S-501:** workflows `feature`/`ship` pausam para aprovação (aprovável via RC). *AC: plano apresentado antes de implementar; ship pede confirmação.*
- **S-502:** modo autônomo ativa guarda destrutivo (política tipo `/gstack-careful`). *AC: rm -rf/force-push em fluxo subagente exige confirmação.*
- **Dependências:** E2.

### E6 — Decisão de memória (P1, S) — fecha ADR-007
- **S-601:** spike claude-mem em 1 projeto; validar coexistência de hooks (ordem SessionStart). *AC: relatório curto + decisão registrada (ADR-007 → Aceito ou trocado por GBrain).*

### E7 — P0 RAD hardening (P1, S) — emenda 2026-08-17, aprovada pelo Romulo
Origem: pesquisa RAD interna (RAD_PATTERNS_FOR_MAESTRO §7-P0 + ECC_DELTA_AUDIT §5-P0;
material privado, mantido fora do repo).
Princípio: carimbos, não componentes — evidência amarrada a conteúdo e tabela blindada
por diff. Tudo warn-only/informativo; nada bloqueia; reversível por revert.
- **S-701:** fingerprint de conteúdo. `bin/maestro-wtree` (bash puro, padrão adaptado do
  gstack-wtree/MIT com atribuição); `maestro decide` carimba `wtree` no decision record
  (DATA_MODEL §3 emenda v1.4); `maestro status` reporta freshness; doctor valida o campo.
  *AC: mesmo conteúdo → mesmo hash; commit do mesmo conteúdo não muda; arquivo novo muda;
  index real intocado; fora de git degrada sem campo e sem erro; `wtree` NUNCA vai ao
  routing.jsonl (§4 intocado).* **Entregue 2026-08-17** (test-wtree.sh, 22 asserções).
  Guarda de design: comparação de wtree é do CLI — **jamais do pre-tool-gate** (NFR <50ms
  × ~200ms do wtree); enforcement no gate só com medição, em épico próprio.
- **S-702:** eval-on-diff Tier 1 da routing table. Baseline pinado por caso
  (`tests/eval/prescribed-baseline.tsv`, gerado do instrumento (A)) + teste de CI que
  falha NOMEANDO os casos cujo veredito prescrito mudou. *AC: mutação de rota reprova
  citando caso e antes→depois; duas execuções do instrumento são idênticas; o SCORE
  continua fora do CI (filosofia do run-eval.sh); baseline regenerável no mesmo PR.*
  **Entregue 2026-08-17** (test-eval-diff.sh).
- **S-703:** ratchet da injeção SessionStart. O doctor roda o hook de verdade e mede os
  bytes reais (`injeção SessionStart: NB de 8000B`; warn >90%, fail_val >8000); o fato
  entra no envelope (`injection.{bytes,budget}`); o RATCHET consciente (6500B, bump só
  deliberado e no mesmo commit) vive em test-injection-budget.sh. *AC: medição real;
  estouro do ratchet reprova nomeando o protocolo; envelope carrega inteiros.*
  **Entregue 2026-08-18.**
- **S-704:** doctor: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` → warn (teams podem se
  formar sem pedido; o roteamento não os governa); MCP servers de `~/.claude.json` +
  `.mcp.json` do projeto nomeados como fora-do-envelope — SÓ nomes, nunca config/URL
  (assert de não-vazamento no teste). *AC: warn com a env; nomes listados; config não
  vaza; nada disso derruba o doctor.* **Entregue 2026-08-18** (test-injection-budget.sh).
- **S-709:** mote de execução na injeção (diretriz do Romulo, 2026-08-18: "the marginal
  cost of completeness is near zero — do the whole thing, with tests, with documentation;
  padrão 'holy shit, that's done'; boil the ocean"). `config/execution-ethos.md` canônico,
  emitido como `## Mote de execução` pelo mesmo mecanismo do S-707; cede depois do estilo
  e antes das heurísticas. Da mesma diretriz: **Maestro, não Legatus, é a metodologia RAD
  padrão do portfólio** — registrado nos globais e nos containers de memória (default,
  Maestro, ClaudeProxy/Legatus). *AC: seção presente; ausente degrada; cessão ordenada;
  teto por arquivo.* **Entregue 2026-08-18** (asserts em test-style-injection e
  test-session-start).
- **S-708:** diretriz Spock na seção de gates humanos (ordem permanente do Romulo,
  2026-08-18): os gates plan/ship valem para risco catastrófico/quase irreversível
  (produção real com usuários/dados, billing, auth/secrets, migração destrutiva, apagar
  dados/volumes, force push, decisão jurídica/produto externa); em RAD privado com a onda
  VERIFICADA, commit/push em branch/PR/deploy de teste fluem sem pergunta, registrando a
  decisão. Uma linha em `sec_gate` do session-start; réplica da diretriz nos arquivos
  globais (CLAUDE.md, AGENTS.md do agy/codex) e no supermemory. *AC: linha presente quando
  há gates declarados; injeção dentro do teto.* **Entregue 2026-08-18.**
- **S-707:** estilo de comunicação com o usuário na injeção. `config/communication-style.md`
  (canônico, versionado; base: Google developer documentation style guide adaptado para
  conversa — pedido do Romulo em 2026-08-18) emitido pelo SessionStart como seção própria;
  teto de 2.000B por arquivo; primeira seção a ceder no orçamento. Réplica manual nos
  AGENTS.md do agy/codex (Maestro não os alcança); `~/.claude/CLAUDE.md` global vira
  ponteiro. *AC: seção presente com o config do repo; arquivo ausente degrada sem seção e
  sem erro; arquivo inchado não passa de ~2KB; sob orçamento apertado cede antes de
  heurísticas/roster; núcleo intocado.* **Entregue 2026-08-18** (test-style-injection.sh).
- **S-705:** capability envelope (P0.1 do ECC_DELTA_AUDIT). Doctor grava
  `$MAESTRO_HOME/capabilities.json` (`maestro.capabilities.v1`: fatos — runtime
  bun/jq/git/flock com versão, contadores do doctor, bindings resolvidos, roster);
  `delegate()` sem Bun cita o envelope no erro ("último doctor: <ts> (<N>h atrás)",
  "envelope velho" com ≥24h); `maestro status` mostra a idade. *AC: sem Bun o erro cita o
  envelope e a idade; sem envelope o erro é o seco original; envelope só com jq (skip
  honesto sem ele); hooks continuam bash puro (ninguém no caminho de hook lê o envelope
  ainda).* **Entregue 2026-08-17** (test-envelope.sh).
- **S-706:** drift de resolução + integridade do vendor (P0.2 do ECC_DELTA_AUDIT).
  Snapshot `$MAESTRO_HOME/bindings-snapshot.tsv` (alvo→caminho→sha256) comparado a cada
  doctor: caminho ou conteúdo do MESMO alvo mudou → `warn binding-resolution-drift`
  nomeando o alvo, snapshot sempre avança (avisa 1× por mudança) — a classe do incidente
  do `--prefix` (2026-08-10) deixa de ser silenciosa. `config/vendor.sha256` (manifesto
  pinado, versionado) verificado offline: divergência é `fail_val` — vendor/ é read-only,
  atualização deliberada regenera o manifesto no mesmo commit. *AC: drift é aviso e nunca
  falha; conteúdo e caminho detectados separadamente; vendor divergente reprova com exit
  1.* **Entregue 2026-08-17** (test-envelope.sh; doctor 24 → 27 checagens).
- **S-710:** drift de INSTALAÇÃO do plugin (emenda 2026-08-18, achado da migração do
  mount de `/home/rcosta00/dev`). O `hooks.json` chama tudo por `${CLAUDE_PLUGIN_ROOT}` e
  quem resolve esse root é o Claude Code, a partir de `~/.claude/plugins`: o `installPath`
  registrado costuma ser uma CÓPIA em cache, congelada na instalação. Cópia divergente viva
  = rollback silencioso (tabela e injeção antigas, sem sinal) — a classe do `--prefix`
  (S-706) um andar acima. O doctor compara `cmp` byte a byte os 8 arquivos que DEFINEM
  comportamento (3 hooks + `hooks.json` + `lib/common.sh` + `routing-table.yaml` +
  `bin/maestro` + `plugin.json`); o fato entra no envelope (`install.{registered,divergent}`).
  Costura de teste: `MAESTRO_PLUGINS_DIR`. **Emenda do mesmo dia:** a severidade depende de
  QUEM EXECUTA — marketplace `source: directory` apontando para o repo faz do repo o
  `${CLAUDE_PLUGIN_ROOT}` vivo (medido em sessão headless), e aí a cópia em cache é inerte e
  vira `ok`; sem ele, o `installPath` executa e divergir é warn. *AC: comparação por conteúdo, não por versão (as
  duas cópias diziam `1.0.4` e o E7 inteiro entrou sem bump); divergência só em doc/teste
  NÃO avisa; `installPath` = repo (ou symlink para ele) não avisa; caminho ausente avisa;
  registro ausente/corrompido/de outro plugin degrada sem inventar drift; sem jq ou sem cmp
  → skip honesto; nunca falha o doctor; nada vaza para o `routing.jsonl`; cópia inerte sob
  marketplace de diretório NÃO avisa; marketplace github/apontando para outro lugar/ilegível
  degrada avisando.* **Entregue 2026-08-18** (test-install-drift.sh, 41 asserções).
- **Dependências:** E2 (CLI/record), E4 (tabela + instrumento de eval).

### E8 — Inteligência situacional por projeto (P1, S) — emenda 2026-08-20, plano aprovado pelo Romulo
Origem: dor real de dogfood ("toda sessão nova varre o repo para saber onde está") +
recomendação de handoff `maestro.handoff.v1` do ECC audit (P1). Princípio: **injetar a
GARANTIA de que o estado existe e está fresco, nunca o estado em si** — trilhos cobram e
verificam; a IA escreve a narrativa. Brief é estado local de trabalho: não é memória
(ADR-007 intocado) e não é log (§4 intocado).
- **S-801:** `maestro brief` — CLI bash puro (sem Bun): leitura com veredito de freshness
  em duas camadas (HEAD barato + wtree/S-701 por conteúdo), `--write` (stdin/--file, cap
  16KB, atômico), `--auto` (esqueleto determinístico do git), `--path`; carimbos
  ts/epoch/HEAD/wtree/session; chave derivada por `maestro_brief_file()` no common.sh —
  definição única para CLI e hook (paridade testada). *AC: FRESCO/STALE contando commits;
  wtree acusa working tree mudado com HEAD igual; fora de git degrada honesto; corrompido
  avisa e não quebra; sem Bun funciona inteiro; nada vaza ao routing.jsonl.*
  **Entregue 2026-08-20** (test-brief.sh, 36 asserções).
- **S-802:** seção `## Projeto` no SessionStart: ponteiro do brief + freshness barata
  (HEAD + idade; hash djb2 puro-bash para caber no NFR — medido 69ms sem brief, 97ms com,
  baseline 77ms) + linha `memória:` derivada do `memory_container:` do `.maestro.yaml`
  (recall com a tag certa vira trilho, não disciplina). *AC: ponteiro do hook = caminho do
  CLI; narrativa NUNCA injetada; malformado omite; sob orçamento a seção cede depois do
  profile e antes de rotas; núcleo sobrevive.* **Entregue 2026-08-20**
  (test-brief-injection.sh, 20 asserções).
- **S-803:** cobrança canônica na mesma seção: "ao fechar trabalho substancial, atualize o
  brief" com o session_id real — o trilho garante QUE a atualização é pedida; a IA decide
  O QUE escrever. Doctor valida os briefs existentes (cabeçalho v1 + epoch).
  *AC: cobrança presente com sid; briefs malformados viram warn nomeado.*
  **Entregue 2026-08-20.**
- **Dependências:** E2 (injeção/CLI), E7/S-701 (wtree).

### E9 — Habit hooks: sensores anti-slop + guias (P1, M) — emenda 2026-08-21, plano aprovado pelo Romulo
Origem: spec de Habit Hooks trazida pelo Capitão (conceito do projeto habit-hooks, MIT —
github.com/habit-hooks/habit-hooks) + pesquisa de catálogos de slop de LLM. Princípio do
padrão: **sensor determinístico e guia qualitativo, sempre juntos** — o guia explica o
PORQUÊ para a correção ser de design, não de burla de métrica. Correção de encaixe sobre a
spec original: hábito dispara NA EDIÇÃO (hook PostToolUse), não sob demanda (skill), e o
guia é config versionada, não corpo de agente — método ≠ executor.
- **S-901:** hook `post-edit-habits.sh` (PostToolUse em Edit|Write|MultiEdit) + motor único
  `hooks/lib/habit-sensors.awk` (uma passada de awk, bash puro). 14 sensores:
  oversized-{function,file}, deep-nesting, too-many-params, swallowed-error,
  debug-leftover, lint-suppression, type-escape, slop-comment, empty-impl, dead-code,
  skipped-test, risky-shortcut e test-gap (sensor de SESSÃO: N edições de src sem teste,
  nag nos degraus 5/15/40). Viés conservador: falso negativo > falso positivo — sensor que
  grita errado ensina o agente a ignorá-lo; shell não aciona swallowed-error (`|| true` é
  degradação-por-design NESTA casa). Anti-ruído: cooldown 15min por (arquivo, smell), ≤3
  achados + ≤2 guias por emissão. Warn-only estrutural: PostToolUse nunca bloqueia (a
  edição já valeu); exit 2 só entrega o texto ao agente. Log: `habit_warn` com
  smell+n+file_ext (DATA_MODEL §4 emendado) — jamais caminho. *AC: positivos por sensor;
  adversariais (código limpo, idioma de shell, console.log EM teste); cooldown; test-gap
  1 nag no degrau; kill-switch; vendor/ fora; degradações exit 0; latência medida 39ms
  limpo / 68ms com 3000 linhas.* **Entregue 2026-08-21** (test-habits.sh, 38 asserções).
- **S-902:** `config/habit-guides/<smell>.md` (14 guias versionados, ~300-700B, emitidos
  capados em 700B) + `habits:` no `.maestro.yaml` (lista liga/desliga por projeto; `[]` =
  desligado; ausente = todos). Doctor: todo sensor do motor tem guia (`fail_val` sem —
  sensor sem guia é linter cru) e os 4 eventos de hook registrados. *AC: config filtra no
  hook E no CLI; guia ausente reprova o doctor.* **Entregue 2026-08-21.**
- **S-903:** `maestro habits` — os MESMOS sensores sobre o diff (default), `--all` ou
  caminhos; para o step review e CI opcional. Exit 0 limpo · 1 achados · 2 ambiente.
  Sensor único pinado em teste: hook e CLI referenciam o mesmo awk. *AC: diff limpo/sujo;
  --all exige git; config respeitada; achado nomeia arquivo:linha e smell com guia junto.*
  **Entregue 2026-08-21** (test-habits-cli.sh, 14 asserções).
- **Rejeitados com registro:** `generic-name` (ruído demais para heurística awk);
  integração com o habit-hooks upstream no hook (Python 3.11 + eslint/ruff quebra
  bash-puro/zero-deps/latência; quem quiser o pipeline pesado roda o tool dele no review —
  composição, não duplicação); `hardcoded-secret` (superfície do `audit`/gstack-cso).
- **Dependências:** E2 (hooks/CLI), E8 (padrão de config por projeto).

---

## Grafo de dependências

```
E1 → E2 → E3 → E4
       ↘ E5
E6 (paralelo após E1)
```

## Roadmap

| Fase | Épicos | Critério de avanço |
|---|---|---|
| Fase 1a (dias) | E1, E2 **em modo warn** | dogfood ativo: gate logando warns/decisões no dia a dia real |
| Fase 1b (1 semana de warn) | promoção warn→block (decisão com dados), E5 (S-502 em paralelo), E3 | primeira semana com roteamento p/ subagentes tierizados; escapes medidos |
| Fase 1c (≤2 semanas de uso) | E4 (routing table calibrada nos logs reais), E6, S-501 (só após especificar mecanismo de aprovação) | `maestro log --summary` mostra <20% override manual; ADR-007 travado |
| Fase 2 (futuro) | task-observer no loop; camada MCP `activate()` no [[orchestrator]]; QM (**só após dogfood provar redução de override**) | novo brief/delta |

**Guarda de escopo:** nada fora destes épicos entra sem emenda documentada aqui.

## Flags para o orchestrator

Nenhuma.
