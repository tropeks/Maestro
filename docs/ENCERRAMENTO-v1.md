# Maestro v1 — encerramento

**Encerrado em 2026-09-22, ao fechar a ordem 039** (decisão do Capitão na Ponte,
`01M325G8FJKQ4AW1HAXMBD8AWE`). Direção final: **INTENT v6**. Este documento é o estado
final: o que o Resultado prometeu e o que foi medido, o que fica de dívida com endereço, e
onde a Fase 2 mora.

Nenhum número aqui é novo. Todos saem do INTENT, do CHANGELOG ou do ledger — este
documento aponta, não mede.

## 1. Os bullets do Resultado, medidos

| bullet | número | onde |
|---|---|---|
| override <20% | **0%** roteável · 479 decisões / 14d | `maestro retro` |
| skill/sessão 0–1 | **1** comando / 48 sessões | `maestro retro` |
| zero correção manual de modo/modelo | sensor `route_fix` **existe** (ordem 030) | `hooks/user-prompt-submit.sh` |
| retro elegeu warn→block | aplicado, `gate.mode: block` | `maestro retro` |
| eval cego 73% → 100% | 100% prescrito (r6) · campo com ressalva (ordem 031) | `docs/ROUTING_EVAL.md` |
| funil com `started` real | planned 153 · **started 255** | `maestro delegation --all` |
| `verify --check` recusa sem recibo | área tocada → **rc=1** | `maestro verify --check` |
| `stable` só com CI verde | `stable` = commit do diagrama, job "aprovar" success | `.github/workflows/ci.yml` |
| ordens citam versão do INTENT | **40/40** | `maestro order --list` |
| `killed` na janela | **3** em 14d | `maestro retro` |
| gatilho da Fase 2 | **0,2% em 481 decisões / 30d** — cumprido-e-encerrado | `maestro retro` |

**Dois bullets fecham por MECANISMO, não por número, e isso é dito por extenso** — está no
INTENT desde a v4 e continua valendo:

- *"zero correção manual de modo/modelo"* era **inverificável** até a ordem 030: nenhum dos
  17 tipos de evento registrava correção em linguagem natural. A 030 entrega o sensor
  `route_fix`; o NÚMERO vem quando houver janela. Encerrar com o sensor de pé e sem o
  número é honesto; declarar "zero" sem poder medir seria o oposto.
- *"eval cego 100%"* é o melhor de seis rodadas contra os MESMOS 15 casos, com sobreajuste
  declarado. O número de CAMPO existe (ordem 031) e mostrou que a definição do instrumento
  varia de **11% a 81%** conforme um termo. Registrado, não maquiado.

## 2. O estado do ledger no encerramento

**40 ordens.** 24 absorvidas · 14 aceitas · **1 aberta** · 1 em execução (esta).

A única ordem viva é a **028 — prova de calibração do Jev**, e ela fica aberta **por
decisão**: acerto × confiança por faixa contra a base rate, ANTES de dar poder ao
classificador. Sem conta ainda. Ela não bloqueia o encerramento; ela guarda a porta de quem
vier depois.

Duas ordens da última onda merecem menção porque mudam como o resto se lê:

- **036** deu ao ledger o campo `work_project`: ordem cujo trabalho vive em outro repo
  fecha o ciclo sem ninguém forçar carimbo. Foi ela que destravou a 033.
- **039** abriu `agents/` para exatamente duas chaves de frontmatter (`effort`,
  `omitClaudeMd`) por equivalência por remoção, mantendo o resto do roster barrado.

## 3. O que fica de dívida — com endereço, não com adjetivo

**Limites conhecidos do próprio gate:**

- **Sem `jq`, o gate INTEIRO degrada aberto** (`hooks/pre-tool-gate.sh:180`:
  `command -v jq || exit 0`, antes de qualquer denylist). É ADR-003 v1.1 + Prioridade 1,
  vale para a denylist toda, e a ordem 039 **não a alargou** — a exceção do roster falha
  fechada em tudo que ela controla. Decisão do Capitão (2026-09-22): aceitar e registrar
  aqui, em vez de abrir ordem.

**Dívidas declaradas no código:**

- `lib/cmd-order.sh` — o corpo da ordem ainda tem teto de 16 KiB. A ordem 037 fechou o
  *hang* e o corte silencioso; o teto em si é o gêmeo restante da issue #43.
- `src/cli.ts` não lista `route_fix` em `EVENTS` → `maestro log --summary` conta o evento
  da 030 como desconhecido. Declarado na emenda do DATA_MODEL, não silencioso.
- `hooks/gate-report.sh` usa `{1,200}` ao extrair `essencia:` — ~11ms FLAT por invocação
  (custo de COMPILAR o quantificador), ~22% do NFR de 50ms. Mesma família da issue #42.
- `installed_plugins.json` aponta para cache inerte de 10/09. **Provado** que hooks, CLI e
  MCP vêm do REPO — é bookkeeping, mas confunde quem for depurar.
- `bubblewrap` + `socat` na forge destravam o eval com Bash de verdade (ordem 023).

**Issues abertas (11):** #43 (fechada de fato pela ordem 032 — confirmar e encerrar no
GitHub), #42, #39, #38, **#36** (recibo provado em worktree lido da árvore principal —
deixada aberta POR DESENHO na ordem 036 e nomeada num teste), #25, #23, #22, #20, #19, #18.

**Dívida de higiene:** worktrees e branches das ordens já terminais podem ser podados; o
resgate dos tips é `git for-each-ref` antes de qualquer `-D`.

## 4. Onde a Fase 2 mora

O gatilho era um número, não uma data, e ele **disparou**: 0,2% de override em 481
decisões, janela de 30 dias, 16 projetos. Por decisão do Capitão
(`01M325G8FJKQ4AW1HAXMBD8AWE`, 2026-09-22), a Fase 2 — multi-usuário/QM e a camada MCP
dinâmica `activate(domínio, projeto)` — sai como **projeto próprio ou wishlist**.

Ela **não é dívida do v1**. Está destravada, está fora, e está escrita no INTENT em "Fora
de escopo" para ninguém reabrir por engano.

## 5. O que este encerramento não faz

Não congela o repo: manutenção continua possível, e continua entrando pelo trilho — ordem
escrita, prova exigida, branch próprio, recibo no tip, aceite do Diretor. O que muda é o
padrão: **nada novo sem ordem do Capitão.**
