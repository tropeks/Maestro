<!-- maestro-order v1
id: 011
ts: 2026-09-15T16:43:52-03:00
epoch: 1789501432
head: e24243517808485bcb50f5060a4590ca9e90808d
branch: refactor/011-e24-verify
frozen: vendor/ agents/ config/routing-table.yaml
intent_version: 2
intent_hash: b1b21050
author_session: c63227f9-8cee-4c01-965f-10182f66b500
absorbed_by: main
absorbed_tree: 92e7417e6c8b191eaa913bdc3c1c485ef2ed2fee
absorbed_at: 2026-09-15T18:19:11-03:00
absorbed_session: desconhecido
-->
# Ordem 011 — E24 ordem B: verify e verificacoes por area — o acoplamento que a ordem A parou para nao cortar



## Contrato de execução
- Trabalhe APENAS no branch `refactor/011-e24-verify`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml
- Prove com o ledger: `maestro evidence --record --label order-11 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v2 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 011` (você não fecha a própria ordem).

## Por que esta ordem existe

INTENT v2, Prioridade 5. **Esta ordem existe porque a ordem A parou.**

Ao decompor `verificações por área`, o executor da 010 encontrou acoplamento não
mapeado, reverteu byte a byte e chamou em vez de resolver no meio do corte. Esta
ordem trata esse acoplamento como ALVO EXPLÍCITO, com o desenho decidido pelo
humano — que era exatamente o que faltava.

Alvos: `verify` (E23b, 75 linhas) e `verificações por área` (E23b, 55).

## O acoplamento, já mapeado pela ordem A

`maestro_verif_load`, `verif_base_ref`, `verif_required` e `verif_record_hint`
sempre foram **residentes incondicionais** de `bin/maestro`. E são chamadas de
fora desta família, por módulos que JÁ SAÍRAM:

- `lib/cmd-evidence.sh`
- `lib/core-order-state.sh`
- `lib/cmd-order.sh`

Eles chamam **assumindo que já estão carregadas**, sem loader.

Mover para módulo lazy-loaded sem resolver isso quebra `evidence` e `order`
sempre que chamados sem `verify` ter carregado antes. A suíte da ordem A provou
ao vivo, e o modo de falha é o pior possível:

```
lib/cmd-evidence.sh: line 38: maestro_verif_load: command not found
```

**mascarado por `>/dev/null 2>&1`.** Falha silenciosa num caminho que produz
prova.

**A decisão de desenho é do humano e precisa sair ANTES do corte.** Duas formas
plausíveis, e a escolha não é do executor:
- um `_verif_lib_load` idempotente chamado por cada consumidor, como os outros
  carregadores já fazem;
- o núcleo de verificação vira dependência carregada pelo despachante antes de
  qualquer comando, deixando de ser lazy.

## TRAVA DE CONTRATO — a mesma da ordem A, e aqui ela pesa mais

Palavras do supervisor: *"verify é o que decide se uma ordem pode ser aceita em
cinco repositórios. Mover o código é seu; mudar o que conta como verificação
aprovada, o nome de um rótulo, ou o que um projeto precisa declarar para passar,
é meu, e você para antes."*

Sob a trava, nomeado:

1. **O que conta como verificação APROVADA** — a regra que decide se um recibo
   satisfaz uma área declarada.
2. **Nome de rótulo** (`labels:`) — outros projetos declaram os seus, e
   `suite` é o do Maestro. Renomear, acrescentar ou remover é contrato.
3. **O que um projeto precisa declarar para passar** — a forma do bloco
   `verifications:` no `.maestro.yaml`: `paths:`, `labels:`, `commands:`.
4. **A mensagem de recusa** do `verify --check`: outros projetos e o supervisor
   leem esse texto para saber o que falta.

Reordenar, renomear função interna, mover bloco: seu. Mudar regra, rótulo,
forma do bloco ou texto de recusa: dele. **Na dúvida, pare — é exatamente a
dúvida que a trava existe para capturar.**

