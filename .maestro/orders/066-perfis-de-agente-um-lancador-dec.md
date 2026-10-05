<!-- maestro-order v1
id: 066
ts: 2026-10-05T10:35:05-03:00
epoch: 1791207305
head: 21c71c1dab4c7f27910d714326d76e181b5e60f2
branch: order/066-perfis-de-agente-um-lancador-dec
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 066 — perfis de agente: um lancador declarado por perfil, pesquisa sem Maestro, Ponte nem MCP

## Por quê

**Ordem direta do Capitão, 05/10.** Todo `claude` lançado na forge **carrega os plugins e os MCPs do usuário**.
Hoje um **Opus de pesquisa do Spock** carregou o **MCP da Ponte**, **bateu no socket** (`~/.ponte/mcp.sock`) e
gerou **alerta de segurança ao Capitão**. Um agente de estudo não tinha por que saber que a Ponte existe, e o
acesso a ela (decisões, `director_ask`, o canal do Diretor) é exatamente o que não pode vazar para um agente
sem papel na ordem.

A causa não é o agente: é que **não existe um lançador**. Cada pane, runner e script monta `claude …` à mão e
herda o que a conta do usuário tem instalado. O que o agente pode tocar tem de ser **declarado por perfil e
imposto por um lançador único**, e não herdado por acaso.

## O que entrega

### 1. Os quatro perfis, cada um declarado e com um lançador único

| perfil | quem usa | Maestro (plugin, hooks, guardas) | Ponte (MCP) | outros MCPs e plugins |
|---|---|---|---|---|
| **dev** | turno de ordem | sim | sim, **pelo envelope do runner, como hoje** | os do envelope, como hoje |
| **gerente** | pane de projeto | sim | sim | os de hoje |
| **diretor** | o Spock | **não** | **sim** | nenhum além da Ponte |
| **pesquisa** (e demais: estudo, avaliação, codex) | agente sem papel na ordem | **não** | **não** | **nenhum MCP, nenhum plugin**; **sem as guardas do método** |

**Regra de segredos do perfil pesquisa (inegociável):** sem as guardas do método, ele **nunca lê `.env`, chave
nem `~/.ponte`**. Como o plugin Maestro **não carrega** nesse perfil, essa proteção **não pode depender dele**:
tem de vir da **configuração do próprio perfil** (regras de permissão `deny` de leitura para `.env*`, chaves
(`*.pem`, `*.key`, `id_*`), `~/.ponte/**` e o `.maestro/` de credenciais, e o que o Claude Code instalado
oferecer de restrição de leitura no sandbox). O turno **mede** o que a versão instalada suporta e declara o
**limite** (leitura por Bash, `python`, `node` é mais difícil de cobrir que a ferramenta Read; o que não cobre
fica escrito, não fingido).

### 2. Um comando único, núcleo agnóstico de provedor

`maestro agente --perfil <dev|gerente|diretor|pesquisa> [--dry-run] -- <args do provedor>`

- **Núcleo** (CLI do Maestro, testável **sem Claude Code**): lê a **declaração** dos perfis em arquivo próprio
  (`config/perfis-agente.yaml`, **fora** da `routing-table.yaml`), resolve o perfil e entrega a um **adaptador**.
  A declaração fala em **capacidades** (`maestro`, `ponte`, `mcp`, `plugins`, `guardas`, `segredos: nega`), **nunca**
  em flag ou palavra de um provedor. No espírito da **E24** (núcleo + adaptadores): o núcleo vale para qualquer
  provedor; o **adaptador do Claude Code** traduz capacidades em flags e variáveis de ambiente.
- **`--dry-run`** imprime exatamente o que seria executado (comando, ambiente relevante, arquivos de configuração
  gerados), **sem lançar nada**: é o que torna o lançador testável sem o provedor e auditável.
- **Falha fechada no perfil:** sem `--perfil`, ou com perfil desconhecido, **erro e nada é lançado**; **não existe
  perfil padrão** que caia no "carrega tudo". O erro diz os perfis válidos.
