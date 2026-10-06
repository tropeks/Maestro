# Fase 1 — painel de medição dos 7 dias (sombra)

Auditoria de 05/10, seção 7, Fase 1, item 4. Rodar: `bash tools/fase1-painel.sh` (somente leitura, só inteiros; exit 3 se uma fonte
esperada sumir). Rollback: `docs/fase1/ROLLBACK.md`.

## Data de início

**Previsto: 2026-10-07T00:00:00-03:00** (arquivo `docs/fase1/INICIO`, a 1ª linha). **Troque pela data real em que o Capitão aplicar o patch
`901-fase1-gate-warn-guard-sombra.patch` e o bloco `sandbox`.** A janela são **7 dias** a partir dela; o baseline são os **14 dias antes**.
Sem sombra ligada, o painel mostra `AGUARDANDO INÍCIO` e a janela fica vazia.

## Os critérios do item 4 e de onde vêm

| # | Critério | Fonte | Regra |
|---|---|---|---|
| 1 | **Prompts e negações nativos** | Ponte, `decision` com `kind='permission'` e `decision_resolution.choice` (`allow`/`deny`), banco aberto em `mode=ro` | **Medida, sem limiar.** Compara prompts/dia e negações da janela com o baseline; quem decide é o Capitão |
| 2 | **Incidentes destrutivos** | `docs/fase1/INCIDENTES.md` (preenchido à mão: uma linha `- AAAA-MM-DD …` por incidente); indício extra: entradas `reset:` no reflog de todos os worktrees | **PASS só com 0 relatados.** O reflog e a "exposição" (comandos que o guard teria barrado, `gate_warn` destrutivo) são indício, não critério |
| 3 | **Decisões espontâneas ≥ 50%** | ledger `~/.maestro/logs/routing.jsonl` | **PASS** se a fração, na janela, for ≥ 50 (inteiro) |
| 4 | **Fração subagent/multi sem queda > 5 p.p.** | o mesmo ledger (`decision.mode`) | **PASS** se a fração da janela for ≥ (baseline − 5) |

**Mínimo de 10 sessões** na janela para o 3 e o 4 valerem; abaixo disso o painel diz `INSUFICIENTE`, não `PASS`.

## Definições (as que o painel usa, escritas para não mudarem no meio)

- **Sessão com código:** sessão do ledger que teve uma `decision` **ou** um bloqueio/aviso de gate de Edit/Write/MultiEdit **sem** `cmd` (ou seja, sem decisão).
- **Espontânea:** a sessão com código cuja **primeira `decision` veio antes** do primeiro gate sem decisão (ou que nunca teve gate sem decisão).
- **subagent/multi:** entre as sessões com `decision`, as que registraram `mode` `subagent` ou `multi` (a primeira decisão da sessão).
- Percentuais são **inteiros arredondados para baixo**.

## Aviso sobre o baseline "~58%"

A auditoria cita decisões espontâneas "~58% hoje". **Com esta definição, e sobre o ledger real, o baseline sai bem mais alto** (88% nos 14 dias anteriores
a 04/10; 78% nos 14 dias anteriores a 06/10). Não consegui reproduzir os 58% a partir do ledger: a definição da auditoria não está escrita lá. O painel usa a
definição acima **igual nos dois lados** (baseline e janela), então o critério "≥ 50%" e a comparação de `subagent/multi` são consistentes entre si, mas **o
50% absoluto é um piso mais folgado do que a auditoria imaginava**. Se o Capitão quiser o piso ligado ao baseline (ex.: "não cair mais que 10 p.p."), é uma
linha em `tools/fase1-painel.sh`.

## O que o painel não mede

- **Prompt que atrapalha um fluxo legítimo:** só aparece como `deny`/`prompts` na Ponte, sem saber se o fluxo era legítimo.
- **Incidente não relatado:** o critério 2 depende de o Capitão registrar. O reflog e a exposição ajudam a achar o que ele não viu.
- **Rede e `autoAllowBashIfSandboxed`:** o que o sandbox permite de rede não foi testado (ver `TESTE-SANDBOX.md`).

## Fim dos 7 dias

Rodar o painel e **decidir**: (a) os 4 critérios em PASS → a Fase 2 pode começar; (b) qualquer FAIL ou INSUFICIENTE com sessões suficientes → rollback ou prorrogar
a sombra, decisão do Capitão. O painel não decide.
