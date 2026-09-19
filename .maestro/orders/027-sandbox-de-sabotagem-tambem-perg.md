<!-- maestro-order v1
id: 027
ts: 2026-09-18T23:52:09-03:00
epoch: 1789786329
head: c41fb6f4e02c3bc204f8843800b45e3186a5dbd1
branch: fix/027-sandbox-de-sabotagem
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 027 — sandbox de sabotagem tambem pergunta pelo endereco: dois testes copiam so bin-maestro



## Contrato de execução
- Trabalhe APENAS no branch `fix/027-sandbox-de-sabotagem`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-27 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 027` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v3, Prioridade 4. A ordem 019 consertou cinco guards que perguntavam pelo
ENDEREÇO em vez do MECANISMO. Ao religá-los, **duas asserções reprovaram** — e o
diagnóstico mostrou a mesma doença num segundo lugar.

### O que a 019 achou, e deliberadamente não consertou

```
test-order-issue11.sh        FAIL sabotagem não pegou (padrão do sed não bateu)
test-order-006-habits-debt.sh  FAIL sabotagem não pegou (padrão do sed não bateu)
```

Os dois blocos provam o "terceiro estado": copiam o binário para uma sandbox,
**sabotam** o mecanismo com `sed`, e exigem que a asserção reprove — provando que
ela mede alguma coisa. Mas a sandbox copia **só `bin/maestro`**, e o mecanismo
sabotado mudou de casa:

| teste | trecho sabotado | morava | mora hoje |
|---|---|---|---|
| `issue11` | `if (( e_load > load_limiar ))` | `bin/maestro` | `lib/cmd-evidence.sh` |
| `006-habits` | `now_epoch > vence && cur > alvo` | `bin/maestro` | `lib/cmd-habits.sh` |

Confirmado por mim: `grep -l` acha os dois em `lib/`, nenhum em `bin/maestro`. A
mudança foi da ordem 016 (`36419c6`, E24 — evidence/habits/retro saem juntos).

O `sed` não acha o padrão, a sabotagem não acontece, e **o próprio teste flagra
isso** com a mensagem acima. Ou seja: o teste está honesto e o andaime é que
apodreceu.

## Por que é ordem própria, e não emenda da 019

Decisão do diretor. Os cinco guards da 019 eram **booleanos** — trocar de onde se
lê não muda o que o teste faz. Aqui é a **construção da prova**: mexer na sandbox
muda o COMPORTAMENTO da verificação, não só o endereço. Duas mudanças de natureza
diferente não entram no mesmo changeset.

## O trabalho

A sandbox passa a montar o que o mecanismo REALMENTE precisa — não um caminho
fixo. Hoje ela copia `$BIN`; o mecanismo vive em `lib/`, e `bin/maestro` carrega
`lib/` por `_ev_lib_load`/`_habits_lib_load`.

**Cuide de três coisas:**

- **A sandbox tem de continuar isolada.** Copiar o repo inteiro resolveria e
  destruiria o propósito: a prova é que o binário sabotado se comporta diferente,
  e isso exige uma cópia que você controla. Copie a estrutura MÍNIMA que faz o
  mecanismo rodar — e lembre da armadilha já paga neste repo: **cópia solta de
  script que faz `source "$SCRIPT_DIR/lib/…"` vira no-op** (o source falha e o
  script sai na primeira linha útil). Se a sandbox virar no-op, a sabotagem
  "funciona" por acidente e o teste mente na direção oposta.
- **A sabotagem tem de PEGAR, e o teste tem de saber disso.** A mensagem
  `sabotagem não pegou` já existe e é boa — mantenha esse guarda. Ele é o que
  transformou um andaime podre em achado em vez de falso verde.
- **Não mude o que a asserção afirma.** Só o andaime que a sustenta.

## TRAVA — pare e chame

- **Não toque em `bin/`, `lib/` nem `hooks/`.** Esta ordem é sobre `tests/`. Se a
  correção parecer estar no código de produção, isso é achado para outra ordem.
- **Não afrouxe a asserção para o teste passar.** Se o mecanismo mudou de FORMA
  (não só de arquivo) e a sabotagem não é mais expressável, isso é achado: PARE e
  relate.
- Mudança de veredito do `maestro doctor`.

## Prova exigida

- Para os **dois** testes: a sabotagem pega, e a asserção reprova **na cópia
  sabotada** enquanto passa na íntegra. As duas pontas, nos dois.
- Prova de que a sandbox **não virou no-op**: mostre que o binário sabotado
  chega ao corpo real antes de a asserção medir (`bash -x` serve).
- Suíte completa verde em cópia patchada — os dois FAIL de hoje somem.
- `maestro habits` por arquivo; `doctor` sem mudança de veredito.
- Recibo `maestro evidence --record --label order-27 -- bash tests/run-all.sh`.

## Depende da 019

Esta ordem **só faz sentido depois da 019 aplicada** — é ela que religa os guards
e faz os dois FAIL aparecerem. Confirme que a 019 está em `main` antes de
começar; se não estiver, **pare e diga**.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-027 -b fix/027-sandbox-de-sabotagem main`.
- **TUDO que a ordem muda entra como patch em `docs/patches/`.** Um diretório,
  ordem de aplicação numerada.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`. **Commite.**
- Sob `set -euo pipefail`: chamada nua a função que pode devolver 1 mata o
  processo em qualquer ponto; e **`local a="${X:-d}" b="$a/x"` ESTOURA** — todas
  as expansões de um `local` são avaliadas antes de qualquer atribuição ter
  efeito (armadilha achada pela ordem 018). Separe em dois `local`.
- `bash -n` por arquivo é o gate de sintaxe.
- Grave o essencial em `docs/patches/027-NOTAS.md`.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 027`.
