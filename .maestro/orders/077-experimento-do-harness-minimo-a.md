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
  aberta→resolvida das decisões do run), fora do tempo de parede do agente; o relatório traz os dois números. Combine o horário com o Spock antes do turno 3.
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

- ESTADO: nenhum turno feito. O primeiro run faz **só o TURNO 1**. Divisão: **turno 1** o aparelho e a escolha da ordem, sem gastar modelo; **turno 2** os 3 runs da config 2 (pura); **turno 3** os 3 runs da config 1 (Maestro completo); **turno 4** a tabela, a recomendação, as emendas e o recibo. Cada run seguinte lê o ESTADO e **não repete** o que já está feito. **DECISÕES DO DIRETOR de 09/10 (a B está aprovada; despacho só depois da 098):** (1) **teto de R$ 20 por run e R$ 120 no total, 6 runs**; run que estourar **para e conta como achado**, sem repetir; o executor converte para dólar pela cotação do dia e registra a cotação; (2) **pode cadastrar na Ponte um project e um order_ref de fixture** do experimento, **nunca a 054 real**; (3) na config 1 **quem responde à Ponte é o Spock**, e a **espera por humano entra numa métrica separada**.
- fatia: **turno 1**: a escolha da ordem com os critérios verificados na base (os 8 FAIL da 054 três vezes seguidas, ou a troca justificada), a base sem futuro, `texto-da-ordem` com o diff `prompt-1`/`prompt-2`, o coletor de métricas, e os três testes do aparelho com `claude` falso e o vermelho colado; o `--debug` das duas configurações em modo de carga (um `claude -p` de uma linha, sem tarefa real)
- fim: os três testes saem 1 antes (colado) e 0 depois; a base montada sem futuro; o diff dos dois prompts colado; o `--debug` mostrando o que carrega em cada configuração; `shellcheck` limpo; o orçamento decidido (N = 3, R$ 20 por run, R$ 120 no total, a cotação do dia e os valores em dólar para `--max-budget-usd`) escrito no relatório
- teto: 4
- fora: o ponte-daemon, rodar a ordem de verdade (turnos 2 e 3), cortar qualquer coisa do método, `hooks/ bin/ lib/ src/ mods/`, settings, vendor/
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
