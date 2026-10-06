<!-- maestro-order v1
id: 068
ts: 2026-10-05T11:02:58-03:00
epoch: 1791208978
head: 21c71c1dab4c7f27910d714326d76e181b5e60f2
branch: order/068-hook-defasado-nunca-roda-turno-c
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
deferred_by: spock 2026-10-06 regra da subtracao
-->
# Ordem 068 — hook defasado nunca roda turno: cache atras do repo recusa o turno e doctor e session-start acusam

## Por quê

**Integridade que a v59 permite antes do gate.** A **ordem 064** provou a causa: o **turno headless da 062** rodou
com o **hook do cache 1.21.0** enquanto o **repo já estava na 1.22.0**, e **relatou falso**: o Stop de turno
antigo liberou calado em 124 (o defeito que a 056 corrigiu) porque o conserto só existia no repo, não no hook
em uso. Os hooks rodam do **cache do plugin** (`~/.claude/plugins/cache/maestro/maestro/<versão>/`), e o cache só
muda com o **giro** do Capitão. Entre o merge e o giro existe uma janela em que **o método que o turno diz estar
cumprindo não é o que está executando**. Um turno não atendido (headless) dentro dessa janela produz **relato
falso**, o pior defeito de um método que existe para tornar a prova mecânica.

O Maestro hoje **já sabe de parte disso**: `maestro doctor` (`check_plugin_install`, S-710) compara a **cópia
registrada** com o repo e avisa "cópia registrada difere". Mas (a) compara **conteúdo de arquivo**, não a
**versão em uso**; (b) trata como inerte a cópia divergente quando o marketplace aponta para o repo, sem checar
qual raiz **este** processo realmente usa; (c) **só avisa** — nada impede o turno de ordem de começar.

## O que entrega

**Uma regra, uma implementação:** *hook defasado nunca roda turno.*

1. **Núcleo: o veredito de versão, uma função só.** O CLI ganha a checagem **versão do plugin em uso** contra a
   **versão do repo do Maestro** e devolve `ok` / `atrás` / `indeterminado`, com exit code por veredito e a
   **razão** legível (`cache 1.21.0 < repo 1.22.0`).
   - **Em uso** = a raiz de onde os hooks **estão rodando agora**: `CLAUDE_PLUGIN_ROOT` (e o `version` do
     `.claude-plugin/plugin.json` dessa raiz). **Repo** = o repo do Maestro de onde o CLI roda
     (`.claude-plugin/plugin.json` do `REPO_DIR`).
   - Comparação **semver por inteiros** (`major.minor.patch`), sem float, sem texto. Só é `atrás` quando **as duas
     versões foram lidas** e a em uso é **menor**. Em uso **maior** ou igual → `ok`.
   - **Qualquer falha de leitura** (arquivo ausente, JSON ilegível, `CLAUDE_PLUGIN_ROOT` não definido, sem `jq`)
     → `indeterminado`: **nunca** é tratado como `atrás` (Prioridade 1: falha de componente não bloqueia).
2. **O turno de ordem headless recusa iniciar com cache atrás.** Quando o veredito é `atrás` **e** a sessão é um
   **turno de ordem não atendido** (branch `order/NNN-…` num worktree com `.maestro/orders/`, **sem humano**), o
   turno **não começa**: sai sem trabalhar, **com o motivo no relatório**, no formato do relato fixo:
   `hook defasado: o cache do plugin está em 1.21.0 e o repo em 1.22.0 — o turno não roda com hook antigo; peça o
   giro do cache ao Capitão`. A recusa **fala por onde a ordem fala** (relatório do turno e `director_report`
   quando a Ponte estiver disponível), nunca em silêncio.
   - **Como se reconhece "headless, não atendido":** candidato `CLAUDE_CODE_SESSION_ATTENDED` (presente no
     ambiente do Claude Code) e o modo `-p`/`CLAUDE_CODE_ENTRYPOINT`. O turno **mede** qual sinal é confiável no
     Claude Code instalado e prova que sessão **atendida** nunca é recusada (só avisada).
   - **Onde a recusa se impõe** (mecanismo **medido**, não presumido): candidatos: (a) o hook `session-start`
     (um `SessionStart` pode encerrar a sessão? medir); (b) o `UserPromptSubmit` (exit 2 apaga o prompt e mostra o
     motivo); (c) o **lançador** de turno (`maestro agente --perfil dev`, ordem 066), que checa **antes** de
     lançar. O executor escolhe o ponto onde a recusa **de fato impede o turno** e cola a medição.
3. **`maestro doctor` e `session-start` acusam cache atrás do repo**, em **qualquer** sessão (atendida ou não),
   usando **o mesmo veredito** do item 1 (nenhuma segunda comparação):
   - `doctor`: `warn` com a razão e o conserto ("gire o cache: …"); substitui o aviso por conteúdo quando a causa é
     versão, e **corrige o caso inerte**: se o repo é a raiz viva (`CLAUDE_PLUGIN_ROOT` = repo), não há cache atrás.
   - `session-start`: uma linha no bloco injetado (`⚠ hook defasado: cache 1.21.0 < repo 1.22.0`), dentro do
     orçamento do bloco (hoje ~7,4 KB de 8 KB — **a linha só entra quando há defasagem**, e o teste de orçamento
     da injeção segue verde).

## O que NÃO muda

