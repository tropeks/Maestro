# Instrumento (B) — julgamento cego de roteamento (S-402)

Gerado por `tests/eval/run-eval.sh --judge-prompt` em 2026-08-09T13:37:34-03:00.
Tabela: sha256 afdc5fa05529

---

Você é o Claude de uma sessão do Claude Code com o plugin Maestro instalado.
O bloco abaixo é o que o hook SessionStart injetou no seu contexto:

```
<maestro-routing>
Maestro v0.1 — roteamento MoE. Kill-switch: MAESTRO_OFF=1.
session_id: desconhecido (não veio no stdin do hook — confirme o id real antes de registrar)

INSTRUÇÃO CANÔNICA — antes de editar código nesta sessão, registre a decisão:
  maestro decide --session desconhecido --workflow <fix|feature|refactor|ship|audit|custom> --mode <direct|subagent|multi> [--agents a,b] [--reason "por quê"]
Sem decision record válido, o gate registra aviso em toda edição (gate.mode: warn).

## Gates humanos — PARE, pergunte e espere resposta explícita.
- gate plan (feature, refactor): entre em plan mode, plano em ≤10 linhas, pergunte "Aprovo o plano? (aprovo | ajusta: …)" — nenhuma edição de código antes do aprovo.
- gate ship (ship): liste em ≤5 linhas o que vai sair e pergunte "Shipo agora? (shipa | espera)" — sem resposta, não shipa.

## Bindings (step → o que roda; "a + b" = método + quem executa). Siga o binding.
- investigate → skill:systematic-debugging
- plan → native:plan-mode
- implement → agent:dev-pleno
- review → skill:requesting-code-review + agent:revisor
- qa → skill:gstack-qa + agent:qa
- ship → skill:gstack-ship
- audit → skill:gstack-cso

## Rotas (intenção → workflow) e workflows
- intent: "correção de bug, erro, quebrou, não funciona", workflow: fix
- intent: "nova funcionalidade, feature, adicionar, criar tela", workflow: feature
- intent: "melhorar estrutura, dívida técnica, limpar", workflow: refactor
- fix: steps: [investigate, implement, review], gate: none
- feature: steps: [plan, implement, review, qa], gate: plan
- refactor: steps: [plan, implement, review], gate: plan
- ship: steps: [ship], gate: ship
- audit: steps: [audit], gate: none
- custom: steps: [], gate: none

## Heurísticas de execução
- edição ≤2 arquivos sem plano → mode: direct
- feature nova ou >3 arquivos → mode: subagent(s) com plano
- tarefa mecânica/repetitiva → dev-junior (haiku)
- decisão de arquitetura ou review → engenheiro/revisor
- linguagem detectada → especialista correspondente

## Roster — nome (modelo). A descrição de cada agente já está no contexto.
- dev-junior (haiku)
- dev-pleno (sonnet)
- engenheiro (sonnet)
- golang-pro (sonnet)
- postgres-pro (sonnet)
- python-pro (sonnet)
- qa (sonnet)
- revisor (sonnet)
- typescript-pro (sonnet)
</maestro-routing>
```

Além dele, você tem no contexto as descrições dos agentes do roster (carregadas always-on pelo harness — reproduzidas aqui porque este é um ambiente offline):

- **dev-junior**: Tarefa mecânica de escopo fechado e critério objetivo: renomear, aplicar padrão repetitivo, corrigir lint, ajustar imports; sem julgamento de design (esse é do dev-pleno).
- **dev-pleno**: Implementação de feature ou bugfix que exige julgamento, quando nenhum especialista de linguagem cobre a stack ou a mudança cruza várias linguagens.
- **engenheiro**: Decisão de arquitetura, escolha entre alternativas técnicas e plano de refactor amplo antes de implementar; entrega plano e trade-offs, não o código final.
- **golang-pro**: Especialista em Go — implementar, revisar ou depurar código .go (concorrência, erros, testes table-driven, perf); quando a tarefa é em Go, prefira este a dev-junior/dev-pleno/engenheiro.
- **postgres-pro**: Especialista em PostgreSQL — schema, migration, índice, transação e tuning de query com EXPLAIN ANALYZE; quando a tarefa é de banco Postgres/SQL, prefira este a dev-junior/dev-pleno/engenheiro.
- **python-pro**: Especialista em Python — implementar, revisar ou depurar código .py (tipagem, async, pytest, FastAPI/Pydantic, uv/ruff); quando a tarefa é em Python, prefira este a dev-junior/dev-pleno/engenheiro.
- **qa**: Teste funcional do que já está implementado: rodar suíte, reproduzir bug, validar fluxo ponta a ponta e relatar evidência; não implementa a correção.
- **revisor**: Review de código já escrito procurando bug, risco e violação de contrato; read-only, relata achados priorizados sem corrigir nada.
- **typescript-pro**: Especialista em TypeScript/React — implementar, revisar ou depurar .ts/.tsx (tipos, strict mode, hooks, estado); quando a tarefa é em TS/JS, prefira este a dev-junior/dev-pleno/engenheiro.

## Tarefa

Para CADA enunciado abaixo (pt-BR, escritos pelo usuário no telefone), decida o
roteamento como decidiria numa sessão real: workflow, mode e agente(s) do roster.
Não peça esclarecimento e não pesquise o repositório — decida com o que está aqui,
que é o que você teria no primeiro turno de uma sessão real.

Responda SOMENTE com TSV, uma linha por caso, sem cabeçalho e sem comentário:

```
<id>	<workflow>	<mode>	<agentes separados por vírgula, ou - se nenhum>
```

workflow ∈ {fix, feature, refactor, ship, audit, custom} · mode ∈ {direct, subagent, multi}

A coluna `agentes` é o campo `--agents` do decision record: **quem executa o
trabalho principal** (investigação/implementação). NÃO liste os agentes que já
vêm de graça dos steps do workflow (o `revisor` do step `review`, o `qa` do step
`qa`) — eles são implícitos no workflow escolhido. Exemplo do DATA_MODEL: workflow
`fix` (steps investigate/implement/review) com agents `["golang-pro"]`, só.
Use `-` quando o trabalho não for de nenhum agente do roster
(ex.: o passo é uma skill pesada como `gstack-ship`/`gstack-cso`, ou fica no contexto principal).

## Enunciados

```
go-nil-worker	o worker do netforge ta estourando nil pointer no parse, arruma
ts-login-quebrado	o login do agenda studio quebrou depois do deploy de ontem
py-export-csv	preciso de export csv no smartquotation, o backend e a telinha
go-endpoint-health	cria um endpoint de health no netforge com as metricas
py-refactor-auth	o vitali ta uma bagunca, todo service repete o mesmo codigo de auth, limpa isso
audit-legatus	da uma olhada de seguranca no legatus antes de eu expor na vps
ship-smartquotation	manda o smartquotation pra producao
pg-query-lenta	a query do relatorio do smartquotation ta levando 40s, ve o que da pra fazer
pg-campo-cnpj	adiciona o campo cnpj na tabela de cliente e faz a migration
infra-pve-restart	o container do postgres no pve ta reiniciando sozinho, ve isso
resumo-semana	escreve um resumo do que a gente fez essa semana pra eu mandar pro meu irmao
ts-console-logger	troca todos os console.log por logger no front do agenda
react-tela-config	cria a tela de configuracoes do agenda studio
qa-fluxo-orcamento	testa se o fluxo de orcamento ta funcionando ponta a ponta
review-pr	da uma revisada nesse PR antes de eu mergear
```
