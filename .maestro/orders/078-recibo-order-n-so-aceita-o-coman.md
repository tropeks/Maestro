<!-- maestro-order v1
id: 078
ts: 2026-10-10T10:42:46-03:00
epoch: 1791639766
head: 1297ce0eb4c7ba8803d6f280636f4183d31e2108
branch: order/078-recibo-order-n-so-aceita-o-coman
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 078 — recibo order-N so aceita o comando do fim da ordem, e rotulos de area so o comando do .maestro.yaml: recusa antes de executar

## Por quê

**Fase S0 de segurança, ordem do Capitão de 10/10.** O `maestro evidence --record` executa **qualquer comando** depois do `--`
(`lib/cmd-evidence.sh`, `_ev_cmd_record`: monta `cmd_str="$*"` e chama `_ev_cmd_run`). E `Bash(maestro *)` está na allowlist do
gerente. Resultado, medido: **um run gravou recibo de um script em `/tmp` sem passar pelo Diretor.** O recibo é a prova que o aceite
lê; quem escolhe o comando escolhe o que "passou".

**O que o código faz hoje, e por que não basta:**

1. Para o rótulo `order-N` **não existe declaração nenhuma**: `_ev_cmd_match` devolve `cmd_match=free` e o comando roda e grava.
2. Para os rótulos de área (`suite`, `tenant-isolation`, `billing`, `frontend`) há declaração em `.maestro.yaml`
   (`commands.<rótulo>`), mas comando diferente **roda do mesmo jeito** e só ganha `cmd_match=no` e um aviso
   ("este recibo NÃO conta como verificação"). O dano já foi feito: o comando arbitrário **executou**, com os poderes do gerente.

O conserto é **recusar antes de executar**, não marcar depois.

**Cabe no congelamento da v59:** é correção de **segurança e integridade**, que a lista do item 3 admite antes do gate. Não é camada
nova nem muda o formato do recibo.

## O que entrega

### 1. Rótulo `order-N`: só o comando do campo `fim` da ordem N

- `maestro evidence --record --label order-N -- <comando>` lê o bloco `## Turno` da **ordem N** e só executa se `<comando>` for
  igual a um dos **comandos declarados no `fim:`**.
- **Onde está o comando no `fim:`:** os trechos **entre crases** (`` `…` ``) do valor do `fim:`. O texto fora das crases é prosa e
  não declara nada. O `fim:` de uma ordem fica assim: `` `bash tests/cli/test-x.sh` sai 1 antes e 0 depois; `bash tests/run-all.sh` sai 0 ``
  declara **dois** comandos.
- **Comparação literal depois de normalizar espaços:** a sequência de espaços/tabs vira um espaço, sem espaço nas pontas, e nada
  mais (sem expandir variável, sem tirar aspas, sem caminho relativo virar absoluto, sem tratar `;`, `&&` ou `|` como mais de um
  comando: `bash tests/run-all.sh; bash /tmp/x.sh` **não** é igual a `bash tests/run-all.sh`). A comparação é por **palavras**: cada
  argumento do comando tem de ser igual à palavra correspondente do declarado; **argumento com espaço dentro é recusado**.
- **Número da ordem:** `order-101` e `order-0101` valem a mesma ordem 101 (`10#`). Ordem que **não existe** neste projeto, ou
  `order-N` sem bloco `## Turno`, ou com `fim:` **sem crases**, é **recusada** com a mensagem dizendo o que falta (fecha para
  negado, nunca para livre).
- **Recusa:** sai com código de **validação** (não 0, não o do comando), **não executa o comando**, **não grava recibo** nem
  toca o arquivo de recibo existente, e a mensagem diz: o rótulo, o comando recebido, os comandos declarados no `fim:` da
  ordem N, e como declarar (editar o `fim:`, que é decisão do Diretor).
- **Sem atalho para o agente:** nem flag (`--force`), nem variável de ambiente (`MAESTRO_OFF=1` incluída), nem
  `MAESTRO_HOME` diferente liga a recusa para "livre". Quem precisa de outro comando muda o `fim:` da ordem, e isso é do Diretor.

### 2. Rótulos de área: só o comando declarado no `.maestro.yaml`

- `suite`, `tenant-isolation`, `billing` e `frontend` (os rótulos de `commands.<rótulo>` do `.maestro.yaml` do projeto, mais o
  `suite-N` da ordem 048, que segue o `commands.suite`) só **executam** o comando igual ao declarado, pela **mesma comparação** do
  item 1. Diferente: **recusa antes de executar**, com a mesma mensagem (rótulo, comando recebido, comando declarado).
