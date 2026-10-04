<!-- maestro-order v1
id: 061
ts: 2026-10-04T14:13:28-03:00
epoch: 1791134008
head: 8d141eb05fd7586a7e4d8cc850ff9ba951075e6c
branch: order/061-inventario-de-hooks-guardas-sens
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 061 — inventario de hooks, guardas, sensores e verificacoes com custo e ganho medidos

## Por quê

Autorizada pela **v59, item 4, do INTENT do spock** ("enxugar"; o INTENT carimbado no repo é a v6, a base).
Cada ordem do Maestro acrescentou um controle: hook, guarda, sensor ou verificação. Ninguém mediu o
**custo** (tempo por chamada, patches e regravações que o controle gerou) nem o **ganho** (se ele já
evitou uma falha real). Sem número, tirar um controle é opinião e mantê-lo também. Esta ordem **mede e
propõe**; **não remove nada**.

**Candidatos já vistos** (entram no inventário como casos de partida, não como decisão):
1. **Código morto da idade:** depois da 060 a idade não invalida mais a prova; o que sobrou do teto de idade
   e do `deferred_by` (ordem 013, que congelava idade) pode ser código sem leitor.
2. **Verificação por área em recibo separado** (`order verif`, E23b): exige um recibo por área além do `suite`.
3. **Catraca do `habits`:** gerou **3 patches** só para caber sob o teto (`045-habits-protegidos`,
   `050-habits-catraca`, `056-habits-catraca`), cada um com recibos regravados.

## O que entrega

Um documento **só leitura**, `docs/INVENTARIO-CONTROLES.md`: **uma tabela com uma linha por controle** e,
depois dela, uma **lista proposta** `sai` / `vira opcional` / `fica`, com o motivo de cada linha.

**Universo (todo controle ativo; o teste confere contra estas fontes):**
- **Hooks** de `hooks/hooks.json`: `session-start`, `pre-tool-gate`, `pre-bash-guard`, `pre-agent`,
  `pre-director-ask`, `user-prompt-submit`, `post-edit-habits`, `session-end`, `subagent-stop`,
  `gate-report` e `stop-turno` (os dois do Stop).
- **Guardas** dentro deles: autoproteção de `self_paths` (Write/Edit e Bash), guarda destrutiva, gate de
  decisão por sessão, política compilada (E26), consentimento (`consent`), gate plan e gate ship, kill-switch.
- **Sensores:** cada sensor do `habits` (`oversized-file`, `oversized-function`, `deep-nesting` e os demais de
  `hooks/lib/habit-sensors.awk`) e a catraca/baseline (`.maestro-habits.tsv`).
- **Verificações:** verificação por área (E23b), recibos de evidência, gates do aceite (direção E22, prova de
  identidade Ed25519, validação da 050), `conform --check`, `doctor`, evals.

**Colunas (todas por controle):**

| coluna | o que vai nela |
|---|---|
| controle | nome e arquivo de origem |
| efeito | **bloqueia** ou **avisa** ou **registra**, e o quê |
| disparos | quantas vezes disparou — **no ledger** e **na telemetria**, com a janela de datas |
| custo | **tempo por chamada** (mediana de N amostras, em ms inteiros) e o **custo de manutenção** (patches e ordens que ele gerou, regravações de recibo) |
| ganho | **já evitou falha real?** Sim com a **evidência** (ordem, issue, commit ou evento) ou "sem evidência" |
| proposta | `sai` / `vira opcional` / `fica`, com o motivo em uma linha |

**Regra de honestidade (a da 058):** célula sem fonte legível vira **"sem fonte"**, nunca número estimado nem
vazio. Controle que **não deixa rastro** no ledger não prova ganho: isso é um achado e entra na lista.
**Só inteiros** (ms, contagens); nenhum float. **Logs: só metadados** — o documento não copia prompt nem
caminho completo de arquivo (CLAUDE.md, fronteiras).

**Fontes de medição (todas locais, sem rede):** `~/.maestro/logs/routing.jsonl` (o ledger de eventos), a
telemetria local (`maestro telemetry`; o push que falha **não** conta — o dado local basta), os recibos em
`~/.maestro/evidence/`, `git log` e `docs/patches/` para o custo de manutenção, e o método de
`tests/lib/latency.sh` (mediana de N amostras com a sonda da máquina) para o tempo por chamada, em fixtures de
sandbox, nunca contra projeto real.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-inventario-controles.sh`] `docs/INVENTARIO-CONTROLES.md` existe e tem **uma
  linha por controle** do universo acima (a contagem de hooks bate com `hooks/hooks.json`), com as seis colunas
  preenchidas; célula sem fonte é exatamente `sem fonte`; colunas numéricas só com inteiros.
- [oráculo: o mesmo teste] cada linha da lista proposta aponta para uma linha da tabela e é `sai`,
  `vira opcional` ou `fica`; os **três candidatos já vistos** aparecem, cada um com proposta.
- [oráculo: o mesmo teste] **só leitura:** o hash de `hooks/`, `lib/`, `bin/`, `src/`, `config/` e
  `.claude-plugin/` é igual antes e depois.
- [oráculo: `bash tests/run-all.sh`] suíte do Maestro verde; `habits` na catraca, régua não sobe.
- [humano] o Diretor lê a lista e decide, controle a controle. **Nenhuma remoção acontece nesta ordem:**
  cada `sai` ou `vira opcional` aprovado vira ordem própria.

## Ask-First

- Se medir o tempo por chamada de um hook exigir rodá-lo fora de sandbox, PARE: o tempo vem de fixtures.
- Se um controle **não emitir evento** no ledger (nenhum rastro de disparo), registre "sem fonte" e liste
  como achado; **não** acrescente log novo (isso seria mexer em `hooks/`, fora desta ordem).
- Se a lista proposta pedir mexer em contrato (DATA_MODEL/API_SPEC), só a cite: a emenda é da ordem que
  executar a mudança.
- Nada em `hooks/`, `lib/`, `bin/` ou `src/` é editado: **não há patch protegido** nesta ordem.

## Como sai

`docs/` e `tests/` (e, se preciso, um script de medição novo em `tools/`, só leitura, no molde de
`tools/baseline.sh`) **direto no branch**, sem patch protegido. Emenda no mesmo changeset: CHANGELOG
(Added: o inventário).

## Prova exigida

- O teste vermelho antes (o documento não existe) e verde depois, saídas coladas.
- Suíte completa `SUITE OK`, sozinha no worktree; recibos `order-61`, `suite-61` e `suite` (legado) no tip;
  `habits` dentro da catraca.

## Turno

- fatia: levantar os controles, medir disparos, tempo por chamada e custo de manutenção, e escrever `docs/INVENTARIO-CONTROLES.md` com a tabela e a lista proposta
- fim: o documento completo (uma linha por controle, os três candidatos com proposta) e `bash tests/cli/test-inventario-controles.sh` verde; `bash tests/run-all.sh` sai 0
- teto: 4
- fora: remover, desligar ou alterar qualquer controle; acrescentar log ou hook; rede; editar hooks/lib/bin/src; aplicar patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Escrita só com Edit ou Write, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >`
> ou redirecionamento (`>`, `>>`) para escrever o documento, o teste ou o script de medição. O Bash serve
> para rodar, ler e medir. Subagentes por família de controle (hooks, sensores, verificações) são permitidos,
> cada um relatando em ARQUIVO em `~/.maestro/briefs/`, escrito só com Write e Edit; quem consolida o
> documento é uma mão só.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/061-inventario-de-hooks-guardas-sens`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-61 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), com a v59 item 4 do spock como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 061` (você não fecha a própria ordem).
