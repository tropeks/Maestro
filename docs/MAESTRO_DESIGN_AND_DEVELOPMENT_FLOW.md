# Maestro — design, funções e fluxo de desenvolvimento

> Documento de reconhecimento técnico do repositório `tropeks/Maestro`.
> Base principal: código e documentação presentes no checkout em
> `/home/rcosta00/dev/Maestro`. As seções **Observado** descrevem contratos
> explícitos; as seções **Leitura de design** registram a interpretação útil para
> comparação com outros sistemas.

## 1. Resumo executivo

O Maestro é um plugin local para Claude Code que funciona como uma camada de
roteamento MoE (Mixture of Experts) e de política de desenvolvimento. Ele não é
o agente que decide tudo nem um servidor central: injeta contexto de roteamento,
registra a decisão da sessão, aplica gates determinísticos antes de operações
sensíveis e mede o resultado.

A tese central é **trilhos determinísticos, IA nas bordas**:

- hooks bash garantem **que** uma decisão, proteção ou registro aconteça;
- o Claude da sessão decide **o que** fazer, lendo a routing table injetada;
- agentes especializados executam partes do fluxo;
- o estado é local, baseado em arquivos versionados e JSON/JSONL;
- nenhum LLM fica no caminho crítico dos hooks;
- falhas do Maestro degradam para o fluxo manual, em vez de impedirem o trabalho.

O fluxo essencial é:

```text
SessionStart
  -> injeta projeto + rotas + bindings + gates + roster
  -> Claude interpreta a intenção e escolhe workflow/mode/agente
  -> maestro decide grava decision record por sessão
  -> PreToolUse valida edição e caminhos protegidos
  -> Task/subagente executa o step
  -> review/QA/ship conforme workflow
  -> log JSONL + summary medem decisões, overrides e gates
```

## 2. O que o Maestro faz e o que não faz

### Faz

1. Filtra e apresenta um roster de agentes proporcional ao tipo de tarefa.
2. Mapeia intenções naturais para workflows declarativos.
3. Separa o método de execução (`skill`, `native`) do executor (`agent`).
4. Exige um registro explícito da decisão antes de editar código.
5. Protege arquivos estruturais do próprio Maestro e configurações executáveis.
6. Guarda comandos destrutivos em fluxos autônomos.
7. Injeta gates humanos curtos para plano e publicação.
8. Mantém brief de continuidade por projeto, com freshness baseada em Git.
9. Expõe `doctor`, logs, status e envelopes de capacidades para diagnosticar drift.
10. Mede o quanto o roteamento automático é substituído por comandos manuais.

### Não faz

- não é um servidor HTTP nem possui banco de dados;
- não classifica a intenção com um segundo LLM;
- não escolhe agentes por regex automática: o Claude da sessão interpreta a tabela;
- não é uma sandbox de segurança completa;
- não garante captura de toda edição feita por Bash (`tee`, redirecionamento,
  `git apply` etc.);
- não tem multi-tenancy ou autorização própria: é single-user/local;
- não deve editar `vendor/` nem reescrever suas próprias regras estruturais;
- não substitui Claude Code, superpowers ou gstack; faz curadoria e roteamento.

## 3. Arquitetura e fronteiras

### 3.1 Componentes

| Componente | Responsabilidade | Fonte |
|---|---|---|
| `hooks/session-start.sh` | preparar o contexto da sessão, compilar política e limpar estado expirado | `hooks/session-start.sh` |
| `hooks/pre-tool-gate.sh` | gate para `Edit`, `Write` e `MultiEdit` | `hooks/pre-tool-gate.sh` |
| `hooks/pre-bash-guard.sh` | proteção de comandos destrutivos em `Bash` | `hooks/pre-bash-guard.sh` |
| `hooks/user-prompt-submit.sh` | medir override manual sem registrar prompt | `hooks/user-prompt-submit.sh` |
| `hooks/lib/common.sh` | kill-switch, caminhos, timestamps, log e validação de records | `hooks/lib/common.sh` |
| `bin/maestro` | wrapper operacional; resolve ambiente e delega ao CLI Bun quando possível | `bin/maestro` |
| `src/cli.ts` | `decide`, `status`, `log` e funções de estado/validação | `src/cli.ts` |
| `config/routing-table.yaml` | workflows, bindings, rotas, heurísticas e política de gate | `config/routing-table.yaml` |
| `agents/*.md` | roster declarativo com frontmatter de modelo e ferramentas | `agents/` |
| `vendor/` | prompts upstream pinados, somente referência | `vendor/` |
| `tests/` | testes de hooks, CLI, fixtures adversariais e evals | `tests/` |