Sessão **atendida**: só aviso, nunca recusa. `MAESTRO_OFF=1`: sai na primeira linha, nada é checado. Veredito
`indeterminado`: o fluxo segue como hoje, com aviso. Nenhum arquivo do cache é tocado: **girar o cache é do
Capitão**; esta ordem só o **detecta e recusa depender dele**.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-order-068-versao-defasada.sh`] o **núcleo**, sem Claude Code: raiz em uso `1.21.0`
  e repo `1.22.0` → `atrás` (exit e razão); iguais ou em uso maior → `ok`; arquivo ausente, JSON inválido,
  `CLAUDE_PLUGIN_ROOT` indefinido → `indeterminado` (**nunca** `atrás`); comparação por inteiros
  (`1.9.0 < 1.10.0`). **Vermelho antes** (o comando não existe e o `doctor` não acusa versão), colado.
- [oráculo: `bash tests/hooks/test-order-068-turno-recusado.sh`] a **recusa**: com cache atrás e turno de ordem
  **não atendido**, o turno é recusado **com o motivo** no relatório; com sessão **atendida**, só avisa; com
  `indeterminado` ou `MAESTRO_OFF=1`, segue como hoje. **Reproduz o incidente da 062** (hook 1.21.0, repo 1.22.0).
- [oráculo: `bash tests/cli/test-order-068-doctor-session-start.sh`] `doctor` e `session-start` acusam pelo
  **mesmo** veredito; repo como raiz viva **não** acusa; o orçamento da injeção do `session-start` segue verde.
- [oráculo: `bash tests/hooks/test-session-start.sh`, `bash tests/hooks/test-guarda-destrutiva.sh` e os testes de
  latência] **não regridem** (o caminho comum não ganha fork nem passa de 50 ms; a leitura da versão é de um
  arquivo pequeno, sem fork além do que já existe).
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [humano] o Diretor lê o ponto de recusa escolhido e a medição que o justifica.

## Ask-First

- **Prioridade 1.** `CLAUDE.md`: "falha de qualquer componente degrada para o fluxo manual — nunca bloqueia
  trabalho". Recusar o turno é a **exceção** que o Capitão **decidiu** (v59, integridade), e só vale em **turno de
  ordem não atendido com defasagem PROVADA** (as duas versões lidas). Qualquer dúvida na leitura ou no sinal de
  "não atendido" → **não recusa**. Se o executor achar caso em que a recusa possa prender sessão atendida ou
  trabalho legítimo, PARE e reporte.
- **Qual é o "repo do Maestro":** o CLI pode rodar de um worktree com `plugin.json` mais velho que a `main`. Defina
  e documente a fonte (o `REPO_DIR` do CLI em uso, ou o checkout canônico) e cole os casos; se a escolha mudar o
  veredito de forma não óbvia, PARE e peça a decisão.
- Se `SessionStart` **não** puder impedir o turno e o `UserPromptSubmit` também não, o ponto de recusa passa a ser
  o lançador (ordem 066): relate, e a adoção no lançador é de **outra ordem**.
- **Toca `bin/` (o `doctor`), `lib/` e `hooks/` (`session-start`, `user-prompt-submit`) — autoprotegidos:** a
  entrega é **UM patch** em `docs/patches/068-*.patch`, feito em clone sandbox FORA do repo, testado antes e
  depois, aplicado pelo Capitão com um `git apply`. `tests/` e `docs/` direto no branch.
- **Não toque o cache do plugin** (`~/.claude/plugins`) nem o gire: é do Capitão. Os testes usam raízes de fixture,
  nunca o cache real.
- Logs: **só metadados** (veredito, versões, ponto de recusa); nunca caminho completo nem prompt.

## Como sai

Os testes e as emendas de docs direto no branch; o núcleo, o `doctor` e os dois hooks em **UM patch protegido**.
Emendas no mesmo changeset: API_SPEC (o comando de versão do núcleo, os códigos de saída, o contrato da recusa e
a exceção à Prioridade 1), ARCHITECTURE (nota de ADR-003: hook defasado), ENGINEERING_SPEC ("O turno da ordem e o
relatório de fim de turno": o turno não roda com hook antigo) e o CHANGELOG (Fixed). Papercut: "turno headless
rodou com o hook do cache atrás do repo e relatou falso".

## Prova exigida

- Os testes novos vermelhos antes e verdes depois, saídas coladas; o caso da 062 reproduzido.
- A medição do **ponto de recusa** (qual mecanismo impede o turno de fato) e do sinal "não atendido".
- Os não-regredidos (latência e orçamento da injeção) com números inteiros em ms/bytes.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-68` no tip com o patch aplicado e
  `maestro order --status 68` VÁLIDA.

## Turno

- fatia: o veredito de versão no núcleo, o teste vermelho (núcleo, caso da 062, doctor e session-start) e a medição do ponto de recusa e do sinal de sessão não atendida
- fim: `test-order-068-versao-defasada`, `test-order-068-turno-recusado` e `test-order-068-doctor-session-start` saem 1 antes (colado) e 0 depois, no sandbox; a medição colada; `bash tests/run-all.sh` sai 0; patch protegido pronto e `git apply --check` ok
- teto: 4
- fora: girar ou tocar o cache do plugin, recusar sessão atendida, adotar a checagem no lançador (ordem 066) ou no daemon, mudar o conteúdo do relato fixo além do motivo, aplicar o patch e tocar vendor/
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
- Trabalhe APENAS no branch `order/068-hook-defasado-nunca-roda-turno-c`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-68 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), Prioridade 3 (trilho onde o trilho alcança), com a decisão do Capitão (v59, integridade antes do gate) como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 068` (você não fecha a própria ordem).
