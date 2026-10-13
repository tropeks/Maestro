#!/usr/bin/env bash
# ordem 081 — fixture dos testes da dispensa de recibos de código (docs_only_paths).
# Quem faz `source` já definiu BIN (bin/maestro sob teste), tmp, MAESTRO_HOME exportado e ok()/bad(),
# e já fez `source tests/lib/declare-order.sh`.
#
#   dz_yaml [docs_only_paths-linha]   → texto do .maestro.yaml (área `code`: src/ exige o rótulo suite)
#   dz_fixture <nome> [yaml]          → projeto P com origin bare, origin/HEAD, ordem 1 declarada, branch BR
#                                       aberto (checkout nele). `yaml` omitido = dz_yaml com a lista padrão.
#   dz_record                         → grava o recibo order-1 no tip do branch
#   dz_status / dz_accept             → saída de `order --status 1` / `order --accept 1` (a partir da main)
#   dz_ledger                         → conteúdo do registro terminal da ordem 1 (vazio se não há)

# hermético: o bwrap exporta estas duas e os repos de mktemp nascem sem `objects` (ordem 081, Ask-First 4)
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

DZ_LIST='docs_only_paths: [docs/**, .maestro/**, "**/*.md"]'

dz_yaml() {
  printf 'verifications:\n  code:\n    paths: [src/]\n    labels: [suite]\ncommands:\n  suite: true\n%s\n' "${1-$DZ_LIST}"
}

dz_fixture() {
  local name="$1" yaml="${2-}" O
  [[ $# -ge 2 ]] || yaml=$(dz_yaml)
  P="$tmp/$name"; O="$tmp/$name.git"; mkdir -p "$P/src" "$P/docs"
  export MAESTRO_HOME="$tmp/home-$name"   # ledger próprio por fixture
  git init -q --bare -b main "$O"
  git -C "$P" init -q -b main
  echo a > "$P/src/a.ts"; echo d > "$P/docs/d.md"; echo r > "$P/README.md"
  printf '%s\n' "$yaml" > "$P/.maestro.yaml"
  G add -A; G commit -qm base
  "$BIN" order --create --title "Docs" --project "$P" --session dir-1 >/dev/null <<'BODY'
## Objetivo
So docs.
BODY
  G add -A; G commit -qm "ordem 1"
  declare_order "$P" 1 true
  G remote add origin "$O"; G push -q -u origin main 2>/dev/null; G remote set-head origin main >/dev/null
  BR=$(grep '^branch:' "$P"/.maestro/orders/001-*.md | awk '{print $2}')
  G checkout -qb "$BR"
}

dz_record() { "$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null 2>&1; }

dz_status() { G checkout -q main 2>/dev/null; "$BIN" order --status 1 --project "$P" 2>&1; }

dz_accept() { G checkout -q main 2>/dev/null; "$BIN" order --accept 1 --project "$P" --session dir-1 2>&1; }

# só o registro TERMINAL (o diretório também guarda baseline e reserva da ordem)
dz_ledger() {
  local f
  while IFS= read -r f; do cat "$f"; done < <(grep -rl 'schema=maestro-order-state-v1' "$MAESTRO_HOME/order-state" 2>/dev/null)
  return 0
}

# dz_merge_case <nome> [yaml] — a main LOCAL fica velha; origin/main anda (código novo) e entra no branch por merge
# (o caso NetForge 108): o verificador de áreas de hoje vê o código do master como "tocado". Termina sem commit de docs.
dz_merge_case() {
  dz_fixture "$1" ${2+"$2"}
  git clone -q "$tmp/$1.git" "$tmp/$1-other"
  git -C "$tmp/$1-other" -c user.email=t@t -c user.name=t checkout -q main 2>/dev/null
  echo m > "$tmp/$1-other/src/m.ts"
  git -C "$tmp/$1-other" add -A
  git -C "$tmp/$1-other" -c user.email=t@t -c user.name=t commit -qm "codigo novo no master"
  git -C "$tmp/$1-other" push -q origin main 2>/dev/null
  G fetch -q origin
  G merge -q --no-edit origin/main
}
