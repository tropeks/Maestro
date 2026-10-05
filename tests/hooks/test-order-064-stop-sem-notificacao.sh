#!/usr/bin/env bash
# Ordem 064: o Stop de turno bloqueia o turno headless que encerra "esperando notificação".
# O critério é o recibo no ledger, NÃO o texto da fala: a frase da 062 ("Suíte ainda
# rodando; aguardo a notificação") sem recibo `order-N` cai em "falta recibo" e bloqueia.
# Não há classificação de frase. Cada hipótese (b)-(f) da ordem é ligada e desligada aqui.
# HOOK_UNDER_TEST=<raiz do plugin> roda o mesmo teste contra OUTRA árvore (ex.: o cache).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="${HOOK_UNDER_TEST:-$REPO}"
HOOK="$ROOT/hooks/stop-turno.sh"
BIN="$ROOT/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q -b main
echo a > "$P/f.txt"; G add -A; G commit -qm base
TURNO='## Turno
- fatia: x
- fim: bash t.sh
- teto: 3
- fora: y
- relatório: ENGINEERING_SPEC'
printf '> **Execução headless:** sandbox.\n%s\n' "$TURNO" | "$BIN" order --create --title "com turno" --project "$P" --session s0 >/dev/null
G add -A; G commit -qm ordem
BR1=$(grep '^branch:' "$P"/.maestro/orders/001-*.md | awk '{print $2}')
G checkout -qb "$BR1"; echo b >> "$P/f.txt"; G add -A; G commit -qm entrega   # nenhum recibo order-1

FRASE='Suíte ainda rodando; aguardo a notificação'
payload() { printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":%s,"last_assistant_message":"%s"}' "$1" "${2:-}" "${3:-false}" "$FRASE"; }
tr_line() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$tmp/tr.jsonl"; }
run() { # <stdin> [VAR=val ...] → stdout do hook em $OUT, rc em $RC
  local in="$1"; shift
  OUT=$(cd "$P" && env CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$ROOT" "$@" bash "$HOOK" <<<"$in" 2>/dev/null); RC=$?
}
blocked() { [[ $RC -eq 0 && "$OUT" == '{"decision":"block","reason":"'* ]]; }
freed()   { [[ $RC -eq 0 && -z "$OUT" ]]; }

tr_line "$FRASE"

# --- o caso da 062: headless, última fala de espera, sem recibo → BLOQUEIA ---------
run "$(payload s062 "$tmp/tr.jsonl")"
if blocked && grep -q 'recibo' <<<"$OUT"; then ok "payload da 062 sem recibo: block (falta recibo)"
else bad "payload da 062 NÃO bloqueou (rc=$RC out=${OUT:0:100})"; fi

# --- (f) transcript ilegível/vazio: o critério é o recibo, não o texto → ainda bloqueia
run "$(payload s062f "$tmp/nao-existe.jsonl")"
blocked && ok "(f) transcript ilegível: block (critério é o recibo)" || bad "(f) transcript ilegível liberou (rc=$RC out=${OUT:0:100})"
run "$(payload s062g "")"
blocked && ok "(f) transcript_path vazio: block" || bad "(f) transcript_path vazio liberou (rc=$RC out=${OUT:0:100})"

# --- (b) reentrada libera por desenho ---------------------------------------------
run "$(payload s062b "$tmp/tr.jsonl" true)"
freed && ok "(b) stop_hook_active:true libera (desenho)" || bad "(b) reentrada bloqueou"

# --- (c) teto de 3 bloqueios por sessão: o 4º libera, sessão nova volta a bloquear --
for i in 1 2 3; do run "$(payload sTETO "$tmp/tr.jsonl")"; done
run "$(payload sTETO "$tmp/tr.jsonl")"
freed && ok "(c) 4º bloqueio da mesma sessão libera (teto 3)" || bad "(c) teto não liberou o 4º"
run "$(payload sNOVA "$tmp/tr.jsonl")"
blocked && ok "(c) sessão nova bloqueia: o teto só gastou a sessão anterior" || bad "(c) sessão nova liberou"

# --- (d) diretório do projeto fora do worktree com .maestro/orders -----------------
OUT=$(cd "$tmp" && env CLAUDE_PROJECT_DIR="$tmp" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" <<<"$(payload s062d "$tmp/tr.jsonl")" 2>/dev/null); RC=$?
freed && ok "(d) CLAUDE_PROJECT_DIR sem .maestro/orders libera" || bad "(d) bloqueou fora do projeto"
OUT=$(cd "$P" && env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" <<<"$(payload s062d2 "$tmp/tr.jsonl")" 2>/dev/null); RC=$?
blocked && ok "(d) sem CLAUDE_PROJECT_DIR, cwd = worktree: block" || bad "(d) cwd do worktree não bastou (rc=$RC out=${OUT:0:100})"

# --- (e) ordem sem ## Turno libera ---------------------------------------------------
of=$(ls "$P"/.maestro/orders/001-*.md)
cp "$of" "$tmp/ordem.bak"
grep -v '^## Turno' "$of" > "$tmp/sem-turno.md"; cp "$tmp/sem-turno.md" "$of"
run "$(payload s062e "$tmp/tr.jsonl")"
freed && ok "(e) ordem sem ## Turno libera" || bad "(e) ordem sem Turno bloqueou"
cp "$tmp/ordem.bak" "$of"

# --- (a) CLI estoura o teto de 2 s (load): rc 124 NÃO pode liberar calado ------------
# Hook sem a checagem local da 056 (cache 1.21.0) libera aqui; o do tip bloqueia pelos rótulos.
mkdir -p "$tmp/slow/bin"
printf '#!/bin/sh\nsleep 5\n' > "$tmp/slow/bin/maestro"; chmod +x "$tmp/slow/bin/maestro"
run "$(payload s062a "$tmp/tr.jsonl")" CLAUDE_PLUGIN_ROOT="$tmp/slow"
if blocked && grep -q 'turno_timeout' <<<"$OUT"; then ok "(a) CLI em 124 com a fala de espera: block pelos rótulos (056)"
else bad "(a) CLI em 124 liberou CALADO (rc=$RC out=${OUT:0:100}) — hook sem a checagem local da 056"; fi

# --- controles: sempre exit 0, sem prender ------------------------------------------
tr_line '[spock] aguardando: posso seguir?'
run "$(payload sE "$tmp/tr.jsonl")"; freed && ok "[spock] aguardando: libera" || bad "bloqueou rodada que pergunta"
tr_line "$FRASE"
run "$(payload sF "$tmp/tr.jsonl")" MAESTRO_OFF=1; freed && ok "MAESTRO_OFF=1 libera" || bad "kill-switch bloqueou"
G checkout -q main
run "$(payload sG "$tmp/tr.jsonl")"; freed && ok "branch sem ordem libera" || bad "main bloqueou"
G checkout -q "$BR1"

exit "$fail"
