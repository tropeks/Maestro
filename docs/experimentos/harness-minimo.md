# Experimento do harness mínimo — a mesma ordem no Maestro completo e num `claude -p` puro

Ordem 077 · INTENT v6 · método: **sem fonte, sem número; sem número, sem recomendação**. Este experimento
**não corta nada**: entrega a tabela e uma recomendação; quem corta é o Capitão.

> **Estado deste documento (fim do turno 1 de 4).** O aparelho está pronto e testado; **nenhum run de
> tarefa foi feito**. As seções 1 a 5 são fatos medidos neste turno. As seções 6 e 7 (tabela e recomendação)
> ficam vazias de propósito até os turnos 2 a 4 — nada nelas é opinião antecipada.

## 1. A ordem escolhida (critério verificado na base)

**Ordem 054** — "reparo dos 8 FAIL pré-existentes da main". Base `41213f0a454bd6c2060d9faa41f91e36ad450047`
(o `head:` da ordem). Texto original: commit `89be67f`, `.maestro/orders/054-reparo-dos-8-fail-preexistentes-da-main.md`.
Solução real (que a base **não** contém): commit `f16dd90`.

| Critério da 077 | Medido | Fonte |
|---|---|---|
| já aceita | carimbo `50af456` | `git log --all --grep=054` |
| ≤ 3 arquivos | **3** (`CHANGELOG.md`, `tests/hooks/test-order-029-gatilho.sh`, `tests/hooks/test-order-038-rodada-corrente.sh`) | `git show --stat f16dd90` |
| ≤ ~60 linhas de diff | **15 inserções, 2 deleções** (17 linhas) | idem |
| não toca caminho protegido (`agents/ bin/ src/ hooks/ lib/ config/routing-table.yaml .claude-plugin/ mods/`) | só `tests/` e `CHANGELOG.md` | idem |
| recibo claro | `bash tests/run-all.sh` sai 0 (os 8 FAIL somem) | Turno `fim:` da 054 |
| **os 8 FAIL aparecem 3 de 3 na base** | **sim**: 029 → **6 FAIL**, 038 → **2 FAIL**, nas três corridas seguidas, na base montada pelo aparelho (`bash …/test-order-029-gatilho.sh` ×3, `…/test-order-038-rodada-corrente.sh` ×3; rc 1 em todas) | corridas deste turno |

FAIL da 029: `paráfrase passou — devia reprovar`, `mensagem não ensina a correção`, `liberou sem evidência de
director.ask`, `mensagem não cita a tool`, `evidência vazou entre sessões`, `sem socket: passou em SILÊNCIO`.
FAIL da 038: `038/2: canônica corrente NÃO segurou ()`, `038/3: paráfrase deixou de reprovar ()`.
Causa (já conhecida pela 054, **não** revelada ao executor): os testes herdam `HERDR_ENV`/`HERDR_PANE_ID` do shell.

Limite desta escolha: a 054 é **reparo de teste**, não feature nova (ver seção 8).

## 2. A base sem futuro

`tools/harness-minimo/montar-base.sh <repo> <commit> <destino>`: `git archive` do commit, `git init`, **um
único commit** (identidade e data fixas), sem remoto, sem tags, sem outros refs. Confere que a árvore da base
é idêntica à do commit de origem e que `git rev-list --all` tem 1 commit; senão sai 1.

Montagem da 054 (duas montagens independentes dão o **mesmo** commit):

```
tree=9e1c1e2816f1318ebf24efa71e177ab52ab07f92
commit=92c7c9e1f356fbf0ff3ffc7d88d28b4007cf7e02
```

`git log --all --oneline` na base: `92c7c9e base do experimento (sem futuro)` (1 linha). O texto da ordem
original **não** está na árvore (ele é posterior ao `head:`): `tools/harness-minimo/extrair-ordem.sh` o tira
do git para um arquivo **fora** da base. Cada run começa do mesmo hash de árvore, registrado em `base-tree.txt`.

## 3. Os dois textos

Uma só fonte: `tools/harness-minimo/texto-da-ordem <ordem.md> <saida> "bash tests/run-all.sh" [prefixo-comum]`
gera `prompt-1.md` (a ordem **inteira**, byte a byte) e `prompt-2.md`. O corte (a hipótese em teste, não o oráculo)
tira **só**: a seção `## Turno`; a seção `## Contrato de execução`; os blocos de citação que abrem por `> **`;
e itens de lista que citam `maestro evidence|order|papercut`, `director_report` ou `habits`. Entra **uma**
seção: `## Critério de pronto` com o comando do recibo da ordem original, escrito como instrução.

Diff real `prompt-1.md` × `prompt-2.md` (a 054):

