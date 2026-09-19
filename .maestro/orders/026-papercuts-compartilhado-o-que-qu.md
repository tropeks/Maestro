<!-- maestro-order v1
id: 026
ts: 2026-09-18T21:50:38-03:00
epoch: 1789779038
head: c41fb6f4e02c3bc204f8843800b45e3186a5dbd1
branch: feat/026-papercuts
frozen: vendor/ agents/
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
absorbed_by: main
absorbed_tree: 349c2e7293784c4d6e70c583a5737b89a6e04818
absorbed_at: 2026-09-19T10:40:56-03:00
absorbed_session: desconhecido
-->
# Ordem 026 — papercuts compartilhado: o que quebrou de forma estranha, consultado antes de investigar



## Contrato de execução
- Trabalhe APENAS no branch `feat/026-papercuts`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/
- Prove com o ledger: `maestro evidence --record --label order-26 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 026` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v3, Prioridade 1 — "nunca bloquear trabalho por estar quebrado". Quando a
ferramenta falha de forma estranha, o gerente hoje **investiga do zero**, sozinho,
e o que ele aprende morre com a sessão.

**Só em 2026-09-18, nesta máquina, pelo menos cinco:**

| sintoma | o que era |
|---|---|
| pane lê vazia no 2.1.277 | regressão do harness |
| carimbo terminal some depois do merge | vivia como modificação não commitada (ordens 021/022) |
| `pkill` sai 144 | código de saída fora do esperado |
| classificador barra LEITURA | consulta ao `ponte.db` com certos filtros virou "transação real" |
| `wtree` conta arquivo não rastreado | recibo de `main` nasce vencido se a árvore estiver suja |

Cada um custou investigação. Vários custaram mais de uma vez, em sessões
diferentes, porque **nenhum gerente enxerga o que o outro já descobriu**.

## O que esta ordem entrega

Um **`papercuts.md` compartilhado por todos os gerentes**, com quatro campos por
linha:

```
data · sintoma · conserto · projeto
```

**Consultado PRIMEIRO** quando uma ferramenta falha de forma estranha, antes de
investigar. Entra no método via **hook de session-start lendo o arquivo**.

## AS DECISÕES QUE VOCÊ TEM DE TOMAR — e elas decidem se isto serve

**1. Onde o arquivo mora.** Ele é *compartilhado por todos os gerentes*, e os
projetos são repos diferentes. Então não é `docs/` de um projeto — é `~/.maestro/`
ou equivalente. Escolha, e justifique contra o `MAESTRO_HOME` que já existe.

**2. O orçamento da injeção, que é o risco real desta ordem.** A injeção do
SessionStart tem **teto de 8000 B com ratchet**, e hoje roda em ~7400. O INTENT
v3 diz, com todas as letras: **injeção acima de 8000 B está FORA por texto
expresso.**

Cinco papercuts já são várias linhas. Cinquenta, daqui a um mês, não cabem.
**Injetar o arquivo inteiro está proibido.** Decida o que vai para a injeção —
ponteiro? contagem? nada, e o gerente lê sob demanda? — e **escreva a razão**.
Se a sua escolha crescer a injeção em qualquer byte, ela tem de **cortar o mesmo
tanto no mesmo commit** (Prioridade 5), ou não vai.

**3. Quem escreve.** Um papercut é registrado por um gerente e lido por nove. Se
qualquer sessão escreve direto no arquivo, duas sessões escrevendo juntas se
atropelam — este projeto já pagou por escrita concorrente. Escolha o mecanismo
(append atômico? CLI? só o humano escreve?) e **teste concorrência**.

**4. O que NÃO entra.** Papercut é falha de FERRAMENTA com conserto conhecido.
Não é bug do projeto (isso é issue), não é lição de método (isso é brief), não é
armadilha de código (isso é comentário no código). Escreva o critério, ou o
arquivo vira despejo em duas semanas e ninguém consulta.

## TRAVAS — pare e chame

- **Injeção acima de 8000 B: fora por texto expresso do INTENT v3.** Se a sua
  solução precisar disso, PARE.
- **Logs só de metadados.** O papercut pode citar ferramenta e código de saída;
  **nunca** caminho completo de arquivo nem conteúdo de prompt.
- **`hooks/` é bash puro**, nunca invoca Bun, nunca importa `src/`, NFR <50ms por
  invocação. Ler um arquivo a cada SessionStart tem custo — **meça**, e meça por
  delta contra o baseline da mesma máquina (`ARCHITECTURE.md`, NFRs).
- Mudança de veredito do `maestro doctor`.

## Prova exigida

- Os **cinco papercuts de 2026-09-18** registrados como conteúdo inicial — são o
  caso de uso real e o teste de que o formato serve.
- Teste do hook: arquivo ausente → nada quebra, sessão inicia normal
  (Prioridade 1). Arquivo presente → o gerente enxerga o que você decidiu que ele
  enxerga.
- Teste de concorrência da escrita, conforme o mecanismo que você escolher.
- **Orçamento da injeção antes e depois, em bytes**, com o corte compensatório se
  houver crescimento.
- Latência do `session-start` por delta, baseline e patched interleaved.
- Suíte completa verde em cópia patchada; `habits` por arquivo; `doctor` sem
  mudança de veredito.
- Recibo `maestro evidence --record --label order-26 -- bash tests/run-all.sh`.

## Contrato de execução
- Worktree próprio: `git worktree add -q /tmp/wt-026 -b feat/026-papercuts main`.
- **TUDO que a ordem muda entra como patch em `docs/patches/`**, `tests/` e
  `docs/` inclusive. Um diretório, ordem de aplicação numerada.
- **Regrave o patch imediatamente após cada edit** e verifique com `git apply` a
  partir do patch salvo, nunca do arquivo editado ao vivo.
- `git clone` para cópia patchada, nunca `git archive`.
- `git add` NOMINAL, jamais `-A`. **Commite.**
- Sob `set -e`, chamada NUA a função que pode devolver 1 mata o processo em
  QUALQUER ponto do corpo — `f && return 0; return 1`.
- Kill-switch `MAESTRO_OFF=1` na primeira linha de todo hook — não quebre.
- **Sem carga sintética** — confirme se o NetForge tem run vivo na lab.
- Grave o essencial em `docs/patches/026-NOTAS.md`.
- Registre a HORA DE CHEGADA.
- O aceite é do diretor: `maestro order --accept 026`.