- **Adaptador do Claude Code:** o único implementado. Para os demais provedores (codex etc.) a ordem entrega só o
  **contrato** do adaptador e prova, com um **adaptador de teste** (falso), que o núcleo **não contém palavra do
  Claude Code**.

### 3. O mecanismo é medido, não presumido

O turno **mede qual funciona no Claude Code instalado** (hoje `2.1.289`; `claude --version` colado). Candidatos,
**cada um medido por perfil** (isolado do ambiente real do Capitão, `HOME` e config em diretório temporário):
- **(a)** `CLAUDE_CONFIG_DIR` por perfil (um diretório de configuração próprio, sem plugins nem MCPs);
- **(b)** `--strict-mcp-config` com `--mcp-config` vazio (ou só com a Ponte, no `diretor`) + `--settings` do perfil
  + `--setting-sources` restrito;
- **(c)** `--bare` (pula hooks, sincronização de plugin, auto-memória etc.), com `--mcp-config`/`--settings`;
- ou a **combinação** mínima que satisfaz a tabela.

**Matriz colada no relatório (candidato × perfil):** plugins carregados (`claude plugin list`), MCPs carregados e
conectados (`claude mcp list`), o `Maestro`/skills/hooks presentes ou ausentes, **autenticação preservada?**
(`CLAUDE_CONFIG_DIR` próprio pode perder o login; o candidato que obriga reautenticar ou gravar credencial em
lugar novo é descartado ou declarado com o custo), e **conexão ao socket da Ponte** (abaixo). A recomendação sai da
matriz, com o motivo.

### 4. A prova central: o perfil pesquisa nunca toca o socket da Ponte

- **Socket de fixture:** um servidor Unix local, em diretório temporário, que **registra cada conexão** recebida.
  `HOME` e `PONTE_MCP_SOCKET` do teste apontam para a fixture: **o teste nunca toca o `~/.ponte` real**.
- **Vermelho antes:** lançar o provedor do jeito de hoje (sem perfil), com a Ponte configurada na fixture, **registra
  conexão** (o incidente reproduzido, saída colada).
- **Verde depois:** `maestro agente --perfil pesquisa` **não registra nenhuma conexão**. Controle: o `diretor` e o
  `gerente` **registram** (a Ponte carrega onde deve).
