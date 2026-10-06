# Fase 1 — rollback (escrito antes de começar)

Vale a qualquer momento da sombra de 7 dias e depois dela. Cada passo é reversível e independente.

## Quando reverter

Reverta **na hora**, sem esperar os 7 dias, se acontecer **qualquer um**:
1. **um incidente destrutivo** (arquivo, commit ou branch perdido por comando que o guard antigo teria barrado) — registre em `docs/fase1/INCIDENTES.md`;
2. o painel mostrar `decisões espontâneas < 50%` **ou** queda de `subagent/multi` **maior que 5 p.p.** com mínimo de 10 sessões na janela;
3. um fluxo legítimo travar por causa do sandbox (`Read-only file system` em operação que o Capitão precisa fazer pelo Claude).

## Passos

1. **Gate e guard (patch `901-…`, no `main`):** voltar `gate.mode: block` em `config/routing-table.yaml` (linha 3). O `pre-bash-guard` volta a bloquear
   sozinho: ele só registra enquanto a política da sessão diz `warn`. Faça por patch inverso: `git apply -R docs/patches/901-fase1-gate-warn-guard-sombra.patch`,
   ou por um patch humano que troque só a linha. Vale para as **sessões novas** (a política é compilada no `session-start`); sessão em curso mantém a que tem.
2. **Sandbox (`settings.json` do Capitão):** remover o bloco `sandbox` inteiro e a regra `Bash(git push -f*)`. As três regras `ask` podem ficar (só pedem permissão).
3. **Conferir:** `maestro doctor` sem aviso novo; uma sessão nova mostra `gate.mode: block` no bloco injetado; `git push -fu origin x` num repo descartável é negado pelo guard.
4. **Registrar:** a data e o motivo no fim de `docs/fase1/INCIDENTES.md`, e fechar o painel com `--inicio` e o fim reais.

## O que não precisa reverter

O `permissions.deny` da Fase 0 (25 regras), o patch `900-fase0-…` (kill-switch na linha 2) e a telemetria desligada: são independentes da sombra.

## Tempo esperado

Os passos 1 e 2 levam minutos. Não há migração de dados: o ledger só ganhou eventos `gate_warn`, que o rollback não apaga.
