<!-- maestro-order v1
id: 031
ts: 2026-09-19T20:26:18-03:00
epoch: 1789860378
head: 441d719fcbae793895c663c452d8cdeb112861e6
branch: feat/031-eval-sobre-log-real
frozen: vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 031 — o numero da S-402 medido no LOG real: o eval cego sai de prescrito para observado

## Por que esta ordem existe

O README publica: *"took routing accuracy from 73% to 100% (15/15, two independent
judges)"*, e o Resultado do INTENT repete. O `docs/ROUTING_EVAL.md` registra a
ressalva que ninguém lê junto:

> **"O número que vale ainda não existe.** A AC da S-402 diz *medido no log*. O
> instrumento (C) lê `~/.maestro/logs/routing.jsonl`, que está **vazio** — o plugin
> foi instalado no mesmo dia. Tudo acima é roteamento **prescrito**, não
> **observado**. A validação de campo é a primeira semana de dogfood."

O log não está mais vazio. Medido hoje: **481 decisões, 16 projetos, janela de 30
dias**, com desfecho registrado em 181 delas (`accepted` 142 · `rework` 36 ·
`killed` 3). A primeira semana de dogfood aconteceu. A validação de campo que o doc
diz faltar é executável agora, e é esta ordem.

## O que entra

Rodar o **instrumento (C)** de `tests/eval/` sobre o log real e publicar o número
com as ressalvas que o próprio doc já escreveu.

O que o número precisa carregar para não repetir o erro atual:

- **A base rate ao lado.** `accepted` é 78,5% dos 181 pares com desfecho. Um preditor
  constante acerta isso. Acurácia sem a base rate é resultado proibido no relatório.
- **O n de cada faixa.** Faixa com n pequeno sai marcada como não-conclusiva no
  próprio TSV, não numa nota de rodapé.
- **A distinção prescrito × observado**, explícita, para os dois números conviverem
  sem um se passar pelo outro.

## O que esta ordem CORRIGE, além de medir

O README e o Resultado do INTENT afirmam 100% sem a ressalva. Não é mentira — é o
melhor de seis rodadas contra os MESMOS 15 casos, e o sobreajuste está registrado
como ressalva 1 do próprio doc. Mas publicado sem a ressalva, o número promete mais
do que a evidência entrega. **O texto do README e do INTENT sai corrigido no mesmo
changeset**, com o número prescrito E o observado.

## Limites duros

- **Sem efeito**: o instrumento LÊ o log, não escreve record, não chama `maestro
  decide`, não toca `~/.maestro/` além da leitura.
- Congelado: `hooks/`, `bin/`, `src/`, `lib/`, `config/routing-table.yaml`. Esta
  ordem não muda roteamento — ela o MEDE. Mudar a tabela por causa do número é outra
  ordem, e só depois de ler este.
- O log tem só metadados, por fronteira dura. O instrumento (C) mede o que o log
  permite — concordância entre decisão registrada e o que a tabela prescreveria — e
  **diz o que NÃO consegue medir** em vez de estimar.

## Prova exigida

- TSV de veredito em `tests/eval/`, com n por faixa e a base rate impressa.
- Relatório em `docs/ROUTING_EVAL.md`: seção nova com o número OBSERVADO, ao lado do
  prescrito, e a ressalva 3 atualizada (ela diz "o log está vazio" — não está mais).
- README e `.maestro/INTENT.md` corrigidos no MESMO changeset.
- Roda sem rede e sem chave de terceiro: se o instrumento exigir juiz LLM, ele
  **pula com honestidade** (exit 0, dizendo o que faltou) em vez de reprovar a suíte.
- Suíte verde; `doctor` sem mudança de veredito.

## Contrato de execução
- Trabalhe APENAS no branch `feat/031-eval-sobre-log-real`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
- Prove com o ledger: `maestro evidence --record --label order-31 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 031` (você não fecha a própria ordem).
