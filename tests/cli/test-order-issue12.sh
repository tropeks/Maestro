#!/usr/bin/env bash
# issue #12 (ordem 004, rodada B) — a ordem absorvida não tinha estado terminal.
# Arquivo PRÓPRIO (não em test-order.sh) para não estourar o teto da catraca
# `oversized-file` — mesmo motivo de tests/cli/test-order-issue6.sh e
# tests/cli/test-order-issue13.sh.
#
# `_order_status` (bin/maestro) tinha UM caminho terminal, `accepted_at`, e
# ele exige prova no TIP do branch DAQUELA ordem. Ordem cujo trabalho foi
# absorvido por outra não tem branch/recibo próprios — fica 'aberta' (ou
# 'em_execucao') para sempre, e o cutucão "provada e sem aceite" dispara sem
# causa real. Dois casos reais, duas portas:
#   - NetForge 018 absorvida DENTRO da 016 (absorção por OUTRA ordem);
#   - Maestro 001/002 absorvidas pelo MAIN via PR (#4, #5, #10).
#
# Entrega: `maestro order --accept N --absorbed-by <M|main>`. O item que faz
# o modelo valer: a ABSORVENTE tem de estar ELA MESMA provada no momento do
# carimbo — senão "absorver" vira porta dos fundos para aceitar sem prova.
# Este arquivo cobre as duas portas E a recusa (a parte que mais importa).
#
# Lição da ordem 003/004A, contrato desta ordem: o teste NÃO exige o patch já
# aplicado. Detecta o MECANISMO em bin/maestro e hooks/session-start.sh:
# ausente → PENDENTE (nunca reprova — bin/ e hooks/ estão na denylist de
# autoproteção do gate, ADR-003 v1.2; quem aplica em docs/patches/ é o
# Capitão); presente → cobra de verdade e REPROVA se o mecanismo não
# funcionar. O patch desta ordem (docs/patches/004-issue12-absorvida-e-
# terminal.patch) assume o patch da rodada A (docs/patches/004-issue13-
# carimbo-de-ordem.patch) JÁ aplicado — os dois tocam as mesmas linhas de
# hooks/session-start.sh; aplique 13 antes de 12.
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

# Mecanismo do CLI: a flag e o caminho de derivação/aceite que esta ordem
# introduz em bin/maestro.
CLI_PATCHED=0
grep -qF -- '--absorbed-by' "$BIN" 2>/dev/null && CLI_PATCHED=1

# Mecanismo do hook: absorbed_by no MESMO teste de exclusão de accepted_at,
# nos dois laços de hooks/session-start.sh (frozen zones e contagem de
# pendentes). Depende do predicado _maestro_order_stamp_ok da rodada A.
HOOK_PATCHED=0
grep -qF 'absorbed_by' "$SS" 2>/dev/null && HOOK_PATCHED=1

git_init_main() { # <dir> → git init com o branch de topo chamado 'main',
  # independente do init.defaultBranch da máquina que roda o teste.
  local d="$1"
  git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD refs/heads/main
}

# ---------------------------------------------------------------------------
# fixture comum às três portas: um projeto com a ordem M (absorvente,
# provada) e a ordem N (absorvida, sem prova própria).
# ---------------------------------------------------------------------------
P="$tmp/proj"; mkdir -p "$P"
git_init_main "$P"
echo a > "$P/f.txt"
git -C "$P" add f.txt
git -C "$P" -c user.email=t@t -c user.name=t commit -qm base

"$BIN" order --create --title "Absorvente M" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
M — a ordem que efetivamente entrega o trabalho.
BODY
OFM="$P/.maestro/orders/001-absorvente-m.md"
BRM=$(grep '^branch:' "$OFM" | awk '{print $2}')
git -C "$P" checkout -qb "$BRM"
echo b >> "$P/f.txt"
git -C "$P" add -A
git -C "$P" -c user.email=t@t -c user.name=t commit -qm entregaM
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null

"$BIN" order --create --title "Absorvida N (porta ordem)" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
N — o caso NetForge 018 dentro da 016: o trabalho foi feito em M, não em N.
BODY

# ---------------------------------------------------------------------------
# (i) recusa: absorver por ordem NÃO provada. É a parte que faz o modelo
# valer — sem isto "absorver" vira porta dos fundos para aceitar sem prova.
# ---------------------------------------------------------------------------
"$BIN" order --create --title "Nao provada" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Fica aberta para sempre; nunca prova nada.
BODY
if (( CLI_PATCHED == 0 )); then
  pending "issue #12 (i): recusa de absorção por ordem não provada — bin/maestro sem --absorbed-by; aplicar docs/patches/004-issue12-absorvida-e-terminal.patch (depois do 004-issue13)"
