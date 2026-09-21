<!-- maestro-order v1
id: 037
ts: 2026-09-20T21:19:48-03:00
epoch: 1789949988
head: 933acd592f860d4d8e40e74b2e00493ddc333659
branch: fix/037-status-sem-carimbo
frozen: vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
-->
# Ordem 037 — arquivo sem carimbo vira ordem no --status: 10# em id vazio quebra a saida

## O sintoma, reproduzido

De `~/dev/worktrees/app-005-estado` (repo `ponte-app`):

```
$ maestro order --status 5
lib/core-order-state.sh: line 79: 10#: invalid integer constant (error token is "10#")
ordem 005: aberta
  branch  : ? (não existe)
  prova   : lib/core-order-state.sh: line 267: 10#: invalid integer constant
```

Erro de bash vaza para o usuário, e o estado sai ERRADO: `aberta`, branch inexistente,
prova `?` — quando a ordem está provada com recibo válido.

## A causa-raiz, achada e provada

**Não é número de um dígito, e não é padding no branch.** Na MESMA pasta, com o MESMO
comando, ordens de um dígito funcionam:

    $ maestro order --status 1   → ordem 001: aceita … recibo order-1 exit 0   OK
    $ maestro order --status 4   → ordem 004: aceita                           OK

A diferença é o arquivo: **`005-estado-do-app-depois-do-enroll-p.md` não tem carimbo.**
Começa direto em `## 1. A causa-raiz`, sem o bloco `<!-- maestro-order v1 … id: …`.
Medido nos quatro arquivos da pasta: 001, 002 e 004 têm carimbo; 005 tem zero.

Sem carimbo, `_order_field "$f" id` devolve VAZIO, e todo `$((10#$id))` vira `$((10#))`:

- `lib/core-order-state.sh:79` — `_order_evidence_candidates`
- `lib/core-order-state.sh:267` — `_order_evidence_label`

**A guarda já existe e o `--status` não a usa.** `_order_valid_stamp()`
(`core-order-state.sh:29`, issue #13 — "nem todo .md é ordem") é chamada pelo `--list`
(`cmd-order.sh:106`) e pelo `bin/maestro:1411`, mas NÃO pelo caminho que resolve o
arquivo por glob de id (`cmd-order.sh:320`), que serve `--status` e `--accept`. O
`--list`, por usá-la, já acerta hoje:

    (ignorado(s) … sem carimbo de ordem: 005-estado-do-app-depois-do-enroll-p.md)

Duas portas para o mesmo dado, uma com tranca e a outra sem — mesma família da issue #18.

## Segundo defeito, achado ao abrir esta ordem

`maestro order --create` **pendura para sempre** quando stdin é um pipe/socket aberto e
vazio: `lib/cmd-order.sh:42` faz `body=$(head -c 16384)` incondicionalmente. Medido: o
processo ficou 147 s em `pipe_read` com um filho `head -c 16384`, sem prompt, sem
mensagem, sem timeout — tive de matá-lo e repetir com o corpo vindo por stdin.

É o GÊMEO da issue #43 (a mesma linha `head -c 16384`, que a ordem 032 consertou no
`brief --write`) e aqui é pior: lá truncava em silêncio, aqui trava em silêncio.

## O que entra

1. **`--status` e `--accept` aplicam `_order_valid_stamp`** logo depois de resolver o
   arquivo, e **degradam com honestidade**: dizem que o arquivo existe e não é ordem,
   com a MESMA linguagem do `--list` ("sem carimbo de ordem"), apontando o caminho.
   Nunca "aberta", nunca estado inventado.
2. **`10#` nunca sobre vazio** — defesa em profundidade. Erro de bash não vaza para o
   usuário (Prioridade 1: degradar, nunca cuspir stderr de implementação).
3. **`--create` nunca pendura.** Ler corpo de stdin passa a ser EXPLÍCITO (flag, ou
   detecção segura), e a ausência de corpo é caminho normal — ordem nasce só com título
   e contrato, como já acontece quando o corpo vem vazio. Quem planeja decide a forma;
   o critério é: nenhum caminho de `--create` espera dado que pode nunca chegar.

Fora de escopo: mudar o formato do carimbo, consertar o arquivo do `ponte-app` (é do
dono do repo), mexer no `--list` (já está certo).

## Prova exigida

- **Caso reproduzido**: arquivo `NNN-*.md` SEM carimbo → `--status NNN` sai com mensagem
  nomeada, rc previsível e **zero** stderr vindo do bash.
- **Ordem de UM DÍGITO com carimbo** (`--status 5` num `005-*.md` carimbado): funciona,
  resolvendo o rótulo do recibo nas duas variantes (`order-5` e `order-005`, S-1802) —
  a não-regressão que o Capitão pediu por nome.
- **`--accept` sobre arquivo sem carimbo**: recusa nomeada, nunca carimba.
- **`--create` com stdin aberto e vazio TERMINA** — teste com timeout, que reprova se
  pendurar.
- Sandbox de teste com o `lib/` junto (armadilha da 027: copiar só o binário faz o
  `source` falhar e o teste mentir na direção oposta).
- Suíte verde; `doctor` sem mudança de veredito; habits dentro da catraca.

## Contrato de execução
- Trabalhe APENAS no branch `fix/037-status-sem-carimbo`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/
- Prove com o ledger: `maestro evidence --record --label order-37 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 037` (você não fecha a própria ordem).
accepted_at: 2026-09-20T22:14:03-03:00
accepted_session: desconhecido
accepted_tree: 30532bec2d62e59b590b70938be03ab79f07c807
accepted_intent: 4
