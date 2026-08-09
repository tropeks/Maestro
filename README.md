# Maestro (v1.0 — E1 a E5)

Camada de roteamento MoE para Claude Code. Estado atual: **E1 a E5 completos** —
injeção da routing table no SessionStart, gate estrutural no PreToolUse,
CLI `decide|status|log`, logging do override manual e roster de 9 agentes
tierizados. E4 (curadoria dos packs) é o próximo épico — ver
`docs/architecture/EPICS.md`.

Filosofia: trilhos determinísticos (hooks garantem QUE a decisão acontece),
IA nas bordas (o Claude da sessão decide O QUE fazer, guiado pela tabela).

## Instalar (local)
```
git clone https://github.com/tropeks/Maestro ~/dev/maestro
claude  # dentro do Claude Code:
/plugin marketplace add ~/dev/maestro
/plugin install maestro@maestro
```

## Validar
```
~/dev/maestro/bin/maestro doctor      # 21 checagens; --ci para pipeline
bash ~/dev/maestro/tests/run-all.sh   # suíte completa (698 asserções)
```

A CI (`.github/workflows/ci.yml`) roda exatamente isso a cada push/PR, mais
`shellcheck` em `hooks/`, `bin/maestro` e `tests/`. O gate do shellcheck bloqueia
em `error`; `warning`/`info` saem como anotação no PR enquanto a dívida não fecha.

## Uso

O SessionStart injeta um bloco `<maestro-routing>` com o `session_id` da sessão,
as rotas, as heurísticas de execução e a instrução canônica. Antes de editar
código, registre a decisão:

```
maestro decide --session <id> --workflow fix --mode subagent --agents golang-pro \
               --reason "bug em 1 módulo Go"
```

Sem decision record válido (TTL 4h), o gate **avisa** em toda edição de código —
`gate.mode: warn` é o default. A promoção para `block` é uma linha em
`config/routing-table.yaml`, depois de uma semana de dados reais (roadmap Fase 1b).

```
maestro status         # decisão corrente, validade, últimos eventos
maestro log --summary  # o dashboard do baseline: override manual, gate, agentes
```

## Roster

Nove agentes, com o modelo proporcional à complexidade do papel:

| agente | model | quando |
|---|---|---|
| `dev-junior` | haiku | tarefa mecânica de escopo fechado |
| `dev-pleno` | sonnet | feature/bugfix que exige julgamento |
| `engenheiro` | sonnet | arquitetura e plano (pede Opus na saída quando precisa) |
| `revisor` | sonnet | review **read-only** — sem Write/Edit/Bash |
| `qa` | sonnet | teste funcional e evidência |
| `golang-pro` `python-pro` `typescript-pro` `postgres-pro` | sonnet | linguagem detectada vence o perfil de senioridade |

Os quatro especialistas são adaptados de [wshobson/agents](https://github.com/wshobson/agents)
(MIT), com os originais pinados por commit em `vendor/` e atribuição no frontmatter.

Um `.maestro.yaml` na raiz do projeto restringe o roster ativo:

```yaml
version: 1
project: remedix
languages: [go]
experts: [golang-pro]     # só ele aparece na injeção
```

## Autoproteção

O gate bloqueia **sempre**, mesmo com decisão registrada:

- `.claude/` e `.github/workflows/` em qualquer projeto — é por onde se
  desregistram hooks, se injeta `env` e se executa CI;
- `hooks/`, `bin/`, `src/`, `agents/`, `config/routing-table.yaml` e
  `.claude-plugin/` **sob a raiz do plugin** — o roteador não reescreve as
  próprias regras (ADR-003 v1.1).

Trabalhando no repo do próprio Maestro, isso significa que um agente edita
`docs/`, `tests/` e `README.md`, mas não o gate nem o CLI — esses são do humano.

## Kill-switch

`MAESTRO_OFF=1` desativa todos os hooks instantaneamente. Nenhum componente do
Maestro bloqueia trabalho: qualquer falha degrada com exit 0.

## Privacidade

O log (`~/.maestro/logs/routing.jsonl`) carrega **só metadados**, com chaves
tipadas e vocabulário fechado. Nunca o texto do prompt, nunca o caminho completo
de um arquivo — só a extensão. Nenhuma chave aceita `/`.

## Licença

São **duas licenças diferentes** no mesmo repositório, e elas não se misturam:

| O quê | Licença | Titular |
|---|---|---|
| O Maestro — `hooks/`, `bin/`, `src/`, `config/`, `docs/`, `tests/` e os 5 agentes próprios (`dev-junior`, `dev-pleno`, `engenheiro`, `revisor`, `qa`) | MIT (`LICENSE`) | © 2026 Romulo de Jesus Costa |
| `vendor/wshobson-agents/` — cópias verbatim de [wshobson/agents](https://github.com/wshobson/agents), pinadas por commit em `PINNED.md` | MIT (`vendor/wshobson-agents/LICENSE`) | © 2024 Seth Hobson |
| `agents/golang-pro.md`, `python-pro.md`, `typescript-pro.md`, `postgres-pro.md` — **adaptações** (obras derivadas) do material acima | MIT do upstream | © 2024 Seth Hobson, adaptado |

Escolher MIT para o projeto **não relicencia** o material vendorizado: ele
continua sob a MIT do Seth Hobson, com o aviso de copyright dele preservado em
`vendor/wshobson-agents/LICENSE`. Os quatro especialistas adaptados carregam a
procedência no frontmatter (`# upstream: wshobson/agents@<commit> (MIT, Seth
Hobson)`), que é a atribuição exigida pelo ADR-004. `vendor/` é read-only: toda
adaptação vive em `agents/`, nunca no original.

Por que MIT e não outra: é a mesma licença do material que o repo já
redistribui (zero atrito de compatibilidade), preserva o aviso de garantia — que
importa numa ferramenta cujos hooks liberam ou barram edição de código — e não
cria obstáculo para a fase 2, quando outras pessoas usarem o plugin. Apache-2.0
traria concessão de patente e `NOTICE` sem superfície patenteável que justifique
o overhead; copyleft seria hostil a um plugin carregado dentro de um host
proprietário; domínio público abriria mão da atribuição e do disclaimer.
