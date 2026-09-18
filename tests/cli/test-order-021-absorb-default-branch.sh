#!/usr/bin/env bash
# ordem 021 (adendo do diretor) — `maestro order --accept N --absorbed-by
# main` recusa TODO repo cujo branch padrão é `master`: a string 'main' é
# literal em QUATRO pontos de `_order_accept_absorb`
# (`lib/cmd-order.sh:235-247`) — gatilho do ramo, existência, árvore E o
# RÓTULO DO RECIBO (`maestro_evidence_file "$proj" main`). `--absorbed-by
# master` também é recusado, pela validação genérica que só aceita 'main' ou
# id numérico. Resultado medido no NetForge: nenhuma ordem pode ser fechada
# como absorvida — não há caminho.
#
# O conserto: `_order_default_branch` (lib/core-order-state.sh) resolve o
# branch padrão de verdade (origin/HEAD → config local, só se o branch
# existir → existência direta de main/master → fallback 'main'), SEM rede.
# 'main' e 'master' viram os DOIS apelidos aceitos para "o branch padrão do
# repo" — resolvidos, nunca fixos — e o carimbo passa a gravar o nome REAL
# do branch (não o apelido digitado), o que também corrige o rótulo do
# recibo (`maestro_evidence_file "$proj" main` → `... "$def_br"`).
#
# Mesmo padrão PENDENTE/reprova-de-verdade das ordens 003/004A/013/017/021:
# sem o patch, PENDENTE (nunca falha; lib/ está na denylist do gate); com o
# patch, cobra de verdade.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
COS="$REPO/lib/core-order-state.sh"
CMO="$REPO/lib/cmd-order.sh"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

# Guard por MECANISMO, nunca por ENDEREÇO (lição da ordem 019, paga aqui):
# a versão anterior exigia `_order_default_branch` em core-order-state.sh E em
# cmd-order.sh. A ordem 022 extraiu as ações de aceite para cmd-order-accept.sh
# — o mecanismo mudou de arquivo, o guard continuou apontando para o antigo, e
# passou a dizer "sem patch" com o patch aplicado. Um guard que erra o mundo em
# que está transforma verde em vermelho falso, que é pior que teste ausente.
# Agora pergunta se o mecanismo existe em ALGUM módulo do plugin — nunca em
# tests/, que casaria com este próprio arquivo e tornaria o guard sempre-verdadeiro.
CORE_PATCHED=0
if grep -rqF '_order_default_branch' "$REPO/lib" "$REPO/bin" "$REPO/hooks" 2>/dev/null; then
  CORE_PATCHED=1
fi

git_init_branch() { # <dir> <branch> → git init com o branch de topo dado (sem depender de -b do git instalado)
  local d="$1" b="$2"
  git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD "refs/heads/$b"
}
git_id() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

# ===========================================================================
# fixture A — baseline: repo cujo branch padrão É 'main'. NÃO pode regredir
# — tem de funcionar igual antes e depois do patch (mesmo rótulo de recibo).
# ===========================================================================
MA="$tmp/proj-main"; mkdir -p "$MA"
git_init_branch "$MA" main
echo a > "$MA/f.txt"; git_id "$MA" add f.txt; git_id "$MA" commit -qm base

"$BIN" order --create --title "Absorvida no main" --project "$MA" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Absorvida pelo branch padrão — repo main, sem regressão.
BODY
echo b >> "$MA/f.txt"; git_id "$MA" add f.txt; git_id "$MA" commit -qm "main andou"
"$BIN" evidence --record --label main --project "$MA" -- true >/dev/null
OUT_A=$("$BIN" order --accept 1 --absorbed-by main --project "$MA" --session dir-1 2>&1)
RC_A=$?
if [[ $RC_A -eq 0 ]]; then
  ok "(A) repo main-default: --absorbed-by main continua funcionando (sem regressão)"
else
  bad "(A) repo main-default: --absorbed-by main deixou de funcionar (regressão) — $OUT_A"