- A leitura continua pelo verificador único (`maestro_proof_verdict`, ordem 060): `evidence --check`, `order --status` e
  `order --accept` **não ganham critério próprio** e nada muda no veredito de recibo já gravado.
- **Rótulo de área sem declaração no `.maestro.yaml`:** recusa (ver Ask-First 3).
- **Rótulo livre** (nem `order-N`, nem área, nem `suite-N`): comportamento de hoje, **intacto**. Nenhum gate lê esse recibo.

### 3. De onde vem o `fim:` que vale (a fonte da verdade)

O arquivo da ordem fica **dentro do repo, onde o run escreve**. Se o `fim:` valesse como está na árvore, o run editaria o `fim:`
para o seu script e gravaria o recibo. Por isso:

- o `fim:` que vale é o do **arquivo commitado** da ordem; edição **não commitada** no `fim:` (diferença entre a árvore de trabalho
  e o commit) torna o recibo **recusado**, com a mensagem dizendo isso;
- **o `fim:` mudar em commit depois do despacho** vale **só com confirmação do Diretor, registrada** (Ask-First 1, opção (a)
  decidida): o Diretor reescreve o `fim:` entre turnos de propósito (a 077 faz isso), e o run também poderia commitar a mudança;
  a confirmação é o que os distingue.

### 4. O que isto não resolve (declarado)

- **O comando declarado roda o que o repo contém.** Se o run edita `tests/run-all.sh` e depois grava `order-N` com
  `bash tests/run-all.sh`, o recibo é do script editado. Quem fecha isso é a revisão e o merge do Capitão, não o recibo.
- **Gravar o arquivo do recibo direto**, fora do `evidence --record` (o arquivo mora em `~/.maestro/`): **medir** se o gerente
  consegue (Ask-First 4) e **relatar**; fechar é outra ordem.
- **RESIDUAL REGISTRADO (Spock, 10/10; medido no turno 1):** o gerente **consegue** gravar em `~/.maestro/` com a ferramenta Write.
  Logo **o ledger em `~/.maestro/` (recibo, `order-state`, `fim_commit`) é forjável pelo run enquanto ele roda com o usuário do
  Capitão.** A recusa desta ordem fecha o comando arbitrário em `evidence --record`, **não** a forja do ledger. Fecha com o
  **sandbox da ordem 107 do ponte-daemon, que não monta `~/.maestro`.** Até lá, o `fim_commit` só protege contra o run que mexe
  no repo, não contra o que escreve no ledger.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-evidence-comando-declarado.sh`] **o caso real, vermelho antes:** em projeto de teste com a ordem
  101 e `fim:` declarando `` `bash tests/run-all.sh` ``, `maestro evidence --record --label order-101 -- bash /tmp/script.sh`
  **tem de falhar** (código não 0): o script **não executou** (arquivo-marcador que ele criaria não existe), **nenhum recibo
  foi gravado** e a mensagem cita o comando recusado e o declarado. **Saída vermelha colada** (hoje grava e sai 0).
- [oráculo: o mesmo teste] **o caso feliz continua verde:** `--label order-101 -- bash tests/run-all.sh` executa e grava; o
  espaço duplicado e o tab entre palavras (`bash  tests/run-all.sh`) também.
- [oráculo: `bash tests/cli/test-evidence-comando-declarado-adversarial.sh`] **adversarial, todos recusados sem executar:**
  (a) `bash tests/run-all.sh; bash /tmp/x.sh`, `bash tests/run-all.sh && …`, `bash tests/run-all.sh | …`; (b) argumento com
  espaço dentro (`bash "tests/run-all.sh x"`); (c) `order-0101` e `order-101` valem a mesma ordem, `order-999` inexistente é
  recusada; (d) ordem com `fim:` sem crases e ordem sem bloco `## Turno` são recusadas; (e) `MAESTRO_OFF=1` e `MAESTRO_HOME`
  trocado **não** liberam; (f) o run edita o `fim:` no arquivo da ordem **sem commitar** e grava: recusado.
- [oráculo: o mesmo teste, área] `--label suite -- bash /tmp/script.sh` com `commands.suite: bash tests/run-all.sh` no
  `.maestro.yaml` falha sem executar; o mesmo para `tenant-isolation`, `billing`, `frontend` e `suite-N`; o comando declarado
  executa; rótulo de área **sem** declaração é recusado; **rótulo livre** (`--label qualquer -- echo ok`) segue como hoje.
