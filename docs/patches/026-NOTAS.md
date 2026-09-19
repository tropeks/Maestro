# Ordem 026 — papercuts compartilhado: notas de execução

Branch `feat/026-papercuts`, regenerado contra **`9812dec`** (main com #42, 025
e 018 dentro). `hooks/`, `bin/`, `config/` e `tests/` são aplicados por mão
humana a partir de `docs/patches/026-papercuts/`.

| # | patch | alvo |
|---|---|---|
| 01 | `01-hooks-lib-project-state.patch` | `hooks/lib/project-state.sh` — derivação do caminho |
| 02 | `02-hooks-lib-papercuts-novo-modulo.patch` | `hooks/lib/papercuts.sh` (novo) — o escritor |
| 03 | `03-hooks-session-start.patch` | `hooks/session-start.sh` — linha da injeção **+ bootstrap de máquina vazia** |
| 04 | `04-bin-maestro-despachante.patch` | `bin/maestro` — `maestro papercut` |
| 05 | `05-config-communication-style-corte.patch` | `config/communication-style.md` — o corte compensatório |
| 06 | `06-tests-order-026-novo.patch` | `tests/hooks/test-order-026-papercuts.sh` (novo) — **inclui as asserções do bootstrap** |
| 07 | `07-tests-injection-budget-ratchet.patch` | `tests/hooks/test-injection-budget.sh` — ratchet 7400 → **7317** |

**Um patch por ARQUIVO, e a ordem de aplicação não importa.** Os sete tocam sete
arquivos disjuntos e cada um aplica sozinho sobre `9812dec` limpo — não há patch
incremental sobre patch neste pacote.

O pacote anterior tinha dez patches, e os três últimos (`08`–`10`) eram
incrementais sobre o estado pós-`07`: o `08` só casava com `hooks/session-start.sh`
**depois** do `03`. Aplicado fora de sequência, falhava em
`hooks/session-start.sh:786` com "patch does not apply" — o sintoma que travou a
aplicação. Medido nesta regeneração, num clone de `9812dec`: `08` sozinho falha;
`01..07` + `08` aplica. Os patches estavam certos; a armadilha era a numeração
valer como ordem obrigatória sem dizer isso. A fusão por arquivo (03+08, 06+09,
07+10) tira a armadilha da mesa em vez de documentá-la.

**Verificação da regeneração** (contra `9812dec`):

- cada um dos 7 aplica **sozinho** em clone limpo — 7/7;
- os 7 aplicados em **ordem reversa** produzem árvore byte-idêntica à dos 10 em
  ordem, nos sete arquivos, sem sujeira extra no `git status`;
- suíte completa na árvore resultante: **`SUITE OK`**, exit 0, zero FAIL
  (as 7 ocorrências de "FAIL" no log são nomes de teste, todas com veredito `ok`);
- `maestro doctor`: `injeção SessionStart: 7333B de 8000B`, o número previsto
  para o cenário de registro vazio.

A única divergência contra a árvore de `/tmp/wt-026` é `bin/maestro`, e é
esperada: são as 33 linhas do `check_order_identifiers` que a 018 trouxe para
`main` depois de `c41fb6f`. O pacote não a toca.

---

## Decisão 1 — onde o arquivo mora

**`$MAESTRO_HOME/papercuts.md`, arquivo único, SEM chave por projeto.**

`MAESTRO_HOME` (default `~/.maestro`) já é o endereço de tudo que é da máquina:
`logs/`, `sessions/`, `config.yaml`, `update-state`, `capabilities.json`. Não se
inventou endereço novo nem env nova — o override de `MAESTRO_HOME` é o que
torna a suíte hermética de graça.

Contra a convenção de chave por projeto (`<slug>-<hash8>`, `hooks/lib/project-state.sh`):
brief, evidência e order-state respondem **"onde este PROJETO está"** e por isso
são chaveados. Um papercut responde **"o que esta MÁQUINA faz de errado"** —
versão de ferramenta instalada, código de saída, bug de harness, guarda local
calibrada demais. Chavear por projeto faria os nove gerentes pagarem a MESMA
investigação nove vezes, que é literalmente a falha que a ordem existe para
fechar. Então: arquivo único, e a procedência ("em que projeto eu bati nisto")
vira **campo da linha**, não nome de arquivo — a informação não se perde, ela só
deixa de particionar o registro.

