#!/usr/bin/env bash
# issue #6 (ordem 003) — o carimbo de `order --accept` invalidava o recibo
# que o autorizou. Arquivo PRÓPRIO (não em test-order.sh) para não estourar
# o teto da catraca `oversized-file` — ver commit desta suíte.
#
# Reproduz o caso real (NetForge, ordem 016): ciclo REAL
# `order --create → evidence --record → order --accept`, não uma simulação
# do recibo (por isso este teste não vive em test-evidence.sh: o defeito só
# aparece quando é o PRÓPRIO `--accept` que escreve o carimbo). A fixture
# confere que o carimbo está NO DISCO e AINDA NÃO COMMITADO no momento da
# leitura — é exatamente o estado em que alguém rodaria
# `maestro evidence --label` logo depois de aceitar.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q
echo a > "$P/f.txt"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm base

"$BIN" order --create --title "Issue 6" --project "$P" --session dir-1 \
  >/dev/null <<'BODY'
## Objetivo
Reproduzir o caso do NetForge ordem 016.
BODY
OF=$(ls "$P/.maestro/orders/"001-*.md)
BR=$(grep '^branch:' "$OF" | awk '{print $2}')

git -C "$P" checkout -qb "$BR"
echo b >> "$P/f.txt"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm entrega

"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
"$BIN" order --accept 1 --project "$P" --session dir-1 >/dev/null

# O carimbo (accepted_at/accepted_session/accepted_tree) foi escrito em
# .maestro/orders/001-*.md, um arquivo RASTREADO (E15) — mas ainda NÃO
# commitado. É esta a fixture que reproduz o defeito: sem ela o teste provaria
# outra coisa (o `order --status`, que já contorna via S-1803/accepted_tree,
# não o `evidence` lido direto).
git -C "$P" status --porcelain -- .maestro | grep -q '^ M .*/orders/001-.*\.md$' \
  && ok "fixture: carimbo do aceite está no disco, AINDA não commitado" \
  || bad "fixture: pré-condição do carimbo não commitado (git status: $(git -C "$P" status --porcelain -- .maestro))"

out=$("$BIN" evidence --label order-1 --project "$P")
grep -q 'VÁLIDA' <<<"$out" \
  && ok "issue #6: evidência lida direto (ledger) segue VÁLIDA após --accept" \
  || bad "issue #6: evidência lida direto (ledger) após --accept (obtido: $out)"

exit $fail
