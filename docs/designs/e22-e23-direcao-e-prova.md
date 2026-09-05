# Partitura — E22 direção versionada · E23 prova em vez de palavra

Data: 2026-09-05 · Diretor: Claude (imediato do Capitão) · Origem: review externo de
06e64c2 ("o Maestro registra a aposta, não prova a execução") + mandato do Capitão
("ataca da melhor forma possível e finaliza todas as mudanças, numa tacada só").

Diagnóstico que esta partitura fecha:

| lacuna | hoje | depois |
|---|---|---|
| direção do projeto | não existe; ordem cita `--doc` opcional | `.maestro/INTENT.md` versionado; ordem nasce carimbada com a versão; mudou a direção → ordem pede revisão do plano |
| delegação | `--agents` é declarativo; nenhum hook vê o disparo | funil `planned → started → received → accepted` no log, correlacionado por sessão/ordem; `outcome accepted` em subagent/multi exige `started` |
| recibo | `maestro evidence --record -- true` vale como prova | verificações obrigatórias por área (`.maestro.yaml`); recibo casa `cmd_hash` com o comando declarado; `order --accept` e `outcome accepted` recusam sem o conjunto exigido |
| auto-update | segue `origin/main` sem CI verde | segue a tag móvel `stable`, que só a CI move depois da suíte verde numa tag `v*` |
| habit sensors | contam heredoc de fixture como código | corpo de heredoc é ignorado; `habits_ignore:` no `.maestro.yaml`; baseline refeita → CI verde |

Fronteiras que NÃO mudam: hooks em bash puro (<100ms, sem Bun); log só metadados
(nunca prompt, nunca caminho completo); falha de componente degrada para o fluxo manual;
rede só no auto-update. Todos os campos novos entram no `RECORD_FIELDS` e no
`record_schema_ok`; todo evento/chave novo entra em `common.sh` E em `src/cli.ts` E no
DATA_MODEL §4.

---

## E22 — Direção versionada (`maestro intent`)

### Artefato: `<projeto>/.maestro/INTENT.md` (público, versionado no repo)

```
<!-- maestro-intent v1
version: 3
ts: 2026-09-05T10:00:00-03:00
head: <sha|none>
author_session: <sid|desconhecido>
-->
# Direção — <nome do projeto>

## Problema
## Público
## Resultado
## Prioridades
## Limites
## Fora de escopo
```

- Seis seções obrigatórias, nesta ordem de exigência (a ordem no arquivo é livre).
  Seção vazia (sem nenhuma linha de texto após o título) conta como ausente.
- `version` é inteiro ≥1, sobe só por `maestro intent --bump`; `--bump` recusa se o
  conteúdo (seções, ignorando o carimbo) não mudou desde o carimbo anterior — a versão
  é o número que as ordens citam, não um contador de saves.
- `intent_hash` = 8 hex de sha256 do corpo SEM o carimbo (`sed '1,/^-->$/d'`), o mesmo
  em CLI e hook. sha256sum é aceitável aqui (não roda no hot path do session-start; o
  hook só lê `version:` com awk).

### CLI `maestro intent`

| flag | ação | exit |
|---|---|---|
| `--init [--project P]` | cria o template (recusa se já existe) | 0 / 1 se existe |
| `--show` | imprime versão, hash, e as seções | 0 |
| `--check` | valida carimbo + 6 seções não-vazias; lista o que falta | 0 ok / 1 |
| `--bump [--session S]` | conteúdo mudou → version+1, ts/head/session novos; não mudou → recusa | 0 / 1 |
| (sem flag) | = `--show`; sem arquivo → "sem direção — `maestro intent --init`", exit 0 |

Log: `intent version=<n> n=<version>`? Não — evento `intent` com chave `n=<version>`
e `via=manual`. Só isso (sem título, sem hash).

### Vínculo com ordens (cmd_order)

- `order --create` com INTENT válido carimba `intent_version:` e `intent_hash:` no
  cabeçalho da ordem (linhas novas no bloco `maestro-order v1`; **subir o limite
  `NR>14` dos leitores de cabeçalho para `NR>20`** em `_order_field`, no session-start
  (frozen) e onde mais houver — grep `NR>14`).
- `order --create` sem INTENT: cria normalmente e avisa "ordem sem direção".
- `order --status N`: linha `direção: v2` e, se `intent_version` < versão atual:
  `ATENÇÃO: a direção mudou (v2 → v3) depois desta ordem — revise o plano contra
  .maestro/INTENT.md`. `order --list` marca `[direção mudou]` ao lado do status.
- `order --accept N` com direção desatualizada: recusa (exit 1) a não ser com
  `--intent-reviewed` (o diretor declara que releu o plano contra a direção nova);
  o aceite carimba `accepted_intent: <versão atual>`.

### Injeção na sessão (session-start.sh, bloco "## Projeto")

- INTENT presente e válido (só `version:` via awk, sem sha256): linha
  `direção: INTENT v3 (.maestro/INTENT.md) → plano cita a seção da direção que serve`.
