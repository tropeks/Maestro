<!-- maestro-order v1
id: 069
ts: 2026-10-05T17:44:50-03:00
epoch: 1791233090
head: a61f3d368c186f9ee39ea3c0cd2c87460604fced
branch: order/069-comando-simples-no-turno-um-coma
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
deferred_by: spock 2026-10-06 troca pela 051 do NetForge
-->
# Ordem 069 — comando simples no turno: um comando por chamada de Bash

## Por quê

**Método autorizado pelo INTENT v61** (a direção do Diretor; o INTENT carimbado no repo é a v6, a base). **Dado
vivo do replay da 093 no ponte-daemon** (dado do Capitão; o replay vive no outro repo e **não é reproduzido
aqui**): dos **731 pedidos de permissão dos turnos, 543 são comandos compostos** (`cd x && …`, pipe para `tail` ou
`head`, `2>&1`) e **609 caem em T3**. Consequência medida: **o Jev não consegue julgar quase nada** e **tudo sobe ao
Diretor**. O pedido de permissão do comando composto é a parte cara do ruído: um comando simples é julgável
(leitura, escrita em área segura, comando conhecido); um `cd x && cmd | tail` mistura três intenções numa chamada e
só pode ser julgado inteiro, no pior caso.

O turno é onde esses compostos nascem: o executor escreve o hábito de shell que lhe é natural. A regra tem de estar
**onde o executor lê**: no **esqueleto do bloco `## Turno`** (que todo `maestro order --create` emite) e no
**ENGINEERING_SPEC** (a fonte normativa).

## O que entrega

**A regra, em cinco cláusulas** (decisão do Diretor; a 4 e a 5 fechadas em 05/10), escrita **igual** nos dois lugares:

1. **Um comando por chamada de Bash.** Sem `&&`, `;` nem `||` encadeando comandos distintos.
2. **Caminho absoluto em vez de `cd` e `&&`.** Em vez de `cd /x && cmd`, `cmd /x/…` (ou `git -C /x …`).
3. **Sem pipe para cortar saída.** Nada de `| tail` e `| head`: a ferramenta já corta a saída.
4. **A suíte roda como UMA chamada só, em segundo plano, e a espera é por Monitor.** O comando é
   `maestro evidence --record --label order-N -- <suíte>`, lançado em segundo plano pelo **`run_in_background` da
   ferramenta Bash** (nada de subshell, `&` nem `echo rc=` encadeado); a espera é por **Monitor**. O recibo **já
   grava o código de saída**, então o `rc=` no log deixa de ser necessário.
5. **`2>&1` é permitido.** Ele **junta saídas, não grava arquivo**; não é composição de comandos e não entra na
   regra de "um comando por chamada".

### No esqueleto do Turno (núcleo, `lib/core-order-turno.sh`)

`_order_turno_skeleton` passa a emitir, **depois** das duas linhas citadas que já existem (`Log e escrita`, 062;
`Headless`, 064), uma **terceira** linha citada, **na mesma forma** (blockquote, **não rótulo**, para o `conform` e o
Stop de turno não a lerem como campo do Turno):

`> **Comando simples:** um comando por chamada de Bash; caminho absoluto em vez de cd e &&; sem pipe para cortar
saída (| tail, | head), a ferramenta já corta; 2>&1 é permitido (junta saídas, não grava arquivo); a suíte roda
como uma chamada só, maestro evidence --record --label order-N -- <suíte>, em segundo plano (run_in_background da
ferramenta Bash) e a espera é por Monitor; o recibo já grava o código de saída.`

**E a linha `Headless` da 064 é reescrita no MESMO patch**, porque ela mandava esperar "por laço até a linha
`rc=` no log" (a convenção que sai). O texto novo, na mesma forma de linha citada:

`> **Headless:** nunca encerre a resposta esperando uma notificação. A suíte roda como uma chamada só (maestro
evidence --record --label order-N -- <suíte>) em segundo plano, pelo run_in_background da ferramenta Bash, e a
espera é por Monitor; o recibo já grava o código de saída. Só depois se relata.`

### No ENGINEERING_SPEC

Em "O turno da ordem e o relatório de fim de turno (ordem 046)", um parágrafo **Comando simples (ordem 069)** com as
cinco cláusulas (incluindo a suíte como uma chamada só e o `2>&1` permitido), o **dado do replay da 093** (731/543/609, citado como dado do Capitão) e o porquê (o Jev só julga
o que é simples). Uma só vez; o esqueleto aponta para ele.

### O teste que prova a regra no esqueleto gerado

`tests/cli/test-order-069-esqueleto-comando-simples.sh` roda `order --create` numa **fixture** e afirma que a ordem
**gerada** contém a linha `Comando simples` com **cada uma das cláusulas** (um comando por chamada; caminho absoluto em
vez de `cd`/`&&`; sem pipe para cortar saída; `2>&1` permitido; a suíte como uma chamada só em segundo plano com
espera por Monitor), que os **cinco rótulos** do Turno seguem os mesmos e preenchíveis, que a linha `Log e escrita`
segue presente, que a linha `Headless` traz o **texto novo** (`run_in_background`, Monitor, recibo grava o código
de saída) e **não menciona mais `rc=`**, e que o `conform --check` **não acusa** nenhuma das linhas. **Vermelho
hoje** (o esqueleto não traz a linha nova e a `Headless` ainda manda esperar o `rc=`), saída colada; verde depois.
Os testes do esqueleto das ordens 046 e 062 seguem verdes; o de 064 (`test-order-064-esqueleto-headless.sh`) é
**ajustado ao texto novo** da `Headless` e a mudança é listada no relatório.

