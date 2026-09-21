#!/usr/bin/env bash
# ordem 036 (DATA_MODEL §9 v1.22) — `work_project`: T2, T4, T5, T6, T7, T8, T9
# do desenho (§8). T3 (o homônimo) e T10-T13 moram em arquivos próprios
# (tests/cli/test-order-036-t3-homonimo.sh, tests/cli/test-order-036-t10-t13.sh)
# — mesmo motivo de sempre: não estourar a catraca `oversized-file` num
# arquivo de teste e manter cada prova nomeável pelo número do desenho.
#
# Mesmo padrão PENDENTE/reprova-de-verdade das ordens 003/004A/013/017/021/022
# (ver comentário de test-order-014-status-json.sh): mecanismo ausente (patch
# ainda não aplicado) → PENDENTE, nunca falha; mecanismo presente → cobra de
# verdade nos SEIS cenários abaixo.
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
# T2 — work_project válido, branch e recibo no repo B: --status deriva
# provada, --accept aceita, --status --json reporta provada/pede_aceite:true
# e os dois campos novos (work_project/work_project_dir).
# ===========================================================================
A="$tmp/t2-dono"; B="$MAESTRO_WORK_ROOT/t2-trabalho"
mkdir -p "$A" "$B"
git_init_main "$A"; echo a > "$A/f.txt"; git_id "$A" add f.txt; git_id "$A" commit -qm base
git_init_main "$B"; echo b > "$B/g.txt"; git_id "$B" add g.txt; git_id "$B" commit -qm base

"$BIN" order --create --title "T2 cross repo" --branch "order/1-t2" --project "$A" --session t2 --work-project t2-trabalho <<'BODY' >/dev/null
## Objetivo
T2 do desenho da ordem 036.
BODY
git_id "$A" branch order/1-t2
git_id "$B" checkout -qb order/1-t2
echo c >> "$B/g.txt"; git_id "$B" add g.txt; git_id "$B" commit -qm trabalho
D8=$(dono8 "$A")
"$BIN" evidence --record --label "order-1-$D8" --project "$B" -- true >/dev/null

ST=$("$BIN" order --status 1 --project "$A" 2>&1 | head -1)
[[ "$ST" == "ordem 001: provada" ]] && ok "(T2) --status deriva provada" || bad "(T2) esperava provada, obtido: $ST"

if command -v jq >/dev/null 2>&1; then
  J=$("$BIN" order --status 1 --project "$A" --json 2>&1)
  [[ "$(jq -r .estado <<<"$J")" == "provada" ]] && ok "(T2) --json estado=provada" || bad "(T2) --json estado != provada: $J"
  [[ "$(jq -r .pede_aceite <<<"$J")" == "true" ]] && ok "(T2) --json pede_aceite=true" || bad "(T2) pede_aceite != true"
  [[ "$(jq -r .work_project <<<"$J")" == "t2-trabalho" ]] && ok "(T2) --json work_project bate" || bad "(T2) work_project errado: $J"
  [[ "$(jq -r .work_project_dir <<<"$J")" == "$B" ]] && ok "(T2) --json work_project_dir bate" || bad "(T2) work_project_dir errado: $J"
fi

OUT=$("$BIN" order --accept 1 --project "$A" --session t2 2>&1); RC=$?
(( RC == 0 )) && ok "(T2) --accept aceita" || bad "(T2) --accept falhou: $OUT"

# ===========================================================================
# T4 — work_project presente, forma OK, NÃO resolve: die validation nomeando
# o campo, stdout VAZIO em texto e em --json (nenhum JSON parcial); --accept
# rc 1; --list continua listando as demais e marca [?].
# ===========================================================================
A4="$tmp/t4-dono"; mkdir -p "$A4"
git_init_main "$A4"; echo a > "$A4/f.txt"; git_id "$A4" add f.txt; git_id "$A4" commit -qm base
"$BIN" order --create --title "T4 noresolve" --project "$A4" --session t4 <<'BODY' >/dev/null
## Objetivo
T4.
BODY
"$BIN" order --create --title "T4 outra ordem normal" --project "$A4" --session t4 <<'BODY' >/dev/null
## Objetivo
segunda ordem, sem o campo — --list não pode parar de listar esta.
BODY
OF4=$(ls "$A4"/.maestro/orders/001-*.md)
sed -i '/^branch:/a work_project: naoexiste-em-lugar-nenhum' "$OF4"

