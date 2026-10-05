<!-- maestro-order v1
id: 064
ts: 2026-10-04T17:13:52-03:00
epoch: 1791144832
head: 587d78799e7fb0317989257f88c4233fc9e97c86
branch: order/064-o-stop-de-turno-nao-bloqueou-o-t
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 064 — o Stop de turno nao bloqueou o turno headless que encerrou esperando notificacao

## Por quê

O hook de fim de turno (`hooks/stop-turno.sh`, ordem 046) existe para uma coisa: **o turno de uma ordem não
termina sem recibo VÁLIDO no tip**. O **turno headless da 062** terminou a resposta com a suíte rodando em
segundo plano e **sem recibo**; a última fala foi *"Suíte ainda rodando; aguardo a notificação"*. O hook
**não bloqueou**. O trilho que devia impedir exatamente isso não impediu, e a ordem ficou parada até o
Capitão notar.

Mecânica do hook: o critério é o recibo no ledger, **não o texto** da fala. Uma frase de espera não deveria
liberar nada; deveria cair em "falta recibo `order-N`" e bloquear (até o teto de 3 por sessão). Por isso a
causa não é "o hook não reconhece essa frase" — **não classifique frase**.

## O que entrega

1. **Reproduzir com teste, antes de qualquer conserto.** Um teste monta o hook como no headless: payload do Stop
   com `last_assistant_message` = *"Suíte ainda rodando; aguardo a notificação"*, `stop_hook_active:false`,
   transcrito com essa última fala, projeto de fixture com uma ordem em curso cujo branch é `order/NNN-…`, bloco
   `## Turno` válido e **nenhum recibo `order-N`**. Esperado: o hook imprime `{"decision":"block", …}`.
   **Saída colada** do que ele faz hoje.
2. **Achar a causa, com prova.** Hipóteses a testar uma a uma, **não a assumir** (a primeira é a que os fatos já
   apontam):
   - **(a) o cache do plugin.** Os hooks rodam do **cache** (`~/.claude/plugins/cache/maestro/maestro/`), que hoje
     está em **1.21.0**: o conserto do 124 da ordem **056** (`TURNO_TIMEOUT_S`, checagem local dos 5 rótulos,
     evento `turno_timeout`) **só existe a partir da 1.22.0**. Sob load, o `order --turno-check` da 1.21.0
     estoura os 2 s, devolve **124** e o hook **libera calado**: o exato defeito da 056, sem ainda ter chegado ao
     hook em uso. Indício: o ledger **não tem nenhum** `turno_timeout`/`turno_teto` do turno da 062. Confirme:
     versão do hook do cache vs. o do repo, o `order --turno-check` cronometrado sob a carga do turno, e o
     resultado do mesmo teste contra o hook **do tip** (se o hook do tip bloqueia e o do cache não, a causa é o
     cache e o conserto é o **giro**, não código).
   - **(b)** reentrada (`stop_hook_active:true` libera por desenho);
   - **(c)** o teto de 3 bloqueios por sessão já consumido;
   - **(d)** diretório do projeto: no headless o `CLAUDE_PROJECT_DIR`/cwd não apontar para o worktree que tem
     `.maestro/orders/` (`[[ -d "$proj/.maestro/orders" ]] || exit 0`);
   - **(e)** a válvula `order --turno-livre` ligada, ou a ordem sem `## Turno` válido no branch daquele turno;
   - **(f)** o `transcript_path` vazio ou ilegível no headless, e `last` vazio.
   Para cada uma: o teste que a **liga e desliga** e o resultado colado.
3. **Corrigir a causa achada**, e só ela. Se for **(a)**, o conserto de código é zero: a entrega é o **mecanismo
   que impede o descompasso**, a proposta mínima para o Diretor decidir (ex.: o `doctor`/`session-start`
   acusar **cache atrás do repo** num projeto com ordem em curso e o headless se recusar a rodar turno de
   ordem com o hook defasado; hoje o `doctor` só avisa "cópia registrada difere"). Se for outra, o patch do
   hook/lib corrige, com o teste do item 1 verde.
