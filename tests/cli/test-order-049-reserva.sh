#!/usr/bin/env bash
# ordem 049 — numeração de ordens por RESERVA no ledger.
#   `order --create` numerava pelo que estava em .maestro/orders/ da árvore
#   onde rodava: ordem só em branch ou em outro worktree era invisível (070 e
#   072 colidiram no ponte-daemon; a 006 saiu duplicada no Enterprise).
#   Contrato: o número é o maior entre árvore, worktrees, branches locais e
#   remotos e reservas gravadas em ~/.maestro/order-state/, sob lock atômico.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

# lib/ está na denylist de autoproteção do gate: a mudança sai como patch em
# docs/patches/049-reserva-de-numeracao.patch e o Capitão aplica. Mecanismo
# ausente → PENDENTE (nunca reprova); presente → cobra de verdade.
if [[ ! -f "$REPO/lib/core-order-reserve.sh" ]]; then
  echo "PENDENTE  ordem 049: aplique docs/patches/049-reserva-de-numeracao.patch (git apply) e rode de novo"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
G() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

stamp() { # <dir> <nnn> <slug> — escreve uma ordem carimbada
  mkdir -p "$1/.maestro/orders"
  printf '<!-- maestro-order v1\nid: %s\nbranch: order/%s-%s\n-->\n# Ordem %s — %s\n' "$2" "$2" "$3" "$2" "$3" \
    > "$1/.maestro/orders/$2-$3.md"
}
mkorder() { # <dir> <título> → id criado (stdout)
  printf 'corpo\n' | "$BIN" order --create --title "$2" --project "$1" --session s0 2>/dev/null \
    | sed -n 's/^ordem \([0-9]*\) criada.*/\1/p'
}

P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q -b main
stamp "$P" 001 um; stamp "$P" 002 dois; stamp "$P" 003 tres
G "$P" add -A; G "$P" commit -qm base

