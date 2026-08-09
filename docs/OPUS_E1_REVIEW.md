# OPUS_E1_REVIEW.md — Revisão técnica do E1 (Maestro)

**Revisor:** Opus 5 | **Data:** 2026-08-09 | **Escopo:** E1 (S-101, S-102, S-103)
**Base comparada:** PROJECT_BRIEF.md, ARCHITECTURE.md, DATA_MODEL.md, API_SPEC.md, ENGINEERING_SPEC.md, EPICS.md, CLAUDE.md
**Método:** leitura integral + execução da suíte + sondagens de falha + mutation testing dos testes e do `doctor` (tudo em cópias no scratchpad; **nenhum arquivo do projeto foi alterado**, exceto a criação deste relatório).

---

## 1. Veredito

O E1 está **bem construído para o tamanho que tem**. O que existe é coerente com a filosofia declarada (trilhos determinísticos, degradação sem bloqueio), as fronteiras do `CLAUDE.md` são respeitadas à risca, e os dois testes existentes são **genuínos** — mutei os hooks e eles pegaram a violação (evidência §6).

O problema não é o código escrito; é **o que o E1 afirma ter fechado e não fechou**:

- **Não há repositório git.** `git status` → `fatal: not a git repository`. O README manda `git clone`, o ENGINEERING_SPEC define rollback por `git checkout <tag>`, o brief lista "versionado em repo git próprio" como constraint. Nada disso existe.
- **O `doctor` diz "instalação saudável" para instalações quebradas.** É o único portão de validação do épico e produz falso-verde nos dois casos que a própria AC da S-103 exige detectar.
- **Nenhum hook chama `log_event` em runtime.** A `lib` de log é excelente e está morta: o E1 rodando em dogfood produz **zero** linhas de baseline.

Resumo por story:

| Story | AC declarada | Situação |
|---|---|---|
| S-101 | `/plugin` lista o Maestro; sessão nova carrega sem erro | **Parcial** — manifestos válidos, mas o caminho de instalação documentado (git clone) é inexecutável (P0-1) |
| S-102 | kill-switch curto-circuita todos os hooks, com teste | **Atendida** — verificada e mutation-tested (§6) |
| S-103 | `doctor` detecta hook não registrado e YAML inválido | **Não atendida** — não detecta nenhum dos dois (P0-2) |

---

## 2. Achados P0 — corrigir antes de qualquer dogfood

### P0-1 · Projeto sem controle de versão; caminho de instalação do README é inexecutável
**Arquivos:** raiz do repo, `README.md:8-13`

**Evidência:**
```
$ git status
fatal: not a git repository (or any of the parent directories): .git
```
`README.md:9` instrui `git clone <este-repo> ~/dev/maestro`. Não há `.git`, não há commit, não há tag, não há `.gitignore`.

**Impacto:**
1. O usuário que seguir o README não instala.
2. ENGINEERING_SPEC §CI/CD define *"Deploy = `git pull` no clone local; rollback = `git checkout <tag>`"* — sem git, **não existe rollback**. Numa camada cujo pior caso declarado (brief §8) é "hook mal configurado bloqueia trabalho", perder o rollback anula metade da mitigação (a outra metade, o kill-switch, funciona).
3. ENGINEERING_SPEC §Convenções exige conventional commits e "1 story por PR" — nenhum desses trilhos existe.
4. `agents/`, `src/`, `tests/fixtures/` estão **vazios** e `vendor/` não existe. Git não versiona diretório vazio: no primeiro commit+clone o layout do ENGINEERING_SPEC se desfaz silenciosamente.

**Correção:** `git init`, `.gitignore`, `.gitkeep` nos diretórios vazios, commit inicial, tag `v0.1.0`.

---

### P0-2 · `maestro doctor` reporta "saudável" em instalação quebrada (AC da S-103 não atendida)
**Arquivo:** `bin/maestro:18-53`

A S-103 pede literalmente: *"AC: detecta hook não registrado e YAML inválido"*. Não detecta nem um nem outro.

