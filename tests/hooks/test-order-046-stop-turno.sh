#!/usr/bin/env bash
# ordem 046 — hooks/stop-turno.sh (evento Stop): o critério é o RECIBO no tip,
# lido do ledger pelo CLI. Cobre: kill-switch, reentrada, caminho comum SEM fork
# de git, ordem sem bloco, rodada que pergunta ao Diretor, bloqueio com lista de
# faltas, recibo válido libera, teto de bloqueios, fail-open (timeout/erro do
# CLI) e os DOIS orçamentos de latência (comum <50 ms; Stop de turno ≤ 2 s).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/stop-turno.sh"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/latency.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

[[ -f "$HOOK" ]] || { bad "hooks/stop-turno.sh não existe"; exit 1; }

P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q -b main
echo a > "$P/f.txt"; G add -A; G commit -qm base

TURNO='## Turno
- fatia: x
- fim: bash t.sh
- teto: 2
- fora: y
- relatório: ENGINEERING_SPEC'
printf '> **Execução headless:** sandbox.\n%s\n' "$TURNO" | "$BIN" order --create --title "com turno" --project "$P" --session s0 >/dev/null
printf '> **Execução headless:** sandbox.\n' | "$BIN" order --create --title "sem turno" --project "$P" --session s0 >/dev/null
# ordem ANTIGA: sem o bloco (o --create emite esqueleto; aqui ele sai de propósito)
sed -i '/^## Turno/,/^## Contrato/{/^## Contrato/!d}' "$P"/.maestro/orders/002-*.md
G add -A; G commit -qm ordens
BR1=$(grep '^branch:' "$P"/.maestro/orders/001-*.md | awk '{print $2}')
BR2=$(grep '^branch:' "$P"/.maestro/orders/002-*.md | awk '{print $2}')

