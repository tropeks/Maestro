#!/usr/bin/env bash
# E15 — work orders com estado DERIVADO. Invariantes: executor não fecha a
# própria ordem (aceite exige prova mecânica); estado vem de git+ledger+aceite,
# nunca de auto-declaração; frozen zone bloqueia autônomo e avisa humano;
# aceite descongela na próxima compilação de política. Hermético.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
SS="$REPO/hooks/session-start.sh"
GATE="$REPO/hooks/pre-tool-gate.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

P="$tmp/proj"; mkdir -p "$P/core/auth" "$P/src"
git -C "$P" init -q
echo a > "$P/core/auth/jwt.py"; echo b > "$P/src/app.py"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm base

echo "-- criação: contrato completo e versionado"
"$BIN" order --create --title "Refazer Auth JWT" --frozen "core/auth/" \
  --budget-steps 15 --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Trocar o backend de sessão.
## Critérios de aceite
- suíte verde no ledger.
## Ask-First
- mudança de schema.
BODY
OF=$(ls "$P/.maestro/orders/"001-*.md)
[[ -f "$OF" ]] && ok "ordem em .maestro/orders/ (viaja com o repo)" || bad "arquivo da ordem"
grep -q '^<!-- maestro-order v1$' "$OF" && ok "carimbo v1" || bad "carimbo v1"
grep -q '^branch: order/001-' "$OF" && ok "branch derivado do título" || bad "branch derivado"
grep -q '^frozen: core/auth/$' "$OF" && ok "frozen zone no contrato" || bad "frozen zone"
grep -q '^budget_steps: 15$' "$OF" && ok "orçamento E14 na ordem" || bad "orçamento"
grep -q 'você não fecha a própria ordem' "$OF" && ok "contrato diz quem aceita" || bad "contrato de aceite"
grep -q 'NUNCA no main' "$OF" && ok "contrato exige branch próprio" || bad "branch próprio"

echo "-- estado derivado: aberta → em_execucao → provada → aceita"
chk "recém-criada = aberta" "$("$BIN" order --list --project "$P" | grep -o '\[[a-z_]*\]')" "[aberta]"
BR=$(grep '^branch:' "$OF" | awk '{print $2}')
git -C "$P" checkout -qb "$BR"; echo fix >> "$P/core/auth/jwt.py"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm entrega
chk "branch existe = em_execucao" "$("$BIN" order --list --project "$P" | grep -o '\[[a-z_]*\]')" "[em_execucao]"
"$BIN" order --accept 1 --project "$P" >/dev/null 2>&1; rc=$?
chk "aceite SEM prova → exit 1 (executor não fecha sozinho)" "$rc" "1"
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
chk "evidência verde no tip = provada" "$("$BIN" order --list --project "$P" | grep -o '\[[a-z_]*\]')" "[provada]"

echo "-- S-1802: label acolchoado não perde prova, sugestão sai normalizada"
# recibo gravado como order-001 (formato do NOME do arquivo, não do label) VALE:
# o leitor tolera o acolchoado — ninguém perde prova boa por formatação.
echo extra >> "$P/core/auth/jwt.py"; git -C "$P" add -A
git -C "$P" -c user.email=t@t -c user.name=t commit -qm mais
"$BIN" evidence --record --label order-001 --project "$P" -- true >/dev/null
chk "recibo com label order-001 (acolchoado) ainda deriva provada" \
    "$("$BIN" order --list --project "$P" | grep -o '\[[a-z_]*\]')" "[provada]"
# S-1804: a EXIBIÇÃO tem de tolerar o mesmo acolchoado que a DERIVAÇÃO tolera.
# Antes: estado 'provada' e linha de prova 'NENHUMA' — a mesma ordem descrita
# de dois jeitos incompatíveis, e foi isso que levou um operador a regravar um
# recibo que já estava bom.
if "$BIN" order --status 1 --project "$P" | grep -q 'prova   : evidência (order-001): VÁLIDA'; then
  ok "linha de prova enxerga o recibo acolchoado (derivação e exibição concordam)"
else
  bad "linha de prova ignora o acolchoado ($("$BIN" order --status 1 --project "$P" | grep 'prova' | head -1))"
