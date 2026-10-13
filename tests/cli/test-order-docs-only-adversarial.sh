#!/usr/bin/env bash
# ordem 081 — adversarial da dispensa de recibos de código: nenhum destes casos pode dispensar, e nenhum grava
# a marca da dispensa no ledger. E `order --status` e `order --accept` concordam em todos.
#
# (a) o branch reescreve docs_only_paths no PRÓPRIO .maestro.yaml: vale a lista do merge-base
# (b) padrão inválido/largo: a lista inteira vale como "sem a chave", com aviso
# (c) sem origin/HEAD, ou sem merge-base com ele: não dispensa, com a razão
# (d) diff vazio: não dispensa
# (e) status e accept concordam (aqui, em cada caso acima)
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

has()   { grep -qF -- "$2" <<<"$1" && ok "$3" || { bad "$3"; printf '%s\n' "$1" | sed 's/^/     | /'; }; }
lacks() { grep -qF -- "$2" <<<"$1" && { bad "$3"; printf '%s\n' "$1" | sed 's/^/     | /'; } || ok "$3"; }

# veredito <rótulo> — status e accept sem dispensa e concordando; ledger sem a marca. Usa o P do fixture corrente.
veredito() {
  local label="$1" st out led
  st=$(dz_status); out=$(dz_accept); led=$(dz_ledger)
  lacks "$st" "DISPENSADOS" "$label: status não dispensa"
  lacks "$out" "DISPENSADOS" "$label: accept não dispensa"
  lacks "$led" "docs_only_dispensa" "$label: ledger sem a marca da dispensa"
  VST="$st"; VOUT="$out"; VLED="$led"
}
so_docs() { echo x > "$P/docs/x.md"; G add -A; G commit -qm "doc"; dz_record; }

# --- (a) o branch edita a própria lista para incluir código
# o diff do branch é src/b.ts + o próprio .maestro.yaml: a lista do tip cobre os dois (por isso `.maestro.yaml` entra),
# de modo que lê-la do tip em vez do merge-base DISPENSARIA; só a do merge-base barra.
for lista in 'docs_only_paths: [docs/**, "src/**", ".maestro.yaml"]' 'docs_only_paths: ["**/*.ts", ".maestro.yaml"]' 'docs_only_paths: ["**"]'; do
  dz_fixture "a-${#lista}"
  echo b > "$P/src/b.ts"; sed -i "s|^docs_only_paths:.*|$lista|" "$P/.maestro.yaml"
  G add -A; G commit -qm "codigo + lista propria"; dz_record
  veredito "(a) lista do tip '$lista'"
  has "$VST" "NENHUMA" "(a) os recibos de código continuam cobrados no status"
  [[ -z "$VLED" ]] && ok "(a) ledger intacto" || bad "(a) ledger gravado"
done

# --- (b) padrão inválido ou largo demais invalida a lista toda
for pad in '"**"' '"*"' '"."' '"../x"' '"/etc/**"' '""' '":(top)src"' '"**/*"'; do
  dz_merge_case "b-${#pad}-$RANDOM" "$(dz_yaml "docs_only_paths: [docs/**, $pad]")"
  so_docs
  veredito "(b) padrão $pad"
  has "$VST" "docs_only_paths tem padrão inválido" "(b) $pad: aviso na saída do status"
  [[ -z "$VLED" ]] && ok "(b) $pad: ledger intacto" || bad "(b) $pad: ledger gravado"
done

# --- (c) sem origin/HEAD
dz_merge_case c1; so_docs
G remote set-head origin -d >/dev/null
veredito "(c) sem origin/HEAD"
has "$VST" "sem origin/HEAD resolvível" "(c) status diz a razão"
[[ -z "$VLED" ]] && ok "(c) sem origin/HEAD: ledger intacto" || bad "(c) ledger gravado"
# --- (c) sem merge-base: origin/HEAD aponta para uma história sem ancestral comum
dz_merge_case c2; so_docs
orf=$(G commit-tree "$(G mktree </dev/null)" -m orfao)
git -C "$P" update-ref refs/remotes/origin/outra "$orf"
git -C "$P" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/outra
veredito "(c) sem merge-base"
has "$VST" "sem merge-base" "(c) status diz a razão"
[[ -z "$VLED" ]] && ok "(c) sem merge-base: ledger intacto" || bad "(c) ledger gravado"

# --- (d) diff vazio
dz_merge_case d1; dz_record
veredito "(d) diff vazio"
has "$VST" "diff contra o merge-base vazio" "(d) status diz a razão"

# --- (e) concordância status × accept no caso positivo e no negativo
dz_merge_case e1; so_docs
st=$(dz_status); out=$(dz_accept)
{ grep -qF "DISPENSADOS" <<<"$st" && grep -qF "DISPENSADOS" <<<"$out"; } && ok "(e) positivo: status e accept dizem a dispensa" \
  || bad "(e) positivo: status/accept divergem"
dz_merge_case e2; echo b > "$P/src/b.ts"; so_docs
st=$(dz_status); out=$(dz_accept)
{ ! grep -qF "DISPENSADOS" <<<"$st" && ! grep -qF "DISPENSADOS" <<<"$out"; } && ok "(e) negativo: nenhum dos dois dispensa" \
  || bad "(e) negativo: status/accept divergem"

exit $fail
