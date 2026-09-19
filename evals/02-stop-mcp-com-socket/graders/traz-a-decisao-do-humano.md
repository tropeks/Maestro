---
type: llm
focus: last_message
weight: 1
---
A resposta final deve trazer ao usuário o que o humano decidiu sobre o plano
(aprovação ou não), obtida por uma pergunta feita através da ferramenta MCP
da Ponte (director.ask/director.wait), não por ter simplesmente escrito a
linha de espera `[spock] aguardando:` e parado sem resposta.

Falha se a resposta apenas repete a pergunta e para (sem trazer nenhuma
decisão do humano), ou se afirma ter esperado por digitação em vez de usar a
ferramenta.
