<!-- maestro-order v1
id: 055
ts: 2026-10-03T17:29:53-03:00
epoch: 1791059393
head: 9e0ee89e8ef863a696f7d9dcf54cd06a8bc40f3b
branch: order/055-reparo-o-aceite-recusa-como-em-e
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 055 — reparo: o aceite recusa como em_execucao a evidencia VALIDA fora do limiar de carga

## Por quê

Reparo prioritário do método. O aceite recusa a ordem como `em_execucao` quando a evidência é
**VÁLIDA, mas fora do limiar de medição de carga** (`evidence --check` diz "VÁLIDA, mas fora do limiar
de medição (load N) — … N medição(ões) INCONCLUSIVA(S) sob carga"). Aconteceu na Vitali 037 e na
Enterprise 017. A forge fica sempre acima do limiar (2,0): na prática, **nenhuma ordem se aceita** lá
sem esperar a máquina esfriar.

**A regra que a ordem estabelece:** carga só invalida o **número de latência**, nunca o **veredito de
um comando que não mede tempo**. `exit 0` com conteúdo byte-idêntico ao tip é prova, com qualquer load.
O recibo continua carregando o qualificador (load, medições inconclusivas) para quem lê — informação,
não bloqueio.

**Nota do Capitão (03/10):** no próprio Maestro, a 048 foi aceita com recibos "VÁLIDA, mas fora do
limiar" (load 7,9 a 9,1) e `order --status` leu "provada". Então o defeito **não é universal**: depende
de versão da CLI (a Vitali e a Enterprise podem rodar a 1.20), de projeto ou de caminho. Descobrir
qual é o primeiro passo.

## O que entrega

1. **Reprodução**, antes de editar: `order --status|--accept` com recibo VÁLIDO fora do limiar, no
   Maestro e num projeto externo conforme (fixture), nas duas versões da CLI (1.20 e a do tip).
   Colar a saída exata de cada caso e dizer **onde** a evidência VÁLIDA vira `em_execucao` —
   candidatos a verificar, não a assumir: (a) o consumidor lê o texto do `--check` e trata o
   qualificador ", mas fora do limiar" como não-VÁLIDA; (b) rc do `evidence --check` diferente de 0
   quando há medição inconclusiva; (c) o `--status --json` (`evidencia_valida`) derivado de outro
   caminho que o `--status` humano; (d) o ledger do projeto externo gravando `inconclusive` no recibo
   e o leitor tratando como inválido.
2. **A regra no código**, num ponto só: quem decide o estado da ordem e o gate do aceite lê o
   **veredito** (exit, conteúdo byte-idêntico, idade, comando) e ignora load/inconclusivas. O qualificador
   segue impresso. Se algum comando mede latência (NFR de teste), o **teste** já usa o portão de
   `tests/lib/latency.sh` — não é o recibo que decide isso.
3. **Honestidade preservada:** recibo cuja corrida mudou a árvore, falhou (exit ≠ 0), venceu de idade ou
   de comando continua inválido. Só a carga deixa de invalidar.

## Ask-First

- Se o conserto exigir mudar o **formato** do recibo, PARE e reporte (DATA_MODEL).
- Se algum consumidor legítimo precisar de "carga conta" (ex.: recibo de latência), PARE: a exceção é
  decisão do Diretor, não do executor.
- Se o defeito só existir na CLI 1.20 já corrigida na 1.21, reporte "não reproduz no tip" com as
  corridas e proponha só o teste de regressão — não declare consertado o que não viu falhar.
- Conserto em `hooks/`, `bin/`, `src/`, `lib/` (autoprotegidos): PARE e diga qual linha e por quê; sai em
  UM patch em `docs/patches/055-*.patch`, feito em clone sandbox FORA do repo, aplicado pelo Capitão.

## Como sai

`tests/` e `docs/` direto no branch; protegido, em UM patch. Emendas no mesmo changeset: API_SPEC
(contrato do aceite/`--status`: carga não invalida veredito) e CHANGELOG. Um papercut se a causa for
armadilha de versão da CLI.

## Prova exigida

- **Vermelho antes:** teste que grava recibo `exit 0` VÁLIDO com `load` acima do limiar (e medições
  inconclusivas) e pede `order --status` e `--accept`: hoje `em_execucao`/recusa, saída colada.
- **Verde depois:** `provada` e aceite liberado, com o qualificador impresso.
- **Controles negativos:** recibo com exit ≠ 0, árvore mudada na corrida, tip diferente do provado e
  idade vencida continuam recusando.
- Suíte completa `SUITE OK`, sozinha no worktree; recibos `order-55` **e** `suite-55`, e `suite`
  (rótulo legado) enquanto a frota não girar; `habits` dentro da catraca.

## Turno

- fatia: reproduzir o aceite recusado com recibo VÁLIDO fora do limiar e achar onde o veredito vira em_execucao
- fim: teste vermelho antes e verde depois; `bash tests/run-all.sh` sai 0
- teto: 4
- fora: mudar o formato do recibo, afrouxar qualquer controle negativo, aceitar a ordem e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**: heredoc, `tee` e redirecionamento no Bash são barrados pelo guard (ordem 047).

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/055-reparo-o-aceite-recusa-como-em-e`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-55 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 055` (você não fecha a própria ordem).
