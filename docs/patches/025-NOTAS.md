# Ordem 025 — notas da rodada única (2026-09-18)

Chegada: 2026-09-18T21:42:33-03:00.

## 1. O que muda, e onde

`hooks/gate-report.sh` (patch `docs/patches/025-aguardando-gate-report.patch`):
o gatilho da Ponte MCP (detecção de `[spock] aguardando:` + socket vivo,
antes só calculado depois do `if [[ -z "$gate" ]]; then … exit 0; fi`, 135
linhas depois) **sobe para ANTES desse `exit 0`**. Agora `mcp_ask`/`reentry`
são calculados uma vez, cedo, e servem os DOIS caminhos:

- **COM gate pendente** (feature/refactor com approach pendente, ou ship sem
  desfecho): comportamento **inalterado** — mesma mensagem, mesmo arquivo de
  gate, mesmo report ao herdr, mesmo bloqueio MCP. Só a implementação do
  bloqueio foi extraída para a função `_maestro_mcp_ask_gate` (reaproveitada
  pelo caminho novo) — regressão provada por `tests/hooks/test-gate-report.sh`
  e `tests/hooks/test-order-020-mcp-ask.sh`, os dois SEM EDITAR NADA, rodando
  contra o hook patchado.
- **SEM gate** (fix, custom, audit, verify, codereview — a maioria das
  rodadas, e a causa medida da ordem: nunca abriam gate, então o gatilho
  nunca era alcançado): agora, se a rodada termina com `[spock] aguardando:`
  e o socket da Ponte existe, o hook bloqueia do mesmo jeito, com o mesmo
  JSON — só que com uma `reason` genérica (não cita "gate pendente", porque
  na maioria dos casos não há gate nenhum).

Por que a POSIÇÃO (não o conteúdo) do gatilho é isolada em duas funções
(`_maestro_mcp_prune_stale`, `_maestro_mcp_ask_gate`): sem extrair, o
`if [[ -z "$gate" ]]` ficaria com duas cópias quase idênticas da lógica de
prune/marcador (uma para o caminho com gate, outra para o sem gate) — a
mesma classe de duplicação que already causou divergência silenciosa em
ordens anteriores. Efeito colateral bom: o sensor `oversized-function`
cruzou o baseline numa primeira versão (uma função de 76 linhas, teto 60) —
cortada a prosa histórica para 46 linhas, apontando para este arquivo e para
`020-NOTAS.md` em vez de repetir os três achados de custo inline.

## 2. O sufixo do marcador sem gate — ARMADILHA 1

Sufixo escolhido: **`aviso`** (`$MCP_ASKED_DIR/${sid}_aviso`), ao lado de
`plan`/`ship`. Ensinado ao prune em UM lugar: o regex de
`_maestro_mcp_prune_stale` passou de `^[A-Za-z0-9_-]+_(plan|ship)$` para
`^[A-Za-z0-9_-]+_(plan|ship|aviso)$` — a mesma função, chamada dos dois
pontos (gate pendente, posição inalterada desde a 020; sem gate, só quando
uma pergunta nova vai mesmo escrever o marcador — nunca introduz um caminho
de escrita que não existiria de qualquer forma, mesma regra da 020).

Testado (`test-order-025-aguardando-sem-gate.sh`, seção ACÚMULO): 9 sessões
abandonadas × 3 chaves (plan, ship, aviso) = 27 marcadores vencidos, mais um
`fresh_aviso` (dentro do TTL) e um `nao-e-marcador.txt` (nome fora do
padrão). Antes: 29 arquivos. Depois de UM Stop sem gate que aciona o prune:
27 vencidos somem, os 2 que devem sobreviver sobrevivem, e o marcador novo
da própria pergunta aparece — 3 arquivos ao final. Sem o sufixo no regex do
prune, os 9 `_aviso` vencidos teriam sobrevivido para sempre — a classe
exata que as ordens 021/022 corrigiram para outro mecanismo.

## 3. TTL de 40min entre perguntas sem gate — ARMADILHA 2, decisão

**Pergunta da ordem:** sem evento de resolução (o caminho com gate limpa o
marcador quando o RECORD muda de estado — `approach` deixa de ser pendente,
`ship` ganha desfecho; um evento observável fora do hook), o gerente fica
40min sem poder perguntar de novo na mesma sessão?

**Decisão, escrita no comentário do hook (não só aqui):** NÃO. A única coisa
que este hook pode observar, rodada a rodada, é se a linha
`[spock] aguardando:` ainda está lá. Regra adotada: se a rodada NÃO tem a
linha (resolvida, ou sem como perguntar — sem socket, ou reentrada
confirmada), o marcador `_aviso` é limpo imediatamente — a MESMA sessão pode
perguntar de novo na rodada seguinte sem esperar o TTL. O TTL só segura
quando a MESMA pergunta se repete rodada após rodada sem resposta ainda —
exatamente o papel que já tinha no caminho com gate (proteção contra laço
numa pergunta aberta, não um período de silêncio entre perguntas distintas).