fi
# fixture ISOLADA (não rouba o próximo id do fluxo principal): ordem 007 já
# existe em disco (nome de arquivo acolchoado) — a sugestão do create seguinte
# deve sair NORMALIZADA (order-8), derivada da mesma fórmula do leitor.
P2=$(mktemp -d); git -C "$P2" init -q
mkdir -p "$P2/.maestro/orders"
sed 's/^id: .*/id: 007/' "$OF" > "$P2/.maestro/orders/007.md"
"$BIN" order --create --title "Oitava" --branch order/8 --project "$P2" >/dev/null 2>&1 <<< "objetivo: t"
OF2=$(ls "$P2/.maestro/orders/"008-*.md 2>/dev/null | head -1)
if [[ -n "$OF2" ]] && grep -q -- '--label order-8 ' "$OF2"; then
  ok "contrato da ordem sugere o label normalizado (order-8, sem zeros)"
else
  bad "contrato da ordem sugere o label normalizado (obtido: $(grep -o 'order-[0-9]*' "$OF2" 2>/dev/null | head -1))"
fi
echo suja >> "$P/src/app.py"; git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm depois
chk "commit APÓS a prova → volta a em_execucao (prova não acompanha)" \
    "$("$BIN" order --list --project "$P" | grep -o '\[[a-z_]*\]')" "[em_execucao]"
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
"$BIN" order --accept 1 --project "$P" --session dir-1 >/dev/null
chk "prova re-feita + aceite = aceita" "$("$BIN" order --list --project "$P" | grep -o '\[[a-z_]*\]')" "[aceita]"
grep -q '^accepted_at: ' "$OF" && ok "aceite carimbado no arquivo (auditável)" || bad "aceite carimbado"

# S-1803: o carimbo do aceite escreve num arquivo RASTREADO, então ele próprio
# move a árvore depois da prova. Sem o carimbo da árvore provada, a ordem ficava
# 'aceita' exibindo 'prova VENCIDA' — auditoria que lê como quebrada. As três
# asserções abaixo rodam ANTES de qualquer commit de propósito: comitar o
# carimbo mascarava o defeito (era o que este teste fazia na linha seguinte).
PT=$(grep -m1 '^accepted_tree: ' "$OF" | sed 's/^accepted_tree: //')
[[ -n "$PT" && "$PT" != "desconhecida" ]] && ok "aceite carimba a árvore provada" || bad "árvore provada no carimbo (obtido: '${PT:-vazio}')"
chk "árvore carimbada == árvore do tip provado" "$PT" "$(git -C "$P" rev-parse "$BR^{tree}")"
if "$BIN" order --status 1 --project "$P" | grep -q 'prova   : VÁLIDA na aceitação'; then
  ok "ordem aceita reporta prova histórica, não comparação ao vivo"
else
  bad "ordem aceita ainda reporta prova ao vivo ($("$BIN" order --status 1 --project "$P" | grep 'prova' | head -1))"
fi

git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm "aceite 001"

# S-1805: aceite é sobre CONTEÚDO. Enquanto o branch não anda, "encerrada".
"$BIN" order --status 1 --project "$P" | grep -q 'encerrada' \
  && ok "aceita e parada no lugar → encerrada" || bad "encerrada"
# Commit APÓS o aceite: a ordem passa a cobrir o que ninguém aceitou.
echo depois-do-aceite >> "$P/src/app.py"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm "andou depois do aceite"
if "$BIN" order --status 1 --project "$P" | grep -q 'o branch andou DEPOIS do aceite'; then
  ok "branch que anda depois do aceite é DENUNCIADO, não escondido atrás de 'encerrada'"
else
  bad "branch andou e a ordem seguiu dizendo encerrada ($("$BIN" order --status 1 --project "$P" | tail -1))"
fi

# S-1806: re-aceite so e no-op quando NADA andou. Aqui o branch andou (teste do
# S-1805 acima), entao pedir aceite de novo e decisao NOVA — e decisao nova
# exige prova do conteudo de AGORA, como qualquer aceite.
"$BIN" order --accept 1 --project "$P" >/dev/null 2>&1; rc=$?
chk "branch andou e sem prova nova → aceite RECUSA (exit 1)" "$rc" "1"
"$BIN" order --accept 1 --project "$P" 2>&1 | grep -q 'não tem prova do conteúdo atual' \
  && ok "a recusa diz o motivo e o comando para gerar a prova" || bad "recusa sem motivo"
# Com prova do conteudo atual, o re-aceite acontece e ACRESCENTA carimbo.
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
"$BIN" order --accept 1 --project "$P" 2>&1 | grep -q 'REACEITA' \
  && ok "com prova do conteúdo atual, reaceita" || bad "reaceite com prova"
