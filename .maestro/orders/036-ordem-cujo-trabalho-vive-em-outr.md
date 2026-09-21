<!-- maestro-order v1
id: 036
ts: 2026-09-20T19:00:01-03:00
epoch: 1789941601
head: 933acd592f860d4d8e40e74b2e00493ddc333659
branch: fix/036-ordem-cross-repo
frozen: vendor/ agents/ config/routing-table.yaml hooks/
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
-->
# Ordem 036 — ordem cujo trabalho vive em outro repo: o ledger nao fecha no lugar certo

## Por que esta ordem existe

A 033 entregou e provou, e o aceite dela **trava** — não por defeito dela, mas por um
defeito de fronteira que ela expôs. O trabalho da 033 vive no `ponte-daemon`; o arquivo
da ordem vive no Maestro. O ledger não tem onde guardar essa distinção.

É a MESMA família do que a 033 consertou: lá, `director.report` inferia o projeto da
SESSÃO em vez de aceitá-lo como campo; aqui, o ledger infere o repo da ordem do
DIRETÓRIO em que o comando roda. As duas premissas nasceram de "um gerente, um projeto"
e as duas quebraram quando o Diretor passou a conduzir três repos.

## O sintoma, medido hoje (2026-09-20)

Três camadas, todas verificadas na mão:

1. **A ordem não sabe onde o trabalho mora.** O cabeçalho `maestro-order v1`
   (DATA_MODEL §"ordem") tem `id/ts/epoch/head/branch/frozen/budget_*/doc/author_session`
   mais `intent_version`/`intent_hash` da E22 — e **nenhum campo para o repo**. Em
   `~/dev/Maestro`, a 033 aparece `em_execucao` sem evidência, porque `--status` procura
   o recibo com `--project` do projeto CORRENTE e o recibo não está lá:

       $ ls ~/.maestro/evidence/ | grep order-33
       ponte-daemon-dcd791bc-order-33      # existe, no ledger do daemon
       # Maestro-abc49550-order-33          → NÃO existe

2. **Apontar o projeto à mão não resolve.** Mesmo com o caminho certo, o recibo lê
   VENCIDA, porque a comparação usa a árvore do CHECKOUT PRINCIPAL do projeto e não a do
   worktree onde a prova foi gravada:

       $ maestro evidence --label order-33 --project ~/dev/ponte-daemon
       evidência (order-33): VENCIDA — conteúdo mudou desde a prova.

   (`~/dev/ponte-daemon` está em `order/004`; a prova é de `ponte-033-report`.) Mesma
   família da issue **#36**, que já está aberta — e aqui ela deixa de ser incômodo e
   vira bloqueio.

3. **No repo do trabalho, a ordem não existe.** Rodando de
   `~/dev/worktrees/ponte-033-report`:

       $ maestro order --status 033
       maestro: validation: ordem 033 não existe

   O executor não consegue ler o próprio contrato nem o próprio estado pela CLI, no lugar
   onde ele trabalha.

## O que NÃO fazer, e por quê

- **Não gravar um recibo `order-33` no ledger do Maestro.** Rodar a suíte do Maestro não
  prova nada sobre uma mudança no `ponte-daemon`: seria recibo válido provando a coisa
  errada — exatamente a "prova que parece prova" que a ordem 005 matou.
- **Não afrouxar `--accept`.** Ele exige `provada` por desenho (DATA_MODEL §"ordem"), e
  essa exigência é o que dá valor ao carimbo.
- **Não duplicar a ordem nos dois repos.** Duas cópias é duas fontes de estado — a lição
  da 018 (três identificadores e ninguém reconciliando) e da issue #18.

## O espaço de decisão (a ordem NÃO decide; o plano decide, com o Capitão)

- **A — campo no cabeçalho.** A ordem ganha algo como `work_project:`/`work_repo:`, e
  `--status`/`--accept` resolvem o recibo NESSE projeto. É a forma simétrica ao conserto
  da 033: o campo diz de que projeto se fala, em vez de inferir de onde se está. Puxa
  junto a camada 2 (achar a árvore certa: worktree do branch, não o checkout principal).
- **B — a ordem mora no repo do trabalho** e o Maestro só referencia. Contraria "a
  convenção do canal é do Maestro" e espalha o ledger.
- **C — recibo com origem declarada**: o próprio recibo carrega o projeto/árvore em que
  foi gravado, e o ledger de qualquer projeto sabe lê-lo.

Quem planeja pesa também o custo de migração das 35 ordens existentes (nenhuma tem o
campo) e a compatibilidade: ordem sem o campo tem de continuar funcionando exatamente
como hoje — mesma regra que a 033 aplicou ao `project` omitido.

## Prova exigida

- Uma ordem cujo trabalho vive em outro repo fecha o ciclo inteiro pela CLI: `--status`
  mostra a prova, `--accept` aceita, e o `--json` reporta o estado certo dos DOIS lados.
- Ordem sem o campo novo: comportamento idêntico ao de hoje — teste de não-regressão.
- A 033 é o caso de teste vivo: com o conserto, ela fecha sem ninguém forçar nada.
- Recibo lido do worktree do branch e do checkout principal dá o MESMO veredito, ou a
  diferença é nomeada (camada 2 / issue #36).
- Suíte verde; `doctor` sem mudança de veredito; DATA_MODEL emendado no MESMO changeset
  (o cabeçalho da ordem é contrato de doc canônico).

## Contrato de execução
- Trabalhe APENAS no branch `fix/036-ordem-cross-repo`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ agents/ config/routing-table.yaml hooks/
- Prove com o ledger: `maestro evidence --record --label order-36 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 036` (você não fecha a própria ordem).
accepted_at: 2026-09-21T00:42:32-03:00
accepted_session: desconhecido
accepted_tree: 8852762e6dd4efd469396bc31d878e89e3846e23
accepted_intent: 4