4. **A regra no esqueleto do Turno** (`_order_turno_skeleton`, `lib/core-order-turno.sh`): ao lado da linha
   "Log e escrita" da 062, passa a trazer
   `> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera por
   laço até a linha rc= no log; só depois se relata.`
   Mesma forma (linha citada, não rótulo): o `conform` e o Stop de turno não a leem como campo do Turno.
   **Teste que falha antes:** `order --create` numa fixture não traz a linha hoje; traz depois.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/hooks/test-order-064-stop-sem-notificacao.sh`] o teste do item 1: **vermelho** onde a
  causa reproduz (colado), **verde** depois do conserto/giro; o caso é o do payload da 062.
- [oráculo: o mesmo teste] **controles:** reentrada, `[spock] aguardando:`, branch sem ordem e `MAESTRO_OFF=1`
  seguem liberando; o hook sai **sempre 0** e nunca prende (Prioridade 1).
- [oráculo: `bash tests/cli/test-order-064-esqueleto-headless.sh`] o esqueleto traz a regra do headless e os
  cinco rótulos seguem os mesmos; `bash tests/cli/test-order-046-turno.sh` verde.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [humano] o Diretor lê a causa provada (a, b, c, d, e ou f) e a proposta, e decide giro vs. código.

## Ask-First

- **Causa (a): PARE antes de propor mecanismo novo** e relate com a prova. Girar o cache e a política de
  "headless recusa hook defasado" são decisões do Diretor/Capitão, não do executor.
- Não classifique a frase do relato (nada de `grep` por "aguardo"): o critério segue sendo o recibo.
- Se o conserto exigir **mudar a Prioridade 1** (bloquear sob falha de componente), PARE.
- **Toca `hooks/` e `lib/`, autoprotegidos** (o esqueleto é `lib/core-order-turno.sh`; o hook, se for ele):
  a entrega é **UM patch** em `docs/patches/064-*.patch`, feito em clone sandbox FORA do repo, testado antes e
  depois, aplicado pelo Capitão com um `git apply`. `tests/` e `docs/` direto no branch.

## Como sai

`tests/` e `docs/` direto no branch; `hooks/` e `lib/` em **UM patch protegido**. Emendas no mesmo changeset:
ENGINEERING_SPEC ("O turno da ordem e o relatório de fim de turno": a causa achada e o contrato do headless),
API_SPEC se o contrato do hook mudar, e o CHANGELOG (Fixed). Papercut: "Stop de turno do cache atrás do repo
libera calado em 124".

## Prova exigida

- O teste vermelho antes (saída colada) e verde depois; a causa com a prova de cada hipótese testada.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-64` no tip com o patch aplicado e
  `maestro order --status 64` VÁLIDA (se a causa for só o cache e não houver patch de código, o recibo vem do
  teste e da emenda).

## Turno

- fatia: o teste vermelho do payload da 062, a causa provada (hipótese a a f) e, se houver código, o conserto em sandbox mais a regra do headless no esqueleto
- fim: `bash tests/hooks/test-order-064-stop-sem-notificacao.sh` e `bash tests/cli/test-order-064-esqueleto-headless.sh` saem 1 antes (colado) e 0 depois, ou o relatório prova que a causa é o cache; `bash tests/run-all.sh` sai 0
- teto: 3
- fora: classificar a frase do relato, girar o cache, mudar a Prioridade 1, aplicar o patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write. Nenhum heredoc, `tee`,
> `sed -i`, `python -c`, `cat >` ou redirecionamento para escrever código, teste ou documento.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera **por
> laço** até a linha `rc=` no log; só depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/064-o-stop-de-turno-nao-bloqueou-o-t`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-64 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), com a decisão do Capitão de 04/10 (v59) como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 064` (você não fecha a própria ordem).
accepted_at: 2026-10-05T12:05:12-03:00
accepted_session: desconhecido
accepted_tree: f5e99aa621bdec3dc871d09b18c3d191d9ada342
accepted_intent: 6
