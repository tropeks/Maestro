<!-- maestro-order v1
id: 020
ts: 2026-09-17T10:42:45-03:00
epoch: 1789652565
head: b1b91eccbca8a7b2a77344b057a2a1e26091e753
branch: feat/020-gerente-pergunta-por-mcp
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 020 — gerente pergunta por MCP: director_ask no Stop, espera no turno do gerente



## Contrato de execução
- Trabalhe APENAS no branch `feat/020-gerente-pergunta-por-mcp`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-20 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 020` (você não fecha a própria ordem).

## Por que esta ordem existe

**INTENT v3, emenda de 2026-09-17** (hash `64b18664`), que trouxe isto para
dentro do escopo com o desenho já decidido:

> Interceptar contatos de fim de sessão via hook Stop/SessionEnd — ~~fora do
> v1~~ **dentro, por emenda v3:** o hook Stop já existe e está ligado desde
> S-2101; o gerente PERGUNTA por `director_ask` da Ponte e espera por
> `director_wait` no próprio turno; o hook nunca espera (`exit 0` sem stdout,
> NFR 50 ms); gatilho = socket presente E linha `[spock] aguardando:`.
> Continua fora: qualquer capacidade de o gerente MANDAR, e injeção acima do
> teto de 8000 B.

Hoje o gerente termina a rodada com `[spock] aguardando: X` e **para**. A
resposta do diretor chega digitada numa pane — o atrito que o PROJECT_BRIEF §1
nomeia como o maior do uso por telefone.

## METADE DISTO JÁ EXISTE — não construa a ida

`hooks/gate-report.sh` (S-2101, entregue 2026-09-02, ligado em
`hooks/hooks.json:85`) já faz a **ida**: detecta gate pendente no Stop, escreve
a pergunta regida em `$MAESTRO_HOME/herdr/gates/<pane>` e chama
`pane report-agent blocked`, best-effort.

O que falta é a **volta** — hoje ela é `hooks/user-prompt-submit.sh` limpando o
gate quando o humano digita. **Esta ordem troca a perna da volta.** Leia os dois
arquivos antes de escrever qualquer linha.

## O contrato da Ponte — fonte, não suposição

Está escrito em `~/dev/Enterprise/.maestro/INTENT.md` (emenda v4, 2026-09-16),
linhas 61-66 e 89-91. Leia de lá; não infira da implementação:

- `director_ask` → `{decision_id, open}`
- `director_wait(id)` em laço, **teto 5 min por chamada**
- a resposta volta **como retorno da ferramenta**, texto livre, **nunca digitada**
- **"o daemon não pausa ninguém — quem escolhe esperar é o gerente"**
- autorização: pane de gerente vale para `director_ask`/`director_wait` **e mais
  nada**; `gates.resolve` segue exclusivo do diretor, e é por ele que a resposta
  sai (`kind: question`, `note` ≤ 2000)
- `kind: question` **não entra** na amostra do GATE do Diretor

As três pontas que eu tinha deixado em aberto estão ESPECIFICADAS — fonte:
`~/dev/ponte-daemon-003/.maestro/orders/006-director-ask-o-gerente-pergunta.md`,
stories S-229/S-230 e o "Critério de saída". Projete contra isto, não contra o
pior caso imaginado:

- **Assinatura**: `ask` devolve `{decision_id, status: open}` NA HORA.
  `wait(id, max_s)` — o teto de 5 min é **parâmetro**, não fixo do daemon.
- **Timeout é retorno normal, não erro**: `director_wait` devolve
  "continua aberta" antes dos 5 min, e a decisão PERSISTE.
- **Restart do daemon não perde a decisão**: `director_wait` funciona depois de
  um restart — é critério de saída da ordem deles, não promessa.
- **Expiração**: decisão sem resposta vira **`expirada` aos 30 min**, e o
  Diretor é avisado. Ou seja, o teto de 30 min desta ordem não é escolha
  arbitrária minha: é o mesmo número que o daemon já usa para expirar.
- **Identidade**: `requireManagerPane` no `AuthorizeMcpPeer`, por SO_PEERCRED
  mais a cadeia `/proc` (adapter em `src/adapters/peercred/adapter.ts` do repo
  deles). O hook **não inventa identidade** — quem identifica é o daemon, pelo
  peer do socket. Pane que não é de gerente é RECUSADA.
- **Concorrência**: o pareamento é por `decision_id`, então duas perguntas do
  mesmo gerente são duas decisões distintas. Não dependa de estado implícito
  de pane.

## O que entra

1. **O plugin expõe o MCP** via `.mcp.json` na raiz do plugin (precedente local:
   `~/.claude/plugins/synced/…/design/.mcp.json`). Servidor: `ponte-daemon mcp`,
   socket `~/.ponte/mcp.sock`.
2. **Caminho por `$HOME`, nunca literal de máquina** (invariante I-1 do E24, por
   causa da migração `rcosta00`→`vulcan` em curso). Binário ou socket ausente →
   o servidor não sobe e a sessão segue normal.
3. **`hooks/gate-report.sh` ganha o gatilho**: detectou `[spock] aguardando: X`
   **E** o socket existe → instrui o gerente a perguntar. Sem a linha, ou sem
   socket: **nada muda**, `exit 0` como hoje.
4. **O gerente pergunta e espera no turno dele**: `director_ask` uma vez,
   `director_wait` em laço de 5 min, teto de 30 min. Desistir é desfecho e vai
   DITO, nunca em silêncio.

## O HOOK NUNCA ESPERA — é a trava central

NFR de 50 ms por invocação, e a regra do próprio `gate-report.sh` é `exit 0`,
nada em stdout. **Se a sua implementação faz o hook aguardar qualquer coisa, ela
está errada.** Quem espera é o gerente, no turno dele — que é literalmente o
contrato da Ponte ("o daemon não pausa ninguém").

O hook só DETECTA e INSTRUI. Nada de `sleep`, nada de `read` bloqueante, nada
de laço de espera dentro de `hooks/`.

## TRAVAS — pare e chame

- **Gerente que MANDA**: fora do escopo por texto expresso da emenda v3. Se o
  desenho der ao gerente qualquer capacidade além de perguntar e esperar, PARE.
- **Injeção acima de 8000 B**: fora por texto expresso da emenda v3. A injeção
  está em **7416 B de 8000 B** hoje — 584 B de folga. Se a sua solução precisar
  crescer a injeção, ela precisa cortar no mesmo commit (Prioridade 5), e isso
  é decisão do diretor: PARE e chame.
- **Laço infinito na sessão.** Um hook Stop que devolve decisão pode prender a
  sessão se a condição de saída falhar. O gatilho exige socket presente E a
  linha; o gerente remove a linha ao receber a resposta. **O teste de não-laço
  é obrigatório.**
- Mudança de veredito do `maestro doctor`.
- Qualquer coisa que faça a sessão depender da Ponte para terminar.

## O TESTE MAIS IMPORTANTE É O DO SOCKET AUSENTE

Prioridade 1 do INTENT: "nunca bloquear trabalho por estar quebrado — falha de
qualquer componente degrada para o fluxo manual". Com o socket ausente, a
sessão tem de terminar **normalmente, sem espera e sem erro**, exatamente como
termina hoje.

Se você entregar tudo o resto e não entregar esse teste, a ordem está
incompleta.

## Prova exigida

- **Socket ausente** → sessão termina normal, sem espera, sem erro. O teste
  principal.
- **Sem a linha `[spock] aguardando:`** → nada dispara, `exit 0`, nada em stdout.
- **Com socket e com a linha** → `director_ask` sai UMA vez; `director_wait`
  itera; a resposta chega como retorno da ferramenta.
- **Teto de 30 min** → desiste e diz, não fica em silêncio.
- **Não-laço**: a sessão não volta a disparar depois da resposta.
- Latência do `gate-report.sh` medida: continua dentro do NFR de 50 ms.
- Suíte completa, `habits` por arquivo, `doctor` sem mudança de veredito.
- Recibo: `maestro evidence --record --label order-20 -- bash tests/run-all.sh`.

## Nota sobre o NFR do session-start nesta forge

Ele reprova **por carga** nesta máquina, e reprova igual em `main` limpo (A/B
com stash, diretor, 2026-09-17). É ambiente, não regressão; a CI é o gate
estrito. Se a sua corrida reprovar só nisso, **diga e siga**.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-020 -b feat/020-gerente-pergunta-por-mcp main`.
- `hooks/`, `bin/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
  `tests/`, `docs/` e `.claude-plugin/` — confirme se este último é denylist
  antes de editar direto; se for, vai por patch também.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`.
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`.
- `bash -n` por arquivo é o gate de sintaxe.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 020`.