else
  ERR=$("$BIN" order --accept 2 --absorbed-by 3 --project "$P" --session dir-1 2>&1); RC=$?
  if (( RC == 0 )); then
    bad "issue #12 (i): absorção por ordem 3 (status 'aberta', nunca provada) foi ACEITA — a porta dos fundos existe ($ERR)"
  elif grep -qi "não\|nem 'provada'\|nem 'aceita'" <<<"$ERR"; then
    ok "issue #12 (i): absorção por ordem NÃO provada foi recusada"
  else
    bad "issue #12 (i): recusou (rc=$RC), mas sem explicar a causa: $ERR"
  fi
  ST3=$("$BIN" order --status 2 --project "$P" 2>/dev/null | head -1)
  if grep -q 'aberta' <<<"$ST3"; then
    ok "issue #12 (i): ordem 2 continua 'aberta' depois da tentativa recusada (sem efeito colateral)"
  else
    bad "issue #12 (i): a tentativa recusada mudou o estado da ordem 2 ($ST3)"
  fi
fi

# ---------------------------------------------------------------------------
# (ii) recusa: auto-absorção e absorvente inexistente — não têm brecha própria.
# ---------------------------------------------------------------------------
if (( CLI_PATCHED == 1 )); then
  "$BIN" order --accept 2 --absorbed-by 2 --project "$P" --session dir-1 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then ok "issue #12 (ii): ordem não pode absorver a si mesma"
  else bad "issue #12 (ii): ordem 2 'absorveu' a si mesma"; fi

  "$BIN" order --accept 2 --absorbed-by 999 --project "$P" --session dir-1 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then ok "issue #12 (ii): absorvente inexistente (999) é recusado"
  else bad "issue #12 (ii): absorvente inexistente (999) foi aceito"; fi
fi

# ---------------------------------------------------------------------------
# (iii) porta 1: absorção por OUTRA ordem, PROVADA — o caso NetForge.
# ---------------------------------------------------------------------------
if (( CLI_PATCHED == 0 )); then
  pending "issue #12 (iii): absorção por ordem provada (NetForge) — bin/maestro sem --absorbed-by"
else
  OUT=$("$BIN" order --accept 2 --absorbed-by 1 --project "$P" --session dir-1 2>&1); RC=$?
  if (( RC != 0 )); then
    bad "issue #12 (iii): absorção por ordem 1 (provada) foi recusada ($OUT)"
  elif grep -qi 'absorvida' <<<"$OUT"; then
    ok "issue #12 (iii): ordem 2 absorvida por 1 (provada) — aceita"
  else
    bad "issue #12 (iii): rc=0 mas a saída não confirma a absorção ($OUT)"
  fi
  ST=$("$BIN" order --status 2 --project "$P" 2>/dev/null)
  if grep -q '^ordem 002: absorvida$' <<<"$ST"; then
    ok "issue #12 (iii): estado derivado de N é 'absorvida'"
  else
    bad "issue #12 (iii): estado derivado de N não é 'absorvida' ($(head -1 <<<"$ST"))"
  fi
  if grep -q 'absorvida' <<<"$ST" && ! grep -qx 'ordem 2: aceita' <<<"$(head -1 <<<"$ST")"; then
    ok "issue #12 (iii): 'absorvida' é DISTINTO de 'aceita' na leitura de status"
  else
    bad "issue #12 (iii): status não distingue absorvida de aceita ($(head -1 <<<"$ST")))"
  fi
  # idempotência: reabsorver não muda nada nem quebra.
  "$BIN" order --accept 2 --absorbed-by 1 --project "$P" --session dir-1 2>&1 | grep -qi 'já absorvida' \
    && ok "issue #12 (iii): re-tentar absorver a mesma ordem é no-op honesto" \
    || bad "issue #12 (iii): reabsorver não foi tratado como no-op"
  # ordem já aceita não pode ser "absorvida" por cima.
  "$BIN" order --accept 1 --project "$P" --session dir-1 >/dev/null 2>&1
  "$BIN" order --accept 1 --absorbed-by 2 --project "$P" --session dir-1 >/tmp/.i12-out.$$ 2>&1
  RC1=$?
  OUT1=$(cat "/tmp/.i12-out.$$"); rm -f "/tmp/.i12-out.$$"
  if (( RC1 != 0 )) && grep -qi 'já está aceita' <<<"$OUT1"; then
    ok "issue #12 (iii): --absorbed-by não se aplica a ordem já ACEITA"
  else
    bad "issue #12 (iii): --absorbed-by sobre ordem já aceita deveria recusar ($OUT1)"
  fi
fi

# ---------------------------------------------------------------------------
# (iv) porta 2: absorção pelo MAIN — o caso Maestro 001/002 (PRs #4/#5/#10).
# Recusa sem recibo fresco no tip ATUAL; passa com recibo (label 'main').
# ---------------------------------------------------------------------------
P2="$tmp/proj2"; mkdir -p "$P2"
git_init_main "$P2"
echo a > "$P2/f.txt"
git -C "$P2" add f.txt
git -C "$P2" -c user.email=t@t -c user.name=t commit -qm base
"$BIN" order --create --title "Absorvida pelo main" --project "$P2" --session dir-1 <<'BODY' >/dev/null
## Objetivo
O caso Maestro 001/002: mesclada e provada no main antes do aceite.
BODY
git -C "$P2" add -A
git -C "$P2" -c user.email=t@t -c user.name=t commit -qm "ordem versionada"

