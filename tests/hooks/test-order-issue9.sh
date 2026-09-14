#!/usr/bin/env bash
# issue #9 (ordem 005) — "warn-only" escondia o que reprova a CI.
# `hooks/post-edit-habits.sh` imprimia "Warn-only — a edição valeu; considere
# resolver ANTES de seguir", mesma redação de EPICS.md:198-199 — verdade para
# ESTE hook (PostToolUse nunca bloqueia). Mas o MESMO achado alimenta
# `maestro habits --all` (catraca com baseline versionado, `.maestro-habits.tsv`,
# S-905), que REPROVA com exit 1 e derruba a CI.
#
# Caso real, pago em minuto de Actions: um arquivo de teste foi de 399 para
# 418 linhas, cruzou o teto de 400 (oversized-file), virou o 13º acima do
# baseline de 12. O PostToolUse disse "warn-only"; a CI do PR #8 ficou
# vermelha; foi preciso um segundo run.
#
# Lição das ordens 003/004: o teste NÃO exige o patch já aplicado. Detecta o
# MECANISMO — ausente → PENDENTE (hooks/ está na denylist de autoproteção do
# gate, ADR-003 v1.2; quem aplica docs/patches/005-issue9-warnonly-cruza-
# baseline.patch é o Capitão); presente → cobra de verdade e prova o
# TERCEIRO ESTADO — sabota a detecção de cruzamento e mostra que a MESMA
# asserção reprova.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/post-edit-habits.sh"
PATCH="$REPO/docs/patches/005-issue9-warnonly-cruza-baseline.patch"
EPICS="$REPO/docs/architecture/EPICS.md"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

# ---------------------------------------------------------------------------
# a nota em EPICS.md ligando os dois mecanismos não depende do patch em
# hooks/ (docs não estão na denylist) — checável sempre.
# ---------------------------------------------------------------------------
if grep -q 'issue #9, ordem 005' "$EPICS" 2>/dev/null && grep -qi 'S-905' <<<"$(grep -A3 'issue #9, ordem 005' "$EPICS")"; then
  ok "EPICS.md liga S-901 (warn-only) a S-905 (catraca) — nota da ordem 005"
else
  bad "EPICS.md ainda não liga o warn-only do hook à catraca de --all"
fi

# ---------------------------------------------------------------------------
# Mecanismo: detecção de cruzamento de baseline (comparação por arquivo,
# git show HEAD:<rel> — NÃO um scan do repo inteiro).
# ---------------------------------------------------------------------------
PATCHED=0
grep -qF 'CRUZOU o baseline' "$HOOK" 2>/dev/null && PATCHED=1

# custo: o mecanismo NÃO pode chamar `habits --all` nem enumerar o repo
# (git ls-files) a cada edição — isso é o próprio -all caro (medido: ~970ms
# neste repo de 223 arquivos rastreados). Checagem estrutural, vale mesmo
# antes do patch: se um dia alguém "resolver" isto chamando --all aqui
# dentro, este teste acusa o custo errado tomando forma.
# (grep por EXECUÇÃO, não por menção — a mensagem para o agente CITA
# `maestro habits --all` de propósito, entre crases de markdown; o que não
# pode existir é o hook RODANDO o CLI ou enumerando o repo com ls-files.)
if grep -qE 'bin/maestro|ls-files' "$HOOK" 2>/dev/null; then
  bad "hooks/post-edit-habits.sh invoca o CLI (bin/maestro) ou ls-files (scan do repo por edição — caro demais)"
else
  ok "hook não faz scan do repo inteiro (nem invoca bin/maestro nem ls-files) por edição"
fi

if (( PATCHED == 0 )); then
  pending "issue #9: hooks/post-edit-habits.sh ainda sem a detecção de cruzamento — aplicar $PATCH"
  exit $fail
fi
ok "mecanismo presente: post-edit-habits.sh detecta cruzamento de baseline por arquivo"

run_hook() { # run_hook <hook-bin> <file> [sid] → stdout = <maestro-habit> block, $? = exit
  printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' \
      "${3:-sid-9}" "$2" \
    | MAESTRO_HOME="$tmp/home" MAESTRO_SESSIONS_DIR="$tmp/home/sessions" \
      CLAUDE_PROJECT_DIR="$PROJ" bash "$1" 2>&1 >/dev/null
}

PROJ="$tmp/proj"; mkdir -p "$PROJ"; git -C "$PROJ" init -q

# ---------------------------------------------------------------------------
# (i) caso real: 399 → 418 linhas, cruza o teto de 400 (oversized-file) —
# NOVO neste arquivo (não existia antes da edição).
# ---------------------------------------------------------------------------
python3 -c "
for i in range(399):
    print(f'x = {i}')
