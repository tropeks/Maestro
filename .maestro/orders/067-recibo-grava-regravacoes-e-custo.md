<!-- maestro-order v1
id: 067
ts: 2026-10-05T10:39:49-03:00
epoch: 1791207589
head: 21c71c1dab4c7f27910d714326d76e181b5e60f2
branch: order/067-recibo-grava-regravacoes-e-custo
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 067 — recibo grava regravacoes e custo: o instrumento que destrava as secoes 8 e 9 do gate

## Por quê

**Ordem direta do Capitão, 05/10: a Etapa 0 do plano v2, que a v59 permite antes do gate.** A v59 (spock
`.maestro/INTENT.md`, "Direção 2026-10-04 - enxugar antes de expandir", item 1) mantém as etapas 0 e 1 e
define o gate (item 2) como a comparação da linha de base da ordem 058 com os próximos 10 aceites, **acrescida
de custo por controle, minutos do Capitão e retrabalho**. Sem o gate lido, nada do congelamento destrava.

Hoje o painel **não consegue ler duas dessas parcelas**. `tools/baseline.sh --all` sai **FALHA nas seções 8
(retrabalho, parcela "recibos regravados") e 9 (custo por ordem)**, por conferência no código
(`tools/lib/baseline-novas.sh`, `m8_retrabalho` e `m9_custo`): nenhum recibo do ledger guarda `regravacoes`,
`tokens` nem `custo_centavos`, e as duas funções transformam cada ordem sem o campo em FALHA. A causa está dita
nas próprias mensagens do painel: **o recibo é sobrescrito** (`_ev_write` grava por `tmp+mv`) **e nenhum evento
guarda a regravação**, e **nenhuma telemetria local guarda custo por ordem**.

Esta ordem é o **instrumento**: faz o `maestro evidence --record` gravar o que o painel precisa, e faz o painel
ler o que existe sem fingir o que não existe.

## O que entrega

### 1. `maestro evidence --record` grava no recibo, em campos aditivos no fim (DATA_MODEL §8)

| campo | valor | regra |
|---|---|---|
| `regravacoes` | **inteiro ≥ 0** | **quantas vezes a mesma label foi gravada de novo na mesma ordem.** A 1ª gravação grava `0`. Se o recibo da label já existe, grava `anterior + 1`, onde `anterior` é o `regravacoes` inteiro do recibo velho; recibo velho **sem** o campo conta como uma gravação anterior (grava `1`). A contagem acompanha o ARQUIVO da label (`<chave>-order-<n>`), que já é por ordem. |
| `tokens` | **inteiro** ou `ausente` | soma de `input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens` das mensagens do(s) transcrito(s) da ordem, **quando a fonte existir** (ver 2). |
| `custo_centavos` | **inteiro** ou `ausente` | custo em **centavos inteiros**, arredondado de forma declarada (meio para cima), **só** quando a fonte traz custo; **nunca float** no recibo (CLAUDE.md: "float em qualquer métrica de custo" é proibido). |
| `custo_fonte` | `transcrito` ou `ausente` | de onde veio o custo; `ausente` quando nenhum dos dois campos acima tem fonte. |

**Regra que vale para os quatro, inegociável: sem fonte, o campo grava a palavra `ausente`. Nunca `0`, nunca
estimativa, nunca valor parcial.** Zero é afirmação ("custou nada"); ausente é "não sei". Se só parte das
mensagens do transcrito tem o dado, o campo é `ausente` e o motivo vai para `custo_fonte`/stderr: soma
parcial não entra.

A janela do leitor de recibo é de **20 linhas** (`_ev_field`, `_ev_read_vars`): o recibo tem 15 hoje e ganha 4 →
**19**. Os campos ficam **no fim**, em ordem fixa, e a ordem **prova** que o recibo continua dentro da janela e
que `_ev_read_vars` e `maestro_proof_verdict` leem o recibo novo e o velho sem mudar de veredito.

