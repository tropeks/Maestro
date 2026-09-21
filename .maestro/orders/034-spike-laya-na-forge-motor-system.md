<!-- maestro-order v1
id: 034
ts: 2026-09-20T09:05:25-03:00
epoch: 1789905925
head: dd6288b19692d54cf507748fd71d568cf744392d
branch: spike/034-laya-na-forge
frozen: vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
-->
# Ordem 034 — spike Laya na forge: motor System 1 local medido com o mesmo instrumento do Jev — acc, Brier, ECE, p50, disco e RAM

## Por que esta ordem existe

Ordem do Capitão, 2026-09-20: **testa antes de decidir.** O Laya
(`convaiinnovations/laya`, Apache-2.0, `pip install laya` 0.3.4) é um motor System 1
não-autorregressivo de decisão TIPADA — `choice`, `score`, `noul` — a mesma forma de
pergunta que a 028 mede no Jev, com uma diferença que importa para este projeto: **ele
roda local, na CPU, sem chave e sem rede em tempo de inferência.**

Isso toca a trava que a 028 declarou por escrito. Lá, ligar o Jev em runtime colide com
*"Nenhuma dependência de rede em runtime, exceto o fetch do auto-update"* (INTENT v4
**Limites**; CLAUDE.md "Proibido"). Um motor local não tem esse conflito: o download do
checkpoint é instalação, não runtime. Se o Laya calibrar, a conversa sobre dar poder a um
System 1 muda de "precisa emendar o INTENT" para "cabe no limite como ele está escrito".

Esta ordem NÃO decide isso. Ela produz o número que torna a decisão possível.

## Correção de fato, antes de qualquer medição

O pedido cita *"as 481 decisões do log real, mesmas perguntas tipadas usadas para o Jev"*.
**Esse corpus não existe na forma descrita, e a 028 já diz por quê:**

- O log **não tem prompt**, por fronteira dura (*"Logs: só metadados; jamais prompt"*).
  As 481 decisões são a contagem da janela de 30 dias que disparou o gatilho da Fase 2 —
  metadado, sem a entrada do usuário. Não há "pergunta tipada" a extrair delas.
- O corpus com ENTRADA é um só: `tests/eval/cases.yaml`, **15 casos** com `prompt`
  verbatim e rótulo humano (`expected`).
- O corpus de DESFECHO é o M1 da 028: **181 pares 1:1** (`accepted` 142 · `rework` 36 ·
  `killed` 3), casando cada `outcome` com a `decision` mais recente da mesma sessão.
- **O replay do Jev ainda não rodou.** A 028 está ABERTA e sem prova. Não existe tabela
  dele para pôr lado a lado hoje — existe o FORMATO que a 028 prescreve.

Portanto esta ordem mede o Laya nos corpora que existem, no formato da 028, com um
harness que serve aos DOIS motores. O lado a lado fica pronto para ser preenchido quando
a 028 rodar; o que falta é o Jev, não o instrumento.

## O que entra

Um harness em `tests/eval/`, **sem efeito** (não grava record, não chama `maestro decide`,
não escreve em `~/.maestro/`), com o motor atrás de uma interface pequena — `laya` agora,
`jev` quando a 028 rodar — e um TSV por corpus.

**M1 — desfecho (n=181, metadado):** o Laya prevê `accepted`/`rework`/`killed` a partir de
`project`, `workflow`, `mode`, `agents`, `tool`, `file_ext`. **A base rate é 78,5%** e vai
impressa ao lado de toda acurácia — acurácia sem ela é resultado proibido (regra da 028).
O número que decide é a **recall de `rework`** (n=36), reportada isolada com o n. `killed`
(n=3) reporta contagem e não deriva nada.

**M2 — roteamento (n=15, com entrada):** concordância por eixo (`workflow`, `mode`,
`agents`), **separada, nunca uma nota só**. Os `ambiguous: true` num bloco à parte:
confiança alta em caso ambíguo é excesso de confiança, e é o sinal mais informativo do
experimento. Com n=15, calibração por faixa é **indicativa, não conclusiva**, e o
relatório diz isso na mesma linha do número.