if (( CLI_PATCHED == 0 )); then
  pending "issue #12 (iv): absorção pelo main — bin/maestro sem --absorbed-by"
else
  "$BIN" order --accept 1 --absorbed-by main --project "$P2" --session dir-1 >/tmp/.i12-out.$$ 2>&1
  RC2=$?; OUT2=$(cat "/tmp/.i12-out.$$"); rm -f "/tmp/.i12-out.$$"
  if (( RC2 != 0 )) && grep -qi "recibo válido" <<<"$OUT2"; then
    ok "issue #12 (iv): main SEM recibo válido no conteúdo atual é recusado"
  else
    bad "issue #12 (iv): main sem recibo deveria recusar ($OUT2)"
  fi

  "$BIN" evidence --record --label main --project "$P2" -- true >/dev/null
  "$BIN" order --accept 1 --absorbed-by main --project "$P2" --session dir-1 >/tmp/.i12-out.$$ 2>&1
  RC3=$?; OUT3=$(cat "/tmp/.i12-out.$$"); rm -f "/tmp/.i12-out.$$"
  if (( RC3 == 0 )) && grep -qi 'absorvida' <<<"$OUT3"; then
    ok "issue #12 (iv): main COM recibo válido (label 'main') no tip atual — absorção aceita"
  else
    bad "issue #12 (iv): main com recibo válido deveria absorver ($OUT3)"
  fi
  ST2=$("$BIN" order --status 1 --project "$P2" 2>/dev/null | head -1)
  grep -q '^ordem 001: absorvida$' <<<"$ST2" \
    && ok "issue #12 (iv): estado derivado é 'absorvida' também na porta do main" \
    || bad "issue #12 (iv): estado inesperado ($ST2)"

  # main ANDOU depois do recibo: o recibo vira stale e a absorção volta a recusar.
  echo mais >> "$P2/f.txt"
  git -C "$P2" add f.txt
  git -C "$P2" -c user.email=t@t -c user.name=t commit -qm "main andou"
  "$BIN" order --create --title "Segunda vitima" --project "$P2" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Testa recibo vencido do main.
BODY
git -C "$P2" add -A; git -C "$P2" -c user.email=t@t -c user.name=t commit -qm "segunda ordem versionada"
"$BIN" order --accept 2 --absorbed-by main --project "$P2" --session dir-1 >/tmp/.i12-out.$$ 2>&1
RC4=$?; OUT4=$(cat "/tmp/.i12-out.$$"); rm -f "/tmp/.i12-out.$$"
  if (( RC4 != 0 )) && grep -qi "recibo válido" <<<"$OUT4"; then
    ok "issue #12 (iv): recibo do main VENCIDO (main andou depois) é recusado, não reaproveitado"
  else
    bad "issue #12 (iv): recibo vencido do main deveria recusar ($OUT4)"
  fi
fi

# ---------------------------------------------------------------------------
# (v) hooks/session-start.sh: ordem absorvida some do congelamento e da
# contagem de pendentes, no MESMO teste de exclusão de accepted_at.
# ---------------------------------------------------------------------------
if (( HOOK_PATCHED == 0 )); then
  pending "issue #12 (v): absorbed_by ainda não excluída dos dois laços de hooks/session-start.sh"
else
  P3="$tmp/proj3"; mkdir -p "$P3/core"
  git_init_main "$P3"
  echo a > "$P3/core/f.txt"
  git -C "$P3" add core/f.txt
  git -C "$P3" -c user.email=t@t -c user.name=t commit -qm base
  "$BIN" order --create --title "Absorvida frozen" --frozen "core/" --project "$P3" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Ordem absorvida que declarou frozen — não pode continuar congelando.
BODY
git -C "$P3" add -A; git -C "$P3" -c user.email=t@t -c user.name=t commit -qm "ordem versionada"
"$BIN" evidence --record --label main --project "$P3" -- true >/dev/null
"$BIN" order --accept 1 --absorbed-by main --project "$P3" --session dir-1 >/dev/null 2>&1

OUT=$(printf '{"session_id":"i12-hook"}' | CLAUDE_PROJECT_DIR="$P3" bash "$SS" 2>/dev/null)
POL="$MAESTRO_HOME/gate-policy.sh"
if grep -q 'MAESTRO_GATE_ORDER_FROZEN="core/"' "$POL" 2>/dev/null; then
  bad "issue #12 (v): frozen: de ordem ABSORVIDA ainda entra na política do gate ($(grep ORDER_FROZEN "$POL" 2>/dev/null))"
else
  ok "issue #12 (v): frozen: de ordem absorvida NÃO entra na política do gate"
fi
if grep -q 'pendente(s)' <<<"$OUT"; then
  bad "issue #12 (v): ordem absorvida ainda conta como pendente ($(grep -o 'ordens: [^ ]* pendente(s)' <<<"$OUT"))"
else
  ok "issue #12 (v): ordem absorvida NÃO conta como pendente"
fi
fi

exit $fail
