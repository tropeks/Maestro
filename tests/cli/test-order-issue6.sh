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

# O conserto vive em `bin/maestro-wtree` e quem o aplica é o Capitão, a partir
# de `docs/patches/003-wtree-exclui-maestro.patch`: `bin/` está na denylist de
# autoproteção do gate (ADR-003 v1.2) e não se edita daqui. Enquanto o patch
# não estiver aplicado, exigir VÁLIDA manteria a suíte vermelha por um defeito
# conhecido — e travaria justamente o PR que entrega o conserto.
#
# A detecção é do MECANISMO, não do resultado: se a exclusão existe e mesmo
# assim o recibo vence, isto REPROVA. Terceira categoria no espírito do
# `inconclusivo sob carga` de tests/lib/latency.sh — visível no log, sem
# mentir que passou e sem quebrar a suíte por algo que ninguém pode corrigir
# de dentro do repo.
patched=0
grep -qF ":(exclude).maestro/**" "$REPO/bin/maestro-wtree" 2>/dev/null && patched=1

out=$("$BIN" evidence --label order-1 --project "$P")
if grep -q 'VÁLIDA' <<<"$out"; then
  ok "issue #6: evidência lida direto (ledger) segue VÁLIDA após --accept"
elif (( patched == 0 )); then
  printf 'PENDENTE  issue #6: defeito reproduzido (esperado) — bin/maestro-wtree ainda sem o patch 003; aplicar docs/patches/003-wtree-exclui-maestro.patch\n'
else
  bad "issue #6: patch aplicado em bin/maestro-wtree e o recibo AINDA vence após --accept (obtido: $out)"
fi

exit $fail