**Evidência A — YAML inválido passa.** Substituí `config/routing-table.yaml` por YAML sintaticamente quebrado numa cópia:
```
ok   routing-table.yaml presente
doctor: instalação saudável
```
`bin/maestro:39` faz apenas `test -f`. Não há parsing de YAML em lugar nenhum do CLI. API_SPEC §2 exige *"Valida: schemas YAML/JSON"*; DATA_MODEL §Regras de integridade exige *"`maestro doctor` valida schema do YAML e dos records"*.

**Evidência B — hooks desregistrados passam.** Substituí `hooks/hooks.json` por `{"hooks":{}}` (plugin instalado, nenhum hook ativo — exatamente o modo de falha da AC):
```
ok   hooks.json é JSON válido
doctor: instalação saudável
```
`bin/maestro:33` valida só que o arquivo é JSON. Não verifica que os eventos existem, que os `command` apontam para arquivos existentes, nem — como API_SPEC §2 pede — que os *"hooks [estão] registrados no settings do Claude Code"*. `grep -n settings bin/maestro` não retorna nada.

**Impacto:** o falso-verde é pior que a ausência do comando. O usuário roda `doctor`, vê verde, assume que o gate está ativo, e trabalha sem gate nenhum — sem sinal algum. Numa ferramenta cuja proposta é *garantir que a decisão aconteça*, "o verificador mente" é o pior modo de falha possível.

**Correção:** validar o YAML (via `bun`/parser real ou, no mínimo, checagem estrutural das chaves obrigatórias `version|gate|workflows|routes`), resolver cada `command` do `hooks.json` para arquivo existente e executável, checar o mapa de eventos contra os 3 esperados, e falhar com `exit 2`.

---

## 3. Achados P1 — corrigir antes do E2

### P1-1 · `log_event` mutila chaves e valores em silêncio; contrato do DATA_MODEL §4 não é representável
**Arquivo:** `hooks/lib/common.sh:43-45`

```bash
k=$(printf '%s' "$k" | tr -cd 'a-z_' | cut -c1-32)
v=$(printf '%s' "$v" | tr -cd 'A-Za-z0-9._/-' | cut -c1-80)
```

**Evidência:**
```
$ log_event decision Session_ID=abc file2=x agents=a,b,c reason="bug no login"
{"ts":"...","event":"decision","ession_":"abc","file":"x","agents":"abc","reason":"bugnologin"}
```
- `Session_ID` → `ession_` (maiúsculas removidas **do meio da string**, não rejeitadas)
- `file2` → `file` (dígitos removidos)
- `agents=a,b,c` → `abc` (vírgulas removidas — a lista some)
- `reason="bug no login"` → `bugnologin` (espaços removidos)

**Evidência de colisão — JSON com chave duplicada:**
```
$ log_event gate_block file2=aaa file3=bbb
{"ts":"...","event":"gate_block","file":"aaa","file":"bbb"}
$ jq -c .   →   {"ts":"...","event":"gate_block","file":"bbb"}   # aaa desaparece
```

A sanitização acerta o objetivo de segurança (nada de injeção — o teste de vocabulário prova isso) mas erra o modo de falha: **corrompe em vez de rejeitar**. Duas consequências concretas para o E2:
1. DATA_MODEL §4 especifica `"agents":["golang-pro"]` — um **array**. `log_event` só emite string, e a vírgula é apagada. O contrato do log não é implementável com a lib atual.
2. API_SPEC §2 define `--reason` truncado em **120** caracteres; `log_event` trunca em **80** e remove espaços. Duas verdades diferentes para o mesmo campo.

**Correção:** rejeitar par inválido (com aviso no stderr) em vez de reescrever; detectar chave duplicada; emitir `agents` como array; alinhar 120/80.

---

### P1-2 · `log_event` pode abortar o hook — viola a regra canônica "log nunca bloqueia operação"
**Arquivo:** `hooks/lib/common.sh:38-39,41-46`

A proteção `{ ... } 2>/dev/null || true` cobre **só** o bloco de escrita (linhas 48-55). Fora dela, sob o `set -euo pipefail` da linha 6, ficam `maestro_ensure_dirs` (protegida por `|| true`), o `ts=$(date -Iseconds)` e os pipelines de sanitização — **desprotegidos**.

