#!/usr/bin/env bash
# issue #13 (ordem 004) — nem todo `.md` em .maestro/orders/ é ordem.
# Arquivo PRÓPRIO (não em test-order.sh) para não estourar o teto da catraca
# `oversized-file` — mesmo motivo de tests/cli/test-order-issue6.sh.
#
# Caso real: Vitali, doc "Rollback — ordem 002" — um `.md` solto dentro de
# `.maestro/orders/`, sem o carimbo `<!-- maestro-order v1` + `id:`, mas com
# um campo `frozen:` escrito à mão no cabeçalho (prática comum em doc de
# rollback: "não toque nisto enquanto eu não tiver revertido"). Os dois laços
# de hooks/session-start.sh tratavam ISSO como ordem: a política do gate
# herdava o `frozen:` do documento (congelando caminho que ninguém decidiu
# congelar) e a contagem `ordens: N pendente(s)` inflava — o supervisor
# cutucou 5x por um arquivo que nunca foi ordem.
#
# Lição da ordem 003 (contrato desta ordem): o teste NÃO exige o patch já
# aplicado. Ele detecta o MECANISMO (a função/predicado que o patch introduz)
# no arquivo alvo: ausente → PENDENTE, sem reprovar (bin/ e hooks/ estão na
# denylist de autoproteção do gate — ADR-003 v1.2 — e quem aplica o patch em
# docs/patches/ é o Capitão); presente → cobra de verdade e REPROVA se o
# mecanismo estiver lá e não funcionar.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
SS="$REPO/hooks/session-start.sh"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

# Mecanismo do hook: o predicado que os dois laços (frozen zones e contagem de
# pendentes) passam a exigir antes de considerar qualquer .md como ordem.
HOOK_PATCHED=0
grep -qF '_maestro_order_stamp_ok' "$SS" 2>/dev/null && HOOK_PATCHED=1

# Mecanismo do CLI: o predicado equivalente usado por `order --list` para não
# listar (nem deixar fingir duplicata de id) um .md que não é ordem, e a
# detecção de id duplicado entre ordens de verdade.
CLI_STAMP_PATCHED=0
grep -qF '_order_valid_stamp' "$BIN" 2>/dev/null && CLI_STAMP_PATCHED=1
CLI_DUPE_PATCHED=0
grep -qF 'id de ordem duplicado' "$BIN" 2>/dev/null && CLI_DUPE_PATCHED=1

P="$tmp/proj"; mkdir -p "$P/core/auth"
git -C "$P" init -q
echo a > "$P/core/auth/jwt.py"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm base

# ---------------------------------------------------------------------------
# fixture 1: ordem de VERDADE, para provar que o mecanismo não engole ordem
# legítima junto com o lixo — só exclui o que não tem carimbo.
# ---------------------------------------------------------------------------
"$BIN" order --create --title "Genuína" --frozen "core/auth/" \
  --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Ordem de verdade — tem que continuar contando e congelando.
BODY

# ---------------------------------------------------------------------------
# fixture 2: o caso Vitali — doc solto, SEM `<!-- maestro-order v1` e SEM
# `id:`, mas com `frozen:` escrito à mão no cabeçalho (prática comum em doc
# de rollback). É exatamente o arquivo que produziu os 5 cutucões.
# ---------------------------------------------------------------------------
cat > "$P/.maestro/orders/rollback-ordem-002.md" <<'EOF'
# Rollback — ordem 002

Passo a passo para reverter manualmente a ordem 002 caso o aceite precise
ser desfeito. NÃO é uma ordem — é um documento de apoio do humano.

frozen: src/
EOF
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm "doc de rollback (não é ordem)"

