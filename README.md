# Maestro (v0.1 — E1)

Camada de roteamento MoE para Claude Code. Estado atual: **E1 completo**
(estrutura de plugin instalável, kill-switch, doctor, lib de log, testes).
E2 (injeção + gate + CLI decide) é o próximo épico — ver docs/architecture/EPICS.md.

## Instalar (local)
```
git clone <este-repo> ~/dev/maestro
claude  # dentro do Claude Code:
/plugin marketplace add ~/dev/maestro
/plugin install maestro@maestro
```

## Validar
```
~/dev/maestro/bin/maestro doctor
bash ~/dev/maestro/tests/run-all.sh
```

## Kill-switch
`MAESTRO_OFF=1` desativa todos os hooks instantaneamente.