**Evidência (simulando `date` indisponível/falhando):**
```
$ bash -c 'source hooks/lib/common.sh; date(){ return 1; }; log_event decision a=b; echo "SOBREVIVEU"'
rc=1        # "SOBREVIVEU" NÃO foi impresso — o shell inteiro morreu dentro de log_event
```

ENGINEERING_SPEC §Regras canônicas: *"Log nunca bloqueia operação — casa: `common.sh::log_event`"*. Hoje o log **é** capaz de derrubar o hook que o chama. No E1 isso é inócuo (nenhum hook chama `log_event`); no E2 todo hook chama. Consequência: `SessionStart` perde a injeção inteira; `PreToolUse` sai com rc=1 e polui a sessão com stderr.

Relacionado: `date -Iseconds` é GNU-only. O código demonstra intenção de portabilidade em `session-start.sh:14` (`stat -c %Y || stat -f %m`), mas `date` não tem fallback — em BSD/macOS todo `log_event` mata o hook.

**Correção:** envolver o corpo inteiro de `log_event` em `{ ... } || true` (ou `set +e` local) e dar fallback ao `date`.

---

### P1-3 · Denylist do gate não protege os componentes que **executam** o gate
**Arquivo:** `config/routing-table.yaml:4-8`

```yaml
allowlist:
  extensions: [.md, .txt, .yaml, .yml, .json, .toml]
  paths: [.maestro/, docs/, docs-ops/]
denylist:
  paths: [agents/, config/routing-table.yaml, .github/workflows/, .claude-plugin/]
```

ADR-003 v1.1 declara que a denylist protege *"o próprio Maestro (plugin, roster, routing table)"*. Faltam justamente os caminhos com poder de execução:

| Caminho | Ausente da denylist | Por que importa |
|---|---|---|
| `hooks/`, `hooks/lib/common.sh` | sim | **é o mecanismo de enforcement**. Um agente com decision record registrada pode reescrever o próprio gate. |
| `bin/` | sim | `maestro-decide` é quem grava o record que o gate confere. |
| `.claude/` | sim | ver abaixo — o buraco mais grave. |

**O buraco `.claude/`:** `.json` está na **allowlist de extensões** e `.claude/` não está na denylist. Pela lógica de API_SPEC §1 (denylist → allowlist → record), `.claude/settings.json` passa no passo 2 — **sem exigir decision record nenhum**. E `settings.json` é onde se (a) registram/desregistram hooks e (b) declara o bloco `env`. Um agente autônomo que grave `{"env":{"MAESTRO_OFF":"1"}}` desliga o Maestro inteiro, permanentemente, a partir da sessão seguinte — usando a via mais barata do gate.

Agrava: `session-start.sh:20` **anuncia o kill-switch ao modelo** em toda sessão (`"Kill-switch: MAESTRO_OFF=1"`). Contar ao agente qual é a saída de emergência e deixar a porta destrancada são erros independentes; juntos são um.

Observação secundária sobre a allowlist: `.json`/`.yaml`/`.toml` são amplos demais para "não-código" — cobrem `package.json` (campo `scripts`), `docker-compose.yml`, `pyproject.toml`, `tsconfig.json`. API_SPEC §1 chama o passo 2 de "allowlist de **não-código**"; essas extensões não satisfazem a descrição.

**Correção:** acrescentar `hooks/`, `bin/`, `.claude/` à denylist; estreitar a allowlist de extensões para `.md`/`.txt` e mover o resto para "exige record".

---

### P1-4 · `REPO_DIR` do CLI quebra quando `bin/maestro` é acessado por symlink
**Arquivo:** `bin/maestro:5`

```bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```
`dirname` não resolve symlink → `REPO_DIR` vira o diretório do link.

**Evidência:**
```
$ ln -s .../maestro-e1/bin/maestro ~/bin/maestro && maestro doctor
FAIL routing-table.yaml presente
maestro: env: doctor encontrou falhas
```
ADR-001 lista symlink como um dos dois métodos de instalação suportados, e pôr o CLI no `PATH` é pré-requisito para o E2 (a instrução canônica injetada manda o Claude chamar `maestro-decide`, o que exige `PATH`). No E2 isso deixa de ser um falso-FAIL do doctor e passa a ser "o CLI não acha a routing table para validar a decisão".

