# Decision log

## 2026-08-08 — Sessão E1 (vibe-code via chat)
- Story: S-101, S-102, S-103
- Implementado: estrutura de plugin (plugin.json, hooks.json, marketplace.json), common.sh (kill-switch, log_event com vocabulário fechado + sanitização + flock -n), 3 hooks como stubs seguros (degradam com exit 0), CLI bash com doctor completo, routing-table.yaml inicial, testes (killswitch, log-vocab) + run-all.
- Decisões: doctor em bash (Bun só entra no E2, checado como warn); sanitização de valores de log por whitelist de caracteres (defesa contra injeção de JSONL, review Opus achado 9); stubs dos hooks E2 já registrados no hooks.json para o wiring ser testado desde já.
- Descartado: implementar decide/status/log adiantado — guarda de escopo do EPICS.
- Flags: nenhum.
