<!-- maestro-order v1
id: 012
ts: 2026-09-16T06:43:19-03:00
epoch: 1789551799
head: 03f8056925287900d2feaf2109fe2dc1cd3ef31f
branch: fix/012-autoprotecao-em-worktree
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: f649a0cf64e6057bff923ab77def9d0d4d339f85
absorbed_at: 2026-09-16T08:24:22-03:00
absorbed_session: desconhecido
-->
# Ordem 012 — autoprotecao reconhece worktree como o mesmo plugin — a guarda vencida por mudanca de endereco



## Contrato de execução
- Trabalhe APENAS no branch `fix/012-autoprotecao-em-worktree`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-12 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 012` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Limites: *"autoproteção do gate: mesmo com record válido, edições a
`.claude/`, `.github/workflows/`, `hooks/`, `bin/`, `src/`, `agents/`,
`config/routing-table.yaml` e `.claude-plugin/` seguem bloqueadas"* (ADR-003
v1.2).

**Dentro de um git worktree essa frase é falsa.** Medido com o MESMO decision
record válido, MESMO payload, editando `bin/maestro`:

```
árvore PRINCIPAL   → "edição bloqueada — protegido pela denylist de autoproteção"
dentro do WORKTREE → (silêncio: PASSOU)
```

A denylist é ancorada em `MAESTRO_PLUGIN_ROOT`, que o `session-start.sh:514`
grava como `REPO_DIR`. O caminho do worktree não casa, e a autoproteção não se
aplica. **A guarda não é removida — é vencida por mudança de endereço**, a mesma
classe que a decisão (A) do Lote 0 recusou quando `lib/` ia nascer fora da
denylist. Só que aqui o endereço muda por frente, e o gate não reclama: silencia.

Motivo imediato: worktree por frente resolve as três colisões de sessão em três
dias (custo medido: 126ms e 6,2 MB por frente), mas **adotá-lo antes deste
conserto trocaria coordenação por autoproteção**, no repo que audita os outros
cinco.

## O mecanismo, já medido

`git rev-parse --path-format=absolute --git-common-dir` distingue o que precisa
ser distinguido:

```
principal  → /home/rcosta00/dev/Maestro/.git
worktree   → /home/rcosta00/dev/Maestro/.git   IGUAL
outro repo → /tmp/tmp.ufSl3rtUCw/.git          DIFERENTE
```

**ARMADILHA VERIFICADA:** sem `--path-format=absolute` a saída é RELATIVA
(`.git`) na raiz e ABSOLUTA no worktree. Comparar a forma crua nunca casaria, e
o conserto pareceria feito sem estar. Testado em git 2.47.3.

Degradação obrigatória: git ausente, comando falhando ou flag indisponível
**não pode afrouxar o gate** — na dúvida, trata como a árvore principal
(INTENT v2, Prioridade 1: falha degrada, nunca bloqueia trabalho; mas aqui
"degradar" é ficar MAIS restritivo, não menos).

## A prova — é o mesmo teste que encontrou o defeito

1. Record válido, editando `bin/maestro` **dentro de um worktree** → **BLOQUEIA**
   pela denylist de autoproteção (hoje passa).
2. Record válido, editando `bin/` de **outro repositório qualquer** → **continua
   livre** (a autoproteção é do plugin, não de todo `bin/` do mundo; é a razão do
   comentário em `config/routing-table.yaml` sobre prefixo relativo).
3. Árvore principal → inalterada.

Os três num teste que reprova se qualquer um regredir.

**AJUSTE DO SUPERVISOR — as três rodam com RECORD VÁLIDO DE VERDADE, nunca mock.**

Sem decision record válido, o portão GENÉRICO (mode=block) bloqueia tudo, e as
três asserções passariam **pelo motivo errado** — o teste ficaria verde sem
nunca ter exercitado a denylist. Seria prova que parece prova, dentro do teste
que existe justamente para fechar essa família.

Com record válido, a ÚNICA coisa capaz de bloquear é a autoproteção. É isso que
torna a asserção 2 (outro repositório continua livre) capaz de provar que o
conserto **não virou bloqueio universal de `bin/`** — que é o modo de falha
oposto, e o mais fácil de introduzir sem perceber.

Grave o record no próprio teste (`maestro decide` num `MAESTRO_HOME` de sandbox)
em vez de depender do record da sessão que roda a suíte — teste que depende do
estado da sessão do chamador é a fuga de ambiente das ordens 001 e 002.

## Contrato de execução
- Branch `fix/012-autoprotecao-em-worktree`; NUNCA no main.
- CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
- Gates locais antes do push: `shellcheck --severity=error`, `bash -n`,
  `maestro habits --all`, suíte completa (`git clone`, nunca `git archive`).
- Prove com o ledger: `maestro evidence --record --label order-12 -- bash tests/run-all.sh`.
- Mudança de FORMATO (nome de variável de política lida por outro projeto,
  texto de recusa do gate) é contrato: PARE e chame.
- Trava procedimental cruzada marca a medição como CONTAMINADA.
