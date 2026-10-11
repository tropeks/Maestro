<!-- maestro-order v1
id: 080
ts: 2026-10-10T23:31:01-03:00
epoch: 1791685861
head: 67b1c0733eb0b38849b0c3be3d9fd7aad25474a5
branch: order/080-recibo-de-suite-so-com-a-maquina
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 080 — recibo de suite so com a maquina leve e um por vez

## Por quê

**Decisão do Capitão, 10/10, depois do Forge.** **Quatro recibos queimados em 10/10** por teste de tempo sob carga: a 079 uma vez,
a 109 duas, a 112 uma. **Todos passaram isolados, 3 de 3.** O recibo é a prova que o aceite lê; um recibo que falha por a máquina
estar ocupada (outra suíte rodando ao mesmo tempo, ou o load alto de outra coisa) custa a suíte inteira e uma gravação com `rc`
errado no ledger.

**O que existe hoje (`lib/cmd-evidence.sh`):** `_ev_cmd_measure_load` mede o load de 1 minuto e `_ev_cmd_preload_warn` só **avisa**
("carga já fora do limiar de medição ANTES de medir… considere esperar a carga cair") e **roda mesmo assim**. O limiar atual
(`MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100`, padrão 200 = load 2,00) serve ao **veredito** ("VÁLIDA mas fora do limiar de medição"), não a
esperar. E **nada impede dois recibos ao mesmo tempo** na mesma máquina, que é a forma mais comum de gerar a carga que queima o
outro.

## O que entrega

### 1. Espera por máquina leve (só `suite` e `order-N`)

- Em `maestro evidence --record`, quando o rótulo é de **suíte ou de ordem** (`suite`, `suite-N`, `order-N`, `order-N-<8 hex>`),
  **antes de executar** o comando, o Maestro **espera** o load de 1 minuto ficar **abaixo de um teto configurável**.
- **Teto de carga:** `MAESTRO_EVIDENCE_ESPERA_LOAD_X100` (inteiro, load × 100, como o limiar que já existe). **Padrão:
  `nproc` vezes 0,75**, em inteiro: `ncpu * 75` (nunca float; 12 CPUs → 900 = load 9,00). Valor inválido volta ao padrão.
- **Teto de espera:** `MAESTRO_EVIDENCE_ESPERA_TETO_S` (inteiro, segundos, padrão **900**). Sonda a cada 10 s (inteiro, constante).
- **Mensagem clara, na tela, enquanto espera** (a cada sonda ou a cada minuto, sem inundar): o load medido, o teto de carga, quanto
  já esperou e o teto de espera. **Ao liberar:** uma linha com quanto esperou.
- **Se o teto de espera acaba e a máquina continua pesada:** **recusa sem executar**, sem gravar recibo, com código de
  **validação** e mensagem que diz o load, o teto de carga, o tempo esperado e as duas variáveis para ajustar. (Gravar mesmo assim
  é a causa dos quatro recibos queimados; ver Ask-First 1.)
- **Outros rótulos** (áreas como `tenant-isolation`, `billing`, `frontend`, rótulo livre) **não esperam e não travam**: comportamento
  de hoje.

### 2. Trava por máquina: um recibo de suíte por vez

- Os mesmos rótulos pegam uma trava **`flock`** antes de esperar o load e a seguram **até o recibo ser gravado** (ou o comando
  falhar). A ordem é **trava primeiro, depois a espera de load**: o load que vale é o medido **depois** de o outro recibo terminar.
- **Caminho da trava:** `MAESTRO_EVIDENCE_LOCK` (padrão: `$XDG_RUNTIME_DIR/maestro-evidence.lock` e, sem ele,
  `/tmp/maestro-evidence-<uid>.lock`). É **por máquina e por usuário**, fora do repo e fora do `MAESTRO_HOME`.
- **Quem espera a trava espera dentro do mesmo teto de espera** (um só relógio, não dois); mensagem diz que há outro recibo em
  andamento. Esgotou: recusa como no item 1.
- **Solta sozinha:** a trava é do descritor do processo, então **morre com ele** (kill, Ctrl-C, queda): nunca fica trava órfã. O
  comando sob prova **não herda** o descritor (um filho que sobrevive não segura a trava).

