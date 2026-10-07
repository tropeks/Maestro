<!-- maestro-order v1
id: 075
ts: 2026-10-07T16:04:07-03:00
epoch: 1791399847
head: dc31a58f0b99f6d28aba7e14c6e418466bc4b1c5
branch: order/075-vigia-de-versao-do-claude-code-t
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 075 — vigia de versao do Claude Code: testes dos mods e ordem de reparo

## Por quê

**Decisão do Capitão de 07/10** (mods como base; fonte `~/dev/spock/docs/pesquisa-claude-code-nativo-vs-metodo-2026-10-07.md`, Riscos 3 e 4:
"API de mods instável"). **Sem fixar versão do Claude Code:** a API dos mods "pode mudar entre versões" e a fábrica se adapta. O preço dessa
escolha é que **um update do Claude Code pode quebrar um mod sem aviso**, e um mod que **falha fechado** vira recusa em cascata. O vigia é o que
transforma "quebrou" em **ordem de reparo** antes que alguém descubra no meio de um run.

Esta é a **4ª de 4 ordens**. Ela testa os plugins das outras três (`mods/maestro-guard`, `mods/maestro-reads`, `mods/maestro-hold`) e qualquer mod
que entre em `mods/` depois: não conhece nenhum pelo nome.

## O que entrega

1. **`tools/vigia-claude-code.sh`** (bash, só leitura de estado e escrita no próprio estado/log). A cada execução:
   1. lê `claude --version` e compara com `~/.maestro/state/claude-code-version` (1ª linha);
   2. **se igual**, registra `vigia sem-mudanca` e sai 0 (barato: roda a cada 10 min);
   3. **se mudou** (ou o arquivo não existe), roda **a bateria**, grava o resultado e só então grava a versão nova.
2. **A bateria**, para cada diretório em `mods/*/` com `.claude-plugin/plugin.json`:
   - `claude plugin validate <dir>` (sai 0; o `hooks:` e o `calls:` **não ganharam chamada nova** desde a versão anterior, comparados com
     `mods/<nome>/validate.baseline`: uma chamada nova, como `http.fetch` ou `process.run`, é **aviso**);
   - `claude plugin test` no diretório (todo teste, inclusive o adversarial e o corpus);
   - o **teste de fumaça de fiação**: o mod `maestro-guard` ainda **nega** um destrutivo de controle e **deixa passar** um `ls`, no kit de teste.
3. **Quebra vira ordem de reparo.** Para cada plugin com falha, o vigia roda
   `maestro order --create --title "reparo: mod <nome> quebrou no claude <versão>"` com corpo gerado (o oráculo é o teste que falhou; a saída
   completa vai para `~/.maestro/briefs/vigia-<nome>-<versão>.md`, **o corpo cita o caminho e traz só contagens**). Idempotente: se já existe
   ordem aberta de reparo do mesmo plugin e versão, **não cria outra** (marca em `~/.maestro/state/vigia-abertas.tsv`).
4. **Relato pela Ponte.** O vigia avisa o Capitão/Diretor **uma vez por versão** com o resultado (`N plugins, N ok, N falhas`, inteiros, e o
   caminho do brief). O canal é o que o resto da fábrica já usa para avisos sem decisão (`PushNotification`/`director.report`); o executor
   **descobre qual** e cola o comando exato. Falha do canal **não** apaga a ordem de reparo.
5. **Quando roda.** Um **timer de usuário do systemd** (`maestro-vigia.timer`, a cada 10 min, `Persistent=true`) com o `.service` de uma linha;
   unidades em `tools/systemd/`, instalação em `docs/mods/VIGIA.md` (o Capitão roda `systemctl --user enable --now`; esta ordem **não** roda).
6. **Um comando de checagem manual:** `bash tools/vigia-claude-code.sh --agora` força a bateria e **não** grava a versão (para testar no
   terminal o que um update trará: `claude --version` mais a bateria).
7. **Sem fixar versão.** Nada impede o `claude update`. O vigia **nunca** reverte, **nunca** trava a versão e **nunca** desliga um mod: ele
   observa e abre ordem. (Reversão de binário, se um dia for decidida, é do Capitão.)
8. **Painel.** Linha única para o painel: versão atual, última bateria, `ok/falhas` (inteiros) e idade da última bateria em minutos. Se o
   vigia não rodou há mais de 30 min, o painel diz **FALHA nomeada** (fonte ausente), não "ok".

## O que fica de fora (e por quê)

