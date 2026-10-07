<!-- maestro-order v1
id: 072
ts: 2026-10-07T16:02:24-03:00
epoch: 1791399744
head: dc31a58f0b99f6d28aba7e14c6e418466bc4b1c5
branch: order/072-mod-de-politica-tool-check-guard
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 072 — mod de politica tool.check: guarda de destrutivos e autoprotecao

## Por quê

**Decisão do Capitão de 07/10:** os controles do Maestro migram para **mods do Claude Code como base**, não como camada fina. Fonte:
`~/dev/spock/docs/pesquisa-claude-code-nativo-vs-metodo-2026-10-07.md` (inventário, linhas 6 e 7: `pre-bash-guard` e autoproteção de
`hooks/` e `bin/`). Sem fixar versão do Claude Code: a API pode mudar e a fábrica se adapta (a ordem de vigia, a quarta da série, cuida disso).
Esta ordem **supera o desenho da 065** (adiada) no que toca à guarda: a lógica mora **no mod**, não num núcleo do CLI, e a queda é **segura**
(recusa), não fail-open.

Esta é a **1ª de 4 ordens** dos mods (guarda, leitura headless, segurar e perguntar, vigia). Elas **não se dispensam entre si**: cada uma é um
plugin separado no mesmo marketplace gerenciado; esta cria o marketplace.

## O que entrega

Um **plugin de mod, `maestro-guard`**, em `mods/maestro-guard/` (plugin.json, `hooks/hooks.json`, `hooks/register.js`, `tests/*.test.ts`) e o
marketplace `mods/.claude-plugin/marketplace.json` (nome `maestro-managed`, o plugin listado por caminho relativo `./maestro-guard`).

1. **Destrutivos (substitui `hooks/pre-bash-guard.sh`).** Hook de `tool.check` (e `tool.call` com `{deny}` como segunda trava) para Bash: nega
   `rm -rf` de alvo largo, `git push` com force (inclui `-f`, `-fu`, `--force`, `--force-with-lease` **só quando** o alvo é a main), `git reset
   --hard` fora de worktree descartável, `DROP`/`TRUNCATE`/`DELETE` sem `WHERE`, `git clean -fdx`, `chmod -R`/`chown -R` largo. A base de casos é a
   do `tests/hooks/test-guarda-destrutiva.sh`: **todo caso do hook bash tem o mesmo veredito no mod** (tabela caso × adaptador colada).
2. **Autoproteção (substitui a parte de `self_paths` do gate e do guard).** Nega `Edit`/`Write`/`NotebookEdit` e escrita por shell (`sed -i`, `tee`,
   `>`, `>>`, heredoc redirecionado, `python -c`, `node -e`, `cp`/`mv`/`install` com destino) em `agents/ bin/ src/ hooks/ lib/
   config/routing-table.yaml config/accept-proof.pub .claude-plugin/ mods/`, no checkout **e em todo worktree** (`/home/.../worktrees/*/…`). A
   exceção é o clone sandbox fora do repo (pasta do run, `/tmp/claude-<uid>/…`), por onde o patch protegido sempre passou.
3. **Segredo.** Nega leitura de `.env*`, `~/.ssh`, `~/.ponte`, `~/.claude/.credentials*`, certificados (`*.pem`, `*.pfx`, e-CPF) por
   `Read`, `Grep`, `Glob` e por `cat`/`less`/`head`/`tail`/`cp` no Bash. **Nenhum conteúdo** de arquivo nem de comando vai a log.
4. **Queda segura que recusa.** Todo hook de bloqueio leva `.catch` que devolve `{deny}` com `next.error.kind` (`throw`/`timeout`); comando
   gigante, bytes inválidos, aspas aninhadas ou evento malformado **nega** (nunca vira `allow`). O mod **nunca emite `allow`**: devolve `deny` ou
   o que `next(e)` devolveu. (A ordem de leitura headless é a única que emite `allow`, e ela fica **atrás** desta na cadeia.)
5. **Falso positivo é o inimigo medido.** A auditoria de 05/10 achou 63–78% de falso positivo no guard léxico (114 bloqueios em 14 dias).
   Um mod léxico que repete isso **falha a ordem**. Regra de desenho: **nega** só a classe estrutural clara; o ambíguo vira **`ask`** (a pergunta
   sobe como hoje), nunca `deny`. O corpus de teste tem **≥ 150 comandos** (≥ 60 que DEVEM passar: `echo $?`, `git commit -m "$(cat <<'EOF'…)"`,
   `2>&1`, `/dev/null`, a pasta do run, `git push` de branch de trabalho, `rm` de arquivo único em `/tmp`…; ≥ 60 que DEVEM negar; o resto `ask`), e o
   relatório traz as contagens **falso positivo / falso negativo** do corpus (só inteiros).