### 3. O que não muda

- **Nada muda no formato do recibo nem no veredito** (`maestro_proof_verdict`, ordem 060): `evidence --check`, `order --status` e
  `order --accept` leem o que leem hoje. O limiar do veredito (padrão 200) **continua como está**; esta ordem **só decide quando
  começar a medir**. Se o teto de espera padrão (`ncpu * 75`) e o limiar do veredito divergirem a ponto de o recibo sair "fora do
  limiar" mesmo depois de esperar, o executor **relata a divergência com números** e **não** mexe no veredito.
- `MAESTRO_OFF=1` e os demais comportamentos de `--record` seguem iguais. **Sem flag nova de linha de comando.**

## Critérios de aceite (com oráculo)

Load e trava **simulados** no teste: o teste fornece o load por um arquivo (`MAESTRO_LOADAVG_FILE`, só para teste; sem a variável lê
`/proc/loadavg` como hoje) e a trava por um caminho próprio (`MAESTRO_EVIDENCE_LOCK`). Nenhum teste depende da carga real nem
dorme mais que alguns segundos (a sonda do teste é configurável para 1 s por `MAESTRO_EVIDENCE_ESPERA_SONDA_S`, só para teste).

- [oráculo: `bash tests/cli/test-evidence-espera-carga.sh`] **vermelho antes** (hoje grava na hora, sem esperar):
  (a) load simulado **acima** do teto, depois caindo: `--record --label suite -- <cmd>` **espera**, imprime o load, o teto e o
  tempo, e **executa só depois** de cair (marcador criado depois do load cair); (b) o mesmo para `order-N`; (c) load **abaixo**
  do teto: executa na hora, sem espera; (d) teto de espera menor que a queda: **recusa sem executar e sem gravar recibo**, rc de
  validação, mensagem com load, teto de carga, tempo e as variáveis; (e) teto de carga padrão = `ncpu * 75`; valor inválido da
  variável volta ao padrão; (f) rótulo de área e rótulo livre **não esperam** mesmo com load alto.
- [oráculo: `bash tests/cli/test-evidence-trava-maquina.sh`] **vermelho antes:** (a) dois `--record --label suite` ao mesmo tempo:
  o segundo **só começa depois** do primeiro terminar (ordem verificada por marcadores com tempo); (b) a trava é solta quando o
  primeiro é morto (`kill -9`): o segundo segue; (c) o comando sob prova **não herda** o descritor da trava: um filho que sobrevive
  ao recibo não segura a trava; (d) o segundo, com teto de espera curto, **recusa** sem executar; (e) rótulo de área não pega a
  trava; (f) travas de usuários/caminhos diferentes não se bloqueiam.
- [oráculo: `bash tests/cli/test-evidence.sh`, `bash tests/cli/test-order-060-verificador-unico.sh` e
  `bash tests/cli/test-order-044-recibo-empilhado.sh`] seguem verdes: formato do recibo e veredito intactos. Os testes
  **existentes** que gravam recibo `suite`/`order-N` ganham `MAESTRO_LOADAVG_FILE` baixo (ou o teto alto) para não esperar; a lista
  deles vai no relato.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo; `shellcheck` limpo.
- [humano] o Capitão lê o patch (toca `lib/`) e faz o merge.

## Ask-First

1. **Teto de espera esgotado: recusar ou gravar assim mesmo?** A ordem **recusa** (fecha para negado), porque gravar com a máquina
   pesada é o defeito. O custo: com a máquina cronicamente acima do teto (load 4 a 9 em 10/10), o recibo fica recusado até
   alguém subir `MAESTRO_EVIDENCE_ESPERA_LOAD_X100` ou o teto de espera. **Meça o load de 1 minuto em repouso desta máquina**
   (3 amostras) e cole no relato: se o padrão `ncpu * 75` já recusar em repouso, **PARE e pergunte** o padrão.
2. **Não mude** o formato do recibo, o veredito, o limiar `MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100`, nem a 078 (`lib/core-evidence-declared.sh`).
   Se o conserto mínimo exigir isso, PARE.