**Calibração:** Brier e ECE (15 faixas, com o n de cada uma) ANTES e DEPOIS de refit de
temperatura, com **split holdout**: a temperatura é ajustada só no split de ajuste e
medida só no de teste. Em M1 o split é estratificado por classe (o `rework` é o que
importa). Em M2, com n=15, **não há split honesto**: o refit de temperatura sai marcado
como não-conclusivo, ou não sai.

**Custo de máquina, medido e não estimado:** latência p50 **e p95** por pergunta na CPU da
forge (8 núcleos, sem GPU), com o número de threads do torch fixado e impresso; disco
ocupado em `~/.cache/huggingface` por checkpoint; pico de RSS do processo.

Números já levantados, para dimensionar e não para dispensar a medição: `laya` 0.3.4
depende de `torch>=2.0`, `transformers>=4.45`, `safetensors`, `huggingface_hub`, `numpy`;
o repo `convaiinnovations/laya` tem **2,37 GB** em três checkpoints e o
`laya-multilingual` **678 MB**; a forge tem 279 GB livres, 62 GB de RAM e 8 núcleos.

## Limites duros

- **Nada sai da forge.** Rede só na instalação (`pip` e download do checkpoint para
  `~/.cache/huggingface`); a medição roda com a rede irrelevante, e o script não fala com
  serviço nenhum. Nenhum dado do log é enviado a lugar algum — é esse o ponto do teste.
- **Nenhum PHI, nenhum dado do Vitali, nenhum prompt no TSV.** M2 usa os prompts de
  `cases.yaml`, que já são fixture do repo; M1 é metadado. O TSV publica rótulo,
  predição, confiança e n — nunca texto de entrada.
- Zonas congeladas: `vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/`.
  Nada de produção muda. O experimento vive inteiro em `tests/eval/`.
- **Nenhum limiar é escrito em lugar nenhum.** Limiar é decisão do Capitão, depois, com o
  número na mão (mesma regra da 028).
- O harness **pula com honestidade** (exit 0, dizendo o que faltou) se o pacote ou o
  checkpoint não estiverem presentes — suíte nunca reprova por dependência de terceiro
  (Prioridades §1).
- Spike: nada aqui entra em produção sem ordem própria. Resultado negativo medido é
  desfecho, não fracasso (E25).

## Prova exigida

- TSV por corpus em `tests/eval/`, com n por faixa e a **base rate impressa**.
- Tabela final no formato da 028 — faixa de confiança × acerto observado × n —, com
  faixa de n < 10 marcada como não-conclusiva no próprio TSV.
- acc (com base rate ao lado), Brier e ECE **antes e depois** do refit de temperatura, no
  split de teste; recall de `rework` isolada.
- p50 e p95 de latência na CPU, threads do torch declaradas, disco por checkpoint e pico
  de RSS.
- Relatório com a coluna do Jev VAZIA e dita vazia — a 028 não rodou —, e o harness
  provando que a mesma chamada serve aos dois motores.
- Suíte completa verde; `doctor` sem mudança de veredito.
- Relato ao Diretor por `director.report`.

## Resultado medido (2026-09-20) — negativo, e com o número

**Veredito: o Laya base, zero-shot, não serve para nenhum dos dois usos medidos.** Não é
falha do instrumento; é o comportamento que o próprio README do Laya documenta para o
checkpoint base.

| medida | Laya (base, zero-shot) | Jev |
|---|---|---|
| M1 acurácia (n=182) | **0,527** — contra base rate **0,786** | — (028 não rodou) |
| M1 recall de `rework` (n=36) | **0,167** (6/36) | — |
| M1 `killed` (n=3) | 1/3 — contagem apenas | — |
| M2 workflow (n=15) | 0,267 | — |
| M2 mode (n=15) | 0,267 | — |
| M2 agents (n=15) | 0,067 | — |

**Calibração (sobre `p_pred` = `probabilities[predicted]`, o posterior real):**

- Brier 0,266 → 0,252 · ECE 0,131 → 0,066 com refit de temperatura.
- **A melhora é degenerada.** A temperatura ótima empurra tudo para 0,5: a NLL converge
  para log(2) quando T→∞, e em T=5 já está a 0,0017 do piso. Calibrar aqui é o mesmo que
  jogar a confiança fora.
