<!-- maestro-order v1
id: 041
ts: 2026-09-22T10:24:53-03:00
epoch: 1790083493
head: eadcacf8cd0863365210561dec79479fd05bba87
branch: feat/041-aceite-por-identidade
frozen: vendor/ src/
intent_version: 6
intent_hash: 31205cc5
author_session: desconhecido
-->
# Ordem 041 — aceite por identidade: assinatura do Diretor, verificada na leitura

## A decisão que a autoriza

Decisão do Capitão na Ponte (`01M34MJJEPS8WKSSN2C9JHVSQW`, 2026-09-22), depois do plano em
cinco linhas: **o aceite passa a exigir prova de identidade**, e a ordem cobre as DUAS
portas — a do comando e a da leitura.

Manutenção sob ordem do Capitão com o v1 já encerrado: **é dívida de segurança, não
feature** (`docs/ENCERRAMENTO-v1.md` §5 — manutenção continua entrando pelo trilho).

## O defeito

`maestro order --accept` valida estado, não identidade. O `accepted_session` é
**autodeclarado** (`${sid:-desconhecido}`; as do Capitão estão gravadas como
`desconhecido`), e quem tem shell aceita a própria ordem. Pior: `.maestro/orders/` e
`~/.maestro/order-state/` **não estão na denylist do gate** — dá para escrever
`accepted_at:`/`accepted_session:` direto no arquivo ou no registro, sem passar pela CLI.
Trancar só o comando deixaria a janela aberta com cara de resolvido.

## O desenho, decidido

**Assinatura Ed25519, não HMAC.** O pedido original dizia HMAC-SHA256 com o segredo só no
daemon; HMAC simétrico não fecha esse requisito, porque **verificar exige a mesma chave que
assina** — e executor e Diretor rodam com o MESMO uid nesta forge, então permissão de
arquivo não separa os dois. Decisão do Capitão (A1): o **ponte-daemon assina com a chave
privada**, o Maestro **verifica com a pública**, que pode viver no repo sem risco. O
`openssl` da forge (3.5.7) faz os dois lados. A troca foi comunicada ao gerente headless
(`w1:p3J`), que emite.

**O que é assinado:**

    projeto \n id \n arvore_provada \n sujeito        (sujeito ∈ {spock, captain})

A árvore provada é a mesma que o aceite já grava (`accepted_tree`, saída de
`_order_proof_tree`): amarra a prova ao conteúdo que passou pela suíte, não à ordem em
abstrato.

**Onde entra e onde é conferida:**

- `MAESTRO_ACCEPT_PROOF` leva sujeito + assinatura ao `--accept`.
- A prova é **gravada no registro terminal** (`~/.maestro/order-state/`).
- A derivação de estado **confere a assinatura**: `--status`/`--json` só dizem `aceita` se
  ela bater. É isto que fecha a porta dos fundos — carimbo escrito à mão não deriva nada.
- `accepted_session` deixa de ser autodeclarado: passa a ser **o sujeito provado**.

**Compatibilidade:** `MAESTRO_ACCEPT_REQUIRE_PROOF` liga a exigência **por projeto**,
default **DESLIGADO** até o daemon emitir. Desligado, comportamento de hoje, byte a byte.

**Migração, e ela não tem atalho honesto:** ligado o REQUIRE, registro sem assinatura
válida **não** deriva `aceita`. As 40 ordens já aceitas não têm assinatura. Confiar em
registro antigo por ser antigo é o mesmo buraco com outro nome — o carimbo de data também
é escrito por quem forja. Logo: ligar o REQUIRE num projeto exige **re-assinar os registros
terminais existentes** (o daemon emite prova para cada `(projeto, id, árvore)` já aceito).
São 40 no Maestro, uma vez só. Enquanto não re-assinar, o projeto fica com o REQUIRE
desligado — e isso é visível, não silencioso.

**Falha FECHADA com o REQUIRE ligado**, em todos os ramos: prova ausente · assinatura
inválida · sujeito fora de `{spock, captain}` · prova de outra ordem, outra árvore ou outro
projeto · `openssl` ausente · chave pública ausente ou malformada.

**Guard:** `pre-bash-guard` levanta a categoria nova `accept` para `maestro order --accept`
em sessão de executor — vocabulário fechado de categorias (`_g_flag`).

## Limites

- A EMISSÃO é do daemon (contrato com `w1:p3J`); esta ordem entrega só a **verificação** e
  o que o Maestro guarda.
- A chave privada nunca entra no repo, no `.env` de projeto nem no ambiente de executor.
  Só a pública.
- Não mexe na denylist do gate: `.maestro/` continua fora dela, e é a verificação na
  leitura que resolve — não uma tranca a mais no caminho de escrita.

## Prova exigida

- **Passa**: aceite com prova válida (sujeito `captain`), e o registro guarda a assinatura;
  `--status` deriva `aceita` conferindo a assinatura.
- **Recusa, cada uma com teste próprio**: prova de OUTRA ordem · de OUTRA árvore · de OUTRO
  projeto · sujeito trocado · sujeito fora do conjunto · prova ausente com REQUIRE ligado ·
  assinatura corrompida · `openssl` ausente com REQUIRE ligado · chave pública ausente.
- **Porta dos fundos**: carimbo `accepted_*` escrito À MÃO no arquivo e no registro, com
  REQUIRE ligado, **não** deriva `aceita` — é o teste que prova que a ordem fechou a janela,
  e não só a porta.
- **Golden**: com REQUIRE desligado, o `--status --json` das 40 ordens é idêntico ao de
  hoje em `estado`/`pede_aceite`/`terminal`/`suspensa`.
- Guard: `maestro order --accept` em sessão de executor levanta `accept`; fora dela, não.
- Suíte verde; `doctor` sem mudança de veredito; habits dentro da catraca; recibo no tip.

## Contrato de execução
- Trabalhe APENAS no branch `feat/041-aceite-por-identidade`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ src/
- Prove com o ledger: `maestro evidence --record --label order-41 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v6 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 041` (você não fecha a própria ordem).
accepted_at: 2026-09-22T13:07:10-03:00
accepted_session: desconhecido
accepted_tree: 68c83e70cda806aeac35117a9b8460a638fca4c6
accepted_intent: 6