**Correção:** `readlink -f`/loop de resolução de symlink antes do `cd`.

---

### P1-5 · Nenhum hook produz log em runtime — o E1 em dogfood não gera baseline
**Arquivos:** `hooks/session-start.sh`, `hooks/pre-tool-gate.sh`, `hooks/user-prompt-submit.sh`

`grep -rn log_event hooks/` só casa com a definição em `lib/common.sh`. Nenhum dos três hooks chama a função; `pre-tool-gate.sh` e `user-prompt-submit.sh` são `source` + `killswitch` + `exit 0`.

Confronto com o roadmap (EPICS §Roadmap, Fase 1a): *"dogfood ativo: gate logando warns/decisões no dia a dia real"*. E com o brief §Baseline: *"o próprio hook do Maestro loga (JSONL local) cada roteamento automático vs. intervenção manual — o número sai de graça da operação"*. Hoje o número **não** sai: o `routing.jsonl` só é escrito por testes.

O `README.md:3-5` diz *"E1 completo … com ela já dá pra dogfood"*. Instalar dá; **medir não** — e medir é o produto.

**Correção barata e de alto retorno:** antecipar a S-205 (`user-prompt-submit.sh` logando `override_manual` com o nome do comando). São ~5 linhas, não dependem do gate nem do CLI, e **começam a relojoaria do baseline agora** — a métrica de sucesso nº 1 do brief (<20% de override) precisa de série histórica, e cada dia sem log é um dia de baseline perdido.

---

## 4. Achados P2 — higiene e divergências de contrato

| # | Arquivo / local | Achado |
|---|---|---|
| P2-1 | `hooks/lib/common.sh:48-55` | `exec 9>>` nunca é fechado: o **fd 9 vaza para todo processo filho** (verificado via `/proc/self/fd/9`) e o `flock` fica **retido até o fim do processo**, não até o fim da escrita. Com `flock -n` (sem retry), dois hooks concorrentes — o cenário normal de multi-subagente do E2 — perdem linha silenciosamente. Fix: `exec 9>&-` após o `printf`. |
| P2-2 | `hooks/lib/common.sh:44` | O sanitizador **preserva `/`**, então nada na lib impede logar caminho completo. A regra canônica *"nunca contém caminho completo"* é sustentada só por disciplina no call site — e o E2 vai manipular `tool_input.file_path`. Fix: remover `/` dos valores ou tipar por chave (`file_ext` aceita só `.[a-z]+`). |
| P2-3 | `session-start.sh:14` vs `DATA_MODEL:53-63` | O TTL é aplicado por **mtime**; o schema define o campo **`expires_at`**. Funciona hoje (verificado: record de 5h é removido, o de agora sobrevive), mas as duas fontes de verdade podem divergir quando o CLI do E2 reescrever records (idempotência atualiza mtime sem mexer em `expires_at`). |
| P2-4 | `ARCHITECTURE:79` / `API_SPEC:41` vs `bin/maestro:58` | Contrato ambíguo: os docs falam do executável `bin/maestro-decide`; o CLI implementa o subcomando `maestro decide`. Resolver antes de escrever a instrução canônica injetada no E2. |
| P2-5 | `DATA_MODEL:12-36` | A chave `gate:` (mode/allowlist/denylist) **não existe** no schema canônico do `routing-table.yaml`, embora API_SPEC §1 e ENGINEERING_SPEC §Regras canônicas a referenciem (`routing-table.yaml::gate.allowlist`) e o arquivo real a implemente. O `CLAUDE.md` declara o DATA_MODEL como dono dos schemas. |
| P2-6 | `bin/maestro:19,57` | `doctor --ci` é aceito e **silenciosamente ignorado** (`ci="${1:-}"` nunca é lido) — e ENGINEERING_SPEC §CI/CD depende dele. Verificado: `maestro doctor --ci` imprime a saída normal. |
| P2-7 | `bin/maestro:33-36` | Se `jq` faltar, as checagens reportam `FAIL hooks.json é JSON válido` / `FAIL plugin.json é JSON válido` — diagnóstico errado (o arquivo está ok; falta a dependência). Encadear condicionalmente ao check de `jq`. |
| P2-8 | `tests/run-all.sh:7` | A suíte roda `bin/maestro doctor` **sem** isolar `MAESTRO_HOME` → escreve em `~/.maestro` real. Os dois testes de hook isolam corretamente; o doctor não. |
| P2-9 | `tests/` | ENGINEERING_SPEC §Estratégia de testes especifica **bats**, e a tabela canônica cita `tests/hooks/injection-budget.bats`. Os testes são bash puro. Decisão legítima, mas não registrada no `docs-ops/decision-log.md` (que registra as outras: doctor em bash, sanitização por whitelist). |
| P2-10 | `tests/hooks/test-log-vocab.sh:6` | O teste faz `source common.sh`, herdando `set -euo pipefail` no próprio script de teste. Funciona hoje por acaso (as checagens estão em listas `&&`, onde errexit é suprimido); qualquer asserção nova em statement solto aborta o teste no meio e ele "passa" por saída precoce. |
| P2-11 | `hooks/*.sh:5` | Se `lib/common.sh` sumir, o `source` falha **antes** do kill-switch: `MAESTRO_OFF=1 ./pre-tool-gate.sh` → `rc=1` + stderr. Degrada sem bloquear (correto), mas o kill-switch não cobre o caso "a lib é o problema". |
| P2-12 | ausentes | `.github/workflows/` (CI exigida pelo ENGINEERING_SPEC — e já protegida por uma denylist que aponta para caminho inexistente), `.gitignore`, `LICENSE` (ADR-004 exige atribuição de licença nos agentes vendorizados no E3). |
| P2-13 | `session-start.sh:20` | O marcador injetado custa contexto em **toda** sessão de **todo** projeto sem entregar roteamento nenhum. Enquanto o E2 não chega, é imposto puro (~30 tokens/sessão) — e ainda divulga o kill-switch ao modelo (ver P1-3). |