### 3.2 Fronteiras invioláveis

- Hooks são bash puro: não importam `src/`, não invocam Bun e não fazem rede.
- A primeira ação efetiva de cada hook é `maestro_killswitch`.
- `MAESTRO_OFF=1` desliga todos os hooks com `exit 0`.
- Logs carregam somente metadados com vocabulário fechado; nunca prompt ou
  caminho completo de arquivo.
- `agents/` contém markdown, não lógica executável.
- `vendor/` é read-only e sua integridade é comparada com
  `config/vendor.sha256` pelo `doctor`.
- Falha de componente normalmente significa fluxo manual, não bloqueio global.
- Métricas de custo usam inteiros de tokens/centavos, não float.

### 3.3 Caminho de dados

```text
config/routing-table.yaml + .maestro.yaml + agents/*.md
                 |
                 v
        session-start.sh
          |          |
          |          +--> ~/.maestro/gate-policy.sh
          +--------------> stdout: <maestro-routing>
                 |
                 v
          Claude Code interpreta
                 |
                 +--> maestro decide --> ~/.maestro/sessions/<sid>.json
                 |                         + routing.jsonl
                 v
       pre-tool-gate / pre-bash-guard
                 |
                 +--> allow / warn / block
                 +--> metadados em routing.jsonl
```

## 4. SessionStart: o bootstrap da sessão

`hooks/session-start.sh` é o ponto de entrada de contexto. Ele:

1. lê o `session_id` do JSON do Claude Code, usando regex bash e `jq` como
   reforço, com fallback para `CLAUDE_SESSION_ID`;
2. lê a routing table por um parser restrito em `awk`/bash;
3. valida tokens antes de colocá-los na injeção ou na policy;
4. lê o `.maestro.yaml` do projeto, se existir;
5. filtra o roster conforme `experts:`;
6. compila `$MAESTRO_HOME/gate-policy.sh`;
7. remove decision records expirados e pode rotacionar o log;
8. emite `<maestro-routing>` com session id, rotas, heurísticas, bindings,
   gates humanos, profile, brief e roster;
9. respeita teto de injeção de 8.000 bytes, truncando primeiro material de
   referência e preservando session id, bindings, gates e instrução canônica.

A ausência de profile não é erro. `experts` ausente significa roster global;
`experts: []` é uma escolha explícita de nenhum especialista; nomes inexistentes
são ignorados com aviso; se todos forem inválidos, volta ao roster completo para
não deixar a sessão sem contexto.

O brief não injeta a narrativa inteira: injeta um ponteiro e um veredito de
freshness. Assim, a IA escreve o estado, mas o hook garante que ele existe e que
o Git seja consultado antes de uma nova varredura cara.

## 5. Gate estrutural de edição

### 5.1 `pre-tool-gate.sh`

O hook é registrado para `Edit|Write|MultiEdit`. A ordem normativa é:

1. kill-switch;
2. leitura de `tool_name`, `tool_input.file_path` e `session_id`;
3. denylist de caminhos: bloqueia sempre, mesmo com decision record;
4. allowlist de arquivos não-código: permite sem decision record;
5. decision record válido e não expirado: permite e registra `gate_pass`;
6. sem record: `warn` (padrão atual) ou `block`, conforme política.

A política atual (`config/routing-table.yaml`) permite `.md`, `.txt`, `.maestro/`
e `docs/` sem decisão. Protege universalmente `.claude/` e
`.github/workflows/`; na raiz do plugin protege `agents/`, `bin/`, `src/`,
`hooks/`, `config/routing-table.yaml` e `.claude-plugin/`.

A normalização de caminho é léxica, sem `realpath`, para manter latência baixa.
Caminhos patológicos muito longos com `..` recebem checagem conservadora de
negação. O caminho completo nunca entra no log; somente a extensão.

### 5.2 Warn versus block

O modo inicial é `warn`. Isso é deliberado: primeiro mede falsos positivos,
escapes e taxa de override no dogfood; só depois promove a política para
`block`. A promoção deve ser baseada em evidência, não em preferência.

