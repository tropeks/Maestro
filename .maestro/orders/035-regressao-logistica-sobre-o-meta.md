<!-- maestro-order v1
id: 035
ts: 2026-09-20T14:19:40-03:00
epoch: 1789924780
head: e766158583023ab4f73e95cb24cb2d58125f2a0d
branch: fix/035-baseline-metadado
frozen: vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
-->
# Ordem 035 — regressao logistica sobre o metadado: o teste barato que decide se ha sinal antes de qualquer GPU

## Por que esta ordem existe

A 034 mediu o Laya base, zero-shot, sobre os 182 pares de desfecho: **acurácia 0,527
contra base rate 0,786**, recall de `rework` 0,167, e a confiança sem poder de
discriminação (AUC 0,456, Brier do posterior cru PIOR que o preditor constante 0,5).

Esse resultado tem DUAS leituras, e a 034 não pode separá-las:

1. o motor é fraco nesta tarefa; ou
2. **o metadado não carrega sinal** — e nenhum motor, de nenhum tamanho, extrai o que a
   feature não tem.

Esta ordem separa as duas, e custa segundos de CPU. Se um modelo trivial sobre as MESMAS
features não bater a base rate, a leitura 2 está provada e a conversa sobre fine-tuning
(17,2 meses de rótulos, horas de T4 alugada — ver o adendo da 034) morre antes de começar,
com número na mão.

## Critério registrado ANTES de medir

Isto é pré-registro: o critério vale como está escrito aqui, e não se reescreve depois de
ver o resultado.

- **Bate a base rate** = acurácia no split de TESTE acima de 0,786, com o intervalo de
  confiança de 95% (binomial, n=92) e o teste binomial exato contra 0,786 reportados ao
  lado. Acurácia sozinha não decide nada.
- **Não bateu → conclusão: o metadado não tem sinal.** É desfecho, não fracasso (E25).
- Um recall de `rework` maior que zero com acurácia abaixo da base rate é resultado
  INTERESSANTE e deve ser reportado como tal — pegar o que deu errado é o uso com valor
  (regra da 028), mesmo quando a acurácia global perde do preditor constante.

## O que entra

Regressão logística multinomial sobre as MESMAS features dos MESMOS 182 pares:
`project`, `workflow`, `mode`, `agents`, `tool`, `file_ext` → `accepted`/`rework`/`killed`.

**O split tem de ser IDÊNTICO ao da 034, não apenas "estratificado".** Reuse
`split_stratified` de `tests/eval/laya-lib.jq` com o mesmo campo de id: ele particiona por
hash estável, sem RNG e sem seed (mesma entrada → mesmo split, sempre). Split diferente
não compara com a 034 — compara com ruído. Mesma coisa para os pares: reuse
`tests/eval/m1-pairs.jq`, não reescreva a derivação.

**Métricas, nas MESMAS definições da 034** (senão os números não são comparáveis):

- acurácia no teste, **sempre com a base rate ao lado**, mais IC 95% e binomial exato.
- **recall de `rework`** isolada, com o n. `killed` (n=3) só contagem.
- Brier e ECE sobre `p_pred` = probabilidade da classe prevista × acerto, como a 034 faz.
- **AUC(confiança → acerto)** — foi o número que matou a confiança do Laya; sem ele não dá
  para dizer se a do modelo trivial é melhor.
- Linha de referência obrigatória no TSV: o **preditor constante** (sempre `accepted`),
  com acurácia 0,786 e Brier de referência.

## Limites duros

- **Tudo em `tests/eval/`.** Congelado: `vendor/ agents/ config/routing-table.yaml hooks/
  bin/ src/ lib/`. Sem GPU, sem rede em tempo de execução.
- **Nenhuma dependência nova no caminho do plugin.** Ou numpy puro (regressão logística
  com L2 em ~40 linhas é determinística e suficiente para n=182), ou a venv que a 034
  deixou. Se usar a venv, o driver **pula com honestidade (exit 0)** quando ela não existe.
- **Determinismo obrigatório**: mesma entrada → mesmos números, sempre. Sem seed aleatória;
  se houver inicialização, ela é fixa e está impressa no TSV.
- **Nenhum hiperparâmetro escolhido olhando o split de teste.** O L2 é fixo e declarado
  antes, ou sai de validação cruzada DENTRO do split de ajuste. Ajustar no teste é o modo
  mais fácil de fabricar sinal que não existe.
- **Reporte a contagem de features depois do one-hot ao lado de n=90 do ajuste.** Com
  `project` (16 valores) e `agents` de alta cardinalidade, é provável haver mais colunas
  que linhas — isso não invalida o teste, mas tem de estar visível, porque é a explicação
  alternativa óbvia para qualquer acurácia alta.
- Sem efeito: não grava record, não chama `maestro decide`, não escreve em `~/.maestro/`.
- **Nenhum limiar é escrito em lugar nenhum.**

## Prova exigida

- `tests/eval/baseline-metadado.tsv`: uma linha por caso do teste (id, rótulo, predição,
  `p_pred`, acerto) e o cabeçalho comentado com acurácia, base rate, IC 95%, p do binomial
  exato, recall de `rework`, Brier, ECE, AUC, n de features × n do ajuste.
- Tabela final comparando **modelo trivial × Laya × preditor constante**, nas mesmas
  colunas — a da 034 tem os números do Laya prontos para copiar.
- `--selftest` no estilo do `laya-spike.sh`, com fixture sintética (não exige venv).
- Suíte completa verde; `doctor` sem mudança de veredito; habits dentro da catraca.
- `maestro evidence --record --label order-35 -- bash tests/run-all.sh` no tip do branch.
- Relato ao Diretor por `director.report`.

## Contrato de execução
- Trabalhe APENAS no branch `fix/035-baseline-metadado`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
- Prove com o ledger: `maestro evidence --record --label order-35 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 035` (você não fecha a própria ordem).
