<!-- maestro-order v1
id: 079
ts: 2026-10-10T18:48:05-03:00
epoch: 1791668885
head: e279566a9806cd08003b8d77cdbbb46084e40fcf
branch: order/079-recibo-order-n-aceita-o-fim-comp
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 079 — recibo order-N aceita o fim composto como bash -c com o texto exato

## Por quê

**Pedido do Capitão, 10/10.** A ordem 078 está aceita, mas fora da `main`, porque os `fim:` das ordens do NetForge declaram comandos
**compostos com `&&`** (por exemplo `` `cd web && npm test` ``). A 078 compara **palavra por palavra** (`_evd_words_equal`, em
`lib/core-evidence-declared.sh`): o recebido `bash -c "cd web && npm test"` nunca é igual a `cd web && npm test`, e o recibo `order-N`
dessas ordens é **recusado sempre**. O conserto não pode reabrir o furo que a 078 fechou: aceitar `&&`, `;` ou `|` no recebido
solto é o caso real (`bash tests/run-all.sh; bash /tmp/x.sh`).

**Parte do branch da 078** (`order/078-recibo-order-n-so-aceita-o-coman`), que já tem o patch aplicado em `lib/`. O patch da
078 **ainda não está na `main`**: esta ordem fica **empilhada** sobre ela. O merge desta só vem **depois** do merge da 078; o
patch desta (`docs/patches/`) é feito contra o `lib/` que a 078 deixou.

**Cabe no S0 de segurança:** é afrouxar uma recusa de forma **mínima e fechada**, não uma nova capacidade. Merge do Capitão (`lib/`).

## O que entrega

Em `_evd_gate_order`, **além** da comparação por palavras (que fica **exatamente como está**), o comando recebido é aceito quando é
**exatamente** estas três palavras:

1. `bash` (a palavra literal, sem caminho: `/bin/bash`, `env bash` e `sh` **não valem**);
2. `-c` (a flag literal: `-lc`, `-ec`, `-xc` e qualquer outra **não valem**);
3. **um único argumento** que, depois de normalizar espaços, é **igual byte a byte** a um dos comandos declarados entre crases
   no `fim:` do **commit-base** (o mesmo `decl` que o laço de palavras já usa).

- **Normalizar espaços** é a mesma normalização da 078 (sequência de espaços e tabs vira um espaço, sem espaço nas pontas) aplicada
  ao argumento e ao declarado. **Nada mais:** nada de expandir variável, tirar aspas, cortar `;`/`&&`, resolver caminho. Quebra de
  linha dentro do argumento **não** é espaço normalizável: o argumento com `\n` é recusado.
- **Mais nada:** sem `sh`, sem `bash -c` com outras flags, sem prefixo de ambiente (`FOO=1 bash -c …`, `env … bash -c …`), sem
  segundo argumento depois do texto (o `$0` do `bash -c`), sem `bash -c` onde o texto é só **parte** de um declarado.
- **O resto da 078 não muda:** o `fim_commit`, a leitura do `fim:` do commit-base, a recusa de `fim:` mudado ou editado sem
  commit, a recusa sem baseline, a recusa de `fim:` sem crases, os rótulos de área (`_evd_gate_area`, que **não** ganham o
  `bash -c`), o `maestro order --baseline` e o `_evd_yaml_gate`. A mensagem de recusa continua a mesma e passa a lembrar, nos
  declarados, que o composto vale como `bash -c '<texto>'`.
- **Garantia, dita na emenda:** o composto aceito executa **o texto que o Diretor escreveu entre crases no commit-base**, nada
  além; o que o texto roda (os scripts que ele chama) é o que o repo contém, o mesmo limite da 078.

## Critérios de aceite (com oráculo)

Todos os testes **vermelhos antes** (saída colada no sandbox, contra o `lib/` da 078) e **verdes depois**. Reuse o fixture
`tests/lib/fixture-comando-declarado.sh` da 078.

- [oráculo: `bash tests/cli/test-evidence-fim-composto.sh`] projeto de teste com a ordem 101 cujo `fim:` declara
  `` `cd sub && bash ok.sh` `` e baseline gravado: `--label order-101 -- bash -c "cd sub && bash ok.sh"` **executa e grava**
  (arquivo-marcador criado); com espaços duplicados e tab dentro do texto, também. **Vermelho antes** (hoje recusa).
- [oráculo: `bash tests/cli/test-evidence-fim-composto-adversarial.sh`] **todos recusados sem executar e sem gravar recibo**
  (marcador ausente, rc não 0):
  (a) `bash -c` com **texto diferente** do declarado (uma palavra a mais, uma a menos, uma trocada);
  (b) `bash -c "cd sub && bash ok.sh; bash /tmp/x.sh"` e com `&&`, `|` ou `;` **extra**;
  (c) `bash -c` com **variável**: `"cd sub && bash $X"` e `"$CMD"` com `CMD` exportado igual ao declarado (o `$CMD` literal não é o
  declarado);
  (d) `bash -lc`, `bash -ec`, `sh -c`, `/bin/bash -c`, `env bash -c`, `FOO=1 bash -c`;
  (e) `bash -c "<declarado>" extra` (argumento a mais) e `bash -c` sem texto;
  (f) texto com `\n` dentro; texto igual a **prefixo** ou a **parte** do declarado;
  (g) o texto declarado vale **só na ordem dele**: `bash -c` do `fim:` da ordem 101 em `--label order-102` é recusado;
  (h) `fim:` editado sem commit, ou mudado depois do baseline, continua recusando o `bash -c` (a 078 não regride);
  (i) `bash -c "<declarado>"` em **rótulo de área** (`suite`) continua recusado: o `bash -c` é só do `order-N`.
