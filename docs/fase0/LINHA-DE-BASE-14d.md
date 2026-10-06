# Fase 0, item 4 — linha de base de 14 dias (fotografia de 06/10/2026)

Janela: **2026-09-22T05:19:53-03:00 a 2026-10-06T05:19:53-03:00** (14 dias). Só **inteiros** e só **metadados**: nenhum prompt,
nenhum caminho completo, nenhum id de sessão. Gerada por leitura (jq sobre o ledger e sobre os transcritos), sem escrever
nada fora deste arquivo e dos tars. Arquivo morto dos dados brutos: `~/.maestro/archive/fase0-2026-10-06/`
(`maestro-logs-evidence-order-state.tar.gz`, `maestro-telemetry.tar.gz`).

## 1. Ledger (`~/.maestro/logs/routing.jsonl`), janela de 14 dias

Sessões distintas com algum evento: **270**.

| evento | n |
|---|---|
| delegation | 11084 |
| gate_pass | 7303 |
| habit_warn | 786 |
| route_fix | 402 |
| decision | 363 |
| gate_warn | 280 |
| **gate_block** | **261** |
| order_create | 256 |
| session_end | 228 |
| order_accept | 209 |
| director_ask | 165 |
| intent | 51 |
| conform | 37 |
| outcome | 34 |

### `gate_block` por classe (261)

| classe | n |
|---|---|
| Bash · `rm_recursive` | 82 |
| Write · sem decisão de roteamento (`.sh` 26, `.ts` 13, `.py` 6, `.md` 3, demais) | 57 |
| sem classe registrada (`gate_block` sem campo de classe) | 25 |
| Bash · `privilege_escalation` | 22 |
| Edit · sem decisão de roteamento | 17 |
| `self_path_write` (escrita em `self_paths`) | 16 |
| Bash · `container_destructive` | 9 |
| Bash · `accept` (`order --accept` pelo executor) | 9 |
| Bash · `git_reset_hard` | 6 |
| Bash · `system_power` | 5 |
| Bash · `git_discard` | 4 |
| Bash · `remote_pipe_shell` | 3 |
| Bash · `disk_format` | 3 |
| Bash · `git_force_push` | 2 |
| Write · `frozen_zone` | 1 |

`gate_warn` (280): `rm_recursive` 124, `privilege_escalation` 104, `frozen_zone` (Edit) 13, `remote_pipe_shell` 9,
`git_force_push` 7, `git_discard` 7, `accept` 6, `container_destructive` 5, `system_power` 4, `disk_format` 1.

## 2. Bytes de injeção do `session-start`

Saída do hook (stdout) medida em `MAESTRO_HOME` isolado, sem checagem de update, com o hook do `main` (`a61f3d3`).
Teto declarado: **8000 bytes**.

| projeto | bytes |
|---|---|
| Maestro | 7869 |
| spock | 7506 |
| NetForge | 7979 |

## 3. Latência por chamada (fixtures de sandbox, `tools/medir-controles.sh 11`)

N = 11 amostras, mediana em ms inteiros. Máquina: **sonda 10 ms, load 5,67 em 8 CPUs** (carga acima de 1,0 por CPU durante a
medição: valem como ordem de grandeza, não como piso).

| controle | mediana ms | min | max |
|---|---|---|---|
| hook:session-start | 201 | 167 | 240 |
| hook:pre-tool-gate (passa) | 104 | 82 | 119 |
| hook:pre-tool-gate (bloqueia) | 89 | 80 | 102 |
| hook:pre-bash-guard (passa) | 35 | 27 | 53 |
| hook:pre-bash-guard (perigo) | 28 | 24 | 32 |
| hook:pre-agent | 32 | 26 | 44 |
| hook:pre-director-ask | 39 | 33 | 58 |
| hook:user-prompt-submit (texto) | 50 | 35 | 66 |
| hook:user-prompt-submit (comando) | 67 | 47 | 80 |
| hook:post-edit-habits | 102 | 73 | 261 |
| hook:session-end | 87 | 77 | 120 |
| hook:subagent-stop | 37 | 27 | 47 |
| hook:gate-report | 51 | 39 | 78 |
| hook:stop-turno | 8 | 7 | 14 |
| guarda:kill-switch | 10 | 9 | 19 |
| cli:habits-all | 90 | 77 | 134 |
| cli:conform-check | 226 | 169 | 290 |
| cli:doctor | 2326 | 1989 | 2674 |
| cli:verify-check | 44 | 38 | 57 |
| cli:evidence | 103 | 81 | 128 |
| cli:order-list | 81 | 66 | 111 |

## 4. Tokens e custo por sessão (registros `type:"cost-state"` dos transcritos do Claude Code)

Fonte: o **último** `cost-state` de cada transcrito modificado nos últimos 14 dias (`~/.claude/projects/*/*.jsonl`). **Ressalvas:**
(a) o registro é gravado no fim da sessão ou na retomada: **232 dos 894 transcritos** da janela o têm; (b) é da **máquina
toda**, não só do Maestro; (c) o custo foi convertido de USD para **centavos inteiros** (`round(totalCostUSD × 100)`).

| medida | valor |
|---|---|
| sessões com `cost-state` | 232 |
| custo total (centavos) | 869823 |
| custo por sessão: mediana / p90 (centavos) | 268 / 8489 |
| tokens totais (entrada + saída + cache criação + cache leitura + thinking) | 22186686928 |
| tokens de saída totais | 57453297 |
| tokens por sessão: mediana / p90 | 6143710 / 150018535 |
| duração total das sessões (s) | 11910954 |
| tempo total de API (s) | 662672 |
| tempo total de ferramentas (s) | 648201 |

## 5. O que esta fotografia não cobre

- Não há `session_start` no ledger: o número de sessões vem dos `session_id` dos eventos, que subconta sessões sem nenhum evento.
- A latência é de fixture, com carga ambiente; o `session-start` real em projeto grande é maior.
- Esta fotografia **conta** bloqueios; não julga quantos foram úteis. Isso é da avaliação por caso, fora desta fase.
