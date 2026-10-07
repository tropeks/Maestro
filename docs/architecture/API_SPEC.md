---
covers:
  - bin/maestro
  - hooks/*.sh
reviewed: b13eed1
---
# API_SPEC.md
**Projeto:** Maestro | **Skill:** system-architect | **Versão:** 1.2 — 2026-09-05 (emendas E22/E23: hooks `pre-agent`/`subagent-stop`, `maestro intent`, `maestro verify`, `maestro delegation`, canal do `upgrade`)
**Consome:** ARCHITECTURE.md, DATA_MODEL.md | **Consumido por:** security-architect, vibe-code

> Sem HTTP. As "APIs" do Maestro são dois contratos: **CLI** (`maestro-decide` e utilitários)
> e **I/O de hooks** do Claude Code (stdin JSON / exit codes). Authz: N/A (ADR-005, local
> single-user). Rate limit: N/A.

---

## 1. Contrato de hooks (Claude Code)

Todos os hooks: primeira linha checa `MAESTRO_OFF=1` → exit 0 imediato (kill-switch).
Entrada: JSON no stdin (formato nativo do Claude Code). Saída: exit code + stdout/stderr.

### `hooks/session-start.sh` — evento SessionStart
- **Lê:** `$CLAUDE_PROJECT_DIR/.maestro.yaml` (se existir), `config/routing-table.yaml`, índice do roster.
- **Emite (stdout → contexto):** bloco `<maestro-routing>` com: **o `session_id` literal da sessão** (para o Claude passar ao CLI), tabela de rotas, heurísticas de execução, lista de agentes (nome + 1 linha + modelo), instrução canônica: *"antes de editar código, registre a decisão com `maestro-decide --session <id>`"*.
- **Também:** limpa decision records expirados (TTL 4h) e **recompila a política do gate** (`$MAESTRO_GATE_POLICY`, default `~/.maestro/gate-policy.sh`) a partir do YAML — fonte de verdade única.
- **Erros:** qualquer falha → exit 0 com stderr logado (degrada, nunca bloqueia sessão).
- **Orçamento:** saída ≤ **8.000 bytes** (proxy determinístico de ~2k tokens). Truncamento em ordem: heurísticas → índice do roster → nunca a instrução canônica nem o session_id.
- **Emenda E7 (S-707/S-709):** emite também `## Mote de execução` (`config/execution-ethos.md`) e `## Estilo de comunicação com o usuário` (`config/communication-style.md`) — teto de 2.000 bytes por arquivo; ausente → seção omitida em silêncio. No orçamento cedem ANTES de tudo, nesta ordem: estilo primeiro, mote depois — referência de comportamento, não instrução de ação.
- **Emenda E19 (S-1901):** ANTES de ler tabela e roster, `update_step` roda a checagem de
  atualização (`hooks/lib/update-check.sh`): `git fetch` com timeout (`MAESTRO_UPDATE_TIMEOUT`,
  5s) no máximo uma vez por intervalo, depois só git local. Estado `available` +
  `auto_upgrade` (default ligado) → `merge --ff-only` e **re-exec do hook novo** com
  `MAESTRO_UPDATE_REEXEC=1`, `MAESTRO_UPDATED_FROM/TO` e `CLAUDE_SESSION_ID` (o stdin já foi
  consumido) — a injeção sai inteira da versão nova, com a linha `atualizado agora: vX → vY`.
  Sem auto: linha `atualização: vX → vY (N commit(s) no origin) — maestro upgrade aplica`.
  Bloqueado (árvore suja/à frente/branch): linha nomeando a máquina de desenvolvimento.
  Rede falha, snooze vigente, em dia ou desligado: **nenhuma linha** — o estado fica em
  `$MAESTRO_HOME/update-state` (DATA_MODEL §10) e é o doctor que fala. A linha mora no
  cabeçalho (nunca trunca). Desliga com `MAESTRO_NO_UPDATE_CHECK=1` ou `update_check: false`.
  **S-1810 (v1.11.1):** dentro do intervalo, se HEAD e `origin/main` são os mesmos SHAs
  da última checagem `current`, o hook reaproveita o estado com dois `rev-parse`
  (`reason=fast-path`) — custo medido ~50ms sobre a sessão sem checagem (era ~150ms).
  Leitura de estado/config sem `sed`: lookups em bash puro.
  **S-1904 (v1.12.1):** o fetch leva `--tags` — máquina que só segue `main` recebe a tag
  da release junto, e o doctor compara o retrato com a tag certa.
  **S-2303 (E23c):** no canal `stable` (default) o candidato do ff-only é o commit da
  tag `stable`, não o topo do `origin/main`; sem a tag no remoto o estado é `no-stable`
  e a injeção diz `atualização: canal stable, e o origin ainda não tem a tag 'stable' —
  auto-update parado; maestro upgrade --channel main pega o topo` (auto-update parado
  é fato que a sessão precisa saber; silêncio seria a staleness muda do E19).
- **Emenda E22 (S-2203):** a seção `## Projeto` ganha a linha `direção:`, em três
  formas: `INTENT vN (.maestro/INTENT.md) → plano cita a seção da direção que serve` ·
  `INTENT sem carimbo → maestro intent --check` · `nenhuma → maestro intent --init
  (E22)`. Um awk sobre as 8 primeiras linhas do arquivo (só `version:`); nenhum sha256
  no hot path; ponteiro, nunca o conteúdo da direção. Ausência é FATO reportado, nunca
  silêncio. O texto do gate plan passa a cobrar "o plano cita a direção (INTENT vN,
  seção) — sem direção, diga que não há". Ratchet da injeção deliberadamente bumpado
  6930 → 7080 bytes. As frozen zones de ordens pendentes passam a ser lidas em 20
  linhas de cabeçalho (E22/S-2202), não 14.

- **Emenda E25 (S-2501/S-2502):** duas mudanças na injeção.
  (a) A instrução canônica ganha UMA linha ensinando o desfecho do descarte (`maestro
  outcome --session <id> killed --reason "…"`) — sem ela o verbo novo do CLI seria letra
  morta, porque o preâmbulo é o único lugar onde a sessão aprende o vocabulário.
  (b) `.maestro.yaml` passa a aceitar `preamble: full|standard|lean` (DATA_MODEL §2):
  `full` é o default e a ausência da chave produz saída **byte a byte idêntica** à de
  antes; `standard` omite `## Rotas`; `lean` omite também `## Heurísticas` e `## Roster`.
  O corte acontece ANTES do laço de orçamento (é escolha do projeto, não aperto de teto) e
  o cabeçalho — que nunca trunca — nomeia o tier e o que ficou de fora, com ponteiro para
  `config/routing-table.yaml` e `agents/`; valor fora do enum degrada para `full` e o diz.
  Ratchet da injeção bumpado deliberadamente por (a), no mesmo commit, conforme o
  protocolo no cabeçalho de `tests/hooks/test-injection-budget.sh`.

- **Emenda E26 (S-2601):** a política do gate passa a ser gravada em
  `${MAESTRO_GATE_POLICY:-$MAESTRO_HOME/gate-policy.sh}` — **o mesmo caminho que o
  `pre-tool-gate.sh` sempre leu**. Enquanto a escrita ignorava a variável, o arquivo era
  único e global: abrir sessão no projeto B sobrescrevia a política da sessão VIVA do
  projeto A (modo do gate, `MAESTRO_GATE_ORDER_FROZEN` da ordem em execução e
  `MAESTRO_PLUGIN_ROOT`), e A passava a ser policiada pelas regras de B, em silêncio. Sem
  a variável, caminho e conteúdo são byte a byte os de antes — nenhuma instalação muda de
  comportamento por atualizar. Valor aceito: caminho **absoluto, sem espaço nem quebra de
  linha**; torto degrada para o padrão com aviso no stderr. O diretório é criado se
  faltar; o temporário é irmão do destino (o `mv` atômico exige o mesmo sistema de
  arquivos). Motivação: mais de um gerente na mesma máquina, cada um com o seu escopo.

### `hooks/pre-tool-gate.sh` — evento PreToolUse, matcher `Edit|Write|MultiEdit`
- **Dependência declarada:** `jq` (parsing de stdin; validado pelo doctor). Fixtures adversariais em `tests/fixtures/`.
- **`post-edit-habits.sh` (E9, PostToolUse em Edit|Write|MultiEdit):** roda os habit
  sensors no arquivo editado e, com achado, emite `<maestro-habit>` (≤3 achados + ≤2
  guias capados em 700B) no stderr com exit 2 — feedback ao agente, NUNCA bloqueio
  (a edição já aconteceu). Cooldown de 15min por (arquivo, smell) em
  `$MAESTRO_HOME/sessions/`. Limpo/degradação → exit 0. Kill-switch idem aos demais.
- **Lê do stdin:** `tool_name`, `tool_input.file_path`, `session_id`.
- **Lógica:**
  1. **denylist por caminho** (repo do plugin, `agents/`, `config/routing-table.yaml`, `.github/workflows/`, configs executáveis) → block sempre (exit 2), mesmo com decisão registrada
  2. allowlist caminho+extensão de não-código (compilada de `routing-table.yaml::gate`) → exit 0
  3. existe `~/.maestro/sessions/<session_id>.json` válido e **não expirado (TTL 4h)** → exit 0 + log `gate_pass`
  4. senão → conforme `gate.mode` na config: **`warn`** (exit 0 + log `gate_warn` + mensagem) ou **`block`** (exit 2). Default inicial: `warn`; promoção a `block` após 1 semana de dados.
- **Latência:** < 50ms.

### `hooks/pre-bash-guard.sh` — autoproteção por Bash (ordem 047, v1.19+)
Além da guarda destrutiva (S-502: autônomo bloqueia, direto avisa), o guard bloqueia **sempre**
(exit 2, em qualquer modo, com record e com consent) o comando que ESCREVE em `self_paths`:
redirecionamento (`>` `>>` `&>` `>|`, heredoc incluso), `tee`, `sed -i`/`--in-place`, `cp`/
`install`/`ln` (destino, inclusive `-t`), `mv` e `truncate` (qualquer alvo), `dd of=`, e
`python`/`node`/`nodejs`/`ruby`/`perl` com caminho protegido em QUALQUER posição (não se separa
leitura de escrita dentro de um programa — falso positivo declarado). Caminho = relativo ao
`cwd`, absoluto ou `~`, normalizado (`.`/`..`), ancorado na raiz do plugin ou num worktree do
mesmo repo. Lista e raiz vêm de `$MAESTRO_GATE_POLICY` (`MAESTRO_GATE_DENY_SELF`,
`MAESTRO_PLUGIN_ROOT`); ausente ou parcial, vale o fallback embutido e a raiz do hook. Origem
de `cp`/`dd if=` fora de `self_paths` não bloqueia (ler é permitido). Mensagem aponta o molde do
patch (clone fora do repo → `docs/patches/NNN-*.patch` → `git apply` humano); `maestro consent`
não destrava. Módulo: `hooks/lib/self-paths.sh`. Teste: `tests/hooks/test-order-047-bash-self-paths.sh`.

### `mods/maestro-guard` — mod de política `tool.check` (ordem 072)
Plugin de mod do Claude Code (>= 2.1.287; escrito contra 2.1.293), no marketplace `maestro-managed` (`mods/.claude-plugin/marketplace.json`).
**Não é hook bash**: é TypeScript em `mods/`, sem importar `src/`, sem rede. Instalação como plugin da organização:
`tools/install-managed-mods.sh` (humano, `sudo`) + settings gerenciados; passo a passo em `docs/mods/INSTALACAO.md`.
- **Eventos.** `tool.check` (veredito `{decision, reason}`) e `tool.call` (segunda trava, só `{deny}`), para as ferramentas
  `Bash` (`input.command`), `Edit`/`Write`/`MultiEdit` (`input.file_path`), `NotebookEdit` (`input.notebook_path`) e `Read`/`Grep`/`Glob`
  (`input.file_path`, `input.path`, `input.glob`, `input.pattern`); `session.start` (`isInteractive`) só para saber se há humano.
  As demais ferramentas seguem direto para `next(e)`.
- **Vereditos.** `deny` (classe estrutural clara), `ask` (ambíguo) ou o que `next(e)` devolveu. **O mod nunca emite `allow`.**
  Decisão pura em `hooks/policy.ts` (`decide(tool, input, ctx)` → `deny | ask | pass` + `rule`).
- **Destrutivos** (`rm -rf` largo, `git push` force na main, `reset --hard` fora de worktree, `clean -fdx`, `DROP`/`TRUNCATE`/`DELETE` sem
  `WHERE`, `chmod -R`/`chown -R` largo, formatar disco): `deny` em **headless**; `ask` em **sessão interativa** (`isInteractive:true`).
  Sem o evento `session.start`, a sessão conta como headless.
- **Autoproteção** (`agents/ bin/ src/ hooks/ lib/ config/routing-table.yaml config/accept-proof.pub .claude-plugin/ mods/`, no checkout e
  em todo worktree): `deny` sempre; a exceção é o clone sandbox em `/tmp`. **Segredo** (`.env*` exceto `.example`/`.sample`/`.template`,
  `~/.ssh`, `~/.ponte`, `~/.claude/.credentials*`, `*.pem`/`*.pfx`/`*.p12`, e-CPF) em `Read`/`Grep`/`Glob` e `cat`/`less`/`head`/`tail`/`cp`
  (e afins) no Bash: `deny` sempre. `maestro order --accept` **não** é casado (o aceite é do Diretor).
- **Queda segura.** `throw`/`timeout`/evento malformado/comando gigante/bytes inválidos/aspas aninhadas não fechadas: `deny` (`.catch` em
  todo hook de bloqueio). Em sessão interativa a queda segue `deny`.
- **Log.** `~/.maestro/logs/guard-mod.jsonl` (`MAESTRO_HOME` respeitado), uma linha por veredito: `{ts, event:"guard_mod", rule, tool,
  verdict}`; **nunca** comando, caminho completo nem prompt. Últimas 1000 linhas.
- **Kill-switch.** `MAESTRO_OFF=1` lido uma vez no load por `$.env.get`; desliga o mod e grava `rule=kill-switch`.
- **`calls:` declarados** (`claude plugin validate`): `env.get`, `fs.exists`, `fs.read`, `fs.write` (só o log), `session.cwd`; **sem**
  `http.fetch`, `process.*`, `mcp.call`, `model.complete`.
- **Testes:** `claude plugin test mods/maestro-guard` (corpus em `tests/corpus.ts`; tabela caso × adaptador em `docs/mods/CASOS-ADAPTADOR.md`).
  `hooks/pre-bash-guard.sh` segue registrado até o patch de remoção (depois da janela da Fase 1).

### `hooks/pre-agent.sh` — evento PreToolUse, matcher `Agent|Task` (E23a/S-2301)
- **Lê:** os primeiros 4096 bytes do stdin. `session_id` por regex
  (`CLAUDE_SESSION_ID` como fallback) e `subagent_type` do payload
  (`"subagent_type":"([^"]{1,64})"`), sem o prefixo `maestro:`, aceito só se casar
  `^[a-z0-9-]+$`. O `prompt` e a `description` do Task **nunca** são lidos — nem para
  log, nem para decisão.
- **Emite:** `delegation phase=started session_id=<id> [agents=<agente>]`. Sem
  `session_id` tipado não há evento (o funil correlaciona por sessão; logar solto seria
  ruído).
- **Erros:** sempre exit 0 — observador, nunca gate. Kill-switch, stdin em
  tty/vazio/lixo, sessão fora do tipo, lib ausente: sem evento, sem ruído. Nada em
  stdout (stdout de PreToolUse é canal de decisão do Claude Code). Bash puro, sem jq,
  sem Bun, sem rede; NFR <100ms. Registrado em `hooks/hooks.json` com `timeout: 5`.
- **Degradação declarada:** prompt gigante pode empurrar o `subagent_type` para fora da
  janela de 4096 bytes — o evento sai sem `agents`, nunca com pedaço de texto.

### `hooks/subagent-stop.sh` — evento SubagentStop (E23a/S-2301)
- **Lê:** mesma janela e mesma extração de sessão; `agent_type` (ou `subagent_type`,
  por simetria com o PreToolUse) quando o payload traz. Nunca o transcript nem o
  resultado do subagente.
- **Emite:** `delegation phase=received session_id=<id> [agents=<agente>]`. Sempre exit
  0, nada em stdout, `timeout: 5` no `hooks.json`.
- **Doctor:** `check_hooks_registry` passa a exigir **7 eventos** (SessionStart,
  PreToolUse, UserPromptSubmit, PostToolUse, SessionEnd, SubagentStop, Stop) e os dois
  hooks novos entram na contagem de `commands` que precisam resolver para script
  executável.

### `hooks/user-prompt-submit.sh` — evento UserPromptSubmit (ADR-008)
- Prompt inicia com `/` → log `override_manual` com **apenas o nome do comando** (vocabulário fechado). Sempre exit 0; nunca altera o prompt.

### `hooks/session-end.sh` — evento SessionEnd (S-1811, v1.11.1)
- **Lê:** `session_id` do stdin (regex; `CLAUDE_SESSION_ID` como fallback) e o decision
  record `$MAESTRO_HOME/sessions/<id>.json`, só por presença: `workflow` presente →
  `decided=yes`; `outcome` ∈ accepted|rework|reverted|killed → `settled=yes` (**emenda
  E25/S-2501:** `killed` fecha a sessão como qualquer outro desfecho — decidir NÃO
  construir é decisão tomada, não decisão pendente).
- **Emite:** uma linha `session_end` no log com `session_id`, `decided`, `settled` — nada
  do record (brief, flags, reason) sai. Nada em stdout (`exec 1>&2`).
- **Erros:** sempre exit 0 — stdin vazio/lixo/id fora do tipo, kill-switch, lib ausente,
  home inescrevível: sem evento, sem ruído. Sem `jq`, sem Bun, sem rede.
- **Consumidor:** `maestro retro` imprime `sessões encerradas · sem decisão · decididas
  sem desfecho` (E18 fase 2: a variável que faltava para medir sessões sem `outcome`).
- **Emenda E20 (S-2001):** depois do evento, se a máquina optou (`telemetry_remote`),
  publica os `routing*.jsonl` no barramento (DATA_MODEL §11) via
  `hooks/lib/telemetry-sync.sh`: uma vez por intervalo, teto de tempo por operação de
  git (`MAESTRO_TELEMETRY_TIMEOUT`, 10s), lock não bloqueante, falha silenciosa e
  registrada em `telemetry-state`. Nunca muda o exit 0. `MAESTRO_NO_TELEMETRY=1` desliga.

### `maestro telemetry` (E20/S-2002)
- `--status` (default): estado legível a partir de `telemetry-state` ou "desligada". Exit 0
  (2 se o último push falhou).
- `--push`: publica agora (ignora o intervalo). Exit 0 publicou/sem novidade, 1 desligada,
  2 falhou.
- `--pull`: deixa o clone `~/.maestro/telemetry` em dia e lista os hosts. Exit 0/1/2.
- `--remote <url>`: grava `telemetry_remote` no config.yaml (liga); `--off` remove (desliga).
- `maestro retro --all`: pull + agrega os logs dos outros hosts (nunca o próprio, que já
  está local) e imprime `-- por máquina: <id> (<HOST>): N decisões · …`; desligada → avisa
  e segue só local. Sem `--all`, saída inalterada.
- Doctor: `check_telemetry` — sem remoto → ok "local"; último push falhou, ou sem push
  bem-sucedido há mais de 7 dias → warn com `maestro telemetry --push`. Envelope ganha
  `telemetry.{result,host}`.

### `hooks/gate-report.sh` — evento Stop (E21/S-2101, v1.13.0)
- **Só dentro do herdr** (`HERDR_ENV=1` + `HERDR_PANE_ID` tipado); fora, no-op absoluto.
- **Lê:** o decision record da sessão (regex, presença + enums). Gate pendente = workflow
  plan-gated (`feature`/`refactor`) SEM desfecho e com `approach: pendente` no brief →
  `plan`; `ship` sem desfecho → `ship`. Sem gate: apaga o arquivo do pane (resolvido por
  outro caminho) e sai. **Emenda E25/S-2501:** desfecho aqui inclui `killed`, e a guarda
  vale para os DOIS gates — matar uma feature antes do plano aprovado é o kill mais
  comum, e sem isso o herdr seguiria perguntando "Aprovo o plano?" (no telefone
  inclusive) sobre trabalho já descartado. A essência é extraída **ancorada ao campo
  `brief`**: o record tem outros campos de texto do diretor (`reason`, `kill_reason`) e
  um deles contendo a substring `essencia:` sairia da máquina pela ponte.
- **Escreve:** `$MAESTRO_HOME/herdr/gates/<pane>` (`:` vira `_`), chave=valor: `gate`,
  `session`, `project` (basename do projeto), `ts`, `message` — a pergunta regida em uma
  linha (`gate plan · <projeto> · <essência> — Aprovo o plano? (aprovo | ajusta: …)` /
  `gate ship · … — Shipo agora? (shipa | espera)`). Só a essência do brief sai; `reason`
  nunca.
- **Reporta (best-effort):** `herdr pane report-agent … --state blocked --message …`, 2s
  de teto. Para o Claude Code a autoridade de estado é a leitura de tela do herdr, então
  o report pode ser ignorado — o arquivo é o canal garantido; o forwarder (Legatus vNext)
  prefere o arquivo ao scrape da tela.
- **Resposta do humano:** `user-prompt-submit.sh` apaga o arquivo do pane e chama
  `pane release-agent` (mesmo teto). Sempre exit 0; nada em stdout (Stop hook com JSON no
  stdout vira decisão do Claude Code).

### `hooks/stop-turno.sh` — evento Stop (ordem 046, INTENT v6 Prioridade 3)
Segundo comando do Stop em `hooks/hooks.json` (`timeout: 5`), ao lado do `gate-report.sh`.
O critério de fim de turno é o **recibo VÁLIDO no tip** da ordem em curso — lido do
ledger pelo CLI (`maestro order --turno-check`), com a MESMA comparação de hash do
`order --status` (`maestro_tree_same`, ordem 044). O hook **nunca executa o `fim:` da
ordem**. Hook próprio, e não o `gate-report.sh`, por medição e por estrutura: o
`gate-report.sh` sai cedo fora do herdr (`HERDR_ENV`) e já está no teto de 400 linhas.

Fluxo (bash puro, sem jq): `MAESTRO_OFF=1` na 1ª linha → `stop_hook_active` libera →
sem `.maestro/orders` libera → branch lido do `.git/HEAD` por `read` (zero fork; worktree
segue o `gitdir:`) → ordem achada por glob `NNN-*.md` pelo número do branch → sem bloco
`## Turno` libera → rodada que termina com `[spock] aguardando:` libera (o gate-report
cuida) → **só então** chama `timeout 2 maestro order --turno-check` com o relatório da
rodada num arquivo temporário (teto `TURNO_TIMEOUT_S` = 2). `rc 1` do CLI vira
`{"decision":"block","reason":"…lista do que falta…"}` no stdout real; `rc 124` (timeout,
ordem 056) NÃO é silêncio: o hook confere localmente os 5 rótulos do relatório fixo, sem
chamar o CLI, registra `turno_timeout` e bloqueia com a lista dos que faltam (os 5 presentes,
ou mensagem ilegível, libera); QUALQUER outro resultado (0, erro, CLI ausente) libera,
exit 0, stdout vazio. O hook nunca prende: a reentrada (`stop_hook_active`) sempre libera.

**Orçamentos, medidos (forge, load 5,2/8 CPUs; N=31 e N=7):** caminho COMUM — sem ordem
em curso ou ordem sem bloco — mediana 18 ms (min 11, max 26), zero fork de `git`,
dentro do NFR de 50 ms; **Stop de turno** com ordem em curso — mediana 708 ms (min 571,
max 939), teto declarado **2 s** (uma vez por turno). Teste: `tests/hooks/test-order-046-stop-turno.sh`.

**Teto de bloqueios** (CLI, `lib/core-order-turno.sh`): no máximo o `teto:` da ordem,
limitado a 3 por sessão; contador em `$MAESTRO_HOME/turno/<sessão>-<ordem>`; atingido,
o CLI libera, imprime o aviso e registra `log_event turno_teto session_id n=<ordem>`.
Recibo válido zera o contador.

### `hooks/log-stop.sh` — evento Stop (opcional, v1.1)
- Fecha o ciclo no log (`event: session_end`), computa contagens da sessão.

## 2. Contrato do CLI

### `maestro-decide`
```
maestro-decide --session <session_id>          # OBRIGATÓRIO — valor injetado pelo SessionStart
               --workflow <fix|feature|refactor|ship|audit|custom>
               --mode <direct|subagent|multi>
               [--agents a,b,c] [--reason "..."]
               [--depth standard|deep|day-zero] [--profile prototipo|piloto|produto]
               [--brief "essencia: ...\nimpacto: ...\napproach: ..."]
               [--fronts "a/ b/;c/"] [--measures]
```
- Valida contra `routing-table.yaml` (workflow precisa existir; `mode≠direct` exige `--agents`; agentes precisam existir no roster). `--reason` truncado em **120 caracteres** com aviso (mitigação de vazamento de prompt).
- **E17/S-1701 — regência:** `--depth` default `standard`; `--profile` **obrigatório
  SSE `--depth day-zero`** (presente com outro `depth` é erro de validação). `--brief`
  exige os três marcadores `essencia:`/`impacto:`/`approach:` — cada um ≤200 chars
  (truncado com aviso, precedente `--reason`), soma ≤700; `approach: pendente` é aceito
  (o approach real chega depois via `maestro conduct`). **Recusa decide-time (exit 1):**
  quando o `--workflow` resolve para `gate: plan` na routing table (`feature`,
  `refactor`) e `--brief` está ausente ou incompleto — o CLI já parseia `gate` da
  routing table para esta checagem; o pre-tool-gate permanece workflow-agnóstico (NFR
  <50ms preservado, nenhuma leitura de routing table no hot path do gate). Verificação é
  **presença + formato**, nunca qualidade — greppável, não julgada. Limitação declarada:
  a allowlist do gate (`.md`, `docs/`) segue liberando edição sem decision record — sessão
  doc-only, inclusive `--depth day-zero`, não é bloqueada por brief ausente (DATA_MODEL §3
  v1.7).
  ```
  $ maestro-decide --session abc123 --workflow feature --mode subagent --agents dev-pleno
  maestro: validation: workflow 'feature' (gate: plan) exige --brief com essencia:/impacto:/approach: (fix: adicione --brief ou use --workflow fix/custom)
  $ maestro-decide --session abc123 --workflow feature --mode subagent --agents dev-pleno \
      --depth deep --brief $'essencia: gate de regência no decide\nimpacto: aprovador le 3 linhas, nao o diff\napproach: pendente'
  ok: record gravado (depth=deep, brief=3/3 marcadores, approach=pendente)
  ```
- **ordem 024 fatia 1 — H6, eixo ARQUIVO + eixo RECURSO (DATA_MODEL §3 v1.21):**
  `--fronts "a/ b/;c/"` só se aplica a `--mode multi` (frentes separadas por `;`,
  caminhos de cada frente separados por espaço; mínimo 2 frentes). **Recusa
  decide-time (exit 1):** sobreposição de PREFIXO de diretório entre DUAS
  frentes — a mensagem cita os dois caminhos e a frente de cada um. `--measures`
  marca esta frente como MEDIDORA (roda suíte/benchmark); com outra sessão VIVA
  e não expirada em `~/.maestro/sessions/*.json` (mesma fonte que o E26 já
  escopa), **avisa** (nunca recusa — Prioridades §1) que "frentes que MEDEM
  correm sozinhas" e segue gravando o record normalmente. A guarda do eixo
  RECURSO degrada em silêncio: sem `~/.maestro/sessions/`, JSON corrompido ou
  arquivo ilegível, ela não encontra nada e não avisa.
  ```
  $ maestro-decide --session s1 --workflow custom --mode multi --agents dev-pleno,qa \
      --fronts "a/ b/;a/sub/"
  maestro: validation: --fronts: 'a/' (frente 1) sobrepõe 'a/sub/' (frente 2) (fix: frentes paralelas exigem caminhos DISJUNTOS — duas frentes que tocam o mesmo diretório se destroem na CPU mesmo sem tocar o mesmo arquivo; separe os caminhos ou junte tudo numa frente só)
  $ maestro-decide --session s2 --workflow custom --mode direct --measures
  maestro: aviso: --measures: já existe outra sessão viva (não expirada) em ~/.maestro/sessions — frentes que MEDEM correm sozinhas; considere esperar a outra sessão encerrar ou tirar --measures desta frente
  decisão registrada: sessão=s2 workflow=custom mode=direct
  ```
- Grava decision record (com `expires_at` = ts+4h) + linha `decision` no JSONL via `JSON.stringify` (nunca concatenação manual). Idempotente por sessão — o re-decide preserva o `flags[]` existente do record anterior, fazendo merge mesmo quando workflow/mode mudam (S-1708).
- **Exit codes:** 0 ok · 1 validação (mensagem clara no stderr, inclui a recusa de brief plan-gated) · 2 ambiente quebrado (instrui `maestro doctor`).

### `maestro status`
- Mostra: decisão da sessão corrente, kill-switch, últimos 5 eventos do log.

### `maestro log [--summary]`
- `--summary`: agrega o JSONL → taxa de decisões automáticas vs. `override_manual`, distribuição de modelos por tarefa (o instrumento do baseline do brief).

### `maestro brief` (E8/S-801)
- Bash puro (sem Bun — o antídoto do cold start não pode depender de runtime).
- Sem flag: lê com veredito de freshness (`FRESCO`/`STALE — N commit(s)`/fora de
  git) e imprime a narrativa. Brief ausente é informativo, exit 0.
- `--write` (narrativa via stdin ou `--file`, teto de 64 KiB/65536 bytes — acima
  dele recusa com os três números e não grava nada, ordem 032) e `--auto` (esqueleto
  determinístico do git) carimbam ts/epoch/HEAD/wtree(S-701)/session e gravam
  atômico em `$MAESTRO_HOME/briefs/` (DATA_MODEL §7). `--path` só o caminho.
- Exit: 0 ok · 1 validação (narrativa vazia, flag/session malformada) · 2 ambiente.

### `maestro habits` (E9/S-903)
- Os mesmos sensores do hook pós-edição (motor único `hooks/lib/habit-sensors.awk`),
  sobre o diff vs HEAD + untracked (default), `--all` (repo inteiro, exige git) ou
  caminhos explícitos. Respeita `habits:` do `.maestro.yaml`.
- **Emenda E23d/S-2304:** no escopo `--all`/`--baseline`, respeita também
  `habits_ignore:` (prefixos relativos à raiz; default vazio). Caminho explícito não é
  filtrado — pedir por nome é decisão de quem pede. Quando algo é filtrado, a saída ganha
  `habits_ignore: N arquivo(s) fora do escopo (.maestro.yaml)` antes do veredito: filtro
  que esconde em silêncio é armadilha. O motor não emite achado em corpo de heredoc de
  arquivo shell — vale igual para o hook `post-edit-habits.sh`, que é o mesmo awk. O
  contrato de exit não muda (0 limpo · 1 achados · 2 ambiente).
- Achado sai como `arquivo:linha: smell — detalhe`, com os guias dos smells distintos
  ao final (sensor + guia, sempre juntos). Exit: 0 limpo · 1 achados · 2 ambiente.
- **S-905 (catraca):** `--baseline` grava `.maestro-habits.tsv` (smell → contagem,
  versionado no projeto). Com o arquivo presente, `--all` compara e **avisa** (ordem 062,
  decisão do Capitão de 04/10): smell acima do baseline sai como
  `AVISO catraca: slop acima do baseline — <smell: N > baseline M; …>` e a dívida declarada
  vencida como `AVISO catraca: dívida declarada VENCEU …`, ambos com **exit 0** — o aviso
  entra no relatório, não reprova a suíte nem o aceite (a catraca gerou 3 patches de puro
  retrabalho: 045, 050, 056). Igual passa; melhora imprime o convite a regravar. A
  detecção não muda: sem baseline (ou com escopo diff/caminho), smell continua exit 1.
  Escopos diff/caminho ignoram o baseline (a régua é do repo inteiro). Formato do
  `.maestro-habits.tsv` inalterado; o aceite, o `conform` e o `doctor` não leem o rc da catraca.

### `maestro consent` · `maestro outcome` · `maestro retro` (E10)
- `consent --grant <routing-table|roster|ops> [--ttl 1min–4h]` / `--revoke` / sem flag
  lista. `routing-table`/`roster` levantam a denylist do gate; `ops` (S-1006) rebaixa o
  BLOQUEIO do pre-bash-guard para aviso auditado quando TODAS as categorias são
  operacionais (privilege_escalation, container_destructive, kubectl_delete) — destruição
  de dados bloqueia integral mesmo com consent. hooks/bin/src jamais consentíveis
  (ADR-003 v1.2). Fail closed; auditado.
- `outcome --session <id> <accepted|rework|reverted> [--suite pass|fail] [--unproven]`
  — fecha a decisão com o desfecho (DATA_MODEL §3 v1.5). Exige record existente e `jq`.
  **Emenda E23a/S-2301:** `accepted` com record em `mode ∈ subagent|multi` exige ≥1
  `delegation phase=started` da sessão no log; sem ela, **exit 1** citando `maestro
  delegation --session <id>` e a alternativa `--unproven`, e o record não é tocado. Com
  prova, carimba `delegation_proof: started`; com `--unproven`, `none`. `mode: direct`
  não exige nada e não grava o campo.
  **Emenda E23b/S-2302:** `accepted` também recusa (exit 1, `sem verificação
  obrigatória: …` + o comando de cada rótulo faltante) quando o working tree contra
  `merge-base(main|master, HEAD)` toca área com verificação obrigatória sem recibo
  VÁLIDA. `--unproven` passa e grava `verifications: "missing"`; o caso normal com áreas
  exigidas grava `"cited"`; sem áreas exigidas o campo não existe. `rework`/`reverted`
  nunca são barrados — só o aceite afirma que a entrega serve. O aviso de honra do
  `--suite pass` continua para o rótulo `suite` quando ele não é exigido por área.
  **Emenda E25/S-2501:** o enum vira `accepted|rework|reverted|killed`. `killed` EXIGE
  `--reason "<por quê>"` (≤120 chars, truncado com aviso — precedente do `reason` do
  `decide`) e grava `kill_reason` no record (DATA_MODEL §3 v1.9); `--reason` com outro
  desfecho e `--suite` junto de `killed` são **exit 1**. `killed` não passa pelos gates de
  delegação e de verificação e não grava os campos deles — os dois existem porque o
  ACEITE afirma que a entrega serve, e no descarte não há entrega. Desfecho é last-wins,
  então gravar qualquer outro veredito sobre um record morto **apaga** `kill_reason`. O
  log recebe `outcome=killed` e **nunca** o texto do porquê. A saída aponta a seção `##
  Fora de escopo` do `.maestro/INTENT.md` (E22) como o lugar onde o kill sobrevive à
  sessão — aponta e não escreve: o INTENT é versionado e o hash do corpo é contrato.
- `retro [--days N]` — relatório determinístico de calibração (override rate, gates,
  smells, desfechos, workflows sem uso) + critério codificado de promoção warn→block.
  Consumidor: `/maestro:retro`, que propõe e (com consentimento) aplica diffs, com
  suíte + eval-on-diff como exame antes do commit.
  **Emenda E18/S-1801 (2026-09-01):** a linha de decisões sai como `override
  roteável: M · não-roteável: K`; a taxa, o sinal ≥20% e a promoção warn→block
  usam só M (comandos que casam com alvo `skill:` de binding ou nome de workflow,
  derivados da routing table; tabela ilegível degrada para a contagem antiga com
  aviso).
  **Emenda E25/S-2501 (2026-09-09):** o bloco `-- sinais:` ganha a leitura do descarte —
  com ≥1 `killed` na janela, quantos foram e onde eles sobrevivem (`## Fora de escopo` do
  INTENT); com ZERO e a janela já de calibração (≥14d, ≥10 decisões), o aviso de que nada
  foi descartado — ou o `interrogate` está aprovando tudo, ou o descarte não está sendo
  registrado. A linha `-- desfechos:` não muda: ela já agrupa por `.outcome` e passa a
  mostrar `killed: N` sozinha.


### `maestro docs` (E16)
- Veredito por doc canônico: FRESCO ou `STALE — N commit(s)` desde
  max(último commit no doc, `reviewed:`); quitação por emenda OU re-atestado.
  `--baseline`/`--check` = catraca (só drift novo reprova). Acusa ausente/sem
  covers/fan-out. Sensor `doc-governed` no habit hook faz o reforço tardio.

### `maestro order` (E15)
**Emenda E18/S-1802 (2026-09-01):** o label canônico de evidência é `order-<n>` SEM zeros (o nome do arquivo `NNN.md` é acolchoado, o label não); a sugestão no contrato da ordem é derivada da mesma fórmula do leitor, e o leitor tolera recibo gravado como `order-00n` — avalia ambos os candidatos até um provar.

- `--create --title t [--branch b] [--frozen "a/ b/"] [--budget-*] [--project d]`
  (corpo via stdin) · `--list` · `--status N` · `--accept N`. Estado derivado de
  git + ledger (§8) + aceite; `--accept` exige `provada` (exit 1 sem prova). O
  session-start compila frozen zones de ordens pendentes na política do gate:
  autônomo bloqueia na zona, direto avisa; aceite descongela.

**Emenda ordem 050 — `--validate N`.** Em projeto com `validation:` no `.maestro.yaml`, `maestro order
--validate N` grava o pedido de validação (fora da árvore) para a árvore provada de uma ordem `provada`
(→ `em_validacao`; idempotente em `em_validacao`/`validada`; exit 1 em `reprovada`, em ordem não provada e em
projeto sem `validation:`). Com `MAESTRO_ACCEPT_REQUIRE_VALIDATION` ligado, `--accept` exige `validada`
(exit 1 com a dica do próximo passo); desligado, comportamento anterior. Estados e recibo `validation-<n>`:
DATA_MODEL §9, emenda v1.25.

**Emenda E22/S-2202 (2026-09-05) — a ordem cita a direção.** `--create` carimba
`intent_version:`/`intent_hash:` quando há direção citável (DATA_MODEL §13) e anuncia
`direção: INTENT vN carimbada na ordem`; sem direção citável cria assim mesmo e imprime
`AVISO: ordem sem direção` com o comando que resolve (`maestro intent --init` quando não
há arquivo, `--check` quando há e está incompleto). O contrato gerado ganha a linha
"Direção vigente na criação: INTENT vN — o plano cita a seção da direção que autoriza
esta ordem". `--status N` mostra `direção : vN` e, se a direção subiu de versão,
`ATENÇÃO: a direção mudou (vA → vB) depois desta ordem — revise o plano contra
.maestro/INTENT.md`; mesma versão com conteúdo outro (edição sem bump) vira nota
apontando `maestro intent --bump`. `--list` marca `[direção mudou]` ao lado do status.
`--accept N` RECUSA (exit 1) sob direção desatualizada, ensinando `--intent-reviewed` —
aceitar sob direção nova é decisão NOVA do diretor, não repetição; com a flag, aceita
dizendo sob qual versão. Todo aceite (inclusive o re-aceite do S-1806) carimba
`accepted_intent: <vN>`. Ordem sem carimbo de direção nunca é acusada.

**Emenda E23b/S-2302 (2026-09-05) — o aceite exige a verificação da área.** `--accept N`
recusa (exit 1) quando o branch toca área com verificação obrigatória (`.maestro.yaml`,
DATA_MODEL §2) sem o conjunto exigido, listando `rótulo: NENHUMA|VENCIDA (motivo)` e o
comando que registra o recibo. Por rótulo: `exit=0`, `wtree_after` == árvore do tip do
branch e `cmd_match ≠ no`. `--status N` ganha `verif   : áreas <…>` e um estado por
rótulo exigido. Ordem que não toca área declarada segue na regra anterior.

**Emenda E23a/S-2301 (2026-09-05):** todo `--accept` emite também `delegation
phase=accepted` com `n` = id da ordem — a última fase do funil.

**Emenda (issue #6, 2026-09-12) — o carimbo do aceite não invalida o próprio
recibo.** `.maestro/` não entra no que a suíte prova — é estado de
governança. `bin/maestro-wtree` (DATA_MODEL §3 emenda v1.10) passa a excluir
`.maestro/**` do fingerprint em `git add -A`, então o `accepted_at`/
`accepted_session`/`accepted_tree` que este mesmo `--accept` grava em
`.maestro/orders/NNN.md` deixa de mover o `wtree_after` comparado na linha
339 e em `maestro evidence` (DATA_MODEL §8). Antes desta emenda, projeto que
rastreia `.maestro/` (E15/E22) via o próprio aceite vencer o recibo que o
autorizou — caso real: NetForge, ordem 016. Prova: `tests/cli/test-order.sh`,
falhando contra o `bin/maestro-wtree` anterior e passando com a exclusão.

**Emenda (ordem 036, DATA_MODEL §9 v1.22) — `work_project`: o trabalho mora em outro
repo.** `--create --title t ... --work-project <nome>` grava `work_project: <nome>` no
cabeçalho, validando NA HORA (recusa forma inválida, alvo que não resolve para repo git, ou
alvo == o próprio dono — três motivos, `exit 1`, nada gravado). `<nome>` é um DIRETÓRIO
irmão do projeto dono (`dirname(realpath(--project))/<nome>`) ou, com `MAESTRO_WORK_ROOT`
setado, `$MAESTRO_WORK_ROOT/<nome>` — nunca relativo ao `$PWD`. Com o campo presente:
- `--status N [--json]`/`--accept N`: o branch/tip/áreas tocadas (E23b) e o ledger de
  evidência passam a ser lidos do projeto do TRABALHO resolvido; o ARQUIVO da ordem, o
  carimbo de aceite, o registro terminal (`~/.maestro/order-state/`) e a citação de direção
  (E22) continuam SEMPRE no projeto DONO (`--project`). Forma inválida ou alvo que não
  resolve → `die validation` (rc 1) na fronteira de despacho, ANTES de qualquer emissão —
  `--status --json` nunca sai com JSON parcial. Alvo == o próprio dono é tratado como
  ausente, com uma nota `ATENÇÃO:` no boletim (é typo, não erro fatal fora do `--create`).
- `--list`: NUNCA morre por um `work_project` quebrado de uma ordem — marca `[?] work_project
  "<valor>": <motivo>` ao lado do estado e segue listando as demais.
- O rótulo do recibo ganha o candidato canônico `order-<n>-<dono8>` (`dono8` = 8 hex djb2 do
  `maestro_brief_file` do dono) na frente dos legados `order-<n>`/`order-<0NN>`; SEM tip de
  branch para ancorar (branch nunca criado ou já apagado), só o candidato namespeado vale —
  os legados ficariam ambíguos entre dois projetos com o mesmo id de ordem.
- A linha `prova :` do boletim, para ordem `provada`, passa a sair da PRÓPRIA derivação
  (`VÁLIDA no tip do branch — árvore <sha>, recibo <rótulo> exit 0`) em vez de perguntar a
  `maestro evidence` — vale para ordens single-repo também: lidas de um checkout fora do
  branch dela, a linha deixa de acusar `VENCIDA`. `maestro evidence --label X --project Y`
  isolado NÃO muda (issue #36 continua aberta).
- `--status N --json` ganha dois campos aditivos, sempre presentes, `null` quando não se
  aplica: `"work_project": "<nome>"`, `"work_project_dir": "<caminho resolvido>"`. `estado`
  não ganha valor novo (enum fechado de 6 valores, contrato do `RespostaSchema` do daemon).
- `MAESTRO_WORK_ROOT`: escape/hermeticidade da resolução (mesma técnica de `MAESTRO_HOME`/
  `MAESTRO_UPDATE_TIMEOUT`) — vence a resolução por diretório irmão quando setado.
- Ordem SEM `work_project`: comportamento idêntico ao de antes desta emenda, byte a byte
  (provado por golden — `tests/fixtures/order036-golden-*.sh` — contra as ~118 ordens reais
  desta máquina).

### `maestro order --turno-check` · `--turno-livre` (ordem 046)
```
maestro order --turno-check [--session <id>] [--report-file <arquivo>] [--project <dir>]
maestro order --turno-livre <N> [--session <id>] [--project <dir>]
```
`--turno-check` é o critério do Stop de turno. Resolve a ordem pelo `branch:` do HEAD do
projeto; **rc 0** libera (stdout vazio, ou o aviso de teto atingido) e **rc 1** bloqueia
com `falta: …` por linha: recibo `order-N` ausente (com o comando que o grava) ou VENCIDA, e
cada recibo de área exigido (`verifications:`) que não esteja VÁLIDA — o que `order --status`
já deriva. Com `--report-file`, lista também os rótulos do relatório fixo
(`feito` `provado` `aberto` `decisão` `próximo`) que faltam; **essa lista nunca bloqueia sozinha**.
Libera sem olhar o ledger: sem branch/ordem, ordem com `turno_livre:` ou sem bloco `## Turno`
válido (lacuna do `conform`, nunca trava o Stop). `--turno-livre` é a válvula escrita:
carimba `turno_livre:`/`turno_livre_session:` no cabeçalho da ordem e `order --status`
mostra `turno   : turno-livre`. `order --create` emite o esqueleto `## Turno` (placeholders
`<…>` contam como vazio) quando o corpo não traz um.

### `maestro intent` (E22/S-2201)
```
maestro intent [--show|--check|--init|--bump] [--project d] [--session s]
```
- `--init`: cria `<projeto>/.maestro/INTENT.md` (v1) com o template das seis seções
  VAZIAS e o carimbo `maestro-intent v1` (`version`/`ts`/`head`/`author_session`/`hash`).
  Recusa se já existe (exit 1). O template **não passa** no `--check` de propósito:
  título não é direção.
- `--show` (default): versão, `intent_hash`, carimbo (ts/head/sessão) e o estado de cada
  uma das seis seções (`N linha(s)` ou `VAZIA`), mais a nota "conteúdo editado desde o
  carimbo vN → maestro intent --bump" quando o hash do corpo difere do carimbado. Sem
  arquivo: `sem direção — maestro intent --init`, **exit 0** (trabalhar sem direção é
  legítimo; fingir que há direção não é). Carimbo ilegível: nomeia o defeito e sai 0.
- `--check`: valida carimbo + seis seções não-vazias e lista o que falta (`direção
  INCOMPLETA (N de 6 seções): falta …`). Exit 0 ok · 1 se falta qualquer coisa
  (inclusive arquivo ausente ou carimbo ilegível). Conteúdo editado sem bump é nota, não
  reprovação — quem decide versionar é gente.
- `--bump`: conteúdo mudado → `version+1` com `ts`/`head`/`author_session`/`hash` novos e
  o CORPO copiado byte a byte; conteúdo igual ao do carimbo → recusa (exit 1) explicando
  que a versão é o que as ordens citam. Bump com direção ainda incompleta passa,
  avisando, e diz que "ordens novas nascem citando vN; as antigas passam a pedir revisão
  do plano".
- Escrita atômica (`> tmp && mv -f`). Log: evento `intent` (`n=<versão>`, `via=manual`,
  `session_id` quando informado) só nas MUTAÇÕES (`--init`/`--bump`); leitura não loga.
- **Exit codes:** 0 ok · 1 validação (direção ausente no `--check`/`--bump`, `--init`
  sobre arquivo existente, `--bump` sem mudança, carimbo ilegível no `--bump`, flag
  desconhecida) · 2 ambiente quebrado (não consigo gravar).

### `maestro verify` (E23b/S-2302)
```
maestro verify [--base REF] [--project P] [--check]
```
- Cruza o diff contra a base (default `merge-base main HEAD`, depois `master`; sem git
  ou sem ancestral → "base: nenhuma", comparando só o working tree) com o bloco
  `verifications:` do `.maestro.yaml` e imprime: a base, as áreas tocadas e, por rótulo
  exigido, a linha do `evidence` (VÁLIDA/VENCIDA/NENHUMA nomeando o motivo e o comando
  que registra o recibo — com `commands.<rótulo>` declarado, o comando REAL, não um
  placeholder).
- Projeto sem `verifications:` → uma linha dizendo isso, exit 0 (o Maestro não inventa
  dever para quem não o declarou). Nenhuma área tocada, ou área sem rótulo → idem.
- `--base` com ref inexistente → exit 1 (validação). Sem `--check` é relatório: exit 0
  mesmo faltando prova. `--check` → exit 1 se algum rótulo exigido não está VÁLIDA.
- Log: evento `verify` com `n = <faltantes>` (0 inclusive). Nunca rótulo, área ou
  caminho.

### `maestro conform --check` (E27/S-2701, ordem 042)
```
maestro conform --check [<dir>] [--json]
```
Determinístico, **sem LLM e sem rede**: lista o que falta para `<dir>` (default: toplevel
git do cwd) entrar no método e rodar headless. Seis famílias de lacuna, código estável:

| família | códigos |
|---|---|
| (a) INTENT | `intent-missing` · `intent-sections` · `intent-hash` |
| (b) `.maestro.yaml` | `yaml-missing` · `yaml-no-verifications` · `yaml-label-no-command` · `yaml-lab-unmarked` · `yaml-lab-only-area` |
| (c) frescor | `brief-missing` · `brief-stale` · `readme-stale` · `doc-stale` |
| (d) ordens | `order-no-headless` · `order-no-turno` · `order-no-relatorio` (ordem 046) |
| (e) daemon (ponte) | `ponte-unregistered` · `ponte-no-policy` · `ponte-unreadable` |
| (f) CLAUDE.md | `claude-md-missing` |

Regras por família em `docs/architecture/DATA_MODEL.md` §2 (`lab:`) e §13 (INTENT).
`intent-*` reusa `lib/core-intent.sh` (`_intent_valid`/`_intent_missing`/
`_intent_body_hash`); `yaml-*` reusa `hooks/lib/verifications.sh`
(`maestro_verif_areas`/`maestro_verif_cmd`); `order-no-headless` reusa
`lib/core-order-state.sh` (`_order_status` — MESMA derivação de `order --status --json`;
terminal = `aceita`|`absorvida`, `adiada` conta como não-terminal); `ponte-*` lê
`~/.ponte/ponte.db` (override `MAESTRO_PONTE_DB`) **somente em `sqlite3 -readonly`** —
sem `sqlite3` ou banco ilegível é `ponte-unreadable`, nunca crash.

**Saída texto:** uma lacuna por linha, `<código>\t<alvo>\t<fix>` — alvo relativo ao
projeto, nunca caminho absoluto. Ordem estável: por família (a→f) e depois por alvo
(`LC_ALL=C`, byte a byte — não depende do locale do shell que roda o comando).

**`--json`:** `{"project":<basename>,"conforme":bool,"lacunas":[{"codigo","familia","alvo","fix"}]}`,
mesmas lacunas e mesma ordem do texto; escapado com o mesmo helper de
`lib/cmd-order-json.sh` (`_order_json_field`/`_order_json_esc`).

**Exit:** `0` só com zero lacunas (stdout vazio) · `1` com ≥1 lacuna · `2` uso (flag
desconhecida, `<dir>` inexistente, `--check` ausente).

**Família (d), ordem 046:** `order-no-turno` — ordem não terminal sem o bloco `## Turno`, ou
com `fatia`/`fim`/`teto`/`fora` ausente, vazio, ainda no placeholder `<…>` do esqueleto, ou
`teto:` que não é inteiro ≥ 1; `order-no-relatorio` — o rótulo `relatório:` do bloco ausente
ou vazio (o contrato do relatório de fim de turno não é citado). Terminal
(`aceita`|`absorvida`) fica fora, como no `order-no-headless`.

**Não escreve nada, em lugar nenhum** — nem no projeto, nem em `~/.maestro/`, nem no
`ponte.db`. Único rastro: `log_event conform n_lacunas=<n> familias=<lista|none>
rc=<0|1>` (DATA_MODEL §4, débito declarado — `hooks/` congelada nesta ordem).

### `maestro delegation` (E23a/S-2301)
```
maestro delegation --session <id> | --all
```
- `--session <id>`: imprime o funil da sessão — `planned` / `started` / `received` /
  `accepted` — contado no `routing.jsonl` **e nos rotacionados** (`routing-*.jsonl`),
  cada linha nomeando quem a emite, mais um veredito: sem delegação registrada ·
  planejada e NÃO disparada · disparada sem retorno · delegação provada. Exit 0.
- `--all`: agrega por sessão as **últimas 20 sessões vistas** no log (ordem de primeira
  aparição), uma tabela por sessão. Exit 0.
- Sem `--session` nem `--all`, ou flag desconhecida: exit 1 com o uso.

### `maestro decide` — flags de orçamento (E14)
- `--max-steps N` (1–500) · `--max-min N` (1–1440) · `--max-cents N` (1–100000): caps
  inteiros gravados em `budget` (DATA_MODEL §3 v1.6). O gate avisa UMA vez por cap
  estourado (steps por contador próprio; minutes pelo ts do record) e NUNCA bloqueia;
  `status` exibe; `retro` conta `budget_warn` na janela.

### `maestro conduct` (E17/S-1702)
```
maestro conduct --session <session_id>
                [--flag "sev|decisao|tradeoff|mitigacao"]...   # repetível, append
                [--approach "..."]
```
- Verbo de MUTAÇÃO do decision record (precedente: mesmo padrão de `maestro outcome`,
  roda pós-decide). Exige record existente para a sessão — sem record, exit 1.
- `--flag`: quatro campos separados por `|`, na ordem `sev|decisao|tradeoff|mitigacao`.
  `sev ∈ {critical|high|medium|low}` (fora do enum → exit 1); `decisao`/`tradeoff`/
  `mitigacao` truncados em **120 caracteres** com aviso (mesmo teto do `reason`). Cada
  `--flag` é um append em `flags[]` (DATA_MODEL §3 v1.7) — nunca substitui as anteriores.
- `--approach`: substitui `brief.approach` do record (≤200 chars, truncado com aviso).
  É o único jeito de sair de `approach: pendente` — o `decide` não reescreve brief depois
  de gravado.
- **Regra de soberania:** flag que contesta decisão já coberta por um ADR existente é
  responsabilidade do DIRETOR fechar citando o ADR (`--flag "medium|...|...|fechado por
  ADR-003"`, por exemplo) — o CLI não interpreta o conteúdo da flag, só valida forma;
  a sessão nunca reabre uma decisão de ADR sozinha.
- Grava evento `conduct` no vocabulário fechado do log (chave `session_id`, jamais o
  texto de `--flag`/`--approach` — mesma fronteira do `reason` no §4 do DATA_MODEL).
- `maestro doctor` valida o schema de `flags[]` a cada rodada (sev fechado, campos sob
  teto) e emite **WARN** (nunca reprova) quando um record tem `outcome` (S-1001)
  registrado com `brief.approach` ainda `"pendente"` — desfecho fechado sem approach é
  partitura incompleta, não erro estrutural.
  ```
  $ maestro conduct --session abc123 --flag "high|cache local sem TTL|pode servir dado velho|TTL de 5min adicionado" --approach "cache com TTL curto; revisitar se latência subir"
  ok: 1 flag registrada (sev=high); approach atualizado
  $ maestro doctor
  ...
  warn: record abc123 tem outcome=accepted com brief.approach=pendente
  ```
- **Exit codes:** 0 ok · 1 validação (record ausente, sev fora do enum, sem `--flag`/
  `--approach`) · 2 ambiente quebrado.

### `maestro evidence` (E13)
- `--record [--label l] -- <cmd>`: roda o comando no projeto e grava o recibo
  (DATA_MODEL §8); o exit do CLI espelha o do comando. Leitura (default) imprime
  VÁLIDA/VENCIDA nomeando o motivo; `--check` sai 1 quando não-válida.
- **Emenda ordem 048 — chave do recibo por ordem.** `--record --label suite-N` grava o
  recibo da ordem N (não sobrescreve o de outra ordem); `suite-N` herda `commands.suite` para
  `cmd_match`. Leitores resolvem a chave certa: `order --status|--accept|--json` pela ordem
  (`suite-N`, senão `suite`), `evidence [--check]`/`outcome --suite`/`verify` pelo número do
  branch atual (`order/NNN-…` → `suite-NNN`, senão `suite`). `suite` sem sufixo segue lido
  como fallback e na `main`. Formato do recibo inalterado. A resolução por branch só vale em
  `order/NNN-…` (`fix/2fa-login`, `release/1.20.0` leem `suite`); na `main`, `outcome --suite`
  resolve SÓ `suite`. A dica de regravação (`evidence` VENCIDA, recusa do aceite) nomeia `suite-N`
  quando o recibo da ordem existe — regravar pela dica fecha o ciclo VENCIDA→VÁLIDA.
- Consumidor: `outcome --suite pass` cita evidência válida ou avisa "palavra de honra"
  (`suite_evidence` no record). Live-dispatch E2E em `tests/e2e/` (tier manual/pago).
- **Emenda E23b/S-2302 — o recibo casa o comando.** `--record` grava
  `cmd_match=yes|no|free` (DATA_MODEL §8) e, quando o comando não é o declarado em
  `commands.<rótulo>`, avisa na hora que "este recibo NÃO conta como verificação" — o
  exit do CLI continua sendo o do comando. A leitura reprova `cmd_match=no` ("comando
  diferente do declarado em .maestro.yaml") e `cmd_hash` divergente do sha16 do comando
  declarado hoje; com declaração, a linha de VENCIDA traz o comando exato para regravar.
  Recibo anterior ao E23b (sem a linha) é lido como `free`.
- **ordem 024 fatia 1 — aviso ANTES de medir.** `--record` mede `load1m_x100`/
  `ncpu` (mesma sonda da issue #11/ordem 005, `lib/cmd-evidence.sh`) ANTES de
  rodar o comando; se a carga já está fora do `load_limiar`
  (`MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100`, default 200 = load 2,0), imprime
  `ATENÇÃO: carga já fora do limiar de medição ANTES de medir` na hora,
  citando load medido e limiar. Sem isto, "fora do limiar" só aparecia DEPOIS
  do recibo gravado — minutos de suíte gastos para um resultado que já se
  sabia inconclusivo antes de começar. Nenhuma sonda nova; nenhum campo novo
  no recibo (§8 intocado) — é só a MESMA leitura, dita mais cedo. O exit do
  CLI continua sendo o do comando medido; o aviso nunca muda o veredito.
- **Emenda ordem 060 — veredito único da prova.** `maestro_proof_verdict <recibo> <proj>
  <rótulo> [árvore_agora]` (`lib/core-proof-verdict.sh`) devolve os **motivos**
  (vazio = VÁLIDO; rc 2 = recibo ilegível) e é a ÚNICA regra de validade: `evidence --check`
  (árvore agora = conteúdo atual do projeto), `order --status|--json` (`_order_evidence_match`,
  árvore agora = tip do branch) e `order --accept` (`_order_verif_report`/`_order_verif_gate`,
  idem) a chamam e não mantêm critério próprio. Motivos, nesta ordem: árvore mudou durante a
  corrida (`wtree_before ≠ wtree_after`) · sem git para comparar · conteúdo mudou desde a prova (`maestro_tree_same`, ordem 044) · exit ≠ 0
  · `cmd_match=no` ou `cmd_hash` ≠ `commands.<rótulo>`. Carga e medições inconclusivas continuam
  só qualificador do texto (ordem 055), fora do veredito. **Idade é informação, nunca veredito:**
  `evidence --check` a imprime ("exit 0 há Nmin") sem reprovar, e recibo velho de conteúdo idêntico
  ao tip é VÁLIDO nos três leitores (única mudança de texto: o recibo que só estava VENCIDO por
  idade passa a VÁLIDO; `MAESTRO_EVIDENCE_MAX_AGE` deixa de decidir). Formato do recibo inalterado; o `--status`/`--accept` passam a nomear os motivos (`VENCIDA
  (…)`). Ordem já `aceita` deriva do registro, não do recibo: não reabre. Recibo de ordem cujo
  branch foi apagado (árvore congelada, ordem 017) segue sem tip e fora desta regra.
- **Emenda ordem 067 — o recibo grava regravações e custo.** `--record` grava, no fim do recibo
  (DATA_MODEL §8), `regravacoes` (0 na 1ª gravação da label, `anterior + 1` depois; recibo velho sem o
  campo vale uma gravação anterior), `tokens`, `custo_centavos` (inteiros, meio para cima, nunca float) e
  `custo_fonte`, lidos **só como inteiros** do transcrito do Claude Code
  (`$MAESTRO_CLAUDE_PROJECTS` ou `~/.claude/projects/<cwd>/<CLAUDE_CODE_SESSION_ID>.jsonl`; sem a sessão,
  só um transcrito único). Sem fonte: a palavra `ausente`, nunca `0` e nunca estimativa. A leitura é só
  leitura, sem rede, sem ponte.db, com piso de 50 MiB (`MAESTRO_EVIDENCE_TRANSCRIPT_MAX_BYTES`), e **nunca
  altera o exit nem imprime texto do transcrito**. Leitura do painel: `tools/baseline.sh` (seções 8, parcela
  `recibos_regravados`, e 9) soma só o campo inteiro, declara `n.antes`/`n.depois` (`populacao`, `n_com_dado`,
  `n_sem_dado`) e `n_com_dado`/`n_sem_dado` totais; `ausente` ou inexistente = sem dado (nunca zero nem
  FALHA; com `n_com_dado=0` a parcela sai `sem dado`, exit 0); FALHA só para ledger ilegível ou campo
  presente e inválido (float, texto que não seja `ausente`), exit 3.

### `maestro graph` (E11)
- Freshness do grafo graphify sem carimbo: mtime de `graphify-out/graph.json` vs último
  commit. `--check` sai 1 apenas em STALE (gatilho de `bin/maestro-graph-refresh`, a
  rotina de operador via crontab — único lugar onde `claude` headless é aceitável; hooks
  seguem sem rede). A injeção emite a linha `grafo:` na seção `## Projeto` só quando o
  grafo existe; STALE manda desconfiar, nunca consultar.

### `maestro upgrade` (E19/S-1902)
- `maestro upgrade`: fetch forçado (ignora o intervalo) e `merge --ff-only` para
  `origin/main`. Em dia → mensagem, exit 0. Bloqueado → explica o motivo (à frente:
  "máquina de desenvolvimento: git push, não pull"; suja; branch; merge em andamento),
  exit 1. Aplicou → evento `upgrade` (`via=manual`), imprime `vX → vY (N commit(s))`, o
  delta do `CHANGELOG.md` entre as duas versões, a linha de rollback, e faz `exec
  bin/maestro doctor --ci` no binário NOVO (só quando o clone atualizado é o próprio
  plugin). Falha de ambiente (não é clone git, sem `origin`, sem `origin/main` conhecido)
  → `die env`, exit 2.
- `--check [--force]`: só mede e imprime uma linha; nunca aplica. Exit 0 em dia/desligado,
  1 disponível/bloqueado, 2 falhou. Sem `--force` honra o intervalo (não vai à rede) e a
  linha DIZ isso: `em dia (vX) — cache do último fetch; --force consulta o origin`; fetch
  falho também é confessado na linha (v1.11.2, achado do Legatus: afirmação sobre o remoto
  sem consultar o remoto contrariava o princípio "silêncio nunca é atualizado"). No doctor,
  "último fetch há Nh" conta a partir de `fetched`, nunca de `checked`.
- `--rollback`: `git reset --keep <prev>` para o SHA gravado pelo último upgrade
  (recusa se perderia alteração local, e recusa — `diverged` — se houver commit local
  depois do upgrade: a ferramenta não desfaz trabalho de gente); evento `upgrade` com
  `via=rollback`; o estado gravado depois é o MEDIDO de novo; exit 1 sem upgrade
  registrado.
- Concorrência: o merge só acontece se o HEAD ainda é o que foi medido; outra sessão
  chegando antes devolve `raced` sem tocar o `prev` do rollback. `check_upstream` do
  doctor honra `MAESTRO_UPDATE_REPO` (a mesma costura da lib).
- `--snooze`: adia o aviso da versão remota atual (24h → 48h → 7 dias, escalonado por
  versão); não muda o estado.
- `--set chave=valor`: `update_check` (true|false), `auto_upgrade` (true|false),
  `update_interval_hours` (1..720) e `update_channel` (stable|main) em
  `$MAESTRO_HOME/config.yaml`.
- **Emenda E23c/S-2303 — canal.** `--channel stable|main` sobrepõe o canal **só nesta
  chamada** (via `MAESTRO_UPDATE_CHANNEL` no próprio processo; não escreve o
  `config.yaml` — para gravar, `--set update_channel=…`); valor fora do domínio → exit 1;
  combina com qualquer modo (`--check`, `--rollback`, `--snooze`, sem flag). Canal
  `stable` sem a tag no remoto: `maestro upgrade` e `--check` saem **0** com "canal
  stable: o origin ainda não tem a tag 'stable' — nada a aplicar (a CI a move quando
  shellcheck + suíte passam numa tag `v*`; `maestro upgrade --channel main` segue o topo
  da main)"; `--snooze` responde "nada a adiar". As linhas de estado nomeiam o canal:
  `atualização: em dia (vX, canal stable)`, `atualização: vX → vY disponível (N
  commit(s), canal stable) — maestro upgrade`, `Maestro vX → vY (N commit(s), canal
  stable)`; em dia sem flags, `já é a última versão (tag stable)`. Bloqueio por `ahead`
  no canal `stable` diz "à frente da tag stable (ainda não aprovados pela CI)" em vez de
  "push, não pull". O evento `upgrade` sai com `channel` nas três vias. Costura de teste
  nova: `MAESTRO_UPDATE_CHANNEL`.
- `update_check: false` e `MAESTRO_NO_UPDATE_CHECK=1` desligam só a checagem automática:
  o comando manual sempre roda (`UPD_MANUAL=1`). Costuras de teste: `MAESTRO_UPDATE_REPO`,
  `MAESTRO_UPDATE_REMOTE`, `MAESTRO_UPDATE_BRANCH`, `MAESTRO_UPDATE_INTERVAL`.

### `maestro doctor`
**Checagem S-1709 (E17):** `doctor` compara `meta.repository.revision` de `docs/assets/architecture.json` (quando o projeto o declara) com o commit da última tag git **ou com o pai dele** (rito desde a v1.14.2: o retrato é pinado no commit de release, commitado em seguida, e a tag vai no commit do diagrama — quem está exatamente na tag já tem o retrato certo) — divergência é warn acionável ("regenere com archify"), ausência é skip; nunca falha o doctor.

- Valida: schemas YAML/JSON, hooks registrados no settings do Claude Code, permissões, versão de Bun.
- **Emenda E7 (S-705/S-706):** grava o envelope `maestro.capabilities.v1` e o snapshot de
  resolução de bindings em `$MAESTRO_HOME` (DATA_MODEL §6); detecta
  `binding-resolution-drift` (aviso) e divergência do vendor/ contra
  `config/vendor.sha256` (falha de validação). `decide|status|log` sem Bun degradam
  citando o envelope ("último doctor: <ts>"; ≥24h = "envelope velho").
- **Emenda E7 (S-710):** compara a cópia do plugin registrada em
  `$MAESTRO_PLUGINS_DIR` (default `~/.claude/plugins`) com este repo e avisa
  `instalação do plugin` quando os arquivos de comportamento divergem — nunca falha; o
  fato vai ao envelope em `install.{registered,divergent,repo_is_live}`. A severidade segue
  quem executa: com marketplace `source: directory` apontando para o repo, a cópia em cache
  é inerte e a linha é `ok`.
- **Emenda S-2301 (E23a):** hooks esperados passam a ser **7** (SubagentStop).
- **Emenda S-2101 (v1.13.0):** hooks esperados passam a ser 6 (Stop).
- **Emenda S-1811 (v1.11.1):** hooks esperados passam a ser 5 (SessionEnd).
- **Emenda E9:** hooks esperados passam a ser 4 (PostToolUse do habit hook);
  todo sensor do motor precisa de guia em `config/habit-guides/` (`fail_val` sem).
- **Emenda E8:** valida cabeçalho e epoch de todo brief em `$MAESTRO_HOME/briefs/`
  (malformado é warn nomeando o arquivo); o SessionStart emite a seção `## Projeto`
  (ponteiro do brief + freshness barata por HEAD + `memória:` do
  `memory_container` + cobrança S-803) — nunca a narrativa, só a garantia.
- **Emenda E19 (S-1903):** `check_update_state` lê `$MAESTRO_HOME/update-state` — disponível
  → warn com `maestro upgrade`; falhou, ou último fetch bem-sucedido há mais de 7 dias →
  warn ("silêncio não é 'atualizado'"); bloqueado → ok nomeando a máquina de
  desenvolvimento; ausente → ok ("a primeira sessão verifica"). `check_upstream` (sem rede):
  commits à frente de `origin/main` sem push e `main` sem upstream viram warn. O envelope
  `capabilities.json` ganha `update.{result,local,remote}`. Nunca falha o doctor.
- **Emenda E23c (S-2303):** `check_update_state` aceita `result=no-stable` (**warn**,
  nunca fail — "auto-update parado", com o comando que ignora o canal; `check_upstream`
  também avisa quando o clone ainda não tem a tag) e nomeia o canal nas linhas de `available` e `current`;
  estado sem `channel` é lido como `main`. `check_upstream` abre com o canal e a posição
  do HEAD em relação à tag `stable` (exatamente na tag · N atrás · N à frente · divergiu
  · tag ainda não existe neste clone) e emite warn quando `update_channel` do
  `config.yaml` está fora do domínio — tudo sem rede. `check_release_diagram` passa a
  usar `describe --tags --abbrev=0 --match 'v*'`: `stable` é ponteiro de canal, não
  release, e sem o filtro sequestraria o retrato de arquitetura.

## 3. Envelope de erro (CLI)

stderr, uma linha, prefixo fixo: `maestro: <categoria>: <mensagem> (fix: <ação>)`
Categorias: `config`, `validation`, `env`. Nunca stack trace em uso normal (`--debug` habilita).

## Flags para o orchestrator

Nenhuma.
