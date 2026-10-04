<!-- maestro-order v1
id: 059
ts: 2026-10-03T21:33:57-03:00
epoch: 1791074037
head: ff78ce3703a471704a6540c0dd9fbd355d9f2b51
branch: order/059-etapa-1-contrato-de-entrada-e-va
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 059 — Etapa 1: contrato de entrada e validador

> Ordem do Capitão, 2026-10-03, **Etapa 1 do plano v2 da fábrica** (`/home/rcosta00/dev/spock/.maestro/INTENT.md`, seção "Direção 2026-10-03 - plano v2 da fábrica", INTENT v58; textos em `docs-ops/fabrica/`). **Proposta de ordem: só enfileira com a aprovação do Capitão.** Base: a ordem 050 (estados de validação). Quem executa não fecha a própria ordem — `maestro order --accept` é do Diretor.

## Por quê
Antes de automatizar qualquer coisa, o que entra precisa estar bem especificado: hoje ordem entra sem critério verificável, sem checar que o arquivo está commitado no branch e sem dependências satisfeitas. Isso é o que gera ordem esquecida, turno que para e prova sem régua.

## Contrato
1. **Critérios de aceite com oráculo.** Toda ordem nova traz a seção `## Critérios de aceite`, uma linha por critério: `- [oráculo: <comando que sai 0 ou 1 | teste: <nome>>] texto` ou `- [humano] texto`. Critério que dependa de julgamento humano é marcado `[humano]`. O esqueleto do `maestro order --create` passa a gerar a seção.
2. **Validador de entrada (máquina), `maestro order --entry-check <id>`**, sai 0 se e só se: (a) o arquivo da ordem está **commitado no branch da ordem**; (b) o **bloco Turno** é válido (reaproveita `_turno_missing`); (c) há ao menos um critério e **cada critério tem oráculo ou é marcado `[humano]`**; (d) as **dependências** declaradas (`depende_de:` no cabeçalho ou na seção) existem e estão **satisfeitas** (aceitas, no estado derivado); (e) a **política do projeto existe** (INTENT válido e `.maestro.yaml`).
3. **Ordem que não passa não entra na fila**: sai com código 1 e uma linha de **motivo por falha**, para o especificador corrigir; nada é enfileirado por este comando (o despacho é a Etapa 2).
4. Compatível: ordens antigas sem a seção **não quebram** `--list`/`--status`; só o `--entry-check` as reprova, com motivo. Flag `MAESTRO_ENTRY_REQUIRE` desligada = comportamento de hoje (como a 041).
5. Arquivos protegidos (`hooks/`, `bin/`, `src/`) não são editados pelo executor: a mudança sai como patch em `docs/patches/` (ou sob o consentimento da ordem 053, quando existir). O que cabe em `lib/` (`lib/core-order-entry.sh`, novo) fica em `lib/`.

## Critérios de aceite (com oráculo)
- [oráculo: `bash tests/cli/test-order-entry-ok.sh`] ordem completa passa (exit 0).
- [oráculo: `bash tests/cli/test-order-entry-falhas.sh`] cada uma das cinco falhas (a a e) reprova com o motivo certo e exit 1.
- [oráculo: `bash tests/cli/test-order-entry-antigas.sh`] ordem antiga sem a seção não quebra `--list`/`--status`.
- [oráculo: `bash tests/run-all.sh`] suíte do Maestro verde.
- [humano] o Diretor confere o esqueleto gerado pelo `--create`.

## Prova
`maestro evidence --record --label order-59 -- bash tests/run-all.sh` no tip do branch.

Depende de: ordem 050 (Maestro) aceita (é a base da Etapa 1); a Etapa 0 (ordem 058) não bloqueia, mas é a linha de base contra a qual a Etapa 1 será comparada.

## Turno

- fatia: o esqueleto de critérios e o `--entry-check` com as cinco checagens, em `lib/core-order-entry.sh`, mais os três testes; o patch de despacho em `bin/` fica pronto, não aplicado
- fim: os quatro critérios com oráculo saem 0; patch pronto em `docs/patches/`; relatório lista o que ficou para o Capitão aplicar
- teto: 4
- fora: despacho automático e a fila (Etapa 2), evidência pelo runner (Etapa 3), aplicar patch em arquivo protegido, e qualquer mudança no ponte-daemon
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/059-etapa-1-contrato-de-entrada-e-va`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-59 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 059` (você não fecha a própria ordem).