OUT4=$("$BIN" order --status 1 --project "$A4" 2>&1); RC4=$?
[[ $RC4 -ne 0 ]] && ok "(T4) --status texto morre (rc=$RC4)" || bad "(T4) --status deveria morrer, rc=$RC4"
[[ "$OUT4" == *"não resolve"* ]] && ok "(T4) mensagem nomeia 'não resolve'" || bad "(T4) mensagem não nomeia o motivo: $OUT4"

OUT4J=$("$BIN" order --status 1 --project "$A4" --json 2>/dev/null); RC4J=$?
[[ $RC4J -ne 0 ]] && ok "(T4) --status --json morre (rc=$RC4J)" || bad "(T4) --json deveria morrer"
[[ -z "$OUT4J" ]] && ok "(T4) --json stdout VAZIO (nenhum JSON parcial)" || bad "(T4) --json vazou stdout parcial: $OUT4J"

OUT4A=$("$BIN" order --accept 1 --project "$A4" --session t4 2>&1); RC4A=$?
[[ $RC4A -ne 0 ]] && ok "(T4) --accept morre (rc=$RC4A)" || bad "(T4) --accept deveria morrer"

OUT4L=$("$BIN" order --list --project "$A4" 2>&1); RC4L=$?
[[ $RC4L -eq 0 ]] && ok "(T4) --list NÃO morre" || bad "(T4) --list morreu: rc=$RC4L"
[[ "$OUT4L" == *"[?]"* ]] && ok "(T4) --list marca [?]" || bad "(T4) --list não marcou [?]: $OUT4L"
[[ "$OUT4L" == *"002"* ]] && ok "(T4) --list continua mostrando a outra ordem (002)" || bad "(T4) --list não mostrou a 002: $OUT4L"

# ===========================================================================
# T5 — work_project com forma inválida: recusado em --create e em --status,
# com a mesma família de mensagem.
# ===========================================================================
A5="$tmp/t5-dono"; mkdir -p "$A5"
git_init_main "$A5"; echo a > "$A5/f.txt"; git_id "$A5" add f.txt; git_id "$A5" commit -qm base

for bad_val in "../x" "a/b" ".oculto" "$(printf 'a%.0s' {1..41})"; do
  OUT5=$("$BIN" order --create --title "T5 $bad_val" --project "$A5" --session t5 --work-project "$bad_val" <<<$'## Objetivo\nx' 2>&1); RC5=$?
  [[ $RC5 -ne 0 && "$OUT5" == *"forma inválida"* ]] \
    && ok "(T5) --create recusa work_project \"$bad_val\"" \
    || bad "(T5) --create deveria recusar \"$bad_val\": rc=$RC5 $OUT5"
done
# forma inválida escrita À MÃO no cabeçalho (bypassa a validação do --create)
"$BIN" order --create --title "T5 status invalido" --project "$A5" --session t5 <<'BODY' >/dev/null
## Objetivo
x
BODY
OF5=$(ls "$A5"/.maestro/orders/001-*.md)
sed -i '/^branch:/a work_project: a/b' "$OF5"
OUT5S=$("$BIN" order --status 1 --project "$A5" 2>&1); RC5S=$?
[[ $RC5S -ne 0 && "$OUT5S" == *"forma inválida"* ]] \
  && ok "(T5) --status recusa work_project de forma inválida escrito à mão" \
  || bad "(T5) --status deveria recusar: rc=$RC5S $OUT5S"

