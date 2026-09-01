---
covers:
  - docs/architecture/**
reviewed: e47661a
---
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

#### Emenda E3 (2026-08-27, aprovada pelo Capitão) — S-304: `arquiteto` (opus)
Pergunta do Capitão ("engenheiro em Opus não traria melhorias?") respondida com o tier que
faltava na escada MoE (haiku → sonnet → opus): `agents/arquiteto.md`, Opus, com a
description como GATE DE CUSTO — só decisão estrutural crítica (cross-sistema, migração de
dados, concorrência, segurança, cara de reverter); plano comum segue no engenheiro
(sonnet), que mantém a escalada por pedido na saída. H4 bifurcado na routing table.
Primeiro uso REAL do consent E10 (roster + routing-table concedidos, edição pela porta do
gate, revogados ao final). Sob medição: o retro compara accepted/rework do arquiteto — se
em ~1 mês não pagar o custo, sai pelo mesmo rito. Roster 9 → 10; injeção 6465B (ratchet
6500B mantido enxugando o H4, não subindo a régua).

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
- **2ª rodada de pesquisa (2026-08-21, a pedido do Capitão):** sloppylint e
  AI-SLOP-Detector (ambos MIT) renderam 4 padrões awk-baratos incorporados aos sensores
  existentes: `except:` sem tipo (pega até SystemExit) em swallowed-error; hedging
  comments ("should work hopefully") em slop-comment; `from x import *` em
  risky-shortcut; corpo só-`pass` (fora de @abstractmethod/@overload) em empty-impl.
- **Rejeitados com registro:** `generic-name` (ruído demais para heurística awk);
  imports alucinados/phantom (exige resolução de ambiente); cross-language leakage e
  clone clusters (AST/similaridade — território dos tools upstream); magic numbers (ruído);
  integração com o habit-hooks upstream no hook (Python 3.11 + eslint/ruff quebra
  bash-puro/zero-deps/latência; quem quiser o pipeline pesado roda o tool dele no review —
  composição, não duplicação); `hardcoded-secret` (superfície do `audit`/gstack-cso).
- **S-904:** `/maestro:deslop` (emenda 2026-08-21, plano aprovado) — slash command do
  plugin (`commands/deslop.md`): sweep da dívida de slop com triagem por classe ANTES do
  fan-out (mecânico → dev-junior; julgamento → especialista H5 com teste no lote; falso
  positivo → ajuste de `habits:`, nunca supressão inline), execução em PIPELINE de lotes
  (paralelo dentro, serial entre; suíte é o gate; lote quebrado reverte), revisor no diff
  final, commit local como teto (Spock). Doctor valida frontmatter de commands/*.md.
  *AC: tabela de triagem mostrada antes de editar; --dry só relata; baseline desce a cada
  lote.* **Entregue 2026-08-21.**
- **S-905:** catraca de baseline — `maestro habits --baseline` grava contagem POR smell em
  `.maestro-habits.tsv` (versionado no projeto); com baseline presente, `--all` reprova SÓ
  o que EXCEDER (dívida igual passa; melhora convida a regravar para baixo no mesmo
  commit). Mesmo desenho do ratchet da injeção (S-703) e do eval-on-diff (S-702). `--all`
  passa a ver untracked não-ignorados — catraca sem isso tem o dente quebrado (achado do
  smoke). Comparação SÓ no escopo --all: régua do repo não mede diff. *AC: igual passa;
  exceder reprova nomeando smell e contagens; untracked conta; regravar desce; escopo por
  caminho ignora baseline.* **Entregue 2026-08-21** (test-habits-cli.sh, 34 asserções).
- **Dependências:** E2 (hooks/CLI), E8 (padrão de config por projeto).

### E10 — Loop de calibração: o Maestro aprende em lote (P1, M) — emenda 2026-08-23, plano aprovado
Princípio: **aprender em runtime é proibido** (IA ajustando trilho enquanto roda = teatro);
o aprendizado é telemetria → retro → proposta de diff → exame (eval-on-diff) → commit.
Aprendizado = história de git. Emenda do Capitão na aprovação: com consentimento explícito,
a IA pode aplicar os diffs de config ela mesma.
- **S-1001:** `maestro outcome --session <id> <accepted|rework|reverted> [--suite pass|fail]`
  — a variável dependente que faltava: decide registra a aposta, outcome registra se pagou.
  Atualiza o record (DATA_MODEL §3 v1.5) e loga enums (`outcome`, `suite`), jamais texto.
  *AC: exige record existente; enums validados; last-wins.* **Entregue 2026-08-23.**
- **S-1002:** `maestro retro [--days N]` — agregação determinística da janela: taxa de
  override, decisões por modo/workflow, gates, habit_warn por smell, desfechos, consents,
  workflows declarados sem uso. Bash+jq; log vazio responde "sem dados", nunca inventa.
  *AC: taxa correta; smells por frequência; honestidade sem dados.* **Entregue 2026-08-23.**
- **S-1003:** `/maestro:retro` (commands/retro.md) — a IA nas bordas interpreta o relatório
  e propõe DIFFS com o sinal que os justifica (rotas, heurísticas, habits:, casos de eval
  destilados com aprovação); com "aplica": consent mínimo → diff → suíte+eval-on-diff como
  exame → commit → revoke. `--dry` para na proposta. *AC: pergunta antes de aplicar; exame
  antes do commit; revoga ao final.* **Entregue 2026-08-23.**
- **S-1004:** critério de promoção warn→block CODIFICADO no retro: ≥14d de janela, ≥10
  decisões, override <20% → imprime "PROMOÇÃO ELEGÍVEL" propondo o diff — nunca automático.
  *AC: não elegível abaixo do piso; elegível com critério cheio.* **Entregue 2026-08-23.**
- **S-1005:** consentimento escopado (ADR-003 v1.2) — `maestro consent --grant/--revoke
  <routing-table|roster> [--ttl 1min–4h]`; o gate levanta a denylist SÓ para o escopo
  mapeado e SÓ no ramo normalizado ancorado no plugin; hooks/bin/src/.claude-plugin não têm
  mapeamento (consent forjado não destrava — testado); fail closed; auditado
  (consent_grant/revoke + scope no evento do gate); doctor mostra consents ativos como
  warn. Consent NÃO dispensa o decision record. *AC: 29 asserções de segurança em
  test-consent.sh.* **Entregue 2026-08-23.**
- **S-1006:** escopo `ops` no consent (emenda 2026-08-25, dor real do Capitão: migrar o
  docker de partição na mão porque o guarda bloqueava sudo/docker em sessão multi). Com
  `maestro consent --grant ops`, o pre-bash-guard REBAIXA bloqueio→aviso auditado, mas SÓ
  quando TODAS as categorias levantadas são operacionais (privilege_escalation,
  container_destructive, kubectl_delete); UMA categoria de destruição de dados
  (rm_recursive, git_force_push, sql_drop, dd, disk_format…) e o bloqueio vale integral —
  ops libera infraestrutura, nunca apagão. A mensagem de bloqueio ENSINA o caminho do
  consent. Camadas irmãs fora do plugin: rcosta00 no grupo docker (sudo desnecessário
  para docker no próximo login) e allow de `docker`/`sudo docker`/`sudo systemctl *
  docker` no settings do harness. *AC: 12 asserções em test-consent.sh — bloqueio sem
  consent, liberação auditada com, destruição bloqueada COM ops, revoke restaura.*
  **Entregue 2026-08-25.**
- **Rejeitados com registro:** auto-tuning em runtime; hook com LLM; arquivo de "instintos"
  não-versionado (classe já rejeitada no ECC audit); memória no Maestro (ADR-007).
- **Dependências:** E7 (eval-on-diff = exame), E9 (habit_warn = sinal), ADR-008 (override).

### E11 — Grafo de conhecimento com freshness (P2, S) — emenda 2026-08-24, aprovado
Objetivo do Capitão: "o agente não ficar perdido e ter que ficar sempre lendo código".
Divisão honesta: brief (E8) = ESTADO; grafo (graphify, skill externa, opcional) =
ESTRUTURA. Invariante: grafo velho é fato morto vestido de mapa — o veredito nunca finge
frescor. Freshness SEM carimbo novo: mtime do graphify-out/graph.json vs último commit.
- **S-1101:** `maestro_graph_state()` (common.sh, 2 forks) + linha `grafo:` na seção
  `## Projeto`: FRESCO → "responda estrutura via graphify query ANTES de ler código";
  STALE → "NÃO confie; atualize com /graphify . --update"; ausente → nenhuma linha
  (graphify é opcional e fora do envelope). `maestro graph [--check]` no CLI (--check sai
  1 se STALE — o gatilho da rotina). **Entregue 2026-08-24.**
- **S-1102:** `/maestro:deslop` monta lotes por CONSULTA ao grafo quando FRESCO
  (independência verificada em vez de palpite); STALE/ausente degrada para o
  comportamento anterior. **Entregue 2026-08-24.**
- **S-1103:** rotina de frescor `bin/maestro-graph-refresh` — FERRAMENTA DE OPERADOR
  (crontab semanal), não hook: é o único lugar onde `claude` headless é aceitável; os
  hooks seguem bash puro e sem rede. Varre $MAESTRO_GRAPH_ROOTS por grafos, atualiza SÓ
  os STALE (`--check`), teto de projetos por rodada, flock, timeout, log de operação
  próprio (nunca o routing.jsonl). Grafo que não existe não é gerado — gerar é decisão
  humana. *AC: fake-claude chamado só no stale; teto respeitado; falha não toca o grafo;
  degradações exit 0.* **Entregue 2026-08-24** (test-graph.sh, 24 asserções).
- **Gate de medição registrado:** binding de workflow ou geração automática só entram se
  medição em repo grande (tool calls até a primeira edição correta, com vs sem grafo)
  mover número — precedente gbrain/claude-mem: camada de conhecimento não ganha isenção
  do tribunal.
- **Dependências:** E8 (padrão ponteiro+freshness), skill graphify instalada (opcional).

### E13 — Evidência mecânica (P1, M) — emenda 2026-08-29, aprovado
Origem: garimpo do salto gstack 1.60→1.72 a pedido do Capitão; o evidence ledger (1.66.1)
é o "Contract 1" que a pesquisa RAD deixou pendente. Princípio: "testes passaram" vira
checagem MECÂNICA (conteúdo + comando + idade), não sistema de honra.
- **S-1301:** `maestro evidence` — `--record -- <cmd>` grava recibo (wtree ANTES e DEPOIS
  da corrida, hash do comando, exit, epoch) em `$MAESTRO_HOME/evidence/` (DATA_MODEL §8);
  leitura dá VÁLIDA só com conteúdo byte-idêntico + exit 0 + idade sob o teto + árvore
  parada durante a corrida — qualquer outra coisa é VENCIDA nomeando o motivo. Falha
  também vira recibo (exit é dado). `--check` para scripts. *AC: 24 asserções em
  test-evidence.sh; nada vaza ao routing.jsonl.* **Entregue 2026-08-29.**
- **S-1302:** consumidores — `outcome --suite pass` consulta o ledger e CITA evidência
  válida (ou avisa "palavra de honra"; `suite_evidence` no record); `/maestro:deslop`
  grava evidência por lote e pula re-execução quando o conteúdo já está provado; retro
  reporta cobertura do ledger; doctor valida recibos. **Entregue 2026-08-29.**
- **S-1303:** live-dispatch E2E (`tests/e2e/`, tier MANUAL/PAGO, fora do run-all — padrão
  gstack gate-tier): sessão `claude -p` real num fixture prova se a injeção governa
  comportamento. **Primeira execução: FAIL honesto e valioso** — a sessão criou o arquivo
  SEM registrar decide (hooks rodaram; o modo warn deixou passar). Leitura: sessão
  interativa obedece (113 decisões de dogfood), one-shot headless escapa — dado NOVO a
  favor da promoção warn→block, que é o que forçaria o registro onde a instrução sozinha
  não alcança. O E2E é o pré-requisito declarado da promoção: aperta-se o gate quando este
  teste passar EM block. **Entregue 2026-08-29** (o teste; o verde dele é meta, não AC).
- **Rejeitados do garimpo (com porquê):** egress ledger (Maestro não tem sink — sem rede
  em runtime); issue-guard/trust envelope (Maestro não ingere texto de tracker); Aside
  browser e section carves (fora de domínio / superfície 20× menor).
- **Dependências:** E7/S-701 (wtree), E10 (outcome).

### E14 — Orçamento declarado (P1, S) — Arco 2, aprovado 2026-08-29 ("Segue")
Contract 2 da pesquisa RAD, o último P1: roteamos por complexidade, faltava rotear por
ORÇAMENTO. Caps inteiros, AND-of-caps, warn-only — orçamento é sinal de deriva, não trava.
- **S-1401:** `decide --max-steps/--max-min/--max-cents` → `budget` no record (§3 v1.6;
  inteiros ≥1, float rejeitado — regra da casa); `status` exibe; schema do doctor valida
  (record com float reprova). **Entregue 2026-08-30.**
- **S-1402:** gate mede `steps` (contador por sessão — ler o log no hot path estouraria o
  NFR) e `minutes` (ts do record); aviso ÚNICO por cap, instruindo reportar ao humano;
  `budget_warn` no vocabulário com `cap`; `cents` declarativo para o retro correlacionar
  custo × desfecho. Estouro NUNCA bloqueia — convive com gate.mode block sem virar segundo
  bloqueio. *AC: 25 asserções em test-budget.sh — aviso único, warn-only, malformado
  degrada, retro conta.* **Entregue 2026-08-30.**
- **Dependências:** E10 (retro/outcome), promoção block (o orçamento nasceu já convivendo
  com o gate duro).

### E15 — Work orders: do roteador ao diretor (P1, M) — Arco 3 v1, aprovado 2026-08-30
Contract 3 da pesquisa RAD, o último dos três. A ordem viaja com o repo
(`.maestro/orders/NNN.md`) e carrega o contrato: objetivo, critérios, frozen zones
(BMAD), Ask-First, orçamento (E14), branch esperado. Princípio central: **estado
DERIVADO, nunca auto-declarado** — o executor não escreve o próprio boletim.
- **S-1501:** `maestro order --create/--list/--status/--accept` — carimbo v1, id
  sequencial, slug/branch derivados; corpo via stdin; contrato de execução gerado no
  próprio arquivo (branch próprio, prova via ledger, Ask-First, quem aceita).
  **Entregue 2026-08-30.**
- **S-1502:** derivação — aberta (nada) → em_execucao (branch existe) → provada
  (recibo `order-N` exit 0 cujo wtree_after == ÁRVORE DO TIP do branch: prova mecânica
  S-701 de que a suíte passou naquele conteúdo exato; commit posterior REBAIXA para
  em_execucao) → aceita (`--accept` do diretor, que EXIGE estado provada e carimba
  auditável). **Entregue 2026-08-30.**
- **S-1503:** injeção — `ordens: N pendente(s) → maestro order --list` na seção
  `## Projeto`; sessão nova no projeto descobre o trabalho sozinha (mesmo padrão do
  brief). **Entregue 2026-08-30.**
- **S-1504:** frozen zones no gate — session-start COMPILA as zonas das ordens
  não-aceitas na política (`MAESTRO_GATE_ORDER_FROZEN`; hot path não lê ordens);
  edição na zona: autônomo (subagent/multi) BLOQUEIA, humano no volante avisa e passa
  (assimetria do S-502); aceite descongela na recompilação. `order_create`/
  `order_accept` no vocabulário; `cmd=frozen_zone` audita. *AC: 27 asserções em
  test-order.sh.* **Entregue 2026-08-30.**
- **Fora do v1, com registro:** frota multi-máquina (Legatus bridge — Fase 2 do arco,
  depois do dado do v1) e despacho automático de sessões (criar ordem ≠ executá-la).
- **Dependências:** E13 (a prova É o ledger), E14 (orçamento na ordem), E8 (padrão de
  descoberta via injeção).

### E16 — Documentação como contrato (P1, M) — aprovado 2026-08-30, desenho batido em pesquisa
Ideia do Capitão ("Maestro orientado à documentação de produção; fire and forget") +
pesquisa dedicada (subagente): validou o esqueleto e corrigiu três palpites — quitação por
FRONTEIRA em vez de "mesmo commit" (falso positivo estrutural), `reviewed:` como
provenance stamp (padrão Fiberplane Drift), e reforço TARDIO da regra (decaimento
intra-sessão de −5,6%/função, arXiv 2605.10039 — posição/tamanho no SessionStart não
movem aderência). Rejeitados com fonte: Spec Kit inteiro (spec rot, pior aderência em
teste independente), Tessl (hype), BMAD (burocracia), granularidade de símbolo
(tree-sitter × hooks bash).
- **S-1601:** `docs:` no `.maestro.yaml` + frontmatter `covers:` (globs) e `reviewed:
  <sha>`; `maestro docs` — FRESCO/STALE contando COMMITS (não dias) desde
  max(último commit no doc, reviewed); acusa doc ausente, sem covers, e fan-out
  (glob que engole >50% do repo, com guarda anti-ruído para repos <20 arquivos).
  Gotcha pago: glob `src/**` expande contra o CWD do bash antes do git — `set -f`.
  **Entregue 2026-08-30.**
- **S-1602:** catraca `.maestro-docs.tsv` (versionada; brownfield entra sem gritar);
  `--check` reprova só drift NOVO. **Entregue 2026-08-30.**
- **S-1603:** a regra em DOIS momentos — injeção (positiva, curta: "todo plano cita
  doc+seção; sem doc que autorize, emenda no mesmo changeset") + nag TARDIO único por
  sessão no 1º edit em área governada (sensor `doc-governed` no habit hook, com guia).
  **Entregue 2026-08-30.**
- **S-1604:** ordem carrega `--doc` (quem a autoriza); contrato cobra emenda no mesmo
  changeset; `--status` mostra o frescor do doc. **Entregue 2026-08-30.**
- **Dogfood na primeira medição:** ARCHITECTURE.md acusou 6 commits de drift real
  (E14/E15 mexeram no gate sem ADR) — quitado com a Emenda v1.3 do ADR-003 neste mesmo
  changeset. O sistema cobrou o autor antes de cobrar qualquer outro projeto.
- **Fase 2 registrada, não construída:** `maestro converge` (reconciliação semântica LLM
  sob demanda, estilo /speckit.converge) e a derivação doc→ordem do FIRE AND FORGET
  (delta de doc gera work order proposta → aprovação → despacho headless): escada
  v1 seguir → v2 propor → v3 despachar, cada degrau com o dado do anterior.
- **Dependências:** E15 (ordem), E9 (habit hook), pesquisa em background (Agent).

### E17 — Maestro conduz a orquestra (P0, L) — design doc aprovado 2026-08-31, office-hours D1-D11 + Codex + 3 rodadas de review
Origem: três ideias ditadas pelo Capitão — regência (todo contato com o aprovador chega
como partitura crua, pressupondo que ele conhece o código), trilhos (execução até o fim
exige docs vivos e roadmap explícito) e compilador de intenção (ditado → interrogatório →
spec → roadmap → plano regido → execução) — mais a absorção conceitual da suíte
architect-orchestrator/system-architect/security-architect/ux-architect (nascida para
gerar a documentação de partida de um projeto). Decisão de escopo: **abstrair e condensar
os conceitos nos mecanismos que o Maestro já tem, nunca importar as skills** (Approach C —
partitura como artefato próprio em `~/.maestro/scores/` — rejeitado por violar a Premissa
4: nenhuma classe de artefato nova). Princípio (Approach B, escolhido): **trilho onde o
trilho alcança** — 3 pontos de enforcement MECÂNICO (brief regido exigido pelo gate no
decide, flags tipadas como campo validado do record, EPICS.md governado pelo E16) + 1
reforço tardio (nag no habit hook) + o resto declarado como compliance ASSISTIDO (injeção
+ julgamento do diretor), nunca fingido de mecânico.
- **S-1701:** `maestro decide` ganha `--depth standard|deep|day-zero` (semântica: standard
  = plano ≤10 linhas; deep = plano + atualização dos docs canônicos das fronteiras
  tocadas + roadmap no EPICS quando multi-fase; day-zero = pacote completo na profundidade
  do `--profile`) e `--profile prototipo|piloto|produto` (obrigatório SSE `--depth
  day-zero`; perfil `prototipo` gera docs enxutos com declaração escrita de que não cobrem
  produção). Ganha também `--brief` com os três marcadores obrigatórios
  `essencia:`/`impacto:`/`approach:` (cada ≤200 chars, total ≤700; `approach: pendente` é
  valor válido no decide — o approach nasce completo só quando o plano existe, atualizado
  depois por `maestro conduct`, S-1702). Ponto de enforcement: **decide-time** — o CLI
  recusa gravar record de workflow **plan-gated** (`gate: plan` na routing table:
  `feature`, `refactor`) sem os 3 marcadores no formato mínimo (cli.ts já parseia `gate`
  da routing table; o pre-tool-gate continua workflow-agnóstico, preservando o NFR de
  latência <50ms). Verificação declaradamente um teto: presença + formato greppável prova
  que o brief existe, não que é bom — qualidade é responsabilidade do diretor. Limitação
  honesta: a allowlist do gate (`.md`, `docs/`) segue passando sem decision record
  (decisão existente do ADR-003, mantida) — sessão doc-only, inclusive day-zero, NÃO é
  bloqueada por falta de brief; comportamento coberto por teste, não corrigido. *AC: gate
  exige os 3 marcadores em workflow plan-gated; caps de tamanho aplicados com truncamento
  avisado (precedente `reason` ≤120); `--profile` exigido sse `day-zero`, rejeitado nos
  demais; doc-only passa sem record (teste documenta o comportamento, não o bloqueia).*
- **S-1702:** verbo de mutação `maestro conduct --session <id>` (precedente: muta o record
  como `maestro outcome`, pós-decide). `--flag "sev|decisao|tradeoff|mitigacao"` repetível
  (append em `flags[]` do record; cada campo ≤120 chars, `sev ∈
  {critical|high|medium|low}`) e `--approach "..."` (≤200 chars, substitui o `approach:
  pendente` do brief). Evento `conduct` entra no vocabulário fechado do log (chave
  `session_id`, nunca o texto da flag). `maestro doctor` valida o schema de `flags[]`
  (severidade fechada, campos truncados/avisados) e emite **WARN** quando um record tem
  `outcome` (S-1001) registrado com `approach:` ainda `pendente` — desfecho fechado sem
  approach preenchido é sinal de partitura incompleta. Regra de soberania explícita: flag
  que contesta decisão já coberta por ADR é fechada pelo diretor CITANDO O ADR — não sobe
  ao humano, não reabre a decisão. Só `critical`/`high` sobem ao humano regidas (essência/
  impacto/approach, não a flag crua). *AC: schema de flags validado pelo doctor; approach
  pendente + outcome presente → warn nomeado; sev fora do enum reprova; evento `conduct`
  no vocabulário sem texto livre.*
- **S-1703:** `H7` em `execution_heuristics` — profundidade é julgamento do diretor
  (`standard` default; `deep` quando a mudança toca fronteira de docs canônicos ou é
  multi-fase; `day-zero` NUNCA automático, só por comando confirmado explícito do humano,
  nunca inferido de projeto vazio — preserva o brownfield silencioso do S-1602). Bullet
  novo no pedido de aprovação REGIDO em `sec_gate` (seção `## Gates humanos` do
  SessionStart, `hooks/session-start.sh`): o gate plan/ship passa a instruir "apresente
  essência/impacto/approach primeiro; 'mostra a partitura' abre o técnico sob demanda" —
  substitui o formato técnico cru hoje injetado. Bump deliberado do RATCHET de injeção
  (hoje 6800B, `tests/hooks/test-injection-budget.sh`): número final MEDIDO pelo doctor no
  plan de implementação (mesmo protocolo do S-703) — só a heurística curta e a linha de
  regência entram na injeção; o formato detalhado do brief/flags vive no habit hook
  (S-1704), não na injeção (Orçamento de injeção, item 9 do design). *AC: H7 presente e
  testado; linha de regência em `sec_gate`; RATCHET bumpado e medido no mesmo commit;
  ausência de `sec_gate`/heurísticas degrada sem quebrar a injeção.*
- **S-1704:** sensor `regencia` no motor de habit hooks (`hooks/lib/habit-sensors.awk`),
  contador de sessão nos degraus **15/40** (padrão do motor S-901/test-gap — dispara tarde
  o bastante para não virar ruído no 1º edit, diferente do S-1603b que dispara no 1º edit
  para área governada por doc). Limitação honesta e DECLARADA: PostToolUse de
  Edit/Write/MultiEdit **aproxima** os contatos de fim de sessão (dispara no enésimo
  edit), **não os intercepta** — contato sem edit subsequente não recebe nag;
  interceptação real via hook Stop/SessionEnd (hoje inexistente em `hooks.json`) fica
  registrada como **fora do E17** (ver "Fora do v1" abaixo). `config/habit-guides/
  regencia.md` pareado (padrão S-902: todo sensor tem guia, ou o doctor reprova). Quita a
  dívida de teste **S-1603b** deixada em aberto pelo E16 (nag tardio de doc-governed sem
  cobertura própria) no mesmo lote de testes. *AC: nag no degrau 15 e reforço no 40, não
  antes; guia presente (doctor reprova sensor órfão); dívida S-1603b com teste próprio;
  kill-switch e degradações herdam o padrão do motor.*
- **S-1705:** `agents/seguranca.md` e `agents/ux.md`, roster novo em **opus** — exceção
  CONSCIENTE ao tiering por custo do ADR-004 (ver ADR-009): responsabilidade de design
  (superfície de segurança e de UX erram caro) + contexto ENXUTO do subagente preserva o
  contexto do diretor — a causa nº 1 de falha de sistemas multi-agente apontada pela
  literatura de 2026, citada no design doc. Contrato de output com `flags[]` (S-1702).
  Destilados das personas `security-architect`/`ux-architect` da suíte já existente,
  filtrados por `.maestro.yaml::experts` como qualquer outro especialista — o Maestro não
  os ativa por conta própria; entram no roteamento quando o projeto os lista. Carona sem
  AC própria (corte primeiro se apertar): `arquiteto.md` absorve vocabulário do
  `system-architect`. *AC: frontmatter `model: opus` + `tools` mínimas; description como
  gate de custo (padrão `arquiteto.md`); sem colisão de gatilho com o roster existente;
  ausente do `experts:` não aparece na injeção.*
- **S-1706:** `EPICS.md` (este arquivo) governado pelo E16 — frontmatter `covers:
  docs/architecture/**` (granularidade de DOCUMENTO, não de linha, evitando o fan-out do
  S-1601: covers amplo dispararia a guarda anti-fan-out). **Entregue 2026-08-31.**
- **S-1707:** estas emendas — ADR-009 em `ARCHITECTURE.md`, Emenda v1.7 em
  `DATA_MODEL.md`, blocos `maestro decide`/`maestro conduct` em `API_SPEC.md`, e este
  épico em `EPICS.md`, todos no mesmo changeset (regra do contrato de docs, E16).
- **S-1708:** flags de dissenso sobrevivem ao re-decide — o decide idempotente reescrevia o record e evaporava o flags[] que o conduct gravou (visto em produção no NetForge, 2026-08-31: conduct flags_n=4 seguido de decide que apagou o conteúdo; o log guarda só contagem, por contrato). cmdDecide agora faz merge do flags[] existente no record novo, inclusive quando workflow/mode mudam — a trilha é da sessão. Apagar flags exige apagar o record. **Entregue 2026-08-31.**
- **S-1709:** diagrama de arquitetura como contrato de milestone — archify vira ferramenta local (~/.tools/archify, fora da listagem de skills: custo zero de contexto nas sessões comuns); fonte determinística versionada em docs/assets/architecture.json (evidence-backed: meta.repository.revision = commit verificado) + HTML entregue ao lado; check warn-only no doctor compara a revision do JSON com o commit da última tag e acusa diagrama atrasado em relação à release. Rito de release ganha o passo: regenerar + Architecture Delta contra a release anterior. **Entregue 2026-09-01.**
- **Fora do v1, com registro:** interceptação REAL dos contatos de fim de sessão via hook
  Stop/SessionEnd (hoje inexistente em `hooks.json` — questão aberta do design, épico
  próprio); day-zero bootstrap ASSISTIDO além da convenção manual (o valor `day-zero` do
  `--depth` e o `--profile` ficam usáveis por convenção; o fluxo guiado de proposta fica
  para depois, corte já previsto na "ordem de corte" do design); nag de regência não
  intercepta contatos sem edit posterior (limitação estrutural do PostToolUse, não bug);
  detecção de marcador do brief por substring sem âncora — texto livre contendo
  "approach:" dentro de outro marcador pode fatiar/substituir errado sem erro (P3 do
  review 2026-08-31); fix real exige parsing ancorado nos 3 marcadores.
- **Dependências:** E16 (docs), E13 (evidence), E10 (consent/outcome).

### E18 — Calibração guiada por telemetria (P1, S) — aberto 2026-09-01, motivado pelo retro do NetForge
- **S-1801:** a taxa de override do retro conta só comando ROTEÁVEL — o sensor ADR-008 loga todo prompt com `/`, mas 12/12 overrides da janela eram ciclo de vida (context-save/restore, upgrade, login) e a taxa saiu 21% (real: 0%), disparando "calibrar antes de endurecer" em falso. `cmd_retro` deriva o conjunto roteável da própria routing table (alvos `skill:` dos bindings + nomes de workflow), reporta roteável e não-roteável separados, e o sinal ≥20% + critério de promoção warn→block usam só os roteáveis. Sensor intacto: dado bruto preservado. **Entregue 2026-09-01.**
- **S-1802:** label de ordem sem fresta — o contrato da ordem sugeria o oid CRU
  (order-001 se o humano digitou 001) enquanto os leitores normalizam (order-1):
  seguir a sugestão gerava recibo invisível e custou uma rodada real de 14min
  (relato do Capitão, NetForge). Sugestão agora derivada da MESMA fórmula do
  leitor; leitor avalia os dois candidatos (canônico e acolchoado) até um
  PROVAR — recibo velho canônico não sombreia recibo fresco acolchoado;
  comentário do código conta a verdade. **Entregue 2026-09-01.**
- **S-1811 — `session_end` emitido (v1.11.1, 2026-09-01):** o evento existia no vocabulário
  desde o E2 e nada o emitia; sessão que acabava sem `outcome` era invisível ao retro.
  `hooks/session-end.sh` (bash puro, sem jq) loga `decided`/`settled` por presença no
  record — nada do conteúdo. Doctor passa a esperar 5 eventos; retro imprime `sessões
  encerradas · sem decisão · decididas sem desfecho`. **Entregue 2026-09-01.**
- **S-1810 — fast path da checagem de update (v1.11.1):** a medição completa custava
  ~150ms por sessão mesmo sem fetch (NFR: <100ms por hook). Dentro do intervalo, com
  HEAD e `origin/main` iguais aos SHAs gravados, dois `rev-parse` decidem; leitura de
  estado/config sem `sed`. Medido: ~50ms sobre a sessão sem checagem. **Entregue 2026-09-01.**
- **Fase 2 registrada, não construída:** calibração de ROTA alimentada por override roteável real (quando existir volume: qual intent falhou, qual frase faltava na tabela); eval blind-judge re-rodado sobre casos vindos de produção.
- **Dependências:** E17 (telemetria de conduct/flags), ADR-008 (sensor).

### E19 — Auto-update via git (P1, S) — aprovado 2026-09-01 ("pode usar rede, desde que nunca quebre a execução")
Origem: o gstack se atualiza sozinho; o Maestro não se atualizava de jeito nenhum — o
README não tinha sequer um passo de `git pull`, e no dia da aprovação a máquina de
desenvolvimento estava com 2 commits sem push e a `main` sem upstream: qualquer outra
máquina que atualizasse ficaria sem dois fixes, sem sinal. Decisão de desenho: o plugin
roda DIRETO do clone (ADR-001), logo atualizar é `fetch` + `merge --ff-only`; a rede entra
no runtime, mas **nunca como dependência** — timeout curto, uma vez por intervalo, falha
silenciosa, e o resultado (inclusive a falha) fica em estado local que o doctor lê.
Silêncio NUNCA significa "atualizado" (lição do gstack #1974). A máquina de
desenvolvimento nunca é sobrescrita: árvore suja, commits à frente ou branch fora da
rastreada bloqueiam o merge; o ff-only já é estritamente seguro e, mesmo assim, só roda
quando não há trabalho local.
- **S-1901 — hook:** `hooks/lib/update-check.sh` (bash puro; única porta de rede do
  Maestro) e `update_step` no SessionStart, ANTES de ler tabela/roster: com
  `auto_upgrade` (default ligado) e estado `available`, aplica o ff-only e **re-executa
  o hook novo** (`exec`, session_id via `CLAUDE_SESSION_ID`, trava anti-loop
  `MAESTRO_UPDATE_REEXEC`) — a sessão inteira nasce na versão nova. Sem auto: uma linha
  no cabeçalho da injeção (`atualização: vX → vY … maestro upgrade`). Bloqueado por
  máquina de dev: linha "push, não pull". Rede falha: nada na injeção, `fetch=failed`
  no `update-state`. Snooze cala só o aviso. Evento `upgrade` (`from`/`to`/`via`) no
  log. Config por máquina em `$MAESTRO_HOME/config.yaml` (DATA_MODEL §10).
  **Entregue 2026-09-01.**
- **S-1902 — CLI:** `maestro upgrade` (fetch forçado, guardas explicadas em pt-BR, delta
  do CHANGELOG entre as versões, `exec doctor --ci` no binário novo), `--check`
  (exit 0/1/2), `--rollback` (`git reset --keep` para o `prev` gravado), `--snooze`
  (24h → 48h → 7d), `--set chave=valor` (config.yaml). `update_check: false` desliga
  só a checagem automática; o comando manual sempre roda. **Entregue 2026-09-01.**
- **S-1903 — doctor:** `check_update_state` (lê o `update-state`: disponível → warn com o
  comando; falhou ou último fetch >7d → warn "silêncio não é atualizado"; bloqueado →
  ok nomeando a máquina de dev) e `check_upstream` (higiene da máquina de
  desenvolvimento: commits sem push e `main` sem upstream viram warn — a fresta
  encontrada no dia). Envelope `capabilities.json` ganha `update.{result,local,remote}`.
  **Entregue 2026-09-01.**
- **Fora do épico:** atualização da cópia em cache do Claude Code (o marketplace de
  diretório executa o repo, S-710 já vigia divergência); notificação ativa (push) —
  a linha na injeção e o doctor bastam para single-user.
- **Dependências:** ADR-001 (emenda), E7 (doctor/envelope), ADR-008 (log).

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
