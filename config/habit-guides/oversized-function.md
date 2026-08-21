**oversized-function** — função longa não é infração de limite: é sinal de que ela
faz coisas demais. Cada bloco com nome próprio ("valida", "persiste", "notifica")
é uma função querendo nascer. Extraia por RESPONSABILIDADE, não por contagem —
cortar no meio só para caber no número é burlar a métrica, não resolver o design.
Não faça: mover metade para uma função `_helper()` sem nome de domínio.
