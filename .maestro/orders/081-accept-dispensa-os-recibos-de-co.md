<!-- maestro-order v1
id: 081
ts: 2026-10-12T23:25:28-03:00
epoch: 1791858328
head: 67b1c0733eb0b38849b0c3be3d9fd7aad25474a5
branch: order/081-accept-dispensa-os-recibos-de-co
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 081 — accept dispensa os recibos de codigo quando o diff e so de docs_only_paths

## Por quê

**Pedido do Capitão, 12/10 (escolha b).** A NetForge pulou a CI de PR **só de documentação** (`paths-ignore` com `docs/**`,
`.maestro/**` e `**/*.md` no `ci.yml`, commit `1fab901`). Mas o `maestro order --accept` exige os recibos de **código** (`suite`,
`tenant-isolation`, `frontend`, `billing`), que leem a **CI do HEAD exato**. Uma ordem só de docs **nunca tem CI**, então **nunca é
aceita**.

**Caso real:** NetForge 108, PR 173. O diff contra o `master` é só o doc e a ordem. O accept recusa porque o branch trouxe o `master`
por **merge**, e o diff contra a **base da ordem** (`verif_base_ref`, usado por `_order_verif_areas` em
`lib/core-order-state.sh`) toca tudo o que veio do `master`: todas as áreas "tocadas", todos os recibos exigidos.

## O que entra

### 1. Dispensa dos recibos de código no accept, quando o diff é só de docs

- No `--accept` (e **na mesma regra do `order --status`**, que usa o mesmo `_order_verif_report`: um verificador só, sem critério
  duplicado), calcula-se `git diff --name-only --no-renames <merge-base> <branch>`, em que `<merge-base>` é o **merge-base do
  branch com o branch padrão remoto** (`origin/HEAD`, resolvido como o Maestro já resolve o branch padrão em outros pontos).
- Se **todos** os caminhos desse diff casam com a lista **`docs_only_paths`** do `.maestro.yaml` do projeto, os recibos de código
  (as áreas que `maestro_verif_labels` devolveria) ficam **DISPENSADOS**: o `_order_verif_gate` não os cobra.
- **O recibo `order-NN` continua exigido**, igual a hoje (veredito `maestro_proof_verdict`, ordem 060, intacto).
- **A dispensa é dita:** na saída do accept e do status ("recibos de código DISPENSADOS: diff contra o merge-base só em
  `docs_only_paths`"), com a **lista de arquivos**, e **no ledger** (o registro `order-state` do aceite ganha a marca da
  dispensa e a lista de arquivos). Campo novo **aditivo**: o leitor antigo ignora; nada que já é lido muda de veredito.
- **Sem a chave `docs_only_paths`, nada muda.** Igual a hoje, byte a byte.

### 2. A lista é do projeto, nunca embutida, e não é do run

- Vem do `.maestro.yaml`; o Maestro **não embute** padrão nenhum. O projeto a mantém **igual ao `paths-ignore` do CI** dele.
- **Lida do `.maestro.yaml` do merge-base (branch padrão), não do tip do branch.** O run edita o tip: se a lista fosse lida do
  branch, um run (ou um doc) poderia declarar `src/**` como "docs" e se dispensar. O mesmo princípio da 078 (`fim_commit`).
- **Allowlist explícita, nunca heurística; entrada inválida vira "sem a chave"** (nada dispensa), com aviso na saída:
  padrão vazio, `.`, `*`, `**` sozinho, com `..`, absoluto, ou que case o repo inteiro. A mesma recusa de padrão largo da 071.
- **Como casar:** o executor usa o glob do próprio git (`pathspec` com `:(exclude,glob)<padrão>`, sem motor de glob próprio).
  Se o glob do git não casar com o do `paths-ignore` do GitHub no caso `**/*.md` (inclusive na raiz), relate com o exemplo.

### 3. Por que `--no-renames`

`git diff --name-only` com detecção de rename mostra **só o caminho novo**. Um arquivo de **código movido para `docs/`** apareceria
como "docs" e dispensaria. Com `--no-renames` o caminho **antigo** (código) aparece como remoção e **impede a dispensa**.
Remoção de arquivo de código também impede (o caminho não é de docs).

### 4. Casos sem merge-base confiável

Sem `origin/HEAD` resolvível, sem merge-base, ou diff **vazio**: **não dispensa** (fecha para negado), com a razão na saída.

## Critérios de aceite (com oráculo)

