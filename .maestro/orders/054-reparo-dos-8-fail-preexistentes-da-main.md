<!-- maestro-order v1
id: 054
ts: 2026-10-03T13:43:21-03:00
epoch: 1791045801
head: 41213f0a454bd6c2060d9faa41f91e36ad450047
branch: order/054-reparo-dos-8-fail-preexistentes-da-main
frozen: vendor/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 054 — reparo: 8 FAIL pré-existentes na suíte da main (test-order-029-gatilho e test-order-038-rodada-corrente)

## Por quê

O turno da 049 rodou a suíte completa da `main` (41213f0) e achou **8 FAIL pré-existentes** em
`tests/hooks/test-order-029-gatilho.sh` e `tests/hooks/test-order-038-rodada-corrente.sh`. Nenhum vem
da 049. Enquanto existirem, nenhuma ordem fecha com `SUITE OK` e o recibo `suite` fica indecidível:
toda ordem nova herda o vermelho.

**Observação do Capitão em 03/10, antes desta ordem:** os dois arquivos, rodados **isolados** numa
sessão interativa (load ~6), saem **rc 0** — 029 com 18 ok, 038 com 6 ok. Logo o defeito não é
"o teste está errado" por padrão: é diferença de **contexto** entre a corrida que falhou (turno
headless da 049, suíte completa) e esta. Esta ordem existe para achar essa diferença.

## O que entrega

1. **Diagnóstico por evidência**, antes de qualquer edição: reproduzir os 8 FAIL (suíte completa
   no tip da `main` e, se preciso, no ambiente de turno headless — `claude -p`, sem TTY, com as
   variáveis `CLAUDE_*` do headless) e **colar a saída exata** de cada FAIL. Para cada um, a causa
   raiz com a prova de que é ela. Hipóteses a testar, não a assumir: (a) dependência de ordem ou de
   estado deixado por teste anterior na suíte; (b) variáveis de ambiente do headless
   (`CLAUDE_CODE_*`, `MAESTRO_*`, ausência de TTY/`HOME`); (c) a carga (038 mede latência — o
   portão de `tests/lib/latency.sh` deve dar inconclusivo, não FAIL); (d) o gatilho do 029 e a
   rodada corrente do 038 dependendo de transcrito/sessão do harness que o sandbox não isola.
2. **Correção** de cada FAIL conforme a causa:
   - defeito do **teste** (acoplamento a ambiente, ao relógio, à carga, a ordem de execução):
     conserta o teste e isola o ambiente com `tests/lib/env-clean.sh` e o portão de latência;
   - defeito do **código** que o teste expôs: só com prova — teste vermelho que isola o
     comportamento, o antes e o depois colados. **Sem prova, o comportamento não muda.**
3. Cada FAIL fecha com um teste que **falha antes e passa depois** no contexto que o reproduzia, ou,
   se for estritamente de ambiente, com o isolamento que o torna determinístico.

## Ask-First

- Se a causa for comportamento do hook/CLI (não do teste), PARE e reporte com a prova antes de mexer.
- Se corrigir exigir afrouxar uma asserção, PARE: o afrouxamento é decisão do Diretor.
- Se o conserto tocar `hooks/`, `bin/`, `src/`, `lib/` (autoprotegidos), PARE e diga qual linha e por quê;
  sai como patch em `docs/patches/054-*.patch`, feito em clone sandbox FORA do repo, aplicado pelo Capitão.
- Se algum FAIL não reproduzir em nenhum contexto, reporte como "não reproduzido" com as corridas
  tentadas — não declare consertado o que não viu falhar.

## Como sai

`tests/` e `docs/` direto no branch. Arquivo protegido, se houver, em UM patch. Emenda no mesmo
changeset: CHANGELOG (Fixed) e, se a causa for método (ex.: teste dependente de ordem), uma linha no
ENGINEERING_SPEC. Um papercut em `maestro papercut --add` se a causa for uma armadilha de ambiente.

## Prova exigida

- Saída colada dos 8 FAIL **antes** (contexto que reproduz) e da suíte **depois**: 0 FAIL desses dois
  arquivos, no mesmo contexto.
- Suíte completa `SUITE OK` no tip, sozinha no worktree (duas suítes no mesmo worktree se
  contaminam — `test-order-041` troca `config/accept-proof.pub`).
- Recibos `order-54` **e** `suite` (rótulo legado: a CLI da frota só lê `suite` até a 1.21 girar) no
  tip exato, árvore limpa; `habits` dentro da catraca.

## Turno

- fatia: reproduzir os 8 FAIL com saída colada e achar a causa raiz de cada um (diagnóstico)
- fim: relatório com causa e prova por FAIL; depois da correção, `bash tests/run-all.sh` sai 0 sem FAIL em 029 e 038
- teto: 4
- fora: mudar comportamento de hook ou CLI sem teste vermelho que o isole, afrouxar asserção, aceitar a ordem, qualquer ordem além da 054
- relatório: formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Execução headless:** cada turno é um `claude -p` novo que lê só a direção do turno, o brief e o INTENT. Travou: parar e relatar.

## Contrato de execução
- Trabalhe APENAS no branch `order/054-reparo-dos-8-fail-preexistentes-da-main`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/
- Prove com o ledger: `maestro evidence --record --label order-54 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 054` (você não fecha a própria ordem).
