<!-- maestro-order v1
id: 060
ts: 2026-10-04T09:16:20-03:00
epoch: 1791116180
head: 9009b061c242e550ab0fd33c8a351b6395526bd5
branch: order/060-verificador-unico-de-prova-evide
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 060 — verificador unico de prova: evidence --check, order --status e order --accept aplicam os mesmos criterios

## Por quê

Autorizada pela **v59, item 3, do INTENT do spock** (a direção do Diretor; o INTENT carimbado no repo
é a v6, que esta ordem cita como base — o item 3 da v59 é o que a autoriza). A avaliação externa achou
que **três leitores da mesma prova discordam entre si**:

- **`evidence --check`** (`lib/cmd-evidence.sh`, `_ev_cmd_reasons`, perto da linha 198) é o rigoroso:
  invalida a execução cuja **árvore mudou durante a corrida** (`wtree_before ≠ wtree_after`), cujo
  **comando mudou** (`cmd_match=no`, ou hash do recibo ≠ `commands.<label>` do `.maestro.yaml`), que
  **falhou** (`exit ≠ 0`), que **venceu de idade** e cujo **conteúdo mudou** desde a prova.
- **`order --status`** (`lib/core-order-state.sh`, `_order_evidence_match`, perto da linha 164) só
  confere `exit=0` e `wtree_after` igual à árvore do tip. **Não olha** árvore-mudou-durante-a-corrida,
  nem comando, nem idade.
- **`order --accept`** (`lib/cmd-order-accept.sh`, perto da linha 233, via `_order_verif_gate` e
  `_order_proof_tree`) tem o **seu** critério, que não é nenhum dos dois.

Consequência: um recibo que o `evidence --check` chama de VENCIDO pode aparecer como `provada` no
`--status` e ser aceito (ou o contrário). A prova — o que o método existe para tornar mecânica — tem
três verdades. O reparo é **uma função de veredito, chamada pelos três**.

## O que entrega

1. **Reprodução primeiro, com teste, antes de qualquer código.** Um teste que monta recibos de fixture e
   mostra a discordância: para cada caso, o veredito dos três leitores lado a lado.
   Casos mínimos (cada um em um recibo próprio): (a) árvore mudou durante a corrida
   (`wtree_before ≠ wtree_after`, `exit 0`, `wtree_after = tip`); (b) comando diferente do declarado
   (`cmd_match=no`); (c) hash do recibo ≠ `commands.<label>`; (d) idade acima do teto;
   (e) `exit ≠ 0`; (f) recibo válido. **Saída colada** do vermelho: onde os três divergem hoje.
2. **Uma função só**, no núcleo (`lib/core-evidence.sh` ou arquivo novo `lib/core-proof-verdict.sh`,
   carregado na hora), que recebe o recibo + o contexto (projeto, rótulo, árvore do tip, comando
   declarado, teto de idade) e devolve **o veredito e os motivos** — a mesma lista de motivos que o
   `_ev_cmd_reasons` produz hoje. `evidence --check`, `order --status` e `order --accept` **chamam essa
   função** e não mantêm critério próprio. Nada de segunda cópia da regra.
3. **Carga continua só qualificador**, como a 055 estabeleceu: load e medições inconclusivas **não**
   entram no veredito, só no texto.
4. **Compatível:** formato do recibo inalterado; `suite` legado, `suite-N` e `order-N` seguem lidos como
   hoje (ordens 048/055); o texto de `evidence --check` não muda para recibo que já era válido ou
   vencido pelos mesmos motivos.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-order-060-verificador-unico.sh`] os seis casos da reprodução dão o
  **mesmo veredito nos três leitores**; vermelho antes (colado), verde depois.
- [oráculo: o mesmo teste] `grep` prova que `evidence --check`, `_order_evidence_match`/`_order_verif_report`
  e o gate do `--accept` chamam a função única, e que **nenhum deles** compara `wtree_before`,
  `cmd_match` ou idade por conta própria.
- [oráculo: `bash tests/cli/test-order-055-carga-nao-invalida.sh`] a regra da 055 segue verde.
- [oráculo: `bash tests/run-all.sh`] suíte do Maestro verde; `habits` na catraca, **régua não sobe**
  (função nova acima de 60 linhas reprova; arquivo acima de 400 também).
- [humano] o Diretor lê a tabela "caso × leitor" do relatório e confirma que o veredito único é o
  rigoroso do `evidence --check`.

## Ask-First

- Se unificar **endurecer** o `--status` ou o `--accept` de forma que uma ordem hoje `aceita` deixe de
  derivar como `aceita` (carimbo antigo, recibo antigo), PARE: ordens já aceitas não podem mudar de
  estado por esta ordem. Reporte quantas seriam afetadas (`maestro order --list`).
- Se o veredito único exigir mudar o **formato** do recibo, PARE (DATA_MODEL).
- Se a função única custar mais de ~50 ms por chamada no `--status` (ele roda no Stop de turno), reporte a
  medição antes de seguir (a 056 acabou de cortar esse custo).
- **Toca `lib/`, autoprotegida:** a entrega é UM patch em `docs/patches/060-*.patch`, feito em clone
  sandbox FORA do repo, testado antes e depois, aplicado pelo Capitão com um `git apply`.

## Como sai

`tests/` e `docs/` direto no branch; `lib/` em **UM patch protegido**. Emendas no mesmo changeset:
API_SPEC (contrato do veredito único: quem chama e quais motivos), DATA_MODEL só se o formato mudar
(não deve), ENGINEERING_SPEC (a prova tem uma verdade só) e CHANGELOG (Fixed).

## Prova exigida

- Vermelho antes e verde depois do teste de reprodução, saídas coladas.
- Controle negativo: recibo válido continua VÁLIDO nos três; ordens já aceitas continuam `aceita`.
- Suíte completa `SUITE OK`, sozinha no worktree; recibos `order-60`, `suite-60` e `suite` (legado) no tip
  com o patch aplicado; `habits` dentro da catraca.

## Turno

- fatia: reproduzir a discordância dos três leitores com teste e levar os três a chamar uma função única de veredito
- fim: o teste dos seis casos sai vermelho antes (colado) e verde depois; `bash tests/run-all.sh` sai 0; patch protegido pronto e `git apply --check` ok
- teto: 3
- fora: qualquer outra mudança — formato do recibo, texto de comandos não relacionados, a regra da 055, o daemon, aplicar o patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Escrita de código só com Edit ou Write, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`,
> `python -c`, `cat >` ou redirecionamento (`>`, `>>`) para escrever código ou teste. O Bash serve para
> rodar, ler e medir. (O guard da ordem 047 barra isso em `self_paths`; aqui a regra vale também fora
> deles.) Patch gerado por `git diff` do sandbox para `docs/patches/` é a única saída por redirecionamento
> admitida, e só para esse arquivo.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/060-verificador-unico-de-prova-evide`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-60 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), com a v59 item 3 do spock como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 060` (você não fecha a própria ordem).