Cada teste **vermelho antes do código** (saída colada no clone de trabalho, contra o `lib/` da `main`) e **verde depois**. Projeto de
teste com `origin` bare, branch padrão, `.maestro.yaml` com `verification` por área e `docs_only_paths: [docs/**, .maestro/**, "**/*.md"]`.

- [oráculo: `bash tests/cli/test-order-docs-only-dispensa.sh`]
  (a) **só docs dispensa:** diff contra o merge-base só com `docs/x.md` e a ordem; os recibos de código não são cobrados, o
  `order-NN` é, a saída e o ledger listam os arquivos;
  (b) **misto não dispensa:** um `.ts` junto de `docs/x.md`: os recibos de código são cobrados como hoje;
  (c) **sem a chave não dispensa:** o mesmo diff só de docs, `.maestro.yaml` sem `docs_only_paths`: cobrado como hoje (saída idêntica);
  (d) **o `master` trazido por merge:** branch com `git merge origin/master` e diff real contra o merge-base só de docs **dispensa**
  (o caso da NetForge 108); o mesmo branch **sem** a dispensa estaria cobrando tudo;
  (e) **renomeado de código para docs não dispensa:** `git mv src/a.ts docs/a.ts.md`;
  (f) **remoção de código não dispensa**;
  (g) **o `order-NN` continua exigido:** só docs, sem recibo `order-NN`: o accept **recusa**.
- [oráculo: `bash tests/cli/test-order-docs-only-adversarial.sh`] todos **sem dispensa, sem tocar o ledger**:
  (a) o branch edita `docs_only_paths` no próprio `.maestro.yaml` para incluir `src/**` ou `**`: vale a lista do **merge-base**;
  (b) padrão inválido (`**`, `*`, `.`, `../x`, `/etc/**`, vazio): tratado como sem a chave, com aviso;
  (c) sem `origin/HEAD` ou sem merge-base: não dispensa;
  (d) diff vazio: não dispensa;
  (e) `order --status` e `order --accept` **concordam** em todos os casos acima.
- [oráculo: as mutações] depois de verdes, **aplique cada mutação, mostre qual teste caiu e REVERTA** (tabela mutação → teste que
  caiu, no relato; nenhuma mutação pode sobreviver):
  M1 trocar "todos casam" por "algum casa"; M2 tirar `--no-renames`; M3 ler a lista do tip do branch em vez do merge-base;
  M4 dispensar sem a chave; M5 dispensar também o `order-NN`; M6 não gravar a lista de arquivos no ledger/saída; M7 deixar o diff
  vazio dispensar; M8 aceitar o padrão `**`.
- [oráculo: `bash tests/cli/test-order-verif-gate.sh` e os demais testes de accept/status da suíte] seguem verdes: sem a chave, nada muda.
- [oráculo: `bash tests/run-all.sh`] suíte verde; `habits` sem aviso novo; `shellcheck` limpo.
- [humano] o Capitão lê o patch (toca `lib/`) e faz o merge.

## Ask-First

1. **Leitura da lista no merge-base** (item 2): se o `.maestro.yaml` não existir no merge-base, ou não for legível, **não dispensa**.
   Se isso inviabilizar o caso real da NetForge 108 (o `.maestro.yaml` com a chave só nasce depois), PARE e relate: a chave na
   NetForge é de outra ordem, **depois do release** (item 4).
2. **Contrato do `.maestro.yaml`:** a chave nova é só `docs_only_paths` (lista de strings). Qualquer outra chave, ou mudar o
   formato do recibo ou o veredito: PARE (API_SPEC, DATA_MODEL). O campo novo do ledger é **aditivo**.
3. **Toca `lib/` (autoprotegido):** a entrega é **UM patch** em `docs/patches/NNN-*.patch`, feito em clone de trabalho **em
   `docs/research/work/` da worktree** (já ignorado pelo `.gitignore`; sob bwrap a `/tmp` do run **não persiste** entre chamadas
   de Bash, então o clone não pode morar lá), testado antes e depois; o patch é gerado **de lá** para `docs/patches/`, e
   `git apply --check` roda na worktree. `tests/` e `docs/` direto no branch. **O merge é do Capitão.**
4. **Sandbox (se o run rodar nele):** sem `~/.maestro`; falta algo de que o turno precisa: **relate e PARE**, sem contornar.
5. Logs: **só metadados**; nunca caminho completo de arquivo.

## Como sai

