<!-- maestro-order v1
id: 002
ts: 2026-09-10T17:37:45-03:00
epoch: 1789072665
head: f63b86903e5da19c543b90c2171b8477d34cbc87
branch: fix/002-fuga-isolada-e-metodo-de-latencia
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
-->
# Ordem 002 — as três pontas que a 001 deixou: fuga isolada, overhead do session-start e o método do teste de latência

## Por que esta ordem existe

Mesma autorização da 001: INTENT v2, Prioridade 4 — "prova mecânica antes de
declaração" (ADR-010; EPICS E23). A 001 provou que o teste podia estar cego sem
que ninguém visse, porque a CI verde era prova de ambiente virgem, não de código
correto. As três pontas abaixo são o resto dessa mesma lição.

Estado herdado: PR #4 aberto com a correção do harness; recibo local da 001
vencido (exit 1) por conta da latência, a re-rodar quando a forge esvaziar.

## Ponta 1 — `test-gate.sh`: a fuga que o `MAESTRO_HOME` mascara

Medido, não suposto: `bash tests/hooks/test-gate.sh` sozinho, em sessão real, dá
**40 FAIL**; com `env -u MAESTRO_GATE_POLICY`, **1**. Dentro do `run-all.sh` ele
**passa**, porque o runner exporta `MAESTRO_HOME` para um tmpdir e isso mascara a
fuga.

É a mesma classe do bug da 001, e o mascaramento é o que a torna pior: quem roda
um arquivo isolado para depurar vê 40 falhas que não existem, e quem roda a suíte
vê verde que não prova o caso default. `test-consent.sh` (1 FAIL) e
`tests/cli/test-order.sh` (3 FAIL) caem no mesmo padrão e entram nesta ponta.

Pergunta a responder antes de corrigir: a limpeza pertence a cada helper (como na
001) ou ao `run-all.sh` e a um helper comum de teste? A 001 resolveu dois arquivos
por dentro; se a resposta for "helper comum", a correção da 001 vira caso
particular de uma solução mais geral, e isso é decisão de contrato de teste.

## Ponta 2 — overhead do `session-start`: 413ms → 577ms

`test-session-start.sh` acusa `FAIL NFR: overhead` em todos os ambientes medidos
na forge — 368ms, 397ms, 413ms, 436ms, 577ms. Não liga/desliga com
`MAESTRO_GATE_POLICY`: é independente da fuga da 001.

CORREÇÃO do que esta ordem dizia antes: o teto NÃO é 300ms. O critério em
`tests/hooks/test-session-start.sh:503-505` já tem TRÊS faixas — `<100ms` é ok e
é o NFR de verdade; `100–300ms` é `warn` com a hipótese de carga escrita no
próprio código ("máquina carregada?"); só `>300ms` reprova. Ou seja: o teste já
antecipava contenção, e a forge estoura até a faixa de tolerância. Na CI (runner
ocioso) o número é **41ms**, com 2,4x de folga contra o NFR de 100ms.

O que ainda não se sabe, e é o trabalho: quanto disso é a máquina compartilhada e
quanto é custo real do hook. O NFR do ARCHITECTURE é <50ms por invocação de hook;
o teto de 300ms deste teste é outro número, de outra natureza, e a primeira coisa
a apurar é de onde ele veio e o que ele protege.

## Ponta 3 — método do teste de latência: mediana de N, não mínimo de 1

Veredito da 001, aceito pelo diretor: **inconclusivo sob carga**, não regressão.

Evidência que o sustenta: 5 medições em série de `test-guarda-destrutiva`, com
load de 1.91 a 4.08 em 8 CPUs — `perigo(bloqueia)` min 59·64·59·60·71ms contra
teto de 50ms, mediana ~100–108ms; e `rotina(passa)` oscilando de min 23ms para
37ms no MESMO código, com o caso de 16KB estourando o próprio teto em 1 de 5
(87ms) e passando nos outros 4.

O teste já mede min, mediana e max, e já tem guarda de regressão na mediana a 2x
o orçamento. O que está errado é o critério de aprovação: o **mínimo de uma
execução** foi escolhido como estimador do custo de código numa máquina
compartilhada, e a evidência mostra que ele se move com a carga — logo deixou de
estimar o que se propunha. Direção do diretor: **mediana de N com teto de folga
declarada**, não mínimo de 1.

Isto vale para os dois testes que usam o protocolo (`test-guarda-destrutiva.sh` e
`test-gate.sh`, que o comentário do próprio código diz compartilharem o método).

Insumo que chega de fora: o PR #4 roda em runner quieto. Se
`test-guarda-destrutiva` passar lá, está provado que o teto de 50ms é calibração
contra contenção, não código mais lento — e a ponta 3 muda de "investigar" para
"trocar o critério". Espere esse sinal antes de escolher o número.

## Contrato de execução
- Trabalhe APENAS no branch `fix/002-fuga-isolada-e-metodo-de-latencia`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-2 -- bash tests/run-all.sh` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`), Prioridade 4.
- Prova antes de declaração: nenhuma correção antes da causa provada por experimento que podia refutá-la.
- Medição de latência é inválida sem o load average ao lado. Sob carga, o veredito é "inconclusivo", nunca "regressão".
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 002` (você não fecha a própria ordem).
