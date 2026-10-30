<!-- maestro-order v1
id: 065
ts: 2026-10-04T20:33:13-03:00
epoch: 1791156793
head: 21c71c1dab4c7f27910d714326d76e181b5e60f2
branch: order/065-piloto-de-mod-do-claude-code-ada
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
deferred_by: spock 2026-10-06 regra da subtracao
-->
# Ordem 065 — piloto de mod do Claude Code: adaptador fino sobre o nucleo da Maestro

## Por quê

**Decisão do Capitão de 04/10.** O Claude Code lançou **mods** em 01/10/2026: handlers JS/TS que rodam
**dentro do processo** do Claude Code e participam dos eventos internos (`tool.check` devolve `allow`/`ask`/`deny`,
`classic.Stop`, `turn.*`), distribuídos dentro de plugins. Pesquisa de 04/10:
`/tmp/claude-1000/-home-rcosta00-dev-spock/8f3b6819-8f8c-49e3-9514-79fd631cd367/scratchpad/mods/mods.md`.

**A regra do Capitão, que manda no desenho:** *a Maestro é a metodologia dele e tem de valer além de qualquer
provedor.* O mod é **só um ADAPTADOR fino do Claude Code**. **A lógica fica no núcleo da Maestro, o CLI, testável
sem Claude Code; o mod só chama o núcleo.** Isto **adianta o "núcleo + adaptadores" da E24** (INTENT, linha 108,
"Split de `bin/maestro` e `src/cli.ts` em núcleo + adaptadores (E24)"; EPICS E24): a E24 separou o CLI em
`lib/core-*` e `lib/cmd-*`, mas as **guardas e o fim de turno ainda vivem como hooks bash** acoplados ao Claude
Code (`hooks/pre-bash-guard.sh`, 669 linhas). O piloto é a primeira fronteira real entre núcleo e adaptador.

**O que o ganho esperado mede:** hoje a escrita por shell (`sed -i`, heredoc, `python -c`, redirecionamento)
vira **pedido de permissão** e o fim de turno **sem relato** sai calado; os dois aparecem no painel da 063
(permissões por turno; turnos encerrados sem relato). O mod intercepta **antes** de virar permissão e fecha o
turno **dentro do processo**.

## O que entrega

**Escopo do piloto: duas coisas e só duas.**

### 1. Trava de escrita por shell, barrada antes de virar permissão

1. **No núcleo (CLI), não no mod.** Um comando do núcleo recebe a chamada de Bash (comando, cwd, projeto) e devolve
   o **veredito** em formato estável e agnóstico de provedor: `{"decision":"deny|allow","reason":"…","rule":"…"}`
   com exit code por veredito. Nome e forma ficam no contrato do núcleo (API_SPEC), **sem nenhuma palavra do Claude
   Code** (nada de `tool.check`, `$`, `e`).
2. **Regra:** o comando é negado (com a instrução "use Edit ou Write") quando **grava arquivo por shell**: `sed -i`,
   heredoc **redirecionado a arquivo** (`cat > f <<EOF`), `tee`, `python`/`python3`/`node` escrevendo, e
   redirecionamento `>`/`>>`/`&>`/`>|` para arquivo. A base é a tabela da ordem 047 (formas de escrita), estendida
   de `self_paths` para **qualquer arquivo**.
3. **O que NÃO pode ser barrado (controles negativos, parte do contrato):** `/dev/null`, redirecionamento de
   descritor (`2>&1`), heredoc que **não** grava arquivo (ex.: `git commit -m "$(cat <<'EOF' … EOF)"`), leitura
   (`cat`, `grep`, `cp` de dentro para fora) e **a pasta temporária do próprio run**,
   `/tmp/claude-<uid>/<cwd codificado>` (regra da 062: log de suíte e saída de espera vão para lá por
   redirecionamento — barrar isso quebraria o próprio método).
4. **Fonte única:** a regra tem **uma implementação**. O hook `hooks/pre-bash-guard.sh` e o mod chamam a mesma,
   nunca duas cópias que divergem. Onde ela mora (lib compartilhada, comando do CLI, ou os dois) é decisão do
   executor, dentro do orçamento do guard (50 ms; Ask-First abaixo).

### 2. Fim de turno dentro do processo

1. O núcleo já tem o veredito: `maestro order --turno-check` (ordem 046/056: recibo VÁLIDO no tip, teto de 3
   bloqueios, contrato (a) do 124 com a checagem local dos 5 rótulos). **Não se reimplementa nada no mod.**
2. O mod registra o handler do fim de turno (`classic.Stop` ou o evento equivalente que a versão instalada
   expuser), chama o núcleo por processo (`$.process`) e, se o veredito for bloquear, **devolve o bloqueio com a
   lista do que falta** no formato do evento. Dentro do processo, o handler **não está sob o `timeout 2` do
   hook**: o orçamento do mod é o do handler (≈10 s no Claude Code; estourar = handler ignorado = libera).

### Princípios do adaptador (valem para os dois itens)

