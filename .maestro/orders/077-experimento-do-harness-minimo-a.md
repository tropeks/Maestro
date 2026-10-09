<!-- maestro-order v1
id: 077
ts: 2026-10-09T13:11:18-03:00
epoch: 1791562278
head: 1297ce0eb4c7ba8803d6f280636f4183d31e2108
branch: order/077-experimento-do-harness-minimo-a
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 077 — experimento do harness minimo: a mesma ordem real no Maestro completo e num claude -p puro

## Por quê

**Aprovada pelo Capitão em 09/10. Entra DEPOIS da ordem de permissões do ponte-daemon (098); não despachar antes.** A auditoria de 05/10 e a pesquisa
de 07/10 (`~/dev/spock/docs/pesquisa-claude-code-nativo-vs-metodo-2026-10-07.md`) dizem que o método é o maior cliente de si mesmo e que o agente é
~4% do lead time. Ninguém **mediu** a pergunta de frente: **a mesma ordem pequena e real, com o mesmo modelo, o mesmo texto e a mesma base, rende
mais, igual ou menos no Maestro completo do que num `claude -p` puro?** Esta ordem mede. Regra da casa: sem fonte, sem número; sem número, sem
recomendação. Ela **não corta nada**: entrega a tabela e uma recomendação, e quem corta é o Capitão.

## O que entrega

