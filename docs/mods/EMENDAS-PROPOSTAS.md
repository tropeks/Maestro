# Emendas propostas — mods como superfície de controle (ordem 072)

**Estado: PROPOSTA, não aplicada.** A ordem 072 cria `mods/` (JS/TS fora de `hooks/`, sem importar `src/`). A regra de `CLAUDE.md` diz
"hooks/ = bash puro, nunca invoca Bun, nunca importa src/": o mod **não a viola** (mora em `mods/`, não em `hooks/`), mas é uma **superfície
nova** que o documento canônico não nomeia. A emenda de `CLAUDE.md` e do ADR é do **Diretor**: este arquivo traz o texto pronto para ele
aplicar, ou recusar, num changeset à parte.

## Emenda 1 — `CLAUDE.md`, seção "Fronteiras (invioláveis)"

Trocar a linha

```
- hooks/ = bash puro, nunca invoca Bun, nunca importa src/
```

por

```
- hooks/ = bash puro, nunca invoca Bun, nunca importa src/
- mods/ = plugins de mod do Claude Code (TypeScript), cada um com `hooks/hooks.json`. Nunca importam src/, nunca abrem rede
  (sem http.fetch, process.*, mcp.call, model.complete), só escrevem o log de metadados. Mod de bloqueio falha FECHADO
  (deny) e nunca emite `allow`; o kill-switch MAESTRO_OFF=1 vale e é lido uma vez no load, com log.
```

Acrescentar a `mods/` à lista de caminhos protegidos (`self_paths`) — isso é o **patch protegido do turno 3**, que a emenda apenas cita.

## Emenda 2 — `docs/architecture/ARCHITECTURE.md`, novo ADR

```
### ADR-012 — Controles como mods do Claude Code, com a decisão fora do hook (ordem 072)

**Contexto.** Os controles de bloqueio (guarda de destrutivos, autoproteção de self_paths, segredo) são hooks bash que leem texto de
comando com regex. A auditoria de 05/10 mediu 63–78% de falso positivo nesse léxico. Os mods do Claude Code (>= 2.1.287) expõem
`tool.check` e `tool.call` tipados, com a cadeia de tiers (`prepend`, org, user) em que um mod de organização vence o do usuário.

**Decisão.** A política de bloqueio mora num plugin de mod (`mods/maestro-guard`), instalado como plugin da organização (diretório
de root + settings gerenciados). A decisão é uma FUNÇÃO PURA (`hooks/policy.ts`), testada contra um corpus (>= 150 comandos) com
contagens de falso positivo/negativo; a fiação (`hooks/register.ts`) só traduz o veredito. O mod:
  1. nega a classe estrutural clara, pergunta (`ask`) no ambíguo e nunca emite `allow`;
  2. em sessão interativa o destrutivo vira `ask`; em headless segue `deny`; autoproteção, segredo e queda segura são `deny` sempre;
  3. cai para `deny` em `throw`/`timeout`/evento malformado (falha fechada), ao contrário dos hooks bash, que degradam para o fluxo manual;
  4. registra só metadados (`rule`, `tool`, `verdict`), sem rede.

**Consequências.** (+) menos falso positivo e um corpus que mede a regressão; (+) a guarda deixa de ser o arquivo que o agente edita.
(−) a API dos mods pode mudar entre versões do Claude Code (a ordem de vigia cuida); (−) sem usuário sem sudo na fábrica o mod é
tripwire, não fronteira; (−) duas superfícies (bash e mod) coexistem até o patch de remoção do `pre-bash-guard`, depois da janela da Fase 1
(2026-10-13T18:07:28-03:00).

**Relação com a regra de falha.** "Falha de componente degrada para o fluxo manual" vale para os hooks bash. Para o mod de bloqueio vale
o inverso, por escolha: recusar é o fluxo manual (o humano responde ao `ask`/`deny` e decide).
```

## Emenda 3 — `CLAUDE.md`, seção "Fronteiras", linha de falha

A linha "Falha de qualquer componente degrada para o fluxo manual — nunca bloqueia trabalho" precisa de uma exceção escrita para o mod, ou
o Diretor decide que o mod também degrada (fail-open). A ordem 072 escolheu a falha fechada; o texto sugerido:

```
- Falha de qualquer componente degrada para o fluxo manual — nunca bloqueia trabalho. Exceção declarada: o mod de bloqueio
  (mods/maestro-guard) falha FECHADO (deny), porque um guarda que libera na queda não guarda.
```

## O que o Diretor decide

| # | Decisão | Padrão da ordem 072 |
| --- | --- | --- |
| 1 | aplicar a Emenda 1 (superfície `mods/` nomeada) | a ordem não a aplica |
| 2 | aplicar a Emenda 2 (ADR-012) | idem |
| 3 | exceção da falha fechada (Emenda 3) ou mod fail-open | falha fechada |
