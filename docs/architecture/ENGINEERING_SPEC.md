# ENGINEERING_SPEC.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.0 — 2026-08-08
**Consome:** ARCHITECTURE.md, DATA_MODEL.md, API_SPEC.md, EPICS.md | **Consumido por:** sessões de vibe-code, architect-orchestrator

---

## Layout do repo

```
maestro/
├── .claude-plugin/plugin.json    # manifesto do plugin
├── hooks/
│   ├── session-start.sh
│   ├── pre-tool-gate.sh
│   └── lib/common.sh             # killswitch check, log helper, flock
├── bin/
│   └── maestro                   # CLI Bun/TS (decide|status|log|doctor)
├── src/                          # fonte TS do CLI
├── agents/                       # roster (frontmatter: model, tools, upstream)
├── config/
│   └── routing-table.yaml
├── vendor/                       # prompts upstream pinados (referência, não instalados)
├── tests/
│   ├── hooks/                    # bats
│   └── cli/                      # bun test
└── docs/                         # documentação (brief, architecture/, decision-log)
    ├── PROJECT_BRIEF.md
    ├── architecture/
    └── decision-log.md
```

**Regras de fronteira:**
- `hooks/` NUNCA importa de `src/` nem invoca Bun — bash puro + `lib/common.sh` (latência do gate).
- `src/` (CLI) nunca lê o stdin de hook — contratos separados (API_SPEC §1 vs §2).
- `agents/` não contém lógica — só markdown com frontmatter; mudança de comportamento de agente = mudança de prompt, revisada em PR.
- `vendor/` é read-only por convenção; adaptações vivem em `agents/` com header `# upstream:`.

## Convenções

- Bash: `set -euo pipefail`, shellcheck no CI; toda saída de bloqueio via stderr com prefixo `Maestro:`.
- TS: Bun, strict, sem dependências além do stdlib do Bun (CLI precisa sobreviver a `bun upgrade`).
- Commits: conventional commits; PR pequeno (1 story); 1 mudança de schema (YAML/JSON) por PR com bump de `version`.
- pt-BR nas mensagens ao usuário; inglês em identificadores.

## Regras canônicas (nunca forkam)

| Regra | Casa |
|---|---|
| Kill-switch é a PRIMEIRA linha de todo hook | `hooks/lib/common.sh` |
| Log nunca bloqueia operação; nunca contém prompt/caminho completo | `common.sh::log_event` |
| Decision record é por session_id | `src/decide.ts` |
| Allowlist de não-código | `config/routing-table.yaml::gate.allowlist` |
| Injeção ≤ 2k tokens | teste `tests/hooks/injection-budget.bats` |

## Estratégia de testes

- **Hooks (bats):** kill-switch; gate bloqueia/permite conforme record; allowlist; latência (<50ms, medida no teste); falha de leitura degrada com exit 0.
- **CLI (bun test):** validação de args; exit codes; idempotência do record; agregação do `log --summary`.
- **Golden files:** saída do SessionStart para 3 cenários (sem profile, com profile, roster filtrado) — todo caso real estranho vira fixture.
- **Teste de fumaça de integração:** script que simula stdin de hook do Claude Code (payloads reais gravados em `tests/fixtures/`).
- Cobertura: sem meta numérica; obrigatório cobrir as 5 regras canônicas.

## CI/CD

- CI (repo git): shellcheck + bats + bun test + `maestro doctor --ci` + validação de schema dos YAML.
- "Deploy" = `git pull` no clone local + `/plugin` reload; rollback = `git checkout <tag>`. Tags semver a cada fase do roadmap.

## Observabilidade

- `~/.maestro/logs/routing.jsonl` (DATA_MODEL §4) é a única telemetria; `maestro log --summary` é o dashboard.
- Métrica de produto de primeira classe: **% de tarefas sem override manual** (meta <20% de override em 3 meses — brief).
- Redação: nunca logar `tool_input.file_path` completo (só extensão), nunca conteúdo de prompt.

## CLAUDE.md do repo (copiar para a raiz)

```markdown
# Maestro — camada de roteamento MoE para Claude Code

Plugin local: hooks determinísticos + routing table + roster de agentes.
Filosofia: trilhos determinísticos (hooks garantem QUE a decisão acontece),
IA nas bordas (o Claude da sessão decide O QUE fazer, guiado pela tabela).

## Fronteiras (invioláveis)
- hooks/ = bash puro, nunca invoca Bun, nunca importa src/
- Kill-switch MAESTRO_OFF=1 na primeira linha de todo hook
- Logs: só metadados; jamais prompt, jamais caminho completo de arquivo
- agents/ = só markdown; vendor/ = read-only
- Falha de qualquer componente degrada para o fluxo manual — nunca bloqueia trabalho

## Docs canônicos
docs/architecture/ARCHITECTURE.md (ADRs) · DATA_MODEL.md (schemas) ·
API_SPEC.md (contratos hook+CLI) · EPICS.md (escopo — nada fora dele sem emenda)

## Proibido
- float em qualquer métrica de custo (usar inteiros de tokens/centavos)
- dependência de rede em runtime (a única chamada de rede é o fetch do auto-update, E19:
  timeout curto, uma vez por intervalo, falha silenciosa — rede nunca bloqueia nem quebra)
- editar vendor/ no lugar
```

## Template de sessão de vibe-code

1. Reler EPICS.md (story alvo) + fronteiras do CLAUDE.md
2. Declarar a story (S-xxx) no início da sessão
3. Implementar dentro das fronteiras — dogfood: registrar a própria decisão via `maestro-decide` assim que E2 existir
4. Rodar suíte (bats + bun test + doctor)
5. Apêndice em `docs/decision-log.md`: o que decidiu, o que descartou, flags

## Flags para o orchestrator

Nenhuma.
