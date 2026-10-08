<!-- maestro-order v1
id: 076
ts: 2026-10-07T16:08:57-03:00
epoch: 1791400137
head: dc31a58f0b99f6d28aba7e14c6e418466bc4b1c5
branch: order/076-prova-da-ponte-sobre-mods-gerent
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 076 — prova da Ponte sobre mods: gerente pede, diretor responde por session.send

## Por quê

**Aprovada pelo Capitão em 07/10.** Os controles migram para mods (ordens 072–075). Falta provar a peça que mais pesa na Ponte: o **gerente pede
permissão e o Diretor responde sem passar por `herdr pane run` nem pelo `--permission-prompt-tool`**, pelas mensagens entre sessões do Claude Code
(`$.session.send` e o evento `session.receive`). Hoje o Diretor é acordado escrevendo na pane; cada pedido é um turno de modelo. Esta ordem é uma
**prova de conceito medida**, com critérios escritos antes e não renegociados. Ela **não** muda o ponte-daemon de produção.

**O ponto que manda no desenho (documentação oficial, Claude Code 2.1.293): "o nome do remetente numa mensagem recebida é o que o remetente
escreveu; não baseie uma decisão nele".** Então a identidade **não pode vir da mensagem**. Ela vem de fora, como já vem no daemon: o
`SO_PEERCRED` do socket dá o PID do peer, o daemon sobe `/proc/<pid>/stat` até o processo `claude` e confere a pane (ST13); quem não bate recebe
`403 not_director` ou `self_approval`. A prova repete esse mecanismo **em miniatura e fora da produção**.

## O que entrega

Um plugin de mod `maestro-prova` (`mods/maestro-prova/`: plugin.json, `hooks/hooks.json`, `hooks/register.js`, `tests/*.test.ts`), com **dois papéis**
escolhidos por variável de ambiente lida no load (`$.env.get`): `diretor` e `gerente`. Mais o aparelho de prova em `tools/prova-ponte-mods/`.

1. **Gerente de teste.** Hook de `tool.check` que, para a chamada que cairia em `ask`, não sobe ao humano: gera um pedido `{rid, classe, hash}`
   (`rid` de 128 bits por `crypto.subtle`; **`hash` é o sha256 da entrada da ferramenta, nunca o comando**), **registra o pedido no verificador**
   (item 3) e o envia ao Diretor por `$.session.send`. Espera a decisão **no máximo 8 s** (menos que o limite de 10 s do hook). Resposta `allow` válida →
   devolve `allow`; `deny` válida → `deny`; **timeout, resposta inválida, erro, `throw` → `deny`** (nunca `allow`, regra da 072) com `.catch`.
2. **Diretor.** Hook de `session.receive`: lê o pedido, **verifica a identidade fora da mensagem** (item 3), decide por **função pura** (tabela
   versionada no mod: leitura em pasta liberada → `allow`; escrita em caminho protegido, segredo, rede → `deny`; o resto → `deny`) e responde por
   `$.session.send`, registrando a decisão no verificador. **Não chama modelo**: o Diretor não precisa de turno para decidir, e é isso que
   dispensa o `herdr pane run`. Mensagem que não vira pedido válido → `{ consumed: reason }` (Claude não a lê).
3. **Verificador de peer (`tools/prova-ponte-mods/peer-verifier`), substituto de teste do daemon, em socket unix próprio** na pasta do run
   (`/tmp/claude-<uid>/<cwd codificado>/…`, nunca `~/.ponte/mcp.sock`). Obtém o PID do peer por `SO_PEERCRED` (Python 3 stdlib tem
   `socket.SO_PEERCRED`; o executor pode escolher outra linguagem, **desde que o PID venha do kernel e não do cliente**), sobe `/proc/<pid>/stat`
   até o processo `claude` e mapeia esse PID a um papel (`diretor`, `gerente`, `desconhecido`). O mapa é gravado **pelo aparelho que lança as sessões**
   (ele conhece o PID do `claude` que lançou), nunca pela sessão. Operações: `registrar-pedido`, `verificar-pedido`, `registrar-decisao`,
   `verificar-decisao`. Regras: o `rid` é de **uso único** e vence em **10 s**; pedido só vale se registrado por peer de papel `gerente`; decisão só vale se
   registrada por peer de papel `diretor` **para aquele `rid`**; peer `desconhecido` ou com cadeia quebrada (processo reparentado ao init) → recusa.
   O cliente do mod é um programa curto chamado por `$.process.run` (sem shell), filho do `claude`, de modo que o kernel dá ao verificador a cadeia certa.
