<!-- maestro-order v1
id: 086
ts: 2026-11-19T19:32:17-03:00
epoch: 1795127537
head: f6f1c342bd45a3e2477732ccba2d7ae96c8f1ca0
branch: order/086-guarda-le-anexos-da-ponte-em-pon
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 086 — guarda le anexos da Ponte em ~/.ponte/media



## Origem
Capitão, 19/11/2026, no grupo do Telegram: "Muda o acesso da pasta de upload do telegram, N faz sentido ter a pasta e n ter acesso". O ponte-daemon salva os anexos do Capitão e do sócio em `~/.ponte/media/AAAA-MM/`. O maestro-guard nega a leitura de todo caminho com `.ponte` (`mods/maestro-guard/hooks/secrets.ts`, `isSecretPath`), e o Spock não lê o PDF que o sócio mandou. Hoje, só um `cp` manual do Capitão libera.

## Fatos
- `isSecretPath` nega todo caminho cujas partes incluam `.ssh` ou `.ponte`, e vale para Read, Grep, Glob e para os leitores de shell (`secretReader`).
- `~/.ponte/` guarda tokens, `.env`, `*.conf` e o banco da Ponte: o resto continua fechado.
- O corpus fixa `~/.ponte/token`, `~/.ponte` (Grep) e `~/.ponte/daemon.log` como `deny` (`mods/maestro-guard/tests/corpus.ts:137,145,157`; `corpus-revisao.ts:12`).
- `maestro consent` não tem escopo para isso (`routing-table`, `roster`, `ops`).

## Direção
Os anexos do Telegram são insumo de trabalho do Diretor, não segredo. Abrir só `~/.ponte/media/**`, e nada mais de `~/.ponte/`.

## Decisões
1. Em `isSecretPath`, um caminho com `.ponte` deixa de ser segredo só quando a parte seguinte a `.ponte` é exatamente `media`, há pelo menos um componente depois dela e nenhum componente é `..`. Os testes de `.env`, chave, `.credentials` e certificado continuam valendo dentro de `media`: um `.env` ou `.pem` enviado pelo Telegram segue negado.
2. Glob que alcança `~/.ponte` fora de `media` (`~/.ponte/*`, `~/.ponte/**`, `~/.ponte/{media,token}`) continua negado.
3. Corpus novo: `pass` (o mod não emite `allow`) para Read de `~/.ponte/media/2026-11/x.pdf` e `cat ~/.ponte/media/2026-11/x.pdf`. `deny` para `~/.ponte/media/../token`, `~/.ponte/media` sem arquivo, `~/.ponte/mediax/a`, `~/.ponte/*`, `~/.ponte/media/2026-11/.env` e `~/.ponte/media/a/chave.pem`. Os `deny` de hoje ficam como estão.

## Rollback
Reverter o commit da ordem: volta a negar `~/.ponte` inteiro.

## Critérios
- [ ] `bash tests/run-all.sh` sai 0 no tip, com recibo `order-86`.
- [ ] Os casos da decisão 3 estão no corpus e passam.
- [ ] Nenhum `deny` existente do corpus mudou de resultado.
- [ ] O diff só toca `mods/maestro-guard/` e esta ordem.

## Turno
- ESTADO: turno 1 deixou `secrets.ts` e `corpus.ts` mudados e sem commit. No host, `claude plugin test mods/maestro-guard` deu 32 pass e 1 fail: o mod nunca emite `allow`, e os dois casos `~/.ponte/media/2026-11/x.pdf` (Read e `cat`) estão com `allow`. Erro do texto da ordem, não do código.
- fatia (turno 2): mover esses dois casos para a lista que passa, com `want` `pass`, como `rm -rf node_modules`; `claude plugin test mods/maestro-guard` verde; commit no branch da ordem
- fim: `bash tests/run-all.sh` sai 0 no tip do branch, com o recibo `order-86` gravado
- teto: 3
- fora: abrir qualquer outro caminho de `~/.ponte/`; mexer em `.ssh` ou nos outros testes de segredo; `bin/`, `hooks/` e `agents/`; push (é do Diretor); escrita fora do worktree
- relatório: pela Ponte (`director_report`), formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run, /tmp/claude-<uid>/<cwd codificado>, nunca /tmp solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera por laço até a linha rc= no log; só depois se relata.

## Contrato de execução
- Trabalhe APENAS no branch `order/086-guarda-le-anexos-da-ponte-em-pon`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-86 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 086` (você não fecha a própria ordem).
accepted_at: 2026-11-19T20:34:00-03:00
accepted_session: desconhecido
accepted_tree: e46b89402a514a7129548d8b0dccc8acf10f232f
accepted_intent: 6
