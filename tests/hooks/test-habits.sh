#!/usr/bin/env bash
# E9 / S-901 + S-902 — habit hook pós-edição: sensores anti-slop + guias.
# O contrato que importa: achado → stderr com sensor E guia juntos, exit 2;
# limpo/degradação → exit 0 em silêncio. NUNCA bloqueia nada (a edição já
# aconteceu); NUNCA caminho no log; cooldown segura o ruído.
# Hermético: MAESTRO_HOME, projeto e fixtures em mktemp -d.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/post-edit-habits.sh"
ENGINE="$REPO/hooks/lib/habit-sensors.awk"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

HOME_T="$tmp/home"
PROJ="$tmp/proj"; mkdir -p "$PROJ"

OUT=''; RC=0
run_hook() { # run_hook <file> [tool] [sid] → OUT=stderr, RC=exit
  OUT=$(printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' \
      "${3:-sid-h}" "${2:-Edit}" "$1" \
    | MAESTRO_HOME="$HOME_T" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" 2>&1 >/dev/null)
  RC=$?
  return 0
}

# ---------------------------------------------------------------------------
echo "-- positivos: cada sensor dispara no seu smell"
# ---------------------------------------------------------------------------
cat > "$PROJ/a.py" <<'FX'
def process(data, a=[], b=2, c=3, d=4, e=5, f=6):
    try:
        print(data)
    except Exception:
        pass
    # for i in range(10):
    #     total = compute(i);
    #     acc += total;
    return data  # TODO: implement caching
FX
run_hook "$PROJ/a.py"
chk "achados → exit 2 (feedback ao agente; nada bloqueado)" "$RC" "2"
grep -q '<maestro-habit>' <<<"$OUT" && ok "bloco maestro-habit no stderr" || bad "bloco maestro-habit no stderr"
for smell in too-many-params risky-shortcut debug-leftover; do
  grep -q "$smell" <<<"$OUT" && ok "sensor $smell disparou" || bad "sensor $smell disparou"
done
grep -q 'Warn-only' <<<"$OUT" && ok "deixa claro que é warn-only" || bad "deixa claro que é warn-only"
grep -qE '\*\*[a-z-]+\*\*' <<<"$OUT" && ok "GUIA acompanha o sensor (par indissociável)" \
                                     || bad "GUIA acompanha o sensor"

cat > "$PROJ/b.ts" <<'FX'
// @ts-ignore
const x = resp as any;
function go() {
  try { run(); } catch (e) {}
}
FX
run_hook "$PROJ/b.ts"
for smell in lint-suppression type-escape swallowed-error; do
  grep -q "$smell" <<<"$OUT" && ok "sensor $smell (ts) disparou" || bad "sensor $smell (ts) disparou"
done

# ---------------------------------------------------------------------------
echo "-- adversariais: parecido com smell NÃO é smell"
# ---------------------------------------------------------------------------
cat > "$PROJ/limpo.py" <<'FX'
import logging
def process(data):
    try:
        return transform(data)
    except ValueError as e:
        logging.warning("entrada inválida: %s", e)
        raise
# O parser usa noqa? Não: usa códigos de regra explícitos.
FX
run_hook "$PROJ/limpo.py"
chk "código limpo → exit 0, silêncio" "$RC" "0"
chk "código limpo → stderr vazio" "$OUT" ""

cat > "$PROJ/guarda.sh" <<'FX'
run() {
  command -v jq >/dev/null 2>&1 || return 0
  rm -f "$tmp/x" 2>/dev/null || true
}
FX
run_hook "$PROJ/guarda.sh"
chk "|| true / 2>/dev/null em SHELL é idioma, não smell" "$RC" "0"

mkdir -p "$PROJ/t"
cat > "$PROJ/t/util.test.ts" <<'FX'
test("caso real", () => { console.log(render()); expect(render()).toBe("ok"); });
FX
run_hook "$PROJ/t/util.test.ts"
grep -q 'debug-leftover' <<<"$OUT" && bad "console.log em arquivo de TESTE não dispara" \
                                   || ok "console.log em arquivo de TESTE não dispara"

cat > "$PROJ/t/pulado.test.ts" <<'FX'
it.skip("um dia eu volto", () => {});
expect(true).toBe(true);
FX
run_hook "$PROJ/t/pulado.test.ts"
grep -q 'skipped-test' <<<"$OUT" && ok "teste pulado/asserção vazia dispara EM teste" \
                                 || bad "teste pulado/asserção vazia dispara EM teste"

# ---------------------------------------------------------------------------
echo "-- padrões da 2ª rodada de pesquisa (sloppylint / AI-SLOP-Detector)"
# ---------------------------------------------------------------------------
cat > "$PROJ/pesq.py" <<'FX'
from os.path import *
try:
    go()
except:
    log.warning("falhou")  # hopefully this holds
FX
run_hook "$PROJ/pesq.py" Edit pesq-1
grep -q 'import \*' <<<"$OUT" || grep -q 'risky-shortcut' <<<"$OUT" \
  && ok "from x import * dispara risky-shortcut" || bad "from x import * dispara risky-shortcut"
grep -q 'sem tipo' <<<"$OUT" && ok "except: sem tipo dispara mesmo com corpo real" \
                             || bad "except: sem tipo dispara mesmo com corpo real"
grep -q 'slop-comment' <<<"$OUT" && ok "hedging comment é assinatura de slop" \
                                 || bad "hedging comment é assinatura de slop"
cat > "$PROJ/pesq2.py" <<'FX'
def stub():
    pass
FX
run_hook "$PROJ/pesq2.py" Edit pesq-1
grep -q 'empty-impl' <<<"$OUT" && ok "corpo só-pass dispara empty-impl" \
                               || bad "corpo só-pass dispara empty-impl"

cat > "$PROJ/abstrato.py" <<'FX'
from abc import abstractmethod
class Base:
    @abstractmethod
    def contract(self):
        pass
FX
run_hook "$PROJ/abstrato.py" Edit pesq-2
grep -q 'empty-impl' <<<"$OUT" && bad "@abstractmethod + pass é contrato, não slop" \
                               || ok "@abstractmethod + pass é contrato, não slop"

# ---------------------------------------------------------------------------
echo "-- lista em comentário não é código morto (falso positivo do guarda)"
# ---------------------------------------------------------------------------
cat > "$PROJ/rodape.sh" <<'FX'
#   - valor de variável: `X=/; rm -rf $X` é barrado;
#   - script indireto: `./deploy.sh`, `make clean`, `npm run reset`;
#   - linguagem hospedeira: `python -c "shutil.rmtree('/')"`;
#   - codificação: `echo x | base64 -d | sh`;
echo real
FX
out2=$(awk -v EXT=sh -v ENABLED=dead-code -v ISTEST=0 -f "$ENGINE" "$PROJ/rodape.sh")
[[ -z "$out2" ]] && ok "rodapé de limitações (prosa em lista) não dispara dead-code" \
                 || bad "rodapé em lista não dispara dead-code ($out2)"

cat > "$PROJ/flags.sh" <<'FX'
case "$1" in
  --no-preserve-root) rec=1; unsafe=1; continue ;;
  --recursive | --dir) rec=1; continue ;;
  --force) f=1 ;;
  --dry-run) d=1 ;;