```
65,66d64
< - Recibos `order-54` **e** `suite` (rótulo legado: a CLI da frota só lê `suite` até a 1.21 girar) no
<   tip exato, árvore limpa; `habits` dentro da catraca.
68d65
< ## Turno
70,74c67
< - fatia: reproduzir os 8 FAIL com saída colada e achar a causa raiz de cada um (diagnóstico)
< - fim: relatório com causa e prova por FAIL; depois da correção, `bash tests/run-all.sh` sai 0 sem FAIL em 029 e 038
< - teto: 4
< - fora: mudar comportamento de hook ou CLI sem teste vermelho que o isole, afrouxar asserção, aceitar a ordem, qualquer ordem além da 054
< - relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido
---
> ## Critério de pronto
76,84c69
< > **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.
< 
< ## Contrato de execução
< - Trabalhe APENAS no branch `order/054-reparo-dos-8-fail-preexistentes-da-main`; NUNCA no main/master.
< - Zonas CONGELADAS (não toque): vendor/
< - Prove com o ledger: `maestro evidence --record --label order-54 -- <suíte>` no tip do branch.
< - Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
< - Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
< - O aceite é do diretor: `maestro order --accept 054` (você não fecha a própria ordem).
---
> Rode `bash tests/run-all.sh` na raiz do repositório e termine quando sair 0.
```

