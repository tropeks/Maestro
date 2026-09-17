#!/usr/bin/env bash
# issue #42 — post-edit-habits.sh:53 usava um regex de fallback
# ([^"]{1,1024}) que bash/glibc trata ~O(N²) para compilar e casar, mesmo
# sem o padrão bater. O custo só é pago no caminho SEM `jq` (ou quando `jq`
# devolve vazio): com `jq` presente e populando FILE, o `&&` da linha 53
# curto-circuita e o regex nunca roda (medido ~0,3ms). Este arquivo cobre
# dois contratos que não tinham teste:
#   1. NFR de latência (<50ms) no caminho SEM jq — o único que exercita a
#      linha 53 de verdade.
#   2. A correção REJEITA acima do teto de 1024, nunca trunca — um FILE
#      truncado pareceria um caminho válido; um FILE vazio não engana
#      ninguém. A fronteira (1024 aceita, 1025 rejeita) e a ausência de
#      vazamento de caminho na mensagem de rejeição são o que garante isso.
#
# Arquivo PRÓPRIO, não uma seção a mais em test-habits.sh: aquele arquivo já
# estava em 456 linhas (acima do teto de 400 do seu próprio sensor
# oversized-file) antes desta ordem — módulo que não cabe ganha módulo novo,
# não fica mais gordo no mesmo changeset. A dívida de test-habits.sh não é
# desta ordem para pagar.
#
# Isolamento: MAESTRO_HOME e projeto em mktemp -d. O ~/.maestro real NUNCA é
# tocado.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/post-edit-habits.sh"

# Mesmo protocolo de medição de latência (N, folga da mediana, portão de
# carga) usado por test-gate.sh e test-guarda-destrutiva.sh.
source "$REPO/tests/lib/latency.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOME_T="$TMP/home"; mkdir -p "$HOME_T/sessions"
PROJ="$TMP/proj"; mkdir -p "$PROJ"

# --- sandbox SEM jq: mesmo padrão de test-guarda-destrutiva.sh/test-gate.sh.
# É o ÚNICO jeito de exercitar a linha 53 — com jq no PATH o `&&` curto-
# circuita antes do regex.
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
for b in bash env cat date dirname stat flock mkdir mv grep sed head tail wc tr sort seq chmod ls awk basename cut paste printf; do
  src=$(command -v "$b" 2>/dev/null) && ln -sf "$src" "$NOJQ/$b" 2>/dev/null
done
if command -v jq >/dev/null 2>&1 && ! PATH="$NOJQ" command -v jq >/dev/null 2>&1; then
  ok "sandbox sem jq montado"
else
  bad "sandbox sem jq não ficou de pé"
fi

OUT=""; RC=0
run_nojq() { # <payload-file> → OUT=stderr, RC=exit; roda o hook SEM jq no PATH
  OUT=$(PATH="$NOJQ" MAESTRO_HOME="$HOME_T" CLAUDE_PROJECT_DIR="$PROJ" "$HOOK" < "$1" 2>&1 >/dev/null)
  RC=$?
  return 0
}
has()     { grep -qF -- "$1" <<<"$2"; }  # achou (substring LITERAL) → 0
assert_has()    { has "$2" "$3" && ok "$1" || bad "$1"; }       # $1=label $2=agulha $3=palheiro
assert_no_has() { has "$2" "$3" && bad "$1" || ok "$1"; }