### 1. A ordem do experimento (escolha com critério)
Uma ordem **já aceita**, **pequena** (≤ 3 arquivos, ≤ ~60 linhas de diff reais), de **recibo claro** (um comando que sai 0 ou 1) e que **não toque
caminhos protegidos** (`agents/ bin/ src/ hooks/ lib/ config/routing-table.yaml .claude-plugin/ mods/`): se tocasse, o Maestro exigiria o patch
protegido e o `claude -p` puro editaria direto, e as duas configurações deixariam de ser comparáveis. **Candidata nomeada: a ordem 054** ("reparo dos 8
FAIL pré-existentes da main", base `41213f0`, entrega real de 15 linhas em dois testes e no CHANGELOG, recibo: os 8 FAIL somem e a suíte sai 0). O
executor **confirma** o critério na base (os 8 FAIL aparecem 3 vezes seguidas; o diff real é o dito); se não cumprir, escolhe outra que cumpra e
**diz por quê**. Ordem do NetForge só se o Diretor pedir (custo de CI e fixtures). Uma ordem é pouco: é a **primeira** medida, não a última.

### 2. A base sem futuro (o controle que mais pesa)
O repo guarda a solução (`git log --all` a mostra). O executor da base **não pode vê-la**. O aparelho monta cada run num diretório novo: `git archive` do
commit `head:` da ordem, `git init` e **um único commit**. Sem remoto, sem outros refs, sem objetos futuros. Também para os dois lados: `MAESTRO_HOME`
temporário e vazio (o ledger, os briefs e os papercuts de hoje trazem rastro desta ordem), sem tocar `~/.claude` do Capitão. Cada run começa do mesmo
estado byte a byte (mesmo hash de árvore, registrado).

### 3. As duas configurações (mesmo modelo, mesmo esforço, mesma base)
- **Config 1, Maestro completo como hoje:** `claude -p` com o **argv que o runner do ponte-daemon usa para gerente** (leia `headless/claudeArgv.ts`; **não suba o
  daemon de produção**: reproduza o argv num diretório isolado), plugin `maestro` carregado, hooks, Ponte (MCP e `--permission-prompt-tool`), o texto
  **inteiro** da ordem (bloco Turno, contrato, `director_report`, recibo por `maestro evidence`).
- **Config 2, `claude -p` puro:** `claude -p --safe-mode` (na 2.1.293 o `--safe-mode` desliga CLAUDE.md, skills, plugins instalados, hooks, MCP, agents e
  comandos; mantém auth, modelo e permissões; settings gerenciados ainda valem), `--strict-mcp-config`, sem `maestro` no `PATH`, sem Ponte, em
  diretório isolado. Permissões sem humano: `--permission-mode dontAsk` com lista fechada igual para todos os runs. O **executor confirma por
  `claude --debug`**, e cola, que nada além do núcleo carregou (nem plugin, nem hook, nem mod, nem MCP, nem CLAUDE.md); se o guard gerenciado ainda
  atuar, diga e registre.
- **O texto:** uma só fonte, `tools/harness-minimo/texto-da-ordem` produz `prompt-1.md` (a ordem inteira) e `prompt-2.md` (a **mesma** ordem sem os
  blocos que só existem por causa do método: o protocolo do Turno, `director_report`, `maestro evidence`, o Contrato de execução). Tudo que sobra é
  **byte a byte igual**; o aparelho imprime o diff dos dois e o relatório o cola. O corte é a hipótese em teste, não o oráculo: **o critério de pronto de
  `prompt-2.md` é o comando do recibo da ordem original**, escrito como instrução ("rode X e termine quando sair 0").
- **Mesmas condições:** o mesmo `--model` e o mesmo esforço (fixos e registrados), mesma versão do `claude` (registrada), mesmo teto de turnos e de
  parede, uma máquina, **runs em sequência** (nunca em paralelo: a carga contamina o tempo), ordem **A B B A A B** para a deriva do relógio e da carga
  não cair toda de um lado, `uptime` registrado antes de cada run.

### 4. O que se mede, por run (inteiros; custo em centavos; nada de float)
- **Aceite sim/não:** o aparelho roda **por fora**, na árvore final, o comando do recibo da ordem original (o agente não se avalia). Sim = sai 0.
- **Regressões:** testes que **passavam na base** e **falham no fim** (diff das listas da suíte completa base × fim; nomes e contagem).
- **Tempo de parede** em ms (spawn → saída), mais o **tempo de espera por humano** (soma dos intervalos aberta→resolvida das decisões da Ponte do run);
  o relatório traz os dois.
- **Tokens e custo:** os quatro contadores (entrada, saída, cache de leitura, cache de criação) e o custo em **centavos inteiros**, do `result` do
  `claude -p --output-format stream-json` ou do `cost-state` do transcrito (a 094 do ponte-daemon descreve as duas fontes). Ausente fica **ausente**,
  nunca zero.
- **Intervenções humanas:** contagem das decisões que o run abriu na Ponte e um humano teve de responder (`permission`, `report`, `ask`, lidas do
  `ponte.db` em `mode=ro`), mais os bloqueios do Stop de turno e as vezes em que o humano falou fora da Ponte. Na config 2 é **0 por construção**: o
  relatório diz isso, e anota quando o run parou esperando.
- **Extras que explicam a diferença:** chamadas de ferramenta, turnos de modelo, arquivos e linhas tocados, commits, relançamentos, uso do `director_report`.

### 5. O relatório (`docs/experimentos/harness-minimo.md`)
Tabela por run e por configuração (mediana e extremos com N = 3), as diferenças em cada métrica, **o que cada peça do método custou e o que pegou
naquelas execuções** (bloqueios do Stop, pedidos da Ponte, catraca do `habits`, recibo), os **limites sem enfeite** (uma ordem, N = 3, um modelo, reparo
de teste não é feature nova, o corte do texto é uma escolha) e **uma recomendação do que manter e do que cortar no método**. Cada item da recomendação
aponta para o número que o sustenta; o que não foi medido fica como "não medido", sem opinião.

## O que fica de fora (e por quê)
- **Não** mexer no ponte-daemon (código, `~/.ponte`, `ponte.db` além de leitura `mode=ro`), nem nas tools `director.*`, nem em settings gerenciados ou
  globais, nem em `hooks/ bin/ lib/ src/ mods/`.
- **Não** rodar na ordem real nem em ordem aberta: só na cópia isolada. **Não** cortar nada do método: a decisão de cortar é do Capitão.
- **Não** repetir o experimento em outras ordens nem trocar de modelo: uma pergunta de cada vez.

## Ask-First
- **Dinheiro — DECIDIDO pelo Diretor (09/10), não reabra:** **R$ 20 por run e R$ 120 no total, 6 runs** (N = 3 por configuração). Run que estourar os R$ 20 **para** e
  **conta como achado** (aceite = não, custo = o teto, o motivo da parada anotado): **não se repete** o run, e o total de R$ 120 não sobe. O `claude` mede em dólar
  (`--max-budget-usd`): o executor converte pela cotação do dia, **registra a cotação e os valores em dólar usados**, e reporta o custo em centavos inteiros nas duas
  moedas. Estourou o total, PARE e relate o parcial.
- **A Ponte da config 1 não pode tocar a ordem real — DECIDIDO pelo Diretor (09/10):** o run usa `project` e `order_ref` de **fixture** do experimento (por exemplo
  `exp-harness-054`), **nunca a 054 real**. O executor **pode cadastrar** na Ponte esse project e esse order_ref de fixture; registra no relatório o que cadastrou e
  como remover, e **não remove nada sozinho**. Qualquer outro cadastro na Ponte continua sendo do Diretor.
- **Quem responde à Ponte na config 1 — DECIDIDO pelo Diretor (09/10):** o **Spock**. A **espera por humano entra numa métrica separada** (soma dos intervalos
  aberta→resolvida das decisões do run), fora do tempo de parede do agente; o relatório traz os dois números. O Spock responde **a qualquer hora, sem horário combinado** (decisão de 09/10).
- **Texto cortado × literal:** se o Diretor quiser o texto literal nas duas configurações, a config 2 verá instruções de `maestro` que não consegue seguir.
  O padrão desta ordem é o corte descrito; mude só por decisão.
- **Reprodutibilidade da base:** se os 8 FAIL da 054 não aparecerem 3 de 3 na base, a ordem não serve; troque e diga.
- **Segurança do isolamento:** `--permission-mode dontAsk` com Bash liberado não é sandbox. O diretório é descartável, mas o Bash alcança o resto do disco.
  O executor registra o risco, não aponta `HOME` para outra pasta (perderia o login) e não usa `--dangerously-skip-permissions`.
- **Toca `lib/`, `bin/`, `hooks/`?** Não deve. O aparelho vive em `tools/harness-minimo/`. Se algum passo exigir, PARE: seria UM patch em clone sandbox.

## Como sai
`tools/harness-minimo/` (montagem da base sem futuro, `texto-da-ordem`, lançador das duas configurações, coletor de métricas), testes do aparelho com
`claude` falso em `tests/cli/test-harness-minimo-*.sh`, e `docs/experimentos/harness-minimo.md` com os dados e a recomendação, direto no branch.
Emenda: CHANGELOG (Added). Nenhuma emenda de contrato.

## Critérios de aceite
- [oráculo: `bash tests/cli/test-harness-minimo-base.sh`] a base montada **não contém** o commit da solução nem refs futuros (`git log --all` tem 1 commit; o
  hash da árvore é o do `head:` da ordem). **Vermelho antes**, colado.
- [oráculo: `bash tests/cli/test-harness-minimo-texto.sh`] `prompt-1.md` e `prompt-2.md` coincidem byte a byte fora dos blocos cortados, e o corte não
  remove o critério de pronto (o comando do recibo aparece em `prompt-2.md`).
- [oráculo: `bash tests/cli/test-harness-minimo-metricas.sh`] o coletor, com `result`/`cost-state` e `ponte.db` de fixture, devolve só inteiros, mostra
  ausência como ausência, e aponta regressão num par de listas de falhas montado de propósito.
- [oráculo: o relatório] 6 runs completos (ou o parcial dito, com o teto que parou) com **todas** as métricas da seção 4, e a recomendação com um número por item.
- [oráculo: `claude --debug` colado] a config 2 sem plugin, hook, mod, MCP nem CLAUDE.md; a config 1 com tudo isso carregado.
- [oráculo: `bash tests/run-all.sh`] `SUITE OK`; `shellcheck` limpo; `habits` sem aviso novo.
- [humano] o Capitão lê a tabela e a recomendação e decide o que cortar.

## Prova exigida
- Os três vermelhos antes e os verdes depois, saídas coladas; o diff entre `prompt-1.md` e `prompt-2.md`; o `--debug` das duas configurações.
- A tabela do relatório colada no `director_report`, com a recomendação.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-NN` no tip e `maestro order --status NN` VÁLIDA.

## Turno

- ESTADO: **ESTADO ATUAL (prevalece sobre tudo o que vem depois nesta linha): turnos 1, 2 e 3 FEITOS, o 3 revisado no tip `a31cbc2`; não repetir nenhum.** TURNO 3 ENTREGOU: a allowlist com `echo`, `printf`, `sort`, `uniq`, `cut` e `tr`, igual nas duas configs, com teste (vermelho antes, verde depois; `bf2c94f`), e o run **C2-R2**, que também **parou na partida**: o agente emitiu de novo um Bash composto (`git log --oneline | head -3 && ls && (bash tests/run-all.sh 2>&1 | tail -40; echo rc=${PIPESTATUS[0]})`) e o `dontAsk` negou **mesmo com todos os comandos na lista** (causa provável, não provada: o subshell `( … )` e/ou o `${PIPESTATUS[0]}`, que o casador de regras não decompõe); parede 13 353 ms, 1 chamada de ferramenta, 4 centavos USD = 20 centavos BRL, 0 arquivos tocados; o turno parou pela regra do ESTADO e **C2-R3 e C2-R4 não foram feitos**. **DECISÃO DO DIRETOR (opção a, sobre o relato do turno 3), não reabra:** (1) o **prefixo comum**, idêntico nos dois prompts, passa a ser: `Faça o diagnóstico e o reparo, até a suíte sair 0. Um comando por chamada de Bash, sem encadear, sem pipe e sem subshell.` (substitui o da decisão (a) de 09/10, que só tinha a primeira frase); (2) **C2-R1 e C2-R2 ficam registrados como ACHADO: sem essa regra, o `claude -p` puro com lista fechada não arranca, 2 de 2; NÃO entram na comparação** (o relatório os cita como achado; os 8 centavos USD dos dois seguem registrados como referência); (3) **NOVA DIVISÃO (vale sobre as anteriores):** **turno 4** regerar os prompts com o prefixo novo (diff dos dois colado) e fazer os 3 runs da config 2, **C2-R3 a C2-R5**, cada um em base NOVA, com `--recibo`; **turno 5** a config 1 (Maestro completo, com o cadastro da fixture na Ponte); **turno 6** o fechamento (suíte completa do repo, recibo, tabela, recomendação e emendas); (4) **o `teto:` sobe de 5 para 6**, razão: **dois runs de partida perdidos por falha do aparelho**; (5) **DECISÃO DO CAPITÃO de 09/10: a conta é flat-rate, o custo é só referência.** O teto em dólar por run (US$ 4,00) vira **freio contra run descontrolado**, igual nos 6 runs; o relatório mostra o custo **como métrica, não como gasto** (o teto total de US$ 24,00 deixa de ser orçamento a respeitar; o acumulado segue registrado como referência). A regra de **parar para relato quando um run falha por motivo do aparelho fica**. **HISTÓRICO (anterior; onde conflitar com o bloco acima, vale o acima):** turno 1 FEITO e aceito (`6403551`); turno 2 FEITO e revisado no tip `f27683b`. TURNO 2 ENTREGOU: o script `tools/harness-minimo/listas-da-suite.sh` (teste com vermelho antes) e a **linha de base das regressões** na base `92c7c9e`: **3081 passam, 8 falham** (`docs/experimentos/lista-base-92c7c9e/{passam,falham}.txt`); o deny de `.ponte` na config 2; e o run **C2-R1**, que **parou na partida**: o agente emitiu um Bash composto (`git log … && ls && bash tests/run-all.sh … | tail; echo rc=…`) cujo subcomando `echo` não estava na lista fechada, o `dontAsk` negou e o agente desistiu pedindo liberação (parede 11 375 ms, 1 chamada de ferramenta, 2 turnos, 4 centavos USD = 20 centavos BRL, 0 arquivos tocados). Os runs 2 e 3 da config 2 **não foram feitos**. **DECISÃO DO DIRETOR (opção a, sobre o relato do turno 2): C2-R1 é DESCARTADO como falha do aparelho e NÃO conta como resultado** (o gasto de 4 centavos USD continua contando contra o teto total, por prudência, como o do turno 1); **a allowlist ganha `Bash(echo *)`, `Bash(printf *)`, `Bash(sort *)`, `Bash(uniq *)`, `Bash(cut *)` e `Bash(tr *)`, IGUAL nas duas configurações e nos 6 runs**; **ficam fora: `env`, `tee` e `mkdir`**. **NOVA DIVISÃO (vale sobre a anterior):** **turno 3** commitar a lista nova com teste, montar bases NOVAS e fazer os 3 runs da config 2 com as métricas, no teto já escrito neste ESTADO; **turno 4** a config 1 (Maestro completo), com o cadastro da fixture na Ponte; **fechamento** (a suíte completa do repo, o recibo, a tabela, a recomendação e as emendas) é um **quinto turno**. **DECISÃO DO DIRETOR: o `teto:` sobe de 4 para 5**, pela razão de que o **C2-R1 foi descartado** (um run de turno perdido por falha do aparelho) e o **fechamento ganha turno próprio** (a suíte completa e o recibo não competem com os runs). A regra de **parar para relato quando um run falha por motivo do aparelho fica**. TURNO 1 ENTREGOU (`tools/harness-minimo/`, `docs/experimentos/harness-minimo.md`, `docs/experimento/politicas.json` e os testes `tests/cli/test-harness-minimo-{base,texto,metricas,lancador}.sh`): a ordem escolhida, a **054** (base `41213f0`; a solução real `f16dd90` a base não contém; os 8 FAIL aparecem 3 de 3: 6 na 029 e 2 na 038); a **base sem futuro** (`montar-base.sh`: árvore `9e1c1e2`, commit `92c7c9e`, reproduzível); `texto-da-ordem` (prompt-1 inteiro; prompt-2 cortado, com `## Critério de pronto`); `lancar.sh` com o argv do runner de gerente (config 1) e `--safe-mode` + `dontAsk` (config 2); `coletar-metricas.sh`; a prova de carga por `claude --debug` das duas configurações (1 turno cada; carga fixa do método: +20 311 tokens de cache de criação, +40 centavos BRL e +4765 ms por turno de partida; N = 1, **não é resultado**); o orçamento e a conversão. **ABERTO no fim do turno 1:** o `prefixo-comum` (o `## Turno` da 054 pede só diagnóstico); o cadastro de fixture na Ponte (nada cadastrado ainda); o `cost-state` do transcrito não foi implementado (a fonte é o `result` do stream; ausente fica "ausente"). (Divisão dos turnos do fim do turno 1, **substituída pela NOVA DIVISÃO no começo deste ESTADO**.) Cada run seguinte lê o ESTADO e **não repete** o que já está feito. **DECISÕES DO DIRETOR de 09/10 (a B está aprovada; despacho só depois da 098):** (1) **teto de R$ 20 por run e R$ 120 no total, 6 runs**; run que estourar **para e conta como achado**, sem repetir; o executor converte para dólar pela cotação do dia e registra a cotação; (2) **pode cadastrar na Ponte um project e um order_ref de fixture** do experimento, **nunca a 054 real**; (3) na config 1 **quem responde à Ponte é o Spock**, e a **espera por humano entra numa métrica separada**. **DECISÕES DO DIRETOR de 09/10 depois do turno 1 (a–e), não reabra:** (a) **SIM, prefixo comum idêntico nos dois prompts:** `Faça o diagnóstico e o reparo, até a suíte sair 0` (o 4º argumento do `texto-da-ordem`); (b) **modelo `sonnet`**, como os gerentes de produção, **sem `--effort`**, `--max-turns 150`, **parede de 5400 s por run**, **cotação 4,998**, **teto de US$ 4,00 por run e US$ 24,00 no total**; (c) na config 1 o **Spock responde à Ponte a qualquer hora, sem horário combinado**; (d) os **plugins de usuário seguem carregados na config 1**, igual à produção, e o **confound vai anotado no relatório** (separar o que é do `maestro` do que é de `superpowers`/`i-have-adhd`); (e) o **turno 2 é o script das listas passam/falham da suíte, feito ANTES dos runs, e os 3 runs da config 2, cada um em base NOVA**; a suíte completa do repo e o recibo ficam no **turno 4**. Limite que isso cria e o relatório diz: rodar os 3 runs da config 2 antes dos da config 1 **desfaz a intercalação A B B A A B**, então a deriva de relógio e de carga não se reparte; registre `uptime` e hora de cada run.
- fatia: **turno 4**: (1) regerar os prompts com o `texto-da-ordem` e o **prefixo novo** (as duas frases, **idênticas** em `prompt-1.md` e `prompt-2.md`), com o **diff dos dois colado**; se o teste do texto conferir o prefixo, atualize-o com o **vermelho antes**; (2) os **3 runs da config 2, C2-R3 a C2-R5**, cada um numa **base nova** (`montar-base.sh`, árvore `9e1c1e2`), com `lancar.sh --config 2 --recibo "bash tests/run-all.sh"`, `sonnet`, sem `--effort`, `--max-turns 150`, parede de 5400 s e o **freio** de US$ 4,00 por run (`--max-budget-usd 4.00`, cotação 4,998); depois de cada run o aparelho roda por fora o recibo da ordem original e `listas-da-suite.sh`, e o coletor grava as métricas contra a linha de base `92c7c9e`; run que estourar o freio ou os 5400 s **para e conta como achado**, sem repetir; um run que **parar na partida por motivo do aparelho** é **anotado e interrompe o turno para relato** (a regra fica), não é repetido por conta própria; **C2-R1 e C2-R2 não são refeitos nem entram na comparação**
- fim: o diff dos dois prompts com o prefixo novo colado (e o teste do texto, se mudou, saindo 1 antes e 0 depois); **3 runs completos da config 2 (C2-R3 a C2-R5)** (ou o parcial dito, com o que parou), cada um com **todas** as métricas da seção 4 (aceite pelo recibo rodado por fora, regressões contra as listas da base `92c7c9e`, parede em ms, tokens, **custo como métrica** em centavos nas duas moedas, intervenções = 0 por construção, `uptime` e hora), gravadas no relatório; `shellcheck` limpo; o custo acumulado registrado **como referência** (a conta é flat-rate), com C2-R1 e C2-R2 apontados como achado fora da comparação; **nenhum run da config 1** e **nenhum cadastro na Ponte** neste turno
- teto: 6
- fora: o ponte-daemon, os runs da config 1 e o cadastro da fixture (turno 5), a suíte completa do repo e o recibo da própria 077 (turno 6, o fechamento), a tabela e a recomendação, `env`/`tee`/`mkdir` na allowlist, refazer o C2-R1 e o C2-R2, cortar qualquer coisa do método, `hooks/ bin/ lib/ src/ mods/`, settings, vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54, com o sha do tip). Terminar a
> resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível, **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou redirecionamento (`>`, `>>`) para
> escrever código, teste ou documento. O Bash serve para rodar, ler e medir. Patch gerado por `git diff` do sandbox para `docs/patches/` é a única
> saída por redirecionamento admitida.

> **Comando simples:** um comando por chamada de Bash; caminho absoluto em vez de cd e &&; sem pipe para cortar saída (| tail, | head), a
> ferramenta já corta; 2>&1 é permitido (junta saídas, não grava arquivo); a suíte roda como uma chamada só, maestro evidence --record --label
> order-N -- <suíte>, em segundo plano (run_in_background da ferramenta Bash) e a espera é por Monitor; o recibo já grava o código de saída.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run, `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp`
> solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. A suíte roda como uma chamada só (`maestro evidence --record --label order-N --
> <suíte>`) em segundo plano, pelo `run_in_background` da ferramenta Bash, e a espera é por **Monitor**; o recibo já grava o código de saída. Só
> depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/077-experimento-do-harness-minimo-a`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-77 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 077` (você não fecha a própria ordem).