" > "$PROJ/big.py"
git -C "$PROJ" add -A; git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm base
python3 -c "
for i in range(399, 418):
    print(f'x = {i}')
" >> "$PROJ/big.py"

OUT=$(run_hook "$HOOK" "$PROJ/big.py" sid-cross); RC=$?
chk() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (esperado '$3', obtido '$2')"; }
chk "achado → exit 2" "$RC" "2"
grep -qi 'CRUZOU o baseline' <<<"$OUT" && ok "(i) 399→418: mensagem acusa CRUZOU o baseline" \
  || bad "(i) mensagem não acusa cruzamento ($OUT)"
grep -q 'oversized-file' <<<"$OUT" && ok "(i) nomeia o smell que cruzou (oversized-file)" \
  || bad "(i) não nomeia o smell ($OUT)"
grep -qF 'maestro habits --all' <<<"$OUT" && ok "(i) mensagem aponta o comando definitivo (maestro habits --all)" \
  || bad "(i) não cita maestro habits --all ($OUT)"
grep -qF '.maestro-habits.tsv' <<<"$OUT" && ok "(i) mensagem nomeia a catraca (.maestro-habits.tsv)" \
  || bad "(i) não nomeia .maestro-habits.tsv ($OUT)"
grep -qi 'warn-only' <<<"$OUT" && ok "(i) ainda diz que ESTE hook é warn-only (verdade parcial preservada)" \
  || bad "(i) perdeu a menção a warn-only ($OUT)"

# ---------------------------------------------------------------------------
# (ii) arquivo que JÁ era oversized ANTES da edição: o smell não é NOVO
# neste arquivo — a mensagem não deve alegar "CRUZOU" (aproximação honesta:
# não sabe se outro arquivo já cruzou o total do repo).
# ---------------------------------------------------------------------------
python3 -c "
for i in range(450):
    print(f'x = {i}')
" > "$PROJ/already-big.py"
git -C "$PROJ" add -A; git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm "already big"
echo "y = 999" >> "$PROJ/already-big.py"

OUT2=$(run_hook "$HOOK" "$PROJ/already-big.py" sid-nocross)
grep -qi 'CRUZOU o baseline' <<<"$OUT2" \
  && bad "(ii) arquivo já era oversized — não deveria alegar CRUZOU ($OUT2)" \
  || ok "(ii) edição em arquivo já oversized não alega cruzamento novo"
grep -qF 'maestro habits --all' <<<"$OUT2" && ok "(ii) mesmo sem cruzar, ainda cita a catraca (verdade inteira)" \
  || bad "(ii) mensagem sem cruzamento não cita a catraca ($OUT2)"

# ---------------------------------------------------------------------------
# terceiro estado: sabota a detecção (corta a comparação old/new, tudo vira
# "não é novo") numa CÓPIA, e mostra que a asserção (i) reprova.
# ---------------------------------------------------------------------------
# post-edit-habits.sh resolve SCRIPT_DIR a partir do PRÓPRIO caminho e
# sourceia "$SCRIPT_DIR/lib/common.sh" — a cópia sabotada precisa de um
# lib/ irmão (symlink), senão "quebra" pelo motivo errado.
SABDIR="$tmp/sabotado-hook"; mkdir -p "$SABDIR"
ln -s "$REPO/hooks/lib" "$SABDIR/lib"
SABHOOK="$SABDIR/post-edit-habits.sh"
cp "$HOOK" "$SABHOOK"
sed -i 's/grep -qxF "\$_sm" <<<"\$old_smells" || crossing+="\${crossing:+, }\$_sm"/true/' "$SABHOOK"
if grep -q 'crossing+="${crossing:+, }' "$SABHOOK"; then
  bad "sabotagem não pegou (padrão do sed não bateu — mecanismo mudou de forma?)"
else
  git -C "$PROJ" checkout -q -- big.py 2>/dev/null || :
  python3 -c "
for i in range(399, 418):
    print(f'x = {i}')
" >> "$PROJ/big.py"
  OUT_SAB=$(run_hook "$SABHOOK" "$PROJ/big.py" sid-sab)
  if grep -qi 'CRUZOU o baseline' <<<"$OUT_SAB"; then
    bad "sabotagem não quebrou nada — (i) passaria mesmo com a detecção de cruzamento cega"
  else
    ok "sabotado: a asserção (i) REPROVA (obtido: '$OUT_SAB') — o teste tem dente"
  fi
fi

exit $fail
