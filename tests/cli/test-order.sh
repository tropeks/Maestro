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
echo suja >> "$P/src/app.py"; git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm depois
chk "commit APÓS a prova → volta a em_execucao (prova não acompanha)" \
    "$("$BIN" order --list --project "$P" | grep -o '\[[a-z_]*\]')" "[em_execucao]"
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
"$BIN" order --accept 1 --project "$P" --session dir-1 >/dev/null
chk "prova re-feita + aceite = aceita" "$("$BIN" order --list --project "$P" | grep -o '\[[a-z_]*\]')" "[aceita]"
grep -q '^accepted_at: ' "$OF" && ok "aceite carimbado no arquivo (auditável)" || bad "aceite carimbado"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm "aceite 001"

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