payload() { printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":%s}' "$1" "${2:-}" "${3:-false}"; }
run() { # <stdin> [VAR=val ...] → stdout do hook em $OUT, rc em $RC
  local in="$1"; shift
  OUT=$(cd "$P" && env CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$REPO" "$@" bash "$HOOK" <<<"$in" 2>/dev/null); RC=$?
}
tr_line() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$tmp/tr.jsonl"; }

# --- liberações sem trabalho -------------------------------------------------
run "$(payload sA)" MAESTRO_OFF=1;                    [[ $RC -eq 0 && -z "$OUT" ]] && ok "kill-switch: sai 0, stdout vazio" || bad "kill-switch"
run "$(payload sA '' true)";                          [[ $RC -eq 0 && -z "$OUT" ]] && ok "stop_hook_active=true libera na hora" || bad "reentrada"
run "$(payload sA)";                                  [[ $RC -eq 0 && -z "$OUT" ]] && ok "branch main (sem ordem) libera, stdout vazio" || bad "main bloqueou ($OUT)"

# --- caminho comum: ZERO fork de git, CLI não é chamado ----------------------
mkdir -p "$tmp/fakebin" "$tmp/fakeroot/bin"
printf '#!/bin/sh\necho git >> "%s/forks.log"\nexec %s "$@"\n' "$tmp" "$(command -v git)" > "$tmp/fakebin/git"; chmod +x "$tmp/fakebin/git"
printf '#!/bin/sh\necho chamado >> "%s/cli.log"\nexit 1\n' "$tmp" > "$tmp/fakeroot/bin/maestro"; chmod +x "$tmp/fakeroot/bin/maestro"
: > "$tmp/forks.log"; : > "$tmp/cli.log"
run "$(payload sA)" PATH="$tmp/fakebin:$PATH" CLAUDE_PLUGIN_ROOT="$tmp/fakeroot"
[[ ! -s "$tmp/forks.log" && ! -s "$tmp/cli.log" ]] && ok "caminho comum (main): zero fork de git, CLI não chamado" || bad "caminho comum forkou ($(wc -l < "$tmp/forks.log") git, $(wc -l < "$tmp/cli.log") cli)"
G checkout -qb "$BR2"
run "$(payload sA)" PATH="$tmp/fakebin:$PATH" CLAUDE_PLUGIN_ROOT="$tmp/fakeroot"
[[ ! -s "$tmp/forks.log" && ! -s "$tmp/cli.log" && -z "$OUT" ]] && ok "ordem SEM bloco Turno: libera sem git e sem CLI" || bad "ordem sem bloco chamou algo"
G checkout -q main

# --- ordem com bloco, sem recibo → bloqueia com a lista de faltas -------------
G checkout -qb "$BR1"; echo b >> "$P/f.txt"; G add -A; G commit -qm entrega
run "$(payload sB)"
if [[ $RC -eq 0 && "$OUT" == '{"decision":"block","reason":"'* ]] && grep -q 'order-1' <<<"$OUT" && grep -q 'ausente' <<<"$OUT"; then
  ok "sem recibo: block com a lista do que falta (recibo order-1 ausente)"
else bad "sem recibo não bloqueou como esperado (rc=$RC out=$OUT)"; fi
grep -q '^{"decision":"block","reason":"[^"]*"}$' <<<"$OUT" && ok "block é JSON de uma linha, sem aspas cruas" || bad "JSON malformado: $OUT"

# rodada que PERGUNTA ao Diretor é fim legítimo
tr_line '[spock] aguardando: posso seguir?'
run "$(payload sC "$tmp/tr.jsonl")"; [[ $RC -eq 0 && -z "$OUT" ]] && ok "rodada com [spock] aguardando: libera (o gate-report cuida)" || bad "bloqueou rodada que pergunta"

# rótulos faltando entram na lista, mas só com o recibo faltando
tr_line 'texto livre sem rotulos'
run "$(payload sD "$tmp/tr.jsonl")"; grep -q 'feito' <<<"$OUT" && ok "rótulos do relatório faltando entram na lista de faltas" || bad "rótulos não listados ($OUT)"

# --- recibo válido libera, mesmo sem rótulos ----------------------------------
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
run "$(payload sE "$tmp/tr.jsonl")"; [[ $RC -eq 0 && -z "$OUT" ]] && ok "recibo VÁLIDA no tip libera, mesmo sem rótulos" || bad "recibo válido bloqueou ($OUT)"

# --- teto: ordem 001 declara 2 → 2 blocks, o 3º libera ------------------------
echo c >> "$P/f.txt"; G add -A; G commit -qm mexe        # recibo vence
run "$(payload sT)"; r1="$OUT"
run "$(payload sT)"; r2="$OUT"
run "$(payload sT)"; r3="$OUT"
[[ -n "$r1" && -n "$r2" && -z "$r3" ]] && ok "teto 2: bloqueia 2×, o 3º libera" || bad "teto (r1='${r1:0:30}' r2='${r2:0:30}' r3='${r3:0:30}')"

# --- fail-open ----------------------------------------------------------------
printf '#!/bin/sh\nsleep 5\n' > "$tmp/fakeroot/bin/maestro"
t0=$EPOCHREALTIME; run "$(payload sF)" CLAUDE_PLUGIN_ROOT="$tmp/fakeroot"; t1=$EPOCHREALTIME
ms=$(( (${t1/./} - ${t0/./}) / 1000 ))
[[ $RC -eq 0 && -z "$OUT" && $ms -lt 3500 ]] && ok "CLI travado: timeout de 2 s e libera (${ms}ms)" || bad "timeout não liberou (rc=$RC, ${ms}ms)"
printf '#!/bin/sh\necho lixo\nexit 2\n' > "$tmp/fakeroot/bin/maestro"
run "$(payload sG)" CLAUDE_PLUGIN_ROOT="$tmp/fakeroot"; [[ $RC -eq 0 && -z "$OUT" ]] && ok "CLI com erro (rc 2): libera" || bad "erro do CLI bloqueou"
run "$(payload sH)" CLAUDE_PLUGIN_ROOT="$tmp/nao-existe"; [[ $RC -eq 0 && -z "$OUT" ]] && ok "CLI ausente: libera" || bad "CLI ausente bloqueou"

# --- orçamentos de latência ---------------------------------------------------
maestro_latency_read_load
G checkout -q main
cat > "$tmp/wrap-comum.sh" <<EOF
#!/usr/bin/env bash
cd "$P" && CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$REPO" exec bash "$HOOK"
EOF
chmod +x "$tmp/wrap-comum.sh"; payload sL > "$tmp/in.json"
maestro_latency_measure "$tmp/wrap-comum.sh" "$tmp/in.json"
maestro_latency_report "stop comum (sem ordem)" "$MIN" "$MED" "$MAX" 50
case "$MAESTRO_LATENCY_VERDICT" in
  ok) ok "latência do caminho comum dentro do orçamento de 50 ms" ;;
  inconclusivo) printf 'INCONCLUSIVO sob carga: caminho comum (mediana %sms)\n' "$MED" ;;
  *) bad "caminho comum estourou 50 ms (mediana ${MED}ms)" ;;
esac
G checkout -q "$BR1"
cat > "$tmp/wrap-turno.sh" <<EOF
#!/usr/bin/env bash
cd "$P" && CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$REPO" MAESTRO_HOME="$tmp/home-lat" exec bash "$HOOK"
EOF
chmod +x "$tmp/wrap-turno.sh"
MAESTRO_LATENCY_N=7 maestro_latency_measure "$tmp/wrap-turno.sh" "$tmp/in.json"
printf '     %-24s min=%sms  mediana=%sms  max=%sms  (orçamento declarado: 2000 ms por turno)\n' "stop de turno (com ordem)" "$MIN" "$MED" "$MAX"
(( MED < 2000 )) && ok "Stop de turno com ordem em curso dentro do teto de 2 s" || bad "Stop de turno estourou 2 s (mediana ${MED}ms)"

exit "$fail"
