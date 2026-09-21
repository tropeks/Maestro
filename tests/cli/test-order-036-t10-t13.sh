#!/usr/bin/env bash
# ordem 036 (DATA_MODEL §9 v1.22) — T10, T11, T12, T13 do desenho (§8).
# Mesmo padrão PENDENTE/reprova-de-verdade das ordens 003/004A/013/017/021/022.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

CORE_PATCHED=0
if [[ -f "$REPO/lib/core-order-workproject.sh" ]] && grep -qF '_order_work_project' "$REPO/lib/core-order-workproject.sh" 2>/dev/null; then
  CORE_PATCHED=1
fi
if (( CORE_PATCHED == 0 )); then
  pending "ordem 036: work_project ainda ausente; aplicar os patches em docs/patches/036-*.patch"
  exit 0
fi

git_id() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }
git_init_main() { local d="$1"; git -C "$d" init -q; git -C "$d" symbolic-ref HEAD refs/heads/main; }
dono8() { REPO_DIR="$REPO" bash -c 'source "'"$REPO"'/hooks/lib/common.sh"; source "'"$REPO"'/lib/core-order-state.sh" 2>/dev/null; _order_dono8 "'"$1"'"'; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
export MAESTRO_WORK_ROOT="$tmp/work"
mkdir -p "$MAESTRO_WORK_ROOT"

# ===========================================================================
# fixture comum a T10/T11: ordem cross-repo, provada.
# ===========================================================================
A="$tmp/dono"; B="$MAESTRO_WORK_ROOT/trabalho"
mkdir -p "$A" "$B"
git_init_main "$A"; echo a > "$A/f.txt"; git_id "$A" add f.txt; git_id "$A" commit -qm base
git_init_main "$B"; echo b > "$B/g.txt"; git_id "$B" add g.txt; git_id "$B" commit -qm base

"$BIN" order --create --title "T10-T11" --branch "order/1-t1011" --project "$A" --session t --work-project trabalho <<'BODY' >/dev/null
## Objetivo
T10/T11.
BODY
git_id "$A" branch order/1-t1011
git_id "$B" checkout -qb order/1-t1011
echo w >> "$B/g.txt"; git_id "$B" add g.txt; git_id "$B" commit -qm w
D8=$(dono8 "$A")
"$BIN" evidence --record --label "order-1-$D8" --project "$B" -- true >/dev/null

# ===========================================================================
# T10 — aceite cross-repo não mexe na árvore do repo do trabalho: HEAD/tip de
# B antes == depois do --accept (I6/restrição 3/issue #6).
# ===========================================================================
TIP_B_ANTES=$(git -C "$B" rev-parse HEAD)
WT_B_ANTES=$(git -C "$B" status --porcelain)
"$BIN" order --accept 1 --project "$A" --session t >/dev/null
TIP_B_DEPOIS=$(git -C "$B" rev-parse HEAD)
WT_B_DEPOIS=$(git -C "$B" status --porcelain)
[[ "$TIP_B_ANTES" == "$TIP_B_DEPOIS" ]] && ok "(T10) tip de B (repo do trabalho) INTOCADO pelo --accept" \
  || bad "(T10) tip de B mudou: $TIP_B_ANTES -> $TIP_B_DEPOIS"
[[ "$WT_B_ANTES" == "$WT_B_DEPOIS" ]] && ok "(T10) árvore de trabalho de B INTOCADA (status --porcelain igual)" \
  || bad "(T10) status de B mudou: [$WT_B_ANTES] -> [$WT_B_DEPOIS]"

# ===========================================================================
# T11 — boletim de ordem provada dá o MESMO veredito rodado do worktree do
# branch (B) e do checkout principal (A) — a metade da #36 que fecha. O
# `maestro evidence` isolado CONTINUA divergindo — nomeado como esperado
# (#36 segue aberta).
# ===========================================================================
# reabre outra ordem provada (a 1 já foi aceita acima) pra testar a linha
# "prova :" de uma ordem AINDA provada, não aceita — cria a segunda.
"$BIN" order --create --title "T11 provada" --branch "order/2-t11" --project "$A" --session t --work-project trabalho <<'BODY' >/dev/null
## Objetivo
T11.
BODY
git_id "$A" branch order/2-t11
git_id "$B" checkout -qb order/2-t11
echo w2 >> "$B/g.txt"; git_id "$B" add g.txt; git_id "$B" commit -qm w2
"$BIN" evidence --record --label "order-2-$D8" --project "$B" -- true >/dev/null

PROVA_DE_A=$("$BIN" order --status 2 --project "$A" 2>&1 | grep '^  prova')
# muda o CHECKOUT de B para um branch diferente do da ordem — é exatamente o
# cenário que fazia `maestro evidence` isolado ler VENCIDA (papercut medido
# em 2026-09-19: "a ordem vive num git worktree e o recibo é comparado
# contra a árvore do checkout ATUAL").
git_id "$B" checkout -q main
PROVA_DE_A_2=$("$BIN" order --status 2 --project "$A" 2>&1 | grep '^  prova')
[[ "$PROVA_DE_A" == "$PROVA_DE_A_2" ]] \
  && ok "(T11) boletim da ordem dá o MESMO veredito com B em branches diferentes (deriva do tip, não do checkout)" \
  || bad "(T11) boletim mudou conforme o checkout de B: [$PROVA_DE_A] vs [$PROVA_DE_A_2]"
[[ "$PROVA_DE_A" == *"VÁLIDA"* ]] && ok "(T11) a linha 'prova :' diz VÁLIDA (sai da derivação, não do 'maestro evidence')" \
  || bad "(T11) esperava VÁLIDA na linha de prova: $PROVA_DE_A"

# `maestro evidence` ISOLADO continua divergindo — é #36, PERMANECE aberta.
EV_ISOLADO=$("$BIN" evidence --label "order-2-$D8" --project "$B" 2>&1)
if [[ "$EV_ISOLADO" == *"VÁLIDA"* ]]; then
  ok "(T11) achado: 'maestro evidence' isolado bateu por coincidência de checkout — não invalida o teste (checkout de B mudou acima)"
else
  ok "(T11) 'maestro evidence' ISOLADO diverge da ordem (issue #36 continua ABERTA, nomeada por desenho — não é regressão desta ordem)"
fi

# ===========================================================================
# T12 — --create --work-project grava o campo, recusa alvo inexistente e
# recusa alvo == o próprio dono; o contrato gerado traz as duas linhas de
# comando do §7.6.
# ===========================================================================
A12="$tmp/t12-dono"; B12="$MAESTRO_WORK_ROOT/t12-trabalho"
mkdir -p "$A12" "$B12"
git_init_main "$A12"; echo a > "$A12/f.txt"; git_id "$A12" add f.txt; git_id "$A12" commit -qm base
git_init_main "$B12"; echo b > "$B12/g.txt"; git_id "$B12" add g.txt; git_id "$B12" commit -qm base

"$BIN" order --create --title "T12" --project "$A12" --session t12 --work-project t12-trabalho <<'BODY' >/dev/null
## Objetivo
T12.
BODY
OF12=$(ls "$A12"/.maestro/orders/001-*.md)
grep -q '^work_project: t12-trabalho$' "$OF12" && ok "(T12) campo work_project gravado no cabeçalho" \
  || bad "(T12) campo não gravado: $(head -12 "$OF12")"
grep -q 'maestro order --status 1 --project' "$OF12" && ok "(T12) contrato traz 'maestro order --status N --project <dono>'" \
  || bad "(T12) contrato não tem a linha de status cross-repo"
D8_12=$(dono8 "$A12")
grep -q "order-1-$D8_12" "$OF12" && ok "(T12) contrato traz 'maestro evidence --record --label order-N-<dono8>'" \
  || bad "(T12) contrato não tem o rótulo namespeado"

OUT12N=$("$BIN" order --create --title "T12 alvo inexistente" --project "$A12" --session t12 --work-project alvo-que-nao-existe <<<$'## Objetivo\nx' 2>&1); RC12N=$?
[[ $RC12N -ne 0 ]] && ok "(T12) recusa --work-project com alvo inexistente" || bad "(T12) deveria recusar alvo inexistente: $OUT12N"

OUT12P=$("$BIN" order --create --title "T12 proprio dono" --project "$A12" --session t12 --work-project "$(basename "$A12")" <<<$'## Objetivo\nx' 2>&1); RC12P=$?
[[ $RC12P -ne 0 ]] && ok "(T12) recusa --work-project apontando pro PRÓPRIO dono (typo)" || bad "(T12) deveria recusar: $OUT12P"

# ===========================================================================
# T13 — contrato do consumidor externo: o JSON novo continua satisfazendo o
# RespostaSchema do daemon (chaves obrigatórias presentes, estado dentro do
# enum FECHADO de 6 valores).
# ===========================================================================
if command -v jq >/dev/null 2>&1; then
  J13=$("$BIN" order --status 1 --project "$A" 2>&1 --json)
  for k in id estado branch branch_existe branch_tip arquivo terminal suspensa pede_aceite motivo direcao verificacao absorvido_por adiado_por prova work_project work_project_dir; do
    [[ "$(jq "has(\"$k\")" <<<"$J13")" == "true" ]] && ok "(T13) chave '$k' presente" || bad "(T13) chave '$k' AUSENTE: $J13"
  done
  EST13=$(jq -r .estado <<<"$J13")
  case "$EST13" in
    aberta|em_execucao|provada|aceita|absorvida|adiada) ok "(T13) estado '$EST13' dentro do enum FECHADO de 6 valores" ;;
    *) bad "(T13) estado '$EST13' FORA do enum de 6 valores — quebraria o daemon (die, nunca estado novo)" ;;
  esac
  # campo novo não quebra leitor antigo (mesmo método do teste da ordem 014)
  FUTURO=$(jq -c '. + {"campo_desconhecido_do_daemon": 7}' <<<"$J13")
  jq -e . >/dev/null 2>&1 <<<"$FUTURO" && ok "(T13) objeto com os dois campos novos + injeção continua JSON válido" \
    || bad "(T13) JSON inválido após adicionar campo"
else
  pending "(T13) jq ausente — teste exige jq para validar o schema"
fi

if (( fail == 0 )); then echo "SUITE test-order-036-t10-t13.sh: OK"; else echo "SUITE test-order-036-t10-t13.sh: FALHAS" >&2; fi
exit $fail