6. **Log só de metadados.** Linha por veredito: `rule`, `tool`, `verdict`, nunca comando, caminho completo nem prompt (regra do projeto). Vai
   para `~/.maestro/logs/` pelo mesmo canal dos hooks; **sem rede**.
7. **Kill-switch.** `MAESTRO_OFF=1` lido **uma vez no load** por `$.env.get` (o ambiente do processo do Claude Code, que o `Bash` do agente não
   altera) desliga o mod e **loga que desligou**. Ver Ask-First.
8. **Instalação.** `tools/install-managed-mods.sh` (o Capitão roda com `sudo`; esta ordem **não** roda) copia `mods/` para
   `/opt/maestro/claude-plugins` com dono `root:root`, modo `755`/`644`, e **recusa** se o destino ou um pai for gravável por não-root. Passo a
   passo em `docs/mods/INSTALACAO.md`: o mod só conta como "da organização" com **settings gerenciados** (patch `903`, ramo
   `mods/managed-settings`, fora desta ordem) e o diretório de root.

## O que fica de fora (e por quê)

- **Não** remover `hooks/pre-bash-guard.sh` nem o registro no `hooks.json` **neste turno**: a janela da Fase 1 (sombra) mede o guard até
  **2026-10-13T18:07:28-03:00**; trocá-lo no meio contamina a medida. A remoção sai como **patch protegido preparado, não aplicado**.
- **Não** reimplementar a guarda como sandbox de SO (é a Fase 1 da auditoria, já feita à parte) nem tocar nos blocos `sandbox`/`permissions` do
  `settings.json`.
- **Não** emitir `allow` (é a ordem de leitura headless) nem perguntar ao humano (é a de segurar e perguntar).
- **Não** abrir rede, **não** ler segredo, **não** escrever arquivo pelo mod além do log de metadados.

## Ask-First

- **Contrato de eventos:** a API dos mods "pode mudar entre versões". Gere os tipos da versão instalada (hoje **2.1.293**; mods exigem ≥ 2.1.287)
  e cole os nomes exatos de `tool.check`, `tool.call`, do campo do comando (`e.input.command`), de `e.input.file_path` e do formato do retorno
  (`{decision:'deny', reason}` no `tool.check`; `{deny}` no `tool.call`). Se um evento ou campo **não existir**, PARE e relate.
- **O kit de teste (`claude-code/testing`) não lista `tool.check` entre os eventos que dispara** (`$.tool.call`, `$.command.run`,
  `$.prompt.submit`, …). Se `tool.check` não puder ser disparado, escreva a decisão como **função pura** num `.ts` (importável pelo teste) com o
  corpus inteiro, e teste a **fiação** do hook com `$.tool.call` + `on('tool.call', …)`. Diga qual caminho valeu; não finja cobertura.
- **Kill-switch no mod:** `CLAUDE.md` exige `MAESTRO_OFF=1` em todo hook. Num mod que **falha fechado**, ele é uma porta. A ordem faz como o
  `CLAUDE.md` manda (liga e loga); se o Capitão preferir sem porta, é uma linha. Relate a escolha.
- **Fronteira do projeto:** `CLAUDE.md` diz "hooks/ = bash puro, nunca invoca Bun, nunca importa src/". O mod é JS **fora** de `hooks/` e **não**
  importa `src/`. É **superfície nova**: PARE se algum passo exigir mudar a regra; a emenda de `CLAUDE.md`/ARCHITECTURE (ADR) é do **Diretor**: a
  ordem **escreve o texto da emenda** em `docs/mods/EMENDAS-PROPOSTAS.md`, não a aplica.
- **Toca `hooks/`, `bin/`, `lib/` (autoprotegidos):** o patch de remoção do guard e a inclusão de `mods/` em `self_paths` são **UM patch** em
  `docs/patches/` (número operacional a combinar), feito em clone sandbox **fora** do repo, `git apply --check` ok, **não aplicado**; `mods/`,
  `tests/`, `tools/` e `docs/` vão direto no branch.
- Se o mod barrar fluxo **legítimo** medido (suíte, comando de turno, `maestro` interno), PARE e reporte os casos antes de afrouxar.
- **Sem sudo na fábrica:** com `sudo` sem senha o dono do processo desfaz o diretório de root; o mod é **tripwire, não fronteira**, até o cutover para
  o usuário sem sudo. Escreva isso em `docs/mods/INSTALACAO.md` sem enfeitar.

## Como sai

Mod, testes, instalador e docs direto no branch; o patch protegido (remoção do guard + `mods/` em `self_paths`) **pronto e não aplicado**.
Emendas no mesmo changeset: API_SPEC (o contrato do mod: eventos, vereditos, log), ENGINEERING_SPEC (limites declarados da guarda léxica: o que
um `bash -c`, `eval` ou variável montando o caminho escapa), CHANGELOG (Added).

## Critérios de aceite

