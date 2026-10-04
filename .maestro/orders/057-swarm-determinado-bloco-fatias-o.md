<!-- maestro-order v1
id: 057
ts: 2026-10-03T21:06:54-03:00
epoch: 1791072414
head: 9e0ee89e8ef863a696f7d9dcf54cd06a8bc40f3b
branch: order/057-swarm-determinado-bloco-fatias-o
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 057 — swarm determinado: bloco Fatias, ondas por order --plan e dependencia entre ordens

## Por quê

Ordem do Capitão (03/10), depois da 056 (prioridade de fila, não dependência técnica). Hoje o swarm
(ordem 024) roda N executores no mesmo turno, mas **quem decide o que pode rodar junto é o gerente, de
cabeça**. Resultado visto nesta semana: duas suítes no mesmo worktree se contaminando
(`test-order-041`), recibos de ordens paralelas que se venciam, forge acima do limiar com várias
corridas pesadas ao mesmo tempo. A regra "no máximo uma suíte pesada por vez" vive em nota de prosa,
sem trilho. Esta ordem a torna **mecânica**: a ordem declara suas fatias, o Maestro calcula as ondas.

Filosofia do projeto: trilhos determinísticos decidem **o que pode** rodar junto; o gerente decide
**o que fazer**.

## O que entrega

1. **Bloco `## Fatias` na ordem.** Cada fatia, uma linha, campos fixos:
   `- F<n> | depende_de: <F..|-> | arquivos: <caminhos ou globs> | classe: <cpu|modelo|io> | <o quê>`.
   Classes: **cpu** = suíte e build; **modelo** = escrever, revisar e pesquisar; **io** = rede e lab.
2. **`maestro order --plan N`** calcula as **ondas**. Uma fatia entra na onda quando (i) não tem
   dependência pendente e (ii) seus `arquivos` são **disjuntos** dos das outras fatias da mesma onda.
   Admissão por classe:
   - **cpu**: por **orçamento de CPU medido** — a carga atual (load×100, inteiro) contra o número de
     CPUs, e o **tempo histórico da suíte** (mediana dos recibos do ledger). Sem orçamento, a fatia
     espera a próxima onda; nunca duas suítes no mesmo worktree.
   - **modelo**: só pelo **teto de cota** (constante em `config/`, inteiro de execuções simultâneas).
   - **io**: uma por vez por padrão (rede e lab são o gargalo escasso).
   Saída: humana e `--json` (ondas, fatia por onda, motivo de cada adiamento).
3. **O mesmo no nível de ordens.** Cabeçalho da ordem ganha `depende_de: <NNN…|->` (opcional;
   ausente = independente). `order --plan` sem N lista as ordens abertas em ondas e `--status --json`
   expõe `depende_de` e `liberada` (booleano), para que o **daemon só libere em paralelo as
   independentes**. A parte do daemon (ponte-daemon) é consumo dessa saída e **fica fora** desta
   ordem: aqui sai o contrato e o dado.
4. **`conform --check` exige o bloco `## Fatias`** em ordem com **mais de uma fatia** (nova lacuna
   `order-no-fatias`, no molde de `order-no-turno`). Ordem de uma fatia só não precisa do bloco.
   Ordens antigas abertas ganham a lacuna como as outras do método (esperado), nunca bloqueio.
5. **Teste com a própria 057 como caso:** o `order --plan 057` deste arquivo dá as ondas abaixo, e o
   teste as confere.

## Fatias

