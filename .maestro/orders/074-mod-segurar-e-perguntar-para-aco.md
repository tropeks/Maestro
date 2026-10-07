<!-- maestro-order v1
id: 074
ts: 2026-10-07T16:03:35-03:00
epoch: 1791399815
head: dc31a58f0b99f6d28aba7e14c6e418466bc4b1c5
branch: order/074-mod-segurar-e-perguntar-para-aco
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 074 — mod segurar e perguntar para acoes classe B

## Por quê

**Decisão do Capitão de 07/10** (mods como base; fonte `~/dev/spock/docs/pesquisa-claude-code-nativo-vs-metodo-2026-10-07.md`, "Onde entram os
mods": **"segurar e perguntar" para os padrões de classe B**). A classe B é o irreversível que só o Capitão assina (deploy, push na main, migração
destrutiva, apagar dado ou volume, billing, auth/segredo). Hoje a trava é lexical (`pre-bash-guard`) e a Ponte. O mod segura a chamada **antes**
dela rodar, pergunta, e **nunca aprova nada sozinho**.

Esta é a **3ª de 4 ordens**: plugin `maestro-hold`, no marketplace `maestro-managed` (criado pela ordem da guarda). Fica **atrás da guarda** na
cadeia: o que a guarda nega, esta nunca pergunta.

## O que entrega

1. **Lista de classe B, versionada.** `mods/maestro-hold/classe-b.json`: cada entrada com `id`, `tool`, padrão estrutural e o **porquê** (a
   linha da matriz "Quem decide" que a justifica). A lista **inicial vem da matriz do INTENT e do ARCHITECTURE** (o executor lê e cita as
   linhas); mínimo esperado: `gh pr merge`, `git push` para main/master, `ssh` para produção e o script de deploy, `DROP`/`TRUNCATE`/`DELETE` sem
   `WHERE`, `docker volume rm`/`prune`, migração destrutiva, edição de `.github/workflows/**`, de `~/.claude/settings*.json` e dos segredos.
   Entrada sem justificativa na matriz **não entra**.
