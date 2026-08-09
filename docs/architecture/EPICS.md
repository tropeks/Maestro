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