- **Não** consertar o mod que quebrou: isso é a ordem de reparo, que o Diretor despacha.
- **Não** fixar, reverter nem bloquear o update do Claude Code.
- **Não** testar o que não é mod (hooks bash, `bin/maestro`): a suíte de CI já cobre.
- **Não** usar rede além do que o próprio `claude --version`/`plugin test` fizerem (o kit de teste roda "sem sessão, login ou rede").
- **Não** instalar o timer. **Não** tocar `hooks/`, `bin/`, `lib/`, settings, vendor/.

## Ask-First

- **Contrato do CLI:** confirme na versão instalada (hoje **2.1.293**) a forma e o código de saída de `claude plugin validate` e `claude plugin
  test` (a documentação diz que `test` sai 1 em falha e imprime `claude plugin test: hooks modules are turned off` quando os mods não podem
  carregar). **Esse segundo caso é falha da bateria, não "sem teste".** Se o comando mudar de nome, PARE e relate.
- **Plugins só carregam sob política:** com `allowManagedModsOnly` ativo os mods de `--plugin-dir` **não** carregam, e `claude plugin test`
  pode recusar. Teste os dois ambientes (com e sem os settings gerenciados `903`) e relate qual o vigia usa; se for preciso um **caminho de
  teste isento**, PARE: abrir exceção na política é decisão do **Capitão**.
- **Relato pela Ponte:** se o script não conseguir chamar o canal sem token/rede, **entregue só a ordem de reparo e o log** e diga que o aviso
  fica para quem consome o log; não invente integração.
- **`maestro order --create` num script:** o corpo vem por stdin e a numeração por reserva; confirme que rodar do timer (sem sessão) cria a ordem no
  repo certo e **não** colide com as ordens abertas. Se não for seguro, grave o pedido num arquivo e deixe a criação para o Diretor.
- **Regra da subtração (v62):** cada ordem de reparo conta como ordem de método. O vigia **não cria mais de 1 por plugin por versão** e nunca
  mais de 3 por rodada; o excedente vira linha no brief.
- **Toca `lib/`, `bin/`, `hooks/`?** Não deve. O script vive em `tools/`.

## Como sai

`tools/vigia-claude-code.sh`, `tools/systemd/*`, `tests/tools/test-vigia-claude-code.sh` (com **`claude` falso** no PATH, que devolve versões e
códigos de saída controlados), `docs/mods/VIGIA.md` direto no branch. Emendas: ENGINEERING_SPEC (o vigia e o limite "sem fixar versão"),
CHANGELOG (Added).

## Critérios de aceite

- [oráculo: `bash tests/tools/test-vigia-claude-code.sh`] com `claude` falso: (1) versão igual → sem bateria, exit 0; (2) versão nova e testes
  ok → grava a versão, 0 ordens; (3) versão nova e um plugin falha → **1 ordem de reparo** criada, versão gravada, aviso uma vez; (4) rodar de novo
  na mesma versão → **0 ordens novas** (idempotente); (5) `test` imprime "hooks modules are turned off" → conta como falha; (6) `claude` ausente
  → FALHA nomeada, sem gravar versão; (7) `--agora` não grava a versão. **Vermelho antes** (o script não existe), colado.
- [oráculo: teste de fumaça] com o `maestro-guard` real, o vigia roda a bateria na versão instalada e sai 0 (se a ordem da guarda ainda não
  estiver no branch, o teste usa um plugin-fixture e diz isso).
- [oráculo: `shellcheck tools/vigia-claude-code.sh`] sem aviso.
- [oráculo: `bash tests/run-all.sh`] verde; `habits` sem aviso novo.
- [humano] o Diretor lê o texto de uma ordem de reparo gerada (colada) e decide se serve.

## Prova exigida

- Vermelho antes e verde depois; a ordem de reparo gerada pelo caso (3), colada; o `shellcheck`.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-NN` no tip e `maestro order --status NN` VÁLIDA.

## Turno

- fatia: o teste com `claude` falso (vermelho colado) e o `tools/vigia-claude-code.sh` com a bateria, a idempotência e a ordem de reparo
- fim: `bash tests/tools/test-vigia-claude-code.sh` sai 1 antes (colado) e 0 depois; `shellcheck` limpo; a ordem de reparo do caso (3) colada
- teto: 3
- fora: consertar mod, fixar/reverter versão, instalar o timer, abrir exceção na política de mods, tocar hooks/bin/lib/settings, vendor/
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
- Trabalhe APENAS no branch `order/075-vigia-de-versao-do-claude-code-t`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-75 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 075` (você não fecha a própria ordem).
