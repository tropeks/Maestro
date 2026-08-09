# ROUTING_EVAL.md — avaliação de qualidade do roteamento (S-402)

**Consome:** `config/routing-table.yaml`, `agents/*.md`, `hooks/session-start.sh`
**Produz:** o número da AC da S-402 e a lista de calibração da routing table
**Harness:** `tests/eval/` (`cases.yaml`, `prescribe.ts`, `run-eval.sh`)

> AC da S-402 (EPICS.md): *"heurísticas de execução escritas e testadas em 10 tarefas
> reais; ≥8/10 roteadas sem correção manual (medido no log)."*

Esta é a única AC do Maestro que mede **qualidade de decisão**, não funcionamento de
código. Todas as outras se provam com asserção; esta não — porque o roteador é um LLM
(ADR-002), e não existe função que decida o workflow. O documento existe para que o
número tenha método declarado, seja reexecutável, e seja **contestável caso a caso**.

**Resultado, em uma linha:** com a tabela `v2` (sha256 `afdc5fa05529`) e 15 casos,
um juiz LLM cego acerta **11/15 (73%)** — abaixo da AC de 80%, com **8 dos 9 erros
concentrados na coluna `mode`**, e uma causa raiz identificada (achado R11). O log de
dogfood, que é a fonte que a AC cita, ainda está vazio.

---

## Por que três instrumentos (e um derivado)

O pedido "compare o que a tabela prescreve com o esperado" esconde uma armadilha: a
comparação exige julgamento, e um harness que finge decidir sozinho estaria medindo o
autor do harness, não a tabela. A saída foi separar o que é objetivamente decidível do
que não é, em instrumentos com escopos diferentes e honestos:

