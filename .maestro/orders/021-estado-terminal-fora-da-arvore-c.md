<!-- maestro-order v1
id: 021
ts: 2026-09-18T11:07:41-03:00
epoch: 1789740461
head: b1b91eccbca8a7b2a77344b057a2a1e26091e753
branch: fix/021-estado-terminal-fora-da-arvore
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 021 — estado terminal fora da arvore: carimbo nao commitado morre no checkout



## Contrato de execução
- Trabalhe APENAS no branch `fix/021-estado-terminal-fora-da-arvore`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-21 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 021` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v3, Prioridade 4 — "prova mecânica antes de declaração". O estado
terminal de uma ordem é o dado que decide se alguém é interrompido. Hoje ele
**desaparece sozinho**.

### A reprodução, medida no Agenda_Studio (2026-09-18)

O diretor fechou as ordens 012–016 como absorvidas contra o recibo de `main` da
árvore `baccdce5`. Mergeou o PR #150. O recibo de `main` passou a `ac0efe70`. As
cinco **voltaram a aparecer `provada`** — nos dois leitores, `maestro order
--list` e a ronda da Ponte. Ele refechou as cinco e elas voltaram a `absorvida`.

O detalhe que resolve o caso: **o refechamento FUNCIONOU.** Se o carimbo ainda
estivesse lá, `_order_accept_absorb` teria dito "ordem já absorvida — nada a
fazer" (`lib/cmd-order.sh:231`). Ele não disse. Logo o carimbo não existia mais.

### A causa

```
$ git status --porcelain .maestro/orders/
 M 012-…md   M 013-…md   M 014-…md   M 015-…md   M 016-…md

