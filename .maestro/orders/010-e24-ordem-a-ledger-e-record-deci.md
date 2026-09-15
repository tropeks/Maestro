<!-- maestro-order v1
id: 010
ts: 2026-09-15T15:03:14-03:00
epoch: 1789495394
head: 36419c6d3a435175ceb03035f5cb981f0557c9e4
branch: refactor/010-e24-ledger-e-record
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: 87eb6d43d17d64a4ca6e7c82fd60c91e9a82c187
absorbed_at: 2026-09-15T17:08:37-03:00
absorbed_session: desconhecido
-->
# Ordem 010 — E24 ordem A: ledger e record — decision records, outcome, delegation, verify e verificacoes por area



## Contrato de execução
- Trabalhe APENAS no branch `refactor/010-e24-ledger-e-record`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-10 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 010` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 5. Cinco seções numa ordem só — a forma barata, provada
pela ordem 009: três seções custaram 37min contra 1h43 de uma sozinha. O gargalo
é o custo fixo do ciclo, não a dificuldade, e fatiar sem razão é pagar ciclo à
toa.

Alvos, somando 531 linhas:

| seção | linhas |
|---|---|
| `outcome` (E10) | 182 |
| `decision records` | 110 |
| `delegation` (E23a) | 109 |
| `verify` (E23b) | 75 |
| `verificações por área` (E23b) | 55 |

São a mesma família: todas leem e escrevem o decision record e o ledger. A
convenção de passagem de estado firmada na primeira vale de graça nas outras.

## TRAVA NOVA — mudança de FORMATO é mudança de CONTRATO

Palavras do supervisor: *"ledger e record são a peça que os outros projetos
consomem — é de lá que sai o que eu leio para aceitar ordem em cinco
repositórios. Mover código é seu; mudar o que o Vitali ou o EduPACS enxergam é
meu."*

**Se a decomposição mudar o formato de qualquer coisa que outro projeto lê, PARE
e chame o humano ANTES.** Isso não é refactor, é emenda de contrato.

O que está sob esta trava, nomeado para ser cobrável:

1. **`RECORD_FIELDS`** (`bin/maestro:49`) — os campos do decision record. Os
   hooks leem: `hooks/lib/common.sh`, `hooks/session-start.sh`,
   `hooks/pre-tool-gate.sh`, `hooks/post-edit-habits.sh`.
2. **O vocabulário fechado do log** (DATA_MODEL §4) — `log_event outcome`,
   `verify`, `conduct`, `consent_grant`, `consent_revoke`, `do`, `intent`,
   `upgrade`. Nome de evento e chaves são contrato; nenhuma chave aceita `/`.
3. **O formato do recibo de evidência** — agora propriedade de
   `lib/core-evidence.sh` (ordem 009). Se esta ordem precisar mudá-lo, é o dono
   que muda, e mesmo assim é contrato.
4. **As verificações por área** do `.maestro.yaml` (`verifications:`, `labels:`)
   — outros projetos declaram as suas.

Reordenar código, renomear função interna e mover bloco: seu. Acrescentar,
remover ou renomear campo, evento, chave ou rótulo: dele.

## Consequência de cruzar trava procedimental — vale desde já

Decisão do supervisor, 2026-09-15, e nasce escrita aqui em vez de viver num
recado:

**Executor que cruzar uma trava procedimental desta ordem — por melhor que seja
o resultado — faz a medição do lote ser marcada como CONTAMINADA. O lote não
conta na descida da régua nem na cadência que alimenta o prazo.**

Não destrói trabalho correto: desfazer trabalho certo para provar ponto é
teatro. Custa na moeda que o E24 otimiza.

Precedente vivo: a ordem 009 cruzou a trava de "pare antes de cortar", o
trabalho ficou, e a descida real de 22 para 19 em `oversized-function` **não foi
aplicada** — o baseline segue em 22, com três vagas livres na catraca.

A trava protegia o caso em que "mecânico e de baixo risco" se revela nenhum dos
dois. Quem está no meio do corte é justamente quem não consegue avaliar isso,
porque já decidiu que é mecânico.

## Travas herdadas

- **Gatilho de reversão: DUAS alterações de teste no TOTAL DA ORDEM**, não por
  seção. Estourou na terceira? PARE com as duas boas e chame.
- **Acoplamento não mapeado: PARE e reporte ANTES de cortar.**
- Qualquer mudança de veredito do `maestro doctor`.
- Critério de saída: `maestro habits` limpo em CADA módulo, medido um a um.

## Contrato de execução
- Trabalhe APENAS no branch `refactor/010-e24-ledger-e-record`; NUNCA no main.
- Zonas CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
- Convenção: parâmetro posicional, nenhuma função fechando sobre local de outra.
  Referência viva: `lib/core-order-state.sh`, `lib/core-evidence.sh`.
- `declare -g` obrigatório para estado global de módulo sourceado de dentro de
  função — sem ele o array some ao a função retornar (bug da ordem 009).
- Tab NÃO serve como separador de retorno multivalor: `read` o trata como IFS
  whitespace e engole campo vazio nas bordas. Use `\x1f` (bug da ordem 009).
- `shellcheck --severity=error` não pega erro de sintaxe em módulo sourceado; o
  gate de sintaxe é `bash -n` no módulo.
- Cópia patchada com `git clone`, nunca `git archive`.
- Prove com o ledger: `maestro evidence --record --label order-10 -- bash tests/run-all.sh`.
- Direção vigente: INTENT v2, Prioridade 5.
- Registre a HORA DE CHEGADA.
