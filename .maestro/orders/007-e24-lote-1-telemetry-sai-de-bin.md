<!-- maestro-order v1
id: 007
ts: 2026-09-14T19:08:25-03:00
epoch: 1789423705
head: 4eedb5daef42608f69c401695fa53dcd2789ee02
branch: refactor/007-e24-lote1-telemetry
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
-->
# Ordem 007 — E24 Lote 1: telemetry sai de bin/maestro — o lote que existe para provar o mecanismo



## Contrato de execução
- Trabalhe APENAS no branch `refactor/007-e24-lote1-telemetry`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-7 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 007` (você não fecha a própria ordem).

## Por que esta ordem existe

Lote 1 do E24, sob INTENT v2, Prioridade 5. O Lote 0 construiu a régua; este é
o primeiro lote que move código.

**LARGADA CRONOMETRADA: 2026-09-14T19:08:25-03:00.**

Isto não é detalhe administrativo. O produto do Lote 1 **não é o módulo** — é a
resposta a duas perguntas que não têm amostra hoje:

1. **Quantas alterações de teste um lote exige?** Se 0, o mecanismo é
   transparente e os catorze lotes seguintes são mecânicos. Se ≥3, o split está
   mudando comportamento e não estrutura, e o plano volta ao gate.
2. **Quanto dura um lote ponta a ponta, incluindo review humano?** É deste
   número, e só dele, que sai o prazo da dívida declarada. Prazo escolhido antes
   de existir amostra é a promessa em comentário que o supervisor proibiu.

Por isso nada alheio entra neste lote. A issue #18 (duas fontes discordando do
estado da ordem) é pequena e cabia tecnicamente — mas o produto aqui é uma
MEDIÇÃO, e trabalho extra contamina exatamente o número que se quer colher. Ela
fica na fila com a #20, que é irmã dela.

## O alvo

`telemetry` (E20), `bin/maestro:4186-4333`, ~148 linhas, oito funções:
`_tel_cli_config_set_remote`, `_tel_cli_config_remove_remote`,
`_telemetry_status`, `_telemetry_push`, `_telemetry_pull`,
`_telemetry_set_remote`, `_telemetry_off`, `cmd_telemetry`.

Escolhido pelo critério do arquiteto, em ordem de desempate: **blast radius** >
cobertura de teste dedicada > acoplamento > tamanho. Tem teste próprio
(`tests/cli/test-telemetry.sh` e `tests/hooks/test-telemetry-sync.sh`), já
sourceia duas libs externas (exercita o padrão), é opt-in e nunca bloqueia por
desenho — **se quebrar, ninguém para de trabalhar**. Tamanho é o critério de
MENOR peso, deliberadamente: o primeiro lote não existe para colher linhas.

## O critério de saída — não é "o comando migrou"

`maestro habits lib/cmd-telemetry.sh` tem de sair **0**: arquivo ≤400 linhas e
nenhuma função >60. Isso força **decomposição por responsabilidade** dentro do
lote, em vez de mover blocos de texto.

A razão está medida: dos 48 achados da catraca, **22 vivem em `bin/maestro`** —
46% da dívida do repo inteiro. Mas só 2 são `oversized-file`; **18 são
`oversized-function`, e função de 203 linhas continua com 203 depois de mudar de
arquivo**. Se os quinze lotes apenas moverem texto, a dívida cai de 48 para 46 e
o prazo vence com quase tudo em pé.

Se `telemetry` — 148 linhas, o caso mais fácil que existe — não cumprir isso, o
mecanismo está errado e a hora de saber é agora.

## Gatilho objetivo de reversão — qualquer um basta

1. o módulo não fica ≤400 com funções ≤60 sem inventar helper sem nome de domínio;
2. a suíte precisa de mais de **duas** alterações de teste;
3. `maestro doctor` muda qualquer veredito;
4. o par de tempo antes/depois de `run-all.sh` sob load ≤2,0 piora.

Reverter o Lote 1 e manter o Lote 0, que tem valor sozinho.

## Contrato de execução
- Trabalhe APENAS no branch `refactor/007-e24-lote1-telemetry`; NUNCA no main.
- Zonas CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/`, `hooks/`, `src/` e agora `lib/` não se editam: patch em `docs/patches/`.
  `lib/` nasceu denylisted no Lote 0 — o módulo novo é ARQUIVO COMPLETO no patch.
- Diretiva `# shellcheck source=lib/cmd-telemetry.sh` é obrigatória: `shellcheck -x`
  não resolve `$REPO_DIR`, e sem ela o gate passa sem ter verificado nada.
- Degradação I-2: módulo ausente derruba o COMANDO com `die env` e fix, não o CLI.
- Gates locais antes do push: `shellcheck -x -P SCRIPTDIR --severity=error`,
  `bash -n`, `maestro habits --all`, suíte completa. Uma execução de CI.
- Prove com o ledger: `maestro evidence --record --label order-7 -- bash tests/run-all.sh`.
- Direção vigente: INTENT v2, Prioridade 5.
- Absorva ANTES de commitar governança.
- **Registre a hora de chegada.** A duração é entregável desta ordem.