- **Fino:** o mod não decide, não parseia comando, não conhece rótulo, ordem ou recibo. Ele **traduz** o evento
  do Claude Code para a chamada do núcleo e o veredito de volta.
- **Nunca libera o que o núcleo nega, e nunca emite `allow`.** O mod só devolve `deny` (quando o núcleo nega) ou
  **passa adiante** (`next(e)`). **Nunca** `allow`: `tool.check` do mod *pode superar* `ask` e, fora de ambiente
  gerenciado, até `deny` (pesquisa, "Limites e permissões"). Núcleo ausente, erro, timeout, saída inválida, versão
  do CLI incompatível → **passa adiante (fail-open do núcleo)**, jamais `allow` por conta própria.
- **Os hooks bash continuam como adaptador de reserva** (`hooks/*.sh` não saem nem mudam de comportamento). Mod
  ausente, desligado ou quebrado → o fluxo é o de hoje. `MAESTRO_OFF=1` desliga o mod também.
- **Mods não são sandboxed** (acessam arquivos, segredos, processos e rede com os privilégios do usuário): o mod
  **não usa rede, não lê segredos, não escreve arquivo por conta própria** e usa só `tool.check`/Stop e
  `$.process` para o CLI. Nenhuma chamada de rede (regra do projeto).
- **Escopo local do piloto:** instalado com `--scope local` (ou `claude --plugin-dir` no worktree), **nunca**
  `user`/`project`. Exige Claude Code **≥ v2.1.287**; versão menor → o mod não registra e o relatório diz.
