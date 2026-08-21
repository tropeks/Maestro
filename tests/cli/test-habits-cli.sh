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

echo "-- S-905: catraca de baseline"
git -C "$PROJ" rm -q -f novo.py 2>/dev/null || rm -f "$PROJ/novo.py"
git -C "$PROJ" add -A; git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm limpa
cat > "$PROJ/legado.py" <<'FX'
def velho(x):
    try:
        return g(x)
    except Exception:
        pass
FX
git -C "$PROJ" add -A; git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm legado
out=$("$BIN" habits --baseline --project "$PROJ"); rc=$?
chk "--baseline grava e sai 0" "$rc" "0"
[[ -f "$PROJ/.maestro-habits.tsv" ]] && ok "baseline versionável no projeto" || bad "baseline versionável no projeto"
grep -q 'swallowed-error	1' "$PROJ/.maestro-habits.tsv" && ok "contagem por smell no tsv" || bad "contagem por smell no tsv"
out=$("$BIN" habits --all --project "$PROJ"); rc=$?
chk "dívida IGUAL ao baseline passa (catraca, não zero-tolerância)" "$rc" "0"
grep -q 'dentro da catraca' <<<"$out" && ok "veredito nomeia a catraca" || bad "veredito nomeia a catraca"
cat > "$PROJ/novo2.py" <<'FX'
def h(y):
    try:
        return k(y)
    except Exception:
        pass
FX
out=$("$BIN" habits --all --project "$PROJ"); rc=$?
chk "slop NOVO acima do baseline reprova (mesmo untracked)" "$rc" "1"
grep -q 'CATRACA.*swallowed-error: 2 > baseline 1' <<<"$out" \
  && ok "reprova nomeando smell e contagens" || bad "reprova nomeando smell e contagens ($out)"
rm -f "$PROJ/novo2.py" "$PROJ/legado.py"
out=$("$BIN" habits --all --project "$PROJ"); rc=$?
chk "dívida paga continua passando" "$rc" "0"
grep -q 'a régua pode descer' <<<"$out" && ok "melhora convida a baixar a catraca" \
                                        || bad "melhora convida a baixar a catraca ($out)"
"$BIN" habits --baseline --project "$PROJ" >/dev/null
grep -qv 'swallowed-error' "$PROJ/.maestro-habits.tsv" && ok "regravar desce a régua" || bad "regravar desce a régua"
out=$("$BIN" habits --project "$PROJ" "$PROJ/base.py"); rc=$?
chk "escopo por caminho IGNORA baseline (régua é do repo inteiro)" "$rc" "0"
rm -f "$PROJ/.maestro-habits.tsv"

echo "-- S-904: /maestro:deslop registrado no plugin"
CMD="$REPO/commands/deslop.md"
[[ -f "$CMD" ]] && ok "commands/deslop.md existe" || bad "commands/deslop.md existe"
head -1 "$CMD" | grep -q '^---$' && ok "frontmatter presente" || bad "frontmatter presente"
grep -q '^description:' "$CMD" && ok "description no frontmatter" || bad "description no frontmatter"
grep -q 'maestro habits --all' "$CMD" && ok "comando usa o sensor como worklist" \
                                      || bad "comando usa o sensor como worklist"
grep -q 'nunca burlar' "$CMD" && ok "regra de ouro dos guias no comando" || bad "regra de ouro dos guias"
grep -q 'reverta o' "$CMD" && ok "suíte como gate entre lotes, com reversão" \
                                || bad "suíte como gate entre lotes"
grep -q -- '--baseline' "$CMD" && ok "catraca desce junto com a dívida" || bad "catraca desce junto"
grep -q 'NUNCA supressão inline' "$CMD" && ok "falso positivo vai para config, não supressão" \
                                        || bad "falso positivo vai para config"

echo "-- sensor único: hook e CLI usam o MESMO motor"
n=$(grep -c 'habit-sensors.awk' "$REPO/hooks/post-edit-habits.sh" "$REPO/bin/maestro" | awk -F: '{s+=$2} END {print (s>=2) ? "ok" : "nao"}')
chk "ambos referenciam hooks/lib/habit-sensors.awk" "$n" "ok"

exit $fail