# ===========================================================================
# T6 — MAESTRO_WORK_ROOT vence o irmão; ausente, o irmão resolve; MESMO
# resultado de três cwds diferentes.
# ===========================================================================
mkdir -p "$tmp/t6-sibroot"
A6="$tmp/t6-sibroot/dono"; SIB6="$tmp/t6-sibroot/trabalho"; OTHER6="$tmp/t6-otherroot/trabalho"
mkdir -p "$A6" "$SIB6" "$OTHER6"
for d in "$A6" "$SIB6" "$OTHER6"; do git_init_main "$d"; echo x > "$d/f.txt"; git_id "$d" add f.txt; git_id "$d" commit -qm base; done
(
  unset MAESTRO_WORK_ROOT
  "$BIN" order --create --title "T6" --project "$A6" --session t6 --work-project trabalho <<'BODY' >/dev/null
## Objetivo
T6.
BODY
  D_SIB=$("$BIN" order --status 1 --project "$A6" --json 2>/dev/null | jq -r .work_project_dir 2>/dev/null)
  [[ "$D_SIB" == "$SIB6" ]] && ok "(T6) sem MAESTRO_WORK_ROOT resolve pro IRMÃO" || bad "(T6) esperava $SIB6, obtido $D_SIB"

  D1=$( cd "$A6" && "$BIN" order --status 1 --project "$A6" --json 2>/dev/null | jq -r .work_project_dir )
  D2=$( cd "$SIB6" && "$BIN" order --status 1 --project "$A6" --json 2>/dev/null | jq -r .work_project_dir )
  D3=$( cd /tmp && "$BIN" order --status 1 --project "$A6" --json 2>/dev/null | jq -r .work_project_dir )
  [[ "$D1" == "$D2" && "$D2" == "$D3" ]] && ok "(T6) MESMO resultado de 3 cwds diferentes" \
    || bad "(T6) resultado variou por cwd: $D1 / $D2 / $D3"
)
D_ROOT=$(MAESTRO_WORK_ROOT="$tmp/t6-otherroot" "$BIN" order --status 1 --project "$A6" --json 2>/dev/null | jq -r .work_project_dir)
[[ "$D_ROOT" == "$OTHER6" ]] && ok "(T6) MAESTRO_WORK_ROOT vence o irmão" || bad "(T6) esperava $OTHER6, obtido $D_ROOT"

# ===========================================================================
# T7 — registro terminal fica na chave do DONO: ordem 1 em A7 (work_project
# B7) e ordem 1 PRÓPRIA de B7 geram DOIS registros distintos em
# ~/.maestro/order-state, e aceitar uma não fecha a outra (I1).
# ===========================================================================
A7="$tmp/t7-dono"; B7="$MAESTRO_WORK_ROOT/t7-trabalho"
mkdir -p "$A7" "$B7"
git_init_main "$A7"; echo a > "$A7/f.txt"; git_id "$A7" add f.txt; git_id "$A7" commit -qm base
git_init_main "$B7"; echo b > "$B7/g.txt"; git_id "$B7" add g.txt; git_id "$B7" commit -qm base

"$BIN" order --create --title "T7 cross" --branch "order/1-t7" --project "$A7" --session t7 --work-project t7-trabalho <<'BODY' >/dev/null
## Objetivo
T7.
BODY
git_id "$A7" branch order/1-t7
git_id "$B7" checkout -qb order/1-t7
echo c >> "$B7/g.txt"; git_id "$B7" add g.txt; git_id "$B7" commit -qm w
D8_7=$(dono8 "$A7")
"$BIN" evidence --record --label "order-1-$D8_7" --project "$B7" -- true >/dev/null
"$BIN" order --accept 1 --project "$A7" --session t7 >/dev/null

git_id "$B7" checkout -q main
"$BIN" order --create --title "T7 propria B" --branch "order/1-t7own" --project "$B7" --session t7b <<'BODY' >/dev/null
## Objetivo
T7 própria de B.
BODY
git_id "$B7" branch order/1-t7own
"$BIN" evidence --record --label order-1 --project "$B7" -- true >/dev/null
"$BIN" order --accept 1 --project "$B7" --session t7b >/dev/null

N_REG=$(ls "$MAESTRO_HOME/order-state/" 2>/dev/null | grep -c -- '-001$')
(( N_REG >= 2 )) && ok "(T7) DOIS registros terminais distintos gravados (encontrados: $N_REG)" \
  || bad "(T7) esperava >=2 registros -001, encontrados $N_REG"
