<!-- maestro-order v1
id: 047
ts: 2026-10-02T10:03:54-03:00
epoch: 1790946234
head: 10d514eb3d058408024bcdb1fe9bd6f9d35bd425
branch: order/047-bash-e-python-escrevendo-em-self
frozen: vendor/ src/
intent_version: 6
intent_hash: 31205cc5
author_session: 78325be8-9ba2-4a68-b281-22a419b849cb
-->
# Ordem 047 — bash e python escrevendo em self_paths: a autoprotecao so intercepta Write e Edit

## A decisão que a autoriza

Decisão do Diretor em 02/10, no relato da ordem 046: **a autoproteção do gate só intercepta
Write e Edit.** Bash e python escrevem em `self_paths` sem barreira — o gerente fez isso nas
ordens 044 e 045 (`lib/core-tree.sh` e os comparadores, gravados por heredoc e por python) sem
nenhum aviso do gate. A direção é o INTENT v6 §Limites ("Autoproteção do gate: … `hooks/`,
`bin/`, `src/`, `agents/` … seguem bloqueadas") e a Prioridade 3: trilho onde o trilho alcança.
Esta ordem fecha o caminho do Bash. A 044 **não** é reaplicada: conteúdo revisado e testado,
reaplicar seria teatro.

## O defeito, reproduzido em 02/10

`hooks/pre-bash-guard.sh` não conhece `self_paths` (nenhuma referência no arquivo). Payload
de Bash com cada forma, projeto limpo, `MAESTRO_HOME` isolado — **rc 0 em todas**:

| forma | exemplo | rc hoje |
|---|---|---|
| redirecionamento | `echo x > lib/a.sh` · `echo x >> bin/maestro` | 0 · 0 |
| heredoc | `cat > hooks/x.sh <<EOF …` | 0 |
| `tee` | `printf x \| tee lib/a.sh` | 0 |
| `sed -i` | `sed -i s/a/b/ bin/maestro` | 0 |
| `cp` · `mv` · `install` | `cp /tmp/a lib/b.sh` · `mv /tmp/a hooks/c.sh` | 0 · 0 · 0 |
| `python`/`node` | `python3 -c "open('lib/x','w')…"` · `node -e "…writeFileSync('bin/x'…)"` | 0 · 0 |
| `perl -i` · `dd of=` | `perl -pi -e … lib/a.sh` · `dd … of=lib/z` | 0 · 0 |

## O que entrega

Fechar o caminho no `pre-bash-guard`, **sem classificar tela** — critério mecânico, sem
heurística sobre intenção: o comando é bloqueado (exit 2, mesma mensagem de autoproteção do
gate) quando contém **uma forma de escrita E um caminho de `self_paths`**.

1. **Formas de escrita**, cada uma com teste: redirecionamento (`>`, `>>`, `&>`, `>|`,
   inclusive heredoc), `tee [-a]`, `sed -i`/`--in-place`, `perl -i`, `cp`, `mv`, `install`,
   `dd of=`, `ln`, `truncate`, e **`python`/`python3`/`node` com caminho de `self_paths` em
   qualquer posição** (não dá para separar leitura de escrita dentro de um programa sem o
   classificar; o interpretador com alvo protegido bloqueia).
2. **O que é "caminho de `self_paths`":** o MESMO conjunto que o `pre-tool-gate` usa — a
   política compilada da sessão (E26/S-2601) e, ausente ela, o fallback embutido
   (`agents/ bin/ src/ hooks/ lib/ config/routing-table.yaml config/accept-proof.pub
   .claude-plugin/`) — relativo ao projeto OU absoluto sob a raiz do plugin OU sob qualquer
   worktree do mesmo repo (a mesma âncora da ordem 043). Fonte única: nenhuma lista nova.
3. **Destino, não origem:** `cp lib/a.sh /tmp/b` (lê de `self_paths`, escreve fora) passa;
   `cp /tmp/a lib/b.sh` bloqueia. Em `mv` conta origem E destino (mover tira o arquivo).
4. **Falha fechada só no ramo que casa:** se o guard não consegue resolver o common-dir de um
   caminho que casa prefixo da denylist, bloqueia (ADR-003 v1.1). Fora desse ramo, qualquer
   falha libera — a Prioridade 1 vence a 3.
5. **A saída diz o que fazer:** a mensagem aponta o molde das ordens 045/046 — clone sandbox
   FORA do repo do plugin, edição lá, `git diff` vira `docs/patches/NNN-*.patch`, aplicado por
   mão humana. `maestro consent` **não** destrava (consent só levanta DADOS: routing-table e
   roster, e só para Write/Edit; esta ordem não o estende ao Bash).

## O que o trilho NÃO alcança — e fica escrito

Honra declarada: um script que o gerente escreve num arquivo FORA de `self_paths` e depois
roda (`bash /tmp/x.sh`, que por dentro escreve em `lib/`) **não é visto** — o guard lê o
comando, não o programa. `git apply docs/patches/…` também passa: o caminho do comando é
`docs/`, e o patch toca `bin/`. `eval`, variável montando o caminho (`D=li; echo x > ${D}b/…`)
e escrita por ferramenta que o guard não lista idem. Cada uma entra em ENGINEERING_SPEC
como limite declarado, com número de formas cobertas e não cobertas.

## Ask-First

- Se ler a política compilada no guard custar >1 fork no caminho comum ou estourar 50 ms (o
  mesmo orçamento do guard), PARE e reporte a medição antes do patch.
- Se `python`/`node` com caminho protegido gerar falso positivo medido na suíte ou no log
  real (leitura legítima bloqueada), reporte os casos antes de afrouxar — o afrouxamento é
  decisão do Diretor, não do executor.
- Se o conserto exigir tocar `hooks/lib/common.sh` além de uma função auxiliar, diga qual
  linha e por quê antes de escrever o patch.

## Como sai

`tests/` e `docs/` direto no branch. `hooks/` (e `lib/`, se preciso) são autoprotegidas — saem
num **UM patch** em `docs/patches/047-*.patch`, feito em clone sandbox fora do repo, testado
antes e depois, aplicado pelo Capitão com um `git apply`. Emendas no MESMO changeset:
ARCHITECTURE (ADR-003, nota da fronteira do Bash), API_SPEC (contrato do `pre-bash-guard`),
ENGINEERING_SPEC (limites declarados), CHANGELOG.

## Prova exigida

- **Vermelho antes:** um teste monta o guard e manda CADA forma da tabela acima com alvo em
  cada raiz da denylist (`agents/ bin/ src/ hooks/ lib/ config/routing-table.yaml
  config/accept-proof.pub .claude-plugin/`); hoje todas saem rc 0 (saída colada no relatório).
- **Verde depois:** todas saem rc 2, pelo caminho relativo, pelo absoluto do projeto e pelo
  de um worktree do repo.
- **Controles negativos:** leitura (`cat`, `grep`, `cp lib/a /tmp/b`, `python` sem caminho
  protegido), escrita em `docs/`, `tests/`, `.maestro/` e `/tmp` passam rc 0.
- **Fail-open:** `MAESTRO_OFF=1` sai 0 na primeira linha; política ilegível degrada para o
  fallback embutido, nunca para "libera tudo".
- **Latência:** o teste de NFR do guard continua dentro do teto calibrado (ordem 016); o
  caminho comum (comando sem forma de escrita) não ganha fork.
- Suíte verde; `doctor` sem mudança de veredito; `habits` dentro da catraca (régua em 6/10 —
  função nova acima de 60 linhas reprova); recibos `order-47` e `suite` no tip exato, árvore
  limpa.

## Turno

- fatia: reprodução vermelha de todas as formas e o desenho da regra, em sandbox
- fim: `bash tests/hooks/test-order-047-bash-self-paths.sh` sai 1 pelos motivos certos, depois 0
- teto: 6
- fora: aplicar o patch (é do Capitão) e qualquer afrouxamento da regra de python/node
- relatório: ENGINEERING_SPEC, "O turno da ordem e o relatório de fim de turno"

> **Execução headless:** a prova é o teste em sandbox, sem humano no laço até a aplicação do
> patch. Nenhuma chamada externa.

## Contrato de execução
- Trabalhe APENAS no branch `order/047-bash-e-python-escrevendo-em-self`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ src/
- Prove com o ledger: `maestro evidence --record --label order-47 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 047` (você não fecha a própria ordem).
accepted_at: 2026-10-02T13:56:26-03:00
accepted_session: desconhecido
accepted_tree: 336989e2ae497205112c7928ca041f8c31eaa8f8
accepted_intent: 6
