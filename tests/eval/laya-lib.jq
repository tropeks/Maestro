# tests/eval/laya-lib.jq — biblioteca de estatística do spike Laya (ordem 034).
#
# Módulo jq (importado com `import "laya-lib" as lib;` e `-L` apontando para
# este diretório). Faz UMA coisa: transforma uma lista de julgamentos
# {correct: 0|1, confidence: <float 0..1>} em acurácia, Brier, tabela de ECE
# em 15 faixas (com n por faixa) e refit de temperatura por NLL — sem nunca
# tocar prompt, caminho de arquivo ou qualquer coisa além desses dois números
# por registro. Nada aqui decide limiar; só mede.
#
# A confiança que laya devolve já é uma PROBABILIDADE (não um logit cru — o
# pacote não expõe logit). O refit de temperatura por NLL escalar, portanto,
# opera no domínio logit(confidence): converte confidence -> logit, divide
# por T, volta com sigmoid. É a leitura padrão de "temperature scaling" para
# uma API que só expõe probabilidade — documentado aqui porque é uma escolha
# de método, não uma obviedade da literatura original (Guo et al. operam
# sobre logits nativos do classificador, que laya não expõe).

def eps: 0.000001;
def clampp: if . < eps then eps elif . > (1 - eps) then (1 - eps) else . end;

def logit: clampp | (. / (1 - .)) | log;
def sigmoid: 1 / (1 + ((-.) | exp));

# ---------------------------------------------------------------- acurácia
def accuracy(xs):
  (xs | length) as $n
  | if $n == 0 then null else (xs | map(.correct) | add) / $n end;

# -------------------------------------------------------------------- Brier
# Brier binário de calibração de confiança: (confidence - correct)^2, médio.
# (Não é o Brier multiclasse de distribuição completa — laya devolve só a
# probabilidade do rótulo ESCOLHIDO, então o alvo mensurável é "essa
# confiança está calibrada com o acerto?", que é a leitura que a tabela da
# ordem pede: faixa de confiança × acerto observado.)
def brier(xs):
  (xs | length) as $n
  | if $n == 0 then null
    else (xs | map((.confidence - .correct) | . * .) | add) / $n
    end;

# --------------------------------------------------------------------- NLL
def nll_at(xs; $T):
  (xs | length) as $n
  | if $n == 0 then null
    else
      (xs | map(
        (.confidence | logit | (. / $T) | sigmoid | clampp) as $p
        | -( (.correct * ($p | log)) + ((1 - .correct) * ((1 - $p) | log)) )
      ) | add) / $n
    end;

# Grid search de T minimizando NLL no split de AJUSTE. Grade fixa e
# documentada (não é gradiente, é spike): 0.05 a 5.00, passo 0.05 — 100
# pontos, barato e determinístico, sem dependência de otimizador externo.
def best_temperature(xs):
  if (xs | length) == 0 then 1.0
  else
    ([range(1; 101) | (. * 0.05)]
     | map({t: ., nll: nll_at(xs; .)})
     | min_by(.nll)
     | .t)
  end;

def apply_temperature(xs; $T):
  xs | map(.confidence = (.confidence | logit | (. / $T) | sigmoid | clampp));

# --------------------------------------------------------------------- ECE
# 15 faixas fixas [0,1/15) .. [14/15,1]. Cada faixa reporta n, confiança
# média da faixa, acerto observado da faixa; ECE = soma ponderada por n de
# |confiança_média - acerto_observado|. Faixa com n<10 marcada não-conclusiva
# — ela ainda entra na soma do ECE (é dado real), só não deriva LEITURA
# isolada no TSV.
def ece_table(xs; $bins):
  (xs | length) as $n
  | [range(0; $bins) as $b
     | (xs | map(select((.confidence * $bins | floor) as $f | ($f == $b) or ($b == $bins - 1 and $f >= $bins))))
     | {
         faixa: $b,
         lo: ($b / $bins), hi: (($b + 1) / $bins),
         n: length,
         conf_media: (if length == 0 then null else (map(.confidence) | add) / length end),
         acerto_observado: (if length == 0 then null else (map(.correct) | add) / length end),
         conclusiva: (length >= 10)
       }]
  | . as $rows
  | { rows: $rows,
      ece: (if $n == 0 then null
            else ([$rows[] | select(.n > 0) | (.n * ((.conf_media - .acerto_observado) | if . < 0 then -. else . end))] | add) / $n
            end) };

# ------------------------------------------------------- split estratificado
# Split determinístico 50/50 por classe via hash estável do `id` do registro
# (sem RNG, sem seed externa: mesma entrada => mesmo split, sempre — condição
# para "medido, não estimado"). `class_key` é o campo usado para estratificar
# (ex.: .true_label em M1). Metade par do hash -> ajuste; metade ímpar -> teste.
def stable_bit($s):
  ($s | explode | add) % 2;

def split_stratified(xs; $id_field; $class_field):
  (xs | group_by(.[$class_field]))
  | map(
      . as $grp
      | ($grp | map(select(stable_bit(.[$id_field]) == 0))) as $ajuste
      | ($grp | map(select(stable_bit(.[$id_field]) == 1))) as $teste
      | {ajuste: $ajuste, teste: $teste}
    )
  | { ajuste: (map(.ajuste) | add // []), teste: (map(.teste) | add // []) };
