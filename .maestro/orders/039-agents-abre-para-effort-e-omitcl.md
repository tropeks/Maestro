<!-- maestro-order v1
id: 039
ts: 2026-09-22T06:29:04-03:00
epoch: 1790069344
head: 921e41381ccdb2f0ec693bb2ad7f7f4f0f01f109
branch: feat/039-roster-dois-campos
frozen: vendor/ src/ bin/
intent_version: 4
intent_hash: 580bb30a
author_session: desconhecido
-->
# Ordem 039 — agents/ abre para effort e omitClaudeMd, e so para elas

## A decisão que a autoriza

Decisão do Capitão, registrada na Ponte (`01M325GBZFYMNFV9A44KJTYMSJ`, escolha
`abre_dois_campos`), 2026-09-22: **`agents/` abre SÓ para dois campos de frontmatter —
`effort` (baixo/alto) e `omitClaudeMd` — e o gate continua barrando qualquer outra
mudança em `agents/`.**

O encerramento do v1 **não** é assunto desta ordem: é outra decisão do Capitão, ainda
aberta.

## Por que isto existe

A 024 mediu e registrou a limitação: o despacho expõe só `model`, enquanto `effort` e
`omitClaudeMd` são frontmatter do agente, e **nenhum dos oito de `agents/` os usa**. A
coluna `model` da H8 já roteia por perfil — mecânica→haiku, contrato/TDD→sonnet,
desenho/revisão/migração/segurança→opus — mas o resto do tiering fica na mesa porque o
roster é zona congelada.

A 024 disse, por escrito: *"`agents/` é zona congelada — se o desenho exigir abrir, PARE e
chame."* Foi o que aconteceu. Esta ordem é o depois dessa parada.

## O que entra

**1. Emenda de Limites no INTENT.** O limite hoje diz `agents/` é só markdown e não é
reescrito por agente. Passa a dizer o que a decisão diz: duas chaves de frontmatter
nomeadas, tudo o mais barrado, com a data e o id da decisão citados. Depois:
`maestro intent --bump`.

**2. O gate ganha a exceção, estreita e falhando FECHADO.** Diff que toque
exclusivamente `effort` e `omitClaudeMd` passa; terceira chave, corpo, `name`, `model`,
`description`, `tools` — tudo continua bloqueado. Regras:

- **Equivalência por remoção**: tirando as linhas das duas chaves dos dois lados, o que
  sobra tem de ser byte-idêntico. É o que prova "só essas chaves mudaram" sem reconstruir
  arquivo.
- **Gramática fechada dos valores**: `effort: baixo|alto` e `omitClaudeMd: true|false`.
  Chave certa com valor livre não passa.
- **Posição**: a mudança tem de cair dentro do frontmatter, não no corpo.
- **Falha FECHADO**: sem `jq`, payload truncado, arquivo ilegível, `Edit` que não casa —
  bloqueia. A exceção é um caminho a mais, nunca uma brecha a menos.
- O resto do gate continua valendo: decision record, catraca, frozen zones. Exceção de
  denylist não é bypass de nada.

**3. A tabela de roteamento usa os dois campos.** A regra é a que já rege a coluna
`model` (H8/ADR-004, "haiku no mecânico, opus no complexo"): mecânica e estreita →
`effort: baixo` + `omitClaudeMd: true`; desenho, revisão final, migração e segurança →
`effort: alto`. O orçamento de injeção tem catraca — se a linha crescer, corta no MESMO
changeset (E25/S-2502).

## Limites desta ordem

- **Não muda a lista de agentes, nem o corpo de nenhum.** A ordem abre a porta; quem passa
  por ela é outra decisão.
- **Não afrouxa nenhuma outra entrada da denylist.** `hooks/`, `bin/`, `src/`,
  `.claude-plugin/` e `config/routing-table.yaml` seguem como estão — a exceção é
  exclusiva de `agents/*.md`.
- O `maestro consent --grant roster`, que já existia, continua existindo e não é tocado.

## Prova exigida

- **Passa**: `Edit` que só troca `effort: baixo` por `effort: alto`; `Edit` que ACRESCENTA
  `omitClaudeMd: true` usando uma linha vizinha como âncora; `Write` do arquivo inteiro com
  só essas linhas diferentes.
- **Barra**: terceira chave de frontmatter junto; mudança no corpo junto; mudança em
  `model`/`name`/`tools`; valor fora da gramática (`effort: medio`); a chave inserida no
  CORPO em vez do frontmatter; `Edit` cujo `old_string` não casa com o arquivo.
- **Barra com `jq` ausente** — a prova de que a exceção falha fechado.
- Teste do gate em sandbox com o `lib/` junto (armadilha da 027).
- Latência do gate pelo instrumento da 016 (sonda + teto com folga), não teto cravado.
- `maestro intent --check` reporta v5 depois do bump; toda ordem viva marcada para revisão
  de plano é comportamento esperado da E22, não regressão.
- Suíte verde; `doctor` sem mudança de veredito; habits dentro da catraca; orçamento de
  injeção dentro da catraca.

## Contrato de execução
- Trabalhe APENAS no branch `feat/039-roster-dois-campos`; NUNCA no main/master.
- Zonas CONGELADAS (não toque): vendor/ src/ bin/
- Prove com o ledger: `maestro evidence --record --label order-39 -- <suíte>` no tip do branch.
- Direção vigente na criação: INTENT v4 (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.
- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.
- O aceite é do diretor: `maestro order --accept 039` (você não fecha a própria ordem).
accepted_at: 2026-09-22T08:13:31-03:00
accepted_session: desconhecido
accepted_tree: 35c1c66084d784f4e2d5c9d975870d153b932a18
accepted_intent: 5