chk "o histórico guarda os DOIS aceites" "$(grep -c '^accepted_at: ' "$OF")" "2"
"$BIN" order --status 1 --project "$P" | grep -q 'encerrada' \
  && ok "depois do re-aceite volta a encerrada (o aceite vigente é o último)" || bad "encerrada pos-reaceite"
# A linha de PROVA tambem tem de seguir o aceite vigente. Com `grep -m1` ela
# ficava congelada no primeiro carimbo mesmo depois de reaceitar — a ordem
# dizia encerrada citando uma arvore que ja nao era a aceita.
PTL=$(grep '^accepted_tree: ' "$OF" | tail -1 | sed 's/^accepted_tree: //')
"$BIN" order --status 1 --project "$P" | grep -q "árvore ${PTL:0:12}" \
  && ok "a linha de prova cita a árvore do aceite VIGENTE, não a do primeiro" || bad "linha de prova presa no primeiro aceite"
# E agora, parada no lugar, re-aceite volta a ser no-op.
"$BIN" order --accept 1 --project "$P" 2>/dev/null | grep -q 'já aceita' && ok "re-aceite sem movimento é no-op honesto" || bad "no-op"

echo "-- S-1804: sem recibo, a sugestão de registro sai normalizada"
P3=$(mktemp -d); git -C "$P3" init -q
echo z > "$P3/z.txt"; git -C "$P3" add -A; git -C "$P3" -c user.email=t@t -c user.name=t commit -qm base
"$BIN" order --create --title "Sem prova" --project "$P3" <<< "obj" >/dev/null
if "$BIN" order --status 1 --project "$P3" | grep -q -- '--label order-1 '; then
  ok "sem recibo → sugere o label canônico (order-1, sem zeros)"
else
  bad "sugestão de label não normalizada ($("$BIN" order --status 1 --project "$P3" | grep 'prova' | head -1))"
fi
rm -rf "$P3"