O gate é **anti-descuido/best-effort**, não uma fronteira de segurança absoluta.
Bash pode escapar do gate estrutural; por isso existe uma guarda separada.

## 6. Guarda destrutiva de Bash

`hooks/pre-bash-guard.sh` é associado ao matcher `Bash`. Ele existe justamente
porque `pre-tool-gate.sh` não intercepta comandos shell.

Fluxo:

1. verifica `MAESTRO_OFF` e depois `MAESTRO_GUARD_OFF`;
2. lê ferramenta, sessão, cwd e comando com `jq`;
3. limita tamanho do comando;
4. remove ofuscação barata: continuidades, aspas, escapes e separadores;
5. preserva corpo de heredoc que esteja apenas sendo escrito para arquivo;
6. divide por `;`, `&&`, `||`, `|`, `&`, command substitution e backticks;
7. classifica pelo verbo no início do segmento, evitando falso positivo em
   `echo "cuidado com rm -rf /"`;
8. avalia alvo de `rm` conservadoramente;
9. em decisão `subagent`/`multi`, bloqueia risco detectado;
10. em modo `direct` ou sem record, avisa e deixa passar para não travar o humano.

Categorias incluem pipe remoto para shell, escrita em dispositivo de bloco,
remoção perigosa, force push, operações destrutivas de banco e comandos
semelhantes. O comando nunca é logado; somente a categoria fechada do risco.
`MAESTRO_GUARD_OFF=1` desliga somente esta guarda.

Limitação importante: isto não é sandbox nem análise adversarial completa. É uma
política determinística para reduzir ações destrutivas acidentais em fluxos
autônomos, mantendo o caminho direto utilizável.

## 7. Override manual e observabilidade

`hooks/user-prompt-submit.sh` detecta prompt iniciado por `/`, interpreta isso
como invocação manual de workflow e registra `override_manual` com somente o
nome do comando. O stdout é redirecionado para stderr porque stdout seria
injetado no contexto do Claude.

O `routing.jsonl` aceita vocabulário fechado:

```text
decision, gate_pass, gate_warn, gate_block,
override_manual, killswitch, session_end
```

`common.sh::log_event` valida evento, chave e valor, rejeita `/`, usa
serialização segura e tenta `flock -n`. Falha de log nunca falha a operação.
O arquivo gira por tamanho/tempo.

`maestro log --summary` transforma o log em instrumento de gestão:

- decisões automáticas versus overrides;
- distribuição de workflows, modos e modelos/agentes;
- passes, warns e blocks;
- contagem derivada de edições por decision record.

A métrica principal é a proporção de tarefas que não precisaram de override
manual. Isso permite calibrar a routing table com uso real.

## 8. Decision record e CLI

O registro fica em `~/.maestro/sessions/<session_id>.json` e é efêmero. Campos
principais:

```json
{
  "session_id": "abc123",
  "ts": "2026-08-08T21:03:11-03:00",
  "expires_at": "2026-08-09T01:03:11-03:00",
  "workflow": "fix",
  "mode": "subagent",
  "agents": ["golang-pro"],
  "reason": "bug em código Go, 1 módulo",
  "wtree": "<opcional, fingerprint de conteúdo>"
}
```

O TTL padrão é quatro horas. O `session_id` impede que uma decisão antiga
libere indefinidamente novas sessões. `wtree`, quando disponível, denuncia que o
conteúdo do working tree mudou mesmo que o HEAD não tenha mudado.

### Comandos

- `maestro decide`: valida workflow, mode e agentes; exige agentes quando o
  modo não é `direct`; limita `reason`; grava record e evento `decision`.
- `maestro status`: mostra decisão corrente, validade, kill-switch, freshness do
  wtree e eventos recentes.
- `maestro log --summary`: agrega o log para medição.
- `maestro brief`: lê, cria (`--write`), gera esqueleto Git (`--auto`) e mostra
  freshness de brief.
- `maestro doctor`: verifica ambiente, schemas, hooks registrados, permissões,
  skills, bindings, vendor, instalação do plugin, envelope e briefs.

Exit codes seguem o contrato: `0` sucesso, `1` validação/conteúdo inválido e
`2` ambiente quebrado. Erros usam envelope curto com categoria, mensagem e ação
corretiva. Quando Bun não está disponível, o wrapper cita o último envelope do
`doctor`, se houver, em vez de inventar um diagnóstico.

