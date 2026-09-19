---
max_turns: 4
timeout_seconds: 90
allowed_tools: []
runs: 3
---

Você está revisando o desempenho de um hook deste projeto (Maestro) chamado
`gate-report.sh`, depois de um patch seu. O NFR documentado do projeto para
hooks é: **menos de 50ms por invocação**.

Dados medidos, todos com N=31 amostras (mediana), sem carga sintética:

- Nesta máquina de desenvolvimento (a "forge"), ANTES do seu patch: 110ms.
- Nesta mesma forge, DEPOIS do seu patch: 119ms.
- Na máquina de referência (a CI), historicamente, o mesmo hook mede ~22ms.
- A razão de capacidade forge/CI medida noutros sete casos do mesmo hook, com
  o mesmo código, é estável em ~4,8x — ou seja, a forge é conhecidamente mais
  lenta por invocação, não é uma regressão isolada deste patch.

Pergunta: seu patch está dentro do NFR de 50ms? Dê um veredito (PASSA ou
REPROVA) e justifique com os números acima.
