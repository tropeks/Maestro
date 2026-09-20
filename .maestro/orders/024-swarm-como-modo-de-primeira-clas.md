<!-- maestro-order v1
id: 024
ts: 2026-09-18T21:26:27-03:00
epoch: 1789777587
head: c41fb6f4e02c3bc204f8843800b45e3186a5dbd1
branch: feat/024-swarm-primeira-classe
frozen: vendor/ agents/
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
absorbed_by: main
absorbed_tree: 2456f953ea43f53c14e2762f5b224694aff93299
absorbed_at: 2026-09-19T22:43:37-03:00
absorbed_session: desconhecido
-->
# Ordem 024 — swarm como modo de primeira classe: N executores no MESMO turno



## Contrato de execução
- Trabalhe APENAS no branch `feat/024-swarm-primeira-classe`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/
- Prove com o ledger: `maestro evidence --record --label order-24 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 024` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v3, Prioridade 2 — "custo proporcional à tarefa; delegar é a regra".

**Medição do Capitão nos transcritos de 2026-09-18, nove sessões:**

| sessão | subagentes despachados |
|---|---|
| Agenda | 28 |
| Maestro | 11 |
| vulcan | 10 |
| Vitali | 8 |

Agentes usados: `dev-pleno`, `typescript-pro`, `python-pro`, `revisor`.

E o número que importa: **ZERO turnos com mais de um despacho em paralelo**, nas
nove sessões. Inclusive na do Maestro e na da Enterprise **depois** de o Capitão
mandar "via swarm" explicitamente.

O gerente do Maestro, nessa ocasião, despachou duas frentes independentes em
**dois turnos seguidos**. Elas rodaram concorrentes no relógio (as duas em
background), mas o padrão foi um-por-vez. Delegação existe e é usada; **swarm
não existe na prática.**

## A causa, em três partes — e nenhuma é "o modelo esqueceu"

**1. A heurística classifica, não despacha.** `config/routing-table.yaml:136`:

> H6 mais de uma stack envolvida, ou frentes independentes que não se bloqueiam
> → mode: multi

`multi` descreve a DECISÃO de roteamento. Nada, em lugar nenhum do Maestro, diz
**"despache no MESMO turno"**. Um gerente que leia H6 e despache em série está
obedecendo ao que está escrito.

**2. O ledger RECUSA o caso mais comum.** Duas frentes do mesmo tipo pedem o
mesmo especialista duas vezes. Medido nesta sessão:

```
$ maestro decide --mode multi --agents dev-pleno,dev-pleno
maestro: aviso: agente duplicado ignorado: dev-pleno
maestro: validation: mode 'multi' exige pelo menos 2 agentes
```

Então H6 manda usar `multi`, e o schema torna `multi` inalcançável quando a
resposta certa é o mesmo expert em N frentes. O gerente registra `subagent`, que
é o valor verdadeiro disponível, e **a paralelização some do dado** — o ledger
não consegue dizer o que de fato aconteceu.

**3. Não há guarda de colisão.** Nada impede duas frentes de escreverem no mesmo
arquivo. O projeto já pagou por isso: três colisões em três dias motivaram o
worktree por frente (ordem 012). Hoje a proteção é disciplina do gerente, não
mecanismo.

## O que esta ordem entrega

**Swarm como modo de primeira classe**: o gerente declara frentes independentes
e despacha N executores no MESMO turno.

O desenho precisa cobrir:

- **A declaração da frente**: cada frente nomeia o que toca — arquivos ou
  worktree. Frentes de um swarm são **disjuntas por construção**, e isso é
  verificável, não prometido.
- **A guarda de colisão**: interseção não-vazia entre frentes é erro ANTES do
  despacho, não achado depois. Decida onde ela mora — CLI, hook, ou os dois — e
  justifique.
- **O ledger passando a expressar o que aconteceu**: N executores, quantos do
  mesmo tipo, quais frentes. Hoje ele não consegue.
- **Um só revisor no fim**, não um por frente — o review olha o conjunto, que é
  onde a colisão apareceria.

## TRAVA DE CONTRATO

- `config/routing-table.yaml` está nas **zonas congeladas** desta ordem? NÃO —
  ela é o alvo. Mas é DADO lido por todo projeto: mudança de forma exige emenda
  no doc canônico correspondente, no MESMO changeset.