---

## 5. Conformidade com as fronteiras invioláveis (`CLAUDE.md`)

Aqui o E1 vai **bem** e merece registro explícito:

| Fronteira | Situação | Evidência |
|---|---|---|
| `hooks/` = bash puro, nunca invoca Bun, nunca importa `src/` | ✅ | os 3 hooks só fazem `source lib/common.sh`; `src/` está vazio |
| Kill-switch na primeira linha de todo hook | ✅ | `maestro_killswitch` na linha 6 de cada hook, imediatamente após o `source` (necessário para a função existir) e **antes** de qualquer efeito colateral — inclusive antes do `maestro_ensure_dirs` |
| Logs: só metadados, jamais prompt | ✅ (por construção) | vocabulário fechado + sanitização; provado pelo teste adversarial |
| Logs: jamais caminho completo | ⚠️ | não violado hoje, mas não impedido pela lib — ver P2-2 |
| `agents/` = só markdown; `vendor/` read-only | ✅ (vacuamente) | ambos vazios/ausentes |
| Falha degrada, nunca bloqueia | ✅ **verificado** | com `MAESTRO_HOME` apontando para diretório read-only, os 3 hooks saem `rc=0` e o `session-start` ainda injeta seu bloco. Com o log file sendo um diretório, `log_event` sobrevive (`rc=0`) |
| Sem dependência de rede em runtime | ✅ | nenhuma chamada de rede em nenhum arquivo |
| Sem float em métrica de custo | ✅ | não há métrica de custo ainda |

**NFRs (ARCHITECTURE §NFRs) — medidos:**

| NFR | Alvo | Medido | Situação |
|---|---|---|---|
| Overhead do gate | < 50ms | **8 ms** | ✅ (com o hook inerte; remedir no E2 com jq + política) |
| Overhead de hook | < 100ms | 8-16 ms | ✅ |
| Injeção do SessionStart | ≤ 8.000 bytes | **125 bytes** | ✅ — mas **sem teste de regressão** (o `injection-budget` da tabela canônica não existe) |

---

## 6. Qualidade dos testes (mutation testing)

Rodei a suíte e depois mutei o código para verificar se os testes têm poder de detecção — a pergunta que importa num E1 de 2 testes.

**Suíte limpa:** 100% verde (2 testes de hook + 11 checagens do doctor).

