# Ordem 078 — proposta de (i) e (ii) do Ask-First 1 (turno 1: só propõe, não implementa)

Direção: INTENT v6, fase S0 de segurança (ordem do Capitão de 10/10). Decisão já tomada pelo Spock: vale o `fim:` do
**commit do despacho**; mudança posterior só com **confirmação do Diretor, registrada**. Falta desenhar onde o `fim:` do
despacho fica e como a confirmação é registrada. Nada abaixo foi implementado.

## O que a medição mudou (Ask-First 4, medido neste turno)

O gerente **consegue** gravar dentro de `~/.maestro/evidence/` com a ferramenta Write (arquivo de sonda criado e apagado; o
diretório é do mesmo usuário, modo `rwxrwxr-x`, e nenhuma guarda barrou). Logo **qualquer ledger em `~/.maestro/` é
forjável pelo run**, pelo mesmo vetor, inclusive `~/.maestro/order-state/` (onde mora o carimbo de aceite). Isto vale para
(i) e (ii): registro em `~/.maestro/` sozinho **não** prova que o Diretor escreveu. Fechar o vetor é outra ordem; esta
proposta diz o que cada opção garante apesar dele.

## (i) onde o `fim:` do despacho fica registrado

| Opção | Como | Garante | Não garante |
|---|---|---|---|
| **A (recomendada)** | `order --create`/despacho grava no registro `~/.maestro/order-state/<proj>-<NNN>` o campo `fim_commit=<sha do commit do despacho>` (já existe o diretório e o escritor `_order_state_write`). O recibo lê o `fim:` com `git show <sha>:<arquivo da ordem>`. Sem `fim_commit`: recusa. | O run que só edita o repo não muda o baseline: reescrever o arquivo, commitar ou emendar o commit não altera o `sha` registrado. Reuso do mecanismo da ordem 021 (estado fora da árvore). | Run que grava o registro via Write (medição acima). Fica coberto só quando o vetor do `~/.maestro/` fechar. |
| B | `fim_hash` (sha256 do `fim:` normalizado) em vez do sha do commit. | Idem A, sem depender de o commit sobreviver a rebase. | Mesmo vetor; perde a rastreabilidade ao commit. |
| C | Tag git assinada no despacho. | Verificável sem ler `~/.maestro/`. | Exige chave do Diretor no fluxo de despacho (daemon); fora desta ordem. |

Quem grava `fim_commit`: o **despacho**. O `maestro order` não tem subcomando `--dispatch` (verificado); o branch e o
commit `chore(order): …` do despacho vêm do fluxo do Diretor/ponte-daemon. Se o gravador tiver de ficar no daemon,
**PARE**: está fora da ordem. Se bastar o `maestro order --create` no CLI (grava no ato de criar), cabe no patch, mas
então o baseline é o commit da **criação**, não o do despacho — a diferença é o que o Spock precisa decidir.

## (ii) como a confirmação do Diretor é registrada sem o run poder chamá-la

Restrição: `Bash(maestro *)` está na allowlist do gerente, então comando comum de `maestro` não serve.

| Opção | Como | Garante | Não garante |
|---|---|---|---|
| **A (recomendada)** | Reaproveitar a prova de identidade da ordem 041: `MAESTRO_ACCEPT_PROOF` (`v1:<sujeito>:<assinatura Ed25519>`), emitida pelo daemon só ao Diretor. `maestro order --confirm-fim N` exige a prova e grava `fim_commit` novo + sujeito + assinatura. | Quem confirma é identificado por assinatura, não por palavra. O run não tem a chave. | **Hoje `_order_accept_proof_verify` é um coto que recusa sempre** (comentário em `lib/cmd-order-accept.sh:172-175`). Implementar a verificação é a ordem de identidade, e a emissão é do ponte-daemon: **fora desta ordem**. |
| B | Confirmação = commit **assinado** (SSH/GPG) pelo Diretor tocando o `fim:`; o recibo aceita `fim:` de um commit posterior só se `git verify-commit` passa com uma chave listada fora do repo. | Não depende do daemon; verificável com o git. | Exige chave pública do Diretor registrada e fluxo de assinatura nos commits de turno do Spock. Lista de chaves em `~/.maestro/` é forjável (medição). |
| C | Sem confirmação mecânica nesta ordem: `fim:` mudou depois do despacho → recibo `order-N` **recusado** sempre; o Diretor muda o `fim:` re-despachando (novo `fim_commit`). | Fecha para negado; zero superfície nova. | Custa um re-despacho quando o Spock reescreve o `fim:` entre turnos (a 077 faz isso). |

## Recomendação

1. **(i) = A** (`fim_commit` no registro do despacho), implementado no CLI.
2. **(ii) = C neste patch**: mudança posterior de `fim:` recusa; o Spock reescreve o `fim:` e re-despacha, o que grava
   novo `fim_commit`. A confirmação assinada (A) entra quando a ordem de identidade tornar a verificação real; até lá
   não há como o run chamá-la porque ela não existe.
3. Sem `fim_commit` para a ordem: recusa (fecha para negado). Ordens já despachadas hoje (sem o campo) precisam de um
   re-despacho ou de uma carga única do campo pelo Diretor.

## Decisão pedida

Aval a (i)=A e (ii)=C (ou outra linha da tabela) antes do turno 2. Sem o aval, o turno 2 só entrega o patch das partes do
Ask-First 1 que **não** dependem dele (itens 1 e 2: comparação literal, número da ordem, rótulos de área) e recusa
`order-N` sempre que faltar `fim_commit`.