- [oráculo: `claude plugin test` em `mods/maestro-guard`] o corpus inteiro verde: destrutivos negam, autoproteção nega no checkout e nos worktrees,
  segredo nega, os controles negativos passam, o ambíguo vira `ask`. **Vermelho antes** (o plugin não existe), colado.
- [oráculo: `claude plugin test`, teste adversarial] o mod **nunca** devolve `allow`; em `throw`/`timeout`/evento malformado devolve `deny`; com
  outro mod no `tier('user')` que devolve `allow`, o veredito do guard **continua `deny`** (usa `plugins:` do kit e `tier('prepend')`).
- [oráculo: `bash tests/hooks/test-guarda-destrutiva.sh` e `bash tests/hooks/test-order-047-bash-self-paths.sh`] seguem verdes (o hook bash **não regride**).
- [oráculo: `claude plugin validate ./mods/maestro-guard`] sai 0; o `hooks:` e o `calls:` colados (só `tool.check`/`tool.call`, `env.get`, `fs.write` do log;
  **sem** `http.fetch`, `process.*`, `mcp.call`, `model.complete`).
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [humano] o Diretor lê a tabela **caso × adaptador** e as contagens de falso positivo/negativo do corpus.

## Prova exigida

- Vermelho antes e verde depois, saídas coladas; a tabela caso × adaptador; as contagens de FP/FN do corpus.
- O `validate` com `hooks:` e `calls:`; a lista dos limites declarados.
- `git apply --check` do patch protegido (não aplicado).
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-NN` no tip e `maestro order --status NN` VÁLIDA.

## Decisões do Diretor de 07/10

Valem a partir do turno 2 e **mudam o que os itens 1 e 4 de "O que entrega" dizem**. Não reabra.

- **(a) Sessão interativa com humano: destrutivo vira `ask`, não `deny`.** `deny` só em **headless** (`session.start` com `isInteractive:false`; sem
  humano para perguntar). O `ask` sobe como hoje ao humano da sessão. Vale para os **destrutivos** (item 1); autoproteção e segredo seguem como a
  ordem escreve (`deny`) até o Diretor dizer o contrário. Queda segura (`throw`/`timeout`/evento malformado) segue **`deny`**, também em sessão
  interativa. Teste obrigatório: o mesmo comando destrutivo dá `ask` com `isInteractive:true` e `deny` com `isInteractive:false`.
- **(b) Aceitos os 12 casos que passam de `block` para `ask`** (tabela `block → ask` de `docs/mods/CASOS-ADAPTADOR.md`, do turno 1). Não os
  "conserte" para `deny` nem os tire do corpus; a tabela caso × adaptador fica como está, com esta decisão citada.
- **(c) `maestro order --accept` fica fora do mod.** O aceite é do Diretor e já tem a trava do CLI (você não fecha a própria ordem); o mod **não** casa,
  nega nem pergunta por `maestro order --accept`. Se algum caso do corpus o tocar, retire-o.
- **(d) O kill-switch `MAESTRO_OFF=1` fica, com log.** Lido uma vez no load por `$.env.get`; ao desligar, o mod **loga que desligou** (só metadados:
  `rule=kill-switch`, nunca comando nem caminho). Um teste cobre os dois estados.

## Estado e divisão em turnos

- **Turno 1: FEITO** (commit `be58181`): o corpus, a decisão como função pura, a fiação do hook, a tabela caso × adaptador. **Não o repita.**
- **Turno 2:** o que falta de `mods/`, `tools/` e `docs/` (fatia abaixo). **Turno 3:** o patch protegido e a suíte completa com recibo.

## Turno

- ESTADO: turnos 1 e 2 concluídos e verdes em `5b20c1b`. **Não repetir.** O próximo run faz **só o turno 3**: o patch protegido com `git apply --check`, a suíte completa e o recibo `order-72`.
- fatia: **turno 3**: o patch protegido em `docs/patches/` (remoção do registro do `pre-bash-guard` no `hooks/hooks.json` e `mods/` em `self_paths`; clone sandbox fora do repo; `git apply --check` ok; **não aplicado**), a suíte completa `bash tests/run-all.sh` e o recibo `order-72` no tip
- fim: o patch pronto com `git apply --check` ok (saída colada); `bash tests/run-all.sh` sai 0 (`SUITE OK`), sozinha no worktree; `maestro evidence --record --label order-72 -- bash tests/run-all.sh` gravado e `maestro order --status 72` VÁLIDA; `claude plugin test` e `claude plugin validate` em `mods/maestro-guard` seguem verdes
- teto: 4
- fora: remover o guard bash, aplicar patch, rodar o instalador, tocar settings.json/managed-settings, emitir `allow`, rede, vendor/
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
- Trabalhe APENAS no branch `order/072-mod-de-politica-tool-check-guard`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-72 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 072` (você não fecha a própria ordem).
