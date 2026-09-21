<!-- maestro-order v1
id: 038
ts: 2026-09-21T00:43:42-03:00
epoch: 1789962222
head: c3993f9e697352f42d00e4ccb128e4bd5001cdea
branch: fix/038-aguardo-rodada-corrente
frozen: vendor/ agents/ config/routing-table.yaml bin/ src/
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
-->
# Ordem 038 — detector de aguardo varre o transcrito inteiro: falso positivo de rodada antiga

## O sintoma, reproduzido

Relato do gerente do `gitorch`: o hook que detecta `[spock] aguardando:` dispara em falso
— parece varrer o transcrito inteiro em vez da rodada corrente.

Reproduzido na mão, com transcrito sintético de 14 mensagens (2.975 bytes) em que a linha
canônica aparece SÓ na segunda mensagem, doze mensagens atrás, e a rodada corrente não
tem pergunta nenhuma:

```
$ printf '{"session_id":"repro-038","transcript_path":"…","stop_hook_active":false}' \
    | bash hooks/gate-report.sh
{"decision":"block","reason":"maestro: a rodada terminou com uma pergunta pendente …"}
```

Bloqueou. A rodada corrente não pedia nada.

## A causa-raiz

`hooks/gate-report.sh:253`:

    tail_txt=$(tail -c 8192 -- "$tpath" 2>/dev/null) || tail_txt=""

A janela é de BYTES, não de rodada: 8 KB de transcrito cobrem muitas rodadas. Qualquer
`[spock] aguardando:` que tenha passado por ali — de uma rodada antiga, de uma citação do
humano, de um relatório que descreva o mecanismo — continua dentro da janela e re-dispara.

A ordem 029 já tinha fechado UM caminho desse defeito (a razão emitida pelo hook não
transcreve mais o marcador, porque ela ia para o transcrito e a rodada seguinte a
encontrava). O caminho geral ficou aberto: **qualquer** ocorrência antiga serve.

## O que entra

O detector passa a olhar **só a rodada corrente**. O transcrito é JSONL, uma mensagem por
linha; a rodada corrente é a ÚLTIMA mensagem do assistente. Da janela lida, o hook usa
apenas a última linha de assistente e casa os dois regexes só nela.

Efeitos que vêm junto, e são desejados:

- Citação do humano deixa de disparar: mensagem de usuário não é mais examinada.
- Linhas de metadado no fim do arquivo (`last-prompt`, `ai-title`, …) deixam de importar.
- Sem linha de assistente na janela, o hook **não bloqueia** — degrada em silêncio, porque
  não dá para afirmar que há pergunta pendente (Prioridade 1).

Limites: `hooks/` é bash puro — sem `jq`, sem parser de JSON, sem rede. A janela continua
limitada (`tail -c`), e nenhum regex com `{1,N}` grande entra (issue #42: `{1,4096}` mediu
~2,7 s nesta forge contra ~7 ms de `+`). NFR de 50 ms por invocação mantido e medido.

## Nota sobre o `papercut --add`

O mesmo relato diz que `maestro papercut --add` recusou por falta de `--fix`. **Isso não é
defeito**: a recusa é por desenho — *"sintoma sem conserto conhecido não é papercut: é
investigação em aberto — abra uma issue"* — e a mensagem já diz o que fazer. Bati na mesma
recusa hoje e o contorno foi escrever o conserto junto. Fica registrado aqui para não virar
ordem por engano; se o Capitão quiser que `--add` aceite sintoma sem conserto, é decisão de
produto e vira ordem própria.

## Prova exigida

- **O caso reproduzido vira teste**: transcrito com a canônica só numa rodada ANTIGA e
  rodada corrente limpa → o hook NÃO bloqueia.
- Canônica na rodada corrente → bloqueia (não-regressão do mecanismo da 029).
- Paráfrase na rodada corrente → o caminho de reprovação da 029 continua valendo.
- Canônica só numa mensagem de USUÁRIO → não bloqueia.
- Sem linha de assistente na janela → não bloqueia.
- Latência do hook medida e dentro do NFR de 50 ms.
- Suíte verde; `doctor` sem mudança de veredito; habits dentro da catraca.

## Contrato de execução
- Trabalhe APENAS no branch `fix/038-aguardo-rodada-corrente`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml bin/ src/
- Prove com o ledger: `maestro evidence --record --label order-38 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 038` (você não fecha a própria ordem).
accepted_at: 2026-09-21T01:07:56-03:00
accepted_session: desconhecido
accepted_tree: 5b119b7beef8f8a4af419cdcce6f02a1d8e19524
accepted_intent: 4