- Comando de medição **sem modelo e sem rede**: `claude mcp list`/`claude plugin list` (que sondam os servidores) sob
  o perfil. Se o `claude` não estiver instalado ou autenticado no ambiente do executor, a camada real vira
  **"não verificado" explícito**, nunca omitida nem dada como verde; a camada do núcleo e do `--dry-run`
  (com stub do provedor) roda sempre.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-order-066-agente-nucleo.sh`] o núcleo, sem Claude Code: os quatro perfis resolvem
  para as capacidades da tabela; sem perfil e perfil desconhecido **falham sem lançar**; `--dry-run` não executa;
  o núcleo não contém palavra do Claude Code (adaptador falso provando). **Vermelho antes** (o comando não existe),
  colado.
- [oráculo: `bash tests/cli/test-order-066-pesquisa-sem-ponte.sh`] o socket de fixture: **sem perfil conecta
  (vermelho), `pesquisa` não conecta, `gerente` e `diretor` conectam**; nunca usa o `~/.ponte` real.
- [oráculo: `bash tests/cli/test-order-066-pesquisa-segredos.sh`] o perfil `pesquisa` traz as regras de negação de
  leitura para `.env*`, chaves e `~/.ponte`, **sem depender do plugin Maestro**; fixture com `.env` e arquivo em
  `~/.ponte` falsos e o que a versão instalada permitir provar **offline**; o resto vira **limite declarado**.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [humano] o Diretor lê a **matriz do mecanismo** e a lista de **limites declarados** e aprova o mecanismo escolhido.

## Ask-First

- **O envelope do runner (perfil `dev`)** vive no **ponte-daemon**, outro repo: **leia-o, não o altere**; o perfil
  `dev` só **declara** o que o envelope já faz. Se não for possível descrevê-lo sem inventar, PARE.
- **A Ponte como MCP sem o plugin Maestro:** hoje o servidor da Ponte chega pelo plugin Maestro
  (`mcp__plugin_maestro_ponte__*`). O perfil **`diretor` (sem Maestro, com Ponte)** exige declarar a Ponte
  **independente do plugin**. Se isso exigir tocar o repo da Ponte ou o manifesto do plugin, PARE e relate.
- Se **nenhum** mecanismo isolar `pesquisa` sem perder a autenticação ou sem escrever em área do usuário, PARE e
  relate a matriz: a escolha entre custo e isolamento é do Diretor.
- Se a proteção de segredos não puder ser provada offline para alguma forma de leitura, **declare o limite**; não
  afirme cobertura que não mediu.
- **Adotar o lançador** nos lançadores reais (panes, runner do daemon, scripts do Spock) é de **outras ordens e
  outros repos**: aqui sai o comando, a declaração, o adaptador e a prova.
- **Toca `lib/`, `bin/` (autoprotegidos):** a entrega do núcleo e do adaptador é **UM patch** em
  `docs/patches/066-*.patch`, feito em clone sandbox FORA do repo, testado antes e depois, aplicado pelo Capitão
  com um `git apply`. `config/perfis-agente.yaml`, `tests/` e `docs/` vão direto no branch.
- Logs: **só metadados** (perfil, adaptador, rc); nunca argumento do provedor, prompt nem caminho completo.

## Como sai

`config/perfis-agente.yaml`, os testes e as emendas de docs direto no branch; o núcleo e o adaptador em **UM patch
protegido**. Emendas no mesmo changeset: API_SPEC (o comando `agente`, o formato da declaração, o contrato do
adaptador), ARCHITECTURE (ADR: perfis, núcleo e adaptador, falha fechada), ENGINEERING_SPEC (a matriz do mecanismo
e os limites declarados da proteção de segredos) e o CHANGELOG (Added). Papercut: "claude da forge herda plugins e
MCPs do usuário".

## Prova exigida

- Os três testes novos vermelhos antes e verdes depois, saídas coladas; a matriz candidato × perfil.
- A prova do socket: sem perfil conecta, `pesquisa` não conecta, `gerente`/`diretor` conectam; ou a camada real
  como "não verificado" com o motivo.
- A lista de limites declarados da proteção de segredos.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-66` no tip com o patch aplicado e
  `maestro order --status 66` VÁLIDA.

## Turno

- fatia: a declaração dos quatro perfis, o núcleo do `maestro agente` com `--dry-run`, o adaptador do Claude Code e a medição do mecanismo (matriz), com o teste do socket vermelho antes
- fim: `test-order-066-agente-nucleo`, `test-order-066-pesquisa-sem-ponte` e `test-order-066-pesquisa-segredos` saem 1 antes (colado) e 0 depois, no sandbox; a matriz candidato × perfil e a prova do socket coladas; `bash tests/run-all.sh` sai 0; patch protegido pronto e `git apply --check` ok
- teto: 4
- fora: alterar o envelope do runner ou o ponte-daemon, adotar o lançador em panes ou scripts, mudar o manifesto do plugin Maestro, tocar o `~/.ponte` real, rede, aplicar o patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54,
> com o sha do tip). Terminar a resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível,
> **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou
> redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e medir.
> Patch gerado por `git diff` do sandbox para `docs/patches/` é a única saída por redirecionamento admitida.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera **por
> laço** até a linha `rc=` no log; só depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/066-perfis-de-agente-um-lancador-dec`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-66 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), núcleo + adaptadores (E24), com a ordem direta do Capitão de 05/10 como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 066` (você não fecha a própria ordem).