**Achado do corte (decisão pedida ao Diretor):** o `## Turno` da 054 pede **só o diagnóstico** (`fatia:
reproduzir os 8 FAIL … achar a causa raiz`; o reparo vem depois). O prompt-1 mantém essa fatia; o prompt-2 não
tem Turno e pede o reparo até a suíte sair 0. Se nada for feito, a config 1 pode parar no diagnóstico e a 2
consertar: o par deixa de medir o método e passa a medir "ordens diferentes". O aparelho aceita um
`prefixo-comum` (um parágrafo **idêntico** nos dois prompts, por exemplo "Faça o diagnóstico e o reparo, até a
suíte sair 0") — padrão da ordem: sem prefixo; só entra por decisão.

## 4. As duas configurações (reprodução do runner, sem subir o daemon)

Argv de gerente conferido em `src/headless/claudeArgv.ts`, `runFiles.ts`, `envelopeRender.ts`,
`config/childEnv.ts` da main do ponte-daemon (`c0af0c6`). `claude` **2.1.294**. Lançador:
`tools/harness-minimo/lancar.sh --config 1|2` (testado com `claude` falso).

| | Config 1 — Maestro completo | Config 2 — `claude -p` puro |
|---|---|---|
| flags | `-p --output-format stream-json --verbose --model sonnet --session-id <uuid> --mcp-config … --strict-mcp-config --settings … --permission-mode default --permission-prompt-tool mcp__ponte__permission_prompt --permission-prompts host --max-turns 150 --append-system-prompt-file <envelope> "<prompt do runner>"` | `-p --output-format stream-json --verbose --model sonnet --max-turns 150 --safe-mode --strict-mcp-config --mcp-config {} --permission-mode dontAsk --allowedTools=<lista fechada> "<prompt-2.md>"` |
| texto | `prompt-1.md` fora da árvore; o envelope (dez fontes) aponta para ele | `prompt-2.md` como prompt posicional |
| plugin, hooks, mods | carregados (settings de usuário, como o daemon) | desligados (`--safe-mode`) |
| Ponte | MCP stdio `ponte-daemon mcp` + `--permission-prompt-tool`; **project `exp-harness-054`, order_ref `order/054-exp-harness`** (fixture; nunca a 054 real) | nenhuma |
| permissões | allowlist **real** do gerente `maestro` (`docs/experimento/politicas.json`, Spock) | a mesma lista **sem** `Bash(maestro *)`, `Bash(./bin/maestro *)` e `mcp__ponte__*` |
| `maestro` no PATH | sim | não (PATH = atalhos + `/usr/local/bin:/usr/bin:/bin`) |
| ambiente do filho | `env -i HOME PATH TERM LANG XDG_RUNTIME_DIR` + `MAESTRO_HOME` temporário e **vazio** | idem (PATH diferente) |

Iguais nos dois: modelo `sonnet` (alias do `manager_model_policy`; resolve para `claude-sonnet-5-5`), **sem**
`--effort` (o default do modelo; registrado — o runner não passa esforço), `--max-turns 150`, versão do
`claude`, base byte a byte, uma máquina, runs em sequência na ordem **A B B A A B** (A = config 2, B = config 1;
o Diretor pode inverter), `uptime` antes de cada run. O **recibo** da ordem original roda por fora, na árvore
final, no mesmo ambiente neutro (`env -i`), e seu rc é o aceite.

Não reproduzido de propósito: o hook de audit `PostToolUse → ponte-hook.sh` (só fala com run que o daemon
conhece; o run de fixture não é um).

## 5. Prova de carga (`claude --debug`, um `claude -p` de uma linha, sem tarefa real)

Prompt: `Responda apenas: ok` · base montada · modelo `sonnet` · log completo em `debug.log` de cada run
(guardado fora do repo, na pasta temporária do turno; trechos abaixo com a linha do log).

**Config 2 (`--safe-mode`):**

```
Skipping plugin hooks - safe mode disables installed plugins (managed settings-file hooks still run; built-in plugins load regardless)
Safe mode: installed plugins are disabled, none of their hooks or hooks modules load; built-in plugins load regardless
Registered 0 hooks from 4 plugins          (os 4 são built-in do próprio claude)
Hooks: Found 0 total hooks in registry
[claudeai-mcp] Disabled in safe mode
[reduced mode] Skipping skill dir discovery
cc-plugin-agents-md: project memory is off  (CLAUDE.md da base não entra)
init.mcp_servers = []   init.agents = [claude, Explore, general-purpose, Plan]   init.skills = só as embutidas
```

Resultado: 1 turno, tokens `entrada 2 · saída 4 · cache de leitura 12436 · cache de criação 5133`,
**US$ 0,0231 → 2 centavos USD → 12 centavos BRL** (cotação 4,998), parede 4982 ms.

**Config 1 (argv do runner, plugin e Ponte):**

```
Applying permission update: Adding 24 allow rule(s) to destination 'flagSettings': ["Read","Edit","Write","Grep","Glob","Agent","Bash(maestro *)", … "mcp__ponte__director_report"]
Applying permission update: Adding 4 deny rule(s) to destination 'flagSettings': ["Read(~/.ponte/**)","Edit(~/.ponte/**)","Bash(ponte-daemon:*)","mcp__plugin_*"]
Read hooks.json for plugin maestro (enabled=true): /home/rcosta00/dev/Maestro/hooks/hooks.json
Read hooks.json for plugin maestro-guard (enabled=true): /opt/maestro/claude-plugins/maestro-guard/hooks/hooks.json
Loaded 2 commands from plugin maestro default directory / Loaded 13 agents from plugin maestro default directory
Registered 13 hooks from 24 plugins
Hook SessionStart:startup (SessionStart) success: … <maestro-routing> Maestro v1.23.0 — roteamento MoE …
MCP server "ponte": Successfully connected (transport: stdio) in 3327ms … serverVersion ponte-daemon-mcp
```

Resultado: 1 turno, tokens `entrada 2 · saída 4 · cache de leitura 12346 · cache de criação 25444`,
**US$ 0,1043 → 10 centavos USD → 52 centavos BRL**, parede 9747 ms.

Leitura (só do que foi medido): a **carga fixa** do método, num prompt de uma linha, foi **20 311 tokens a mais
de cache de criação** (25444 − 5133) e **+40 centavos BRL** (52 − 12) por turno de partida, e **+4765 ms** de
parede (9747 − 4982). É N = 1 de cada lado, **não** é resultado do experimento — é a prova de que cada
configuração carrega o que deveria.

Ressalvas de isolamento, ditas sem enfeite:
- **CLAUDE.md na config 2:** o log diz "project memory is off" e o `--safe-mode` o desliga por definição; não há
  linha `--debug` que cite o CLAUDE.md da base por nome. Prova indireta, não direta.
- **Settings gerenciados ainda valem** na config 2: `/etc/claude-code/managed-settings.json` impõe
  `prependPlugins: maestro-guard@maestro-managed` (a linha do log diz que ele **não** tem módulo de hook
  habilitado e foi pulado) e as regras de `permissions` do settings de usuário (negações de `git push --force`,
  de edição em `hooks/ lib/ src/ bin/` etc.) aparecem aplicadas como `userSettings`. Valem nos dois lados.
- **Plugins de usuário na config 1:** `superpowers` e `i-have-adhd` (SessionStart) também carregam, porque o
  runner de produção herda o settings de usuário ("como hoje"). São carga do harness, não do método Maestro:
  o relatório final deve separar o que é do `maestro` do que é de outros plugins.

## 6. Orçamento decidido pelo Diretor (09/10) e conversão

**N = 3 por configuração (6 runs) · R$ 20 por run · R$ 120 no total.** Run que estourar o teto **para e
conta como achado** (aceite = não, custo = o teto, motivo anotado); **não se repete**; o total não sobe.

Cotação do dia: **R$ 4,998 por US$ 1** (dólar à vista, 09/10/2026, ~09h30 de Brasília, intradiário —
[InfoMoney](https://www.infomoney.com.br/mercados/dolar-hoje-abertura-fechamento-comercial-turismo-09102026/) e
[ISTOÉ Dinheiro](https://istoedinheiro.com.br/mercado-hoje-ipca-ia-petroleo-9-outubro-2026-3); não é PTAX de fechamento).
No coletor: `--cotacao-milesimos 4998`.

| Teto | Em reais | Em dólar para `--max-budget-usd` (arredondado para baixo, 2 casas) | Reais efetivos |
|---|---|---|---|
| por run | R$ 20,00 (2000 centavos) | **US$ 4,00** (400 centavos USD) | R$ 19,99 (1999 centavos) |
| total (6 runs) | R$ 120,00 (12000 centavos) | **US$ 24,00** (2400 centavos USD) | R$ 119,95 (11995 centavos) |

Ressalva: `--max-budget-usd` é checado entre chamadas de API; um run pode passar do teto por uma resposta.
O aparelho confere o custo do `result` depois e, se passar, registra como estouro (achado).

Gasto até aqui (turno 1, só carga): US$ 0,0231 + US$ 0,1043 = US$ 0,1274 ≈ **13 centavos USD ≈ R$ 0,64**; uma
tentativa anterior falhou na partida (a flag variadica `--allowedTools` engolia o prompt), sem chamada de modelo.
Conta contra o mesmo R$ 120 por prudência.

## 7. Tabela por run e recomendação

*(vazias até os turnos 2 a 4 — nenhum run de tarefa foi feito.)*

## 8. Limites (sem enfeite)

- **Uma ordem** (054), **N = 3**, **um modelo** (`sonnet`): é a primeira medida, não a última.
- **Reparo de teste não é feature nova.** A 054 é diagnóstico + ajuste de ambiente em 2 arquivos de teste.
- **O corte do texto é uma escolha**, e o `## Turno` da 054 pede só diagnóstico (seção 3).
- **Allowlists diferentes:** a config 2 não pode ter `maestro`/Ponte; a diferença é só essa.
- **Envelope de reprodução:** as dez fontes com ponteiros, **sem** o bloco de prova/fingerprint do daemon.
- **O run de fixture da Ponte não é um run do daemon:** sem `manager_run`, sem audit, sem relançamento, sem Stop
  de turno de produção. O que a Ponte faz no run real (supervisão, T_PAREDE do daemon) não é reproduzido.
- **Quem responde à Ponte é o Spock** (decisão do Diretor); a espera dele entra numa métrica à parte.
- **Bash liberado com `dontAsk` não é sandbox:** o diretório é descartável, mas o Bash alcança o resto do disco
  (`HOME` real, para não perder o login). Sem `--dangerously-skip-permissions`.
- **Carga da máquina varia:** `uptime` registrado antes de cada run; a ordem A B B A A B reparte a deriva.
- **Cobertura da fonte de custo:** o coletor lê `total_cost_usd`/`usage` do `result` do stream. O `cost-state`
  do transcrito (094 do ponte-daemon) **não** foi implementado neste turno; ausente fica "ausente".

## 9. Para refazer

```
tools/harness-minimo/extrair-ordem.sh  <repo> 89be67f .maestro/orders/054-reparo-dos-8-fail-preexistentes-da-main.md <ordem.md>
tools/harness-minimo/texto-da-ordem    <ordem.md> <dir-textos> "bash tests/run-all.sh" ["prefixo comum"]
tools/harness-minimo/montar-base.sh    <repo> 41213f0a454bd6c2060d9faa41f91e36ad450047 <dir-base>     # uma base NOVA por run
tools/harness-minimo/lancar.sh --config 2 --max-budget-usd 4.00 --recibo "bash tests/run-all.sh" --prompt <dir-textos>/prompt-2.md --base <dir-base> --saida <dir-run>
tools/harness-minimo/lancar.sh --config 1 --max-budget-usd 4.00 --recibo "bash tests/run-all.sh" --prompt <dir-textos>/prompt-1.md --base <dir-base> --saida <dir-run>
tools/harness-minimo/coletar-metricas.sh --stream <dir-run>/stream.jsonl --cotacao-milesimos 4998 --aceite-rc "$(cat <dir-run>/recibo.rc)" --parede-ms <ms> …
```

Testes do aparelho (todos com `claude` falso ou fixture): `tests/cli/test-harness-minimo-{base,texto,metricas,lancador}.sh`.

Cadastro na Ponte para a config 1: **nada foi cadastrado neste turno.** O project `exp-harness-054` e o order_ref
`order/054-exp-harness` ainda **não existem** na Ponte; o executor do turno 3 os cadastra (autorizado pelo
Diretor), registra aqui o que cadastrou e **como remover**, e não remove sozinho.