- [oráculo: `bash tests/cli/test-evidence.sh`, `bash tests/cli/test-order-060-verificador-unico.sh` e
  `bash tests/cli/test-order-044-recibo-empilhado.sh`] seguem verdes: a leitura e o veredito não mudaram. Os testes **existentes**
  que gravam recibo com comando qualquer em rótulo `order-N` ou de área são **ajustados** para declarar o comando; a lista deles
  vai no relato.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo; `shellcheck` limpo.
- [humano] o Capitão lê o patch (toca `lib/` e `bin/`) e faz o merge.

## Ask-First

1. **Fonte da verdade do `fim:` (item 3) — DECIDIDO pelo Spock em 10/10: opção (a).** Vale o `fim:` do **commit do despacho**;
   mudança posterior no `fim:` **só vale com confirmação do Diretor, registrada**. A proposta do turno 1
   (`docs/designs/078-fim-do-despacho-proposta.md`) foi decidida pelo Spock em 10/10:
   - **(i) = opção A:** o campo `fim_commit` no registro `order-state` (`~/.maestro/order-state/<proj>-<NNN>`), **gravado pelo
     CLI**. O `maestro order` não tem `--dispatch`, então o **baseline é o commit da criação da ordem**. O recibo lê o `fim:` com
     `git show <fim_commit>:<arquivo da ordem>`. O commit da criação só existe depois do `chore(order)`: o executor define o
     momento da gravação; se não couber no CLI (nem no `--create`, nem em outro subcomando do `maestro order`), **PARE**.
   - **(ii) = opção C:** `fim:` mudado depois do baseline → recibo `order-N` **recusado**, sempre. O Diretor **re-despacha para
     regravar o baseline** (novo `fim_commit`). Não há confirmação mecânica nesta ordem; a confirmação assinada fica para a
     **ordem de identidade** (`_order_accept_proof_verify` ainda é coto).
   - Sem `fim_commit` para a ordem: recibo **recusado** (fecha para negado). Ordens já criadas hoje não têm o campo: o executor
     lista o efeito e **não carrega** o campo em nenhuma. O comando que regrava o baseline é parte do patch; se precisar do
     ponte-daemon, PARE.
2. **Ordens abertas com `fim:` em prosa, sem crases — DECIDIDO:** o executor **só lista** quais das ordens não terminais do
   projeto ficam assim; **não edita nenhuma**. O Spock acerta o `fim:` de cada uma quando ela voltar ao despacho. **A ordem 028
   fica fora da lista: registre que não foi lida.**
3. **Rótulo de área sem declaração no `.maestro.yaml`:** a proposta é **recusar**. Se algum projeto cadastrado depender de gravar
   `suite` sem declarar, PARE e relate qual.
4. **Medir, não consertar — DECIDIDO:** o gerente consegue gravar o arquivo do recibo fora do `evidence --record`? Cole a medição no
   relato. **Só mede e relata;** não fecha o vetor nesta ordem.
5. **Toca `lib/` e `bin/` (autoprotegidos):** a entrega é **UM patch** em `docs/patches/NNN-*.patch`, feito em clone sandbox FORA
   do repo, testado antes e depois, aplicado pelo Capitão com um `git apply`; `git apply --check` no worktree. `tests/` e `docs/`
   direto no branch. **O merge é do Capitão.**
6. Contrato do `.maestro.yaml` além do que já existe, formato do recibo, ou qualquer mudança no veredito de recibo gravado: PARE
   (API_SPEC, DATA_MODEL).
7. Logs: **só metadados**; nunca caminho completo de arquivo, nunca o texto do comando recusado inteiro no log (a mensagem na
   tela pode citá-lo; o log só grava o rótulo e o motivo).

## Como sai

Testes e emendas direto no branch; a recusa em **UM patch protegido**. Emendas no mesmo changeset: API_SPEC (o contrato de
`evidence --record`: recusa antes de executar, código de saída, mensagem), ENGINEERING_SPEC (o que a recusa garante e o que não:
item 4 acima), CHANGELOG (Security). Papercut: "recibo de comando arbitrário via `Bash(maestro *)`".

## Prova exigida