- Conferido de forma independente, sobre o TSV: **Brier do `p_pred` cru = 0,262, PIOR que
  o preditor constante 0,5 (0,250)**; e **AUC(confiança → acerto) = 0,456** — abaixo de
  0,5, ou seja, **nenhum poder de discriminação**. A faixa inteira de `p_pred` vive entre
  0,34 e 0,70 num problema de 3 classes: o modelo é quase indiferente.

**A ressalva que impede a generalização:** isso é M1, metadado. A confiança pode não
discriminar porque a FEATURE não carrega sinal, não porque o motor é ruim. Em M2, com
prompt real, o quadro é outro e pior de um jeito diferente: ele erra **com alta
confiança** justamente nos casos ambíguos — `infra-pve-restart/agents` errou com
`p_pred=0,999`, `ts-console-logger/agents` com 0,964, `pg-campo-cnpj/agents` com 0,959. O
p_pred médio nos erros ambíguos é 0,678 contra 0,598 nos não-ambíguos. Um limiar de
confiança sobre este motor, nesta configuração, deixaria passar exatamente os casos em
que ele mais erra.

**Correção de instrumento, registrada para quem ler depois:** a primeira rodada leu o
campo `confidence` do Laya como se fosse a probabilidade da classe prevista. Não é —
`laya/common.py:200` define `confidence_from_probs` como entropia de Shannon normalizada,
`1 - H(p)/log(k)`. O sinal foi um número impossível: 0,0072 de "confiança" no argmax de 3
classes. **As tabelas de calibração da primeira rodada estão mortas**; acurácia, recall e
concordância não mudaram, porque saem do argmax.

**Custo de máquina na forge:** p50 4.076 ms · p95 5.534 ms por pergunta (4 threads, carga
1,93 na largada) · pico de RSS 5,6 GiB · 2,3 GB de disco (o bundle inteiro: carregar o
checkpoint inglês baixa os três — papercut registrado).

## Adendo — viabilidade de fine-tuning (só leitura, nada treinado)

Pedido do Capitão depois da calibração refeita. **Nada foi treinado, nada foi baixado além
do que o spike já tinha.** Tudo aqui é leitura da documentação do Laya e medição do nosso
próprio log.

### O README do Laya já previa o nosso número

Duas linhas do `README.md` do repo HF, textuais:

> *"The base checkpoints sit below the majority-class baseline here — the capability on
> this benchmark comes from fine-tuning, which is what the fine-tuning notebook is for."*

> *"Base checkpoints are near chance on typed-decisions zero-shot — 0.362 here and 0.352
> for multilingual, against a 0.318 random and 0.461 majority-class baseline. Laya is a
> fast base to specialise, not a zero-shot decision engine."*

O nosso M1 reproduz o padrão de forma independente: **0,527 contra base rate 0,786**.
Zero-shot abaixo da classe majoritária é o comportamento DOCUMENTADO do checkpoint base,
não uma surpresa. Consequência para a leitura do spike: a 034 mediu o Laya **base,
zero-shot** — ela não mede o teto do Laya **fine-tunado**, e não deve ser citada como se
medisse.

### O que o notebook exige

Fonte: `notebooks/laya_finetune_typed_decisions_2xT4_kaggle.ipynb`
(github.com/NandhaKishorM/laya), lido na íntegra.

| exigência | o que o notebook pede |
|---|---|
| formato do dado | linha = `state` (JSON) · `questions` (dict de perguntas tipadas) · `gold` (dict `qid` → `{probabilities: {opção: p}}`) |
| rótulo | **distribuição do teacher**, não rótulo duro — o alvo é `target[]` normalizado; `label` é só o argmax dele |
| n do treino | **1.200 casos = 6.000 decisões tipadas** (≈5 perguntas por caso) |
| n do teste | 400 casos = 2.000 decisões |
| hiperparâmetros | `EPOCHS=4` · `MICRO_BATCH=8` · `GRAD_ACCUM=4` (lote efetivo 64) · GRPO `GROUP_SIZE=4` · `LR_ENCODER=2.5e-5` · `LR_HEAD=1.0e-4` · ruído 0,4→0,1 |
| hardware | `torchrun --nproc_per_node=2` com `init_process_group("nccl")` + `autocast` |
| tempo | **~4 a 6 minutos** em 2×T4 |

