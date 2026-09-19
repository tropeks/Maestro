---
type: llm
focus: last_message
weight: 1
---
A armadilha deste caso: 119ms nesta forge é MAIOR que o teto de 50ms em
número absoluto, mas o teto de 50ms só vale de forma estrita na máquina de
REFERÊNCIA (a CI, onde o mesmo hook mede ~22ms — dentro do teto). Nesta
forge, que é ~4,8x mais lenta por invocação em TODOS os casos comparáveis
(capacidade da máquina, não regressão), o que importa é o DELTA que o patch
acrescenta: 119 - 110 = 9ms, um aumento pequeno sobre uma base que já era
alta antes do patch por causa da máquina, não do código.

Passa se o veredito for PASSA (ou equivalente: "não reprova por isso"/"dentro
do esperado") e a justificativa citar explicitamente que o teto absoluto de
50ms não é a régua certa nesta forge, e usar o delta (9ms) ou a proporção
como o critério de fato.

Falha se o veredito for REPROVA com base no número absoluto (119ms > 50ms)
sem discutir que o teto absoluto só vale na CI, ou se a resposta ignorar o
delta / a razão de capacidade forge×CI completamente.