## O que fica de fora (e por quê)

- **Não** mecanizar a regra (nenhum hook novo que bloqueie composto): é regra de método, escrita; um guard é
  outra ordem e tem custo de falso positivo (os 543 compostos incluem formas legítimas).
- **Não** reproduzir nem refazer o replay da 093: vive no ponte-daemon. Medir o "depois" (fração de pedidos
  compostos) é de outra ordem, naquele repo, depois que a regra circular.
- **Não** alterar ordens já escritas: só o esqueleto das **novas**.

## Ask-First

- **Decidido pelo Diretor (05/10), não reabra:**
  1. **A convenção `rc=` sai.** A suíte roda como **uma chamada só**,
     `maestro evidence --record --label order-N -- <suíte>`, em segundo plano pelo `run_in_background` da
     ferramenta Bash, e a espera é por **Monitor**; o recibo já grava o código de saída. A linha `Headless` da
     064 é **reescrita no mesmo patch** (texto no item "No esqueleto do Turno"), e este bloco Turno já a segue.
  2. **`2>&1` é permitido**: junta saídas, não grava arquivo. A regra o diz.
- **Já escritas, não mexa:** as ordens 060, 062 e 064 e seus Turnos continuam com o texto antigo do `rc=`; só o
  **esqueleto das novas** muda. Liste no relatório onde mais a convenção antiga aparece (ENGINEERING_SPEC,
  ordens abertas) para o Diretor decidir a limpeza; **não** a reescreva fora do esqueleto e do parágrafo da 069.
- **Toca `lib/core-order-turno.sh` (autoprotegida):** a entrega é **UM patch** em `docs/patches/069-*.patch`,
  feito em clone sandbox FORA do repo, testado antes e depois, aplicado pelo Capitão com um `git apply`;
  `git apply --check` no worktree. `tests/` e `docs/` direto no branch.
- A linha nova **não pode estourar** `lib/core-order-turno.sh` acima do teto de 400 linhas nem criar função acima
  de 60 (catraca do `habits` é aviso desde a 062, mas não a ignore: reporte o número).

## Como sai

O teste e o ENGINEERING_SPEC (e a nota no API_SPEC se o contrato do esqueleto estiver lá) direto no branch; a
linha do esqueleto em **UM patch protegido**. Emendas no mesmo changeset: ENGINEERING_SPEC (a regra), CHANGELOG
(Changed). Papercut: "comando composto no turno sobe tudo ao Diretor".

## Prova exigida

- O teste vermelho antes (colado) e verde depois; os testes de esqueleto de 046, 062 e 064 verdes.
- O `order --create` de uma fixture mostrado com a linha nova (saída colada).
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-69` no tip com o patch aplicado e
  `maestro order --status 69` VÁLIDA.

## Turno

- fatia: o teste vermelho do esqueleto, a linha `Comando simples` e a nova linha `Headless` (a convenção rc= sai) no esqueleto (sandbox), o ajuste do teste da 064 e o parágrafo do ENGINEERING_SPEC
- fim: `bash tests/cli/test-order-069-esqueleto-comando-simples.sh` sai 1 antes (colado) e 0 depois, no sandbox; os testes de esqueleto de 046 e 062 verdes e o da 064 ajustado e verde; patch protegido pronto e `git apply --check` ok; `bash tests/run-all.sh` completa no sandbox sai 0
- teto: 3
- fora: mecanizar a regra em hook ou guard, reescrever o `rc=` fora do esqueleto e do parágrafo da 069, reproduzir o replay da 093, alterar ordens já escritas, aplicar o patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54,
> com o sha do tip). Terminar a resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível,
> **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou
> redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e medir.
> Patch gerado por `git diff` do sandbox para `docs/patches/` é a única saída por redirecionamento admitida.

> **Comando simples:** um comando por chamada de Bash; caminho absoluto em vez de cd e &&; sem pipe para cortar
> saída (| tail, | head), a ferramenta já corta; 2>&1 é permitido (junta saídas, não grava arquivo); a suíte roda
> como uma chamada só, maestro evidence --record --label order-N -- <suíte>, em segundo plano
> (run_in_background da ferramenta Bash) e a espera é por Monitor; o recibo já grava o código de saída. (Esta
> ordem aplica a regra que entrega: o executor a segue já neste turno.)

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. A suíte roda como uma chamada só
> (`maestro evidence --record --label order-N -- <suíte>`) em segundo plano, pelo `run_in_background` da
> ferramenta Bash, e a espera é por **Monitor**; o recibo já grava o código de saída. Só depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/069-comando-simples-no-turno-um-coma`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-69 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), Prioridade 3 (trilho onde o trilho alcança), com o método do INTENT v61 como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 069` (você não fecha a própria ordem).
