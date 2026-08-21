#!/usr/bin/env bash
# E9 / S-903 — `maestro habits`: os mesmos sensores do hook, sobre o diff.
# Sensor único (hooks/lib/habit-sensors.awk): o teste pina que hook e CLI
# apontam para o mesmo motor. Exit: 0 limpo · 1 achados · 2 ambiente.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

PROJ="$tmp/proj"; mkdir -p "$PROJ"
git -C "$PROJ" init -q
printf 'def soma(a, b):\n    return a + b\n' > "$PROJ/base.py"
git -C "$PROJ" add -A; git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm base

echo "-- diff limpo"
out=$("$BIN" habits --project "$PROJ"); rc=$?
chk "sem mudanças → exit 0" "$rc" "0"
grep -q 'diff limpo' <<<"$out" && ok "explica que o diff está limpo" || bad "explica que o diff está limpo ($out)"

echo "-- diff sujo com smell"
cat > "$PROJ/novo.py" <<'FX'
def f(data):
    try:
        return g(data)
    except Exception:
        pass
FX
out=$("$BIN" habits --project "$PROJ"); rc=$?
chk "achado no diff → exit 1" "$rc" "1"
grep -q 'novo.py:.*swallowed-error' <<<"$out" && ok "achado nomeia arquivo:linha e smell" \
                                              || bad "achado nomeia arquivo:linha e smell ($out)"
grep -q '\*\*swallowed-error\*\*' <<<"$out" && ok "guia sai junto do achado" || bad "guia sai junto do achado"

echo "-- caminhos explícitos e --all"
out=$("$BIN" habits --project "$PROJ" "$PROJ/base.py"); rc=$?
chk "caminho explícito limpo → exit 0" "$rc" "0"
git -C "$PROJ" add -A; git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm novo
out=$("$BIN" habits --all --project "$PROJ"); rc=$?
chk "--all varre o repo inteiro → acha o smell commitado" "$rc" "1"

echo "-- config do projeto vale para o CLI também"
printf 'version: 1\nhabits: []\n' > "$PROJ/.maestro.yaml"
out=$("$BIN" habits --all --project "$PROJ"); rc=$?
chk "habits: [] → CLI desligado, exit 0" "$rc" "0"
grep -q 'desligado' <<<"$out" && ok "diz que o projeto desligou" || bad "diz que o projeto desligou"
rm -f "$PROJ/.maestro.yaml"

echo "-- validação e ambiente"
"$BIN" habits --flag-x --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "flag desconhecida → exit 1" "$rc" "1"
NOGIT="$tmp/semgit"; mkdir -p "$NOGIT"; printf 'x=1\n' > "$NOGIT/a.py"
"$BIN" habits --all --project "$NOGIT" >/dev/null 2>&1; rc=$?
chk "--all fora de git → exit 2 (ambiente)" "$rc" "2"

echo "-- sensor único: hook e CLI usam o MESMO motor"
n=$(grep -c 'habit-sensors.awk' "$REPO/hooks/post-edit-habits.sh" "$REPO/bin/maestro" | awk -F: '{s+=$2} END {print (s>=2) ? "ok" : "nao"}')
chk "ambos referenciam hooks/lib/habit-sensors.awk" "$n" "ok"

exit $fail