## Consequência de cruzar trava procedimental

Vale desde a ordem 010: **executor que cruzar uma trava — por melhor que seja o
resultado — faz a medição do lote ser marcada como CONTAMINADA, e o lote não
conta na descida da régua nem na cadência do prazo.**

Trabalho correto não é desfeito; desfazer para provar ponto é teatro. O custo é
na moeda que o E24 otimiza.

Precedente: a ordem 009 cruzou, o trabalho ficou, e a descida de
`oversized-function` 22→19 não foi aplicada. A ordem 010 **respeitou** a trava —
parou, reverteu, chamou — e é por isso que esta ordem existe com desenho humano
em vez de um conserto improvisado no meio do corte.

## A DECISÃO DE DESENHO — tomada pelo supervisor, com condição

**Opção (1): carregador idempotente por consumidor.** Consistente com
`_order_lib_load`, `_ev_lib_load`, `_habits_lib_load`.

**A (2) foi RECUSADA, e o motivo é método:** carregar o núcleo sempre paga custo
fixo em toda invocação, e o número que justificaria esse custo NÃO EXISTE — a
medição de startup saiu `inconclusiva sob carga 11,66` e foi declarada assim.
*"Escolher a opção mais cara com base num custo não medido é palpite com
aparência de prudência."*

**A (1) entra JUNTO com a guarda que torna a falha dela detectável.** Isto não é
acessório: é a condição que muda a natureza da escolha. Palavras do supervisor:
*"o problema da (1) não é o desenho, é que a falha é silenciosa — consumidor
esquece o carregador e a função some num caminho que raramente roda. A cura de
falha silenciosa é detecção."*

### A guarda, e ela é entregável desta ordem

**Obrigatória — teste de execução isolada.** Cada comando exercitado num
processo LIMPO, com stderr CAPTURADO (nunca `>/dev/null 2>&1`), reprovando se
aparecer `command not found`. Isso pega a CLASSE inteira, não só o `verif`: foi
o modo de falha dos bugs das ordens 009 e 010, nas duas.

**Desejável — checagem estática.** Todo `lib/*.sh` que usa `maestro_verif_*`
tem de chamar o carregador. Um grep cruzado basta; se não for confiável, diga e
fique só com a de execução.

**Sinal de desenho errado:** se escrever a guarda se revelar DIFÍCIL, isso é
informação sobre o desenho, não sobre a guarda. **PARE e reporte antes de
seguir** — dificuldade em provar é sinal de que a (1) está errada.

## Travas herdadas
- Gatilho de reversão: DUAS alterações de teste no TOTAL DA ORDEM.
- Acoplamento não mapeado ALÉM do já descrito: PARE e reporte antes de cortar.
- Qualquer mudança de veredito do `maestro doctor`.
- Critério de saída: `maestro habits` limpo em CADA módulo, medido um a um.

## Contrato de execução
- Trabalhe APENAS no branch `refactor/011-e24-verify`; NUNCA no main.
- Zonas CONGELADAS: vendor/ agents/ config/routing-table.yaml
- `bin/`, `hooks/`, `src/` e `lib/` não se editam: patch em `docs/patches/`.
- Convenção: parâmetro posicional, nenhuma função fechando sobre local de outra.
- `declare -g` para estado global de módulo sourceado de dentro de função.
- Tab não serve como separador multivalor: `read` o trata como IFS whitespace.
  Use `\x1f`.
- **Vigie `>/dev/null 2>&1` mascarando `command not found`** — foi o modo de
  falha dos bugs das ordens 009 e 010, nas duas.
- Cópia patchada com `git clone`, nunca `git archive`.
- Prove com o ledger: `maestro evidence --record --label order-11 -- bash tests/run-all.sh`.
- Direção vigente: INTENT v2, Prioridade 5.
- Registre a HORA DE CHEGADA.