## 9. Routing table: workflow, binding e heurística

A routing table é YAML versionado. Na versão 2, `steps` são nomes abstratos e
`bindings` dizem o que executa cada step:

```yaml
workflows:
  feature: {steps: [plan, implement, review, qa], gate: plan}
bindings:
  plan: native:plan-mode
  implement: agent:dev-pleno
  review: [skill:requesting-code-review, agent:revisor]
  qa: [skill:gstack-qa, agent:qa]
```

Há três tipos de binding:

- `skill:<nome>`: método/procedimento disponível no ambiente;
- `agent:<nome>`: executor do roster versionado no plugin;
- `native:<nome>`: capacidade nativa, atualmente vocabulário fechado como
  `plan-mode`.

A ordem de dois alvos é semântica: primeiro o método, depois quem executa.
Assim o Maestro não mistura “como revisar” com “quem revisa”.

A heurística é outro eixo: escolhe modo, senioridade e especialista conforme
escopo, linguagem e risco. O binding `implement: agent:dev-pleno` é um default
residual; uma linguagem coberta por especialista o sobrepõe.

### Workflows observados

| Workflow | Steps | Gate |
|---|---|---|
| `fix` | investigate → implement → review | nenhum humano obrigatório |
| `feature` | plan → implement → review → qa | aprovação do plano |
| `refactor` | plan → implement → review | aprovação do plano |
| `ship` | ship | confirmação de publicação |
| `audit` | audit | nenhum gate humano declarado |
| `verify` | qa | nenhum |
| `codereview` | review | nenhum |
| `custom` | vazio | nenhum |

Rotas de intenção são âncoras semânticas lidas pelo Claude, não um classificador
por regex. Existem rotas para bug, feature, refactor, publicação, segurança,
verificação e code review.

## 10. Gates humanos

O gate humano não é outro hook: é uma instrução curta injetada a partir de
`workflows.*.gate`.

- `gate: plan`: entrar em plan mode, resumir o plano e perguntar se está aprovado;
- `gate: ship`: listar o que será publicado e pedir confirmação explícita.

A política de risco é assimétrica. Desenvolvimento privado verificado pode
seguir com commit, push em branch, PR e deploy de teste sem perguntar a cada
etapa. A confirmação humana fica reservada para quase irreversível:

- produção real com usuários ou dados;
- billing;
- auth e secrets;
- migração destrutiva;
- apagar dados/volumes;
- force push;
- decisões jurídicas ou externas de produto.

Isso reduz burocracia sem transformar o agente em autoridade silenciosa.

## 11. Roster e proporcionalidade de custo

Os agentes são markdown com frontmatter de `name`, `description`, `model` e
`tools`. O roster próprio inclui, entre outros:

| Perfil | Modelo típico | Papel |
|---|---|---|
| `dev-junior` | haiku | tarefa mecânica, fechada e objetiva |
| `dev-pleno` | sonnet | implementação com julgamento |
| `engenheiro` | sonnet/opus sob demanda | arquitetura e trade-offs, não código final |
| `revisor` | sonnet | review read-only |
| `qa` | sonnet | teste funcional e evidência |
| `golang-pro` | sonnet | especialização Go |
| `python-pro` | sonnet | especialização Python |
| `typescript-pro` | sonnet | especialização TypeScript |
| `postgres-pro` | sonnet | especialização SQL/Postgres |

O `.maestro.yaml` do projeto pode restringir `experts`. Os especialistas
upstream adaptados vivem em `agents/`; o original pinado fica em `vendor/`, com
atribuição de licença e hash.

A regra prática é delegar por padrão. `direct` é exceção para meta-trabalho na
própria sessão, contexto conversacional indispensável ou leitura/pergunta sem
edição. Tarefa pequena não implica automaticamente `direct`.

## 12. Brief, continuidade e memória

`maestro brief` resolve o cold start sem colocar uma narrativa inteira no prompt.
O brief:

- é local e por projeto;
- guarda o que estava em curso, decisões abertas e próximo passo;
- tem cabeçalho com timestamp, epoch, HEAD, wtree e sessão;
- é gravado atomicamente em `$MAESTRO_HOME/briefs/`;
- aceita narrativa de até 16KB;
- é validado pelo `doctor`;
- é classificado como estado de trabalho, não como log nem memória durável.