4. **Assinatura × parentesco.** O Capitão aceitou os dois. Esta ordem escolhe o **parentesco** e **registra por que a assinatura não serve** como
   segurança aqui: gerente e Diretor rodam com o **mesmo usuário**, então uma chave assinadora é legível por qualquer processo dele (inclusive o
   Bash do agente); sem uma custódia fora do alcance do agente, ela autentica a mensagem e não o remetente. Se o executor propuser assinatura, a
   chave tem de morar **no verificador**, nunca com o remetente.
5. **O impostor.** Sessão e processos de teste que **tentam enganar** os dois lados (item "Critérios"): mensagem com o nome do gerente ou do Diretor, `rid`
   válido copiado, `rid` repetido (replay), `rid` vencido, pedido registrado por peer errado, decisão enviada por quem não é o Diretor, processo
   reparentado ao init, hash trocado, texto malformado e gigante. **Cada tentativa tem de falhar e ficar contada.**
6. **Acordar sem `herdr pane run`.** O Diretor de teste é uma sessão do Claude Code **viva e ociosa** (modo interativo numa pty ou `claude -p` com
   entrada contínua; o executor mede qual **acorda** com `session.receive` e diz). Um **`herdr` falso no PATH** grava cada chamada e sai com erro:
   o critério é **0 chamadas**. Sem turno de modelo no Diretor para as trocas (contado pelo transcrito/`turn.start`).
7. **Medição.** O tempo vai do **início do `tool.check` do gerente** até a **decisão aplicada**, em **milissegundos inteiros** por `$.clock.now()`
   (sem float). O relatório traz mediana, p95 e máximo **inteiros** e a contagem de timeouts.
8. **Log só de metadados** (regra do projeto): `rid` truncado, papel, veredito, `ms`; **nunca** comando, caminho nem prompt. Sem rede.

## O que fica de fora (e por quê)

- **Não** mexer no **ponte-daemon de produção**: nem código, nem `~/.ponte/mcp.sock`, nem `ponte.db`, nem as tools `director.*`. Nenhuma sessão de
  produção (o Diretor ou o Spock reais, as panes) participa: só sessões de teste lançadas pelo aparelho.
- **Não** trocar o canal de permissão de produção nem instalar o mod no ambiente; **não** tocar `hooks/`, `bin/`, `lib/`, settings, vendor/.
- **Não** usar modelo para o Diretor decidir (a política é a tabela); **não** provar classe B/biometria (é a 074 e a Ponte).
- **Não** abrir rede além do socket unix local. **Não** dar ao verificador poder de decidir: ele só **atesta quem registrou**.

## Ask-First

- **Contrato de eventos, versão instalada (2.1.293):** cole os tipos de `session.receive` e `session.send` e responda: (a) o que `e.origin` carrega; (b) `to`
  aceita só `{sessionId}`/`{agentId}`/endereço recebido?; (c) a mensagem **acorda** sessão ociosa interativa? e `claude -p` com entrada contínua?; (d) a
  configuração de **recusar mensagens de entrada** (cross-session messaging) é preciso desligar no Diretor de teste? Se `session.receive` não disparar
  na sessão ociosa, o critério de acordar **FALHA, nomeada**: PARE e relate; **não** reintroduza `herdr`.
- **Hook de 10 s:** esperar a resposta num `Promise` próprio **conta** no limite (documentação). Se o desenho não couber nisso, relate e proponha
  (por exemplo, devolver `ask` e responder depois); **não** estoure o limite deixando o hook ser "pulado" para `allow`.
- **Mod gerenciado:** com `allowManagedModsOnly` (patch 903) o `--plugin-dir` é recusado. A prova roda com `--plugin-dir` **enquanto o 903 não estiver
  aplicado**; depois dele, com o plugin instalado no diretório de root (etapa B; passo a passo na ordem 072). Diga qual ambiente valeu.
