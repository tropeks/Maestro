#!/usr/bin/env bash
# ordem 081 — o accept/status dispensa os recibos de CÓDIGO quando o diff contra o merge-base com o branch
# padrão remoto só toca `docs_only_paths` (lista lida do .maestro.yaml do merge-base). O recibo order-NN segue exigido.
#
# (a) só docs dispensa, e diz (saída + ledger) · (b) misto não · (c) sem a chave não · (d) o master trazido por
# merge dispensa (caso NetForge 108) e, sem a chave, o mesmo branch cobra tudo · (e) código renomeado para docs
# não · (f) remoção de código não · (g) sem o order-NN o accept recusa · (h) o glob `**/*.md` pega a raiz.
# MAESTRO_REPO_UNDER_TEST aponta outro checkout (o clone de trabalho do patch); padrão: este repo.
set -u

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="${MAESTRO_REPO_UNDER_TEST:-$HERE}"
BIN="$REPO/bin/maestro"

source "$HERE/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$HERE/tests/lib/declare-order.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
source "$HERE/tests/lib/docsonly-fixture.sh"

# has <texto> <padrão> <descrição> / lacks — asserções sobre a saída capturada
has()   { grep -qF -- "$2" <<<"$1" && ok "$3" || { bad "$3"; printf '%s\n' "$1" | sed 's/^/     | /'; }; }
lacks() { grep -qF -- "$2" <<<"$1" && { bad "$3"; printf '%s\n' "$1" | sed 's/^/     | /'; } || ok "$3"; }

commit_docs() { echo x > "$P/docs/x.md"; G add -A; G commit -qm "doc"; dz_record; }

# Todos os casos partem do master trazido por merge (a main local fica velha): é onde o verificador de áreas de hoje
# vê código "tocado" num diff que, contra o merge-base com origin/HEAD, é só de docs. Sem isso a recusa nunca existiria.

# --- (a) só docs dispensa
dz_merge_case a; commit_docs
st=$(dz_status); out=$(dz_accept); rc=$?; led=$(dz_ledger)
has "$st" "recibos de código DISPENSADOS" "(a) status diz a dispensa"
has "$st" "docs/x.md" "(a) status lista o arquivo"
(( rc == 0 )) && ok "(a) accept aceita só-docs sem recibo de código (rc 0)" || { bad "(a) accept recusou só-docs (rc $rc)"; echo "$out"; }
has "$out" "recibos de código DISPENSADOS" "(a) accept diz a dispensa"
has "$out" "docs/x.md" "(a) accept lista o arquivo"
has "$led" "docs_only_dispensa=1" "(a) ledger marca a dispensa"
has "$led" "docs_only_files=docs/x.md" "(a) ledger lista os arquivos"
has "$led" "outcome=aceita" "(a) ledger registra o aceite"

# --- (b) misto não dispensa
dz_merge_case b; echo b > "$P/src/b.ts"; commit_docs
st=$(dz_status); out=$(dz_accept); rc=$?; led=$(dz_ledger)
(( rc != 0 )) && ok "(b) misto: accept recusa" || bad "(b) misto: accept aceitou"
has "$out" "toca área com verificação obrigatória e falta prova" "(b) cobra os recibos de código como hoje"
lacks "$st$out" "DISPENSADOS" "(b) não diz dispensa"
[[ -z "$led" ]] && ok "(b) ledger intacto" || bad "(b) ledger gravado"

# --- (c) sem a chave não dispensa (saída sem nenhuma menção)
dz_merge_case c "$(dz_yaml '')"; commit_docs
st=$(dz_status); out=$(dz_accept); rc=$?; led=$(dz_ledger)
(( rc != 0 )) && ok "(c) sem a chave: accept recusa" || bad "(c) sem a chave: accept aceitou"
has "$out" "toca área com verificação obrigatória e falta prova" "(c) cobra como hoje"
lacks "$st$out" "dispens" "(c) saída sem menção à dispensa"
lacks "$st$out" "DISPENSADOS" "(c) saída sem DISPENSADOS"
[[ -z "$led" ]] && ok "(c) ledger intacto" || bad "(c) ledger gravado"

# --- (d) o master trazido por merge: caso NetForge 108 (a main local fica velha; origin/main anda e entra por merge)
merge_case() { dz_merge_case "$@"; commit_docs; }
merge_case d
st=$(dz_status); out=$(dz_accept); rc=$?; led=$(dz_ledger)
(( rc == 0 )) && ok "(d) branch com o master por merge e diff real só de docs: dispensa e aceita" || { bad "(d) recusou (rc $rc)"; echo "$out"; }
has "$out" "docs/x.md" "(d) a lista é só o diff real contra o merge-base"
lacks "$out" "src/m.ts" "(d) o código que veio do master não entra na lista"
has "$led" "docs_only_dispensa=1" "(d) ledger marca a dispensa"
merge_case d2 "$(dz_yaml '')"
out=$(dz_accept); rc=$?
(( rc != 0 )) && has "$out" "toca área com verificação obrigatória e falta prova" "(d) o mesmo branch SEM a chave cobra tudo" \
  || bad "(d) o mesmo branch sem a chave aceitou"

# --- (e) código renomeado para docs não dispensa
dz_merge_case e; G mv src/a.ts docs/a.ts.md; G commit -qm "move"; dz_record
st=$(dz_status); out=$(dz_accept); rc=$?
(( rc != 0 )) && ok "(e) renomeado de código para docs: accept recusa" || bad "(e) renomeado dispensou"
lacks "$st$out" "DISPENSADOS" "(e) sem dispensa"
has "$out" "toca área com verificação obrigatória e falta prova" "(e) cobra os recibos de código"

# --- (f) remoção de código não dispensa
dz_merge_case f; G rm -q src/a.ts; G commit -qm "remove"; dz_record
st=$(dz_status); out=$(dz_accept); rc=$?
(( rc != 0 )) && ok "(f) remoção de código: accept recusa" || bad "(f) remoção dispensou"
lacks "$st$out" "DISPENSADOS" "(f) sem dispensa"

# --- (g) o order-NN continua exigido: só docs, sem recibo
dz_merge_case g; echo x > "$P/docs/x.md"; G add -A; G commit -qm doc
st=$(dz_status); out=$(dz_accept); rc=$?; led=$(dz_ledger)
(( rc != 0 )) && ok "(g) só docs sem recibo order-NN: accept recusa" || bad "(g) aceitou sem o order-NN"
has "$out" "não 'provada'" "(g) a razão é a prova da ordem, não a CI de código"
[[ -z "$led" ]] && ok "(g) ledger intacto" || bad "(g) ledger gravado"

# --- (h) `**/*.md` pega a raiz e subpastas (o glob do git acompanha o paths-ignore do GitHub)
dz_merge_case h; echo r2 > "$P/README.md"; mkdir -p "$P/deep/er"; echo y > "$P/deep/er/y.md"; G add -A; G commit -qm "mds"; dz_record
st=$(dz_status)
has "$st" "README.md" "(h) **/*.md casa README.md na raiz"
has "$st" "deep/er/y.md" "(h) **/*.md casa md em subpasta"
G checkout -q "$BR"   # dz_status deixou o checkout na main
echo z > "$P/z.txt"; G add -A; G commit -qm "txt"; dz_record
st=$(dz_status)
lacks "$st" "DISPENSADOS" "(h) um .txt na raiz não casa e impede a dispensa"

exit $fail
