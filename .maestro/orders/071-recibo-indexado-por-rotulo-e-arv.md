<!-- maestro-order v1
id: 071
ts: 2026-10-05T22:59:19-03:00
epoch: 1791251959
head: a61f3d368c186f9ee39ea3c0cd2c87460604fced
branch: order/071-recibo-indexado-por-rotulo-e-arv
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
deferred_by: spock 2026-10-06 regra da subtracao
-->
# Ordem 071 — recibo indexado por rotulo e arvore canonica: rebase so de carimbo nao vence o recibo

## Por quê

**Item 12 do plano aprovado pelo Capitão em 05/10**
(`/home/rcosta00/dev/spock/docs/pesquisa-metodo-testes-netforge-2026-10-05.md`, seção 4, "No Maestro: recibo
indexado por (rótulo, árvore canônica)"; mecanismos 1 e 2 da seção 3.3). A avaliação mediu duas perdas que vêm
do **formato do recibo**:

1. **O recibo é um arquivo por rótulo e por projeto, e o último a gravar vence**
   (`maestro_evidence_file`, `hooks/lib/project-state.sh:89-93`; `lib/cmd-evidence.sh`). Em 03/10 a 047 gravou
   por cima do recibo da 045, e a 045 o achou VENCIDO 30 minutos depois. A 048 já deu a saída parcial
   (`suite-N` por ordem), mas o formato continua sendo "um arquivo por chave".
2. **Fast-forward + recibo preso à árvore = cada aceite derruba as irmãs.** 4 CIs verdes descartadas (628
   lab-min, 23% do lab das PRs). O rebase da 045 sobre a 046 veio de um delta só em `docs/ci/test_weights.tsv`,
   **sem interseção** com a 045, e custou CI de 94 min + billing de ~51 min + `order-45`. **Até merge só de docs
   invalida** (PR #120), porque `core-tree.sh` exclui apenas `.maestro/**`.

**O que o Maestro já faz (ordem 044):** `maestro_tree_same` ignora `.maestro/**`, então o rebase que traz **só o
carimbo de aceite da irmã** não vence o recibo. O que **falta** é o que a 044 não cobre: (a) o rebase cujo delta
é **inerte mas não é `.maestro/`** (docs, TSV de pesos de teste), e (b) **um recibo por rótulo e árvore**, em
vez de um arquivo por chave que a próxima gravação sobrescreve.

## Conflito com o congelamento da v59: diga-se

**Há conflito, em dois pontos.** O INTENT v59 (spock, "enxugar antes de expandir"), item 3: *"O que entra antes do
gate é só"* uma lista fechada (correção de segurança e integridade, 080 do daemon, permissão dos runs headless,
**um verificador único de prova**, wake, backup). Esta ordem **não é nenhuma delas**: é mudança de **formato do
ledger** e de **semântica de quando um recibo vale**. Não é camada nova (sem estação, fila, especialista ou
empresa plugável: o item 1 não a barra), mas **o item 3 não a lista**. E há um **segundo** conflito, de método:

- **Contamina o gate.** O gate da v59 compara a linha de base da 058 com os **próximos 10 aceites** (população e
  janela iguais, pós-v59), medindo **retrabalho** (recibos regravados) e **tempo parado em "pronta"**. Mudar
  **quando um recibo vale** no meio da janela **muda essas duas métricas por causa do formato**, não por causa
  das medidas que o gate quer avaliar: o ganho se confunde com o efeito do formato.

**Consequência escrita na ordem:** ela **entra por ordem direta do Capitão**, como a v60 e a v61 excepcionaram o
congelamento (o plano de 05/10 foi aprovado por ele, item 12 incluído), **e só com a exceção registrada no
INTENT** (emenda do Diretor). **Pré-condição para o executor começar:** a emenda registrada, e **decidido** se
a mudança entra **antes** do gate (o painel da 063 marca a quebra de série na janela) ou **depois** dele.
Sem isso, **PARE** no primeiro passo (Ask-First).

## O que entrega

### 1. O que é a "árvore canônica"

A **árvore canônica** é a árvore do tip **sem os caminhos declarados inertes**. O default **continua** sendo só
`.maestro/**` (a política da 044: nada muda para projeto que não declarar). O projeto pode declarar mais, em
`.maestro.yaml`, caminhos que **comprovadamente não afetam o que o rótulo prova** (ex.: `docs/`, `*.md`,
`docs/ci/test_weights.tsv`). **Allowlist explícita, nunca heurística:** caminho não declarado **conta**.
Declarar um caminho inerte é uma **decisão do dono do projeto**, e o Maestro a imprime no recibo.

### 2. O recibo indexado por (rótulo, árvore canônica)

- O recibo passa a ser identificado por **(rótulo, hash da árvore canônica)**, e **gravar um não sobrescreve o
  outro**: a gravação de `billing` na árvore B não apaga o de `billing` na árvore A. Leitura: dado o tip, o
  verificador procura o recibo do **rótulo** cuja **árvore canônica é igual à do tip**.
- **Compatível:** o arquivo antigo (um por chave) continua **lido** como recibo do seu `wtree_after`, e a
  chave `suite-N`/`order-N` da 048 segue valendo. Nenhum recibo existente deixa de ser lido ou muda de veredito.
- **Higiene:** o índice tem **teto** (os N mais recentes por rótulo, N inteiro e declarado) para não crescer sem
  limite; poda só de recibo mais antigo que a árvore atual **e** fora do teto, nunca de recibo VÁLIDO no tip.
- **Um verificador só:** a regra mora no verificador único (`maestro_proof_verdict`, ordem 060) e em
  `maestro_tree_same`/`lib/core-tree.sh`. `evidence --check`, `order --status` e `order --accept` **não ganham
  critério próprio**.

### 3. O que isso resolve, e o que não

- **Resolve:** o rebase cujo delta cai só em caminhos inertes declarados **não vence** o recibo; gravações
  paralelas do mesmo rótulo em árvores diferentes **coexistem**; o aceite em lote deixa de derrubar as irmãs
  por docs/TSV.
- **Não resolve (declarado):** o rebase que traz **código que o rótulo exercita** continua vencendo o recibo (é o
  correto); um caminho inerte **mal declarado** produz falso VÁLIDO: por isso a allowlist é do dono e impressa
  no recibo, e o teste adversarial abaixo tenta forçar esse erro.

## Critérios de aceite (com oráculo)

- [oráculo: `bash tests/cli/test-order-071-recibo-por-arvore.sh`] **dois recibos do mesmo rótulo em árvores
  diferentes coexistem**; a leitura devolve o do tip. **Vermelho antes** (a segunda gravação sobrescreve a
  primeira), colado.
- [oráculo: `bash tests/cli/test-order-071-arvore-canonica.sh`] com caminho inerte declarado (`docs/`), um rebase
  que só muda `docs/` **não vence** o recibo; **sem a declaração, vence** (default da 044 intacto); mudança em
  código fora da allowlist vence sempre. **Reproduz o caso da 045** (delta só em um TSV inerte declarado).
- [oráculo: `bash tests/cli/test-order-071-adversarial.sh`] **adversarial:** (a) caminho inerte declarado que
  **na verdade** o comando exercita não vira VÁLIDO por acidente sem o dono ter declarado; (b) caminho com
  `..`, symlink, glob largo (`*`) ou `.` na allowlist é **recusado** com erro claro; (c) `.maestro.yaml`
  ilegível degrada para o default da 044, **nunca** para "tudo inerte"; (d) recibo antigo e recibo novo para a
  mesma árvore **não divergem** de veredito.
- [oráculo: `bash tests/cli/test-order-044-recibo-empilhado.sh`, `bash tests/cli/test-order-060-verificador-unico.sh`
  e `bash tests/cli/test-evidence.sh`] seguem verdes: **a 044 e o verificador único não regridem**.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo.
- [humano] o Diretor lê a allowlist proposta para o NetForge e confirma o que é inerte lá.

## Ask-First

- **Pré-condição (acima):** a exceção ao congelamento registrada no INTENT e a decisão **antes ou depois do
  gate**. Sem ela, PARE no primeiro passo e relate.
- **Mudança de formato do ledger (DATA_MODEL):** é o ponto da ordem. Se o índice por árvore exigir **quebrar**
  leitor existente (CLI de projeto na 1.20/1.21), PARE; o descompasso de versão da frota é o caso do papercut 50 e
  da ordem 068.
- **Reproduza o problema antes de consertar:** o "rebase só de carimbo" **já está coberto pela 044**; escreva o
  teste vermelho para o que de fato falha (delta inerte que não é `.maestro/`) e **diga**, com a saída colada,
  qual parte da queixa a 044 já resolvia. Se **todo** o caso da 045 já passar com a 044, relate "não reproduz" e
  reduza a ordem ao índice por árvore.
- Se a **allowlist por projeto** exigir mudar o **contrato do `.maestro.yaml`** além de uma chave nova,
  PARE (API_SPEC).
- **Toca `lib/` e `hooks/lib/project-state.sh` (autoprotegidos):** a entrega é **UM patch** em
  `docs/patches/071-*.patch`, feito em clone sandbox FORA do repo, testado antes e depois, aplicado pelo Capitão
  com um `git apply`; `git apply --check` no worktree. `tests/` e `docs/` direto no branch.
- **Fora desta ordem:** os scripts de recibo do NetForge e a política de "rebase automático após o carimbo"
  (item 4 do plano): outro repo e outro método.
- Logs: **só metadados**; nunca caminho completo de arquivo.

## Como sai

Os testes e as emendas de docs direto no branch; a árvore canônica, o índice e a leitura em **UM patch
protegido**. Emendas no mesmo changeset: DATA_MODEL (o formato do recibo indexado, a compatibilidade, o teto do
índice, a chave `proof_inert` no `.maestro.yaml`), API_SPEC (leitura por (rótulo, árvore canônica)),
ENGINEERING_SPEC (o que a allowlist garante e o que não) e o CHANGELOG (Changed). Papercut: "último recibo a
gravar sobrescreve o do mesmo rótulo".

## Prova exigida

- Os três testes novos vermelhos antes e verdes depois, saídas coladas; a 044 e o verificador único verdes.
- A saída que mostra **qual parte da queixa a 044 já resolvia** e qual não.
- A allowlist proposta para o NetForge (para o Diretor conferir), sem aplicá-la.
- Suíte completa `SUITE OK`, sozinha no worktree; recibo `order-71` no tip com o patch aplicado e
  `maestro order --status 71` VÁLIDA.

## Turno

- fatia: o teste vermelho do caso da 045 (delta só em caminho inerte declarado e dois recibos do mesmo rótulo em árvores diferentes) e a separação do que a 044 já cobre
- fim: `test-order-071-recibo-por-arvore` e `test-order-071-arvore-canonica` saem 1 antes (colado) e 0 depois, no sandbox, com a 044 e o verificador único verdes; patch protegido pronto e `git apply --check` ok; `bash tests/run-all.sh` completa no sandbox sai 0
- teto: 4
- fora: começar sem a exceção ao congelamento registrada e a decisão antes/depois do gate, aplicar a allowlist ao NetForge, mudar o veredito além do índice por árvore, os scripts de recibo e o rebase automático (outro repo), aplicar o patch e tocar vendor/
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
- Trabalhe APENAS no branch `order/071-recibo-indexado-por-rotulo-e-arv`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-71 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`), Prioridade 3 (trilho onde o trilho alcança), com o aval do Capitão de 05/10 ao plano (item 12) como autorização **condicionada à exceção ao congelamento da v59 registrada no INTENT** — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 071` (você não fecha a própria ordem).
