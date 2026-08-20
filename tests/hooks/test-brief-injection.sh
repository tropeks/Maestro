#!/usr/bin/env bash
# E8 / S-802 + S-803 — seção "## Projeto" do SessionStart: o hook injeta a
# GARANTIA de que o estado existe e está fresco (ponteiro + veredito), nunca o
# estado em si; e cobra a atualização do brief ao fechar trabalho (S-803).
# Freshness do hook é a barata (HEAD + idade); wtree é assunto do CLI.
# Hermético: MAESTRO_HOME, projeto e brief em mktemp -d.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

HOME_T="$tmp/home"
PROJ="$tmp/projeto"
mkdir -p "$PROJ"; git -C "$PROJ" init -q
echo a > "$PROJ/a.txt"; git -C "$PROJ" add -A
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm inicial

OUT=''
run_hook() { # run_hook <proj> [sid] → OUT recebe a injeção
  OUT=$(printf '{"session_id":"%s"}' "${2:-sid-brief}" \
    | MAESTRO_HOME="$HOME_T" CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>/dev/null)
  return 0
}
projeto_sec() { sed -n '/^## Projeto$/,/^$/p' <<<"$OUT"; }

# ---------------------------------------------------------------------------
echo "-- sem brief e sem profile: só a cobrança do S-803"
# ---------------------------------------------------------------------------
run_hook "$PROJ"
grep -q '^## Projeto$' <<<"$OUT" && ok "seção Projeto sempre presente" \
                                 || bad "seção Projeto sempre presente"
grep -q '^brief:' <<<"$OUT" && bad "sem brief → sem linha de brief" || ok "sem brief → sem linha de brief"
grep -q 'atualize o brief: maestro brief --write --session sid-brief' <<<"$OUT" \
  && ok "S-803: cobrança de atualização com o session_id real" \
  || bad "S-803: cobrança de atualização com o session_id real"
grep -q 'memória:' <<<"$OUT" && bad "sem memory_container → sem linha de memória" \
                             || ok "sem memory_container → sem linha de memória"

# ---------------------------------------------------------------------------
echo "-- brief FRESCO: ponteiro + veredito + ordem de leitura"
# ---------------------------------------------------------------------------
printf 'Em curso: E8.\n' | MAESTRO_HOME="$HOME_T" "$BIN" brief --write --project "$PROJ" >/dev/null
run_hook "$PROJ"
grep -q 'brief: FRESCO' <<<"$OUT" && ok "HEAD inalterado → FRESCO" || bad "HEAD inalterado → FRESCO"
grep -q 'ANTES de varrer o repo' <<<"$OUT" \
  && ok "instrui a ler o brief antes da varredura" || bad "instrui a ler o brief antes da varredura"
BF=$(MAESTRO_HOME="$HOME_T" "$BIN" brief --path --project "$PROJ")
grep -qF "$BF" <<<"$OUT" && ok "ponteiro do hook = caminho do CLI (derivação única)" \
                         || bad "ponteiro do hook = caminho do CLI ($BF ausente)"
H7=$(git -C "$PROJ" rev-parse --short=7 HEAD)
grep -q "HEAD $H7" <<<"$OUT" && ok "veredito nomeia o HEAD atual" || bad "veredito nomeia o HEAD atual"
n=$(grep -c "Em curso: E8" <<<"$OUT" || true)
chk "a NARRATIVA nunca é injetada (só o ponteiro)" "$n" "0"

# ---------------------------------------------------------------------------
echo "-- brief STALE: conta commits e manda confiar no git"
# ---------------------------------------------------------------------------
echo b >> "$PROJ/a.txt"; git -C "$PROJ" add -A
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm segundo
run_hook "$PROJ"
grep -q 'brief: STALE (1 commit(s) atrás' <<<"$OUT" \
  && ok "1 commit depois → STALE contando" || bad "1 commit depois → STALE contando"
grep -q 'o git dá a verdade' <<<"$OUT" \
  && ok "STALE aponta a fonte de verdade" || bad "STALE aponta a fonte de verdade"

# ---------------------------------------------------------------------------
echo "-- memory_container do .maestro.yaml (S-802)"
# ---------------------------------------------------------------------------
printf 'version: 1\nproject: fixture\nmemory_container: sm_project_Fixture\n' > "$PROJ/.maestro.yaml"
run_hook "$PROJ"
grep -q 'memória: recall no supermemory com containerTag sm_project_Fixture' <<<"$OUT" \
  && ok "container do projeto vira instrução determinística" \
  || bad "container do projeto vira instrução determinística"
printf 'version: 1\nmemory_container: "tag inválida!"\n' > "$PROJ/.maestro.yaml"
run_hook "$PROJ"
grep -q 'memória:' <<<"$OUT" && bad "container malformado é omitido" || ok "container malformado é omitido"
rm -f "$PROJ/.maestro.yaml"

# ---------------------------------------------------------------------------
echo "-- degradações: carimbo ilegível · fora de git · hook nunca falha"
# ---------------------------------------------------------------------------
printf 'lixo\n' > "$BF"
run_hook "$PROJ"
grep -q 'carimbo ilegível' <<<"$OUT" && ok "brief corrompido vira aviso de regravação" \
                                     || bad "brief corrompido vira aviso de regravação"
NOGIT="$tmp/semgit"; mkdir -p "$NOGIT"
printf 'nota\n' | MAESTRO_HOME="$HOME_T" "$BIN" brief --write --project "$NOGIT" >/dev/null
run_hook "$NOGIT"
grep -q 'sem git para conferir' <<<"$OUT" \
  && ok "fora de git: idade sem fingir freshness" || bad "fora de git: idade sem fingir freshness"
rc=0
printf '{"session_id":"x"}' | MAESTRO_HOME="$HOME_T" CLAUDE_PROJECT_DIR="$tmp/nao-existe" \
  bash "$HOOK" >/dev/null 2>&1 || rc=$?
chk "projeto inexistente → hook sai 0 (nunca bloqueia sessão)" "$rc" "0"

# ---------------------------------------------------------------------------
echo "-- orçamento: a seção cede sob pressão e o núcleo sobrevive"
# ---------------------------------------------------------------------------
OUT=$(printf '{"session_id":"orc"}' | MAESTRO_HOME="$HOME_T" CLAUDE_PROJECT_DIR="$PROJ" \
  MAESTRO_INJECTION_BUDGET=900 bash "$HOOK" 2>/dev/null)
bytes=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
(( bytes <= 900 )) && ok "teto de 900B respeitado (${bytes}B)" || bad "teto de 900B respeitado (${bytes}B)"
grep -q 'INSTRUÇÃO CANÔNICA' <<<"$OUT" && ok "núcleo sobrevive ao aperto" || bad "núcleo sobrevive ao aperto"
# sob 900B a seção Projeto (que vem depois de gates/bindings/profile) já cedeu
grep -q 'brief: ' <<<"$OUT" && bad "sob aperto a seção Projeto cede" || ok "sob aperto a seção Projeto cede"

exit $fail
