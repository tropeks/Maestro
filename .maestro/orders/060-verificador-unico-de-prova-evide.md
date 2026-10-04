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
   (`cmd_match=no`); (c) hash do recibo ≠ `commands.<label>`; (d) recibo **velho e idêntico ao tip** (idade acima do
   antigo teto; V nos três, ver "Decisões do Diretor — turno 2");
   (e) `exit ≠ 0`; (f) recibo válido. **Saída colada** do vermelho: onde os três divergem hoje.
2. **Uma função só**, no núcleo (`lib/core-evidence.sh` ou arquivo novo `lib/core-proof-verdict.sh`,
   carregado na hora), que recebe o recibo + o contexto (projeto, rótulo, árvore do tip, comando
   declarado; **sem teto de idade**) e devolve **o veredito e os motivos** — a mesma lista de motivos que o
   `_ev_cmd_reasons` produz hoje. `evidence --check`, `order --status` e `order --accept` **chamam essa
   função** e não mantêm critério próprio. Nada de segunda cópia da regra.
3. **Carga continua só qualificador**, como a 055 estabeleceu: load e medições inconclusivas **não**
   entram no veredito, só no texto.
4. **Compatível:** formato do recibo inalterado; `suite` legado, `suite-N` e `order-N` seguem lidos como
   hoje (ordens 048/055); o texto de `evidence --check` não muda para recibo que já era válido ou
   vencido pelos mesmos motivos. **Única exceção, decidida pelo Diretor:** o recibo que só estava
   VENCIDO por idade (conteúdo idêntico ao tip) passa a VÁLIDO.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-order-060-verificador-unico.sh`] os seis casos da reprodução dão o
  **mesmo veredito nos três leitores**; vermelho antes (colado), verde depois.
- [oráculo: o mesmo teste] `grep` prova que `evidence --check`, `_order_evidence_match`/`_order_verif_report`
  e o gate do `--accept` chamam a função única, e que **nenhum deles** compara `wtree_before`,
  `cmd_match` por conta própria, e que **nenhum reprova por idade** (a idade só é impressa).
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

## Decisões do Diretor — turno 2

Registradas em 04/10 após o turno 1 (teste de reprodução, emendas e patch já no branch, `c76627b`). Valem
como contrato; o executor não as reabre sem prova nova. **Substituem** o que o turno 1 assumiu sobre idade.

1. **Veredito único RIGOROSO: sim.** Os critérios do `evidence --check` valem para os **três** leitores
   (`evidence --check`, `order --status`, `order --accept`): **exit** (`exit = 0`), **árvore durante a
   corrida** (`wtree_before = wtree_after`), **comando declarado** (`cmd_match ≠ no` e hash do recibo =
   `commands.<label>`) e **identidade com o tip** (conteúdo igual ao do tip, pela mesma igualdade
   `maestro_tree_same` da ordem 044). Reprovou em qualquer um: VENCIDO nos três, com os mesmos motivos.
2. **Idade NÃO invalida prova em nenhum leitor.** Recibo com **conteúdo idêntico ao tip continua VÁLIDO,
   ponto.** Motivo (v59, "enxugar"): idade não prova nada sobre a árvore e só gera regravação de suíte.
   `evidence --check` **mostra a idade como informação** (já impressa no texto: "exit 0 há Nmin"), **sem
   reprovar**. O motivo "idade no teto" sai da lista de motivos da função única; o teto de idade deixa
   de ser parâmetro dela.
3. **O patch e o teste mudam de acordo.** O caso (d) do teste de reprodução vira "recibo velho e
   idêntico ao tip": **V nos três leitores** (e continua V com idade enorme). Os casos (a), (b), (c) e (e)
   seguem V/vencido pelos motivos de sempre; (f) segue V. O patch protegido do turno 1 é **refeito** a
   partir do tip do branch: a função única sem o ramo de idade, os três chamando-a, a idade só impressa.
   Testes existentes que assertam "idade vence o recibo" (procurar com `grep -rn "idade" tests/`) são
   **ajustados ao novo contrato** e a mudança é listada no relatório, teste a teste.
4. **Suíte completa no sandbox depois do conserto**, não só `test-order*`: com o patch aplicado no clone
   sandbox FORA do repo, `bash tests/run-all.sh` sozinha (uma suíte pesada por vez, `PYTHONDONTWRITEBYTECODE=1`),
   `SUITE OK` e `habits` na catraca (régua não sobe) antes de declarar o patch pronto.

**Ask-First deste turno** (somam-se aos da ordem):
- Se tirar a idade deixar **código morto** que não é desta ordem (ex.: `deferred_by` congelando idade, ordem
  013; a constante do teto), **não o remova**: liste no relatório. "Qualquer outra mudança" segue fora.
- Se um teste fora de `test-order*`/`test-evidence*` quebrar por causa da idade, pare e cole o FAIL antes de
  ajustá-lo.
- A emenda de contrato (API_SPEC, DATA_MODEL §recibo, ENGINEERING_SPEC) e o CHANGELOG passam a dizer "idade
  é informação, nunca veredito", no MESMO changeset.

## Turno

- fatia: turno 2 — aplicar as decisões 1 a 4: veredito único rigoroso sem idade, caso de recibo velho e idêntico V nos três, patch refeito
- fim: o teste de reprodução (caso "velho e idêntico" V nos três) sai vermelho antes (colado) e verde depois; `bash tests/run-all.sh` completa no sandbox com o patch aplicado sai 0 (SUITE OK), `habits` na catraca e `git apply --check` ok no worktree
- teto: 3
- fora: qualquer outra mudança — formato do recibo, texto de comandos não relacionados, a regra da 055, remover código morto da idade, o daemon, aplicar o patch e tocar vendor/
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
