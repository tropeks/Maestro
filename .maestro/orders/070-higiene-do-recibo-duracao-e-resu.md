<!-- maestro-order v1
id: 070
ts: 2026-10-05T22:59:13-03:00
epoch: 1791251953
head: a61f3d368c186f9ee39ea3c0cd2c87460604fced
branch: order/070-higiene-do-recibo-duracao-e-resu
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 070 — higiene do recibo: duracao e resumo do pytest, limiar de carga por CPU e travas de suite

## Por quê

**Item 10 do plano aprovado pelo Capitão em 05/10**
(`/home/rcosta00/dev/spock/docs/pesquisa-metodo-testes-netforge-2026-10-05.md`, seção 4, "Higiene"; mecanismo 8
da seção 3.3). A avaliação da metodologia de testes do NetForge mediu perda de ciclo que **não vem de falta de
máquina, vem de método**, e parte dela é **higiene do recibo** no Maestro:

1. O recibo **não registra quanto a corrida durou** nem **o que o pytest disse** (passou, falhou, pulou): só
   `exit` e árvore. Sem isso a auditoria do recibo é cega, e o "tempo histórico da suíte" que a ordem 057 queria
   (orçamento de CPU) não tem fonte.
2. **O limiar de carga é absoluto (2,00) numa forge de 8 CPUs**: todo recibo sai "fora do limiar"
   (`lib/cmd-evidence.sh`, `_ev_cmd_qualifiers`). Desde a 055 a carga só **qualifica** o texto do recibo, nunca
   o veredito; com o limiar errado o qualificador **deixou de informar** (sempre diz "fora").
3. **A manutenção do host não respeita as travas de suíte.** O exit 125 do recibo da 047 do NetForge coincidiu com
   o `apt upgrade` de `containerd.io` e `docker-ce` na forge (13:07 a 13:09 BRT de 03/10, `/var/log/dpkg.log`):
   a corrida morreu por manutenção, e o recibo ficou como **falha** da suíte.

## O que entrega

Tudo **aditivo e de higiene**: nenhuma camada nova (sem estação, fila ou especialista), nenhuma mudança no
**veredito** da prova (o verificador único da 060 não muda de critério).

### A. Duração e resumo do pytest no recibo

1. O recibo ganha, **além** dos campos de hoje, a **duração da corrida** (`dur_ms`, inteiro, medida no próprio
   `evidence --record` com `EPOCHREALTIME`, sem float) e o **resumo do pytest** quando o comando o imprime:
   `pytest_passed`, `pytest_failed`, `pytest_skipped`, `pytest_errors` (**inteiros**, lidos da linha-resumo final
   do pytest, ex.: `12 passed, 1 skipped in 8.3s`) e `pytest_secs` (os segundos **em centésimos inteiros**: `830`,
   nunca `8.3`). Comando que **não** é pytest **não** ganha os campos (ausentes, não zero).
2. **Formato:** campos novos no **fim** do arquivo do recibo, no mesmo estilo `chave=valor`. **Compatível:** recibo
   antigo sem os campos segue lido; o leitor ignora campo que desconhece; o veredito não usa nenhum deles.
3. **`evidence --check`** imprime a duração e o resumo como **informação** (como já faz com a idade), sem reprovar.
4. **Sem float em métrica de custo** (regra do projeto): milissegundos e centésimos inteiros.
5. A captura da saída do comando **não pode mudar o comportamento dele** (mesmo `exit`, mesma saída no terminal);
   o resumo é lido do que já passa pelo `tee` de hoje.

### B. Limiar de carga por CPU

1. O limiar passa de **absoluto** para **por CPU**: compara `load1m_x100 / ncpu` (inteiros) contra um limiar por
   CPU. O recibo já grava `load1m_x100` e `ncpu`; o qualificador ", mas fora do limiar de medição" só aparece
   quando a carga **por CPU** passa do limiar.
2. **O valor padrão sai de medição, não de palpite:** o executor mede a carga típica da forge e do ambiente do
   Capitão (`/proc/loadavg`, `nproc`) e cola. Candidato inicial: **1,00 por CPU** (100 em ×100). **O valor
   final é decisão do Diretor** (Ask-First).
3. **Override** por ambiente preservado (o nome que já existe), e o aviso "carga já fora do limiar ANTES de
   medir" (`_ev_cmd_preload_warn`, ordem 024) usa o **mesmo** cálculo por CPU: uma só implementação.
4. **Não muda** o limiar de **latência** de `tests/lib/latency.sh` (ordem 016, calibrado por sonda): é outro
   mecanismo, para outra pergunta.

### C. Manutenção do host e as travas de suíte

1. **Mapear primeiro, colar:** onde vivem as "travas de suíte" (lock dos scripts de recibo do NetForge, o
   `deploy-holder`, o `flock` da forge) e quem faz a manutenção do host (`apt upgrade`, restart de docker). A
   fonte da pesquisa aponta para **scripts e infra de outro repo**, não para o CLI do Maestro.
2. **O que é do Maestro:** (a) o recibo **distingue corrida interrompida por manutenção de falha da suíte**
   quando houver um sinal confiável (ex.: `exit` 125/126/137 com o daemon do docker reiniciado na janela da
   corrida), gravando o fato como **qualificador** (`interrompido=host`), **nunca** alterando o veredito; (b) um
   **contrato de uma página** em `docs/` (protocolo da trava: quem a segura, como a manutenção a respeita antes
   de reiniciar serviço) para os donos da infra aplicarem.
