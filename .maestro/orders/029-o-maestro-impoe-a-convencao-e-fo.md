<!-- maestro-order v1
id: 029
ts: 2026-09-19T20:13:41-03:00
epoch: 1789859621
head: 441d719fcbae793895c663c452d8cdeb112861e6
branch: feat/029-gatilho-imposto
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 029 — o Maestro impoe a convencao e forca a chamada por MCP: tres caminhos no Stop

## O furo, medido

Rodada na Enterprise terminou pedindo decisão em paráfrase — "Aguardo de você:" —
em vez da linha canônica. O hook não disparou; a mensagem chegou ao Diretor pelo
**eco do bridge**, não por MCP. O mecanismo das ordens 020/025 ficou inerte de novo.

E a causa raiz é anterior ao regex: a linha canônica vivia no INTENT, nas ordens
020/025, no CHANGELOG, em dois testes e num grader de eval — e **NUNCA na injeção**.
O gerente era cobrado por uma string que ninguém lhe entregava.

## A decisão, e que ela substitui a minha recomendação

Eu havia recomendado alargar o gatilho e recusado a alternativa de o gate reprovar,
argumentando superfície e Prioridade 1. **O Capitão decidiu diferente e sem escolha:
o Maestro IMPÕE a convenção e FORÇA a chamada por MCP.** O desenho dele é mais forte
no ponto que importa: liberar por **evidência da chamada** tira o mecanismo das mãos
do modelo. Meu argumento valia contra "reprovar por classificação de linguagem
natural"; o item (2) não faz isso.

## Os três caminhos

1. **Paráfrase sem a canônica, com socket → REPROVA.** A rodada volta com instrução
   de reescrever o fecho com a linha exata. É a imposição da convenção.
2. **Canônica com socket → SEGURA** até existir EVIDÊNCIA de que `director.ask` foi
   chamado nesta sessão. O Stop não libera por texto; libera por fato.
3. **Sem socket → passa, e REGISTRA** (`director_ask phase=sem_socket`).
   Prioridade 1 do INTENT: nunca bloquear trabalho por componente ausente. E o log
   passa a distinguir "não havia pergunta" de "havia e não houve como perguntar".

E, como conserto da causa raiz: **a injeção passa a ENSINAR a linha**, condicional ao
socket da Ponte — máquina sem Ponte não paga byte por mecanismo que não tem como
disparar (mesmo princípio do papercuts, ordem 026). Com o gate agora REPROVANDO,
ensinar deixou de ser cortesia: é parte de impor.

## Onde mora a evidência, e por que não no daemon

A decisão aberta vive em `~/.ponte/ponte.db` (SQLite). Lê-la custaria `sqlite3` como
dependência dura nova — que o próprio `pre-bash-guard.sh` classifica como comando de
banco — e acoplaria o Maestro ao esquema interno de OUTRO produto, que o INTENT põe
em "Fora de escopo" ("os gerentes e o supervisor vivem em repos próprios").

`director.ask` é uma tool MCP, e tool passa por **PreToolUse**, que é do Maestro.
`hooks/pre-director-ask.sh` (irmão do `pre-agent.sh`, mesmo molde) grava um marcador
por sessão quando a tool é chamada. Bash puro, sem jq, sem rede, sem dependência
nova. **Só metadados**: `session_id` e o nome da tool; os ARGUMENTOS da chamada —
que carregam a pergunta ao Diretor — nunca são lidos. A pergunta é conteúdo; o
marcador é fato.

Só `director_ask` marca: `director_wait` e `director_report` não provam que a
pergunta foi ABERTA.

## Prova exigida

`tests/hooks/test-order-029-gatilho.sh`, 16 asserções, os três caminhos e as bordas:
paráfrase reprovada com mensagem que ensina · canônica sem evidência segurada ·
canônica com evidência liberada · `director_wait` não libera · evidência não vaza
entre sessões · sem socket passa E registra · rodada sem pergunta passa limpo ·
contrato do hook novo (shebang, kill-switch, só metadados, bash puro).

Suíte completa verde. Catraca de habits **dentro do baseline** — a primeira rodada
estourou `oversized-file` e `deep-nesting`, e as duas foram pagas no mesmo
changeset (`gate-report.sh` de volta a 400 linhas, aninhamento do teste achatado).

Ratchet da injeção: **7310 B, inalterado** — a linha ensinada é condicional ao
socket, e `test-injection-budget.sh` passa a fixar `PONTE_MCP_SOCKET` num caminho
inexistente para medir conteúdo, não ambiente (mesmo buraco que a 026 fechou para o
papercuts).

## Achados registrados, fora do escopo

- **`gate-report.sh:304` usa `{1,200}`** ao extrair `essencia:` do brief. Medido:
  **~11 ms por invocação, FLAT** (13,3 ms com 100 chars de entrada, 10,2 ms com 700 —
  o custo é de COMPILAR o quantificador, não de casar). São ~22% do NFR de 50 ms.
  Mesma família da issue #42, em N menor. Conserto = `+` com corte por substring.
- **A razão do próprio hook continha o marcador, e o re-disparava.** Medido ao vivo,
  três vezes nesta sessão: o texto emitido dizia "nao repita a linha <marcador>" com o
  marcador LITERAL; ele ia para o transcript, e o `tail -c` da rodada SEGUINTE o
  encontrava e disparava o hook de novo — sem pergunta pendente nenhuma. **O hook
  escrevia a causa do próprio disparo seguinte.** Corrigido nesta ordem: as duas razões
  DESCREVEM o marcador em vez de transcrevê-lo, e uma asserção nova (029/4b) reprova
  qualquer razão que volte a contê-lo.
- **O gatilho por prosa não distingue uso de menção.** Uma rodada desta própria
  sessão foi barrada por CITAR a linha canônica ao explicar o mecanismo, sem
  pergunta pendente. Registrado em `papercuts.md`. O caminho (2) reduz o dano (a
  rodada é liberada assim que houver evidência), mas a classificação continua por
  texto — fechar isso de verdade é outra ordem.

## Contrato de execução
- Trabalhe APENAS no branch `feat/029-gatilho-imposto`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-29 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 029` (você não fecha a própria ordem).