**Roda em CPU? Não como está.** O `nccl` é backend de GPU; rodar na forge exigiria trocar
para `gloo`, desligar o `autocast` e cair para um processo só — alteração de código, não
de flag.

**Estimativa de custo em CPU, derivada da NOSSA medição** (e declarada como estimativa,
não como número medido): 6.000 sequências × 4 épocas × GRPO `GROUP_SIZE=4` ≈ 96.000
forwards, mais o backward, que costuma custar ~2× o forward → ordem de 10⁵ forwards
equivalentes. Com o p50 que medimos nesta forge (4,1 s por pergunta, 4 threads; 0,87 s na
corrida sob outra carga), isso dá **dezenas a centenas de horas de CPU** — dias, contra 4
a 6 minutos em duas T4. A conclusão é robusta à faixa: fine-tuning aqui é trabalho de GPU
alugada, não da forge.

### Quantos exemplos rotulados o Maestro produz por mês

Medido no log real, `~/.maestro/logs/routing.jsonl`, janela do primeiro ao último
`outcome`: **2026-09-04 → 2026-09-20, 15,65 dias, 182 desfechos.**

| classe | n | por dia | por mês (30d) |
|---|---|---|---|
| `accepted` | 143 | 9,14 | **274** |
| `rework` | 36 | 2,30 | **69** |
| `killed` | 3 | 0,19 | **6** |
| **total** | **182** | **11,63** | **349** |

O ritmo é em rajada, não constante: dias de 41–46 desfechos ao lado de dias de 1 a 5.

**O que isso dá, contra a escala do notebook:**

- 6.000 decisões rotuladas (escala de treino): **17,2 meses**.
- 2.000 decisões (escala do split de teste): **5,7 meses**.
- 1.000 exemplos da classe que interessa (`rework`): **14,5 meses**.

E há três limites que o número de exemplos não resolve:

1. **Uma pergunta por caso, não cinco.** O notebook conta 5 perguntas por caso; o desfecho
   do Maestro é UMA pergunta de 3 opções. A comparação de escala acima já é generosa.
2. **Rótulo duro, sem distribuição de teacher.** O RLCD treina contra a distribuição
   completa; nós temos `accepted`/`rework`/`killed` e mais nada. Produzir distribuição
   exigiria um teacher rotulando — que é justamente o custo que se queria evitar.
3. **Entrada sem prompt, por fronteira dura.** O estado é metadado. Nenhum volume de
   exemplos cria sinal que o metadado não carrega.

### O teste barato que vem ANTES de qualquer GPU

O limite 3 é uma hipótese testável e custa segundos de CPU: **ajustar um modelo trivial
(regressão logística ou árvore) sobre as MESMAS features de metadado dos 182 pares, com o
mesmo split holdout, e ver se ele bate a base rate de 78,6%.**

- Se o modelo trivial **não** bate a base rate, o metadado não carrega sinal, e nenhum
  fine-tuning de 421M parâmetros muda isso — a resposta custou segundos em vez de horas
  de T4 alugada.
- Se ele **bate**, existe sinal, e aí a conversa sobre fine-tuning passa a ter base — com
  o teto do modelo trivial como piso a superar.

Fica como recomendação medida, não como ordem: é ordem própria, e é do Capitão.

### O harness

Permanece como instrumento, não como resultado: `predict(state, questions)` em
`laya_engine.py` é a única superfície a trocar para rodar o **replay do Jev da 028**. A
coluna do Jev nas tabelas continua vazia e dita vazia até a 028 rodar.

## Contrato de execução
- Trabalhe APENAS no branch `spike/034-laya-na-forge`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
- Prove com o ledger: `maestro evidence --record --label order-34 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 034` (você não fecha a própria ordem).
accepted_at: 2026-09-20T13:28:01-03:00
accepted_session: desconhecido
accepted_tree: e5efe43a20d64028392bf0036e21a46b890adb3c
accepted_intent: 4