2. **Hook `tool.call` (Bash, Edit, Write, MCP) do `maestro-hold`.** Se a chamada casa um padrão da lista: **segura** e chama `$.ui.ask` com a
   pergunta no formato regido, em 3 linhas: **essência** (o que é) · **impacto** (o que representa) · **approach** (como seria feito), com as
   opções `Executar` e `Recusar`.
   - `Executar` → `return next(e)` (**a checagem normal de permissão ainda roda depois**: o mod não aprova, só deixa seguir);
   - `Recusar`, texto digitado, pergunta dispensada → `{deny}` com instrução que o Claude consiga seguir ("é classe B; peça ao Diretor pela
     Ponte, classe B");
   - **sem humano para perguntar** (`claude -p`, em que `$.ui.ask` rejeita): `{deny}` com a mesma instrução. **No headless o caminho é a Ponte
     (`director.ask`, classe B com biometria), não o mod.**
3. **Padrões, não adivinhação.** A decisão é função pura `classificar(tool, input) → {classeB: bool, id}`, testada com corpus (≥ 80 casos: ≥ 30
   classe B, ≥ 30 que NÃO são, o resto de borda), com as contagens de **falso positivo e falso negativo** no relatório (só inteiros). Pergunta
   demais é o defeito que a auditoria apontou na guarda léxica (63–78% de falso positivo): **cada falso positivo medido tem de ter razão escrita**.
4. **Queda segura que recusa.** `.catch` que devolve `{deny}` com `next.error.kind`; **o tempo da pergunta não conta** no limite do hook (espera
   dentro de `$.ui.ask`), mas tempo em promessa própria conta: o teste cobre a espera longa.
5. **Registro só de metadados.** Linha por segurada: `id` da classe, `tool`, `resposta` (`executar|recusar|sem-humano|erro`), nunca comando,
   caminho nem prompt. **Sem rede.** Contagem por dia para o painel (só inteiros).
6. **Sem `allow`, sem `deny` por regra própria fora do hold.** O mod só **segura e pergunta**; a recusa automática é da guarda.

## O que fica de fora (e por quê)

- **Não** aprovar classe B (aprovação biométrica é da Ponte); **não** chamar a Ponte, a rede ou o daemon a partir do mod.
- **Não** substituir o gate de ship/deploy da Ponte nem a custódia da credencial de produção (a credencial fora do alcance do agente é
  outra frente, do Capitão).
- **Não** tocar `hooks/`, `bin/`, `lib/`; **não** instalar o mod; **não** mexer em settings.
- **Não** ampliar a lista da classe B sem linha da matriz (isso é decisão do Diretor).

## Ask-First

- **Contrato de eventos:** tipos da versão instalada (hoje **2.1.293**): cole o nome exato de `$.ui.ask`, de `tool.call` e dos campos do
  comando/caminho. Confirme no teste o comportamento que a documentação descreve: `$.ui.ask` **rejeita** em `claude -p`. Se não rejeitar, PARE.
- **O kit de teste** simula `$.ui.ask` por um stub de `tool.call` para a ferramenta `AskUserQuestion` (documentação do kit). Use-o; se não
  funcionar com o mod real, relate o que ficou sem cobertura.
- **Quem é "o humano" da pergunta:** em pane de gerente ou de Diretor a pergunta aparece na tela do agente, **não** chega ao Capitão. Por isso
  `Executar` só é seguro como "deixa seguir para a checagem normal", e a **assinatura** de classe B continua na Ponte. Relate se o Diretor quer
  que `Executar` fique **desligado** nos runs não interativos (padrão desta ordem: desligado, sempre `deny` no headless).
- **Origem da lista:** se a matriz do INTENT não enumerar um padrão, **não invente**: PARE e liste as lacunas no relatório.
- **Toca `lib/`, `bin/`, `hooks/`?** Não deve; se for preciso, **UM patch** em clone sandbox fora do repo.

## Como sai

`mods/maestro-hold/` (inclui `classe-b.json`), testes e docs direto no branch; a linha do plugin em `mods/.claude-plugin/marketplace.json`.
Emendas: API_SPEC (contrato do mod e da lista), ENGINEERING_SPEC (limites: o que a lista lexical não vê), CHANGELOG (Added).

## Critérios de aceite

- [oráculo: `claude plugin test` em `mods/maestro-hold`] cada padrão de classe B **segura** e pergunta; cada controle negativo passa **sem** pergunta;
  `Executar` → `next(e)`; `Recusar`/texto/dispensa → `{deny}`; headless → `{deny}`. Vermelho antes, colado.
- [oráculo: teste adversarial] o mod **nunca** devolve `allow`; em `throw`/`timeout`/evento malformado devolve `{deny}`; com a guarda em `prepend`
  negando, a pergunta **nem aparece**.
- [oráculo: corpus] contagens FP/FN coladas, cada FP com razão escrita.
- [oráculo: `claude plugin validate ./mods/maestro-hold`] sai 0; `hooks:` e `calls:` colados (`ui.ask`, `env.get`, `fs.write` do log; **sem** `http.fetch`/`process.*`).
- [oráculo: `bash tests/run-all.sh`] verde; `habits` sem aviso novo.
- [humano] o Diretor lê `classe-b.json` com a linha da matriz de cada entrada e as lacunas.

## Prova exigida

- Vermelho antes e verde depois; o corpus (FP/FN); as linhas da matriz citadas; o `validate`.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-NN` no tip e `maestro order --status NN` VÁLIDA.

## Turno

- fatia: a leitura da matriz "Quem decide" e a lista `classe-b.json` com a justificativa de cada entrada, o corpus (≥ 80) com o vermelho colado e a função pura `classificar`
- fim: `claude plugin test` em `mods/maestro-hold` sai 1 antes (colado) e 0 depois; as contagens FP/FN coladas; as lacunas da matriz listadas
- teto: 3
- fora: aprovar classe B, chamar Ponte/rede/daemon, ampliar a lista sem linha da matriz, instalar o mod, tocar settings/managed-settings, vendor/
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
- Trabalhe APENAS no branch `order/074-mod-segurar-e-perguntar-para-aco`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-74 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 074` (você não fecha a própria ordem).