# --- helper: caminho de comprimento EXATO em bytes, para testar a fronteira
# 1024/1025. Componentes de até 200 bytes (bem abaixo do limite de 255 bytes
# por componente do filesystem); o nome-folha absorve o resto exato.
mkchunk() { printf '%*s' "$1" '' | tr ' ' 'a'; }
build_path_of_len() { # <target_len> → stdout: caminho sob $PROJ com exatamente <target_len> bytes
  local target="$1"
  local path="$PROJ"
  local remaining leaf_len leaf seg
  remaining=$(( target - ${#path} ))
  while (( remaining > 256 )); do
    seg=$(mkchunk 200)
    path="$path/$seg"
    remaining=$(( target - ${#path} ))
  done
  leaf_len=$(( remaining - 1 ))
  leaf="$(mkchunk $((leaf_len - 3))).py"
  printf '%s/%s' "$path" "$leaf"
}

echo "-- correção #42: REJEITA acima do teto de 1024 (nunca trunca)"

echo "-- caso: sem aspas de fechamento"
printf '{"session_id":"s","tool_name":"Edit","tool_input":{"file_path":"%s/sem-fechamento' "$PROJ" > "$TMP/p-unterminated.json"
run_nojq "$TMP/p-unterminated.json"
chk "sem aspas de fechamento → exit 0" "$RC" "0"
chk "sem aspas de fechamento → stderr vazio (regex não casa, não é rejeição)" "$OUT" ""

echo "-- caso: campo file_path ausente"
printf '{"session_id":"s","tool_name":"Edit","tool_input":{}}' > "$TMP/p-nofield.json"
run_nojq "$TMP/p-nofield.json"
chk "campo ausente → exit 0" "$RC" "0"
chk "campo ausente → stderr vazio" "$OUT" ""

echo "-- caso: exatamente 1024 bytes → ACEITA (fronteira inclusiva)"
P1024=$(build_path_of_len 1024)
chk "path de teste tem 1024 bytes" "${#P1024}" "1024"
mkdir -p "$(dirname "$P1024")"
cat > "$P1024" <<'FX'
def process(data, a=[], b=2, c=3, d=4, e=5, f=6):
    print(data)  # TODO: fix
FX
printf '{"session_id":"s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$P1024" > "$TMP/p-1024.json"
run_nojq "$TMP/p-1024.json"
chk "1024 bytes → exit 2 (achados — o sensor RODOU, não foi rejeitado)" "$RC" "2"
assert_has    "1024 bytes: sensor rodou de verdade (bloco de achados presente)" '<maestro-habit>' "$OUT"
assert_no_has "1024 bytes: sem mensagem de rejeição (fronteira inclusiva confirmada)" 'rejeitado' "$OUT"

echo "-- caso: 1025 bytes → REJEITA, visível, sem vazar o caminho"
P1025=$(build_path_of_len 1025)
chk "path de teste tem 1025 bytes" "${#P1025}" "1025"
printf '{"session_id":"s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$P1025" > "$TMP/p-1025.json"
run_nojq "$TMP/p-1025.json"
chk "1025 bytes → exit 0 (rejeição NUNCA bloqueia — PostToolUse já aconteceu)" "$RC" "0"
assert_has    "mensagem cita o comprimento capturado (1025, metadado)" '1025 bytes' "$OUT"
assert_has    "mensagem é explícita sobre a rejeição (falha alta, não muda)" 'rejeitado' "$OUT"
assert_no_has "sem vazamento: o caminho REAL não aparece na mensagem" "$PROJ" "$OUT"
assert_no_has "sem vazamento: nenhum fragmento do conteúdo do caminho aparece" "aaaa" "$OUT"
assert_no_has "1025 bytes: sensor não rodou (rejeitado antes do -f)" '<maestro-habit>' "$OUT"

# ---------------------------------------------------------------------------
echo "-- NFR: latência < 50ms — fallback de regex SEM jq (issue #42)"
# ---------------------------------------------------------------------------
LAT_PAYLOAD="$TMP/lat-payload.json"
# file_path aponta para um arquivo INEXISTENTE de propósito: o hook sai logo
# depois de resolver FILE (o `-f "$FILE"` falha), isolando o custo do
# parsing — onde mora o regex de #42 — do resto do pipeline (sensores awk).
printf '{"session_id":"lat-sid","tool_name":"Edit","tool_input":{"file_path":"%s/nao-existe.py"}}' \
  "$PROJ" > "$LAT_PAYLOAD"

maestro_latency_read_load
# maestro_latency_measure roda "$bin" < "$input" direto (sem wrapper) — o PATH
# sem jq precisa estar no AMBIENTE por fora da chamada, não numa função.
OLDPATH="$PATH"
export PATH="$NOJQ"
maestro_latency_probe "$HOOK"
maestro_latency_measure "$HOOK" "$LAT_PAYLOAD"
export PATH="$OLDPATH"
maestro_latency_report "post-edit-habits(sem-jq)" "$MIN" "$MED" "$MAX" 50
case "$MAESTRO_LATENCY_VERDICT" in
  ok) ok "latência ok — sem jq (mediana ${MED}ms < teto ${MAESTRO_LATENCY_TETO}ms [$MAESTRO_LATENCY_TETO_MOTIVO])" ;;
  inconclusivo)
    echo "INCONCLUSIVO sob carga — sem jq (mediana ${MED}ms >= teto ${MAESTRO_LATENCY_TETO}ms [$MAESTRO_LATENCY_TETO_MOTIVO]; load ${MAESTRO_LATENCY_LOAD1M}/${MAESTRO_LATENCY_NCPU} CPUs — não conta como falha)" ;;
  fail) bad "regressão de latência (issue #42) — sem jq (mediana ${MED}ms >= teto ${MAESTRO_LATENCY_TETO}ms [$MAESTRO_LATENCY_TETO_MOTIVO]; load ${MAESTRO_LATENCY_LOAD1M}/${MAESTRO_LATENCY_NCPU} CPUs — sem carga para culpar; suspeito: ([^\"]{1,1024}) na linha 53, quantificador O(N²) no bash/glibc)" ;;
esac

# sanidade: COM jq no PATH (o caso comum), o MESMO payload roda muito mais
# rápido — confirma que o `&&` de fato curto-circuita e que o custo acima é
# do FALLBACK, não do hook inteiro. Mesmo relatório/portão de carga da
# medição principal (não reaproveita o teto já calculado acima: esse foi
# calculado para o rótulo "sem-jq" e um override manual de demonstração não
# pode vazar para esta checagem).
if command -v jq >/dev/null 2>&1; then
  maestro_latency_measure "$HOOK" "$LAT_PAYLOAD"
  maestro_latency_report "post-edit-habits(com-jq)" "$MIN" "$MED" "$MAX" 50
  case "$MAESTRO_LATENCY_VERDICT" in
    ok) ok "com jq no PATH → mediana ${MED}ms < teto ${MAESTRO_LATENCY_TETO}ms (confirma que o regex de #42 é só fallback)" ;;
    inconclusivo) echo "INCONCLUSIVO sob carga — com jq (mediana ${MED}ms >= teto ${MAESTRO_LATENCY_TETO}ms; não conta como falha)" ;;
    fail) bad "com jq no PATH → mediana ${MED}ms >= teto ${MAESTRO_LATENCY_TETO}ms (esperava curto-circuito bem mais rápido)" ;;
  esac
fi

exit $fail