**Mutação 1 — hook que loga antes do kill-switch** (`log_event` inserido acima de `maestro_killswitch` em `pre-tool-gate.sh`):
```
ok   pre-tool-gate silencioso com kill-switch     ← passou pela checagem de saída…
FAIL log escrito com kill-switch                  ← …mas a asserção de efeito colateral pegou
rc=1
```
O `test-killswitch.sh` é um teste **de verdade**: verifica exit code, ausência de saída **e** ausência de efeito no disco. É a peça mais forte do E1.

**Mutação 2 — remoção da sanitização:** o `test-log-vocab.sh` detecta por duas vias independentes (`grep 'rm -rf'` e `jq -e`). Também é um teste real.

**Lacunas de cobertura** (contra as 5 regras canônicas do ENGINEERING_SPEC):

| Regra canônica | Coberta? |
|---|---|
| Kill-switch é a primeira linha | ✅ |
| Log nunca bloqueia; nunca contém prompt/caminho | 🟡 parcial — "nunca contém prompt" ✅; "nunca bloqueia" ❌ (e P1-2 mostra que **falha**); "caminho completo" ❌ |
| Decision record por `session_id` | ❌ (E2) |
| Allowlist de não-código | ❌ (E2) |
| Injeção ≤ 2k tokens | ❌ — **testável hoje**, é a regressão mais barata de blindar |

Faltam ainda, todas testáveis no E1 sem escrever feature nova: degradação com `MAESTRO_HOME` inválido (sondei à mão, passa — merecia teste), caminho positivo dos hooks (só existe o teste com kill-switch **ligado**; ninguém verifica que o `session-start` injeta o bloco com ele desligado), limpeza de TTL (sondei à mão, funciona), e exit codes do CLI conforme API_SPEC §3.

---

## 7. Segurança

Superfície pequena e tratada com cuidado acima da média para um E1. O que encontrei:

**Bem resolvido:**
- Injeção de JSONL bloqueada por whitelist de caracteres, com teste adversarial (`.go"; rm -rf /` → `.gorm-rf/`, inerte). Foi a resposta correta ao achado 9 da review anterior.
- Vocabulário fechado de eventos rejeita evento arbitrário.
- `flock -n` não bloqueante: o log não pode travar o trabalho por contenção.
- Nenhum `eval`, nenhuma expansão não quotada em posição de comando, nenhum uso de `$(...)` sobre dados de stdin. `set -euo pipefail` em todos os scripts.
- Sem rede, sem segredos, sem dados de terceiros — coerente com o brief §7 e ADR-005.

**Riscos abertos:**
1. **Autoproteção incompleta + `.claude/settings.json` na allowlist** (P1-3) — o item mais sério. O gate do E2, com a config atual, permite desativar o próprio gate.
2. **Kill-switch divulgado ao modelo** em toda injeção (`session-start.sh:20`). Não é exploit sozinho (hooks herdam o env do Claude Code, não o de um `export` num Bash tool call), mas combinado com o item 1 vira caminho concreto.
3. **`MAESTRO_HOME` controlável por env** redireciona o destino de log/records. Risco baixo (quem controla o env já executa código), mas o `doctor` deveria ao menos reportar quando `MAESTRO_HOME ≠ ~/.maestro`.
4. **fd 9 herdado por processos filhos** (P2-1) — descritor de escrita no log vazando para tudo que o hook invocar.
5. **`/` preservado nos valores de log** (P2-2) — nada estrutural impede o vazamento de caminho que o brief §10 e o ENGINEERING_SPEC §Observabilidade proíbem.

Nenhum achado exige tratamento fora do fluxo normal: todos são de configuração/hardening, corrigíveis antes de o gate existir.

---

## 8. Prontidão para dogfood

**Instalável:** parcial — os manifestos (`plugin.json`, `marketplace.json`, `hooks/hooks.json` com `${CLAUDE_PLUGIN_ROOT}`) estão corretos e o `hooks/hooks.json` está no local de auto-descoberta esperado; mas o caminho documentado exige um repo git que não existe (P0-1). A AC da S-101 (*"`/plugin` lista o Maestro; sessão nova carrega sem erro"*) não foi verificável nesta revisão estática — precisa de um `/plugin install` real.

