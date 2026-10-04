#!/usr/bin/env bash
# Ordem 056: o Stop de turno não libera calado quando o CLI estoura o teto.
# Contrato (a) do Diretor: em timeout o hook confere LOCALMENTE os 5 rótulos do
# relatório, sem chamar o CLI. Faltou rótulo, bloqueia com a lista do que falta;
# os 5 presentes, libera. O evento turno_timeout (só metadados) vai ao log e o
# hook sempre sai 0 sem prender. Controles: reentrada, espera ao Diretor, branch
# sem ordem e kill-switch. Custo: o turno-check real abaixo de 700 ms, pelo
# portão de carga de latency.sh.
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
for i in $(seq 1 45); do   # projeto real: dezenas de ordens ANTES da ordem do branch (a busca custava ~600 ms com 51)
  sed -e "s/^id: 001$/id: 000/" -e "s#^branch: order/001-#branch: order/000-#" "$P"/.maestro/orders/001-*.md > "$P/.maestro/orders/000-filler-$i.md"
done
G add -A; G commit -qm ordem
BR1=$(grep '^branch:' "$P"/.maestro/orders/001-*.md | awk '{print $2}')
G checkout -qb "$BR1"; echo b >> "$P/f.txt"; G add -A; G commit -qm entrega

# CLI "lento": dorme acima do teto de 2 s (o `timeout` do hook devolve 124)
mkdir -p "$tmp/slow/bin"
printf '#!/bin/sh\necho chamado >> "%s/cli.log"\nsleep 5\n' "$tmp" > "$tmp/slow/bin/maestro"; chmod +x "$tmp/slow/bin/maestro"

payload() { printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":%s}' "$1" "${2:-}" "${3:-false}"; }
run() { # <stdin> [VAR=val ...] → stdout do hook em $OUT, rc em $RC
  local in="$1"; shift
  OUT=$(cd "$P" && env CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$tmp/slow" "$@" bash "$HOOK" <<<"$in" 2>/dev/null); RC=$?
}
tr_line() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$tmp/tr.jsonl"; }
FULL='feito: a\nprovado: b\naberto: c\ndecisão: d\npróximo: e'

# --- 124 com relatório SEM rótulos → bloqueia, lista o que falta --------------
tr_line 'texto livre sem rotulos'
run "$(payload sA "$tmp/tr.jsonl")"
if [[ $RC -eq 0 && "$OUT" == '{"decision":"block","reason":"'* ]] && grep -q 'feito' <<<"$OUT" && grep -q 'próximo' <<<"$OUT"; then
  ok "124 sem rótulos: block com a lista do que falta"
else bad "124 sem rótulos liberou calado (rc=$RC out=${OUT:0:80})"; fi

# --- 124 com rótulos faltando (parcial) → lista só os que faltam --------------
tr_line 'feito: a\nprovado: b'
run "$(payload sB "$tmp/tr.jsonl")"
lista="${OUT#*rótulos: }"; lista="${lista%%. Escreva*}"
if [[ "$lista" == "aberto decisão próximo" ]]; then
  ok "124 com relatório parcial: lista só aberto/decisão/próximo"
else bad "lista parcial errada (${OUT:0:120})"; fi

# --- 124 com os 5 rótulos → libera -------------------------------------------
tr_line "$FULL"
run "$(payload sC "$tmp/tr.jsonl")"
[[ $RC -eq 0 && -z "$OUT" ]] && ok "124 com os 5 rótulos: libera" || bad "124 com relatório completo bloqueou (${OUT:0:80})"

# --- o 124 deixa rastro: turno_timeout no log, só metadados ------------------
lg=$(cat "$MAESTRO_HOME"/logs/* 2>/dev/null)
grep -q 'turno_timeout' <<<"$lg" && ok "evento turno_timeout registrado" || bad "turno_timeout ausente do log"
grep -q 'texto livre\|feito: a' <<<"$lg" && bad "log vazou texto da mensagem" || ok "log só com metadados (sem texto da mensagem)"

# --- controles: sempre exit 0, sem prender -----------------------------------
tr_line 'texto livre sem rotulos'
run "$(payload sD "$tmp/tr.jsonl" true)"; [[ $RC -eq 0 && -z "$OUT" ]] && ok "stop_hook_active libera" || bad "reentrada bloqueou"
tr_line '[spock] aguardando: posso seguir?'
run "$(payload sE "$tmp/tr.jsonl")"; [[ $RC -eq 0 && -z "$OUT" ]] && ok "[spock] aguardando: libera" || bad "bloqueou rodada que pergunta"
tr_line 'texto livre sem rotulos'
run "$(payload sF "$tmp/tr.jsonl")" MAESTRO_OFF=1; [[ $RC -eq 0 && -z "$OUT" ]] && ok "MAESTRO_OFF=1 libera" || bad "kill-switch bloqueou"
G checkout -q main
run "$(payload sG "$tmp/tr.jsonl")"; [[ $RC -eq 0 && -z "$OUT" ]] && ok "branch sem ordem libera" || bad "main bloqueou"
G checkout -q "$BR1"

# --- custo: o CLI real, sob o portão de carga --------------------------------
maestro_latency_read_load
rf="$tmp/rel.txt"; printf 'feito: x\n' > "$rf"
cat > "$tmp/wrap-check.sh" <<EOF
#!/usr/bin/env bash
exec "$BIN" order --turno-check --project "$P" --session lat --report-file "$rf"
EOF
chmod +x "$tmp/wrap-check.sh"; : > "$tmp/in.json"
MAESTRO_LATENCY_N=9 maestro_latency_measure "$tmp/wrap-check.sh" "$tmp/in.json"
maestro_latency_report "order --turno-check" "$MIN" "$MED" "$MAX" 700
case "$MAESTRO_LATENCY_VERDICT" in
  ok) ok "turno-check dentro do orçamento (mediana ${MED}ms)" ;;
  inconclusivo) printf 'INCONCLUSIVO sob carga: turno-check (mediana %sms)\n' "$MED" ;;
  *) bad "turno-check estourou 700 ms (mediana ${MED}ms)" ;;
esac

exit "$fail"
