<!-- maestro-order v1
id: 001
ts: 2026-09-10T13:24:44-03:00
epoch: 1789057484
head: 7dec469021cb13080118c5d1a1e87e924d96b60c
branch: fix/e26-politica-do-gate-e-nfr-latencia
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_pr: 4
absorbed_note: mesclada e branch apagado antes do aceite; prova no conteudo do main
-->
# Ordem 001 — as 3 falhas que a CI verde escondia: política do gate (E26/S-2601) e NFR de latência

## Por que esta ordem existe

A direção autoriza esta ordem pela Prioridade 4 do INTENT v2 — "prova mecânica
antes de declaração" (ADR-010; EPICS E23). Hoje a CI está verde e a suíte local
falha no MESMO commit. Enquanto as duas discordarem, o verde da CI não é prova
de nada: é o ambiente virgem do runner passando por cima de um comportamento que
só aparece em sessão real. Explicar essa divergência é o primeiro achado, e ele
decide se o resto é bug de produto ou teste desatualizado.

Achado colhido antes da ordem: as falhas NÃO vêm do changeset do INTENT v2.
Rodei os três testes num worktree limpo do `main` em 6119bec, sem aquele branch
e sem o `.maestro/INTENT.md` — falham idênticas. São pré-existentes.

## As três frentes

### (a) política do gate — `test-session-start` e `test-gate-policy-escopo`

Oito asserções caídas, todas em torno de compilar e gravar a política do gate:

- `FAIL gate-policy.sh gerado`
- `FAIL política recompilada acompanha outro YAML (mode block)`
- `FAIL YAML corrompido: denylist de autoproteção embutida assume`
- `FAIL sem jq: gate-policy.sh ainda compilado`
- `FAIL grava no caminho de sempre`
- `FAIL com o conteúdo de sempre`
- `FAIL arquivo padrão sumiu`

Suspeita a REFUTAR ou confirmar: `a978175` (E26/S-2601, "a política do gate era
global, e dois gerentes se corrompiam calados") escopou a política por sessão. Se
a compilação passou a escrever num caminho escopado sempre que há sessão no
ambiente, o "caminho de sempre" deixa de ser escrito para quem roda em sessão
real — e passa na CI, que não tem sessão. Se confirmado, a pergunta que decide
tudo é: o teste ficou para trás do E26, ou o E26 degradou o gate para quem roda
em sessão?

A pergunta mais cara desta ordem: **o gate está protegendo de verdade nesta
máquina, agora?** Ela se responde antes de qualquer correção.

### (b) NFR de latência — `test-guarda-destrutiva`

`FAIL latência estourada (min 58ms >= 50ms)` em dois casos. O NFR de <50ms por
invocação de hook é de ARCHITECTURE "NFRs" e vale. Mas 58ms é 16% acima do teto,
o que cabe em carga de máquina. Medir 5 vezes antes de decidir: se o mínimo
oscilar em torno do teto, é ruído e o teste precisa de método (mediana de N, ou
um teto com folga declarada); se ficar cravado acima, é regressão de latência e
o alvo é outro.

### (c) o overhead do session-start

`FAIL NFR: overhead 577ms` (413ms na baseline limpa). Anotado, não priorizado
aqui — mas a diferença entre 413ms e 577ms é grande demais para ignorar de vez.

## Contrato de execução
- Trabalhe APENAS no branch `fix/e26-politica-do-gate-e-nfr-latencia`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-1 -- bash tests/run-all.sh` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`), Prioridade 4 — "prova mecânica antes de declaração".
- Nenhuma correção antes da causa-raiz provada por experimento que podia tê-la refutado.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 001` (você não fecha a própria ordem).