fi
STA=$(head -1 <<<"$("$BIN" order --status 1 --project "$MA" 2>&1)" | awk '{print $3}')
[[ "$STA" == "absorvida" ]] \
  && ok "(A) estado 'absorvida', rótulo de recibo 'main' seguiu sendo achado" \
  || bad "(A) esperava 'absorvida', obtido '$STA'"

# ===========================================================================
# fixture B — o caso do NetForge: repo cujo branch padrão é 'master'.
# ===========================================================================
MB="$tmp/proj-master"; mkdir -p "$MB"
git_init_branch "$MB" master
echo a > "$MB/f.txt"; git_id "$MB" add f.txt; git_id "$MB" commit -qm base

"$BIN" order --create --title "Absorvida no master" --project "$MB" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Absorvida pelo branch padrão — repo master (NetForge).
BODY
echo b >> "$MB/f.txt"; git_id "$MB" add f.txt; git_id "$MB" commit -qm "master andou"
"$BIN" evidence --record --label master --project "$MB" -- true >/dev/null

OUT_B1=$("$BIN" order --accept 1 --absorbed-by main --project "$MB" --session dir-1 2>&1)
RC_B1=$?
if (( CORE_PATCHED == 0 )); then
  pending "(B.1) sem o patch: --absorbed-by main num repo master — rc=$RC_B1 — aplicar docs/patches/021-estado-terminal-*.patch"
  [[ $RC_B1 -ne 0 ]] \
    && ok "vermelho confirmado (sem patch): --absorbed-by main recusa repo master — $OUT_B1" \
    || bad "vermelho não reproduziu: --absorbed-by main deveria recusar (sem patch) num repo master, mas rc=0"
else
  if [[ $RC_B1 -eq 0 ]]; then
    ok "(B.1) --absorbed-by main resolve para o branch padrão real ('master') e funciona"
  else
    bad "(B.1) --absorbed-by main deveria funcionar (resolvendo para master) — $OUT_B1"
  fi
  ST_B1=$(head -1 <<<"$("$BIN" order --status 1 --project "$MB" 2>&1)" | awk '{print $3}')
  [[ "$ST_B1" == "absorvida" ]] \
    && ok "(B.1) estado 'absorvida' depois de --absorbed-by main num repo master" \
    || bad "(B.1) esperava 'absorvida', obtido '$ST_B1'"
  ABS_BY=$(grep '^absorbed_by:' "$MB"/.maestro/orders/001-*.md 2>/dev/null | awk '{print $2}')
  [[ "$ABS_BY" == "master" ]] \
    && ok "(B.1) carimbo grava o branch REAL ('master'), não o apelido digitado ('main')" \
    || bad "(B.1) absorbed_by deveria ser 'master', obtido '$ABS_BY'"
fi

# ---------------------------------------------------------------------------
# fixture B.2 — MESMO repo master, segunda ordem, usando o apelido 'master'
# explicitamente (o outro sintoma relatado: --absorbed-by master também era
# recusado hoje, pela validação genérica).
# ---------------------------------------------------------------------------
"$BIN" order --create --title "Absorvida no master (apelido explicito)" --project "$MB" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Segunda ordem, usa --absorbed-by master (apelido explícito) em vez de main.
BODY
OUT_B2=$("$BIN" order --accept 2 --absorbed-by master --project "$MB" --session dir-1 2>&1)
RC_B2=$?
if (( CORE_PATCHED == 0 )); then
  pending "(B.2) sem o patch: --absorbed-by master — rc=$RC_B2 (validação genérica recusa hoje)"
  [[ $RC_B2 -ne 0 ]] \
    && ok "vermelho confirmado (sem patch): --absorbed-by master é recusado pela validação de hoje — $OUT_B2" \
    || bad "vermelho não reproduziu: --absorbed-by master deveria ser recusado sem o patch, mas rc=0"
else
  [[ $RC_B2 -eq 0 ]] \
    && ok "(B.2) --absorbed-by master (apelido explícito) funciona" \
    || bad "(B.2) --absorbed-by master deveria funcionar — $OUT_B2"
fi

if (( fail == 0 )); then echo "SUITE test-order-021-absorb-default-branch.sh: OK"; else echo "SUITE test-order-021-absorb-default-branch.sh: FALHAS" >&2; fi
exit $fail