- **Nenhum valor novo no enum de `mode` sem parar e chamar.** Hoje é
  `direct|subagent|multi`. Se o desenho pedir um quarto, isso é decisão de
  modelo — PARE. Provavelmente `multi` já é o valor certo e o que falta é o
  schema deixar de recusá-lo.
- `maestro decide` valida o record por schema. Mudança ali muda o contrato que
  o `doctor` cobra — emenda do `DATA_MODEL` no MESMO changeset. A maior hoje é
  **v1.19**; confirme com
  `grep -oE "Emenda v1\.[0-9]+" docs/architecture/DATA_MODEL.md | sort -t. -k2 -n | tail -1`,
  posição POR SEÇÃO, nunca no fim do arquivo.
- **Não mexa no comportamento de agente.** Esta ordem dá o mecanismo e o dado;
  ela não reescreve como o gerente decide. Se o desenho exigir mudar o preâmbulo
  injetado, lembre do teto: **injeção acima de 8000 B está fora por texto
  expresso do INTENT v3**, e ela vive perto do teto.

## Prova exigida

- **O caso que motivou a ordem**: duas frentes do mesmo especialista registram
  `multi` com N=2, e o ledger mostra as duas. Hoje isso é recusado — mostre as
  duas pontas.
- **Guarda de colisão**: frentes com interseção de arquivos são recusadas ANTES
  do despacho; frentes disjuntas passam. As duas pontas.
- **Ordens 001–024 deste repo, antes e depois: nenhuma muda de estado.**
- Suíte completa verde em cópia patchada; `habits` por arquivo, um a um;
  `doctor` sem mudança de veredito.
- Recibo `maestro evidence --record --label order-24 -- bash tests/run-all.sh`.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-024 -b feat/024-swarm-primeira-classe main`.
- **TUDO que a ordem muda entra como patch em `docs/patches/`** — `docs/`,
  `tests/` e `config/` inclusive. Um pacote, um diretório, ordem de aplicação.
  Regra do diretor, nascida de três furos: contrato e teste que viajam por
  caminho diferente do código não chegam ao `main`.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`. **Commite.**
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`.
- **`{1,N}` grande em regex bash é ~O(N²)** (issue #42), inclusive `{1,64}`
  repetido por item.
- Grave o essencial em `docs/patches/024-NOTAS.md`.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 024`.

## EMENDA (2026-09-18, changelog oficial v2.1.269+) — o que torna N executores seguros

Três mecanismos do harness entram no desenho. **Nenhum deles é convenção deste
repo hoje** — conferido: os oito agentes de `agents/` usam só
`name`/`description`/`model`/`tools`, e **nenhum** usa os campos abaixo.

**Verifique que funcionam antes de adotar**, e diga no relatório o que você
observou. Adotar flag de changelog sem prova é a mesma classe do precedente
falso que esta sessão já pegou uma vez.

- **`omitClaudeMd: true` para executor ESTREITO** — revisor de log, checagem
  pontual, tarefa de critério objetivo. Corta o CLAUDE.md do contexto dele.
  Ganho: contexto menor, resposta mais rápida, menos chance de o executor
  "lembrar" de regra que não é da tarefa dele. **Não** use em executor que
  precisa das travas do projeto: quem escreve código em `lib/` precisa do
  CLAUDE.md.
- **`memory: project`** onde couber — avalie caso a caso e diga onde coube.
- **Worktree próprio por executor** — já é a prática desde a ordem 012, e é o
  que faz frentes disjuntas serem disjuntas de fato, não por promessa. Com N
  executores no mesmo turno, isso deixa de ser boa prática e vira **requisito**:
  sem worktree por frente, a guarda de colisão vira teatro.

O desenho da ordem deve dizer **qual perfil de executor recebe qual flag**, e o
ledger deve registrar isso — senão a economia de contexto acontece e ninguém
consegue medir se valeu.

## EMENDA — modelo do executor pela COMPLEXIDADE da frente

Decisão do Capitão, 2026-09-18, e vale desde já (aplicada nos despachos daquele
dia, antes desta ordem existir).

**O modelo do executor deixa de ser fixo.** Regra inicial:

