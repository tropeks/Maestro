<!-- maestro-order v1
id: 016
ts: 2026-09-16T17:42:15-03:00
epoch: 1789591335
head: 555cda99dfdcf2d689d61817d7062658a21d0c72
branch: fix/016-sonda-de-baseline
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: desconhecido
-->
# Ordem 016 — teto de latência calibrado por SONDA da máquina

**REESCRITA em 2026-09-16.** A primeira redação desta ordem (limiar de carga
relativo ao `ncpu`, 0,50/CPU) foi implementada, provada e recusada em `rework`.
A implementação estava certa; a CALIBRAÇÃO estava errada, e o erro foi do
gerente. O que aquela rodada mediu é o que motiva esta.

## Por que esta ordem existe

INTENT v2, Prioridade 4 ("prova mecânica antes de declaração") e Prioridade 3
("nunca fingir mecânico o que é compliance assistido").

**Carga é o proxy errado.** Medido em 2026-09-16, mesma máquina, mesma janela,
com o limiar forçado alto para não mascarar:

| versão | `gate_pass` min | mediana |
|---|---|---|
| antes da ordem 015 (`4051dc4`) | 92ms | 120ms |
| depois, com a 016 v1 (`c73ad3d`) | 79ms | 119ms |

Idêntico. **Não há regressão de código** — o custo é anterior ao E24 inteiro. E
a CI passa os mesmos testes com teto ESTRITO (verde nos PRs #35 e #37). O modelo
de custo documentado (`tests/lib/latency.sh:93`) diz ~12ms para o caminho que
passa; aqui o MÍNIMO é 79ms, e o mínimo aproxima o caso sem contenção.

Conclusão: **esta forge é ~6x mais lenta por invocação que o runner da CI.** O
limiar absoluto de 2,00 escondia isso porque a máquina quase nunca fica abaixo
dele. Carga mede CONTENÇÃO; o que reprova aqui é CAPACIDADE.

### O erro da v1, escrito para não se repetir

O fator 0,50/CPU foi derivado do equivalente por-CPU do limiar antigo na CI
(2,00 ÷ 4 CPUs). Mas a CI **nunca rodou a 0,50/CPU** — ela roda a 0,22–0,26/CPU.
O fator tinha de sair das MEDIÇÕES observadas como quietas, não do limiar.
Puxar número de limiar antigo em vez de medição é o vício; ele passou pelo gate
humano porque a conta parecia aritmética e não empírica.

Efeito se aquilo tivesse mergeado: a forge ficaria **vermelha com a máquina
ociosa e verde com ela ocupada**. Invertido, e pior que o mascaramento.

## O desenho — decisão do diretor, 2026-09-16

**Sonda**: N invocações no-op do próprio hook pelo caminho do kill-switch
(`MAESTRO_OFF=1`), medidas no INÍCIO da corrida. É o piso já documentado no
modelo de custo ("~3ms, custo do kill-switch sozinho"): mesmo binário, mesmo
interpretador, mesmo `source`, zero trabalho. Mede a capacidade da máquina para
exatamente aquilo que se orça.

**Fator** = `max(1, sonda ÷ SONDA_REF)`, aritmética inteira ×100 — nenhum float,
em lugar nenhum (`CLAUDE.md`).

**Teto** = `orçamento × fator`, no lugar do `× FOLGA` binário de hoje.

As três condições do diretor caem fora da FÓRMULA, não de caso especial:

1. **Na CI o teto continua estrito e absoluto** — lá a sonda ≈ `SONDA_REF`, o
   fator dá 1, o teto é o orçamento puro. O NFR segue cobrado na máquina de
   referência, que é o único lugar onde ele é cobrado de verdade.
2. **A sonda só relaxa em máquina que se PROVOU mais lenta**, na proporção que
   provou.
3. **Nunca mais permissiva que a CI** — é o que o `max(1, …)` garante.

E "quieta" deixa de ser função de load absoluto.

## Ponto de inserção

`maestro_latency_report` (`tests/lib/latency.sh:152-161`) já calcula
`MAESTRO_LATENCY_TETO`; troca-se a FONTE do fator. `maestro_latency_read_load`
**continua existindo** — load vira informação no relatório, não portão. Não o
remova: saber a carga ao lado da medição é a regra do diretor que originou o
arquivo.

`probe_ms` vai gravado no recibo ao lado de `load1m_x100` e `ncpu`.
`lib/core-evidence.sh` é o dono do formato (`_ev_write`); `lib/cmd-evidence.sh`
grava.

## BOOTSTRAP EM DOIS PRs — não tente fazer num só

`SONDA_REF` só pode sair da CI, e a sonda ainda não existe. Então:

**PR 1 — instrumenta e MEDE, sem mudar enforcement.** A sonda é executada,
impressa no relatório e gravada no recibo. O teto continua decidido como hoje.
A CI publica o número, e é dele que sai `SONDA_REF`.

**PR 2 — calibra e liga.** Fixa `SONDA_REF` com o valor medido na CI e troca o
teto para o fator.

É o mesmo padrão warn→block que este projeto já usou para promover o gate
(CHANGELOG v1.3.0): instrumentar, medir em uso, e só então cobrar.

## A HIPÓTESE QUE O PR 1 TEM DE VALIDAR COM DADO

O desenho assume que **sonda e medição inflam JUNTAS sob contenção**, de modo
que a RAZÃO entre elas isole capacidade e cancele carga.

Isso é hipótese, não fato. Se a razão não for estável entre níveis de carga
nesta forge, a sonda relava carga por outra porta e o PR 2 **não sobe**.

**Critério de saída do PR 1**: medir a razão em pelo menos três faixas de carga
distintas nesta forge e mostrar os números. Se a razão variar de forma que mude
o fator inteiro, PARE e reporte — não ajuste a fórmula para o dado caber.

## Travas de contrato

- `probe_ms` é campo NOVO no recibo. Nome e forma não mudam; o leitor antigo
  continua tolerante (`maestro-evidence-v1`, sem migração — mesmo tratamento da
  emenda v1.15).
- **Emenda do `DATA_MODEL` no MESMO changeset** que o código (regra do
  `CLAUDE.md`). A maior emenda hoje é **v1.15**, então a próxima é **v1.16** — e
  a posição é POR SEÇÃO (o § do recibo, `docs/architecture/DATA_MODEL.md:601-643`),
  nunca no fim do arquivo. Descubra a maior com
  `grep -oE "Emenda v1\.[0-9]+" docs/architecture/DATA_MODEL.md | sort -t. -k2 -n | tail -1`.
  Esse erro já foi cometido duas vezes neste projeto.
- **Mexer em orçamento em ms, em `FOLGA`, ou no veredito do `doctor`: PARE e
  chame.** Esta ordem muda o TETO, nunca o orçamento. Se um teste passar a
  falhar e a correção natural for mexer no que ele afirma, isso é ACHADO.

## O que se aproveita da v1 (branch `fix/016-limiar-relativo-ncpu`, `c73ad3d`)

- `tests/lib/test-limiar-ncpu.sh`: o MOLDE serve — ele prova calibração em
  pontos forçados e traz uma guarda de divergência que foi sabotada e gritou nos
  10 valores testados. O alvo muda de `ncpu` para sonda.
- O patch de `lib/cmd-evidence.sh` e a decisão de piso do `nproc` provavelmente
  deixam de ser necessários, já que o load sai do portão. **Confirme, não
  presuma** — e diga no relatório o que reaproveitou e o que descartou.

Branch NOVO, a partir do `main`: `fix/016-sonda-de-baseline`. Não construa em
cima do `c73ad3d` — ele carrega a calibração superseded.

## Prova exigida

- Teste da fórmula em pontos forçados: sonda = ref → fator 1; sonda = 6×ref →
  fator 6; sonda < ref → fator 1 (nunca mais permissivo que a CI).
- Os números da validação da hipótese (três faixas de carga).
- Suíte completa verde em cópia patchada.
- `maestro habits` limpo em cada arquivo tocado, medido um a um.
- `maestro doctor` sem mudança de veredito.
- Recibo: `maestro evidence --record --label order-16 -- bash tests/run-all.sh`.
- **O número que justifica a ordem**: as 6 medições que hoje reprovam nesta
  forge (`gate_pass`, `denylist`, `perigo(bloqueia)`, `ofuscado`,
  `comando-16KB`, `caminho-22KB`) passam a caber no teto por fator, **sem que
  nenhum orçamento em ms tenha sido tocado**. Se não couberem, a sonda não está
  medindo o que se propõe — relate, não force.

## Fora desta ordem

`tests/cli/test-order-issue11.sh` está PENDENTE desde a ordem 009: procura em
`bin/maestro` o mecanismo de `load1m_x100`/`ncpu`/`inconclusive` que foi para
`lib/core-evidence.sh` no E24, então as asserções de qualificação de limiar
nunca são exercitadas. Vai para a ordem 018. Se tropeçar, **relate e siga**.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-016b -b fix/016-sonda-de-baseline main`.
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
  `tests/` e `docs/` se editam direto.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`.
- **Medir latência com duas suítes concorrentes produz FAIL espúrio** — o
  executor da v1 perdeu uma medição assim. Sempre sequencial.
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`, nunca `f; return $?`.
- `bash -n` por arquivo é o gate de sintaxe; `shellcheck --severity=error` não
  pega sintaxe em módulo sourceado.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 016`.
accepted_at: 2026-09-17T10:29:00-03:00
accepted_session: desconhecido
accepted_tree: 7a0a66396224e961dff2432ff0750db8e16a3d71
accepted_intent: 3