Na prática isto quase nunca chega a valer: como o gerente resolve a
pergunta por MCP no mesmo turno (`director.ask`/`director.wait`), a rodada
SEGUINTE já não repete a linha — o marcador morre no próximo Stop, não
precisa do TTL. O TTL de 40min continua existindo só como a segunda rede de
não-laço (a mesma da 020), para o caso patológico de a MESMA pergunta se
repetir sem resposta por muitas rodadas seguidas.

Testado (`test-order-025-aguardando-sem-gate.sh`, seção "DECISÃO"): pergunta
1 bloqueia e cria o marcador; rodada seguinte sem a linha limpa o marcador
sem bloquear; pergunta 2 (nova, mesma sessão, imediatamente depois) bloqueia
de novo — não ficou presa no TTL. Não precisei parar para pedir decisão de
modelo: a extensão do papel que o TTL já tinha no caminho com gate cobre o
caso sem ambiguidade.

## 4. As duas pontas de cada teste

- **Gatilho sem gate** (a prova principal da ordem): rodada sem gate
  (workflow `fix`), com a linha e com o socket, rodada contra o hook de
  `main` (extraído via `git show main:hooks/gate-report.sh`, executado
  dentro de uma cópia completa de `hooks/` — ver armadilha de medição no
  item 6) → **FALHA de verdade** contra o código atual: `exit 0`, stdout
  vazio, nenhum gate escrito (sai no antigo `:145`, sem olhar a linha). A
  MESMA rodada contra o hook patchado → bloqueia, com `director.ask`/
  `director.wait` na `reason`, sem vazar texto do record. Seção "AS DUAS
  PONTAS" do teste novo.
- **Regressão do gate**: `tests/hooks/test-gate-report.sh` e
  `tests/hooks/test-order-020-mcp-ask.sh`, **sem editar uma linha**, rodando
  contra o hook patchado — os dois OK, incluindo a seção de prune/amostragem
  original (chave `plan|ship`, sem o sufixo novo).
- **Sem a linha → nada dispara; sem socket → nada dispara**: seção dedicada
  no teste novo, caminho sem gate — `exit 0`, stdout vazio, socket não é
  criado por engano.
- **Não-laço, três casos de `stop_hook_active`, caminho sem gate**:
  `true` → não bloqueia; ausente → bloqueia na 1ª, não bloqueia na 2ª pergunta
  igual (TTL); `false` numa sessão nova → bloqueia (parada legítima).
- **Acúmulo**: item 2 acima.
- **Latência**: item 5 abaixo.

## 5. Latência — delta contra baseline, interleaved (nunca absoluto)

Máquina sob carga durante toda a medição (load1m entre 6,2 e 8,6 — muito
acima do limiar de 2,00 de `tests/lib/latency.sh`; ARCHITECTURE.md §NFRs: o
teto de 50ms vale na CI, aqui só o delta conta). Medido com script ad-hoc
(`/tmp/wt-025-scratch/measure-latency.sh`, fora do repo — script solto, não
suíte formal), N=31 amostras por lado, **interleaved** (uma amostra de cada
por vez, alternando), baseline e patchado com a **estrutura inteira de
`hooks/` (lib/ ao lado)** — não arquivo solto (ver armadilha do item 6).
Duas rodadas independentes:

| caso | baseline med | patched med | delta (rodada 1) | delta (rodada 2) |
|---|---|---|---|---|
| gate pendente (plan), sem aguardando — caminho INALTERADO | 76ms | 80ms | **+4ms** | **-1ms** |
| sem gate (fix), COM aguardando+socket — caminho NOVO da 025 | 48ms | 60-68ms | **+12ms** | **+14ms** |
| sem gate (fix), sem aguardando — early-exit dos dois lados | 44-52ms | 53-60ms | **+8ms** | **+9ms** |

Leitura: o caminho já existente (gate pendente) não regride — delta dentro
do ruído (-1 a +4ms), consistente com "mesma lógica, só relocada em
função". O caminho NOVO (sem gate, com a pergunta) custa de fato mais
(+8 a +14ms): é trabalho real que não existia antes (checar socket+linha,
sample do prune, escrever o marcador `_aviso`, montar o JSON) — não uma
regressão de código existente. Nos dois casos, a ordem de grandeza do delta
é de um dígito a baixa dezena de ms, muito abaixo da folga de 2x que o NFR
já concede sob carga (ARCHITECTURE.md §NFRs).

## 6. Armadilha de medição que quase reproduziu o bug do repo

Primeira tentativa de medir a baseline usou uma cópia SOLTA de
`hooks/gate-report.sh` (sem `lib/` ao lado) extraída de `main`. Resultado:
baseline "mediu" ~18ms constante em QUALQUER cenário — porque
`source "$SCRIPT_DIR/lib/common.sh"` falha (lib/ não existe ali) e o hook
sai no PRÓPRIO source-guard (`if ! source … ; then exit 0; fi`), medindo um
no-op, não o hook de verdade. Corrigido copiando `hooks/` inteiro (com
`lib/`) e só sobrescrevendo `gate-report.sh` com o conteúdo de `main` — a
mesma armadilha que a ordem já avisava ("armadilhas do repo", item de
medição). Números da tabela acima já são da versão corrigida.

