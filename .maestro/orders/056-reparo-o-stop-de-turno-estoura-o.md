<!-- maestro-order v1
id: 056
ts: 2026-10-03T21:06:28-03:00
epoch: 1791072388
head: 9e0ee89e8ef863a696f7d9dcf54cd06a8bc40f3b
branch: order/056-reparo-o-stop-de-turno-estoura-o
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 056 — reparo: o Stop de turno estoura o timeout de 2 s sob carga e libera o fim do turno sem relato

## Por quê

Reparo prioritário do método. `hooks/stop-turno.sh` chama
`timeout 2 maestro order --turno-check …`. O check leva **~1,8 s sem carga** e estoura o teto sob
carga: devolve **124**, e o hook trata 124 como "libera" (`(( rc == 1 )) || exit 0`). O fim do turno
passa **sem relato**. Foi o que fez um turno do daemon terminar sem `director_report`: o trilho que
existe para garantir o relato desligou exatamente quando a máquina estava ocupada, que é quando há
mais turno em paralelo.

A ordem 046 mediu o Stop de turno em **708 ms** (teto 2 s). Hoje o mesmo caminho passa de 1,8 s:
algo cresceu desde então (candidatos: a reserva e a leitura de worktrees/branches da 049, a
resolução de recibo por ordem da 048, a leitura do ledger a cada chamada). **Descobrir o que custa é
o primeiro passo** — não se sobe o teto às cegas.

## O que entrega

1. **Medição por fase** do `order --turno-check` (ledger, `git worktree list`, resolução de recibo,
   leitura da ordem, relatório): onde vão os 1,8 s, sem carga e com carga, mediana de N amostras.
   Saída colada. É o diagnóstico; sem ele nada se altera.
2. **Cortar o custo** onde ele está (memoizar o que é lido duas vezes, não varrer branches/worktrees
   num check que só precisa da ordem do branch atual, evitar forks repetidos). Meta: caminho comum
   abaixo de ~700 ms sem carga, como a 046 mediu, com folga sob carga.
3. **O 124 deixa de ser silêncio.** Timeout não pode virar "turno sem relato" calado. O contrato
   fica entre dois polos, e a escolha é do Diretor (ver Ask-First):
   (a) o hook, em 124, faz a **checagem barata local** (a última mensagem tem os rótulos do relatório
   do bloco `## Turno`?) e só bloqueia se faltarem; ou
   (b) o hook registra o evento (`turno_teto`/novo `turno_timeout`, só metadados) e libera, mas o
   `director_report` passa a ser exigido por **outro** trilho que não depende do tempo.
   Em qualquer caso, a Prioridade 1 vence: o hook **nunca prende** o gerente, e falha de componente
   degrada para o fluxo manual.
4. O teto do `timeout` (hoje 2 s) sai do código e vira constante nomeada, com o orçamento e a medição
   no comentário.

## Ask-First

- **PARE antes do item 3**: reverter o "124 libera" é mexer na Prioridade 1 (nunca bloquear por
  componente lento). Reporte a medição do item 1 e proponha (a) ou (b) com o custo de cada um; a
  escolha é do Diretor.
- Subir o teto do `timeout` sem reduzir o custo mascara a regressão: só com a medição que o
  justifique e como complemento do item 2, nunca no lugar dele.
- Conserto em `hooks/stop-turno.sh`, `bin/`, `lib/`, `src/` (autoprotegidos): PARE e diga qual linha e
  por quê; sai em UM patch em `docs/patches/056-*.patch`, feito em clone sandbox FORA do repo, aplicado
  pelo Capitão. Os hooks rodam do **cache do plugin**: o conserto só vale depois do giro.

## Como sai

`tests/` e `docs/` direto no branch; protegido, em UM patch. Emendas no mesmo changeset:
ENGINEERING_SPEC ("O turno da ordem e o relatório de fim de turno": orçamento medido e o contrato do
124), API_SPEC (contrato do hook) e CHANGELOG. Papercut: "Stop de turno libera em 124 sob carga".

## Prova exigida

- **Vermelho antes:** teste que simula o check lento (stub do CLI que dorme acima do teto) e mostra o
  hook liberando sem relato; saída colada.
- **Verde depois:** o comportamento escolhido no item 3, e o caminho comum dentro do orçamento medido
  (usar o portão de carga de `tests/lib/latency.sh`: sob load, estouro é inconclusivo, nunca FAIL).
- **Controles:** reentrada (`stop_hook_active`), `[spock] aguardando:`, branch sem ordem e
  `MAESTRO_OFF=1` seguem liberando; o hook sempre sai 0 sem prender.
- Suíte completa `SUITE OK`, sozinha no worktree; recibos `order-56`, `suite-56` e `suite` (legado, até
  a frota girar); `habits` dentro da catraca.

## Turno

- fatia: medir o `turno-check` por fase, achar o custo e propor o contrato do 124 (item 1 e a proposta do item 3)
- fim: medição por fase colada e a escolha (a) ou (b) pedida ao Diretor; depois testes vermelho antes e verde depois e `bash tests/run-all.sh` sai 0
- teto: 4
- fora: subir o timeout sozinho, decidir o contrato do 124 sem o Diretor, aplicar o patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**: heredoc, `tee` e redirecionamento no Bash são barrados pelo guard (ordem 047).

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/056-reparo-o-stop-de-turno-estoura-o`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-56 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 056` (você não fecha a própria ordem).