| | pergunta que responde | quem decide | reexecutável | é a AC? |
|---|---|---|---|---|
| **(A)** aproximação determinística | *o TEXTO da tabela, lido ao pé da letra, basta?* | função pura | 100% | **não** — é piso |
| **(B)** julgamento cego de LLM | *o mecanismo real acerta?* | LLM sem gabarito | sim, com variância | **sim, hoje** |
| **(B')** concordância entre juízes | *a tabela está determinada?* | dois LLMs, sem gabarito | sim | não — mas é o mais objetivo |
| **(C)** log de dogfood | *o Romulo precisou corrigir?* | operação real | sim | **sim, quando houver dado** |

O que **não** foi feito, e é o ponto: nenhum número aqui saiu de mim lendo a tabela e
decidindo "acertou". Em (A) quem decide é código; em (B) quem decide é um LLM que nunca
viu o gabarito; em (B') ninguém decide (mede-se a divergência entre dois juízes);
em (C) quem decide é o log. O único julgamento meu está nos rótulos
`expected` de `tests/eval/cases.yaml` — declarado por extenso, com justificativa por
caso, exatamente para poder ser derrubado.

---

## A matriz — `tests/eval/cases.yaml`

15 casos (a AC pede 10; o contrato pede ≥12), escritos como o Romulo escreve: pt-BR, do
telefone, curtos, vagos, no imperativo, acentuação irregular.

| # | id | stack | tipo | esperado (workflow / mode / agentes) |
|---|---|---|---|---|
| 1 | `go-nil-worker` | Go | bug trivial | fix / direct / golang-pro |
| 2 | `ts-login-quebrado` | TS | bug trivial | fix / direct / typescript-pro |
| 3 | `py-export-csv` | Py+TS | feature multi-arquivo | feature / multi / python-pro+typescript-pro |
| 4 | `go-endpoint-health` | Go | feature média | feature / subagent / golang-pro |
| 5 | `py-refactor-auth` | Py | refactor amplo | refactor / multi / engenheiro+python-pro |
| 6 | `audit-legatus` | infra | auditoria de segurança | audit / direct / — |
| 7 | `ship-smartquotation` | Py | ship | ship / direct / — |
| 8 | `pg-query-lenta` **†** | Postgres | performance | fix / subagent / postgres-pro |
| 9 | `pg-campo-cnpj` **†** | Postgres | feature pequena | feature / direct / postgres-pro |
| 10 | `infra-pve-restart` **†** | infra | diagnóstico | fix / direct / — |
| 11 | `resumo-semana` | — | não-código | **custom** / direct / — |
| 12 | `ts-console-logger` **†** | TS | mecânico | refactor / subagent / dev-junior |
| 13 | `react-tela-config` | TS | feature de UI | feature / subagent / typescript-pro |
| 14 | `qa-fluxo-orcamento` | Py+TS | verificação pura | **custom** / subagent / qa |
| 15 | `review-pr` | — | review isolado | **custom** / subagent / revisor |

**†** = ambíguo por desenho (duas rotas ou duas heurísticas competem). Os quatro são
declarados no campo `competes` do YAML:

- **8** `fix` × `refactor` × `custom` — lentidão não é "erro" nem "dívida técnica";
  nenhum `intent` da tabela cobre performance.
- **9** H1 (`≤2 arquivos → direct`) × H2 (`feature nova → subagente com plano`). Uma
  coluna + uma migration dispara as duas, e a tabela não diz qual vence.
- **10** `fix` × `custom` — diagnóstico de infra pode não ter edição de código, e
  `workflows.fix` pressupõe `implement`+`review`.
- **12** H3 (`mecânica → dev-junior/haiku`) × H5 (`linguagem → especialista`). Sem
  precedência declarada, o tiering de custo (a razão de existir do roster) fica no ar.

Três casos esperam `custom`: um por natureza (11, não é código) e **dois por lacuna da
tabela** (14 e 15 — `qa` e `review` existem só como *step*, nunca como workflow).

---

## Instrumento (A) — aproximação determinística

`tests/eval/prescribe.ts`. Implementa, como função pura, **só o que o YAML declara**:

- **R-W1 (workflow):** cada `routes[].intent` vira lista de frases separadas por
  vírgula; casamento **literal por substring** sobre o enunciado normalizado
  (minúsculas, sem acento). Mais frases casadas vence; empate = ordem de declaração;
  zero casamentos → `custom`. Sem stemming — stemming seria a aproximação consertando a
  tabela por baixo do pano e **escondendo o defeito que se quer medir**.
- **R-M1 (mode):** H2 (`workflow == feature → subagent`); todo o resto cai em `direct`.
  H1 é inaplicável (exige contagem de arquivos, que o enunciado nunca traz) e **nenhuma
  regra da tabela produz `multi`**.
- **R-A1 (agentes):** H3 (mecânica) → H4 (arquitetura/review) → H5 (linguagem), na
  ordem de declaração, acumulando e reportando conflito.

Onde a tabela não diz o suficiente, a aproximação inventou — e cada invenção está
listada na saída como **assunção**, contando como dívida da tabela, não do caso:

| | assunção | por quê |
|---|---|---|
| A1 | léxico de linguagem | "linguagem detectada" não diz por quais tokens |
| A2 | léxico de "mecânica/repetitiva" | idem |
| A3 | precedência entre heurísticas | a tabela não ordena |
| A4 | contagem de arquivos | H1/H2 dependem dela; o enunciado nunca traz |
| A5 | não-casamento → `custom` | a tabela documenta o escape hatch, não a queda nele |

### Resultado (A)

```
$ bash tests/eval/run-eval.sh
tabela: routing-table.yaml v2 sha256:afdc5fa05529
APROXIMAÇÃO DETERMINÍSTICA: 1/15 exatos | workflow 4/15 | mode 7/15 | agentes 8/15 | ambíguos 0/4
```

**1/15.** Ler este número como "o roteador do Maestro acerta 1 em 15" seria erro grave:
o roteador não é esta função. O que 1/15 diz é uma coisa só, e ela é grave o bastante:
**o texto da routing table, sozinho, quase nunca chega ao roteamento certo.** O acerto
que sobra é a tarefa que não é código (`resumo-semana`) — a tabela acerta por omissão.

O detalhe por dimensão é onde está o valor: `workflow 4/15` isola o problema em
`routes[].intent`; `mode 7/15` mostra que `multi` é inalcançável; `agentes 8/15` mostra
que as heurísticas de agente são a parte mais saudável da tabela.

### What-if (quanto cada conserto valeria)

```
$ bash tests/eval/run-eval.sh --what-if
baseline ............ 1/15 exatos | workflow 4/15 | mode 7/15 | agentes  8/15
intents por radical . 2/15 exatos | workflow 7/15 | mode 7/15 | agentes  8/15
linguagem do profile  2/15 exatos | workflow 4/15 | mode 7/15 | agentes 10/15
os dois ............. 3/15 exatos | workflow 7/15 | mode 7/15 | agentes 10/15
```

Isto **quantifica** duas recomendações (R1 e R3 abaixo) em vez de argumentá-las:
casar por radical vale +3 em workflow; a linguagem vinda do `.maestro.yaml` vale +2 em
agentes. Nenhum dos dois resolve `mode` — problema de outra natureza (R4 e R11), e o
mesmo que o instrumento (B) isola em seguida.

---

## Instrumento (B) — julgamento cego de LLM

É o mecanismo real: ADR-002 diz que quem decide é *"o Claude da própria sessão, guiado
pela routing table injetada no SessionStart"*. O instrumento reproduz isso literalmente.

**Protocolo (o cego é o ponto):**

1. `run-eval.sh --judge-prompt` monta o prompt do juiz com **a saída de verdade** do
   `hooks/session-start.sh` (não uma paráfrase) + as descriptions do roster, que o
   harness carrega always-on + os 15 enunciados, **só id e texto**.
2. O prompt **não contém** `expected`, `stack`, `kind`, `rationale` nem a marcação de
   ambiguidade. Há asserção no `--selftest` verificando que não vaza.
3. O juiz roda como subagente com contexto limpo, proibido de ler qualquer outro
   arquivo do repositório, e devolve TSV `id / workflow / mode / agentes`.
4. `run-eval.sh --judge-score FILE` abre o gabarito **só depois** que o juiz respondeu.

**Ameaças à validade, declaradas:** (i) os rótulos `expected` são meus, e eu escrevi a
matriz — um juiz que discorde de mim conta como erro mesmo quando a decisão dele é
defensável (por isso os quatro casos ambíguos estão marcados e reportados à parte);
(ii) o juiz é não-determinístico: **uma execução não é uma medida**, por isso duas, em
modelos diferentes; (iii) o juiz vê 15 casos de uma vez, e não um por sessão — isso
provavelmente **ajuda** (comparação entre casos), então o número é otimista nessa
dimensão; (iv) sem `.maestro.yaml` no contexto (os casos são de projetos diferentes),
que é a condição mais dura possível.

### Rodada 1 — e o defeito que ela expôs

| juiz | exatos | workflow | mode | agentes |
|---|---|---|---|---|
| Opus 5 | **6/15** | 15/15 | 8/15 | 6/15 |
| Sonnet | **5/15** | 14/15 | 12/15 | 6/15 |

Os dois juízes, independentemente, erraram a coluna `agentes` da **mesma** maneira:
listaram `revisor` e `qa` em quase todo caso, porque `review` e `qa` são **steps** dos
workflows. A leitura deles é defensável — o texto injetado não diz que `--agents` é só
quem executa o trabalho principal. Isso é **defeito do instrumento e da injeção**, não
erro de roteamento, e está registrado como achado **R10**. O prompt do juiz foi
desambiguado (fixando a semântica do DATA_MODEL §3) e a rodada foi refeita. Os TSV da
rodada 1 ficam no repositório (`tests/eval/judge-*-r1.tsv`) como evidência.

### Rodada 2 — o número

| juiz | exatos | workflow | mode | agentes |
|---|---|---|---|---|
| Opus 5 | **11/15** (73%) | 14/15 | 12/15 | 15/15 |
| Sonnet | **10/15** (67%) | 15/15 | 10/15 | 13/15 |

**O número da S-402 é 11/15 (73%) no melhor juiz, 10/15 no outro, contra uma AC de
≥8/10 (80%). A AC não foi atingida — por pouco, e essencialmente por uma causa só.**

| caso | Opus | Sonnet |
|---|---|---|
| `go-nil-worker` | mode direct→subagent | ok |
| `ts-login-quebrado` | mode direct→subagent | ok |
| `py-export-csv` | ok | mode multi→subagent · agentes py+ts→dev-pleno |
| `py-refactor-auth` | ok | mode multi→subagent · agentes eng+py→python-pro |
| `pg-query-lenta` † | ok | mode subagent→direct |
| `pg-campo-cnpj` † | mode direct→subagent | ok |
| `infra-pve-restart` † | workflow fix→custom | ok |
| `qa-fluxo-orcamento` | ok | mode subagent→direct |
| `review-pr` | ok | mode subagent→direct |

**8 dos 9 erros são a coluna `mode`.** Workflow (14-15/15) e agentes (13-15/15) estão
resolvidos; a tabela roteia bem *o quê* e *quem*, e mal *como*. Dentro de `mode`:

- **H1 pede informação que o roteador não tem** (achado **R11**): "edição ≤2 arquivos"
  só se sabe **depois** de investigar, e a decisão acontece **antes**. Sem o dado, o
  Opus delega por segurança (3 erros) e o Sonnet arrisca `direct` (3 erros) — os dois
  chutam, em direções opostas. Só isso levaria o Opus a 14/15 (93%), acima da AC.
- **`multi` não tem regra** (achado **R4**): o Sonnet nunca o usou e errou os 2 casos
  multi-stack; o Opus usou-o de mais na rodada 1 e de menos na 2.

Vale notar a direção do erro do Opus: ele **super-delega**, enquanto a dor do brief §1
é o oposto (o modelo edita direto quando deveria delegar). O viés original foi
corrigido; o resíduo é custo de token, não retrabalho.

### (B') Concordância entre juízes — o número sem gabarito nenhum

```
$ bash tests/eval/run-eval.sh --judge-agree tests/eval/judge-opus-r2.tsv tests/eval/judge-sonnet-r2.tsv
CONCORDÂNCIA ENTRE JUÍZES: 6/15 exatos | workflow 14/15 | mode 7/15 | agentes 13/15
```

Este é o único número aqui que **não depende de julgamento humano nenhum** — nem meu,
nem de gabarito: dois LLMs independentes lendo a mesma tabela ou concordam ou não.
Ele confirma o diagnóstico por um caminho totalmente distinto: **workflow 14/15 e
agentes 13/15 de concordância, contra `mode` 7/15**. Uma tabela que produz a mesma
resposta em dois modelos diferentes está determinada; `mode` não está. Se um só número
tivesse de sobrar deste documento como pauta de calibração, seria este 7/15.

---

## Instrumento (C) — o log real (a AC "medido no log")

`~/.maestro/logs/routing.jsonl` **está vazio hoje**: o plugin acabou de ser instalado e
não houve dogfood. O instrumento existe pronto para o dia em que houver.

```
$ bash tests/eval/run-eval.sh --log ~/.maestro/logs/routing.jsonl
log inexistente: /home/rcosta00/.maestro/logs/routing.jsonl
SEM DADO — o instrumento (C) só produz número depois do dogfood.
```

**Por que não dá para casar log com esta matriz:** o log é proibido de conter texto de
prompt (DATA_MODEL §4, brief §10). Não existe chave para ligar uma linha do log ao caso
`pg-campo-cnpj`. Qualquer harness que prometesse "prescrito × observado por caso" estaria
mentindo — ou pedindo para violar a política de log. A métrica observável é outra, e é
justamente a que a AC pede ("roteadas **sem correção manual**"):

```
universo  = sessões com ≥1 evento `decision`
suja      = sessão com QUALQUER um de:
              · `override_manual`                       (ADR-008: o humano digitou comando)
              · 2+ eventos `decision` divergentes       (re-decisão = correção de rumo)
              · `gate_warn`/`gate_block` antes do 1º `decision`  (editou antes de rotear)
métrica   = (universo − sujas) / universo
```

Sessões sem nenhum `decision` ficam fora do universo (podem não ter tido trabalho de
código). Re-registro **idêntico** do mesmo record não suja — só divergência conta.

**Limites conhecidos desta definição:** `override_manual` não distingue "o Romulo
corrigiu o roteamento" de "o Romulo quis rodar uma skill de propósito" — a métrica
**superestima** a correção manual, ou seja, é conservadora contra o Maestro. E correção
feita em linguagem natural ("faz via subagentes"), que é o caso literal do brief §1, é
**invisível ao log**: não começa com `/` e não gera evento. Enquanto isso não for
observável, (C) mede um limite inferior da qualidade e não substitui (B).

As 10 asserções de (C) no `--selftest` rodam contra logs sintéticos em `mktemp -d` —
sessão limpa, override, re-decisão divergente, re-registro idêntico, gate antes da
decisão, sessão fora do universo, log vazio, log inexistente e linha corrompida.

---

## Achados de calibração da routing table

Ordenados por dano. Nada disto foi aplicado: `config/routing-table.yaml` é do agente A
nesta rodada. Cada item traz a evidência que o produziu.

### R1 — `routes[].intent` está no infinitivo; o Romulo fala no imperativo
**Evidência (A):** `workflow 4/15`. `"adicionar"` não casa `"adiciona o campo cnpj"`;
`"criar tela"` não casa `"cria a tela de configurações"`. Casando por radical o número
vai a `7/15` — o maior ganho isolado da tabela inteira.
**Mudança:** trocar as frases por radicais/variantes (`adicion*`, `cri*`, `nov*`) ou
declarar explicitamente que o casamento é semântico, não lexical (o LLM faz isso de
graça, mas então o texto atual está enganando quem lê a tabela, incluindo o próprio LLM).

### R2 — `ship` e `audit` são workflows sem nenhuma rota
**Evidência (A):** os casos 6 e 7 caem em `custom` — a tabela não dá **nenhuma** âncora
lexical para "manda pra produção" ou "olhada de segurança".
**Mudança:** duas linhas em `routes`: `{intent: "subir, deploy, produção, lançar, publicar", workflow: ship}`
e `{intent: "segurança, vulnerabilidade, auditoria, exposto", workflow: audit}`.

### R3 — "linguagem detectada" detecta no enunciado errado
**Evidência (A):** `go-nil-worker` ("o worker do **netforge**…") não tem token de Go
nenhum — a linguagem é fato do **projeto**, não do texto. Com a linguagem vinda do
profile, `agentes` sobe de 8/15 para 10/15.
**Mudança:** reescrever H5 como `linguagem do projeto (.maestro.yaml languages/experts)
ou detectada no enunciado → especialista correspondente`. A infraestrutura já existe
(S-303); a heurística é que não a menciona.

### R4 — nenhuma heurística produz `mode: multi`
**Evidência (A):** `R-M1` nunca emite `multi` para nenhum dos 6 workflows; os casos 3 e
5 (duas stacks / refactor amplo) são inatingíveis. O vocabulário do DATA_MODEL §3 tem
três modos e a tabela só sabe decidir dois.
**Evidência (B):** o Sonnet nunca usou `multi` e errou exatamente esses dois casos; o
Opus usou-o em 9 casos na rodada 1 e em 2 na rodada 2 — instabilidade típica de valor
sem regra.
**Mudança:** heurística explícita — `mais de uma stack ou frentes independentes → mode: multi`.

### R5 — H1 e H2 se contradizem em feature pequena, sem desempate
**Evidência:** caso 9, marcado ambíguo. "adiciona o campo cnpj" é feature nova (H2 →
subagente **com plano**) e cabe em 2 arquivos (H1 → direct). Aplicar H2 põe um gate de
plano numa migration de uma coluna — a cerimônia que faz o brief §9 (0-1 comandos por
sessão) falhar na prática.
**Mudança:** ordenar as heurísticas e dizer que a primeira que casa vence, ou emendar H2
com `feature nova que toca >2 arquivos`.

### R6 — H3 (custo) × H5 (especialista) sem precedência
**Evidência:** caso 12; o prescritor reporta o conflito explicitamente. Se H5 vencer,
tarefa mecânica de TS vai para `typescript-pro` (sonnet) em vez de `dev-junior` (haiku)
— e o tiering de custo é a razão de existir do roster (ADR-004).
**Mudança:** declarar `H3 vence H5` no texto da heurística.

### R7 — não há workflow de verificação nem de review isolados
**Evidência:** casos 14 e 15 forçam `custom` para dois pedidos rotineiros ("testa o
fluxo", "revisa esse PR"). `qa` e `review` só existem como *step* de `feature`/`fix`.
**Mudança:** dois workflows de um passo — `verify: {steps: [qa], gate: none}` e
`review: {steps: [review], gate: none}` — reaproveitando os bindings que já existem.
Custo: 2 linhas. Benefício: tira 2 casos do escape hatch.

### R8 — nada cobre performance nem infra
**Evidência:** casos 8 e 10, ambos ambíguos. "tá levando 40s" e "container reiniciando"
não são "erro/quebrou" nem "dívida técnica". Além disso o roster (ADR-004) não tem
agente de infra/SRE — coerente com o escopo por linguagem, mas o Romulo **é analista de
infra** e o homelab é metade do portfólio.
**Mudança:** incluir `lento, performance, travando` no intent de `fix` (barato) e
registrar a lacuna de agente de infra como decisão consciente — ou item de roadmap.

### R9 — o binding `implement → agent:dev-pleno` contradiz H5
**Evidência:** injeção atual (S-401, agente A). A seção de bindings diz que `implement`
roda `agent:dev-pleno`, enquanto H5 manda usar o especialista da linguagem. Para 9 dos
15 casos o esperado é um especialista, não `dev-pleno`.
**Mudança:** `implement → agent:<especialista da linguagem, senão dev-pleno>`, ou uma
nota no binding dizendo que H5 o sobrepõe. **Este é o único achado que não vem da minha
matriz e sim da mudança do agente A** — vale conferir antes do fechamento.

### R10 — `--agents` não está definido em lugar nenhum que o modelo veja
**Evidência (B, rodada 1):** dois juízes independentes, em modelos diferentes, leram
`agentes` como "todo o elenco do workflow" e incluíram `revisor`/`qa` porque são steps.
Custo medido: `agentes` caiu de 15/15 para 6/15 só por essa ambiguidade.
**Por que importa em produção:** o mesmo texto está na injeção real. Um `decision
record` com `agents: [golang-pro, revisor, qa]` polui a métrica de tiering de custo
(ADR-004) e o `edits_per_decision` do ADR-008.
**Mudança:** uma linha na INSTRUÇÃO CANÔNICA da injeção — `--agents = quem executa o
trabalho principal; revisor/qa dos steps são implícitos` — ou a mesma nota no
DATA_MODEL §3. É a correção mais barata desta lista e a de efeito mais imediato.

### R11 — H1 pede informação que o roteador não tem na hora de decidir
**Evidência (B, rodada 2):** 3 dos 4 erros do Opus. "edição ≤2 arquivos" só é conhecido
**depois** de investigar; a decisão acontece **antes**. O juiz, sem o dado, delega por
segurança — e um bugfix de uma linha vira subagente.
**Impacto:** consertar isto sozinho leva o número de 11/15 (73%) a 14/15 (93%),
atravessando a AC. É a maior alavanca da tabela hoje.
**Mudança:** reescrever H1 em termos do **pedido**, não do resultado. Por exemplo:
`sintoma único e localizado, ou pedido de uma frase numa linguagem só → mode: direct;
na dúvida sobre extensão, investigue em direct e re-registre se crescer`. A segunda
metade importa: re-decidir depois de investigar é barato e o log já distingue
re-decisão de override (instrumento C).

---

## Como reexecutar

```bash
bash tests/eval/run-eval.sh --selftest        # 16 asserções do harness (roda em mktemp -d)
bash tests/eval/run-eval.sh                   # (A) veredito por caso + diagnóstico
bash tests/eval/run-eval.sh --what-if         # (A) quanto cada conserto valeria
bash tests/eval/run-eval.sh --judge-prompt    # (B) gera tests/eval/judge-prompt.md
#   → rodar o prompt num subagente limpo, salvar o TSV
bash tests/eval/run-eval.sh --judge-score tests/eval/judge-<modelo>.tsv
bash tests/eval/run-eval.sh --judge-agree A.tsv B.tsv   # (B') concordância, sem gabarito
bash tests/eval/run-eval.sh --log ~/.maestro/logs/routing.jsonl   # (C)
```

Artefatos versionados como evidência: `tests/eval/judge-prompt.md` (o que os juízes
viram) e `tests/eval/judge-{opus,sonnet}-r{1,2}.tsv` (o que responderam).

`--prescribed --min N` devolve exit≠0 abaixo do mínimo, para quem quiser gate de CI.
**`tests/eval/` fica fora de `tests/run-all.sh` de propósito:** score de roteamento
abaixo de 100% é informação, não regressão, e não pode derrubar a suíte do plugin.

### O dia em que houver log real

1. Rode (C) semanalmente: `run-eval.sh --log ~/.maestro/logs/routing.jsonl`.
2. Compare com a baseline do brief (*"~100% das tarefas exigem correção de rumo"*, ou
   seja **0/N**) e com a meta de 3 meses (**<20% de intervenção**, ou seja ≥8/10 — o
   mesmo número da AC da S-402: os dois são a mesma métrica).
3. Quando (B) e (C) discordarem, **(C) ganha**: o juiz cego é uma simulação; o log é o
   Romulo. Divergência grande entre os dois significa que a matriz não representa o
   trabalho real — nesse caso o conserto é a matriz, não a tabela.
4. Reexecute (A) e (B) a cada mudança de `config/routing-table.yaml`. O sha256 da tabela
   sai em toda saída justamente para que nenhum score fique órfão da revisão que o gerou.
5. Reabra este documento como o registro de calibração: cada item R1-R9 aplicado deve
   fazer (A) subir; se aplicar e não subir, a hipótese estava errada e isso é resultado.
