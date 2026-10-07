# Fase 1 — painel de medição dos 7 dias (sombra)

Auditoria de 05/10, seção 7, Fase 1, item 4. Rodar: `bash tools/fase1-painel.sh` (somente leitura, só inteiros; exit 3 se uma fonte
esperada sumir). Rollback: `docs/fase1/ROLLBACK.md`.

## Data de início

**Início: 2026-10-06T18:07:28-03:00** (arquivo `docs/fase1/INICIO`, a 1ª linha). É o instante em que o **cache do plugin carregou a 1.23.0**
(informado pelo Capitão): os hooks rodam do cache, então a sombra do patch `901-fase1-gate-warn-guard-sombra.patch` (`gate.mode: warn`, guard só registrando)
só vale a partir dele, **não** a partir do merge. Panes de longa duração que não foram reiniciadas seguem com o gate antigo, e isso contamina a janela.
A janela são **7 dias** a partir do início (fim em 2026-10-13T18:07:28-03:00); o baseline são os **14 dias antes**. O bloco `sandbox` **não** foi aplicado
(ver `TESTE-SANDBOX.md`): a sombra desta janela é só a do gate e do guard.

## Os critérios do item 4 e de onde vêm

| # | Critério | Fonte | Regra |
|---|---|---|---|
| 1 | **Prompts e negações nativos** | Ponte, `decision` com `kind='permission'` e `decision_resolution.choice` (`allow`/`deny`), banco aberto em `mode=ro` | **Medida, sem limiar.** Compara prompts/dia e negações da janela com o baseline; quem decide é o Capitão |
| 2 | **Incidentes destrutivos** | `docs/fase1/INCIDENTES.md` (preenchido à mão: uma linha `- AAAA-MM-DD …` por incidente); indício extra: entradas `reset:` no reflog de todos os worktrees | **PASS só com 0 relatados.** O reflog e a "exposição" (comandos que o guard teria barrado, `gate_warn` destrutivo) são indício, não critério |
| 3 | **Decisões espontâneas ≥ baseline medido** | ledger `~/.maestro/logs/routing.jsonl` | **PASS** se a fração da janela for ≥ a fração dos 14 dias antes do início, **medida pelo próprio painel** (decisão do Capitão de 06/10: o piso não é 50 nem 58 fixos; na fotografia de 06/10 o baseline é **78%**) |
| 4 | **Fração subagent/multi sem queda > 5 p.p.** | o mesmo ledger (`decision.mode`) | **PASS** se a fração da janela for ≥ (baseline − 5) |

**Mínimo de 10 sessões** na janela para o 3 e o 4 valerem; abaixo disso o painel diz `INSUFICIENTE`, não `PASS`.

## Definições (as que o painel usa, escritas para não mudarem no meio)

- **Sessão com código:** sessão do ledger que teve uma `decision` **ou** um bloqueio/aviso de gate de Edit/Write/MultiEdit **sem** `cmd` (ou seja, sem decisão).
- **Espontânea:** a sessão com código cuja **primeira `decision` veio antes** do primeiro gate sem decisão (ou que nunca teve gate sem decisão).
- **subagent/multi:** entre as sessões com `decision`, as que registraram `mode` `subagent` ou `multi` (a primeira decisão da sessão).
- Percentuais são **inteiros arredondados para baixo**.

## O piso das decisões espontâneas é o baseline medido (decisão do Capitão, 06/10)

A auditoria citava "~58%" e um piso de 50%. **Sobre o ledger real, com a definição acima, o baseline sai mais alto** (88% nos 14 dias anteriores a 04/10;
**78% nos 14 dias anteriores a 06/10**); a definição da auditoria não está escrita lá e não consegui reproduzir os 58%. O Capitão decidiu **amarrar o piso ao
baseline medido pelo painel** (78% na fotografia de 06/10), e é o que o painel faz: o critério 3 compara a janela com **os 14 dias antes do `INICIO`**, medidos com
a mesma definição. Sem tolerância (a janela precisa ser ≥ ao baseline); se o ruído de 7 dias pedir folga, é uma linha em `tools/fase1-painel.sh`.

## O que o painel não mede

- **Prompt que atrapalha um fluxo legítimo:** só aparece como `deny`/`prompts` na Ponte, sem saber se o fluxo era legítimo.
- **Incidente não relatado:** o critério 2 depende de o Capitão registrar. O reflog e a exposição ajudam a achar o que ele não viu.
- **Rede e `autoAllowBashIfSandboxed`:** o que o sandbox permite de rede não foi testado (ver `TESTE-SANDBOX.md`).

## Fim dos 7 dias

Rodar o painel e **decidir**: (a) os 4 critérios em PASS → a Fase 2 pode começar; (b) qualquer FAIL ou INSUFICIENTE com sessões suficientes → rollback ou prorrogar
a sombra, decisão do Capitão. O painel não decide.