STA7=$("$BIN" order --status 1 --project "$A7" 2>&1 | head -1)
STB7=$("$BIN" order --status 1 --project "$B7" 2>&1 | head -1)
[[ "$STA7" == "ordem 001: aceita" ]] && ok "(T7) A7/001 continua aceita" || bad "(T7) A7/001: $STA7"
[[ "$STB7" == "ordem 001: aceita" ]] && ok "(T7) B7/001 (própria) continua aceita, independente" || bad "(T7) B7/001: $STB7"

# ===========================================================================
# T8 — candidatos de rótulo: com o campo presente, order-<n>-<dono8> é
# preferido; order-<n> legado ainda casa quando o BRANCH EXISTE.
# ===========================================================================
A8="$tmp/t8-dono"; B8="$MAESTRO_WORK_ROOT/t8-trabalho"
mkdir -p "$A8" "$B8"
git_init_main "$A8"; echo a > "$A8/f.txt"; git_id "$A8" add f.txt; git_id "$A8" commit -qm base
git_init_main "$B8"; echo b > "$B8/g.txt"; git_id "$B8" add g.txt; git_id "$B8" commit -qm base
"$BIN" order --create --title "T8 legado com branch" --branch "order/1-t8" --project "$A8" --session t8 --work-project t8-trabalho <<'BODY' >/dev/null
## Objetivo
T8.
BODY
git_id "$A8" branch order/1-t8
git_id "$B8" checkout -qb order/1-t8
echo c >> "$B8/g.txt"; git_id "$B8" add g.txt; git_id "$B8" commit -qm w
"$BIN" evidence --record --label order-1 --project "$B8" -- true >/dev/null   # SÓ o legado
ST8=$("$BIN" order --status 1 --project "$A8" 2>&1)
[[ "$ST8" == "ordem 001: provada"* ]] && ok "(T8) legado order-1 casa quando BRANCH existe" \
  || bad "(T8) esperava provada via legado com branch vivo: $ST8"

# ===========================================================================
# T9 — branch AUSENTE + work_project: recibo legado order-<n> do OUTRO dono
# NÃO vira provada (só o namespaceado vale) — trava do falso positivo (§5.3).
# ===========================================================================
A9="$tmp/t9-dono"; B9="$MAESTRO_WORK_ROOT/t9-trabalho"
mkdir -p "$A9" "$B9"
git_init_main "$A9"; echo a > "$A9/f.txt"; git_id "$A9" add f.txt; git_id "$A9" commit -qm base
git_init_main "$B9"; echo b > "$B9/g.txt"; git_id "$B9" add g.txt; git_id "$B9" commit -qm base
"$BIN" order --create --title "T9 sem branch" --branch "order/9-inexistente" --project "$A9" --session t9 --work-project t9-trabalho <<'BODY' >/dev/null
## Objetivo
T9.
BODY
# recibo LEGADO order-1 gravado no ledger de B9 (poderia ser de uma ordem
# HOMÔNIMA de outro dono, M4) — branch nunca existiu, sem tip pra ancorar.
"$BIN" evidence --record --label order-1 --project "$B9" -- true >/dev/null
ST9=$("$BIN" order --status 1 --project "$A9" 2>&1 | head -1)
[[ "$ST9" == "ordem 001: aberta" ]] && ok "(T9) legado SEM branch NÃO vira provada (falso positivo travado)" \
  || bad "(T9) deveria continuar aberta com só o legado sem branch: $ST9"
D8_9=$(dono8 "$A9")
"$BIN" evidence --record --label "order-1-$D8_9" --project "$B9" -- true >/dev/null
ST9b=$("$BIN" order --status 1 --project "$A9" 2>&1 | head -1)
[[ "$ST9b" == "ordem 001: provada" ]] && ok "(T9) namespaceado SEM branch vira provada" \
  || bad "(T9) deveria virar provada com o namespaceado: $ST9b"

if (( fail == 0 )); then echo "SUITE test-order-036-t2-t9.sh: OK"; else echo "SUITE test-order-036-t2-t9.sh: FALHAS" >&2; fi
exit $fail
