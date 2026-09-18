<!-- maestro-order v1
id: 019
ts: 2026-09-17T10:40:01-03:00
epoch: 1789652401
head: b1b91eccbca8a7b2a77344b057a2a1e26091e753
branch: fix/019-guard-por-mecanismo
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 019 — guard de teste pergunta pelo mecanismo, nao pelo endereco: 5 blocos desligados pelo E24



## Contrato de execução
- Trabalhe APENAS no branch `fix/019-guard-por-mecanismo`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-19 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 019` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v3, Prioridade 4 — "prova mecânica antes de declaração". **Cinco blocos
de asserção da suíte não rodam há semanas, e nada acusou.**

Os testes de ordem usam um guard que pula o bloco quando o mecanismo ainda não
foi aplicado (porque `bin/` está na denylist e o patch é aplicado por mão
humana). O guard pergunta pelo **endereço**:

```bash
BIN="$REPO/bin/maestro"
grep -qF '<trecho do mecanismo>' "$BIN" && PATCHED=1
```

O E24 moveu os mecanismos para `lib/`. O guard não seguiu. Medido em 2026-09-17:

| teste | procura | em `bin/maestro` | mora hoje em |
|---|---|---|---|
| `test-order-issue11.sh:45` | `load1m_x100=%s` | **não** | `lib/core-evidence.sh` |
| `test-order-issue12.sh:50` | `--absorbed-by` | **não** | `lib/cmd-order.sh` |
| `test-order-issue13.sh:48` | `_order_valid_stamp` | **não** | `lib/cmd-order.sh` |
| `test-order-issue13.sh:50` | `id de ordem duplicado` | **não** | `lib/cmd-order.sh` |
| `test-order-006-habits-debt.sh:25` | `base_vence` | **não** | `lib/cmd-habits.sh` |

Cinco de cinco. Todos dão `PATCHED=0` para sempre, imprimem `PENDENTE`, e as
asserções atrás deles nunca são exercitadas.

## Por que é grave, e não cosmético

**É a issue #9 por outra porta.** A ordem 005 já atacou "o warn-only que esconde
a catraca": sinal que não reprova vira sinal que ninguém lê. `PENDENTE` não é
falha, então a suíte ficou verde enquanto perdia cobertura.

**Custo já materializado:** as asserções desligadas do `test-order-issue11.sh`
são exatamente as de qualificação de limiar — `VÁLIDA (load 1.80)`,
`fora do limiar (load 12.12)`, `N medição(ões) INCONCLUSIVA(S)`. São as que
teriam exercitado a **ordem 016**. A 016 foi executada, revisada e teve o PR 2
parado sem que ninguém soubesse que a cobertura dela estava menor do que
aparentava.

**Custo futuro, e é por isso que esta ordem não espera:** restam duas ordens no
E24 — `consent`+`conduct`+`graph`, e o `upgrade` sozinho, que é o de maior blast
radius do épico. Cada uma vai mover mais mecanismo para fora de `bin/maestro` e
**desligar mais blocos em silêncio**.

## O desenho

O guard passa a perguntar pelo **MECANISMO**, não pelo endereço: "este trecho
existe em algum lugar do código do plugin?", não "está neste arquivo?".

Regras que o desenho tem de respeitar:

- **O guard não pode virar sempre-verdadeiro.** Um guard que nunca pula é tão
  inútil quanto um que sempre pula — ele existe para distinguir "patch ainda não
  aplicado" de "patch aplicado". Prove que ele ainda PULA quando o mecanismo
  realmente não existe.
- **Não amplie a busca a ponto de casar com o próprio teste.** Procurar no repo
  inteiro faz o teste achar a string dentro de si mesmo e passar sempre.
  Delimite o escopo ao código do plugin (`bin/`, `lib/`, `hooks/`), nunca
  `tests/`.
- Cuide do custo: cinco guards × `grep` recursivo por arquivo de teste não pode
  transformar a suíte num crawl. Meça antes e depois e relate.

## ESPERE QUE LIGAR AS ASSERÇÕES REVELE FALHA

Cinco blocos voltam a rodar de uma vez, contra código que mudou bastante desde
que eles rodaram pela última vez. **É provável que algum reprove.**

Isso é o valor da ordem, não um acidente dela. Quando acontecer:

- **NÃO conserte o código para a asserção passar.** Não ajuste a asserção para o
  código passar. Nenhum dos dois é desta ordem.
- **RELATE**: qual asserção, o que ela afirma, o que o código faz hoje, e desde
  qual ordem provavelmente divergiu (o `git log` do arquivo conta essa história).
- Se a divergência for grande, **PARE** e chame — pode ser que ligar os cinco de
  uma vez seja demais para um changeset, e aí a decisão de fatiar é do diretor.

Uma ordem que entregue "religuei os cinco, três passam, dois reprovam e aqui
está o diagnóstico de cada um" está COMPLETA. Uma que entregue cinco verdes
porque ajustou asserção está reprovada.

## TRAVA DE CONTRATO

- **Não mexa em `bin/`, `lib/` ou `hooks/` nesta ordem.** Ela é sobre os guards
  em `tests/`. Se a correção parecer estar no código de produção, isso é achado
  para outra ordem.
- Mudança de veredito do `maestro doctor`: PARE e chame.
- Não remova nenhum guard "porque o patch já foi aplicado mesmo". O guard existe
  porque `bin/` e `lib/` são denylist e a aplicação é humana — ele volta a
  importar na próxima ordem de patch.

## Prova exigida

- Para CADA um dos cinco guards: prova de que ele agora **liga** com o mecanismo
  presente, e de que ainda **pula** com o mecanismo ausente. As duas pontas, nos
  cinco.
- Contagem de `PENDENTE` da suíte antes e depois, com a lista de quais eram.
- Diagnóstico de toda asserção que reprovar ao ser religada.
- Tempo total da suíte antes e depois (o custo do `grep` mais largo).
- Suíte em cópia patchada, `habits` por arquivo, `doctor` sem mudança de
  veredito.
- Recibo: `maestro evidence --record --label order-19 -- bash tests/run-all.sh`.
  **Se a suíte reprovar por asserção religada, grave o recibo VERMELHO como
  saiu** — não re-rode até dar verde. O recibo honesto é a entrega.

## Nota sobre o NFR do session-start nesta forge

O NFR de overhead do `session-start` reprova **por carga** nesta máquina, e
reprova igual em `main` limpo (A/B com stash feito pelo diretor em 2026-09-17).
É ambiente, não regressão; a CI é o gate estrito. Se a sua corrida reprovar só
nisso, **diga isso e siga** — não é achado novo, é a dívida do skip honesto.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-019 -b fix/019-guard-por-mecanismo main`.
- `tests/` se edita direto. `bin/`, `lib/`, `hooks/`, `src/` não se tocam.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`.
- `bash -n` por arquivo é o gate de sintaxe.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 019`.
