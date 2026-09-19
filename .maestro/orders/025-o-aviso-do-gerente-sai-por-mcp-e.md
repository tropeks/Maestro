<!-- maestro-order v1
id: 025
ts: 2026-09-18T21:41:48-03:00
epoch: 1789778508
head: c41fb6f4e02c3bc204f8843800b45e3186a5dbd1
branch: feat/025-aguardando-por-mcp
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
absorbed_by: main
absorbed_tree: 349c2e7293784c4d6e70c583a5737b89a6e04818
absorbed_at: 2026-09-19T10:40:55-03:00
absorbed_session: desconhecido
-->
# Ordem 025 — o aviso do gerente sai por MCP em toda rodada, nao so quando ha gate



## Contrato de execução
- Trabalhe APENAS no branch `feat/025-aguardando-por-mcp`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-25 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 025` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v3, "Fora de escopo" (emenda v3): o gerente PERGUNTA por `director.ask` e
espera por `director.wait` no próprio turno; gatilho = socket presente E linha
`[spock] aguardando:`.

A ordem 020 entregou o mecanismo — e ele **nunca disparou**. Medido no próprio
turno do gerente do Maestro, com plugin 1.16.0 e `director_ask` visível: nenhuma
decisão `kind=question` no daemon. O aviso chegou à pane do Diretor pelo **eco do
`done` do herdr**, não por MCP.

### A causa, medida

```
hooks/gate-report.sh:140   if [[ -z "$gate" ]]; then … exit 0; fi
hooks/gate-report.sh:275   mcp_ask=0      ← o gatilho da 020
hooks/gate-report.sh:278   [[ "$raw" =~ \[spock\][[:space:]]aguardando: ]]
```

**O gatilho está 135 linhas DEPOIS do `exit 0`.** O hook sai antes de olhar para
a linha.

E `gate` só é preenchido em dois casos (`:121-129`): `feature`/`refactor` com
`approach: pendente`, ou `ship` sem desfecho. Rodadas de `fix`, `custom`, `audit`,
`verify` e `codereview` — a maioria — **nunca abrem gate**, então o hook sempre
saiu no `:145`.

Não é o cache (o gatilho está em `main`, 5 ocorrências de `mcp_ask`) nem o formato
da linha (o regex casa). É posição no fluxo.

A 020 ligou a Ponte ao **gate humano**; `[spock] aguardando:` é convenção de fim
de rodada e cobre muito mais — "escolhe entre A e B", "aplica isto", "autoriza
aquilo". Nenhum abre gate.

## O desenho — decisão do diretor, 2026-09-18

**O gatilho sobe para ANTES do `exit 0`** e vale para **toda rodada** que termina
com `[spock] aguardando:`. O caminho de gate pendente **fica como está, por
cima** — não mude o comportamento dele.

Razão do diretor, que fecha a objeção óbvia: **o volume não muda.** Essa linha já
chega à pane dele hoje, pelo eco do bridge. O que muda é o **canal e a forma** —
decisão no daemon, com id, em vez de texto solto.

## AS DUAS ARMADILHAS QUE ESTA MUDANÇA ARMA — resolva as duas

**1. O marcador de não-laço não tem nome para o caso sem gate.**

```
:305  asked_marker="$MCP_ASKED_DIR/${sid}_${gate}"
:223  [[ "$_base" =~ ^[A-Za-z0-9_-]+_(plan|ship)$ ]]     ← o prune
```

Sem gate, `${gate}` é vazio. Se você inventar um sufixo novo e **não** ensinar o
prune a reconhecê-lo, o marcador **nunca é podado** e acumula para sempre — a
classe exata que as ordens 021 e 022 passaram o dia consertando. Escolha o sufixo,
ensine o prune, e **teste o acúmulo** (9 sessões × N, diretório antes e depois).

**2. A limpeza do marcador ao resolver o gate some.**

```
:144  rm -f "$MCP_ASKED_DIR/${sid}_plan" "$MCP_ASKED_DIR/${sid}_ship"
```

Hoje o marcador é apagado quando o gate resolve. Sem gate **não há evento de
resolução** — só o TTL de 40min. Diga o que acontece entre uma pergunta e a
seguinte na mesma sessão: o gerente fica 40min sem poder perguntar de novo? Isso
é aceitável ou é defeito? **Decida, escreva a razão no hook, e teste.**

## TRAVAS — pare e chame

- **O hook NUNCA espera.** NFR 50ms. Decide e sai; quem espera é o gerente, no
  turno dele. Nada de `sleep`, `read` bloqueante ou laço.
- **Não mude o caminho de gate pendente.** Fica por cima, intacto.
- **Não vaze conteúdo.** Logs só de metadados; a `reason` do block não carrega
  `message=`/`essencia` do gate. A 020 acertou isso — mantenha.
- As duas redes de não-laço da 020 (`stop_hook_active` e marcador com TTL)
  continuam obrigatórias, agora no caminho novo.
- Mudança de veredito do `maestro doctor`.

## CRITÉRIO DE ACEITE — prova na própria sessão

Ditado pelo diretor:

> O gerente termina uma rodada com `[spock] aguardando: X`; o hook segura o Stop;
> o gerente chama `director.ask` com X; o daemon acorda a pane do Diretor com
> `kind=question`; o Diretor resolve; a resposta volta pelo `director.wait`.

**Provado na sessão do próprio gerente**, não em fixture. O teste automatizado
prova o hook; a prova ponta a ponta é essa rodada acontecendo.

## Prova exigida

- **Gatilho sem gate**: rodada sem gate, com a linha e com o socket → o hook
  devolve decisão. Tem de FALHAR contra o código atual (hoje sai no `:145`);
  mostre as duas pontas.
- **Regressão do gate**: rodada COM gate pendente segue exatamente como hoje.
- **Sem a linha** → nada dispara. **Sem socket** → nada dispara e a sessão termina
  normal (Prioridade 1).
- **Não-laço** nos três casos de `stop_hook_active` (ausente / `false` / `true`).
- **Acúmulo**: 9 sessões × N marcadores, antes e depois, incluindo o sufixo novo.
- Latência do `gate-report.sh` medida **por delta contra o baseline da mesma
  máquina**, nunca pelo absoluto (`ARCHITECTURE.md`, NFRs — esta forge é ~4,8x
  mais lenta que a CI).
- Suíte completa verde em cópia patchada; `habits` por arquivo; `doctor` sem
  mudança de veredito.
- Recibo `maestro evidence --record --label order-25 -- bash tests/run-all.sh`.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-025 -b feat/025-aguardando-por-mcp main`.
- **TUDO que a ordem muda entra como patch em `docs/patches/`**, `tests/` e
  `docs/` inclusive. Um pacote, um diretório, ordem de aplicação.
- **Regrave o patch imediatamente após cada edit** e verifique com `git apply` a
  partir do patch salvo, nunca do arquivo editado ao vivo.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`. **Commite.**
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`.
- **Sem carga sintética** — confirme se o NetForge tem run vivo na lab.
- Grave o essencial em `docs/patches/025-NOTAS.md`.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 025`.