## 7. Suíte, `habits`, `doctor`

- **Suíte completa em cópia patchada** (`git clone` de `/tmp/wt-025` para
  `/tmp/wt-025-scratch/clone-patched` — nunca `git archive` — + `git apply`
  dos dois patches de código: `025-aguardando-gate-report.patch` e
  `025-aguardando-teste.patch`): **SUITE OK**, 2578 asserções `ok`, zero
  FAIL/FALHOU, 80 arquivos de teste + `doctor`.
- `maestro habits hooks/gate-report.sh tests/hooks/test-order-025-aguardando-sem-gate.sh tests/hooks/test-order-020-mcp-ask.sh`
  na cópia patchada → `habits: limpo (3 arquivo(s) sensoriado(s))`.
  `oversized-function`/`oversized-file` não cruzam mais o baseline depois do
  corte de prosa (item 1).
- `maestro doctor`: **veredito idêntico** entre um clone de `main` sem
  nenhum patch (`/tmp/wt-025-scratch/clone-baseline`) e o clone patchado —
  `43 checagens, 2 aviso(s)` nos dois.
- `bash -n` e `shellcheck --severity=error` em `hooks/gate-report.sh` e nos
  dois arquivos de teste tocados: limpo nos dois.

## 8. O que ficou de fora / decisões descartadas

- Não considerei rodar a poda (`_maestro_mcp_prune_stale`) em TODA rodada
  sem gate, incondicionalmente — só quando `mcp_ask==1 && reentry==0` (isto
  é, quando o marcador `_aviso` vai mesmo ser escrito). Motivo: manter o
  invariante "nunca introduz caminho de escrita novo, só reaproveita o que
  já ia escrever" (o mesmo que já regia o caminho com gate desde a ordem
  020) — rodar prune (que pode criar `$MAESTRO_HOME/herdr/mcp-asked-prune-
  counter`) em rodadas que hoje não escrevem NADA (fix/custom sem pergunta
  nenhuma) seria um caminho de escrita novo sem necessidade. Trade-off
  aceito: um projeto que só dispara `_aviso` uma única vez, nunca mais, e
  nenhuma outra sessão nunca abre gate NEM outra pergunta sem gate, deixaria
  esse único marcador sem poda automática até o TTL vencer e alguma OUTRA
  pergunta (com ou sem gate) rodar o prune. Nunca cresce sem limite (é no
  máximo 1 arquivo por sessão), só não é podado no INSTANTE em que vence —
  mesma classe de imprecisão que o mecanismo original já tinha (o prune
  também não roda "sozinho": sempre precisa de ALGUMA rodada que o dispare).
- Não toquei em `hooks/user-prompt-submit.sh` — a limpeza do marcador
  `_aviso` não depende de resposta humana digitada (não há "resposta" nesse
  caminho; a volta é por MCP, no mesmo turno do gerente), então não há
  gancho de limpeza ali.
- Reason do bloqueio: usei a MESMA string para os dois caminhos (com e sem
  gate), generalizada para não citar "gate pendente" — evita duas strings
  quase idênticas divergindo com o tempo. Os testes de conteúdo da `reason`
  (director.ask/director.wait, 30min, desfecho, sem vazamento) continuam
  batendo nos dois arquivos de teste.

## 9. Patches e commit

Pacote em `docs/patches/`, ordem de aplicação:
1. `025-aguardando-gate-report.patch` — `hooks/gate-report.sh` (denylist:
   patch-only, não commitado direto).
2. `025-aguardando-teste.patch` — `tests/hooks/test-order-025-aguardando-
   sem-gate.sh` (arquivo novo; também commitado direto, por contrato).
3. `025-aguardando-ordem.patch` — `.maestro/orders/025-o-aviso-do-gerente-
   sai-por-mcp-e.md` (também commitado direto).

Verificação feita ANTES do commit: `hooks/gate-report.sh` revertido para
HEAD, `git apply --check` + `git apply` de `025-aguardando-gate-report.patch`
a partir do arquivo SALVO reproduziu byte a byte o mesmo conteúdo que estava
editado ao vivo (`diff` vazio) — nunca testei a partir do arquivo editado ao
vivo sem essa verificação.

Commit desta rodada: ver `git log` no tip do branch
`feat/025-aguardando-por-mcp` logo após este arquivo. Recibo
`maestro evidence --record --label order-25 -- bash tests/run-all.sh`
gravado no tip **depois** do commit e de eu já ter descartado os dois
clones (`clone-patched`, `clone-baseline`) — nesse ponto `hooks/` no tip não
tem o patch aplicado (por contrato, denylist), então o recibo desta suíte
roda contra o código SEM o patch: espera-se vermelho, com as FAILs sendo as
asserções positivas de `test-order-025-aguardando-sem-gate.sh` que só
passam com o patch (mesmo padrão do recibo da ordem 020 — ver
`020-NOTAS.md`, rodada 4/5).

Término: 2026-09-18T22:30:00-03:00 (aprox.; ver timestamp real do commit).
