#!/usr/bin/env bash
# ordem 059 — contrato de entrada: cada uma das cinco falhas (a a e) reprova
# com exit 1 e a linha de motivo certa; falhas múltiplas saem uma linha cada.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/entry-fixture.sh"
entry_pendente

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
expect() { # <rótulo> <regex do motivo> <rc> <saída>
  [[ $3 -eq 1 ]] && grep -qE "$2" <<<"$4" && ok "$1" || bad "$1 (rc $3): $4"
}

# (a) não commitado no branch -------------------------------------------------
entry_project pa
entry_order "nao commitada" "$TURNO_OK
$CRIT_OK"
out=$(entry_chk 1); rc=$?
expect "(a) arquivo fora do branch" '\(a\).*(não existe|não está commitado)' $rc "$out"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
echo "- mudança solta" >> "$OF"
out=$(entry_chk 1); rc=$?
expect "(a) arquivo alterado depois do commit" '\(a\).*não commitadas' $rc "$out"
grep -c 'reprovada' <<<"$out" | grep -qx 1 && ok "(a) uma linha só para a falha" || bad "(a) linhas extras: $out"

# (b) Turno inválido ----------------------------------------------------------
entry_project pb
entry_order "sem turno" "$(printf '%s\n' "$TURNO_OK" | grep -v '^- fim:')
$CRIT_OK"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
out=$(entry_chk 1); rc=$?
expect "(b) Turno sem fim:" '\(b\).*fim' $rc "$out"

# (c) critério sem oráculo / sem a seção --------------------------------------
entry_project pc
entry_order "critério solto" "$TURNO_OK
## Critérios de aceite
- [oráculo: \`bash tests/x.sh\`] ok.
- fica bonito no fim"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
out=$(entry_chk 1); rc=$?
expect "(c) critério sem oráculo nem [humano]" '\(c\).*fica bonito' $rc "$out"
entry_project pc2
entry_order "sem seção" "$TURNO_OK"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
out=$(entry_chk 1); rc=$?
expect "(c) sem a seção de critérios" "\(c\).*Critérios de aceite" $rc "$out"

# (d) dependência inexistente / não aceita ------------------------------------
entry_project pd
entry_order "aberta" "$TURNO_OK
$CRIT_OK"
G add -A; G commit -qm "ordem 1"
entry_order "dependente" "depende_de: 001, 077
$TURNO_OK
$CRIT_OK"
OF=$(ls "$P"/.maestro/orders/002-*.md); entry_commit_on_branch "$OF"
out=$(entry_chk 2); rc=$?
expect "(d) dependência não aceita" '\(d\).*001.*não .aceita' $rc "$out"
expect "(d) dependência inexistente" '\(d\).*077.*não existe' $rc "$out"

# (e) política ausente --------------------------------------------------------
entry_project pe
entry_order "sem politica" "$TURNO_OK
$CRIT_OK"
OF=$(ls "$P"/.maestro/orders/001-*.md); entry_commit_on_branch "$OF"
G rm -q --cached .maestro.yaml; rm -f "$P/.maestro.yaml"; G commit -qm "sem yaml"
out=$(entry_chk 1); rc=$?
expect "(e) sem .maestro.yaml" '\(e\).*\.maestro\.yaml' $rc "$out"
printf 'lixo\n' > "$P/.maestro/INTENT.md"
out=$(entry_chk 1); rc=$?
expect "(e) INTENT inválido" '\(e\).*INTENT' $rc "$out"

# várias falhas → uma linha por falha ----------------------------------------
entry_project pm
entry_order "tudo errado" "depende_de: 099
## Critérios de aceite
- sem oráculo"
out=$(entry_chk 1); rc=$?
n=$(grep -c 'reprovada' <<<"$out")
[[ $rc -eq 1 && $n -ge 4 ]] && ok "várias falhas: $n linhas, exit 1" || bad "várias falhas (rc $rc, $n linhas): $out"

exit $fail
