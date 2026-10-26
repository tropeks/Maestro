<!-- maestro-order v1
id: 085
ts: 2026-10-26T13:12:40-03:00
epoch: 1793031160
head: a50fe3973c66439fc3fe8258b5a03c998f4ebc45
branch: order/085-condicao-verificavel-libera
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 085 — condição verificável libera a edição (CONTRATO v3)

> Ordem do Spock, 26/10/2026, por decisão do Capitão (Ponte `01M5WFFMHCEYVMSZTFWRDPS18N`, "aprovo"): `tropeks/spock:docs/diretoria/CONTRATO.md` v3. Hoje `approved_with_conditions` nunca libera o gate `domain` (`hooks/pre-tool-gate.sh:775`, `hooks/lib/domain-record.sh:25,63`), e trabalho legítimo de auth e deploy trava: a ordem 131 do NetForge (10 rodadas) e a 014 do SmartQuotation.

## Direção que autoriza

- `spock:docs/diretoria/CONTRATO.md` v3, tabela das respostas: na edição de arquivo (gate `domain`), `approved_with_conditions` libera quando **toda** condição traz `check_ref`; cada condição vira critério obrigatório do aceite da ordem, conferido pelo Diretor com recibo. Condição com `check_ref: null` não libera. Ação operacional com condição segue sem executar.

## Decisões

1. **Gate (`pre-tool-gate.sh` e `domain-record.sh`):** decisão `approved_with_conditions` vinda pela Ponte (`via=ponte`), não revogada, não vencida, com todas as `conditions[].check_ref` não nulas, conta como liberação do domínio, como `approved`. Com qualquer `check_ref: null`, segue `pending`, como hoje. Manual (`via=manual`) segue não liberando.
2. **Condições no aceite:** `maestro order --accept N` de uma ordem cujo record tem decisão liberada por condição lista as condições e só aceita com a flag nova `--condicoes-conferidas`. Sem ela, recusa com a lista. O aceite grava as condições conferidas no carimbo (`accepted_conditions:`), só `texto` e `check_ref`.
3. **Testes:** (a) todas com `check_ref` liberam; (b) uma `null` não libera; (c) revogada ou vencida não libera; (d) manual não libera; (e) o aceite sem a flag recusa e lista; (f) com a flag aceita e grava. Mais um caso com `approved` puro, que continua igual.

## Critérios de aceite
- [oráculo: `bash tests/run-all.sh`] suíte do Maestro verde, com os testes novos.

## Adendo da rodada 2 (Diretor, 26/10): o recibo no host reprovou

O código da rodada 1 está commitado (`ordem 085: condicao verificavel libera...`). O `bash tests/run-all.sh` no host saiu `rc=1` por dois motivos, nenhum de lógica:

1. **Patch da 084 não aplica mais:** o teste da 084 aplica `docs/patches/084-revisao-fria-roteamento.patch` numa cópia, e o patch toca `lib/cmd-order.sh` e `lib/cmd-order-accept.sh`, que esta ordem mudou ("fixture: patch 084 não aplicou na cópia"). Regere o patch da 084 sobre os arquivos atuais, sem mudar o que ele faz, e confira que o teste da 084 volta a passar.
2. **Catraca do `habits`:** "oversized-function: 7 > baseline 6". A função que cresceu é a do aceite. Quebre em função menor, sem subir o baseline.

Rode `bash tests/run-all.sh` inteiro no tip e commite com `git -c user.name=gerente-maestro -c user.email=gerente@vulcan.dev.br commit`.

## Turno
- fatia: as decisões 1 a 3
- fim: `bash tests/run-all.sh` sai 0 no tip do branch, com o recibo `order-85` gravado
- teto: 3
- fora: mudar o significado das outras respostas; o caminho manual; `bin/`, `hooks/` e `agents/` só por patch em `docs/patches/` se a autoproteção barrar a edição; push (é do Diretor); escrita fora do worktree
- relatório: pela Ponte (`director_report`), formato fixo da v54: de pé com evidência · aberto · decisão pedida · próximo turno sugerido, com o que o Capitão aplica pelo botão se sair patch

> **Log e escrita:** log de suíte e saída de espera vão para a pasta temporária do próprio run, /tmp/claude-<uid>/<cwd codificado>, nunca /tmp solto; escrita só com Edit ou Write.

> **Headless:** nunca encerre a resposta esperando uma notificação. Suíte em segundo plano se espera por laço até a linha rc= no log; só depois se relata.

## Contrato de execução
- Trabalhe APENAS no branch `order/085-condicao-verificavel-libera`; NUNCA no main/master.
- Prove com o ledger: `maestro evidence --record --label order-85 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 085` (você não fecha a própria ordem).
accepted_at: 2026-10-26T17:44:16-03:00
accepted_session: desconhecido
accepted_tree: a3f48fe64602a5a2bda240350fb9c3ce817024d9
accepted_intent: 6