- [oráculo: `bash tests/cli/test-evidence-comando-declarado.sh`, `bash tests/cli/test-evidence-comando-declarado-adversarial.sh`
  e `bash tests/cli/test-evidence.sh`] seguem verdes.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo; `shellcheck` limpo.
- [humano] o Capitão lê o patch (toca `lib/`) e faz o merge, depois do merge da 078.

## Ask-First

1. **Se o `fim:` composto de alguma ordem do NetForge tiver crase dentro do comando** (crase não cabe entre crases), PARE e
   relate qual: fora desta ordem.
2. **Não mude** `_evd_words_equal`, o leitor do veredito (`maestro_proof_verdict`), o formato do recibo nem o `_evd_gate_area`.
   Se o conserto mínimo exigir isso, PARE.
3. **Toca `lib/` (autoprotegido):** a entrega é **UM patch** em `docs/patches/079-*.patch`, feito em clone de trabalho a partir do
   branch da 078 **na pasta temporária do run**, testado antes e depois; o patch final é o que **fica na worktree**, em
   `docs/patches/`, e `git apply --check` roda na worktree. `tests/` e `docs/` direto no branch.
4. **Sandbox (a partir de agora o projeto Maestro roda dentro do bwrap):** `HOME` vazio, `/tmp` efêmero, **sem `~/.maestro`** e
   sem escrita fora da worktree e da pasta temporária do run. Consequências: o clone de trabalho vive na pasta temporária do run
   (some quando o run acaba; só o que está na worktree sobrevive); `maestro evidence`, `maestro order --status` e qualquer
   coisa que leia o ledger **não funcionam lá dentro**. Se algo de que o turno precisa **não existir dentro do sandbox**, o
   executor **relata e PARA**, sem contornar (nada de remontar, de apontar `HOME` para outro lugar nem de pedir ao Spock um atalho).
5. Logs: **só metadados**; nunca o texto do comando recusado inteiro no log.

## Como sai

Testes e emendas direto no branch; a mudança de `_evd_gate_order` em **UM patch protegido**. Emendas no mesmo changeset:
API_SPEC (o contrato de `evidence --record`: `bash -c` + um argumento aceito no `order-N`), ENGINEERING_SPEC (o que o composto
garante e o que não) e CHANGELOG (Changed).

## Prova exigida

- Os dois testes novos vermelhos antes e verdes depois, saídas coladas; os três da 078 verdes.
- `git apply --check` do patch no worktree; `shellcheck` limpo.
- **A suíte completa NÃO roda no run.** O run apenas **declara** o comando da suíte no `fim:` (`bash tests/run-all.sh`, entre
  crases). O Spock roda a suíte e grava o recibo `order-79` **fora do run** (um processo destacado do run morre com ele: o
  daemon encerra o grupo). Não lance `setsid`/`nohup`, não deixe processo para depois do relato.

## Turno

- fatia: os dois testes vermelhos (composto aceito, adversarial a–i) colados contra o `lib/` da 078, o ajuste mínimo de `_evd_gate_order` em clone de trabalho na pasta temporária do run, a partir do branch da 078, os testes verdes, as emendas (API_SPEC, ENGINEERING_SPEC, CHANGELOG), o patch final em `docs/patches/` da worktree com `git apply --check` ok e `shellcheck` limpo; a suíte completa NÃO roda no run (o Spock a roda e grava o recibo fora dele); dentro do sandbox bwrap, o que faltar é relatado e o turno para
- fim: `bash tests/cli/test-evidence-fim-composto.sh` e `bash tests/cli/test-evidence-fim-composto-adversarial.sh` saem 1 antes (colado) e 0 depois no sandbox, com `bash tests/cli/test-evidence-comando-declarado.sh`, `bash tests/cli/test-evidence-comando-declarado-adversarial.sh` e `bash tests/cli/test-evidence.sh` verdes; patch protegido na worktree e `git apply --check` ok; o comando da suíte declarado aqui é `bash tests/run-all.sh`, que o run NÃO executa (o Spock roda e grava o recibo fora do run)
- teto: 2
- fora: aceitar `sh`, outras flags do `bash`, prefixo de ambiente ou segundo argumento, o `bash -c` em rótulo de área, mexer em `_evd_words_equal`, no veredito ou no formato do recibo, gravar o baseline de qualquer ordem (é do Spock, no despacho), editar o `fim:` de qualquer ordem, mexer no ponte-daemon, aplicar o patch no repo, mergear (o merge é do Capitão, depois da 078) e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54,
> com o sha do tip). Terminar a resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível,
> **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou
> redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e medir.
> Patch gerado por `git diff` do sandbox para `docs/patches/` é a única saída por redirecionamento admitida.

> **Comando simples:** um comando por chamada de Bash; caminho absoluto em vez de cd e &&; sem pipe para cortar
> saída (| tail, | head), a ferramenta já corta; 2>&1 é permitido (junta saídas, não grava arquivo).

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação nem um subagente: espere em laço até o fim antes de relatar.
> Não lance processo destacado (`setsid`, `nohup`): ele morre com o run. Nenhuma espera fica para depois do relato; a suíte completa
> é rodada pelo Spock fora do run.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/079-recibo-order-n-aceita-o-fim-comp`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-79 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 079` (você não fecha a própria ordem).
accepted_at: 2026-10-10T20:19:22-03:00
accepted_session: desconhecido
accepted_tree: a925286b7d1def9fa518ef3c96c4e613d701f6c5
accepted_intent: 6