# ---------------------------------------------------------------------------
# (i) política do gate: `frozen:` do doc do Vitali NÃO pode entrar.
# ---------------------------------------------------------------------------
printf '{"session_id":"vitali-1"}' | CLAUDE_PROJECT_DIR="$P" bash "$SS" >/tmp/.issue13-out.$$ 2>/dev/null
OUT=$(cat "/tmp/.issue13-out.$$"); rm -f "/tmp/.issue13-out.$$"
POL="$MAESTRO_HOME/gate-policy.sh"

if grep -q 'ORDER_FROZEN="core/auth/' "$POL" 2>/dev/null; then
  ok "regressão: a ordem legítima continua congelando core/auth/"
else
  bad "regressão: a ordem legítima parou de congelar core/auth/ ($(grep ORDER_FROZEN "$POL" 2>/dev/null))"
fi

if (( HOOK_PATCHED == 0 )); then
  pending "issue #13 (i): doc sem carimbo não pode congelar — hooks/session-start.sh ainda sem _maestro_order_stamp_ok; aplicar docs/patches/004-issue13-carimbo-de-ordem.patch"
elif grep -q 'ORDER_FROZEN="core/auth/"$' "$POL" 2>/dev/null; then
  ok "issue #13 (i): doc do Vitali (sem carimbo) NÃO entrou na política do gate"
else
  bad "issue #13 (i): patch aplicado e o frozen: do doc do Vitali AINDA vaza para a política ($(grep ORDER_FROZEN "$POL" 2>/dev/null))"
fi

# ---------------------------------------------------------------------------
# (ii) contagem de pendentes: só a ordem de verdade conta.
# ---------------------------------------------------------------------------
if (( HOOK_PATCHED == 0 )); then
  pending "issue #13 (ii): contagem de pendentes ainda soma o doc do Vitali — hooks/session-start.sh sem o patch"
elif grep -q 'ordens: 1 pendente(s)' <<<"$OUT"; then
  ok "issue #13 (ii): doc do Vitali (sem carimbo) NÃO conta como ordem pendente"
else
  bad "issue #13 (ii): patch aplicado e a contagem ainda inclui o doc do Vitali (obtido: $(grep -o 'ordens: [^ ]* pendente(s)' <<<"$OUT"))"
fi

# ---------------------------------------------------------------------------
# (iii) `order --list`: doc sem carimbo não aparece como ordem "aberta".
# ---------------------------------------------------------------------------
LISTOUT=$("$BIN" order --list --project "$P" 2>/dev/null)
if (( CLI_STAMP_PATCHED == 0 )); then
  pending "issue #13 (iii): order --list ainda lista o doc do Vitali como ordem — bin/maestro sem _order_valid_stamp"
elif grep -q 'Rollback' <<<"$LISTOUT"; then
  bad "issue #13 (iii): patch aplicado e order --list AINDA lista o doc do Vitali ($LISTOUT)"
else
  ok "issue #13 (iii): order --list não lista o doc do Vitali como ordem"
fi

# ---------------------------------------------------------------------------
# (iv) id duplicado: dois arquivos com o MESMO id (carimbo válido nos dois —
# cópia/colagem, não o caso Vitali) — `--list` acusa em vez de calar.
# ---------------------------------------------------------------------------
cat > "$P/.maestro/orders/003-dup-a.md" <<'EOF'
<!-- maestro-order v1
id: 003
-->
# Ordem 003 — dup A
EOF
cat > "$P/.maestro/orders/003-dup-b.md" <<'EOF'
<!-- maestro-order v1
id: 003
-->
# Ordem 003 — dup B
EOF

DUPOUT=$("$BIN" order --list --project "$P" 2>/dev/null)
if (( CLI_DUPE_PATCHED == 0 )); then
  pending "issue #13 (iv): id duplicado listado calado — bin/maestro sem a acusação de duplicata"
elif grep -qi 'duplicad' <<<"$DUPOUT"; then
  ok "issue #13 (iv): order --list acusa o id 003 duplicado"
else
  bad "issue #13 (iv): patch aplicado e o id 003 duplicado segue listado calado ($DUPOUT)"
fi

exit $fail