3. **O que NÃO é desta ordem:** mudar o script de manutenção do host ou as travas no repo/infra deles. Se o mapa
   mostrar que a trava vive fora do Maestro, a entrega do item C é o **contrato e o qualificador**, e o conserto
   no host vira ordem do outro repo.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-order-070-recibo-duracao-pytest.sh`] `evidence --record` de um comando que imprime
  um resumo de pytest grava `dur_ms` e os cinco campos `pytest_*` **inteiros**; comando não-pytest não os grava;
  recibo antigo (sem os campos) segue lido e o **veredito não muda**; `--check` mostra duração e resumo sem
  reprovar. **Vermelho antes** (o recibo não tem os campos), colado.
- [oráculo: `bash tests/cli/test-order-070-limiar-por-cpu.sh`] com `ncpu` 8, load 7,50: **dentro** do limiar de
  1,00 por CPU (hoje diz "fora"); com load 12,00: **fora**; o aviso prévio e o qualificador usam o **mesmo**
  cálculo; override por ambiente continua valendo; só inteiros.
- [oráculo: `bash tests/cli/test-order-070-interrompido-host.sh`] corrida com `exit` de interrupção e o sinal de
  reinício de serviço na janela grava `interrompido=host` **e** o veredito segue **VENCIDO** pelo `exit ≠ 0` (o
  qualificador informa, não perdoa); sem o sinal, nada é afirmado.
- [oráculo: `bash tests/cli/test-order-055-carga-nao-invalida.sh`, `bash tests/cli/test-order-060-verificador-unico.sh`
  e `bash tests/cli/test-evidence.sh`] seguem verdes: **o veredito não regride**.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [humano] o Diretor lê o limiar por CPU medido e o contrato da trava.

## Ask-First

- **Congelamento da v59.** O INTENT v59 (item 1) congela estação, fila, especialista e empresa plugável novos até
  o gate, e o item 3 lista o que entra antes dele. Esta ordem **não cria nenhuma camada** (higiene aditiva de
  campo e de limiar) e vem **aprovada pelo Capitão em 05/10** (plano, item 10), como as ordens 059/062/082.
  O INTENT carimbado no repo é a v6; **a emenda que registra a exceção no INTENT é do Diretor**. Se o executor
  achar que algum passo cria camada nova, PARE.
- **O valor do limiar por CPU** é decisão do Diretor: cole a medição e o candidato; não o fixe sozinho.
- **Mudança de formato do recibo (campos novos):** é aditiva e compatível; se algum leitor existente **quebrar**
  com campo desconhecido, PARE (DATA_MODEL).
- Se o sinal de "interrompido por host" **não** puder ser distinguido de forma confiável, **não o grave**: o item
  C vira só o contrato e o mapa, e o relatório diz por quê.
- **Toca `lib/` (autoprotegida):** a entrega é **UM patch** em `docs/patches/070-*.patch`, feito em clone sandbox
  FORA do repo, testado antes e depois, aplicado pelo Capitão com um `git apply`; `git apply --check` no
  worktree. `tests/` e `docs/` direto no branch.
- **Fora desta ordem:** os scripts de recibo do NetForge (`exit=$?` depois de `$(date)`, repetir o rótulo até
  passar, o `( … ) & sleep 1`): são de outro repo e já estão no plano (itens 1 e 4).
- Logs: **só metadados**; nada de saída do comando no log nem caminho completo.

## Como sai

Os testes e as emendas de docs direto no branch; o recibo e o limiar em **UM patch protegido**. Emendas no mesmo
changeset: DATA_MODEL (campos novos do recibo, aditivos), API_SPEC (`evidence --check` mostra duração e resumo;
o limiar por CPU), o contrato da trava em `docs/` e o CHANGELOG (Changed/Added). Papercut: "todo recibo sai fora
do limiar numa forge de 8 CPUs".

## Prova exigida

- Os três testes novos vermelhos antes e verdes depois, saídas coladas; os de veredito (055, 060, evidence) verdes.
- A medição do limiar por CPU (carga típica, `nproc`) e o mapa das travas.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-70` no tip com o patch aplicado e
  `maestro order --status 70` VÁLIDA.

## Turno

- fatia: os testes vermelhos de duração e resumo do pytest e do limiar por CPU, o conserto em `lib/core-evidence.sh` e `lib/cmd-evidence.sh` no sandbox e o mapa das travas de suíte
- fim: `test-order-070-recibo-duracao-pytest` e `test-order-070-limiar-por-cpu` saem 1 antes (colado) e 0 depois, no sandbox; os testes de veredito (055, 060, evidence) verdes; o mapa das travas colado; patch protegido pronto e `git apply --check` ok; `bash tests/run-all.sh` completa no sandbox sai 0
- teto: 4
- fora: mudar o veredito da prova, fixar o valor final do limiar sem o Diretor, mexer nas travas ou na manutenção do host (outro repo), scripts do NetForge, camada nova, aplicar o patch e tocar vendor/
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
> (run_in_background da ferramenta Bash) e a espera é por Monitor; o recibo já grava o código de saída.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. A suíte roda como uma chamada só
> (`maestro evidence --record --label order-N -- <suíte>`) em segundo plano, pelo `run_in_background` da
> ferramenta Bash, e a espera é por **Monitor**; o recibo já grava o código de saída. Só depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/070-higiene-do-recibo-duracao-e-resu`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-70 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), Prioridade 3 (trilho onde o trilho alcança), com o aval do Capitão de 05/10 ao plano (item 10) como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 070` (você não fecha a própria ordem).