echo "-- injeção (S-1503) e frozen zone no gate (S-1504)"
"$BIN" order --create --title "Segunda" --frozen "core/auth/" --project "$P" <<< "x" >/dev/null
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm "ordem 002"
OUT=$(printf '{"session_id":"o1"}' | CLAUDE_PROJECT_DIR="$P" bash "$SS" 2>/dev/null)
grep -q 'ordens: 1 pendente(s)' <<<"$OUT" && ok "injeção conta só as NÃO-aceitas" || bad "injeção conta pendentes"
grep -q 'ORDER_FROZEN="core/auth/"' "$MAESTRO_HOME/gate-policy.sh" && ok "política compila a zona" || bad "política compila"
probe() { printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" | CLAUDE_PROJECT_DIR="$P" bash "$GATE" >/dev/null 2>&1; echo "$?"; }
"$BIN" decide --session o1 --workflow fix --mode direct >/dev/null
chk "direct na zona → avisa e passa" "$(probe o1 "$P/core/auth/jwt.py")" "0"
"$BIN" decide --session o2 --workflow custom --mode multi --agents dev-pleno,qa >/dev/null
chk "multi na zona → BLOQUEIA" "$(probe o2 "$P/core/auth/jwt.py")" "2"
chk "multi fora da zona → passa" "$(probe o2 "$P/src/app.py")" "0"
grep -q '"cmd":"frozen_zone"' "$MAESTRO_HOME/logs/routing.jsonl" && ok "frozen_zone auditado" || bad "auditado"
git -C "$P" checkout -qb order/002-segunda
"$BIN" evidence --record --label order-2 --project "$P" -- true >/dev/null
"$BIN" order --accept 2 --project "$P" >/dev/null
printf '{"session_id":"o3"}' | CLAUDE_PROJECT_DIR="$P" bash "$SS" >/dev/null 2>&1
grep -q 'ORDER_FROZEN=""' "$MAESTRO_HOME/gate-policy.sh" && ok "aceite descongela na recompilação" || bad "descongela"
chk "multi pós-aceite → passa" "$(probe o2 "$P/core/auth/jwt.py")" "0"

echo "-- validações"
"$BIN" order --create --project "$P" <<< "x" >/dev/null 2>&1; rc=$?
chk "sem --title → exit 1" "$rc" "1"
"$BIN" order --status 99 --project "$P" >/dev/null 2>&1; rc=$?
chk "ordem inexistente → exit 1" "$rc" "1"

# ---------------------------------------------------------------------------
# E22 — a ordem cita a DIREÇÃO sob a qual nasceu. Direção que muda depois não
# invalida a ordem: torna o plano suspeito, e quem revê é gente (o aceite passa
# a exigir a declaração explícita do diretor).
# ---------------------------------------------------------------------------
mk_intent() { # mk_intent <proj> <versão> <texto do conteúdo>
  mkdir -p "$1/.maestro"
  cat > "$1/.maestro/INTENT.md" <<EOF
<!-- maestro-intent v1
version: $2
ts: 2026-09-05T10:00:00-03:00
head: none
author_session: desconhecido
hash: 00000000
-->
# Direção — teste

## Problema
- $3
## Público
- o Capitão.
## Resultado
- $3
## Prioridades
- $3
## Limites
- bash puro nos hooks.
## Fora de escopo
- virar orquestrador.
EOF
}

echo "-- E22: a ordem nasce carimbada com a direção vigente"
P4=$(mktemp -d); git -C "$P4" init -q
echo a > "$P4/a.txt"; git -C "$P4" add -A
git -C "$P4" -c user.email=t@t -c user.name=t commit -qm base
mk_intent "$P4" 1 "o roteador não sabe para onde o projeto vai."
OUT=$("$BIN" order --create --title "Com direção" --project "$P4" <<< "obj")
OF4=$(ls "$P4/.maestro/orders/"001-*.md)
grep -q '^intent_version: 1$' "$OF4" && ok "cabeçalho carimba a versão da direção" || bad "intent_version no cabeçalho"
grep -q '^intent_hash: [0-9a-f]\{8\}$' "$OF4" && ok "cabeçalho carimba o hash (8 hex) da direção" || bad "intent_hash no cabeçalho"
chk "o hash carimbado é o do corpo do INTENT sem o carimbo" \
    "$(awk -F': ' '/^intent_hash: /{print $2; exit}' "$OF4")" \
    "$(sed '1,/^-->$/d' "$P4/.maestro/INTENT.md" | sha256sum | head -c 8)"
grep -q 'direção: INTENT v1 carimbada na ordem' <<<"$OUT" && ok "o create diz sob qual direção a ordem nasceu" || bad "create anuncia a direção"
grep -q 'Direção vigente na criação: INTENT v1' "$OF4" && ok "o contrato manda o plano citar a seção da direção" || bad "contrato cita a direção"
"$BIN" order --status 1 --project "$P4" | grep -q '^  direção : v1$' && ok "status mostra a direção da ordem" || bad "status mostra direção"
"$BIN" order --status 1 --project "$P4" | grep -q 'ATENÇÃO: a direção mudou' && bad "direção parada acusou mudança" || ok "direção parada não vira alarme"
"$BIN" order --list --project "$P4" | grep -q 'direção mudou' && bad "list marcou ordem em dia" || ok "list não marca ordem em dia"

echo "-- E22: direção editada SEM bump é dita, mas não é 'mudou'"
mk_intent "$P4" 1 "outro texto, mesma versão."
"$BIN" order --status 1 --project "$P4" | grep -q 'editada sem bump' \
  && ok "conteúdo outro na mesma versão é denunciado no status" || bad "edição sem bump silenciosa no status"
"$BIN" order --list --project "$P4" | grep -q 'direção mudou' \
  && bad "edição sem bump marcou a lista (a versão é o que a ordem cita)" || ok "sem bump, a lista não acusa"

echo "-- E22: direção que SOBE de versão põe a ordem em revisão"
mk_intent "$P4" 2 "a direção andou."
"$BIN" order --status 1 --project "$P4" | grep -q 'ATENÇÃO: a direção mudou (v1 → v2) depois desta ordem — revise o plano contra .maestro/INTENT.md' \
  && ok "status manda revisar o plano contra a direção nova" || bad "status acusa direção desatualizada"
"$BIN" order --list --project "$P4" | grep -q '\[direção mudou\]' && ok "list marca [direção mudou]" || bad "list marca direção mudada"

echo "-- E22: aceite sob direção desatualizada é decisão NOVA do diretor"
BR4=$(grep '^branch:' "$OF4" | awk '{print $2}')
git -C "$P4" checkout -qb "$BR4"; echo entrega >> "$P4/a.txt"; git -C "$P4" add -A
git -C "$P4" -c user.email=t@t -c user.name=t commit -qm entrega
"$BIN" evidence --record --label order-1 --project "$P4" -- true >/dev/null
chk "ordem provada mesmo com a direção desatualizada" \
    "$("$BIN" order --list --project "$P4" | grep -o '\[[a-z_]*\]')" "[provada]"
"$BIN" order --accept 1 --project "$P4" >/dev/null 2>&1; rc=$?
chk "aceite com direção desatualizada → exit 1" "$rc" "1"
"$BIN" order --accept 1 --project "$P4" 2>&1 | grep -q -- '--intent-reviewed' \
  && ok "a recusa ensina o comando que declara a revisão" || bad "recusa sem saída"
grep -q '^accepted_at: ' "$OF4" && bad "recusa carimbou aceite mesmo assim" || ok "recusa não carimba nada"
OUT=$("$BIN" order --accept 1 --project "$P4" --intent-reviewed --session dir-9)
grep -q 'ACEITA' <<<"$OUT" && ok "com --intent-reviewed o aceite acontece" || bad "aceite com --intent-reviewed"
chk "o aceite carimba sob qual direção foi dado" \
    "$(grep '^accepted_intent: ' "$OF4" | tail -1 | sed 's/^accepted_intent: //')" "2"

echo "-- E22: projeto sem direção cria ordem assim mesmo, avisando"
P5=$(mktemp -d); git -C "$P5" init -q
echo a > "$P5/a.txt"; git -C "$P5" add -A
git -C "$P5" -c user.email=t@t -c user.name=t commit -qm base
OUT=$("$BIN" order --create --title "Sem direção" --project "$P5" <<< "obj"); rc=$?
chk "sem INTENT a ordem é criada (o Maestro não bloqueia trabalho)" "$rc" "0"
grep -q 'AVISO: ordem sem direção' <<<"$OUT" && ok "o create avisa que a ordem nasceu sem norte" || bad "aviso de ordem sem direção"
grep -q 'maestro intent --init' <<<"$OUT" && ok "o aviso ensina como criar a direção" || bad "aviso ensina o --init"
OF5=$(ls "$P5/.maestro/orders/"001-*.md)
grep -q '^intent_version: ' "$OF5" && bad "carimbou direção que não existe" || ok "sem direção, nada é carimbado"
"$BIN" order --status 1 --project "$P5" | grep -q '  direção :' && bad "status inventou direção" || ok "ordem sem direção não ganha linha de direção"
git -C "$P5" checkout -qb "$(grep '^branch:' "$OF5" | awk '{print $2}')"
git -C "$P5" add -A; git -C "$P5" -c user.email=t@t -c user.name=t commit -qm entrega
"$BIN" evidence --record --label order-1 --project "$P5" -- true >/dev/null
"$BIN" order --accept 1 --project "$P5" >/dev/null 2>&1; rc=$?
chk "ordem sem direção aceita normalmente (nada a revisar)" "$rc" "0"

echo "-- E22: a janela do cabeçalho (NR>20) alcança os campos novos"
# Cabeçalho artificialmente CHEIO: intent_version cai na linha 16, além do
# antigo teto de 14 — é exatamente o que a subida da janela precisa provar.
P6=$(mktemp -d); git -C "$P6" init -q
echo a > "$P6/a.txt"; git -C "$P6" add -A
git -C "$P6" -c user.email=t@t -c user.name=t commit -qm base
mkdir -p "$P6/.maestro/orders"
cat > "$P6/.maestro/orders/001-cheia.md" <<'ORDEM'
<!-- maestro-order v1
id: 001
ts: 2026-09-05T10:00:00-03:00
epoch: 1757070000
head: none
branch: order/001-cheia
budget_steps: 15
budget_min: 60
budget_cents: 500
doc: docs/architecture/EPICS.md
x1: enchimento
x2: enchimento
x3: enchimento
x4: enchimento
frozen: core/pad/
intent_version: 4
intent_hash: abcdef12
author_session: desconhecido
-->
# Ordem 001 — Cabeçalho cheio
ORDEM
chk "intent_version está mesmo além da linha 14" \
    "$(grep -n '^intent_version: ' "$P6/.maestro/orders/001-cheia.md" | cut -d: -f1)" "16"
"$BIN" order --status 1 --project "$P6" | grep -q '^  direção : v4$' \
  && ok "o leitor de cabeçalho alcança intent_version na linha 16" || bad "campo novo fora da janela do cabeçalho"
printf '{"session_id":"o9"}' | CLAUDE_PROJECT_DIR="$P6" bash "$SS" >/dev/null 2>&1
grep -q 'ORDER_FROZEN="core/pad/"' "$MAESTRO_HOME/gate-policy.sh" \
  && ok "frozen zone continua compilada com o cabeçalho maior" || bad "frozen zone perdida no cabeçalho maior"
rm -rf "$P4" "$P5" "$P6"

exit $fail
