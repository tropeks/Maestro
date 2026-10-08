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

Um plugin de mod `maestro-prova` (`tools/prova-ponte-mods/maestro-prova/`, **nunca em `mods/`**: plugin.json, `hooks/hooks.json`, `hooks/register.js`, `tests/*.test.ts`), com **dois papéis**
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
- **Mod gerenciado:** com `allowManagedModsOnly` (patch 903) o `--plugin-dir` é recusado. A prova roda com `--plugin-dir` **enquanto a política não estiver
  armada**. **Decisão do Diretor de 08/10:** com a política armada e o mod recusado, o resultado é **FALHA NOMEADA** (cole a mensagem da recusa),
  **sem contornar**: nada de instalar o mod de prova no diretório de root, de editar settings gerenciados ou de usar `--safe-mode`. Diga qual ambiente valeu.
- **Sessões de teste e credencial:** lance-as isoladas de `~/.claude` do Capitão, **sem** apontar o HOME para uma pasta falsa que esconda o login
  (o OAuth seria perdido), sem tocar settings globais. Custo: as 100 trocas passam por **comando do mod** (`/prova-ponte N`), sem turno de modelo;
  só **5 trocas** usam o caminho real (o modelo executa 5 comandos e o `tool.check` cai no pedido). Diga os dois números.
- **Limite que não se disfarça:** mesmo usuário e mod sem sandbox: quem controla o processo do `claude` do Diretor (`ptrace`, injeção) forja
  tudo. É **tripwire e reconciliação** (como ST26), não fronteira, até o cutover para usuário sem `sudo`. Escreva isso no relatório.
- **Toca `lib/`, `bin/`, `hooks/`?** Não deve. Se algum passo exigir, PARE: seria UM patch em clone sandbox.

## Como sai

`tools/prova-ponte-mods/` (o mod `maestro-prova` em `tools/prova-ponte-mods/maestro-prova/`, o verificador, o cliente, o lançador das sessões, o
impostor, o `herdr` falso), `tests/` e `docs/mods/PROVA-PONTE.md` (desenho, resultado, limites) direto no branch. **Decisão do Diretor de 08/10 (opção
3 sobre o guard): o mod de prova NUNCA vive em `mods/`** (que segue protegido); ele não entra em `mods/.claude-plugin/marketplace.json`; promover a
`mods/` só por patch protegido, decisão futura. Emendas: API_SPEC (o contrato gerente↔Diretor da prova) e CHANGELOG (Added). A emenda da Ponte de
produção, se a prova passar, é do **Diretor** e fica como proposta em `docs/mods/EMENDAS-PROPOSTAS.md`.

## Critérios de aceite

Todos escritos antes e **não renegociados**:

- [oráculo: `tools/prova-ponte-mods/rodar.sh`] **100 trocas seguidas** gerente→Diretor→gerente, **todas** com decisão correta e aplicada, **nenhuma falha no meio**
  (a primeira falha zera a contagem e o relatório diz onde). Saída colada, só inteiros.
- [oráculo: impostor] **0 decisões aceitas de remetente falso**, nos **dois sentidos** (pedido falso ao Diretor; decisão falsa ao gerente), com **≥ 100
  tentativas** cobrindo ≥ 8 formas (as do item 5), **intercaladas** com as 100 trocas válidas. Tabela forma × tentativas × aceitas (deve ser 0 em todas).
- [oráculo: tempo] **mediana do pedido até a decisão ≤ 5000 ms** nas 100 trocas; p95, máximo e timeouts reportados (timeout conta como falha da troca).
- [oráculo: acordar sem herdr] **0 chamadas** ao `herdr` falso e **0 turnos de modelo** no Diretor durante as trocas; a sessão do Diretor estava ociosa.
- [oráculo: `claude plugin test` em `tools/prova-ponte-mods/maestro-prova`] a decisão (função pura), o fail-closed (`throw`/timeout/resposta inválida → `deny`) e a recusa de mensagem
  malformada verdes; **vermelho antes**, colado. Se o kit não disparar `session.receive`, diga e cubra a função pura.
- [oráculo: `claude plugin validate ./tools/prova-ponte-mods/maestro-prova`] sai 0; `hooks:` e `calls:` colados (`session.send`, `process.run`, `env.get`, `fs.write` do log; sem `http.fetch`).
- [oráculo: `shellcheck` nos scripts bash] sem aviso; `bash tests/run-all.sh` verde; `habits` sem aviso novo.
- [humano] o Diretor lê a tabela do impostor e o parágrafo do limite e decide se a Ponte de produção segue este caminho.

## Prova exigida

