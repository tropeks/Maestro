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
"$BIN" order --accept 1 --project "$P" 2>/dev/null | grep -q 'já aceita' && ok "re-aceite é no-op honesto" || bad "re-aceite"

exit $fail