- **Local do código:** `adapters/claude-code/` (fora de `hooks/`, que segue **bash puro**, e de `src/`, que o mod
  **não importa**). Plugin próprio (`adapters/claude-code/.claude-plugin/plugin.json`, `hooks/hooks.json` com
  `"modules"`), sem tocar o `.claude-plugin/` da Maestro.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-order-065-nucleo-guarda.sh`] **o núcleo, sem Claude Code:** o comando de veredito,
  alimentado por stdin/arquivo, nega cada forma de escrita por shell da tabela (relativo, absoluto, fora de
  `self_paths`) e **permite** todos os controles negativos do item 3 (incluindo a pasta temporária do run).
  **Vermelho antes** (o comando não existe), colado.
- [oráculo: `bash tests/cli/test-order-065-mod-adversarial.sh`] **teste adversarial do mod** (ver abaixo): o mod
  **nunca** retorna `allow`, e **nunca libera o que o núcleo nega**.
- [oráculo: `bash tests/cli/test-order-065-mod-fim-de-turno.sh`] com o núcleo simulado, o handler bloqueia quando o
  `--turno-check` bloqueia, libera quando libera, e passa adiante em erro/timeout; o veredito do hook bash e o do
  mod são **iguais** para os mesmos casos (tabela caso × adaptador colada).
- [oráculo: `bash tests/hooks/test-guarda-destrutiva.sh` e `bash tests/hooks/test-order-047-bash-self-paths.sh`] seguem
  verdes (o hook de reserva não regride) e o orçamento de 50 ms do guard se mantém.
- [oráculo: `claude plugin validate ./adapters/claude-code`] sai 0 e lista só os eventos do escopo (o `validate` não
  executa o mod; é a checagem de forma, **reportada** no relatório; se `claude` não estiver instalado no ambiente
  do executor, vira "não verificado" explícito, nunca omitido).
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [humano] o Diretor lê a **tabela antes/depois** (abaixo) e decide se o mod sai do piloto.

### Teste adversarial: o mod nunca libera o que o núcleo nega

O teste roda o **mod real** contra um **arnês falso** do contrato `($, e, next)` (sem Claude Code, sem modelo, sem
rede) e um **núcleo simulado** controlável. Propriedade verificada, para cada caso: **resultado do mod ∈ {`deny`,
passar adiante}; jamais `allow`**, e **severidade(mod) ≥ severidade(núcleo)**:
1. núcleo nega → mod nega; 2. núcleo permite → mod passa adiante (**não** `allow`); 3. núcleo devolve `ask`/vazio/
JSON inválido/exit ≠ 0 → passa adiante; 4. núcleo estoura o timeout, ausente, sem permissão de execução → passa
adiante; 5. `e` malformado (sem `command`, comando gigante, bytes inválidos, aspas/`$()`/crases aninhados, quebra
de linha, unicode) → passa adiante, **nunca** exceção que vire `allow`; 6. handlers encadeados: `next(e)` devolve
`allow` de outro mod e o mod, ao ver o veredito do núcleo `deny`, **continua negando**; 7. fuzz: N (≥ 200)
comandos gerados (formas da tabela, com variações de espaço, `;`, `&&`, `|`, subshell, `bash -c`, `eval`,
variável montando o caminho) — para **cada um**, `veredito_mod` e `veredito_cli` coincidem na negação.
**Limites declarados** (como a 047): o que o núcleo não vê (script gravado fora e executado depois, `eval`,
caminho por variável) o mod também não vê; o teste os lista, não os finge cobertos.

## Medição antes e depois (painel da 063)

Pelo painel da 063 (`tools/baseline.sh`, população e janela iguais nos dois lados, fonte ausente = FALHA nomeada):
1. **Permissões por turno** (métrica 4, da Ponte) e 2. **turnos encerrados sem relato** (retrabalho), **antes** (o
snapshot "antes" da 063) e **depois** do mod instalado. O "depois" é a janela dos **próximos 10 turnos de ordem**
sob o mod, registrada com a data de instalação. **Só inteiros**, sem estimar; a decisão é do Diretor com a tabela.
Se o painel der FALHA numa fonte, o relatório diz qual e a medida fica FALHA, **não** "sem mudança".

## Ask-First

- **Contrato de eventos:** a API dos mods "pode mudar entre versões; prevalecem os tipos gerados pela instalação
  local". Gere os tipos da versão instalada e cole o nome exato dos eventos usados; se `tool.check` ou o evento de
  Stop **não existirem** na versão instalada, PARE e relate.
- **Orçamento do guard (50 ms):** se o hook passar a delegar ao CLI e estourar 50 ms ou >1 fork a mais no caminho
  comum, PARE e reporte a medição; o fallback é lib única `source`-ada pelos dois (uma implementação, dois
  chamadores), nunca duas cópias.
- **Fronteira do projeto:** `CLAUDE.md` diz "hooks/ = bash puro, nunca invoca Bun, nunca importa src/". O mod é TS
  **fora** de `hooks/` e **não** importa `src/`. Isso é **nova superfície**: PARE se algum passo exigir mudar essa
  regra; a emenda de `CLAUDE.md`/ARCHITECTURE (ADR) e EPICS E24 é do **Diretor**, e a ordem a **propõe** no texto
  da emenda, não a aplica.
- Se a trava de escrita por shell barrar um fluxo **legítimo** medido (suíte, comando de turno, `maestro` interno),
  PARE e reporte os casos antes de afrouxar — o afrouxamento é decisão do Diretor.
- **Toca `lib/`, `bin/`, `hooks/` (autoprotegidos)** (o núcleo novo e, se preciso, o hook de reserva): a entrega é
  **UM patch** em `docs/patches/065-*.patch`, feito em clone sandbox FORA do repo, testado antes e depois, aplicado
  pelo Capitão com um `git apply`. `adapters/`, `tests/` e `docs/` vão direto no branch.
- Instalar o mod no ambiente do Capitão (`/plugin install`, `/reload-plugins`) **não** é desta ordem: é do Capitão,
  depois do patch aplicado; a ordem entrega o pacote e o passo a passo.

## Como sai

`adapters/claude-code/` (o mod), os testes e as emendas de docs direto no branch; o **núcleo** (`lib/`, `bin/`) e o
hook de reserva (`hooks/`, se tocado) em **UM patch protegido**. Emendas no mesmo changeset: API_SPEC (o comando de
veredito do núcleo e o contrato adaptador↔núcleo), ARCHITECTURE (ADR: núcleo + adaptadores, o mod como adaptador de
um provedor), ENGINEERING_SPEC (limites declarados da trava de escrita), a **proposta** de emenda do EPICS E24 e do
CLAUDE.md (para o Diretor aplicar) e o CHANGELOG (Added).

## Prova exigida

- Vermelho antes e verde depois dos quatro testes novos, saídas coladas; a tabela caso × adaptador (hook e mod).
- O adversarial verde **e** a lista dos limites declarados (o que o núcleo não vê).
- O pacote do mod com `claude plugin validate` reportado; o passo a passo de instalação local para o Capitão.
- A **linha de base "antes"** de permissões por turno e turnos sem relato, do painel da 063, colada; o "depois"
  fica para o piloto rodar (próximos 10 turnos).
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-65` no tip com o patch aplicado e
  `maestro order --status 65` VÁLIDA.

## Turno

- fatia: o núcleo da trava de escrita (comando de veredito, regra e controles negativos) com o teste vermelho antes, e o contrato adaptador↔núcleo escrito
- fim: `bash tests/cli/test-order-065-nucleo-guarda.sh` sai 1 antes (colado) e 0 depois, no sandbox, sem Claude Code; `bash tests/run-all.sh` completa no sandbox sai 0; patch protegido do núcleo pronto e `git apply --check` ok
- teto: 4
- fora: o mod em si, o fim de turno no mod e a medição (turnos seguintes); instalar o mod no ambiente do Capitão; mudar `hooks/` além do necessário à fonte única; rede; aplicar o patch e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Escrita só com Edit ou Write, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou
> redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e medir.
> Patch gerado por `git diff` do sandbox para `docs/patches/` é a única saída por redirecionamento admitida.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera **por
> laço** até a linha `rc=` no log; só depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/065-piloto-de-mod-do-claude-code-ada`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-65 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), linha 108 (E24, núcleo + adaptadores), com a decisão do Capitão de 04/10 como autorização — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 065` (você não fecha a própria ordem).