- F1 | depende_de: - | arquivos: lib/core-order-fatias.sh tests/cli/test-order-057-fatias.sh | classe: modelo | parser do bloco Fatias, validação dos campos e das classes
- F2 | depende_de: F1 | arquivos: lib/cmd-order-plan.sh tests/cli/test-order-057-plan.sh | classe: modelo | `order --plan N`: ondas por dependência e arquivos disjuntos, saída humana e --json
- F3 | depende_de: F1 | arquivos: lib/core-order-budget.sh tests/cli/test-order-057-budget.sh | classe: modelo | orçamento: cpu por carga e tempo histórico da suíte, modelo por teto de cota, io serial
- F4 | depende_de: F1 | arquivos: lib/core-conform-orders.sh tests/cli/test-order-057-conform.sh | classe: modelo | lacuna `order-no-fatias` no `conform --check`
- F5 | depende_de: F2 F3 | arquivos: lib/core-order-state.sh lib/cmd-order-status.sh tests/cli/test-order-057-ordens.sh | classe: modelo | `depende_de` no cabeçalho, `liberada` no --status --json e o plano no nível de ordens
- F6 | depende_de: F2 F3 F4 F5 | arquivos: docs/architecture/API_SPEC.md docs/architecture/DATA_MODEL.md CHANGELOG.md | classe: modelo | emendas de contrato e CHANGELOG
- F7 | depende_de: F6 | arquivos: - | classe: cpu | suíte completa e recibos no tip

Ondas esperadas para este arquivo: **[F1] → [F2 F3 F4] → [F5] → [F6] → [F7]**. F2, F3 e F4 correm
juntas (arquivos disjuntos, todas `modelo`); F7 é a única `cpu` e roda sozinha.

## Ask-First

- Se o **tempo histórico da suíte** não estiver no recibo (hoje há `epoch` e `wtree` antes/depois,
  não a duração), PARE antes de mudar o formato do recibo (DATA_MODEL): reporte e proponha como medir
  (ex.: campo `dur_ms` inteiro). Sem float em qualquer métrica.
- Se o cálculo de ondas exigir mais de ~100 ms no caminho de `--plan` (ledger + git), reporte a
  medição antes de seguir.
- Se o `depende_de` entre ordens exigir mudar o **carimbo** ou o estado derivado da ordem (DATA_MODEL
  §9), PARE: é contrato.
- Conserto em `bin/`, `hooks/`, `src/`, `lib/` (autoprotegidos): sai em UM patch em
  `docs/patches/057-*.patch`, feito em clone sandbox FORA do repo, aplicado pelo Capitão. O despacho de
  `order --plan` em `bin/maestro`, se mudar, vai no mesmo patch.
- Liberar o daemon (ponte-daemon) para ler `liberada` é outra ordem, de outro repo — não toque.

## Como sai

`tests/` e `docs/` direto no branch; protegido, em UM patch. Emendas no mesmo changeset: API_SPEC
(`order --plan`, `--status --json`, `conform`), DATA_MODEL (bloco Fatias e `depende_de`), CHANGELOG e
ENGINEERING_SPEC (o swarm deixa de ser prosa).

## Prova exigida

- **Vermelho antes:** `order --plan` não existe; `conform` não acusa ordem de 2+ fatias sem bloco.
- **Verde depois:** as ondas desta ordem saem como declaradas acima; duas fatias com o mesmo arquivo
  nunca caem na mesma onda; sob carga acima do orçamento a fatia `cpu` é adiada com o motivo;
  `depende_de` entre ordens não libera a dependente antes da independente.
- **Controles:** ordem de uma fatia sem bloco passa no `conform`; bloco com classe inválida,
  `depende_de` circular ou fatia sem arquivos (exceto F-cpu de suíte) é ERRO claro, nunca plano
  silencioso; só inteiros nas métricas.
- Suíte completa `SUITE OK`, sozinha no worktree; recibos `order-57`, `suite-57` e `suite` (legado
  até a frota girar); `habits` dentro da catraca (função nova acima de 60 linhas reprova).

## Turno

- fatia: F1 (parser do bloco Fatias) e, com F1 verde, a onda [F2 F3 F4] — o plano da própria 057 como teste
- fim: `order --plan 057` imprime as ondas declaradas e o teste as confere; `bash tests/run-all.sh` sai 0
- teto: 6
- fora: o consumo pelo daemon (ponte-daemon), mudar o formato do recibo sem o Ask-First, aplicar o patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Paralelismo:** as fatias da mesma onda podem ir a subagentes distintos, cada um com os arquivos da
> sua fatia (disjuntos por construção). No máximo UMA suíte pesada por vez, sozinha neste worktree.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**: heredoc, `tee` e redirecionamento no Bash são barrados pelo guard (ordem 047).

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/057-swarm-determinado-bloco-fatias-o`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-57 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 057` (você não fecha a própria ordem).