# --- (1) caso 070/072: ordem só em branch de outro worktree ---------------
WA="$tmp/wa"; WB="$tmp/wb"
G "$P" worktree add -q -b ordem-a "$WA"
G "$P" worktree add -q -b ordem-b "$WB"
stamp "$WA" 004 so-no-branch-a; G "$WA" add -A; G "$WA" commit -qm "ordem 004 so em branch"
id1=$(mkorder "$P" "primeira"); id2=$(mkorder "$WB" "segunda")
if [[ "$id1" =~ ^[0-9]+$ && "$id2" =~ ^[0-9]+$ && "$id1" != "$id2" ]] && (( 10#$id1 >= 5 && 10#$id2 >= 5 )); then
  ok "(1) ordem só em outro worktree/branch é vista; números distintos ($id1, $id2)"
else
  bad "(1) 070/072: ids '$id1' e '$id2' (esperado distintos e >= 005)"
fi
# ...e sem worktree em cima: só o branch local guarda a ordem.
stamp "$WA" 030 so-no-branch-a2; G "$WA" add -A; G "$WA" commit -qm "ordem 030 so em branch"
G "$P" worktree remove --force "$WA"
id1b=$(mkorder "$P" "terceira")
if [[ "$id1b" =~ ^[0-9]+$ ]] && (( 10#$id1b >= 31 )); then ok "(1b) branch local sem worktree continua contado ($id1b)"
else bad "(1b) id '$id1b' (esperado >= 031)"; fi

# --- (2) branch remoto ------------------------------------------------------
R="$tmp/remote.git"; git init -q --bare "$R"
G "$P" remote add origin "$R"
G "$P" push -q origin main
RC="$tmp/rclone"; git clone -q "$R" "$RC" 2>/dev/null
G "$RC" checkout -q -b so-remoto; stamp "$RC" 050 remota; G "$RC" add -A; G "$RC" commit -qm remota
G "$RC" push -q origin so-remoto
G "$P" fetch -q origin
id3=$(mkorder "$P" "apos remoto")
if [[ "$id3" =~ ^[0-9]+$ ]] && (( 10#$id3 >= 51 )); then
  ok "(2) ordem só em branch remoto é vista (próximo $id3 >= 051)"
else
  bad "(2) remoto: id '$id3' (esperado >= 051)"
fi

# --- (3) corrida: criações paralelas, árvores diferentes e a mesma ----------
WC="$tmp/wc"; G "$P" worktree add -q -b ordem-c "$WC"
out="$tmp/race"; : > "$out"
for i in 1 2 3 4 5 6; do
  dir="$P"; (( i % 3 == 1 )) && dir="$WB"; (( i % 3 == 2 )) && dir="$WC"
  ( mkorder "$dir" "corrida $i" >> "$out" ) &
done
wait
n=$(grep -c . "$out"); u=$(sort -u "$out" | grep -c .)
if (( n == 6 && u == 6 )); then ok "(3) 6 criações paralelas: 6 números distintos"
else bad "(3) corrida: $n ids, $u distintos ($(tr '\n' ' ' <"$out"))"; fi

# --- (4) reserva não consumida: --list mostra; expira por validade explícita
Q="$tmp/q"; mkdir -p "$Q"; git -C "$Q" init -q -b main
echo x > "$Q/f"; G "$Q" add -A; G "$Q" commit -qm base
qid=$(MAESTRO_ORDER_RESERVE_TTL=1 mkorder "$Q" "abandonada")
rm -f "$Q"/.maestro/orders/*.md   # ordem nunca commitada: reserva fica sem consumo
L=$("$BIN" order --list --project "$Q" 2>&1)
grep -qi 'reserva' <<<"$L" && grep -q "$qid" <<<"$L" \
  && ok "(4) --list mostra a reserva não consumida" || bad "(4) --list sem a reserva $qid: $L"
sleep 2
L=$("$BIN" order --list --project "$Q" 2>&1)
grep -qi 'expirad' <<<"$L" && ok "(4) --list acusa a reserva expirada, não a esconde" \
  || bad "(4) reserva vencida não aparece como expirada: $L"

# --- (5) colisão detectada depois é ERRO ------------------------------------
D="$tmp/d"; mkdir -p "$D"; git -C "$D" init -q -b main
echo x > "$D/f"; G "$D" add -A; G "$D" commit -qm base
stamp "$D" 007 a; stamp "$D" 007 b
"$BIN" order --list --project "$D" >"$tmp/l.out" 2>&1; rc=$?
(( rc != 0 )) && grep -qi 'duplicad' "$tmp/l.out" \
  && ok "(5) --list: id duplicado é erro (rc $rc)" || bad "(5) --list rc=$rc: $(cat "$tmp/l.out")"
"$BIN" order --status 7 --project "$D" >"$tmp/s.out" 2>&1; rc=$?
(( rc != 0 )) && grep -qi 'duplicad' "$tmp/s.out" \
  && ok "(5) --status: id duplicado é erro (rc $rc)" || bad "(5) --status rc=$rc: $(cat "$tmp/s.out")"
"$BIN" conform --check "$D" 2>/dev/null | grep -q 'order-id-duplicado' \
  && ok "(5) conform: acusa order-id-duplicado" || bad "(5) conform não acusa o id duplicado"

# --- (6) compat: o arquivo criado mantém o formato de cabeçalho ------------
f=$(ls "$P"/.maestro/orders/*primeira*.md 2>/dev/null | head -1)
if [[ -n "$f" ]] && head -1 "$f" | grep -qx '<!-- maestro-order v1' \
   && grep -q '^id: ' "$f" && grep -q '^epoch: ' "$f" && grep -q '^author_session: ' "$f"; then
  ok "(6) cabeçalho da ordem inalterado"
else bad "(6) cabeçalho mudou ou ordem ausente ($f)"; fi

exit $fail
