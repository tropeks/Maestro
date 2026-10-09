# C2-R5 — como o recibo e as listas foram obtidos

O `claude` do C2-R5 terminou em 730 063 ms (rc 0). O **recibo do `lancar.sh` foi cortado** pelo teto de parede do turno ("Terminated" no fim do
`recibo.log`) e não gravou `recibo.rc`. Por ordem do Spock o recibo foi **rodado de novo por fora**, depois, na base final do run (`base-r5`), no mesmo ambiente
do lançador (`env -i`, `HOME` real, `PATH` do run, `TERM=dumb`, `MAESTRO_HOME` temporário e vazio): `bash tests/run-all.sh` → **rc 1**. As listas
(`passam.txt`, `falham.txt`) vêm de uma segunda passada da suíte na mesma árvore (`listas-da-suite.sh`, rc 1 da suíte, que **mede e não julga**).

- O C2-R5 **não alterou arquivo nenhum** (0 arquivos, 0 linhas, 0 commits): a árvore final é a base. Por isso `aceite = não` e os **mesmos 8 FAIL da base** seguem em `falham.txt`.
- **Carga da máquina na rodada de fechamento:** `load average: 9,11 / 8,01 / 7,18` quando o recibo terminou; o run do agente rodou com `5,48 / 4,90 / 5,43` (`uptime.txt`).
  Só o *tempo* do recibo foi afetado; o rc e as listas não dependem da carga.
- `stream.jsonl` e os logs completos (`recibo.log`, `suite.log`) **não** foram copiados para o repo (tamanho e conteúdo do agente); ficam em `/tmp/claude-1000/-home-rcosta00-dev-worktrees-maestro-077/exp/runs/c2-r5/`.
