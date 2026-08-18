#!/usr/bin/env bash
# E7 / S-707 — seção "## Estilo de comunicação com o usuário" na injeção do
# SessionStart: presença, degradação sem o arquivo, teto de 2000B por arquivo
# inchado e cessão ANTES das seções de ação sob orçamento apertado.
# Isolado: MAESTRO_HOME/CLAUDE_PROJECT_DIR em mktemp -d; arquivo de estilo via
# MAESTRO_STYLE_FILE (nunca depende do config real além do caso de presença).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

HDR='## Estilo de comunicação com o usuário'

run() { # run [VAR=VAL ...] → OUT/RC
  local home proj outf="$SANDBOX/out"
  home=$(mktemp -d "$SANDBOX/home.XXXXXX"); proj=$(mktemp -d "$SANDBOX/proj.XXXXXX")
  printf '{"session_id":"style-test"}' \
    | env MAESTRO_HOME="$home" CLAUDE_PROJECT_DIR="$proj" "$@" bash "$HOOK" >"$outf" 2>/dev/null
  RC=$?; OUT=$(cat "$outf")
  return 0
}

echo "-- presença e conteúdo (config real do repo)"
run
[[ $RC -eq 0 ]] && ok "hook sai 0" || bad "hook sai 0 (rc=$RC)"
grep -q "$HDR" <<<"$OUT" && ok "seção de estilo presente" || bad "seção de estilo presente"
grep -q 'Clareza vence a regra' <<<"$OUT" \
  && ok "conteúdo vem de config/communication-style.md" \
  || bad "conteúdo vem de config/communication-style.md"

echo "-- degradação: arquivo ausente → sem seção, sem erro"
run MAESTRO_STYLE_FILE=/nao/existe/style.md
[[ $RC -eq 0 ]] && ok "arquivo ausente: exit 0" || bad "arquivo ausente: exit 0 (rc=$RC)"
grep -q "$HDR" <<<"$OUT" && bad "arquivo ausente: seção NÃO aparece" \
                         || ok  "arquivo ausente: seção NÃO aparece"
grep -q '</maestro-routing>' <<<"$OUT" && ok "bloco íntegro sem o estilo" \
                                       || bad "bloco íntegro sem o estilo"

echo "-- teto por arquivo: 2000 bytes, arquivo inchado não devora o orçamento"
big="$SANDBOX/big.md"
head -c 6000 /dev/zero | tr '\0' 'x' > "$big"
run MAESTRO_STYLE_FILE="$big"
sty=$(sed -n "/$HDR/,/^##\|<\/maestro-routing>/p" <<<"$OUT" | wc -c)
if [[ "$sty" -gt 0 && "$sty" -le 2100 ]]; then
  ok "seção limitada a ~2000B (obtido ${sty}B)"
else
  bad "seção limitada a ~2000B (obtido ${sty}B)"
fi

echo "-- orçamento apertado: estilo cede ANTES de heurísticas e roster"
run MAESTRO_INJECTION_BUDGET=3000
[[ $RC -eq 0 ]] && ok "orçamento 3000: exit 0" || bad "orçamento 3000: exit 0"
if grep -q "$HDR" <<<"$OUT"; then
  # se estilo sobreviveu, heurísticas e roster TÊM de estar inteiros (prioridade maior)
  grep -q '## Heurísticas de execução' <<<"$OUT" && grep -q '## Roster' <<<"$OUT" \
    && ok "estilo só sobrevive se heurísticas+roster couberam antes" \
    || bad "estilo sobreviveu com seção de prioridade maior cortada"
else
  ok "estilo cedeu primeiro sob orçamento apertado"
fi
grep -q 'INSTRUÇÃO CANÔNICA' <<<"$OUT" && ok "núcleo preservado" || bad "núcleo preservado"

exit $fail