- As 100 trocas (saída colada), a tabela do impostor, mediana/p95/máximo em ms, o log do `herdr` falso (vazio) e a contagem de turnos do Diretor.
- O vermelho antes e o verde depois dos testes do mod; o `validate`.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-NN` no tip e `maestro order --status NN` VÁLIDA.

## Turno

- ESTADO: **turnos 1 a 5 FEITOS; o teto (5) está esgotado; NÃO despachar turno 6 nem repetir nenhum.** TURNO 5 (revisado no tip `4f94d3f`; depois rebaseado sobre `origin/main` `e132c16`) PROVOU, em sessão viva com a política desarmada pelo Capitão: **100 trocas seguidas pelo mod, 100 corretas, 0 timeouts, mediana 405 ms, p95 549 ms, máximo 2045 ms**, mais 5 pelo caminho real (5 de 5); **200 tentativas de impostor em 13 formas, 0 aceitas** (nos dois sentidos); `herdr` falso com **0 chamadas** e **0 turnos de modelo** no Diretor; (c) **medido na `claude -p` ociosa com entrada contínua: `session.receive` dispara** e não gera turno; (d) **medido na `claude -p`: nenhuma configuração precisou ser desligada**. Achados que mudam a Ponte de produção: o corpo chega embrulhado em `<cross-session-message …>` com atributos do remetente; o `$.session.send` tem limite de taxa (rajada ~50, depois ~0,5/s; acima disso o envio é recusado e o gerente faz `deny`); o hook de `command.run` vale 10 s; a `classe` não estava amarrada ao pedido (corrigido); inundação é negação de serviço segura, não falsificação. **LACUNA ABERTA, para uma ORDEM CURTA SEGUINTE (não desta): (c) e (d) em SESSÃO INTERATIVA NÃO foram medidos.** O Diretor interativo (numa pty, `pty-diretor`) carregou o mod e ficou vivo, mas o gerente não o achou (`$.session.send: not sent: no live session on this machine has id <uuid>`): a `claude -p` aparece em `~/.claude/sessions/<pid>.json`, a interativa lançada pelo aparelho não, e a causa não foi isolada. O Diretor de produção é interativo, então isto precisa de medição própria antes de qualquer cutover. **TURNO 4 FICOU SEM MEDIÇÃO, por um erro fora da ordem e do run:** o Capitão rodou o religar junto com o desarme (sudo log 11:42:40), então a política `allowManagedModsOnly` voltou a estar armada durante o turno; nenhum dado de (c), (d), das 100 trocas ou do tempo foi produzido, e não há commit do turno 4. **O teto sobe de 4 para 5, por decisão do Diretor.** **O TURNO 5 REPETE EXATAMENTE A FATIA DO TURNO 4** (a fatia e o fim abaixo, sem mudança de conteúdo). O Capitão desarma de novo antes do despacho do turno 5 e religa só depois do relato; o run nunca toca settings. TURNO 3 (tip `b41ce7f`) PROVOU: o mod `maestro-prova` em `tools/prova-ponte-mods/maestro-prova/` (gerente em `tool.check` com `deny` em qualquer queda, Diretor em `session.receive` por função pura, endereço da resposta vindo de `PROVA_PAR` e nunca da mensagem); o **vermelho antes** (`claude plugin test` sem o mod falhou com `no hooks module to load`, rc 1) e o **verde depois** (16 testes, 0 falhas); `claude plugin validate` sai 0 (`hooks: tool.check, session.receive`; `calls: $.clock.now, $.clock.sleep, $.env.get, $.fs.write, $.process.run, $.session.send`, sem `http.fetch`); a **mutação do Diretor** (`tests/cli/test-prova-ponte-mutacao-diretor.sh`): o mutante, que decide por `e.origin.plugin`, deixa o teste do impostor **VERMELHO com 2 impostores aceitos**; o Diretor real, **VERDE com 0**. **FALHA NOMEADA do turno 3:** (c) e (d) em sessão viva **não foram medidos**, porque a política `allowManagedModsOnly` estava armada e recusou o mod de prova nas duas sessões: `plugin.register: maestro-prova (user, maestro-prova@inline), judged by cc-plugin-sec-default: refused by cc-plugin-sec-default: mods are limited to your organization's by policy (allowManagedModsOnly); maestro-prova was not loaded`. Nada foi contornado. Observação: `claude plugin test` carrega o mod (o kit não passa pelo `plugin.register` da política), então as tabelas valem para a lógica, não para a sessão viva. **DECISÃO DO CAPITÃO (01M4DX51): DESARMAR `allowManagedModsOnly` só durante o turno de medição (turno 4, repetido no turno 5).** Ele mesmo desliga e religa; **o run nunca toca settings** (nem para desarmar, nem para religar, nem `--safe-mode`). **TURNO 5 = a próxima rodada** (fatia abaixo, a mesma que era do turno 4). **Se a sessão viva AINDA recusar o mod no turno 5, é FALHA NOMEADA (cole a mensagem da recusa) e o run PARA**: não prossiga para as 100 trocas, não contorne. TURNO 2 (revisado no tip `1d5a6da`) ENTREGOU a **mutação de controle do verificador**: `tests/cli/test-prova-ponte-mutacao.sh` e `tools/prova-ponte-mods/peer-verifier-mutante-de` (um verificador que **confia no campo `de`** da mensagem). O mesmo teste do impostor roda contra os dois: **mutante → VERMELHO com 4 impostores aceitos; verificador real → VERDE com 0** (rc 1 contra rc 0; reconfirmado em 08/10). O turno 2 **não criou o mod**: o guard (`mods/` protegido) o barrou. **DECISÃO DO DIRETOR de 08/10 (opção 3):** o mod de prova vive em `tools/prova-ponte-mods/maestro-prova`, **nunca em `mods/`**; promover a `mods/` só por patch protegido. Onde este texto dizia `mods/maestro-prova`, vale o caminho novo. TURNO 1 ENTREGOU: o verificador de peer (`tools/prova-ponte-mods/peer-verifier`, `SO_PEERCRED`, cadeia `/proc` até o `claude`, mapa de papéis gravado pelo aparelho, `rid` de uso único com TTL), o `peer-client`, o `claude-falso` e o `orfao`, `tests/cli/test-prova-ponte-verificador.sh` e `docs/mods/PROVA-PONTE.md`. Resultado: 100 trocas válidas seguidas, intercaladas com 313 tentativas de impostor em 16 formas, **0 aceitas em todas**; o verificador aceitou exatamente 400 operações (4 por troca). Ask-First (a) e (b) respondidos dos tipos da 2.1.293. ABERTO: (c) se `session.receive` acorda sessão ociosa, interativa e `claude -p` com entrada contínua, e (d) se há configuração de recusar mensagens de entrada: **não respondidos por tipos, só com sessão viva**; o mod `maestro-prova` **não existe**; as 100 trocas **pelo mod** e o tempo (mediana ≤ 5000 ms) **não medidos**; o "vermelho antes" do turno 1 foi só o **verificador ausente** (vermelho fraco: qualquer teste vermelho se o arquivo não existe), **sem controle por mutação**; o `comm` do `claude` real e a limpeza do mapa por PID no lançador seguem por conferir.
- fatia: **turno 5 (a mesma fatia que era do turno 4)**: (1) **medir-acordar** (`tools/prova-ponte-mods/medir-acordar`) com a política desarmada pelo Capitão: confirme **primeiro** que o mod carrega nas duas sessões (a linha de debug `hooks module maestro-prova ... loaded`); se ainda for recusado, **FALHA NOMEADA e PARE**; (2) as respostas **(c) e (d) MEDIDAS em sessão viva**: `session.receive` acorda a sessão ociosa interativa? e a `claude -p` com entrada contínua? há configuração de recusar mensagens de entrada, e é preciso desligá-la no Diretor de teste? Relate o que mediu, não o que os tipos sugerem; (3) as **100 trocas pelo mod** (comando `/prova-ponte N`, sem turno de modelo) mais as 5 pelo caminho real, **intercaladas** com as tentativas de impostor, com **mediana, p95 e máximo em ms inteiros** e os timeouts; (4) o `herdr` falso (0 chamadas) e a contagem de turnos de modelo no Diretor (0); (5) as **emendas** (API_SPEC do contrato gerente↔Diretor; CHANGELOG; `docs/mods/EMENDAS-PROPOSTAS.md` para a Ponte de produção) e o **recibo** `order-76`
- fim: (c) e (d) medidas e coladas; `tools/prova-ponte-mods/rodar.sh` com as 100 trocas seguidas sem falha, **0 aceitas** de remetente falso nos dois sentidos, **mediana ≤ 5000 ms**; `herdr` falso com 0 chamadas; `shellcheck` limpo; `bash tests/run-all.sh` `SUITE OK`, sozinha no worktree, recibo `order-76` no tip e `maestro order --status 76` VÁLIDA; nada em `mods/` nem de produção tocado e **nenhum settings tocado pelo run**. Se qualquer critério falhar, o relatório diz qual, com o número, sem renegociar
- teto: 5
- fora: o ponte-daemon de produção, sessões de produção, modelo no Diretor, **criar ou editar qualquer coisa em `mods/`**, instalar o mod, tocar settings/managed-settings, contornar a política de mods, hooks/bin/lib, rede, vendor/
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
accepted_at: 2026-10-08T13:51:36-03:00
accepted_session: desconhecido
accepted_tree: 47769d59b9fc457ffc5d6d96b298cfb46fa7015c
accepted_intent: 6
