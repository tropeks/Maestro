<!-- maestro-order v1
id: 043
ts: 2026-09-25T21:00:03-03:00
epoch: 1790380803
head: e226b8b58c1b9ac5361cd7d8eb772b71c0a9e04d
branch: feat/043-gate-worktree-autoprotecao
frozen: vendor/ src/
intent_version: 6
intent_hash: 31205cc5
author_session: 2c956cd6-dea6-490a-9273-9e8077483f27
-->
# Ordem 043 — autoprotecao do gate vencida por worktree fora da raiz: Write em agents/ passa com rc=0

## A decisão que a autoriza

Decisão do Diretor em 25/09, no relato da ordem 042: **o incidente é grave**. A
autoproteção do ADR-003 (v1.1/v1.2) tem um buraco. Durante a 042, um subagente escreveu
`agents/conformador.md` com o Write, direto no worktree
`~/dev/worktrees/maestro-042`, e o gate não bloqueou. O executor apagou o arquivo e refez
como patch, e o commit da 042 não tem nada em `agents/`. Mas a guarda falhou em silêncio.

É dívida de segurança, não feature (`docs/ENCERRAMENTO-v1.md` §5). A direção é o INTENT v6
§Limites ("Autoproteção do gate: … `bin/`, `src/`, `agents/` … seguem bloqueadas") e
§Prioridades 4.

## O defeito, reproduzido em 25/09 sem subagente

O gate do main (`hooks/pre-tool-gate.sh`) recebeu o payload de um Write e respondeu:

| `file_path` do payload | `cwd` | rc |
|---|---|---|
| `~/dev/Maestro/agents/x.md` | worktree | **2** (bloqueia) |
| `~/dev/worktrees/maestro-042/agents/x.md` | worktree | **0** (passa) |
| `~/dev/worktrees/maestro-042/agents/x.md` | main | **0** (passa) |

Logo, o subagente não é a causa primária: **o gate não reconhece o worktree do próprio
plugin como o plugin**, fora da raiz. A ordem 012 ("autoproteção reconhece worktree como o
mesmo plugin", `git --git-common-dir`) devia cobrir esse caso. Descubra por que não cobre:
o ramo só dispara com `PROJ` e `REL` resolvidos (`pre-tool-gate.sh` ~575), e a checagem
"barato-primeiro" pode sair antes. Hipótese secundária a confirmar ou descartar com
evidência: o PreToolUse não roda em subagente, ou roda com outra política ou outro
`PLUGIN_ROOT` (o compilado pelo session-start contra o derivado da localização do hook).

## O que entrega

1. **Reprodução vermelha primeiro:** um teste que monta o plugin numa sandbox, cria um
   `git worktree` fora da raiz e manda ao gate um Write/Edit em `agents/`, `bin/`, `hooks/`,
   `src/`, `config/routing-table.yaml`, `config/accept-proof.pub` e `.claude-plugin/`, pelo
   caminho do worktree. Com `cwd` no main e no worktree, e com a política compilada e
   ausente. Hoje ele falha em `agents/` pelo menos, e o relato registra quais alvos passam.
2. **O conserto:** caminho de qualquer worktree do repo do plugin (mesmo
   `--git-common-dir`) cai na denylist ancorada, igual à raiz. Sem fork novo no caminho
   comum: a edição que não parece autoproteção continua sem `git` (NFR <50 ms, INTENT
   §Limites). A exceção estreita da 039 (`effort`/`omitClaudeMd`) e o `consent roster`
   continuam valendo no worktree exatamente como na raiz, nem mais nem menos.
3. **O subagente:** a prova diz, com evidência (log do gate numa sessão com subagente,
   metadado só), se o PreToolUse dispara em subagente. Se não dispara, **pare e reporte**:
   é limite do harness, não do Maestro, e vira linha no ENCERRAMENTO §3 com endereço.
4. **Falha fechada:** se `git` falhar ao resolver o common-dir de um caminho que casa
   prefixo da denylist, o gate bloqueia. Não degrada aberto nesse ramo (ADR-003 v1.1,
   review P1-3).

## Como sai

`hooks/` está na autoproteção e nenhum consent a destrava. O conserto sai como
**patch em `docs/patches/043-*.patch`**, aplicado por mão humana, no molde das ordens
012/019/027. Os testes rodam em sandbox com o patch aplicado e continuam verdes depois que
o Capitão aplicar o patch. Emendas no MESMO changeset: ARCHITECTURE (ADR-003, a nota do
worktree) e, se o contrato do gate mudar, API_SPEC.

## Ask-First

- Se o conserto exigir tocar `hooks/lib/common.sh` ou o `session-start`, diga qual linha e
  por quê antes de escrever o patch.
- Se a causa for o harness (item 3), não invente mecanismo: pare e reporte.

## Prova exigida

- **Vermelho antes:** o teste de reprodução falha contra o `pre-tool-gate.sh` do main
  (saída colada no relato).
- **Verde depois:** com o patch, todo alvo da denylist sai com rc=2 pelo caminho do
  worktree, nos 4 cenários (`cwd` main/worktree × política presente/ausente).
- **Sem regressão:** edição comum no worktree (ex.: `lib/`, `tests/`, `docs/`) passa
  com rc=0 e sem fork de `git` (conte os forks com um `git` falso no PATH). A exceção
  `effort`/`omitClaudeMd` e o `consent roster` se comportam igual na raiz e no worktree.
- **Latência:** o teste de NFR do gate continua dentro do teto calibrado (ordem 016).
- Suíte verde; `doctor` sem mudança de veredito; `habits` dentro da catraca; recibo no tip.

> **Execução headless:** a prova é o teste em sandbox, sem humano no laço até a aplicação do
> patch. Nenhuma chamada externa.

## Contrato de execução
- Trabalhe APENAS no branch `feat/043-gate-worktree-autoprotecao`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ src/
- Prove com o ledger: `maestro evidence --record --label order-43 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 043` (você não fecha a própria ordem).
accepted_at: 2026-09-26T09:16:48-03:00
accepted_session: desconhecido
accepted_tree: 6339217ee2898b20219a4d8a370cf363301421d2
accepted_intent: 6