Testes e emendas direto no branch; a dispensa em **UM patch protegido**. Emendas no mesmo changeset: API_SPEC (a chave
`docs_only_paths` do `.maestro.yaml` e o que o accept faz com ela), DATA_MODEL (o campo aditivo da dispensa no registro do aceite),
ENGINEERING_SPEC (o que a dispensa garante e o que não: ela dispensa a **CI de código**, não a prova da ordem), CHANGELOG (Added).
Papercut: "ordem só de docs nunca é aceita quando a CI pula docs".

## Prova exigida

- Os dois testes novos vermelhos antes e verdes depois, saídas coladas; os existentes verdes.
- A tabela das mutações (mutação → teste que caiu → revertida).
- O exemplo do glob `**/*.md` na raiz, casando ou não com o `paths-ignore`.
- `git apply --check` do patch na worktree; `shellcheck` limpo.
- **A suíte completa `bash tests/run-all.sh` NÃO roda no run:** o run a declara no `fim:` e quem despacha roda e grava o recibo
  `order-NN` fora do run. Não lance `setsid`/`nohup`.

## Turno

Limites do turno: **60 min · 100 turnos** (teto de turnos da ordem = 1). Fora do bloco por não serem rótulos.

- fatia: (os três arquivos de teste que já estão na worktree sem commit, `tests/cli/test-order-docs-only-dispensa.sh`, `tests/cli/test-order-docs-only-adversarial.sh` e `tests/lib/docsonly-fixture.sh`, o run os valida e commita) o accept com dispensa (`docs_only_paths`, `--no-renames`, lista lida do merge-base, a marca na saída e no ledger), os testes vermelhos antes e verdes depois, as mutações M1 a M8 aplicadas e revertidas com o teste que caiu, as emendas, o patch final em `docs/patches/` da worktree com `git apply --check` ok e `shellcheck` limpo
- fim: `bash tests/cli/test-order-docs-only-dispensa.sh` e `bash tests/cli/test-order-docs-only-adversarial.sh` saem 1 antes (colado) e 0 depois no clone de trabalho, com a tabela das mutações toda caída e revertida; patch protegido na worktree e `git apply --check` ok; o comando da suíte da Maestro declarado aqui é `bash tests/run-all.sh`, que o run NÃO executa (quem despacha roda e grava o recibo da ordem fora do run)
- teto: 1
- fora: o release (é do Capitão, pelo botão `release_maestro`), a chave `docs_only_paths` no `.maestro.yaml` da NetForge (ordem dela, depois do release), embutir qualquer lista de caminhos no Maestro, mudar o formato do recibo ou o veredito, dispensar o `order-NN`, rodar a suíte completa no run, processo destacado, mexer no ponte-daemon, aplicar o patch no repo, mergear e tocar vendor/
- relatório: nos cinco rótulos: feito · provado · aberto · decisão · próximo

> **`director_report` obrigatório.** O turno **só termina** com o `director_report` enviado (relato fixo da v54,
> com o sha do tip). Terminar a resposta sem ele é turno sem relato. Se o MCP da Ponte não estiver disponível,
> **pare e diga isso** no fim da resposta; não encerre em silêncio.

> **Escrita só com Write ou Edit, nunca por shell.** Nenhum heredoc, `tee`, `sed -i`, `python -c`, `cat >` ou
> redirecionamento (`>`, `>>`) para escrever código, teste ou documento. O Bash serve para rodar, ler e medir.
> Patch gerado por `git diff` do clone de trabalho para `docs/patches/` é a única saída por redirecionamento admitida.

> **Comando simples:** um comando por chamada de Bash; caminho absoluto em vez de cd e &&; sem pipe para cortar
> saída (| tail, | head), a ferramenta já corta; 2>&1 é permitido (junta saídas, não grava arquivo).

> **Log e escrita:** o clone de trabalho e os logs (de teste, de mutação, de espera) vão para `docs/research/work/` da worktree
> (ignorado pelo `.gitignore`), nunca para `/tmp`: sob bwrap a `/tmp` do run não persiste entre chamadas de Bash. Escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação nem um subagente: espere em laço até o fim antes de relatar.
> Não lance processo destacado (`setsid`, `nohup`): ele morre com o run. Nenhuma espera fica para depois do relato.

> **Revisão de subagente:** termina em ARQUIVO em `~/.maestro/briefs/` — o relato cita o caminho, não cola o achado. Arquivo se escreve **só com Write e Edit**.

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/081-accept-dispensa-os-recibos-de-co`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-81 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 081` (você não fecha a própria ordem).
