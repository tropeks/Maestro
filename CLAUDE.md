# Maestro — camada de roteamento MoE para Claude Code

Plugin local: hooks determinísticos + routing table + roster de agentes.
Filosofia: trilhos determinísticos (hooks garantem QUE a decisão acontece),
IA nas bordas (o Claude da sessão decide O QUE fazer, guiado pela tabela).

## Fronteiras (invioláveis)
- hooks/ = bash puro, nunca invoca Bun, nunca importa src/
- Kill-switch MAESTRO_OFF=1 na primeira linha de todo hook
- Logs: só metadados; jamais prompt, jamais caminho completo de arquivo
- agents/ = só markdown; vendor/ = read-only
- Falha de qualquer componente degrada para o fluxo manual — nunca bloqueia trabalho

## Docs canônicos
docs/architecture/ARCHITECTURE.md (ADRs) · DATA_MODEL.md (schemas) ·
API_SPEC.md (contratos hook+CLI) · EPICS.md (escopo — nada fora dele sem emenda)

## Proibido
- float em qualquer métrica de custo (usar inteiros de tokens/centavos)
- dependência de rede em runtime
- editar vendor/ no lugar