esac
FX
out2=$(awk -v EXT=sh -v ENABLED=dead-code -v ISTEST=0 -f "$ENGINE" "$PROJ/flags.sh")
[[ -z "$out2" ]] && ok "case arms --flag em shell não são comentário SQL" \
                 || bad "case arms --flag não são comentário SQL ($out2)"

# ---------------------------------------------------------------------------
echo "-- one-liner não é função gigante (falso positivo do dogfood da catraca)"
# ---------------------------------------------------------------------------
{
  printf 'ok()  { printf "ok %%s" "$1"; }\n'
  printf 'bad() { printf "no %%s" "$1"; }\n'
  for i in $(seq 1 80); do printf 'echo linha%s\n' "$i"; done
} > "$PROJ/oneliner.sh"
out2=$(awk -v EXT=sh -v ENABLED=oversized-function -v ISTEST=0 \
  -f "$ENGINE" "$PROJ/oneliner.sh")
[[ -z "$out2" ]] && ok "helpers de uma linha não abrem função no sensor" \
                 || bad "helpers de uma linha não abrem função no sensor ($out2)"

# ---------------------------------------------------------------------------
echo "-- cooldown: refatoração em curso não é reincidência"
# ---------------------------------------------------------------------------
run_hook "$PROJ/a.py" Edit cool-1
chk "primeira edição avisa" "$RC" "2"
run_hook "$PROJ/a.py" Edit cool-1
chk "mesma sessão, mesmo arquivo, já no cooldown → silêncio" "$RC" "0"
MAESTRO_HABITS_COOLDOWN=0 OUT2=$(printf '{"session_id":"cool-1","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$PROJ/a.py" \
  | MAESTRO_HOME="$HOME_T" CLAUDE_PROJECT_DIR="$PROJ" MAESTRO_HABITS_COOLDOWN=0 bash "$HOOK" 2>&1 >/dev/null); rc2=$?
chk "cooldown zerado (costura) → volta a avisar" "$rc2" "2"

# ---------------------------------------------------------------------------
echo "-- test-gap: sensor de SESSÃO, nag só nos degraus"
# ---------------------------------------------------------------------------
gap_hits=0
for i in 1 2 3 4 5 6; do
  cat > "$PROJ/clean$i.py" <<'FX'
def soma(a, b):
    return a + b
FX
  run_hook "$PROJ/clean$i.py" Edit gap-1
  grep -q 'test-gap' <<<"$OUT" && gap_hits=$(( gap_hits + 1 ))
done
chk "5 edições de src sem teste → exatamente 1 nag de test-gap" "$gap_hits" "1"
cat > "$PROJ/t/novo.test.ts" <<'FX'
test("x", () => { expect(1).toBe(1); });
FX
run_hook "$PROJ/t/novo.test.ts" Edit gap-2
cat > "$PROJ/clean99.py" <<'FX'
def sub(a, b):
    return a - b
FX
for i in 1 2 3 4 5; do run_hook "$PROJ/clean99.py" Write gap-2; done
grep -q 'test-gap' <<<"$OUT" && bad "sessão COM edição de teste não leva nag" \
                             || ok "sessão COM edição de teste não leva nag"

# ---------------------------------------------------------------------------
echo "-- configuração por projeto (.maestro.yaml habits:)"
# ---------------------------------------------------------------------------
printf 'version: 1\nhabits: [debug-leftover]\n' > "$PROJ/.maestro.yaml"
run_hook "$PROJ/a.py" Edit cfg-1
grep -q 'debug-leftover' <<<"$OUT" && ok "sensor listado continua ativo" || bad "sensor listado continua ativo"
grep -q 'too-many-params' <<<"$OUT" && bad "sensor fora da lista é desligado" \
                                    || ok "sensor fora da lista é desligado"
printf 'version: 1\nhabits: []\n' > "$PROJ/.maestro.yaml"
run_hook "$PROJ/a.py" Edit cfg-2
chk "habits: [] desliga tudo no projeto" "$RC" "0"
rm -f "$PROJ/.maestro.yaml"

# ---------------------------------------------------------------------------
echo "-- fronteiras: kill-switch · degradação · escopo · log"
# ---------------------------------------------------------------------------
OUT3=$(printf '{"session_id":"ks","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$PROJ/a.py" \
  | MAESTRO_OFF=1 MAESTRO_HOME="$HOME_T" bash "$HOOK" 2>&1); rc3=$?
chk "MAESTRO_OFF=1 → exit 0" "$rc3" "0"
chk "MAESTRO_OFF=1 → silêncio total" "$OUT3" ""
printf 'lixo{' | MAESTRO_HOME="$HOME_T" bash "$HOOK" >/dev/null 2>&1; rc3=$?
chk "stdin malformado → exit 0" "$rc3" "0"
run_hook "$PROJ/inexistente.py"
chk "arquivo inexistente → exit 0" "$RC" "0"
run_hook "$PROJ/README.md"
chk "arquivo não-código → exit 0" "$RC" "0"
mkdir -p "$PROJ/vendor"; cp "$PROJ/a.py" "$PROJ/vendor/a.py"
run_hook "$PROJ/vendor/a.py"
chk "vendor/ fica fora do sensor" "$RC" "0"
run_hook "$PROJ/a.py" Bash
chk "tool fora do matcher → exit 0 (defesa em profundidade)" "$RC" "0"

LOG="$HOME_T/logs/routing.jsonl"
if [[ -f "$LOG" ]]; then
  grep -q '"event":"habit_warn"' "$LOG" && ok "habit_warn no log (vocabulário fechado)" \
                                        || bad "habit_warn no log"
  grep -q 'a\.py\|/proj\|tmp\.' "$LOG" && bad "caminho NUNCA vaza para o log" \
                                       || ok "caminho NUNCA vaza para o log"
  grep -qE '"smell":"[a-z-]+"' "$LOG" && ok "smell logado como categoria" || bad "smell logado como categoria"
else
  bad "routing.jsonl deveria existir após habit_warn"
fi

# ---------------------------------------------------------------------------
echo "-- anti-ruído: no máximo 3 achados e 2 guias por emissão"
# ---------------------------------------------------------------------------
run_hook "$PROJ/a.py" Edit ruido-1
n_ach=$(grep -cE '^- [a-z-]+' <<<"$OUT" || true)
(( n_ach <= 3 )) && ok "≤3 achados listados ($n_ach)" || bad "≤3 achados listados ($n_ach)"
n_guias=$(grep -cE '^\*\*[a-z-]+\*\*' <<<"$OUT" || true)
(( n_guias <= 2 )) && ok "≤2 guias por emissão ($n_guias)" || bad "≤2 guias por emissão ($n_guias)"
grep -q '(+.*achado' <<<"$OUT" && ok "excedente é anunciado, não escondido" \
                               || bad "excedente é anunciado, não escondido"

# ---------------------------------------------------------------------------
echo "-- regencia: contato REGIDO com o Capitão, degraus 15/40 (S-1704)"
# ---------------------------------------------------------------------------
cat > "$PROJ/regfile.py" <<'FX'
def soma(a, b):
    return a + b
FX
for i in $(seq 1 14); do
  MAESTRO_HABITS=regencia run_hook "$PROJ/regfile.py" Edit reg-sess
done
chk "14 edições → silêncio no 14º" "$RC" "0"
MAESTRO_HABITS=regencia run_hook "$PROJ/regfile.py" Edit reg-sess
chk "15ª edição → RC 2 (degrau)" "$RC" "2"
grep -q 'regencia' <<<"$OUT" && ok "bloco contém regencia no degrau 15" || bad "bloco contém regencia no degrau 15"
MAESTRO_HABITS=regencia run_hook "$PROJ/regfile.py" Edit reg-sess
chk "16ª edição → silêncio" "$RC" "0"
cat > "$PROJ/regfile2.py" <<'FX'
def sub(a, b):
    return a - b
FX
for i in $(seq 1 15); do
  MAESTRO_HABITS=debug-leftover run_hook "$PROJ/regfile2.py" Edit reg-off
done
chk "sensor desligado via MAESTRO_HABITS (sem regencia) → silêncio no degrau 15" "$RC" "0"

# ---------------------------------------------------------------------------
echo "-- doc-governed: dívida S-1603b — cobertura em test-habits.sh"
# ---------------------------------------------------------------------------
mkdir -p "$PROJ/docs" "$PROJ/src" "$PROJ/other"
cat > "$PROJ/docs/A.md" <<'FX'
---
covers:
  - src/**
---
# A
FX
printf 'version: 1\ndocs: [docs/A.md]\n' > "$PROJ/.maestro.yaml"
cat > "$PROJ/src/x.py" <<'FX'
def f():
    return 1
FX
MAESTRO_HABITS=doc-governed run_hook "$PROJ/src/x.py" Edit docg-1
chk "1º edit em área governada → RC 2" "$RC" "2"
grep -q 'doc-governed' <<<"$OUT" && ok "bloco contém doc-governed" || bad "bloco contém doc-governed"
MAESTRO_HABITS=doc-governed run_hook "$PROJ/src/x.py" Edit docg-1
chk "2º edit, mesma sessão → silêncio (once-per-session)" "$RC" "0"
cat > "$PROJ/other/y.py" <<'FX'
def g():
    return 2
FX
MAESTRO_HABITS=doc-governed run_hook "$PROJ/other/y.py" Edit docg-2
chk "edit FORA do covers → silêncio" "$RC" "0"
rm -f "$PROJ/.maestro.yaml"

exit $fail