### 2. A fonte do custo: o transcrito do turno, medida e declarada, não presumida

O que **já conferi** (e o turno **reconfere**, porque é onde a ordem pode quebrar):

- O **transcrito do Claude Code** (`~/.claude/projects/<cwd codificado>/<session_id>.jsonl`) traz `usage` por
  mensagem do assistente (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`,
  `cache_read_input_tokens`) e, em algumas linhas, `costUSD`.
- O `routing.jsonl` **não** traz tokens nem custo na amostra que li (`telemetry/logs/*/routing-current.jsonl`):
  o turno confirma em todos os arquivos que o `maestro` lê e **declara** que o routing não é fonte, ou o
  é — com o campo e o arquivo citados.
- O turno headless de um runner da Ponte guarda `manager_run.claude_session_id` (ponte.db): é a chave para achar
  o transcrito de um turno headless. O turno interativo precisa de outra chave: o turno **mede** o que o
  `maestro evidence --record` tem à mão (variável de ambiente da sessão, `session_id` do decision record) e
  declara.

O turno entrega o **mapa das fontes** (colado): por tipo de turno (headless de runner, interativo), de onde sai
a sessão, qual arquivo tem o `usage`, se o `costUSD` é **por mensagem ou acumulado** (medir em transcrito real,
os dois exemplos que vi diferem em ordem de grandeza), e **o que fica `ausente` por construção**. A leitura do
transcrito é **só leitura**, sem rede, e **nunca grava texto do transcrito** no recibo, no log nem no stdout:
só os inteiros. Transcrito não encontrado, ilegível, ambíguo (duas sessões candidatas) ou sem `usage` → `ausente`,
**sem erro** (o `evidence --record` não pode falhar nem ficar mais lento por causa de custo: degrada para
`ausente`, como manda a filosofia do plugin).

### 3. `tools/baseline.sh` lê os campos e as seções 8 e 9 saem `ok` com N declarado

Mudança em `tools/lib/baseline-novas.sh` (`recibos_json`, `m8_retrabalho`, `m9_custo`) e no cabeçalho de
`tools/baseline.sh`:

- Campo **inteiro** → entra na conta. Campo **`ausente` ou inexistente** (ordens antigas, anteriores a esta
  ordem, e ordens novas sem fonte) → a ordem **fica fora da soma e dentro da contagem de "sem dado"**:
  **não vira zero e não vira FALHA**.
- As seções 8 (parcela `recibos_regravados`) e 9 saem `ok` **declarando N**: `n_com_dado` (ordens que entram na
  conta), `n_sem_dado` (ordens da população sem o campo) e a população total, por lado do corte da v59
  (`antes`/`depois`). Com `n_com_dado = 0` a seção sai **`sem dado`** (exit 0), nunca FALHA nem zero.
- **FALHA continua** onde a fonte falha: ledger ilegível; campo **presente e inválido** (float, texto que não
  seja `ausente`); o painel não adivinha. O exit 3 só vem de FALHA real.
- **A mesma população nos dois lados do corte** (ordem 063) continua valendo: a população é a mesma; o que muda
  é o que cada ordem declara.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-order-067-recibo-regravacoes.sh`] `maestro evidence --record` em MAESTRO_HOME de
  fixture: 1ª gravação grava `regravacoes=0`; 2ª, `1`; 3ª, `2`; recibo velho sem o campo → `1`; labels
  diferentes não se somam; o recibo cabe nas 20 linhas e `_ev_read_vars`/`maestro_proof_verdict` dão o mesmo
  veredito no recibo velho e no novo. **Vermelho antes** (o campo não existe), colado.
- [oráculo: `bash tests/cli/test-order-067-recibo-custo.sh`] transcrito de **fixture** (jsonl sintético, nunca
  real): com `usage` completo grava `tokens` inteiro, com `costUSD` completo grava `custo_centavos` inteiro
  (arredondamento declarado, caso de meio centavo coberto) e `custo_fonte=transcrito`; sem transcrito, transcrito
  ilegível, duas sessões candidatas, `usage` parcial e `costUSD` parcial gravam **`ausente`**, **nunca `0`**,
  e o `--record` sai com o exit do comando provado (custo não altera o exit nem imprime texto do transcrito).
  **Vermelho antes**, colado.
- [oráculo: `bash tests/cli/test-order-067-baseline-secoes-8-9.sh`] ledger de fixture com ordens novas (campos
  inteiros), ordens antigas (sem campo) e uma com `ausente`: seções 8 e 9 `ok`, `n_com_dado`/`n_sem_dado`
  corretos por lado, soma só das ordens com dado, **nenhum zero no lugar de ausência**; população só de ordens
  antigas → `sem dado`, exit 0; campo float ou texto inválido → FALHA nomeada, exit 3; ledger ilegível → FALHA.
  **Vermelho antes** (hoje a seção sai FALHA), colado.
- [oráculo: `bash tests/cli/test-baseline-novas-medidas.sh`, `bash tests/cli/test-baseline-sem-fonte.sh`]
  **ajustados e verdes**: as asserções que hoje exigem FALHA para "campo ausente" (linhas 131 a 139 do
  `test-baseline-novas-medidas.sh`) passam a exigir `sem dado`/N declarado; as de float seguem FALHA. A mudança
  de expectativa vai **declarada** no relato, com o antes e o depois.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [oráculo: `bash tools/baseline.sh --all --format json`, no ledger real, **só leitura**] as seções 8 e 9 **não
  saem FALHA por campo ausente**: saem `ok` com N declarado ou `sem dado`, e o exit 3 só aparece se houver FALHA
  real, que o turno cita. O turno **cola a saída** (o `--all` chama o lab-ci por ssh e pode passar de 2
  minutos: roda por laço em segundo plano com timeout, ver Contrato).
- [humano] o Diretor lê o **mapa das fontes** (2) e o **N declarado** do painel e aprova a definição de `tokens`
  e do arredondamento.

## Ask-First

- **Toca `lib/` (autoprotegido):** `lib/core-evidence.sh` (dono do formato, `_ev_write`) e `lib/cmd-evidence.sh`
  (`_ev_cmd_record`). A entrega desse código é **UM patch** em `docs/patches/067-*.patch`, feito em **clone
  sandbox FORA do repo**, com os testes novos vermelhos antes e verdes depois, aplicado pelo Capitão com um
  `git apply`. `tools/`, `tests/` e `docs/` vão direto no branch. Se alguma parte precisar de `bin/`, `hooks/`
  ou `src/`, PARE e relate: o mesmo patch pode cobrir, mas é decisão do Capitão.
- **Não há fonte de custo para algum tipo de turno:** é resultado válido. O campo sai `ausente` e o mapa diz
  por quê. **Não invente fonte, não use telemetria de rede, não estime.** Se NENHUM tipo de turno tiver fonte
  legível, PARE e relate: a decisão de onde passar a guardar custo é do Capitão.
- **Ler o ponte.db** para achar `claude_session_id`: só `sqlite3 -readonly`, como o painel já faz. Se o
  `evidence --record` não puder ler a Ponte sem criar acoplamento novo entre o Maestro e o banco, PARE e relate
  a alternativa (ex.: o runner gravar a sessão em arquivo): é outro repo, outra ordem.
- **O custo do `--record` não pode subir o tempo do comando:** se a leitura do transcrito passar de um piso
  declarado no turno (medido, não chutado), pare e relate; vale degradar para `ausente`.
- **Não regrave o ledger real.** Nenhum recibo existente muda; ordens antigas **continuam sem dado**, e é
  exatamente o que o painel deve mostrar. Nada de backfill, nem "para o gate ficar bonito".
- **Float** em qualquer campo de custo: proibido (CLAUDE.md). Conversão para centavos inteiros é a única forma.
- **Logs: só metadados** (nunca texto do transcrito, nunca caminho completo de arquivo, nunca prompt).
- **A Ponte, o ponte-daemon e o `~/.ponte` real:** só leitura, e só pelo painel. Nada de tocá-los.

## Como sai

`tests/cli/test-order-067-*.sh`, `tools/baseline.sh`, `tools/lib/baseline-novas.sh`, o ajuste dos dois testes do
painel e as emendas de docs direto no branch; o código de `lib/` em **UM patch protegido**. Emendas no mesmo
changeset: **DATA_MODEL §8** (os quatro campos, ordem no fim do recibo, regra "ausente, nunca zero", a janela de
20 linhas), **API_SPEC** (`maestro evidence --record` e o que ele grava; leitura do painel) e o **CHANGELOG**
(Added). Os cabeçalhos de `tools/baseline.sh` e `tools/lib/baseline-novas.sh` perdem a "proposta" e passam a
descrever a fonte real. Papercut: nenhum previsto.

## Prova exigida

- Os três testes novos **vermelhos antes e verdes depois**, saídas coladas; os dois testes do painel ajustados,
  com o antes e o depois das asserções.
- O **mapa das fontes** de custo (2), colado, com o que é `ausente` por construção.
- A saída de `tools/baseline.sh --all --format json` no ledger real, só leitura, antes e depois do patch,
  mostrando as seções 8 e 9 de FALHA para `ok com N declarado` (ou `sem dado`).
- O recibo de uma gravação real no sandbox, mostrando os quatro campos e que cabe nas 20 linhas.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-67` no tip com o patch aplicado e
  `maestro order --status 67` VÁLIDA; `git apply --check` do patch ok.

## Turno

- fatia: o `regravacoes` e o `custo` no recibo (patch protegido, em sandbox), a leitura nas seções 8 e 9 de `tools/baseline.sh` e os três testes novos, vermelhos antes
- fim: `test-order-067-recibo-regravacoes`, `test-order-067-recibo-custo` e `test-order-067-baseline-secoes-8-9` saem 1 antes (colado) e 0 depois, no sandbox; os dois testes do painel ajustados saem 0; o mapa das fontes e a saída do painel colados; `bash tests/run-all.sh` sai 0; patch protegido pronto e `git apply --check` ok
- teto: 3
- fora: tocar o ledger real ou regravar recibo existente, backfill de ordens antigas, estimar custo, usar rede, tocar o ponte-daemon, a Ponte ou o `~/.ponte`, gravar texto de transcrito em recibo, log ou stdout, mudar `hooks/` ou `src/`, aplicar o patch, tocar vendor/ e adotar o custo em qualquer gate novo
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54,
> com o sha do tip). Terminar a resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível,
> **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou
> redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e medir.
> Patch gerado por `git diff` do sandbox para `docs/patches/` é a única saída por redirecionamento admitida.

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run,
> `/tmp/claude-<uid>/<cwd codificado>`, nunca `/tmp` solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano (e o `baseline.sh
> --all`, que passa de 2 minutos por causa do ssh) se espera **por laço** até a linha `rc=` no log; só depois
> se relata.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

## Contrato de execução
- Trabalhe APENAS no branch `order/067-recibo-grava-regravacoes-e-custo`; NUNCA no main/master.
- Direção: a v59 (spock `.maestro/INTENT.md`, "Direção 2026-10-04 - enxugar antes de expandir", item 1: etapas 0 e 1 seguem; item 2: o gate inclui custo e retrabalho) **autoriza** esta ordem; a ordem direta do Capitão de 05/10 a nomeia. O INTENT v6 do Maestro cita o núcleo e os adaptadores (E24) e o ledger de evidência (E13).
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-67 -- <suíte>` no tip do branch, com o patch aplicado.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 067` (você não fecha a própria ordem).
accepted_at: 2026-10-05T13:56:45-03:00
accepted_session: desconhecido
accepted_tree: 7dad9fffb835f28f4bdc43f9e0360641cefcfb3e
accepted_intent: 6