- Presente sem `version:` legível: `direção: INTENT sem carimbo → maestro intent --check`.
- Ausente: `direção: nenhuma → maestro intent --init (E22)`.
- O texto do gate plan ganha o trecho: "plano cita a direção (INTENT vN, seção) — sem
  direção, diga que não há".

### Testes: `tests/cli/test-intent.sh` (novo) + casos em `tests/cli/test-order.sh`
init/show/check/bump (recusa sem mudança; incrementa com mudança); ordem carimbada;
status/list acusam direção desatualizada; accept recusa e aceita com `--intent-reviewed`;
injeção nas três formas; NR>20 lê os campos novos.

---

## E23a — Prova de delegação (funil no log)

Evento `delegation` com chave `phase ∈ planned|started|received|accepted` (+
`session_id`, `agents` quando houver, `n` = ordem quando houver).

| fase | quem emite | quando |
|---|---|---|
| planned | `src/cli.ts` (decide) | record com `agents` (subagent/multi), logo após o evento `decision` |
| started | `hooks/pre-agent.sh` (NOVO; PreToolUse matcher `Agent\|Task`) | disparo real; `agents=<subagent_type sem prefixo "maestro:">` se casar `^[a-z0-9-]+$` |
| received | `hooks/subagent-stop.sh` (NOVO; evento `SubagentStop`) | subagente terminou; `agents=<agent_type>` se o payload trouxer e casar a regex |
| accepted | `cmd_order --accept` | aceite do diretor (`n=<ordem>`) |

- Hooks novos: bash puro, `MAESTRO_OFF` na primeira linha, mesma janela de 4096 bytes
  e mesma extração de `session_id` do pre-tool-gate; nunca leem `prompt`; exit 0 sempre.
  Registrar em `hooks/hooks.json` (timeout 5). O doctor valida hooks.json — conferir
  `check_hooks` para que os eventos novos passem.
- `maestro delegation --session S` (novo cmd bash): funil `planned/started/received/
  accepted` contado no `routing.jsonl` (e rotacionados do mês) para a sessão; exit 0.
  `--all` agrega por sessão (últimas 20).
- `cmd_outcome accepted` com record `mode ∈ subagent|multi`: exige ≥1 `delegation`
  `phase=started` da sessão no log; senão exit 1 com a explicação; `--unproven` passa e
  grava `delegation_proof: "none"` (senão `"started"`); em `direct` grava nada.
  Campo novo `delegation_proof` ∈ `started|none` no `RECORD_FIELDS` + `record_schema_ok`
  (só existe se `outcome` existe).
- `src/cli.ts`: `EVENTS` ganha `delegation`, `outcome`, `order_create`, `order_accept`,
  `budget_warn`, `upgrade`, `habit_warn`, `consent_grant`, `consent_revoke`, `intent`,
  `verify` (o summary do `maestro log` deixa de jogar eventos reais em `unknownEvent`).
- Testes: `tests/hooks/test-delegation.sh` (payloads Agent/Task/SubagentStop; sem prompt
  no log; subagent_type com prefixo `maestro:`; inválido não vira chave), casos em
  `tests/cli/test-e10-cli.sh` (outcome recusa/aceita/--unproven) e `maestro delegation`.

---

## E23b — Verificações obrigatórias por área + recibo casado com o comando

### `.maestro.yaml` (DATA_MODEL §perfil)

```yaml
verifications:
  auth:
    paths: [src/auth/, migrations/]
    labels: [suite, tenant-isolation]
  billing:
    paths: [src/billing/]
    labels: [suite, billing-recovery]
commands:                      # comando canônico por rótulo (opcional)
  suite: bash tests/run-all.sh
  tenant-isolation: bash tests/tenant.sh
habits_ignore: [tests/fixtures/]   # E23d
```

Parser: `hooks/lib/verifications.sh` (bash+awk, sem yq/Bun), aceita lista em flow
`[a, b]` ou separada por espaço. Funções: `maestro_verif_areas <proj>` (nome→paths→labels,
TSV), `maestro_verif_touched <proj> <base> <tip>` (áreas cujos `paths` casam por prefixo
com `git diff --name-only base tip`; tip vazio = working tree + index), `maestro_verif_labels
<proj> <áreas>` (união de labels), `maestro_verif_cmd <proj> <label>` (comando declarado
ou vazio).

### Recibo casa o comando (fecha o buraco do `true`)

- `evidence --record --label L`: se `commands.L` existe e o comando executado (join por
  espaço) difere do declarado, grava o recibo com `cmd_match=no` e imprime que "não é o
  comando declarado"; igual → `cmd_match=yes`; sem declaração → `cmd_match=free`.
