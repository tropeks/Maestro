<!-- maestro-order v1
id: 028
ts: 2026-09-19T16:17:03-03:00
epoch: 1789845423
head: a01e9e4e864c55e13d29451ecfbcc7da0bed3ca7
branch: feat/028-prova-de-calibracao-jev
frozen: vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
intent_version: 3
intent_hash: 64b18664
author_session: desconhecido
-->
# Ordem 028 — prova de calibracao do Jev: acerto x confianca por faixa, contra a base rate, antes de dar poder

## Por que esta ordem existe

A direção do Capitão põe o Jev (TypeSafe AI) na routing-table (`Choice` para
intenção → workflow/executor, `Score` com limiar para modelo por complexidade) e nos
graders de eval. O estudo está em `spock:docs/typesafe-ai-estudo.md` e é explícito
sobre o que vem antes: **"calibração é promessa deles; a primeira ordem mede"**.

Esta ordem é essa medição. Nada ganha poder de decidir antes do número.

## O corpus — medido, não suposto

São DOIS, porque respondem perguntas diferentes e nenhum sozinho fecha a questão.

### M1 — telemetria: a confiança separa o que deu certo do que deu errado?

`~/.maestro/logs/routing.jsonl`, 16.219 linhas. Casando cada `outcome` com a
`decision` mais recente da MESMA sessão antes dele, saem **181 pares 1:1**, em **16
projetos**: `accepted` 142, `rework` 36, `killed` 3.

O estado entregue ao Jev é **metadado apenas** — `project`, `workflow`, `mode`,
`agents`, e o contexto de gate da sessão (`tool`, `file_ext`). **Nunca o pedido do
usuário: ele não está no log, por fronteira dura** (*"Logs: só metadados; jamais
prompt"*), e não vai passar a estar para viabilizar esta medição.

A pergunta que este corpus responde é: *dado o metadado da decisão, o Jev prevê o
desfecho, e a confiança dele é calibrada?*

**A TRAVA deste corpus: a base rate é 78,5%** (142/181). Um preditor constante que
sempre diga `accepted` acerta 78,5% e não vale nada. Portanto:

- **Acurácia sem a base rate ao lado é resultado proibido no relatório.**
- O número que decide é a **recall de `rework`** (n=36) — pegar o que deu errado é o
  único uso com valor. Reportar isolada, com o n.
- `killed` (n=3) é pequeno demais para qualquer leitura. Reportar a contagem e
  **não** derivar nada dela.

### M2 — `tests/eval/cases.yaml`: ele roteia como nós?

15 casos com `prompt` verbatim **e** `expected: {workflow, mode, agents}` como rótulo
humano declarado, mais `ambiguous`/`competes`/`rationale` (S-402, `docs/ROUTING_EVAL.md`).
É o único corpus onde a ENTRADA existe, e portanto o único que mede a decisão de
roteamento de verdade.

Concordância por eixo (`workflow`, `mode`, `agents`), reportada **separadamente** —
nunca uma nota só. Com n=15 a curva de calibração por faixa é **indicativa, não
conclusiva**, e o relatório diz isso na mesma linha do número.

**Os `ambiguous: true` vão num bloco à parte.** São onde duas rotas competem de
verdade; confiança ALTA num caso ambíguo é excesso de confiança e mata o uso da
confiança como limiar. É o sinal mais informativo que este experimento produz.

## A chave

`~/.config/vulcan/typesafe.key` (600). **Só por variável de ambiente, em tempo de
execução.** Nunca em arquivo de config, nunca em log, nunca na saída, nunca no TSV,
nunca no relatório, nunca em mensagem de erro. O script lê a variável; quem exporta é
quem roda. Se a variável não estiver setada: **skip honesto, exit 0**, dizendo que
falta a chave — suíte nunca reprova por ausência de credencial de terceiro
(Prioridades §1). O `.gitignore` cobre qualquer artefato bruto de resposta.

## Prova exigida

- Script em `tests/eval/`, **sem efeito**: não grava record, não chama `maestro
  decide`, não escreve em `~/.maestro/`. Lê, chama, imprime TSV.
- M1 e M2 rodam separados e reportam separados. Juntar as duas num número só é recusa.
- Tabela de calibração: faixa de confiança × acerto observado × **n da faixa**. Faixa
  com n < 10 sai marcada como não-conclusiva, no próprio TSV.
- **Custo real em centavos inteiros**, medido na resposta da API, nunca estimado.
- Nenhum limiar é escrito em lugar nenhum nesta ordem. Limiar entra depois, por
  decisão do Capitão, com o número desta ordem na mão.
- Suíte completa verde; `doctor` sem mudança de veredito.
- Se NÃO calibrar: arquiva-se **com o número**. Resultado negativo medido é desfecho,
  não fracasso (E25).

## O que esta ordem NÃO faz

**Não liga o Jev em runtime.** Routing por `Choice` durante a sessão colide com
*"Nenhuma dependência de rede em runtime, exceto o fetch do auto-update (E19)"* —
INTENT v3 **Limites**, e CLAUDE.md "Proibido". A leitura é discutível (quem chamaria
seria a sessão, não o hook), e é por ser discutível que não se resolve aqui: limite do
INTENT se emenda no INTENT, pelo Capitão, no mesmo changeset. Esta ordem produz o
número que torna essa conversa possível.

Graders de eval por `Score` (encaixe (b) do estudo) **não** têm esse conflito — eval é
lote, e lote é o regime que Prioridades §6 prescreve. Entra como ordem própria depois
desta, se o número permitir.

Congelado: `config/routing-table.yaml`, `hooks/`, `bin/`, `src/`, `lib/`, `agents/`,
`vendor/`. Nada de produção muda. O experimento vive inteiro em `tests/eval/`.

## Contrato de execução
- Trabalhe APENAS no branch `feat/028-prova-de-calibracao-jev`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml hooks/ bin/ src/ lib/
- Prove com o ledger: `maestro evidence --record --label order-28 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v3 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 028` (você não fecha a própria ordem).
