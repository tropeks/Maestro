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
Origem: docs/research/RAD_PATTERNS_FOR_MAESTRO.md §7-P0 + ECC_DELTA_AUDIT.md §5-P0.
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
- **S-703:** ratchet da injeção SessionStart (context-bill: medir bytes reais injetados
  contra o teto de 8000B com protocolo de ratchet + linha no doctor). *Pendente.*
- **S-704:** doctor: check de `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` ativo (teams podem
  se formar sem pedido) + linha nomeando MCP servers conectados como fora-do-envelope.
  *Pendente.*
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
- **Dependências:** E2 (CLI/record), E4 (tabela + instrumento de eval).

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
