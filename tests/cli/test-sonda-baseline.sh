#!/usr/bin/env bash
# ordem 016 PR1 — `probe_ms` gravado no recibo (`maestro evidence --record`).
#
# `lib/`, `bin/` e `hooks/` não se editam direto (contrato de execução): a
# mudança de `lib/core-evidence.sh` e `lib/cmd-evidence.sh` vive em
# docs/patches/016-sonda-core-evidence.patch e
# docs/patches/016-sonda-cmd-evidence.patch. Este teste roda SEMPRE — contra
# o repo tal como está. Se os patches ainda não foram aplicados (caso do
# worktree onde a ordem foi escrita, antes do Capitão aplicar), reporta
# PENDENTE em vez de FAIL, mesmo padrão tolerante do molde reaproveitado de
# tests/lib/test-limiar-ncpu.sh (branch fix/016-limiar-relativo-ncpu,
# superseded — só o padrão de tolerância foi reaproveitado, não a calibração
# por ncpu, que esta ordem rejeitou).
#
# O que se prova NÃO é "probe_ms vale X" (o valor é da máquina) — é que o
# campo É GRAVADO, é aditivo (recibo sem a linha continua lendo normalmente,
# mesma tolerância de `load1m_x100`/`ncpu`/`inconclusive`) e não deslocou
# nenhum campo pré-existente da janela do leitor.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

fail=0
ok()      { printf 'ok   %s\n' "$1"; }
bad()     { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

if ! grep -qF '_ev_cmd_measure_probe' "$REPO/lib/cmd-evidence.sh" 2>/dev/null \
  || ! grep -qF 'probe_ms' "$REPO/lib/core-evidence.sh" 2>/dev/null; then
  pending "ordem 016 PR1: lib/core-evidence.sh e/ou lib/cmd-evidence.sh ainda sem probe_ms — aplicar docs/patches/016-sonda-*.patch"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

P="$tmp/proj"; mkdir -p "$P"; git -C "$P" init -q
echo base > "$P/f"
git -C "$P" -c user.email=t@t -c user.name=t add -A
git -C "$P" -c user.email=t@t -c user.name=t commit -qm x

echo "-- probe_ms é gravado por --record"
"$BIN" evidence --record --project "$P" -- true >/dev/null
EF=$(ls "$MAESTRO_HOME/evidence/" | head -1)
[[ -n "$EF" ]] || { bad "recibo não foi gravado"; exit 1; }
probe_line=$(awk -F= '/^probe_ms=/{print $2}' "$MAESTRO_HOME/evidence/$EF")
if [[ "$probe_line" =~ ^[0-9]+$ ]]; then
  ok "probe_ms=$probe_line — inteiro, nenhum float (CLAUDE.md)"
else
  bad "probe_ms ausente ou não-inteiro no recibo (obtido '$probe_line')"
fi

echo "-- campos pré-existentes não saíram da janela do leitor"
for campo in schema label ts epoch cmd_hash exit wtree_before wtree_after cmd_match \
             load1m_x100 ncpu inconclusive; do
  grep -q "^${campo}=" "$MAESTRO_HOME/evidence/$EF" \
    && ok "campo '$campo' continua presente" || bad "campo '$campo' sumiu do recibo"
done

echo "-- leitura continua VÁLIDA com o campo novo presente"
out=$("$BIN" evidence --project "$P")
grep -q 'VÁLIDA' <<<"$out" && ok "VÁLIDA com probe_ms no recibo" || bad "leitura ($out)"

echo "-- aditivo: recibo SEM probe_ms (formato anterior a esta ordem) continua legível"
sed -i '/^probe_ms=/d' "$MAESTRO_HOME/evidence/$EF"
grep -q '^probe_ms=' "$MAESTRO_HOME/evidence/$EF" && bad "fixture: linha não foi removida" \
  || ok "fixture: recibo sem a linha probe_ms"
out=$("$BIN" evidence --project "$P")
grep -q 'VÁLIDA' <<<"$out" \
  && ok "recibo anterior à ordem 016 (sem probe_ms) segue VÁLIDA — leitor tolerante" \
  || bad "recibo antigo deixou de valer ($out)"

exit $fail
