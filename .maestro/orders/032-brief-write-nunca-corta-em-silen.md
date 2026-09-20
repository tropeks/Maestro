<!-- maestro-order v1
id: 032
ts: 2026-09-20T00:07:36-03:00
epoch: 1789873656
head: 3b1c256a772cc5dc90dc47f543e2bab2b83fbb0a
branch: fix/032-brief-sem-corte-silencioso
frozen: vendor/ agents/ config/routing-table.yaml hooks/
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
absorbed_by: main
absorbed_tree: 49b64852966e043fdb36231026db8ec070b318ed
absorbed_at: 2026-09-20T01:46:29-03:00
absorbed_session: desconhecido
-->
# Ordem 032 — brief --write nunca corta em silencio: teto de 64 KiB e erro explicito acima dele

## Por que esta ordem existe

Issue #43, medida duas vezes hoje na mão do Vitali: um brief de 26–29 KB passado por
`--file` foi gravado com ~16,5 KB, **cortado no meio de uma palavra, sem um aviso**.
O comando reportou sucesso. 44% da entrada desapareceu.

A causa é de duas linhas — `lib/cmd-brief.sh:44` e `:48`:

```bash
narrative=$(head -c 16384 -- "$file")   # --file
narrative=$(head -c 16384)              # stdin
```

`head -c` corta em BYTES e não compara nada: o código não sabe que truncou, então não
tem como avisar.

O dano não é o tamanho, é ONDE ele cai. O brief é a arma contra o cold start, e o que
some é o FIM do arquivo — "próximo passo", "issues abertas", "armadilhas". A sessão
seguinte não perde só contexto: ela não tem como saber que ele existiu. E a última
seção sobrevivente fica mutilada, podendo afirmar o contrário do que dizia.

## O que entra

Decisão do Capitão (2026-09-20), e ela fecha a pergunta em aberto da issue:

- **Teto de 64 KiB** (65536 bytes) para a narrativa, nos DOIS caminhos (`--file` e
  stdin). O teto do brief não é o orçamento da injeção do SessionStart (~8 KB com
  catraca): o brief é lido sob demanda, e teto maior não custa contexto por sessão.
- **Acima do teto: erro explícito, com número** — quanto entrou, qual o teto, quanto
  passou. `die validation`, rc≠0, NADA gravado. O brief antigo fica intacto.
- **Nunca corte silencioso.** Truncar deixa de ser um desfecho possível: ou grava
  inteiro, ou recusa dizendo por quê. Não existe caminho em que o comando reporte
  sucesso tendo perdido byte.

## Limites duros

- `hooks/` congelado: esta ordem é de `lib/`, e nada aqui roda em hook.
- A leitura não pode carregar o arquivo inteiro para decidir: medir o tamanho é
  `wc -c` (ou ler teto+1 e ver se sobrou byte), não `$(cat)`.
- A mensagem de erro cita tamanho e teto em BYTES inteiros — sem float, sem "≈".
- `--auto` não muda: o esqueleto é gerado, não lido.
- Prioridade 1 vale: o brief que já está em disco nunca é danificado por uma recusa.

## Prova exigida

- **Brief de 34 KB grava INTEIRO** (o caso do Capitão): a última linha do arquivo
  gravado é a última linha da entrada, byte a byte. Vale por `--file` e por stdin.
- Entrada acima de 64 KiB → rc≠0, mensagem com os três números, e o arquivo de brief
  anterior **inalterado** (compara sha256 antes e depois).
- Entrada de 16 KB (abaixo do teto antigo) continua gravando igual — sem regressão.
- `maestro brief` (leitura) devolve o conteúdo completo do brief de 34 KB, incluindo
  a última seção — a perda era invisível justamente na leitura.
- Suíte verde; `doctor` sem mudança de veredito; catraca de habits dentro do baseline.

## Contrato de execução
- Trabalhe APENAS no branch `fix/032-brief-sem-corte-silencioso`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml hooks/
- Prove com o ledger: `maestro evidence --record --label order-32 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 032` (você não fecha a própria ordem).