A derivação é única (`maestro_set_papercuts_file`, em `project-state.sh`, ao lado
das três chaveadas — o contraste documentado no comentário é metade do valor),
com duas formas: publica em variável para o hook (zero fork, caminho quente) e
escreve no stdout para o CLI.

## Decisão 2 — o orçamento da injeção

**Vai CONTAGEM + ponteiro + gatilho. Uma linha, sempre do mesmo tamanho.**

```
papercuts: 5 (~/.maestro/papercuts.md) → ferramenta falhou estranho: leia ANTES de investigar; conserto novo: maestro papercut --add
```

Nenhum dos dois extremos serve, e a razão de cada recusa:

- **Conteúdo inteiro: proibido.** Cinco papercuts já são ~800B; cinquenta não
  cabem em orçamento nenhum. Uma linha que cresce com o arquivo mata os 8000B
  sozinha, e o INTENT v3 põe esse teto fora de negociação por texto expresso.
- **Nada, com leitura sob demanda: não funciona.** O gerente só leria se
  soubesse que o arquivo existe — e quem não sabe, investiga do zero. É o
  estado de hoje, com um arquivo a mais.
- **Ponteiro sozinho: fraco.** "Existe um arquivo" não puxa ninguém. O número é
  o que diz que o registro está VIVO e vale o `Read`.

A propriedade que fecha a conta: **a contagem é O(1) em dígitos.** O papercut nº
50 custa o mesmo que o nº 5 (+1B pelo dígito, medido no teste). Esta seção nunca
mais precisa ser renegociada com o orçamento. É o mesmo princípio do brief
(E8/S-802) e do INTENT (E22): a injeção carrega a GARANTIA de que o estado
existe; o conteúdo se lê sob demanda — que aqui é exatamente o momento em que a
ferramenta falha.

### Bootstrap de máquina vazia (2ª rodada — decisão do diretor)

Na primeira rodada eu recusei o anúncio em máquina vazia **por preço** e registrei
a recusa como decisão do diretor. Ele decidiu: **entra.** A razão é boa e eu a
subestimei — máquina nova é exatamente onde o gerente mais precisa saber que o
mecanismo existe, e é onde ele não descobre por caminho nenhum, porque o único
anúncio seria a linha que **só nasce depois do primeiro registro**. O mecanismo
tinha um ovo-e-galinha na raiz.

```
papercuts: 0 → consertou falha estranha de FERRAMENTA? maestro papercut --add
```

**Preço real: 80 B** (eu havia estimado ~90 B). O desenho mais barato saiu de
perguntar o que serve a quem **não tem o que ler**: o ponteiro sai (não há
arquivo para abrir) e o "leia ANTES de investigar" sai (não há o que consultar).
Ficam as três coisas que a máquina vazia precisa — o **nome** (`papercuts`), o
**gatilho** (falha estranha de FERRAMENTA, em caixa alta, que é a fronteira do
critério) e o **verbo**. Contra os 135 B da linha cheia.

A gramática é a mesma nos dois estados (`papercuts: <n> → …`): quando o número
sair de 0 para 7, o gerente já sabe o que ele conta.

**Ilegível continua MUDO** — e agora é o único estado que não emite nada. Dizer
"0" para um arquivo que existe e não se consegue ler seria mentir a contagem, e
o Maestro não finge estado (mesma regra do `direção: nenhuma` no E22 e do
`no-stable` no E19). Ausente, vazio e só-cabeçalho emitem o bootstrap.

**A conta, em bytes medidos nesta forge (`wc -c` da injeção):**

| cenário | baseline (c41fb6f) | patched | delta |
|---|---|---|---|
| máquina COM papercuts (`~/.maestro`, 5 registros) | 7400 B | **7372 B** | **−28 B** |
| máquina de registro VAZIO, com bootstrap (cenário do ratchet) | 7400 B | **7317 B** | **−83 B** |
| `maestro doctor` (mesmo cenário vazio, session_id +16 B) | 7416 B | **7333 B** | −83 B |
| ratchet novo | 7400 | **7317** | — |

Os dois cenários vivos ficam **abaixo** do baseline de 7400 B: o corte de 163 B
paga a linha cheia (+135 B) **e** o bootstrap (+80 B), e ainda sobra. Nenhum
corte compensatório adicional foi necessário — não precisei parar e perguntar.

