<!-- maestro-order v1
id: 023
ts: 2026-09-18T21:26:27-03:00
epoch: 1789777587
head: c41fb6f4e02c3bc204f8843800b45e3186a5dbd1
branch: feat/023-evals-do-plugin
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 023 — evals do plugin: o Maestro nao tem diretorio evals



## Contrato de execução
- Trabalhe APENAS no branch `feat/023-evals-do-plugin`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-23 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 023` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v3, Prioridade 4 — "prova mecânica antes de declaração". O Capitão rodou
`claude plugin eval` e recebeu:

```
No eval cases found
```

O Maestro **não tem diretório `evals/`**. O plugin promete comportamento —
roteamento, rito da ordem, gate, injeção — e nada disso é exercitado por eval.
A suíte em `tests/` prova o CÓDIGO; nenhum teste prova que o AGENTE se comporta
como o plugin promete.

## O formato, aprendido da ferramenta

Não invente: `claude plugin eval init --bare <nome>` gera o molde. Confirmado
nesta sessão:

```
evals/<caso>/prompt.md          frontmatter: max_turns, allowed_tools
evals/<caso>/graders/*.md       frontmatter: type (llm|…), weight
```

`claude plugin eval` roda `<eval dir>/**/case.yaml` OU `prompt.md + graders/*.md`.
O diretório default é `evals/`, salvo `--eval-dir` ou o valor de
`experimental.evals` no manifesto.

**Use `--ablation with-without`** (o default quando um plugin resolve): ele roda
um braço SEM o plugin e reporta o delta. É o que separa "o modelo acertou" de
"o plugin fez acertar" — sem isso o eval mede o modelo, não o Maestro.

## Os quatro casos

**Três que passam hoje:**

1. **Rito da ordem** — `create` → `status` → `evidence` → `accept`. O caso
   verifica que o agente segue a sequência e que o aceite exige prova. É o
   contrato mais antigo e mais exercitado do plugin.
2. **Gatilho do Stop chamando `director.ask`** — com a linha `[spock]
   aguardando:` presente E o socket da Ponte disponível, o gerente pergunta em
   vez de esperar resposta digitada (ordem 020, INTENT v3). **Sem socket, nada
   dispara** — esse é o caso que prova a degradação, e ele vale tanto quanto o
   positivo.
3. **Catálogo por peer visto de uma sessão de gerente** — as tools que o daemon
   expõe para pane de gerente (`director.ask`, `director.wait`, `director.report`)
   e **não** as do Diretor (`gates.resolve`, `captain.*`, `ponte.*`). Autorização
   por SO_PEERCRED + cadeia `/proc`.

**Um que reprova de propósito — controle negativo.** Sem ele a suíte não prova
nada: uma suíte que só tem verde não distingue "o plugin funciona" de "os
graders são frouxos". O caso negativo tem de reprovar **por motivo nomeado**, e
o relatório tem de mostrar isso.

## O CASO DO NFR — leia antes de escrever, é armadilha paga

O NFR de hook é **50 ms por invocação**, e o quarto eixo que o Capitão pediu é
ele. Mas:

> **O teto de 50 ms vale na máquina de REFERÊNCIA (a CI). Nesta forge vale o
> DELTA contra o baseline do mesmo caso.**
> (`docs/architecture/ARCHITECTURE.md`, seção NFRs, decisão do Capitão 18/09.)

Medido: esta forge é **~4,8x mais lenta por invocação** que o runner da CI, e a
razão é estável entre os sete casos — capacidade, não regressão. `gate_pass` deu
22 ms na CI e 119 ms aqui, com o MESMO código.

Então: **um eval que cobre 50 ms absolutos nesta forge reprova sempre.** O caso
mede o delta contra o baseline da mesma máquina; o teto absoluto só na CI. Se
você escrever o caso cobrando o número absoluto, ele vira o falso vermelho que
já custou duas rodadas a este projeto.

## TRAVA DE CONTRATO

- `evals/` é diretório NOVO. Se o manifesto (`.claude-plugin/plugin.json`)
  precisar de `experimental.evals`, isso é mudança de manifesto — **PARE e
  chame** antes, porque o manifesto acabou de ser bumpado para 1.16.0 e mexer
  nele fora do rito de release tem consequência.
- **Nenhum eval pode ter efeito em produção.** `director.report` acorda um
  humano; `director.ask` também. Se um caso precisar chamá-los de verdade,
  **PARE e pergunte** — o Capitão já barrou isso uma vez por classificação de
  transação real, e a decisão é dele.
- Eval roda `claude` de verdade, na conta do usuário, com custo. Respeite
  `max_turns` baixo e diga no relatório o custo observado.

## Prova exigida

- **O resultado de `claude plugin eval maestro@maestro` anexado** ao patch —
  é o que o Capitão pediu, e é a diferença entre "escrevi evals" e "os evals
  rodam".
- Os três casos positivos passando, **com o delta da ablação** mostrando que o
  plugin é a causa.
- O caso negativo reprovando **pelo motivo nomeado**, não por acidente.
- Suíte `tests/run-all.sh` intocada e verde — evals não substituem testes.
- `maestro habits` limpo nos arquivos novos; `doctor` sem mudança de veredito.
- Recibo `maestro evidence --record --label order-23 -- bash tests/run-all.sh`.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-023 -b feat/023-evals-do-plugin main`.
- **TUDO que a ordem muda entra como patch em `docs/patches/`**, `evals/` e
  `docs/` inclusive. Um pacote, um diretório, ordem de aplicação.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`. **Commite.**
- Grave o essencial em `docs/patches/023-NOTAS.md`, incluindo o relatório do eval.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 023`.

## EMENDA (2026-09-18, changelog oficial v2.1.269+) — comece pelo `init`, não pela mão

**Não escreva os casos do zero.** `claude plugin eval init` na raiz do plugin faz
uma entrevista e **escreve casos e graders a partir da descrição do que é um bom
resultado**. Rode ele primeiro; sua curadoria vem DEPOIS, em cima do que ele
gerou.

A ordem do trabalho passa a ser:

1. `claude plugin eval init` na raiz — deixa a ferramenta propor a suíte;
2. **curadoria**: corte o que não corresponde ao que o plugin promete, ajuste
   grader frouxo, e garanta que os quatro eixos do Capitão estão cobertos (rito
   da ordem · gatilho do Stop · catálogo por peer · NFR por delta);
3. **o controle negativo** — esse você escreve à mão, porque uma ferramenta que
   gera casos a partir de "o que é um bom resultado" não gera o caso que tem de
   reprovar.

`--bare <nome>` continua servindo para caso avulso; o molde confirmado é
`prompt.md` (frontmatter `max_turns`, `allowed_tools`) + `graders/*.md`
(frontmatter `type`, `weight`).

### CUSTO — meça antes de rodar a suíte inteira

**Cada caso é chamada real de modelo, na conta do Capitão.** Rode **UM** caso
primeiro (`--case <glob>`), registre o custo observado, e só então rode a suíte.

Use `--max-cost-usd` como teto duro na primeira corrida completa. Diga no
relatório o custo por caso e o total — sem isso, "os evals rodam" é afirmação
sem número.