| perfil da frente | modelo | effort | frontmatter |
|---|---|---|---|
| estreita e **mecânica** — varredura de log, aplicar patch pronto, checagem pontual | **haiku** | low | `omitClaudeMd: true` |
| **implementação com contrato e TDD** | padrão (sonnet) | medium | — |
| **desenho, revisão final, migração, segurança** | **opus** | high | — |

A `routing-table.yaml` passa a carregar **`model` + `effort` por perfil e por
`depth`**, e o **brief registra qual modelo executou cada frente**, para medirmos
**custo por resultado**. Sem esse registro, a economia acontece e ninguém
consegue dizer se valeu.

### O princípio vence o exemplo

O critério é a **complexidade da frente**, não a etiqueta da tarefa. Caso real do
dia: "papercuts" foi citado como exemplo de tarefa mecânica, mas a ordem 026 como
escrita tem quatro decisões de modelo, mexe em hook e esbarra no teto de injeção
— foi despachada em **opus**, não em haiku. O exemplo estava certo para o
conceito de papercut; errado para aquela ordem.

Escreva isso no mecanismo: quem classifica olha o QUE A FRENTE EXIGE, não o nome
dela.

### A limitação medida, que esta ordem tem de resolver

No despacho de hoje, o gerente controla **`model`** e mais nada. **`effort` e
`omitClaudeMd` não são parâmetros de despacho** — são frontmatter do agente, e
**nenhum dos oito agentes de `agents/` os usa** (conferido: todos têm só
`name`/`description`/`model`/`tools`).

Então a regra acima só vira mecanismo se:

1. os agentes ganharem os campos — **e `agents/` está nas zonas congeladas desta
   ordem**, então isso exige decisão do diretor: ou a zona abre, ou a regra fica
   em outro lugar;
2. a `routing-table.yaml` carregar `model`+`effort` por perfil e por `depth`;
3. o record e o brief passarem a registrar o modelo por frente.

**PARE e chame** se o desenho exigir abrir `agents/` — é zona congelada por
contrato desta ordem, e mudar isso é do diretor.

## EMENDA — a fatura do swarm: frentes que MEDEM correm sozinhas

Decisão do diretor, 2026-09-18, a partir do primeiro swarm real deste projeto.
**Vira regra**, não recomendação.

### O que aconteceu, medido

Seis frentes despachadas em paralelo (025, 018, 023, 019, 026, #42), arquivos
disjuntos, worktree própria cada uma. O trabalho de julgamento acelerou de
verdade — seis ordens fecharam numa janela em que, em série, caberiam duas.

**E a máquina pagou:**

| medida | valor |
|---|---|
| load 1min, pico | **17,4** (8 CPUs — mais de 2 por núcleo) |
| suíte completa, antes | 8m41s |
| suíte completa, sob swarm | 9m52s |
| medições de latência aproveitáveis | **zero** |

A ordem 018 ficou presa ~47 min esperando `tests/run-all.sh` em fila. A 019 e a
026 reportaram **"inconclusivo sob carga"** — corretamente, e é por isso que o
número delas não serve para decidir nada.

### A regra

> **Frentes que DECIDEM paralelizam. Frentes que MEDEM correm sozinhas.**

Declarar frentes disjuntas em **arquivos** não basta — é preciso que sejam
disjuntas em **recurso**. Duas frentes que só leem, pensam e escrevem patch não
competem por nada. Duas frentes que rodam a suíte ou medem latência competem
pela mesma CPU e **envenenam uma à outra**.

O desenho da 024 tem de cobrir isso:

- a declaração da frente diz se ela **mede** (latência, tempo de suíte, sonda) —
  e frente que mede **não entra no mesmo lote** de outra que mede;
- a guarda de colisão passa a olhar **dois eixos**: interseção de arquivos, e
  concorrência de medição;
- quem mede registra o **load junto do número**, e diz "inconclusivo sob carga"
  em vez de reportar valor ruim — é o que o harness do projeto já faz e o que os
  executores fizeram certo sozinhos.

### O que NÃO muda

Isto não é argumento contra swarm — o swarm entregou seis ordens. É a condição
de contorno: **o teto do paralelismo é a máquina**, e ignorá-lo troca velocidade
de decisão por medição inútil, que é o insumo mais caro deste projeto.