3. **Rótulos fora do escopo** (áreas, livre) não esperam nem travam. Se um deles for chamado pelo gate do aceite em lote e
   precisar da trava, PARE e relate.
4. **Toca `lib/` (autoprotegido):** a entrega é **UM patch** em `docs/patches/NNN-*.patch`, feito em clone de trabalho **na pasta
   temporária do run**, testado antes e depois; o patch final fica na **worktree**, em `docs/patches/`, e `git apply --check` roda
   nela. `tests/` e `docs/` direto no branch. **O merge é do Capitão.**
5. **Convivência com a 078 (já na `main`):** o gate da 078 (`_evd_gate`, em `lib/core-evidence-declared.sh`) recusa **antes de
   executar**. A espera e a trava entram **depois** do gate: comando recusado pela 078 **não** espera nem pega a trava. O patch é
   feito contra a `main`; não reescreva a 078.
6. **Sandbox bwrap** (se o run rodar nele): `HOME` vazio, `/tmp` efêmero, sem `~/.maestro`. Falta algo de que o turno precisa:
   **relate e PARE**, sem contornar. A trava e o load reais **não** são exercidos no sandbox; os testes usam os simulados.
7. Logs: **só metadados**; nunca o texto do comando inteiro no log.

## Como sai

Testes e emendas direto no branch; a espera e a trava em **UM patch protegido**. Emendas no mesmo changeset: API_SPEC (o contrato de
`evidence --record`: espera por load e trava por máquina, as quatro variáveis, a recusa ao esgotar), ENGINEERING_SPEC (o que a
espera garante e o que não: ela reduz recibo queimado por carga, não torna medição de tempo determinística), CHANGELOG (Changed).
Papercut: "recibo queimado por teste de tempo sob carga e por recibos simultâneos".

## Prova exigida

- Os dois testes novos vermelhos antes e verdes depois, saídas coladas; os três existentes verdes.
- As três amostras de load em repouso (Ask-First 1) e a divergência, se houver, entre o teto de espera e o limiar do veredito.
- `git apply --check` do patch na worktree; `shellcheck` limpo.
- **A suíte completa `bash tests/run-all.sh` NÃO roda no run:** o run a declara no `fim:` e o Spock a roda e grava o recibo
  `order-N` fora do run. Não lance `setsid`/`nohup`.

## Turno

- fatia: os dois testes vermelhos (espera por load e trava por máquina) colados contra o `lib/` da `main`, a implementação em clone de trabalho na pasta temporária do run, os testes verdes, as emendas (API_SPEC, ENGINEERING_SPEC, CHANGELOG, papercut), o patch final em `docs/patches/` da worktree com `git apply --check` ok e `shellcheck` limpo, e as três amostras de load em repouso
- fim: `bash tests/cli/test-evidence-espera-carga.sh` e `bash tests/cli/test-evidence-trava-maquina.sh` saem 1 antes (colado) e 0 depois no clone de trabalho, com `bash tests/cli/test-evidence.sh`, `bash tests/cli/test-order-060-verificador-unico.sh` e `bash tests/cli/test-order-044-recibo-empilhado.sh` verdes; patch protegido na worktree e `git apply --check` ok; o comando da suíte declarado aqui é `bash tests/run-all.sh`, que o run NÃO executa (o Spock roda e grava o recibo fora do run)
- teto: 2
- fora: mudar o formato do recibo, o veredito ou o limiar `MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100`, mexer na 078 ou no `_evd_gate`, esperar ou travar rótulo de área ou livre, flag nova de linha de comando, rodar a suíte completa no run, processo destacado, mexer no ponte-daemon, aplicar o patch no repo, mergear e tocar vendor/
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54,
> com o sha do tip). Terminar a resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível,
> **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou
> redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e medir.
> Patch gerado por `git diff` do clone de trabalho para `docs/patches/` é a única saída por redirecionamento admitida.

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
- Trabalhe APENAS no branch `order/080-recibo-de-suite-so-com-a-maquina`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-80 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 080` (você não fecha a própria ordem).
