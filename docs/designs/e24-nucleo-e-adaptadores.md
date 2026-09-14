# E24 — núcleo, adaptadores e configuração: plano de execução

Planejado pelo arquiteto (opus) em 2026-09-14, por H4: decisão estrutural
crítica no repo que audita os outros. Decisões do supervisor tomadas no gate e
marcadas como **[decidido]** — não se reabrem em execução.

Ordem 006. Direção: INTENT v2, Prioridade 5 ("contexto contido — o Maestro não
pode causar o inchaço que combate").

## O problema real

Não é "`bin/maestro` tem 4380 linhas". É que **a ferramenta que audita os outros
projetos tem um ponto cego sobre si mesma, e ele é estrutural**: o filtro por
extensão (`hooks/post-edit-habits.sh:62-68` e `bin/maestro:3704-3709`, duplicado)
isenta toda uma classe — executável sem extensão. `bin/maestro` é a instância; a
classe é "todo executável POSIX do repo".

Medido em 2026-09-14 contra o épico (2026-09-05):

| arquivo | no épico | hoje | delta |
|---|---|---|---|
| `bin/maestro` | 4043 | 4380 | +337 |
| `hooks/session-start.sh` | 787 | 902 | +115 |
| `src/cli.ts` | 1271 | 1271 | 0 |

As +337 são os patches das ordens 003/004/005 — os consertos da família "prova
que parece prova". Cada conserto honesto engordou o arquivo que o E24 existe
para dividir, e nada acusou.

## Decisões do supervisor [decidido]

1. **Detecção por SHEBANG, não por nome** — corrigir a classe, não a instância.
2. **Dívida DECLARADA com prazo, nunca baseline absorvido.** "O teto desce a
   cada lote que sai, e a conta fica visível."
3. **`lib/` nasce DENYLISTED no Lote 0** (opção A). Razão, do supervisor:
   *"(A) erra para atrito medível e reversível; (B) erra para reescrita
   silenciosa dos comandos que produzem a prova. Janela livre de dias em `bin/`
   e `lib/` é justamente o intervalo em que nada do que se prova vale, e ninguém
   sabe desde quando."* Módulos nascem como ARQUIVO COMPLETO em `docs/patches/`
   — para arquivo novo, o diff É o arquivo.
4. **Um comando por lote, suíte como gate ENTRE lotes.**
5. **`src/cli.ts` é frente separada**; `hooks/` fica fora (NFR de latência).
6. **Prazo da dívida sai da duração MEDIDA do Lote 1**, não de palpite.
7. **Startup declarado `inconclusivo sob carga`** (medições sob load 11,66).
8. **O `doctor` fica fora do split.**

## Invariantes — se um lote precisar de exceção, ele para e volta ao gate

- **I-1** Nenhum caminho absoluto de máquina. Tudo sai de `REPO_DIR`
  (`bin/maestro:23-41`), por causa da migração `rcosta00`→`vulcan` em curso.
- **I-2** Degradação, nunca bloqueio. Módulo ausente derruba o COMANDO com
  `die env` e fix, não o CLI.
- **I-3** `hooks/` continua bash puro e sem dependência de `lib/`.
- **I-4** Vocabulário fechado no log: `file_ext` recebe token de linguagem
  (`sh`), nunca nome de arquivo.
- **I-5** O split não pode reduzir a cobertura de auditoria da instalação (R-2).
- **I-6** Sem float: prazo é epoch inteiro.

## Onde os módulos nascem

`lib/cmd-<comando>.sh` e `lib/core-<área>.sh`, na raiz. O épico já escreveu esse
caminho (EPICS.md:779); `hooks/lib/common.sh` estabelece a convenção. Descartados
com custo declarado: `bin/lib/` (denylist), `cli/` (colide com `src/cli.ts`),
`libexec/` (obscuro), `share/maestro/` (packaging sem ganho), `src/` (denylist +
confusão bash/Bun).

## Resolução em runtime — não há mecanismo novo

`bin/maestro` já sourceia biblioteca relativa a `REPO_DIR` em **14 sítios**.
`REPO_DIR` sai de `maestro_realpath` (`readlink -f` com fallback), escrito para o
caso do symlink em `~/.local/bin`. **Zero fork adicional**; a migração de usuário
é não-evento. Padrão de degradação a copiar: `maestro_verif_load`
(`bin/maestro:2543-2558`) — com `die env` no lugar dos stubs.

Armadilha: `shellcheck -x` não resolve `$REPO_DIR`. A diretiva
`# shellcheck source=lib/cmd-x.sh` é obrigatória, senão o gate passa sem ter
verificado nada.

## O achado que muda o desenho da dívida

**Dividir paga `oversized-file`. NÃO paga `oversized-function`.** Dos 19 achados
do `bin/maestro`, **17 são imunes ao split** — função de 203 linhas continua com
203 depois de mudar de arquivo. E `lib/cmd-order.sh` nasceria com ~587 linhas,
acima do teto: o split ingênuo MOVE a violação.

Portanto o **critério de saída de cada lote** é `maestro habits lib/cmd-<x>.sh`
sair 0 — arquivo ≤400 e nenhuma função >60 —, forçando decomposição por
responsabilidade dentro do lote. É o valor que o épico prometeu; mover blocos de
texto não o entrega.

Estouro de catraca no dia 1, medido: `deep-nesting` 10→11, `oversized-file`
12→13, `oversized-function` 6→**23**.

## Dívida declarada — forma

`.maestro-habits.tsv` ganha colunas 3 e 4, opcionais:

```
# sensor  contagem  vence_epoch  alvo
oversized-function    23    <epoch>    6
```

Linha de 2 colunas lê como hoje (retrocompatível). `habits --all` sai 1 quando
`now > vence_epoch` E `contagem > alvo`, mesmo dentro do baseline — é a única
forma de o prazo ser mecânico. `doctor` avisa a partir de D-14. A coluna 2 desce
a cada lote, no mesmo commit; lote que não desça nada é lote que não fez nada, e
isso fica no diff.

## Riscos e sinais precoces

| # | Risco | Sinal precoce | Retorno barato |
|---|---|---|---|
| R-1 | `lib/` fora da denylist vence o ADR-003 v1.2 por realocação | **Nenhum sinal automático** — por isso (A) o elimina em vez de vigiá-lo | ≤1 lote mesclado |
| R-2 | `check_plugin_install` (`bin/maestro:735-737`) compara lista fixa sem `lib/` → **rollback silencioso** | `test-install-drift.sh` verde depois do Lote 1 É o sintoma | Lote 0, bloqueante |
| R-3 | `covers:` de ARCHITECTURE/API_SPEC não alcança `lib/` | `docs --check` verde num lote que moveu 500 linhas | Lote 0 |
| R-4 | Comando migrado perde global do prelúdio | Teste dedicado — por isso só comandos COM teste próprio nos primeiros lotes | revert do lote |
| R-5 | `shellcheck -x` passa sem seguir o source | Injetar erro de propósito e confirmar reprovação | Lote 0 |
| R-6 | Suíte verde sem exercitar o módulo movido | Quebrar o módulo de propósito e ver se reprova | Lote 1 |
| R-7 | Migração `rcosta00`→`vulcan` quebra a resolução | Teste que invoca por symlink com `$HOME` e diretório diferentes — **não existe hoje** | Lote 0 |

## Sequência de lotes

Critério, em ordem de desempate: **blast radius** > cobertura de teste dedicada >
acoplamento > tamanho. Tamanho é o de MENOR peso, deliberadamente: o primeiro
lote não existe para colher linhas, existe para provar o mecanismo.

O arquivo já está fraturado por banner de seção — as linhas de fratura foram
desenhadas por quem o escreveu, não precisam ser descobertas. É o principal
argumento de que o E24 está maduro.

| Lote | Comando | ~linhas | Por quê |
|---|---|---|---|
| 0 | — mecanismo | 0 | régua e carregador |
| 1 | `telemetry` | 148 | **lote-prova**: teste próprio, opt-in, se quebrar ninguém para |
| 2 | `graph` | 40 | menor, teste próprio |
| 3-5 | `docs`, `conduct`, `delegation` | 150/82/109 | isolados, teste próprio |
| 6 | `consent` | 87 | toca segurança — depois do mecanismo provado 5× |
| 7-8 | `brief`, `habits` | 157/186 | `habits` é o próprio sensor |
| 9-12 | `outcome`+`retro`, `verify`, `evidence`, `intent` | 395/355/227/208 | |
| 13 | `upgrade` | 233 | **penúltimo**: blast radius máximo, falha silenciosa |
| 14 | `order` | 587 | maior e mais acoplado; sai já subdividido |
| 15 | núcleo do `doctor` | 1470 | **frente própria**, não lote — depois de 10+ lotes |

## Gatilho objetivo de reversão do Lote 1 — qualquer um basta

1. o módulo não fica ≤400 com funções ≤60 sem inventar helper sem nome de domínio;
2. a suíte precisa de mais de **duas** alterações de teste (mais que isso é
   mudança de comportamento, não de estrutura);
3. `doctor` muda qualquer veredito;
4. o par de tempo antes/depois de `run-all.sh` sob load ≤2,0 piora.

Reverter o Lote 1 e manter o Lote 0, que tem valor sozinho.

## Lacunas de dado

1. Latência sob load ≤2,0 (tudo foi medido sob 11,66 — `inconclusivo`).
2. Invocações **dinâmicas** do CLI na suíte (82 é contagem estática de sítios).
3. Duração real de um lote ponta a ponta — insumo do prazo, sem amostra hoje.
4. Acoplamento exato de `cmd_order` (inferido por nome, não por grafo de chamadas).
5. Se `check_plugin_install` deve comparar arquivo a arquivo ou hash de diretório.

## Fora do E24

- `git rm` do arquivo espúrio rastreado com nome quebrado — limpeza, commit próprio.
- NFR de latência para o CLI: régua criada depois de conhecer o resultado não é régua.
