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

## Convenção `[spock] aguardando:` (protocolo de fim de rodada)

Ordem do Capitão da Vulcan, 2026-09-12. Quando uma sessão de agente **termina a
rodada precisando de algo de quem a supervisiona** — aprovo/ajusta, aceite,
decisão, "vai", credencial, root —, a **última linha da resposta** é exatamente:

```
[spock] aguardando: <o quê, em até 10 palavras>
```

Rodada que termina sem precisar de nada **não** leva a linha.

**Por que é linha de resposta e não arquivo de estado:** quem lê é a ronda do
supervisor, varrendo a tela da pane pelo herdr. Um agente que travou no meio do
turno não consegue escrever arquivo nenhum, mas o que ele já imprimiu continua
na tela — e o caso que mais custa é justamente esse.

**Por que existe:** sem ela, o supervisor descobre que um agente parou só quando
olha. Custou 6 h de trabalho parado num dia em que quatro agentes terminaram a
rodada esperando resposta e nada os denunciou. A ronda cobre o resto com
"pane idle há mais de 20 min", porque protocolo só pega quem o segue: agente que
morreu ou esqueceu a linha não declara nada, e é o que fica invisível mais tempo.

**Assimetria de custo, declarada pelo Capitão:** *"falso positivo custa um olhar
meu; falso negativo custou 6h hoje"*. Na dúvida, avisar.

## O turno da ordem e o relatório de fim de turno (ordem 046)

A ordem diz o QUE entregar; o bloco `## Turno` diz o que cabe num turno e quando ele
termina. Cinco rótulos, uma linha cada, dentro da seção `## Turno` (esqueleto emitido por
`maestro order --create`):

- `fatia:` o que cabe num turno · `fim:` o critério de término — comando que sai 0/1, nunca
  "quando estiver bom" · `teto:` rodadas máximas, **inteiro ≥ 1** (o Stop usa no máximo 3 por
  sessão) · `fora:` o que este turno NÃO faz · `relatório:` onde está o contrato abaixo.

**Relatório fixo de fim de turno** — cinco rótulos, nesta ordem, no fim da última mensagem
da rodada (relatório é ESTADO, não jornada): `feito:` · `provado:` (o comando e o rc, ou
"não provado") · `aberto:` · `decisão:` (o que exige o Diretor, ou "nenhuma") · `próximo:`.
Este é o contrato citado no rótulo `relatório:` de cada ordem.

**O que é trilho e o que é honra** (Prioridade 3 do INTENT, decisão do Capitão, 2026-10-02):

| | trilho (mecânico, sem LLM) | honra declarada (nenhum hook alcança) |
|---|---|---|
| presença | `conform --check` acusa ordem sem `## Turno` / sem `relatório:` | — |
| fim de turno | o **Stop** lê o ledger: recibo VÁLIDO no tip, e os recibos de área exigidos; sem eles, bloqueia com a lista do que falta, até o teto | o `fim:` foi bem escolhido; a fatia coube no turno |
| relatório | os rótulos faltantes entram na lista de faltas (checagem ADICIONAL — sozinhos não bloqueiam) | o TEXTO do relatório é verdadeiro: um `provado: rc 0` inventado não é detectável |

O Stop **não executa** o `fim:` (comando arbitrário num hook viola a fronteira de `hooks/`);
confere o recibo que o executor gravou. Válvula escrita e visível: `maestro order
--turno-livre <N>`, para a ordem cuja natureza não cabe em turno. Falha de qualquer parte
degrada para liberar — a Prioridade 1 vence a 3.

**Orçamento medido e o contrato do 124 (ordem 056).** O `order --turno-check` custava ~1,7 s
(load 9–10 em 8 CPUs, worktree com 51 ordens) e estourava o `timeout` de 2 s; o hook tratava o
124 como "libera" e o turno terminava sem relato. Medição por fase (mediana, mesmas condições):
busca da ordem do branch ~600 ms (2 `awk` de carimbo por ordem × 51), `_order_status` ~200 ms,
verificação por área ~400 ms, bloco `## Turno` ~65 ms (5 `awk`); por baixo, `_order_field`
forkava 18× e a chave do ledger (`maestro_brief_file`: `cd -P`, `git rev-parse` no worktree,
`$(...)` do chamador) era resolvida ~8×. Corte: ordem achada pelo NNN do branch (varredura só
de reserva), `_order_field`/`_order_valid_stamp` em bash puro, bloco `## Turno` e rótulos do
relatório em uma passada, chave do ledger resolvida uma vez (`maestro_brief_prime`). Depois:
~500 ms sob a mesma carga (meta do Diretor: < 700 ms sob carga). O teto do `timeout` **fica em
2 s** (`TURNO_TIMEOUT_S`): subir o teto mascararia a regressão. Contrato do 124, escolha (a) do
Diretor: em timeout o hook confere LOCALMENTE os 5 rótulos de `TURNO_REPORT_LABELS` na última
mensagem, sem chamar o CLI; faltou rótulo, bloqueia com a lista; os 5 presentes, libera; sem
mensagem legível ou qualquer falha da checagem, libera (Prioridade 1). O evento `turno_timeout`
(só metadados) vai ao log. O hook reconhece o 1º rótulo colado ao `"text":"` do JSON da linha.

## Limites da autoproteção (ordem 047) — trilho e honra

A autoproteção de `self_paths` (`agents/ bin/ src/ hooks/ lib/ config/routing-table.yaml
config/accept-proof.pub .claude-plugin/`) é trilho em DOIS lugares: `pre-tool-gate` (Write/Edit/
MultiEdit) e `pre-bash-guard` (formas de escrita por Bash, ordem 047). Cobertas, cada uma com
teste: `>` `>>` `&>` `>|`, heredoc, `tee`, `sed -i`, `perl -i`, `cp`, `mv`, `install`, `dd of=`,
`ln`, `truncate`, `python`/`node`/`ruby`/`perl` com alvo protegido; em caminho relativo,
absoluto, `./`, `../` e de worktree. **Honra declarada — o guard lê o comando, não o programa:**

| não coberto | por quê |
|---|---|
| script gravado FORA de `self_paths` e executado depois (`bash /tmp/x.sh`) | o alvo está dentro do arquivo, que o guard não lê |
| `git apply docs/patches/…` | o caminho do comando é `docs/`; o patch é que toca `bin/` |
| `eval`, `D=li; echo x > ${D}b/…`, `cd lib && echo x > a.sh` | o caminho não aparece inteiro no texto |
| symlink para dentro de `self_paths` | não se resolve link |
| ferramenta de escrita fora da lista (`rsync`, `awk -i inplace`, editor) | a lista é fechada |

O caminho legítimo é o molde das ordens 045/046: clone sandbox FORA do repo do plugin, patch em
`docs/patches/`, `git apply` por mão humana. Nenhuma dessas lacunas é consentível.

## Template de sessão de vibe-code

1. Reler EPICS.md (story alvo) + fronteiras do CLAUDE.md
2. Declarar a story (S-xxx) no início da sessão
3. Implementar dentro das fronteiras — dogfood: registrar a própria decisão via `maestro-decide` assim que E2 existir
4. Rodar suíte (bats + bun test + doctor)
5. Apêndice em `docs/decision-log.md`: o que decidiu, o que descartou, flags

## Flags para o orchestrator

Nenhuma.