**Seguro de rodar:** sim. Os hooks são inertes, saem 0 sob toda falha que sondei, custam 8-16 ms e o kill-switch funciona e é testado. Não há como o E1 travar trabalho.

**Útil hoje:** não. Sem gate, sem injeção de routing table e sem log em runtime, o E1 instalado é um `echo` de 125 bytes por sessão. Isso é **legítimo** pela guarda de escopo do EPICS — a crítica não é ao escopo, é ao `README.md:3-5` vender "dá pra dogfood" quando o que dá é instalar.

**Mede alguma coisa:** não (P1-5) — e o E1 poderia medir, via S-205, por ~5 linhas.

Recomendação: **não promover a "dogfood ativo"** (Fase 1a do roadmap) enquanto P0-1, P0-2 e P1-5 não estiverem fechados. Com os três resolvidos, o E1 vira exatamente o que promete: fundação instalável, versionada, auditável e já acumulando baseline.

---

## 9. Top 5 correções antes do E2

**1. `git init` + `.gitignore` + `.gitkeep` + commit inicial + tag `v0.1.0`** — (P0-1)
Destrava o caminho de instalação do README, restaura o rollback do ENGINEERING_SPEC e impede que `agents/`/`src/`/`tests/fixtures/`/`vendor/` desapareçam no primeiro clone. Custo: minutos. É pré-requisito de tudo o mais.

**2. `doctor` que reprova instalação quebrada** — (P0-2, P1-4, P2-6, P2-7)
Validar schema do YAML; resolver cada `command` do `hooks.json` para arquivo existente e executável; conferir os 3 eventos esperados; implementar `--ci` de fato; `readlink -f` no `REPO_DIR`; não confundir "jq ausente" com "JSON inválido". Enquanto o `doctor` mentir, nenhum outro sinal do sistema é confiável.

**3. Blindar `log_event` antes que o E2 passe a usá-lo** — (P1-1, P1-2, P2-1, P2-2)
Quatro correções na mesma função: (a) rejeitar par inválido em vez de mutilar, e detectar chave duplicada; (b) envolver o corpo inteiro em `|| true` + fallback do `date`, para que o log **nunca** derrube o hook; (c) `exec 9>&-` após escrever; (d) remover `/` dos valores. Esta é a função mais crítica do repo — é a única que o E2 inteiro vai chamar em todo hook — e é a que tem mais defeitos latentes.

**4. Fechar a política do gate antes de o gate existir** — (P1-3)
Acrescentar `hooks/`, `bin/` e `.claude/` à denylist e estreitar a allowlist de extensões para não-código de verdade. Corrigir na config custa uma linha agora; corrigir depois que o `pre-tool-gate.sh` compilar a política é mudança de comportamento em produção. Reavaliar também se o marcador do `session-start` deve continuar anunciando `MAESTRO_OFF=1` ao modelo.

**5. Antecipar a S-205 e blindar as regressões testáveis hoje** — (P1-5, lacunas do §6)
`user-prompt-submit.sh` logando `override_manual` (~5 linhas, sem dependência de gate ou CLI) começa a acumular a série histórica da métrica nº 1 do brief **agora**; cada dia sem isso é baseline perdido. Junto: teste do orçamento de injeção (8.000 bytes), teste de degradação com `MAESTRO_HOME` inválido, teste do caminho positivo dos hooks, e isolar `MAESTRO_HOME` no `run-all.sh`.

---

## 10. Nota final

Ordenei os achados por risco, não por volume, e vale dizer o que os P0 não significam: os dois são lacunas de **ferramental de suporte** (versionamento e verificador), não defeitos do desenho. O núcleo — kill-switch, degradação, sanitização, fronteiras — está correto e, onde tem teste, tem teste que morde. O E1 errou em declarar-se completo, não em construir.

O maior risco estrutural para o E2 não está em nenhum achado isolado: é que a `lib/common.sh` seja a fundação de tudo o que vem (todo hook do E2 chama `log_event`) e ainda carregue P1-1 e P1-2. Corrigir agora custa uma tarde; corrigir depois custa reescrever o comportamento de cinco hooks em produção.
