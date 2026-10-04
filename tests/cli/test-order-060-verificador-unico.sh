#!/usr/bin/env bash
# ordem 060 — a prova tem UMA verdade: evidence --check, order --status e order --accept
# aplicam o mesmo veredito (maestro_proof_verdict, lib/core-proof-verdict.sh).
#
# Seis recibos de fixture, cada um num projeto próprio; para cada caso o veredito dos três
# leitores lado a lado (V = válido, I = inválido). Passa quando os três concordam e
# concordam com o rigoroso (o de `evidence --check`): só o caso (f) é válido.
# MAESTRO_REPO_UNDER_TEST aponta outro checkout (o sandbox do patch); padrão: este repo.
set -u

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="${MAESTRO_REPO_UNDER_TEST:-$HERE}"
BIN="$REPO/bin/maestro"

source "$HERE/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

# fixture <nome> → $tmp/<nome> com a ordem 001 num branch com entrega; commands.order declarado
# e a área f.txt exigindo o rótulo `order`. Define P, BR; EF = recibo order-1 gravado no tip.
fixture() {
  P="$tmp/$1"; mkdir -p "$P"
  git -C "$P" init -q -b main
  echo a > "$P/f.txt"
  printf 'verifications:\n  f:\n    paths: [f.txt]\n    labels: [order]\ncommands:\n  order: true\n' > "$P/.maestro.yaml"
  G add -A; G commit -qm base
  "$BIN" order --create --title "Prova" --project "$P" --session dir-1 >/dev/null <<'BODY'
## Objetivo
Uma verdade só.
BODY
  G add -A; G commit -qm "ordem 1"
  BR=$(grep '^branch:' "$P"/.maestro/orders/001-*.md | awk '{print $2}')
  G checkout -qb "$BR"; echo b >> "$P/f.txt"; G add -A; G commit -qm entrega
  "$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null 2>&1
  EF=$(ls -t "$MAESTRO_HOME"/evidence/*-order-1 2>/dev/null | head -1)
  [[ -f "$EF" ]] || { bad "fixture $1: recibo order-1 não gravado"; return 1; }
}

# leitores: imprimem V (válido) ou I (inválido)
r_evidence() { "$BIN" evidence --check --label order-1 --project "$P" >/dev/null 2>&1 && echo V || echo I; }
r_status()   { "$BIN" order --status 1 --json --project "$P" 2>&1 | grep -q '"estado":"provada"' && echo V || echo I; }
r_accept()   { G checkout -q main; "$BIN" order --accept 1 --project "$P" --session dir-1 >/dev/null 2>&1 && echo V || echo I; }

# caso <id> <esperado V|I> <descrição> <sed-expr ou vazio>
rows=""
caso() {
  local id="$1" want="$2" desc="$3" expr="$4" e s a
  fixture "caso-$id" || return 0
  [[ -n "$expr" ]] && sed -i "$expr" "$EF"
  e=$(r_evidence); s=$(r_status); a=$(r_accept)
  rows+=$(printf '| %s | %-34s | %s | %s | %s | %s |' "$id" "$desc" "$e" "$s" "$a" "$want")$'\n'
  if [[ "$e" == "$want" && "$s" == "$want" && "$a" == "$want" ]]; then
    ok "($id) $desc: evidence=$e status=$s accept=$a (esperado $want)"
  else
    bad "($id) $desc: evidence=$e status=$s accept=$a (esperado $want nos três)"
  fi
}

caso a I "árvore mudou na corrida"          's/^wtree_before=.*/wtree_before=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'
caso b I "comando ≠ declarado (cmd_match=no)" 's/^cmd_match=.*/cmd_match=no/'
caso c I "hash do recibo ≠ commands.<label>"  's/^cmd_hash=.*/cmd_hash=0123456789abcdef/'
caso d I "idade acima do teto"               's/^epoch=.*/epoch=1/'
caso e I "exit ≠ 0"                          's/^exit=.*/exit=1/'
caso f V "recibo válido"                      ''

printf '\n| caso | descrição                          | evidence | status | accept | esperado |\n|---|---|---|---|---|---|\n%s\n' "$rows"

# --- controle negativo: ordem JÁ aceita segue `aceita` mesmo com o recibo vencido depois
out=$("$BIN" order --status 1 --json --project "$P" 2>&1)
grep -q '"estado":"aceita"' <<<"$out" && ok "controle: ordem aceita (caso f) deriva aceita" \
  || bad "ordem aceita não deriva aceita: $out"
sed -i 's/^epoch=.*/epoch=1/' "$EF"
"$BIN" order --status 1 --json --project "$P" 2>&1 | grep -q '"estado":"aceita"' \
  && ok "controle: recibo vencido depois do aceite não reabre a ordem" \
  || bad "recibo vencido reabriu ordem aceita"

# --- estrutura: ninguém mantém critério próprio
grep -q 'maestro_proof_verdict' "$REPO/lib/cmd-evidence.sh" \
  && ok "evidence --check chama maestro_proof_verdict" || bad "cmd-evidence.sh não chama maestro_proof_verdict"
grep -q 'maestro_proof_verdict' "$REPO/lib/core-order-state.sh" \
  && ok "_order_evidence_match/_order_verif_report chamam maestro_proof_verdict" || bad "core-order-state.sh não chama maestro_proof_verdict"
grep -q '_order_verif_gate' "$REPO/lib/cmd-order-accept.sh" \
  && ! grep -q '_ev_cmd_reasons' "$REPO"/lib/*.sh \
  && ok "gate do --accept passa por _order_verif_gate → veredito único; _ev_cmd_reasons não existe mais" \
  || bad "_ev_cmd_reasons ainda existe ou accept não usa o veredito"
for f in lib/cmd-evidence.sh lib/core-order-state.sh lib/cmd-order-accept.sh; do
  if grep -nE '"\$e_wb"|"\$e_match"|"\$e_exit"|/\^cmd_match=/|age >= |wtree_before' "$REPO/$f" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
    bad "$f ainda compara wtree_before/cmd_match/idade por conta própria"
  else
    ok "$f não compara wtree_before/cmd_match/idade"
  fi
done
exit $fail