A memória de longo prazo é uma decisão do ambiente, documentada no ADR-007; o
Maestro apenas injeta `memory_container` do `.maestro.yaml` como ponteiro para o
recall correto. Isso separa continuidade operacional de conhecimento durável.

## 13. Doctor, envelope e drift

O `doctor` não é somente um “está instalado?”. Ele executa medições reais:

- dependências (`bash`, `jq`, `flock`, `git`, Bun);
- hooks e `hooks.json` registrados;
- YAML/JSON e frontmatter;
- resolução dos bindings para skills/agentes;
- tamanho efetivo da injeção SessionStart;
- integridade de `vendor/` contra `vendor.sha256`;
- drift de caminho/conteúdo dos bindings;
- divergência entre repo vivo e cópia instalada do plugin;
- briefs malformados ou vencidos;
- condições do ambiente que não são governadas, como MCPs ou Agent Teams.

Ele grava `~/.maestro/capabilities.json` com fatos inteiros e booleanos e um
snapshot de bindings. O envelope é diagnóstico local, não telemetria. O
consumidor decide se está velho, normalmente após 24 horas.

O objetivo de design é tornar falhas de instalação e cópias congeladas visíveis,
sem fazer do diagnóstico uma dependência do caminho quente dos hooks.

## 14. Testes, evals e CI

### Testes determinísticos

A suíte em `tests/run-all.sh` isola `MAESTRO_HOME` em diretório temporário e não
contamina o estado real. Ela cobre:

- kill-switch;
- injeção e orçamento;
- roster e filtro por projeto;
- routing table e bindings;
- gate warn/block, allowlist e denylist;
- normalização de caminhos e traversal;
- guarda Bash e ofuscação;
- log e vocabulário;
- decisão, TTL, idempotência e status;
- brief e freshness;
- doctor, envelope, drift e instalação;
- argumentos, exit codes e envelopes de erro.

Fixtures adversariais existem para JSON malformado, caminhos enormes, traversal,
comandos ofuscados, `rm`, force push e tentativas de editar arquivos protegidos.

### Eval de roteamento

`tests/eval/` prescreve casos e baseline. O eval-on-diff compara o veredito da
routing table antes/depois e reprova a CI quando uma mutação muda casos
prescritos, nomeando o caso e a transição. Isso transforma melhoria da tabela em
mudança testável, não em opinião subjetiva.

### CI

A CI combina shellcheck, testes bash, testes Bun, `maestro doctor --ci`,
validação de schemas e eval-on-diff. O ratchet do orçamento mede a saída real do
hook e impede que novas seções consumam silenciosamente todo o contexto.

## 15. Fluxo de desenvolvimento recomendado

1. **Abrir ou continuar sessão**: SessionStart injeta profile, brief, rotas,
   bindings, gates e roster.
2. **Identificar a intenção**: o Claude escolhe `fix`, `feature`, `refactor`,
   `ship`, `audit`, `verify`, `codereview` ou `custom`.
3. **Escolher modo/executor**: aplicar heurísticas; preferir `subagent` ou
   `multi` quando houver implementação, múltiplas áreas ou stacks.
4. **Registrar a decisão**: executar `maestro decide --session ...` antes da
   primeira edição de código.
5. **Passar pelo gate humano, se aplicável**: aprovar plano em feature/refactor;
   confirmar ship antes da publicação.
6. **Investigar**: usar o binding de systematic debugging e buscar causa raiz,
   não aplicar patch por sintoma.
7. **Implementar**: delegar ao especialista de linguagem ou tier apropriado.
8. **Revisar separadamente**: `revisor` é read-only e não corrige aquilo que
   revisa.
9. **Testar com QA**: executar testes funcionais e produzir evidência sem deixar
   o próprio implementador ser a única validação.
10. **Publicar, quando solicitado**: usar o fluxo `ship`, com confirmação para
    produção/ações irreversíveis.
11. **Atualizar o brief**: ao fechar trabalho substancial, registrar estado,
    decisões abertas e próximo passo com o session id.
12. **Medir**: rodar `maestro log --summary` e `maestro doctor`; investigar
    overrides, warns, drift e aumento de injeção.
13. **Promover política somente com dados**: após dogfood, decidir se `warn`
    deve virar `block` e ajustar rotas usando eval-on-diff.