- O teste do caso real **vermelho antes e verde depois**, saídas coladas; o adversarial verde.
- A lista dos testes existentes ajustados e a lista das ordens abertas com `fim:` sem crases (Ask-First 2).
- A medição do Ask-First 4.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-N` no tip com o patch aplicado e `maestro order --status N` VÁLIDA.

## Turno

ESTADO (Spock, 10/10): turno 1 FEITO (tip 3a2550f: testes vermelhos, medição, proposta de (i) e (ii)). Decisões do Diretor: (1) opção (a), vale o `fim:` do commit-base e mudança posterior só com confirmação registrada; (2) ordens abertas com `fim:` em prosa: o executor lista, não edita, o Spock acerta o `fim:` de cada uma quando voltar ao despacho; a 028 fica fora da lista, registrar que não foi lida; (3) a medição de gravação direta em `~/.maestro/` só mede e relata; (i) opção A: `fim_commit` no registro `order-state`, gravado pelo CLI, baseline = commit da criação da ordem (o `maestro order` não tem `--dispatch`); (ii) opção C: `fim:` mudou depois do baseline, recibo recusado, o Diretor re-despacha para regravar o baseline, confirmação assinada fica para a ordem de identidade. RESIDUAL: o ledger em `~/.maestro` é forjável pelo run (Write) enquanto ele roda com o usuário do Capitão; fecha com o sandbox da ordem 107 do ponte-daemon, que não monta `~/.maestro`. Turno 2 INCOMPLETO (14:15): o run terminou esperando 4 agentes, sem patch, sem suíte completa e sem recibo; o branch está em ed267ee (testes e emendas). O trabalho de código está no clone sandbox `/tmp/claude-1000/-home-rcosta00-dev-worktrees-maestro-s0/sandbox`, com 24 arquivos alterados e NÃO commitados. TURNO 3, o último do teto 3, só para FECHAR: parta desse sandbox, não recomece.

- fatia: (1) conferir o que os agentes deixaram no sandbox (diff contra a base) e terminar os testes antigos que gravam recibo `order-N` ou de área com comando qualquer; (2) fechar duas lacunas: (a) o `commands.<rótulo>` da área é lido do `.maestro.yaml` do `fim_commit` e não da árvore de trabalho (o run edita a árvore); (b) `maestro order --baseline N` grava o `fim_commit` e RECUSA sobrescrever baseline existente, e `evidence --record --label order-N` RECUSA ordem sem baseline (fecha para negado); quem grava o baseline no despacho é o Spock; (3) `bash tests/run-all.sh` completo no sandbox com o rc, patch em `docs/patches/` com `git apply --check` ok no worktree, `shellcheck` limpo, recibo `order-78`; (4) relatar como residuais: `order-N-dono8` recusado (o rótulo com sufixo) e o ledger em `~/.maestro` forjável pelo run até a ordem 107 do ponte-daemon. PROIBIDO terminar o turno esperando agente: se lançar subagente, espere em laço até o fim (Monitor) antes de relatar. Se faltar tempo, relate o que fechou e o que não, nunca "aguardando".
- fim: `bash tests/cli/test-evidence-comando-declarado.sh` e `bash tests/cli/test-evidence-comando-declarado-adversarial.sh` saem 1 antes (colado) e 0 depois, no sandbox, com `bash tests/cli/test-evidence.sh` verde; patch protegido pronto e `git apply --check` ok; `bash tests/run-all.sh` completa no sandbox sai 0
- teto: 3
- fora: gravar o baseline de qualquer ordem (é do Spock, no despacho), confirmação assinada do Diretor, carregar `fim_commit` em ordem existente, mexer no ponte-daemon, editar o `fim:` de qualquer ordem, fechar o vetor do ledger em `~/.maestro` (é da ordem 107 do ponte-daemon), mudar o formato do recibo ou o veredito, aplicar o patch, mergear e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54,
> com o sha do tip). Terminar a resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível,
> **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou
> redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e medir.
> Patch gerado por `git diff` do sandbox para `docs/patches/` é a única saída por redirecionamento admitida.

> **Comando simples:** um comando por chamada de Bash; caminho absoluto em vez de cd e &&; sem pipe para cortar
> saída (| tail, | head), a ferramenta já corta; 2>&1 é permitido (junta saídas, não grava arquivo); a suíte roda
> como uma chamada só, maestro evidence --record --label order-N -- <suíte>, em segundo plano
> (run_in_background da ferramenta Bash) e a espera é por Monitor; o recibo já grava o código de saída.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. A suíte roda como uma chamada só
> (`maestro evidence --record --label order-N -- <suíte>`) em segundo plano, pelo `run_in_background` da
> ferramenta Bash, e a espera é por **Monitor**; o recibo já grava o código de saída. Só depois se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/078-recibo-order-n-so-aceita-o-coman`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-78 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 078` (você não fecha a própria ordem).