$ git show HEAD:.maestro/orders/012-…md | grep -c '^absorbed_by:'   → 0
$ grep -c '^absorbed_by:' .maestro/orders/012-…md                   → 1
```

**O carimbo terminal nunca é commitado.** `maestro order --accept
--absorbed-by` escreve `absorbed_by:` no arquivo da **árvore de trabalho** e
para aí. O arquivo é rastreado, e no `HEAD` ele não tem carimbo nenhum.

Então o estado terminal vive como modificação não commitada. Qualquer operação
git que restaure a versão do `HEAD` — `checkout`, `stash` sem `pop`, `reset`, a
limpeza que alguns fluxos de merge fazem antes de integrar — **apaga o carimbo
em silêncio**, e o arquivo volta a ser uma ordem sem desfecho.

Isso também explica por que os DOIS leitores concordaram: os dois liam a
verdade. Não era leitor desatualizado, não era recálculo, não era revalidação de
árvore.

### Mesma raiz da issue #36

Lá o carimbo de aceite não atravessa worktree; aqui não atravessa um `checkout`.
Nos dois casos: **estado terminal guardado em arquivo de árvore de trabalho.**
Esta ordem ataca a raiz; a #36 fica mais fácil depois dela.

## O DESENHO — decisão do diretor, 2026-09-18

> O estado terminal passa a ser gravado **fora da árvore de trabalho**, no
> diretório de estado do Maestro (`~/.maestro/`), **chaveado por projeto e
> ordem**, com a árvore como **dado do carimbo e não como fonte da verdade**. O
> arquivo da ordem **pode continuar** recebendo o carimbo, por conveniência de
> leitura humana, mas a **fonte passa a ser o registro fora da árvore**.

### Use a convenção que já existe — não invente chave nova

`hooks/lib/project-state.sh:77-81` já resolve "por projeto":

```bash
maestro_evidence_file() { # <raiz-do-projeto> <rótulo>
  local bf; bf=$(maestro_brief_file "$1")
  local base="${bf##*/}"; base="${base%.md}"
  printf '%s/evidence/%s-%s' "${MAESTRO_HOME:-$HOME/.maestro}" "$base" "${2:-suite}"
}
```

O `<slug>-<hash8>` vem do brief e **já trata worktree e repo principal como o
MESMO projeto** (`project-state.sh:50-51`, E15) — propriedade que esta ordem
precisa e que você ganha de graça ao reusar. Siga esse molde. Se precisar de uma
irmã em vez da própria função, escreva a irmã e diga por quê.

### O que o registro guarda

O suficiente para o estado terminal se sustentar sozinho: qual desfecho, quando,
por quem (sessão), e **a árvore como DADO** — nunca como condição de validade. A
árvore entra para auditoria ("foi absorvida contra esta árvore"), não para ser
reconferida depois.

## TRAVA DE CONTRATO — pare e chame

- **Nome de campo e forma do `--status --json` não mudam.** Campo novo é sempre
  ADITIVO (DATA_MODEL §9, emenda v1.15). O supervisor e o `watcher.ts` leem isso.
- **Nenhum valor novo no enum de `estado`.** Esta ordem muda ONDE o estado mora,
  não quais estados existem.
- **Emenda do `DATA_MODEL` no MESMO changeset**, porque a fonte da verdade do
  §9 muda. A maior emenda hoje é **v1.17** — confirme com
  `grep -oE "Emenda v1\.[0-9]+" docs/architecture/DATA_MODEL.md | sort -t. -k2 -n | tail -1`
  — e a posição é **POR SEÇÃO**, nunca no fim do arquivo. Erro já cometido duas
  vezes neste projeto.
- **Precedência quando os dois discordam.** Arquivo com carimbo e registro sem,
  ou o inverso: decida a regra, escreva-a na emenda, e teste os dois sentidos.
  Se você achar que a regra certa exige decisão de modelo, **PARE e chame**.
- **Migração do que já existe.** Há ordens carimbadas só no arquivo, hoje, em
  vários projetos desta máquina. Elas não podem virar `aberta` quando este
  código entrar. Diga como você trata isso — e se a resposta for "o arquivo
  ainda conta", ótimo, mas escreva a regra.

## O TESTE QUE É A ORDEM

Reproduza o caso do Agenda, mecanicamente:

1. carimba uma ordem como absorvida (ou aceita);
2. roda **`git checkout`** no arquivo da ordem;
3. **o estado continua terminal.**

Tem de **FALHAR contra o código atual** — mostre as duas pontas, vermelha e
verde, com o texto da falha. Cubra os dois desfechos terminais, `absorvida` e
`aceita`, porque os dois têm o mesmo defeito.

Cubra também: registro presente e arquivo restaurado (o caso acima), registro
ausente e arquivo carimbado (a migração), e os dois presentes e concordando.

## Prova exigida

- As duas pontas do teste acima.
- **Ordens 001–021 deste repo, antes e depois: nenhuma muda de estado.** Se
  alguma mudar, é achado — relate antes de seguir.
- As ordens do `~/dev/Agenda_Studio` (012–016, carimbadas só no arquivo) **não
  podem** virar `aberta`. Confira e relate. **Leitura apenas — não escreva
  naquele repo.**
- Suíte completa verde em cópia patchada.
- `maestro habits` limpo em cada arquivo tocado, medido um a um.
- `maestro doctor` sem mudança de veredito.
- Recibo: `maestro evidence --record --label order-21 -- bash tests/run-all.sh`.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-021 -b fix/021-estado-terminal-fora-da-arvore main`.
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
  `tests/` e `docs/` se editam direto.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`. **Commite** — sem commit não há tip onde gravar
  o recibo.
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`, nunca `f; return $?`.
- **Quantificador `{1,N}` grande em regex bash custa ~O(N²)** — mesmo com N=64
  repetido por item. Use `+` e corte o tamanho depois, em aritmética (issue #42).
- `bash -n` por arquivo é o gate de sintaxe.
- **Sem carga sintética** — confirme se o NetForge tem run vivo na lab antes de
  qualquer medição.
- Registre a HORA DE CHEGADA, e grave o essencial em `docs/patches/021-NOTAS.md`
  — o canal de relatório falhou nas últimas rodadas e as notas salvaram a frente.
- O aceite é do diretor: `maestro order --accept 021`.
accepted_at: 2026-09-18T12:50:01-03:00
accepted_session: desconhecido
accepted_tree: b28898f5e7d3f5ff847059ae77b582a753381dd8
accepted_intent: 3