## 16. Decisões de design e trade-offs

### Determinismo no enforcement, julgamento na interpretação

Um classificador adicional reduziria a carga no Claude principal, mas adicionaria
custo, latência e outra superfície probabilística. A tabela é explícita e o LLM
continua julgando linguagem natural; os hooks só impõem invariantes verificáveis.

### Arquivos locais em vez de banco

Para um plugin single-user, arquivos versionáveis são suficientes e simplificam
instalação, rollback e inspeção. O custo é não haver concorrência multiusuário,
replicação ou autorização de rede.

### Warn antes de block

Bloqueio imediato protegeria mais, mas falsos positivos fazem o operador desligar
o sistema. O Maestro mede primeiro e promove depois, mantendo kill-switch e
proteção estrutural sempre ativa.

### Curadoria em vez de absorção

Superpowers fornece método, roster fornece executor e gstack fornece automação
pesada. O Maestro evita copiar packs inteiros, reduz colisões e permite trocar a
ferramenta sem renomear o workflow.

### Metadados em vez de conteúdo

Perder prompt e caminho completo reduz a capacidade de investigação detalhada,
mas evita transformar o log em vazamento de dados. O sistema privilegia métricas
suficientes para melhorar roteamento sem capturar conteúdo privado.

## 17. Limitações e pontos para comparação no LEM

1. O gate de edição não cobre todo caminho de alteração via shell.
2. O guard de Bash é léxico e best-effort; não é sandbox.
3. A qualidade do roteamento depende da qualidade da tabela e da interpretação do
   Claude da sessão.
4. Bindings de skills dependem do ambiente instalado; drift pode surgir entre repo,
   marketplace e cache.
5. O estado principal é local e single-user.
6. Gatilhos de aprovação humana são instruções no contexto, não uma máquina de
   estados externa com confirmação durável.
7. A métrica de override mede comportamento, mas precisa de dogfood suficiente
   para calibrar corretamente o modo `warn`/`block`.
8. `doctor` informa componentes fora do envelope, mas não governa automaticamente
   MCPs ou Agent Teams.

Essas limitações são úteis para comparar o Maestro com Legatus/LEM: o Maestro
concentra-se em contratos pequenos, locais e determinísticos no caminho crítico,
enquanto deixa coordenação mais ampla, durabilidade multiagente e políticas de
nível organizacional para uma camada posterior.

## 18. Mapa rápido de leitura do repositório

- Visão e instalação: `README.md`, `README.pt-BR.md`
- Decisões arquiteturais: `docs/architecture/ARCHITECTURE.md`
- Contratos: `docs/architecture/API_SPEC.md`
- Modelo de dados local: `docs/architecture/DATA_MODEL.md`
- Limites de engenharia: `docs/architecture/ENGINEERING_SPEC.md`
- Escopo e roadmap: `docs/architecture/EPICS.md`
- Decisões/incidentes: `docs/decision-log.md`
- Rotas e bindings: `config/routing-table.yaml`
- Enforcement: `hooks/lib/common.sh`, `hooks/pre-tool-gate.sh`,
  `hooks/pre-bash-guard.sh`
- Injeção: `hooks/session-start.sh`
- Métrica de override: `hooks/user-prompt-submit.sh`
- CLI: `bin/maestro`, `src/cli.ts`
- Roster: `agents/`
- Integridade upstream: `vendor/`, `config/vendor.sha256`
- Testes: `tests/run-all.sh`, `tests/hooks/`, `tests/cli/`, `tests/eval/`

## 19. Conclusão

O Maestro gerencia desenvolvimento por **registro + roteamento + gates +
evidência**. Ele não tenta ser um orquestrador onisciente. O desenho mais
importante é separar:

```text
intenção       -> routing table lida pelo Claude
workflow       -> sequência de etapas
binding        -> método/ferramenta que executa a etapa
roster         -> pessoa/agente/modelo que executa
record         -> decisão observável por sessão
hook           -> enforcement determinístico
log/doctor     -> evidência e diagnóstico
```

Essa separação torna o fluxo explicável, testável e evolutivo. A metodologia pode
ser comparada no LEM com sistemas mais amplos sem perder de vista o contrato que
o Maestro realmente cumpre: impedir decisões silenciosas, reduzir uso indevido
de contexto caro, proteger ações irreversíveis e tornar a evolução da própria
routing table mensurável.