- `evidence [--check]`: recibo com `cmd_match=no` é **VENCIDA** ("comando diferente do
  declarado em .maestro.yaml"). Recibo antigo sem a linha = `free`. Além disso, se hoje há
  `commands.L` e o recibo tem `cmd_hash` ≠ sha16 do declarado → VENCIDA (o hash já era
  gravado, só não era comparado).
- Schema do recibo continua `maestro-evidence-v1` (linha nova é opcional e o leitor é
  tolerante).

### `maestro verify` (novo cmd)

`maestro verify [--base REF] [--project P] [--check]`: áreas tocadas (base default =
`git merge-base main HEAD`, ou `master`; sem git → nada), rótulos exigidos, estado de
cada recibo (VÁLIDA/VENCIDA/NENHUMA com o comando para registrar). `--check` exit 1 se
algum exigido não é VÁLIDA. Log `verify n=<faltantes>`.

### Gates

- `order --accept N`: áreas tocadas = diff `merge-base(main, branch)..branch`; cada
  rótulo exigido precisa de recibo com `exit=0`, `wtree_after` = árvore do tip e
  `cmd_match ≠ no`. Faltou → exit 1 listando `rótulo: NENHUMA|VENCIDA — comando`.
  Ordem sem áreas tocadas segue a regra atual (`order-N` prova).
- `outcome accepted`: áreas tocadas = working tree vs `merge-base(main, HEAD)` (na main:
  HEAD~0 = nada; usa só working tree suja); rótulo exigido sem recibo VÁLIDA → exit 1
  ("sem verificação obrigatória: …"); `--unproven` passa e grava `verifications: "missing"`
  senão `"cited"` (campo novo no record, só com outcome). O aviso de honra do `--suite`
  continua para o rótulo `suite` quando não é exigido por área.

### Testes: `tests/lib/test-verifications.sh` (parser), `tests/cli/test-verify.sh`,
casos novos em test-evidence (cmd_match), test-order (accept recusa/aceita), test-e10 (outcome).

---

## E23c — Auto-update segue tag aprovada pela CI

- CI (`.github/workflows/ci.yml`): job novo `approve` (`needs: [shellcheck, suite]`, só
  em `refs/tags/v*`, `permissions: contents: write` no job): `git tag -f stable
  $GITHUB_SHA && git push -f origin refs/tags/stable`. A tag `stable` é MÓVEL por
  desenho; é a única coisa que a CI escreve.
- `~/.maestro/config.yaml`: `update_channel: stable|main` (default `stable`).
- `hooks/lib/update-check.sh`: canal `stable` → fetch `+refs/tags/stable:refs/tags/stable`
  (e as tags `v*`), candidato = commit de `stable`; classificação igual à de hoje
  (ahead/behind/diverged) contra esse commit; merge `--ff-only` para ele. `stable`
  ausente no remoto → estado `no-stable` (sem update, sem erro). Canal `main` = hoje.
- `maestro upgrade [--channel stable|main]`; doctor `check_upstream` mostra canal e
  onde está `stable`; `check_update_state` aceita `no-stable`.
- Log `upgrade` ganha chave `channel ∈ stable|main`.
- Testes em `tests/lib/test-update-check.sh` (ou equivalente existente): remoto de
  fixture com `stable` atrás de `main` → update para ao `stable`; sem `stable` → `no-stable`;
  canal `main` mantém o comportamento.

---

## E23d — Habit sensors ignoram fixture

- `hooks/lib/habit-sensors.awk`: dentro de arquivo `.sh`/`.bash`, linha que abre heredoc
  (`<<-?[ ]*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?`) liga estado; a linha igual ao delimitador
  (tabs à esquerda permitidos com `<<-`) desliga; linhas no estado não alimentam sensor
  nenhum e não contam para `oversized-function` (contam para `oversized-file`, que é
  tamanho de arquivo mesmo).
- `cmd_habits`: `habits_ignore:` do `.maestro.yaml` (prefixos) filtra os arquivos de
  `--all`; default vazio.
- Refazer a baseline `.maestro-habits.tsv` com o sensor novo (`maestro habits --all
  --baseline` ou o comando que existir) e deixar `maestro habits --all --project .`
  verde no CI. Dead-code real em `hooks/lib/update-check.sh:48` → corrigir de verdade.
- Testes: `tests/hooks/test-habits.sh` (heredoc não conta; delimitador com aspas; `<<-`
  com tabs), `tests/cli/test-habits-cli.sh` (`habits_ignore`).

---

## Documentação (mesmo changeset)

EPICS.md: E22, E23 (S-2301 a S-2304) e E24 (adapters, pendente). ARCHITECTURE.md:
ADR-010 (direção versionada e prova em vez de palavra — o que o Maestro passa a exigir e
o que continua sendo honra). DATA_MODEL.md: §INTENT, §ordem (campos novos), §3 record
(`delegation_proof`, `verifications`), §4 vocabulário completo (o doc estava atrás do
código), §8 recibo (`cmd_match`), §perfil (`verifications`, `commands`, `habits_ignore`,
`update_channel`). API_SPEC.md: `intent`, `verify`, `delegation`, flags novas de `order`,
`outcome`, `upgrade`, hooks novos. README: seção "prova, não palavra". CHANGELOG 1.14.0.