**O corte compensatório (Prioridade 5): −163 B em `config/communication-style.md`.**
Saíram as duas linhas da regra de TIPOGRAFIA ("Formato serve ao conteúdo: lista
numerada só para sequência real, tabela só para fatos curtos, `código` para
comando e path, negrito para elemento de UI"). Dois motivos:

1. **Não se perde a regra.** A linha que ficou já diz "Base: Google developer
   documentation style guide" — a tipografia mora lá inteira. A injeção pagava
   bytes para repetir por extenso o que a referência nomeada já entrega.
2. **É a moeda que este repo já usou.** O bump anterior do ratchet (E26/S-2602)
   se pagou exatamente assim: "quatro linhas de tipografia viraram uma só,
   −172B… regra de comportamento vale mais que regra de formatação, e o corte
   foi a forma de dizer isso com o byte."

A adição custa +135 B só onde há papercuts; o corte devolve 163 B em todo lugar.
O líquido é negativo nos dois cenários — a injeção sai desta ordem **menor** do
que entrou.

**O buraco que isto abre, e o guarda que o fecha.** O ratchet compartilhado e o
`doctor` medem a injeção com `MAESTRO_HOME` em `mktemp` — hermético, sem
papercuts. A linha de papercuts é a **primeira** coisa da injeção que depende do
estado de `$MAESTRO_HOME`, e portanto é invisível para os dois medidores: 135 B
reais entrariam em produção sem que nenhum deles visse. Por isso
`test-order-026-papercuts.sh` cobra o cenário de produção **com fixture**
(`MAESTRO_HOME` sob um `HOME` falso, ponteiro encurtado em `~/`) contra o
ratchet que valia ANTES da ordem (7400 B) e contra o teto duro de 8000 B.
Não se mexeu no `doctor` — mexer mudaria o número que ele reporta em toda
máquina, e mudança de veredito do doctor é trava desta ordem.

O ratchet desceu 7400 → 7237 na primeira rodada e subiu para **7317** com o
bootstrap (é o cenário de registro vazio que ele mede). Deixá-lo em 7400 seria
guardar folga em silêncio para a próxima adição — o oposto do que a catraca
existe para fazer. Ordem preservada: **ratchet 7317 < warn 7500 < teto 8000**.

## Decisão 3 — quem escreve

**Escritor único: `maestro papercut --add "<sintoma>" --fix "<conserto>"`**, que
valida, deduplica por sintoma e apende sob `flock`.

`>>` direto de cada sessão quebra em dois pontos: (a) a checagem de duplicata é
leia-depois-escreva, e duas sessões que batem no MESMO papercut gravam as duas;
(b) sem validação, o critério da decisão 4 vira decoração e o arquivo é despejo
em duas semanas. "Só o humano escreve" morre pelo outro lado: o custo de
registrar no instante da descoberta tem de ser quase zero, ou ninguém registra.

A seção crítica cobre **leitura + escrita** — é esse o ponto, não só o append.
Diferença deliberada para o `log_event` do `common.sh`: lá, contenção
**descarta** a linha (telemetria; perder um evento é barato). Aqui não se
descarta nada — um papercut perdido é a investigação repetida que a ordem existe
para evitar. Por isso `flock -w 5`, com espera, e não `flock -n`.

Sem `flock` na máquina, o append de uma linha curta em fd `O_APPEND` continua
atômico (write único < PIPE_BUF) e **só a deduplicação degrada**: o pior caso é
uma linha repetida, nunca uma corrompida nem uma perdida. O teste cobre os dois
regimes.

**Concorrência testada de verdade** (`tests/hooks/test-order-026-papercuts.sh`):

- 12 processos `maestro papercut --add` simultâneos, sintomas distintos → 12
  linhas, todas começando por data, todas com exatamente 4 campos (nenhuma
  entrelaçada), nenhuma duplicada, e o cabeçalho escrito **uma vez só** apesar
  de 12 criadores concorrentes.
- 8 processos simultâneos com o **mesmo** sintoma → **1 linha**. É a corrida que
  o `>>` direto perderia.

## Decisão 4 — o que NÃO entra

O critério mora em dois lugares, e o segundo é o que importa:

1. **No topo do próprio arquivo**, onde é lido — quem abre `papercuts.md` para
   consultar vê, antes do primeiro registro, o que não entra ali.
2. **Executado pelo escritor.** Critério que só existe em documentação é
   critério que não existe.

```
ENTRA: a ferramenta falhou de um jeito que não se deduz do sintoma e o conserto
já é conhecido — versão com regressão, código de saída fora da tabela, guarda
que barra o que devia passar, comando que conta o que não devia.

NÃO ENTRA:
  bug do PROJETO ............. é issue (tem dono e morre quando for corrigido)
  lição de MÉTODO ............ é brief (como se trabalha, não o que quebrou)
  armadilha de CÓDIGO ........ é comentário no código (quem edita tem de ver)
  sintoma SEM conserto ....... é investigação em aberto — abra issue
  caminho absoluto, segredo ou conteúdo de prompt ......... nunca

Teste: outro gerente, em outro projeto, bate no MESMO sintoma amanhã. Se a linha
não poupa a investigação dele, não é papercut — some com ela.
```

Recusas mecânicas (rc 1, com a mensagem ensinando o critério): `--add` sem
`--fix` ("sintoma sem conserto conhecido não é papercut: é investigação em
aberto — abra uma issue"); caminho **absoluto** em qualquer campo (caminho
relativo passa: `hooks/lib/common.sh` é referência útil, `/home/fulano/...` é
metadado de outra máquina — mesma família de regra do `log_event`); `·` dentro
de campo (é o separador); caractere de controle; campo acima de 120/240
caracteres; slug de projeto fora do formato.

## Conteúdo inicial — os cinco papercuts de 2026-09-18

Gravados em `~/.maestro/papercuts.md` **pelo próprio CLI** (é o caso de uso real
e a prova de que o formato serve). Não vão versionados no plugin de propósito:
papercut é estado de MÁQUINA, e embutir os desta forge no repo os entregaria a
toda instalação como se fossem verdade universal — o mesmo motivo pelo qual
brief e evidência não são versionados.

```
2026-09-18 · leitura de pane do tmux volta VAZIA na 2.1.277 · regressão do harness de leitura, não da sessão: confirme a versão antes de culpar o comando e releia por outro caminho — a pane não está vazia · ponte
2026-09-18 · carimbo de estado terminal da ordem some depois do merge · o carimbo vivia como modificação não commitada na árvore; a fonte é o registro fora da árvore (ordens 021/022) — pergunte ao maestro order --status --json, não ao arquivo · maestro
2026-09-18 · pkill sai 144 · 144 não está na tabela do pkill (0/1/2/3): é 128+sinal, quem morreu foi o processo — confira o casamento do padrão com pgrep antes de investigar o comando · ponte
2026-09-18 · classificador de risco barra LEITURA do ponte.db · consulta com certos filtros é lida como transação real; reformule com SELECT explícito e sem palavra de escrita no texto, ou peça consentimento escopado — não é falha do banco · ponte
2026-09-18 · wtree conta arquivo não rastreado e o recibo de main nasce VENCIDO · árvore suja muda o wtree: limpe ou ignore o não rastreado antes de gravar a evidência, ou grave o recibo com a árvore limpa · maestro
```

O formato de quatro campos aguentou os cinco sem reescrita. Os consertos foram
escritos no nível de certeza que a ordem de fato traz — onde só se sabe
reconhecer, a linha diz como reconhecer, que já é o que poupa a investigação.

## O trade-off que virou decisão

Ficou registrado como pendência do diretor e ele decidiu na 2ª rodada: o
bootstrap **entra**, a 80 B (ver a seção da decisão 2). O que eu havia pesado
como "custo puro em máquina vazia" era, do ângulo dele, o único momento em que a
descoberta importa — e o desenho ficou 10 B mais barato do que a estimativa
justamente porque o alvo mudou de "anunciar o registro" para "ensinar o
mecanismo a quem não tem o que ler".

## Fora de escopo, por decisão

- **`maestro doctor` não ganhou checagem de papercuts.** Mudança de veredito do
  doctor é trava da ordem, e o doctor não tem o que cobrar de um registro cuja
  ausência é um estado legítimo.
- **Sem seção própria (`## Papercuts`) na injeção.** O cabeçalho custaria bytes
  para zero informação; a linha entrou em `## Projeto`, que é a seção de
  inteligência situacional ("o que você precisa saber antes de começar"), e o
  ponteiro `~/.maestro/…` já diz que o escopo é a máquina.
- **O módulo ficou em `hooks/lib/`, não em `lib/`.** Precedente do `upgrade`,
  que sourceia `hooks/lib/update-check.sh`: é estado de máquina sob
  `$MAESTRO_HOME`, a mesma família do `common.sh`. O hook **não** sourceia o
  módulo — só o CLI. O caminho quente do `session-start` não paga nada por ele.
