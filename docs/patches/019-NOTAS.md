# Ordem 019 — guard de teste pergunta pelo mecanismo, não pelo endereço

## O que mudou

Os cinco guards que o E24 desligou (mecanismo migrado de `bin/maestro` para
`lib/*.sh`, guard ainda apontando para `bin/maestro`) passam a perguntar pelo
MECANISMO — "este trecho existe em algum módulo do plugin?" — em vez do
ENDEREÇO fixo. Forma copiada do precedente já resolvido em
`tests/cli/test-order-021-absorb-default-branch.sh`:

```bash
PATCHED=0
if grep -rqF '<trecho do mecanismo>' "$REPO/lib" "$REPO/bin" "$REPO/hooks" 2>/dev/null; then
  PATCHED=1
fi
```

Escopo do `grep -r` sempre `lib/ bin/ hooks/` — nunca `tests/` (casaria com o
próprio arquivo de teste e tornaria o guard sempre-verdadeiro).

## Os cinco arquivos e patches

| # | patch | arquivo | guard | mecanismo hoje |
|---|---|---|---|---|
| 1 | `019-01-guard-issue11-por-mecanismo.patch` | `tests/cli/test-order-issue11.sh:45` | `PATCHED` (load1m_x100) | `lib/core-evidence.sh` |
| 2 | `019-02-guard-issue12-por-mecanismo.patch` | `tests/cli/test-order-issue12.sh:50` | `CLI_PATCHED` (`--absorbed-by`) | `lib/cmd-order.sh` + `lib/cmd-order-accept.sh` |
| 3 | `019-03-guard-issue13-por-mecanismo.patch` | `tests/cli/test-order-issue13.sh:48,50` | `CLI_STAMP_PATCHED` / `CLI_DUPE_PATCHED` | `lib/core-order-state.sh` + `lib/cmd-order.sh` |
| 4 | `019-04-guard-006-habits-por-mecanismo.patch` | `tests/cli/test-order-006-habits-debt.sh:25` | `PATCHED` (base_vence) | `lib/cmd-habits.sh` |

Aplicar na ordem numerada (independentes entre si — cada patch toca um
arquivo só — mas mantém-se a ordem por rastreabilidade).

Guards NÃO tocados nesta ordem, de propósito: `HOOK_PATCHED` em
`test-order-issue12.sh` e `test-order-issue13.sh` continuam checando só
`hooks/session-start.sh` — o mecanismo (`absorbed_by`, `_maestro_order_stamp_ok`)
não saiu de lá, não é um dos cinco pontos medidos na ordem, e ampliar o escopo
deles seria escopo além do que foi encomendado.

## PENDENTE: antes e depois

Antes (7 linhas, os cinco guards nunca ligavam):
- `ordem 006/0.3: bin/maestro ainda sem colunas 3/4 ...`
- `issue #11: bin/maestro ainda sem load1m_x100/ncpu/inconclusive ...`
- `issue #12 (i): recusa de absorção por ordem não provada — bin/maestro sem --absorbed-by ...`
- `issue #12 (iii): absorção por ordem provada (NetForge) — bin/maestro sem --absorbed-by`
- `issue #12 (iv): absorção pelo main — bin/maestro sem --absorbed-by`
- `issue #13 (iii): order --list ainda lista o doc do Vitali como ordem — bin/maestro sem _order_valid_stamp`
- `issue #13 (iv): id duplicado listado calado — bin/maestro sem a acusação de duplicata`

Depois: 0 PENDENTE nos cinco pontos (os cinco guards ligam de verdade, cobrando
as asserções reais).

## Asserções que reprovaram ao religar (NÃO consertadas — é a issue #9 pagando de novo, agora no lado do teste)

Duas — mesma causa raiz, mesma classe de bug que esta ordem existe para
corrigir, só que na "prova do terceiro estado" (sabotagem em cópia), não no
guard PATCHED:

1. `tests/cli/test-order-issue11.sh` — `"sabotagem não pegou (padrão do sed
   não bateu — mecanismo mudou de forma?)"`. O bloco de terceiro estado
   copia só `$BIN` (`bin/maestro`) para uma sandbox e faz `sed` no trecho
   `if (( e_load > load_limiar )); then` dentro dessa cópia, para inverter o
   sentido da qualificação e provar que a MESMA asserção reprova. Esse
   trecho morava em `bin/maestro`; a ordem 016 (`E24 lote encadeado — commit
   36419c6`) moveu a qualificação para `lib/cmd-evidence.sh:185`
   (`_ev_cmd_qualifiers`). A cópia sandboxed não inclui `lib/`, o `sed` não
   acha o padrão em `$SAB`, e o próprio teste detecta isso e reprova
   honestamente. Divergência: desde o commit `36419c6` (ordem do E24 "lote
   encadeado: evidence, habits e retro saem juntos").

2. `tests/cli/test-order-006-habits-debt.sh` — mesmo sintoma, mesma causa:
   `now_epoch > vence && cur > alvo` morava em `bin/maestro`, a mesma ordem
   016/`36419c6` moveu para `lib/cmd-habits.sh:183`. A sandbox do terceiro
   estado também só copia `$BIN`, sem `lib/`.

Este NÃO é o defeito que a ordem 019 pediu para corrigir (os cinco guards
`PATCHED`) — é o MESMO padrão (endereço fixo em vez de mecanismo), mas na
construção da sandbox de sabotagem, dentro do corpo do teste que só roda
quando `PATCHED=1`. Consertar a sandbox (fazer `SABROOT/lib` conter uma cópia
sabotada do módulo certo, com o resto symlinkado) é mudança de código de
teste que a ordem não pediu e que muda o COMPORTAMENTO da prova, não só o
guard — por isso fica de fora, relatado para o diretor decidir se abre ordem
nova. Não é regressão de produção; `bin/maestro`/`lib/*.sh` não mudaram nesta
ordem.

## Custo do grep mais largo

`grep -rqF` em `lib/ bin/ hooks/` em vez de `grep -qF` num arquivo único, 5
guards, uma vez cada por execução do arquivo de teste. Tempo total da suíte
medido antes/depois (ver relatório) — a variação ficou dentro do ruído de
carga da máquina (outras 3 frentes rodando em paralelo + run vivo do
NetForge na lab); não dá para atribuir com confiança a este `grep` mais
largo.
