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

## Contrato de execução
- Trabalhe APENAS no branch `spike/034-laya-na-forge`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
- Prove com o ledger: `maestro evidence --record --label order-34 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 034` (você não fecha a própria ordem).
