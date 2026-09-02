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

echo "-- S-1807: o sensor é de linha e confundia TEXTO com código"
# Os três casos vieram de uso real no NetForge, todos com o mesmo desfecho: o
# comportamento certo era IGNORAR o sensor. Sensor que se ignora com frequência
# ensina a ignorar sempre — por isso viram teste.
mkdir -p "$PROJ/fp"
# 1) docstring com lista indentada NÃO é deep-nesting
cat > "$PROJ/fp/doc_nesting.py" <<'FX'
"""
Fontes que o relatório soma:
  - support.SupportTicket         (chamados; schema do tenant)
  - billing.InvoiceCollectionLog  (cobrança; schema do tenant)
                                    (continuação bem indentada)
"""
def f():
    return 1
FX
# 2) `@pytest.mark.skip` CITADO num docstring NÃO é teste pulado
cat > "$PROJ/fp/test_doc_skip.py" <<'FX'
class TestAlgo:
    """
    Não dá para usar `@pytest.mark.skipif(...)` como decorator aqui: a
    expressão roda em tempo de COLETA, antes de o banco estar liberado.
    """
    def test_algo(self):
        assert 1 == 1
FX
# 3) marcador `*` de keyword-only NÃO é parâmetro
cat > "$PROJ/fp/kwonly.py" <<'FX'
def make(tenant, *, status, first_seen, acked=None, resolved=None):
    return (tenant, status, first_seen, acked, resolved)
FX
out=$("$BIN" habits "$PROJ/fp/doc_nesting.py" "$PROJ/fp/test_doc_skip.py" "$PROJ/fp/kwonly.py" --project "$PROJ" 2>&1); rc=$?
grep -q 'deep-nesting' <<<"$out" && bad "docstring indentado ainda vira deep-nesting" || ok "docstring indentado não é deep-nesting"
grep -q 'skipped-test' <<<"$out" && bad "skip citado em docstring ainda vira skipped-test" || ok "skip citado em docstring não é teste pulado"
grep -q 'too-many-params' <<<"$out" && bad "marcador '*' ainda conta como parâmetro" || ok "marcador '*' de keyword-only não conta como parâmetro"
chk "os três juntos → exit 0 (limpo)" "$rc" "0"

# E o sensor não pode ficar CEGO: os casos de verdade seguem sendo pegos.
cat > "$PROJ/fp/real.py" <<'FX'
def make(a, b, c, d, e, f):
    return 1
FX
cat > "$PROJ/fp/test_real_skip.py" <<'FX'
import pytest
@pytest.mark.skip(reason="depois")
def test_x():
    assert 1 == 1
FX
out2=$("$BIN" habits "$PROJ/fp/real.py" "$PROJ/fp/test_real_skip.py" --project "$PROJ" 2>&1) || true
grep -q 'too-many-params' <<<"$out2" && ok "seis parâmetros DE VERDADE continuam sendo pegos" || bad "sensor ficou cego para too-many-params"
grep -q 'skipped-test' <<<"$out2" && ok "skip DE VERDADE continua sendo pego" || bad "sensor ficou cego para skipped-test"

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