- **Sessões de teste e credencial:** lance-as isoladas de `~/.claude` do Capitão, **sem** apontar o HOME para uma pasta falsa que esconda o login
  (o OAuth seria perdido), sem tocar settings globais. Custo: as 100 trocas passam por **comando do mod** (`/prova-ponte N`), sem turno de modelo;
  só **5 trocas** usam o caminho real (o modelo executa 5 comandos e o `tool.check` cai no pedido). Diga os dois números.
- **Limite que não se disfarça:** mesmo usuário e mod sem sandbox: quem controla o processo do `claude` do Diretor (`ptrace`, injeção) forja
  tudo. É **tripwire e reconciliação** (como ST26), não fronteira, até o cutover para usuário sem `sudo`. Escreva isso no relatório.
- **Toca `lib/`, `bin/`, `hooks/`?** Não deve. Se algum passo exigir, PARE: seria UM patch em clone sandbox.

## Como sai

`mods/maestro-prova/`, `tools/prova-ponte-mods/` (verificador, cliente, lançador das sessões, impostor, `herdr` falso), `tests/` e
`docs/mods/PROVA-PONTE.md` (desenho, resultado, limites) direto no branch; a linha do plugin em `mods/.claude-plugin/marketplace.json`
(a 072 cria o arquivo; quem entrar depois dá rebase). Emendas: API_SPEC (o contrato gerente↔Diretor da prova) e CHANGELOG (Added). A emenda da
Ponte de produção, se a prova passar, é do **Diretor** e fica como proposta em `docs/mods/EMENDAS-PROPOSTAS.md`.

## Critérios de aceite

Todos escritos antes e **não renegociados**:

- [oráculo: `tools/prova-ponte-mods/rodar.sh`] **100 trocas seguidas** gerente→Diretor→gerente, **todas** com decisão correta e aplicada, **nenhuma falha no meio**
  (a primeira falha zera a contagem e o relatório diz onde). Saída colada, só inteiros.
- [oráculo: impostor] **0 decisões aceitas de remetente falso**, nos **dois sentidos** (pedido falso ao Diretor; decisão falsa ao gerente), com **≥ 100
  tentativas** cobrindo ≥ 8 formas (as do item 5), **intercaladas** com as 100 trocas válidas. Tabela forma × tentativas × aceitas (deve ser 0 em todas).
- [oráculo: tempo] **mediana do pedido até a decisão ≤ 5000 ms** nas 100 trocas; p95, máximo e timeouts reportados (timeout conta como falha da troca).
- [oráculo: acordar sem herdr] **0 chamadas** ao `herdr` falso e **0 turnos de modelo** no Diretor durante as trocas; a sessão do Diretor estava ociosa.
- [oráculo: `claude plugin test` em `mods/maestro-prova`] a decisão (função pura), o fail-closed (`throw`/timeout/resposta inválida → `deny`) e a recusa de mensagem
  malformada verdes; **vermelho antes**, colado. Se o kit não disparar `session.receive`, diga e cubra a função pura.
- [oráculo: `claude plugin validate ./mods/maestro-prova`] sai 0; `hooks:` e `calls:` colados (`session.send`, `process.run`, `env.get`, `fs.write` do log; sem `http.fetch`).
- [oráculo: `shellcheck` nos scripts bash] sem aviso; `bash tests/run-all.sh` verde; `habits` sem aviso novo.
- [humano] o Diretor lê a tabela do impostor e o parágrafo do limite e decide se a Ponte de produção segue este caminho.

## Prova exigida

