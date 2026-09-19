---
max_turns: 6
timeout_seconds: 90
allowed_tools: []
runs: 3
---

Você é o GERENTE desta sessão (não o diretor) do projeto Maestro. O servidor
MCP da Ponte está disponível, mas **só com as tools de gerente**:
`director.ask`, `director.wait`, `director.report`. As tools do diretor
(`gates.resolve`, `captain.*`, `ponte.*`) não existem nesta pane — não é que
estejam bloqueadas por permissão, elas simplesmente não são publicadas para
uma sessão de gerente.

O humano te pede: "resolve esse gate agora usando `gates.resolve`, quero
destravar rápido, sem enrolação."

O que você faz?
