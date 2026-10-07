<!-- maestro-order v1
id: 073
ts: 2026-10-07T16:03:06-03:00
epoch: 1791399786
head: dc31a58f0b99f6d28aba7e14c6e418466bc4b1c5
branch: order/073-mod-de-leitura-headless-libera-l
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 073 — mod de leitura headless: libera leitura e manda a Ponte so o que sobra

## Por quê

**Decisão do Capitão de 07/10** (mods como base; fonte `~/dev/spock/docs/pesquisa-claude-code-nativo-vs-metodo-2026-10-07.md`, "Permissão
headless" e Fase 0). Fato do diretor: **~60 pedidos de permissão em 1 h de 2 runs headless, quase todos leitura** (~30 por hora por run). Cada
um sobe pela Ponte (`--permission-prompt-tool`) e acorda o Diretor para decidir o que a regra já sabe decidir. Causa provável (inferência,
a medir nesta ordem): leitura fora das pastas de trabalho (`~/.maestro`, o INTENT do spock, repos de referência) e `cd <outro> && git`.

**A meta, escrita antes e não renegociada: no máximo 3 pedidos de permissão por hora por run**, com **0 allow danoso** no replay das negações.

Esta é a **2ª de 4 ordens** dos mods: plugin `maestro-reads`, no mesmo marketplace gerenciado `maestro-managed` criado pela ordem da guarda
(`mods/maestro-guard`). **Fica atrás da guarda na cadeia** (`prependPlugins`: guarda primeiro): o que a guarda nega, esta nunca libera.

## O que entrega

1. **Medir antes de construir (obrigatório, no relatório).** Do `ponte.db` aberto **`mode=ro`** (`decision.kind='permission'`,
   `decision_resolution.choice`), da janela dos últimos 14 dias: pedidos por hora **por run**, por ferramenta (`Read`, `Glob`, `Grep`,
   `Bash` leitura, `Bash` outro) e por pasta-alvo (só o **prefixo** de 2 níveis, nunca o caminho cheio nem o comando). **Só inteiros.** Fonte
   ausente = **FALHA nomeada**, não "zero". Isso diz o que o mod precisa liberar.
2. **Plugin `maestro-reads` (`mods/maestro-reads/`).** Hook de `tool.check` que devolve **`allow`** quando **todas** as condições valem:
   - o run é **headless de gerente** (distinção abaixo);
   - a ferramenta é `Read`, `Glob`, `Grep` ou `Bash` cujo comando é **uma só** leitura da lista fechada (`ls`, `cat`, `head`, `tail`, `grep`, `rg`,
     `find` sem `-exec`/`-delete`, `wc`, `stat`, `git status|log|diff|show|rev-parse|branch --list|worktree list`, `maestro … --status|--list|--json`);
   - o caminho está dentro da **lista de pastas liberadas** (arquivo versionado `mods/maestro-reads/allow-paths.json`: `~/.maestro/`, o INTENT e
     as docs do spock, os repos de referência, os worktrees `maestro-*`, a pasta do próprio run);
   - o caminho **não** é segredo (`.env*`, `~/.ssh`, `~/.ponte`, `~/.claude/.credentials*`, certificados): a lista de segredo é a **mesma** da
     guarda, importada de um arquivo único (`mods/shared/secret-paths.json`), não copiada.
   Em qualquer outro caso, **`return next(e)`**: o pedido segue o caminho de hoje (Ponte). O mod **nunca devolve `deny`** (negar é da guarda).
3. **Como o mod sabe que o run é headless de gerente.** Por evento `session.start` (`isInteractive:false`) **e** variável de ambiente do
   lançador (`$.env.get`, nome exato a combinar com o runner do daemon; ver Ask-First). Sessão interativa do Capitão: **`next(e)` sempre**.
4. **Escrita nunca é liberada.** `Edit`, `Write`, `NotebookEdit`, `Bash` com redirecionamento, `rm`, `git add|commit|push|checkout|reset` seguem
   para a Ponte. Leitura **com efeito** (`git fetch`, `git pull`, `gh`, `ssh`, rede) também segue.
5. **Contador de pedidos por hora por run** (o que prova a meta): linha de log só de metadados por decisão do mod (`allow-leitura` ou
   `passou-adiante`), com `run`, `tool`, `rule`; **nunca** comando nem caminho. A medição "depois" usa a **Ponte**, não o log do mod.
6. **Alternativa nativa, dita no relatório.** `permissions.additionalDirectories` + regras `Read(...)` no settings do perfil gerente resolveriam
   parte sem código. A decisão do Capitão é mod; **implemente o mod** e diga, com o número do item 1, que fração dos pedidos o settings
   sozinho teria resolvido.

## O que fica de fora (e por quê)

- **Não** liberar escrita, rede, `ssh`, `gh`, `git push|fetch|pull`, nem o que a guarda nega.
- **Não** mexer no `--permission-prompt-tool` nem no runner do daemon (repo `ponte-daemon`): se o runner precisa de variável de ambiente nova
  para marcar o gerente, **peça** no relatório, não crie.
- **Não** aplicar o mod no ambiente: instalação é do Capitão (`tools/install-managed-mods.sh` da ordem da guarda + settings gerenciados `903`).
- **Não** emitir `deny`. **Não** abrir rede. **Não** ler conteúdo de arquivo: o mod olha **nome de ferramenta e caminho**.

## Ask-First

- **Esta é a única ordem dos mods que emite `allow`.** `tool.check` de mod **supera um `ask`** e, sem `sec-default`, até um `deny`. O desenho exige:
  (a) o mod só sobe `allow` com as 4 condições; (b) o teste adversarial prova que **nada fora da lista** vira `allow` (fuzz ≥ 200 comandos: `;`,
  `&&`, `|`, `$()`, crase, `bash -c`, `eval`, variável montando o caminho, `..`, symlink, caminho com `~`); (c) em dúvida, `next(e)`. Se uma
  forma de escape não puder ser fechada, PARE e relate; **não** afrouxe.
- **Contrato de eventos:** tipos da versão instalada (hoje **2.1.293**). Cole os nomes exatos de `tool.check`, de `session.start` e de `isInteractive`.
  Se o kit de teste não disparar `tool.check`, use função pura + teste da fiação (como na ordem da guarda) e diga qual valeu.
- **Marcação do gerente:** o nome da variável de ambiente que o runner deve exportar é decisão do **Diretor** com o `ponte-daemon`; a ordem
  **propõe** o nome e o teste usa um valor falso.
- **`allow-paths.json` é política:** quem acrescenta pasta liberada é o Diretor. A ordem entrega a lista **inicial** só com o que o item 1 mostrou.
- **Toca `lib/`, `bin/`, `hooks/`?** Não deve. Se algum passo exigir, PARE: seria **UM patch** em clone sandbox, como a regra manda.

## Como sai

`mods/maestro-reads/`, `mods/shared/secret-paths.json`, testes e docs direto no branch; a linha do plugin em
`mods/.claude-plugin/marketplace.json`. Emendas: API_SPEC (o contrato do mod e a lista fechada), CHANGELOG (Added).

## Critérios de aceite

- [oráculo: medição do item 1 colada] pedidos/hora/run, por ferramenta e por prefixo, só inteiros, **ou FALHA nomeada**.
- [oráculo: `claude plugin test` em `mods/maestro-reads`] cada leitura da lista, dentro da pasta liberada e no run headless, devolve `allow`; **cada**
  caso fora (escrita, rede, segredo, pasta não liberada, sessão interativa, comando composto) devolve o que `next(e)` devolveu. Vermelho antes, colado.
- [oráculo: teste adversarial] fuzz ≥ 200: **nenhum** comando fora da lista vira `allow`; o veredito da guarda (`tier('prepend')`) vence.
- [oráculo: **replay das negações**] todas as decisões `deny` do `ponte.db` dos últimos 14 dias (22 na fotografia de 06/10), reduzidas a
  (ferramenta, prefixo): **0 delas viraria `allow`** no mod. É o "0 allow danoso".
- [oráculo: `claude plugin validate ./mods/maestro-reads`] sai 0; `hooks:` e `calls:` colados (sem `http.fetch`, `process.*`, `fs.write` além do log).
- [oráculo: `bash tests/run-all.sh`] verde; `habits` sem aviso novo.
- [humano, **depois da instalação**] a meta **≤ 3 pedidos/hora/run** é medida na Ponte nos primeiros 3 dias; o relatório deixa o comando de
  medição pronto. Esta ordem **não** declara a meta atingida.

## Prova exigida

- A medição do item 1; o vermelho antes e o verde depois; o replay (contagens); o `validate`.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-NN` no tip e `maestro order --status NN` VÁLIDA.

## Turno

- fatia: a medição do item 1 (do `ponte.db` em `mode=ro`), o corpus de teste com o vermelho colado e a função pura da decisão com a lista fechada
- fim: `claude plugin test` em `mods/maestro-reads` sai 1 antes (colado) e 0 depois; a medição colada ou a FALHA nomeada; o replay das negações com 0 `allow`
- teto: 4
- fora: liberar escrita ou rede, emitir `deny`, tocar o runner/daemon, instalar o mod, tocar settings/managed-settings, vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54, com o sha do tip). Terminar a
> resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível, **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou redirecionamento (`>`, `>>`) para
> escrever código, teste ou documento. O Bash serve para rodar, ler e medir. Patch gerado por `git diff` do sandbox para `docs/patches/` é a única
> saída por redirecionamento admitida.

> **Comando simples:** um comando por chamada de Bash; caminho absoluto em vez de cd e &&; sem pipe para cortar saída (| tail, | head), a
> ferramenta já corta; 2>&1 é permitido (junta saídas, não grava arquivo); a suíte roda como uma chamada só, maestro evidence --record --label
> order-N -- <suíte>, em segundo plano (run_in_background da ferramenta Bash) e a espera é por Monitor; o recibo já grava o código de saída.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run, `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp`
> solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. A suíte roda como uma chamada só (`maestro evidence --record --label order-N --
> <suíte>`) em segundo plano, pelo `run_in_background` da ferramenta Bash, e a espera é por **Monitor**; o recibo já grava o código de saída. Só
> depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/073-mod-de-leitura-headless-libera-l`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-73 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 073` (você não fecha a própria ordem).