- As 100 trocas (saída colada), a tabela do impostor, mediana/p95/máximo em ms, o log do `herdr` falso (vazio) e a contagem de turnos do Diretor.
- O vermelho antes e o verde depois dos testes do mod; o `validate`.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-NN` no tip e `maestro order --status NN` VÁLIDA.

## Turno

- ESTADO: **turno 1 FEITO e aceito no tip `5637255`; não repetir.** ENTREGOU: o verificador de peer (`tools/prova-ponte-mods/peer-verifier`, `SO_PEERCRED`, cadeia `/proc` até o `claude`, mapa de papéis gravado pelo aparelho, `rid` de uso único com TTL), o `peer-client`, o `claude-falso` e o `orfao`, `tests/cli/test-prova-ponte-verificador.sh` e `docs/mods/PROVA-PONTE.md`. Resultado: 100 trocas válidas seguidas, intercaladas com 313 tentativas de impostor em 16 formas, **0 aceitas em todas**; o verificador aceitou exatamente 400 operações (4 por troca). Ask-First (a) e (b) respondidos dos tipos da 2.1.293. ABERTO: (c) se `session.receive` acorda sessão ociosa, interativa e `claude -p` com entrada contínua, e (d) se há configuração de recusar mensagens de entrada: **não respondidos por tipos, só com sessão viva**; o mod `maestro-prova` **não existe**; as 100 trocas **pelo mod** e o tempo (mediana ≤ 5000 ms) **não medidos**; o "vermelho antes" do turno 1 foi só o **verificador ausente** (vermelho fraco: qualquer teste vermelho se o arquivo não existe), **sem controle por mutação**; o `comm` do `claude` real e a limpeza do mapa por PID no lançador seguem por conferir.
- fatia: **turno 2**: o mod `maestro-prova` (`mods/maestro-prova/`, papéis `diretor` e `gerente` por variável de ambiente, o gerente em `tool.check` com `deny` na queda, o Diretor em `session.receive` por função pura, o cliente do verificador por `$.process.run`), a conferência **com sessão viva** das respostas (c) e (d) (sessão ociosa interativa e `claude -p` com entrada contínua; relate o que mediu, não o que os tipos sugerem), e o **vermelho REAL por mutação de controle**: um verificador mutante que **confia no campo `de`** da mensagem (a identidade que o remetente escreve) tem de **fazer o teste do impostor ficar VERMELHO** (impostores aceitos > 0, contagem colada), e o verificador de verdade, VERDE; o mesmo para um Diretor mutante que decide pelo `e.origin.plugin`. Sem a mutação vermelha, o teste não prova nada. As 100 trocas pelo mod com mediana/p95/máximo ficam para o **turno 3**
- fim: `claude plugin validate ./mods/maestro-prova` sai 0 (`hooks:` e `calls:` colados, sem `http.fetch`); `claude plugin test` em `mods/maestro-prova` verde (decisão pura, fail-closed `throw`/timeout/resposta inválida → `deny`, mensagem malformada consumida), com **vermelho antes** do mod ausente colado; as respostas (c) e (d) **medidas em sessão viva** e coladas (ou "FALHA nomeada" se `session.receive` não disparar na ociosa: não reintroduza `herdr`); a **tabela de mutação**: mutante `de` → impostores aceitos N (> 0), real → 0, para o verificador e para o Diretor; `shellcheck` limpo; nada de produção tocado
- teto: 4
- fora: o ponte-daemon de produção, sessões de produção, modelo no Diretor, instalar o mod, tocar settings/managed-settings, hooks/bin/lib, rede, vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54, com o sha do tip). Terminar a
> resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível, **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou redirecionamento (`>`, `>>`) para
> escrever código, teste ou documento. O Bash serve para rodar, ler e medir. Patch gerado por `git diff` do sandbox para `docs/patches/` é a única
> saída por redirecionamento admitida.

> **Comando simples:** um comando por chamada de Bash; caminho absoluto em vez de cd e &&; sem pipe para cortar saída (| tail, | head), a
> ferramenta já corta; 2>&1 é permitido (junta saídas, não grava arquivo); a suíte roda como uma chamada só, maestro evidence --record --label
> order-N -- <suíte>, em segundo plano (run_in_background da ferramenta Bash) e a espera é por Monitor; o recibo já grava o código de saída.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run, `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp`
> solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. A suíte roda como uma chamada só (`maestro evidence --record --label order-N --
> <suíte>`) em segundo plano, pelo `run_in_background` da ferramenta Bash, e a espera é por **Monitor**; o recibo já grava o código de saída. Só
> depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/076-prova-da-ponte-sobre-mods-gerent`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-76 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 076` (você não fecha a própria ordem).
