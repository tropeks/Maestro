---
description: "Retro de calibração: lê o relatório determinístico do maestro retro, propõe diffs de tabela/heurísticas/sensores, e — com consentimento explícito — aplica, examina no eval e commita"
argument-hint: "[--days N] [--dry]"
---

# /maestro:retro — o Maestro aprendendo, do jeito da casa

O Maestro não aprende em runtime: aprende AQUI — telemetria → proposta → exame
→ commit versionado. Você é a IA nas bordas deste loop. Argumentos: `$ARGUMENTS`.

## 1. Ler o sinal (determinístico)

1. Rode `maestro retro` (repasse `--days` se veio nos argumentos) e leia também
   `maestro log --summary`.
2. Se o retro disser "sem dados", reporte e PARE — sem dado não há aprendizado,
   e inventar calibração é pior que não calibrar.

## 2. Interpretar e propor (o seu trabalho)

Traduza os números em DIFFS concretos, cada um com o sinal que o justifica:

- **Override ≥20%** → a tabela erra rota: proponha mudança de `routes:` ou
  heurística em `config/routing-table.yaml`, citando quais comandos manuais
  dispararam o override (estão no log como `cmd`, sem texto de prompt).
- **Desfecho ruim por agente/modo** (rework/reverted concentrado) → proponha
  ajuste de heurística de tiering ou da description do agente (`agents/*.md`).
- **habit_warn dominado por um smell** com cara de falso positivo → proponha
  `habits:` no `.maestro.yaml` do projeto, ou threshold; NUNCA supressão inline.
- **Workflows declarados sem uso** → proponha remover ou fundir (menos tabela =
  menos bytes de injeção).
- **`PROMOÇÃO ELEGÍVEL`** no retro → proponha `gate.mode: warn → block`.
- **Casos de eval novos**: se a conversa recente contém pedidos reais que a
  tabela roteou mal, proponha destilá-los para `tests/eval/cases.yaml`
  (enunciado parafraseado — pergunte antes; o log jamais contém prompt, mas a
  sessão viva pode doar o caso com aprovação do usuário).

Mostre TODOS os diffs como patch, com o porquê de cada um. Se `--dry`, pare aqui.

## 3. Consentimento e aplicação (só com aval explícito)

1. Pergunte: **"Aplico os diffs? (aplica | só mostra)"** — e espere a resposta.
2. Com "aplica": conceda o MENOR escopo necessário, por pouco tempo:
   `maestro consent --grant routing-table --ttl 30m --session <session_id>`
   (e/ou `roster` se houver diff em `agents/*.md`). Escopos são só esses dois —
   hooks/, bin/ e src/ não são consentíveis, nem tente.
3. Aplique os diffs e passe no EXAME antes de qualquer commit:
   `bash tests/run-all.sh` — o eval-on-diff (S-702) reprova nomeando o caso se
   uma rota mudou de veredito sem você regenerar o baseline no MESMO commit
   (`tests/eval/prescribe.ts` gera; a mudança de veredito tem de ser intencional
   e explicada na mensagem).
4. Suíte verde → commit (mensagem: `calibrate: <o quê> — sinal: <número do retro>`).
   Suíte vermelha → reverta os diffs, reporte o exame que falhou.
5. SEMPRE ao final: `maestro consent --revoke <escopo>` — consentimento não
   sobrevive à tarefa que o justificou.

## 4. Fechar o loop

- Registre o desfecho da própria calibração: `maestro outcome --session <id>
  accepted --suite pass` (ou o que tiver acontecido).
- Atualize o brief do projeto com o que mudou e por quê.
- Reporte: sinais lidos → diffs propostos → aplicados/recusados → exame →
  baseline de eval antes/depois. Push/PR seguem o fluxo do projeto (Spock) —
  este comando para no commit local.
