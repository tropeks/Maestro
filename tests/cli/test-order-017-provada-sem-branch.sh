#!/usr/bin/env bash
# ordem 017 — estado terminal da ordem não pode depender de o branch existir.
# Arquivo PRÓPRIO (não em test-order.sh) para não estourar o teto da catraca
# `oversized-file` — mesmo motivo de tests/cli/test-order-issue6.sh e
# tests/cli/test-order-issue13.sh.
#
# Caso real, medido no vulcan (2026-09-16):
#   .maestro/orders/002-lab-como-ambiente-de-prova-cript.md
#     id: 002   branch: order/006-lab-prova
#     absorbed_by: AUSENTE     accepted_at: AUSENTE
#   → "estado":"aberta"  "branch_existe":false  "terminal":false
#
# "Branch ausente" tem dois sentidos opostos e `_order_status` só conhecia um:
# nunca criado (aberta, certo) e mergeado-e-apagado (aberta, ERRADO — o
# caminho feliz do projeto rebaixa a ordem para "nada começou"). A CAUSA não é
# `absorbed_tree` (só é IMPRESSO, nunca comparado nos três lugares em que
# aparece) — é o ramo em `lib/core-order-state.sh` que decide `aberta` assim
# que `git rev-parse --verify` falha para o branch, sem checar o ledger.
#
# Decisão do diretor (não abrir estado novo no enum — item 2/3 da trava desta
# ordem): reusar `provada`, que já significa "há recibo válido, revise e
# aceite" para todo consumidor (`pede_aceite:true`, `motivo:"revisar e
# aceitar"`, `terminal:false` — nenhum dos três muda). O que muda é CONTRA O
# QUE o recibo é conferido quando não há branch: a árvore que ele CONGELOU
# (`wtree_after`), nunca comparada a um tip que não existe — mesma técnica de
# `_order_deferred_tree` (ordem 013, adiada), por outro motivo (lá é "adiada
# não anda", aqui é "o branch sumiu"). O recibo continua tendo de existir E
# ter `exit=0`; a prova não afrouxa, só o alvo da comparação muda.
#
# Lição da ordem 003/004A, contrato desta ordem: o teste NÃO exige o patch já
# aplicado. Detecta o MECANISMO em lib/core-order-state.sh: ausente →
# PENDENTE (nunca reprova — lib/ está na denylist de autoproteção do gate;
# quem aplica docs/patches/ é o Capitão); presente → cobra de verdade e
# REPROVA se o mecanismo não funcionar.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
COS="$REPO/lib/core-order-state.sh"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

command -v jq >/dev/null 2>&1 || { echo "PENDENTE  jq ausente — pulando as asserções de --json"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

# Mecanismo do núcleo: o predicado que esta ordem introduz — árvore CONGELADA
# do recibo, sem comparar com tip (mesma varredura de _order_deferred_tree,
# gate próprio de exit=0, mesmo rigor de _order_evidence_match).
CORE_PATCHED=0
grep -qF '_order_evidence_frozen_tree' "$COS" 2>/dev/null && CORE_PATCHED=1

git_init_main() { # <dir> → git init com o branch de topo chamado 'main'
  local d="$1"
  git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD refs/heads/main
}

P="$tmp/proj"; mkdir -p "$P"
git_init_main "$P"
echo a > "$P/f.txt"
git -C "$P" add f.txt
git -C "$P" -c user.email=t@t -c user.name=t commit -qm base

# ---------------------------------------------------------------------------
# fixture 1 (o caso do vulcan): recibo VÁLIDO gravado no branch de entrega,
# branch depois MERGEADO e APAGADO (fim normal de toda ordem), SEM carimbo
# terminal (accepted_at/absorbed_by/deferred_by ausentes). O arquivo da ordem
# fica de fora do git de propósito (untracked) — é assim que este repo os
# trata hoje (ver `git status` do worktree real: `.maestro/orders/*.md` são
# `??`), e é o que garante que ele sobrevive ao checkout/delete do branch,
# exatamente como o caso do vulcan.
# ---------------------------------------------------------------------------
"$BIN" order --create --title "Vulcan-like" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Reproduz .maestro/orders/002 do vulcan: recibo com branch mergeado e apagado.
BODY
OF1="$P/.maestro/orders/001-vulcan-like.md"
BR1=$(grep '^branch:' "$OF1" | awk '{print $2}')
git -C "$P" checkout -qb "$BR1"
echo b >> "$P/f.txt"; git -C "$P" add f.txt
git -C "$P" -c user.email=t@t -c user.name=t commit -qm entrega
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
git -C "$P" checkout -q main
git -C "$P" merge -q --no-edit "$BR1" >/dev/null
git -C "$P" branch -D "$BR1" >/dev/null

TXT1=$("$BIN" order --status 1 --project "$P" 2>&1)
ST1=$(head -1 <<<"$TXT1" | awk '{print $3}')

if (( CORE_PATCHED == 0 )); then
  pending "ordem 017 (i): recibo com branch apagado ainda lê 'aberta' — lib/core-order-state.sh sem _order_evidence_frozen_tree; aplicar docs/patches/017-estado-terminal-core-order-state.patch"
  # a asserção que PROVA o defeito hoje, contra o código sem o patch — vermelha:
  # o invariante da ordem ("prova no ledger nunca lê aberta") ainda FALHA.
  if [[ "$ST1" == "aberta" ]]; then
    ok "vermelho confirmado (sem patch): recibo válido + branch apagado ainda lê 'aberta' — $TXT1"
  else
    bad "vermelho não reproduziu: esperava 'aberta' no código sem patch, obtido '$ST1'"
  fi
else
  if [[ "$ST1" == "provada" ]]; then
    ok "ordem 017 (i): recibo válido + branch apagado + sem carimbo → 'provada', NUNCA 'aberta' ($TXT1)"
  else
    bad "ordem 017 (i): esperava 'provada', obtido '$ST1' — $TXT1"
  fi
fi

# ---------------------------------------------------------------------------
# fixture 2 (o caso legítimo): sem recibo nenhum e sem branch — nada começou.
# Continua 'aberta', com ou sem o patch — não é gated por CORE_PATCHED.
# ---------------------------------------------------------------------------
"$BIN" order --create --title "Nunca comecou" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Nada aconteceu ainda — nem branch, nem recibo.
BODY
TXT2=$("$BIN" order --status 2 --project "$P" 2>&1)
ST2=$(head -1 <<<"$TXT2" | awk '{print $3}')
if [[ "$ST2" == "aberta" ]]; then
  ok "ordem 017 (ii): sem recibo e sem branch → 'aberta' (nada começou) — continua certo"
else
  bad "ordem 017 (ii): regressão — sem recibo e sem branch deveria seguir 'aberta', obtido '$ST2'"
fi

# ---------------------------------------------------------------------------
# fixture 3: recibo com exit != 0 (execução provou FALHA) + branch apagado —
# não pode virar 'provada' às escondidas; o gate de exit=0 é o mesmo rigor de
# _order_evidence_match. Não é gated por CORE_PATCHED: no código sem patch já
# é 'aberta' (o ramo nem olha pro recibo); com patch tem de continuar 'aberta'
# porque o recibo não é VÁLIDO.
# ---------------------------------------------------------------------------
"$BIN" order --create --title "Recibo com falha" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Execução falhou; branch some depois — não pode virar prova.
BODY
OF3="$P/.maestro/orders/003-recibo-com-falha.md"
BR3=$(grep '^branch:' "$OF3" | awk '{print $2}')
git -C "$P" checkout -qb "$BR3"
echo c >> "$P/f.txt"; git -C "$P" add f.txt
git -C "$P" -c user.email=t@t -c user.name=t commit -qm entrega3
"$BIN" evidence --record --label order-3 --project "$P" -- false >/dev/null 2>&1
git -C "$P" checkout -q main
git -C "$P" branch -D "$BR3" >/dev/null
TXT3=$("$BIN" order --status 3 --project "$P" 2>&1)
ST3=$(head -1 <<<"$TXT3" | awk '{print $3}')
if [[ "$ST3" == "aberta" ]]; then
  ok "ordem 017 (iii): recibo com exit≠0 + branch apagado → continua 'aberta' (recibo inválido não prova nada)"
else
  bad "ordem 017 (iii): recibo com exit≠0 não pode virar prova — obtido '$ST3'"
fi

# ---------------------------------------------------------------------------
# fixture 4: 'aceita' continua terminal com o branch deletado.
# ---------------------------------------------------------------------------
"$BIN" order --create --title "Vai aceitar" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Prova, aceita, depois o branch some — tem de continuar 'aceita'.
BODY
OF4="$P/.maestro/orders/004-vai-aceitar.md"
BR4=$(grep '^branch:' "$OF4" | awk '{print $2}')
git -C "$P" checkout -qb "$BR4"
echo d >> "$P/f.txt"; git -C "$P" add f.txt
git -C "$P" -c user.email=t@t -c user.name=t commit -qm entrega4
"$BIN" evidence --record --label order-4 --project "$P" -- true >/dev/null
"$BIN" order --accept 4 --project "$P" --session dir-1 >/dev/null 2>&1
git -C "$P" checkout -q main
git -C "$P" merge -q --no-edit "$BR4" >/dev/null
git -C "$P" branch -D "$BR4" >/dev/null
TXT4=$("$BIN" order --status 4 --project "$P" 2>&1)
ST4=$(head -1 <<<"$TXT4" | awk '{print $3}')
[[ "$ST4" == "aceita" ]] \
  && ok "ordem 017 (iv): 'aceita' continua terminal com o branch deletado" \
  || bad "ordem 017 (iv): regressão — esperava 'aceita', obtido '$ST4'"

# ---------------------------------------------------------------------------
# fixture 5: 'absorvida' continua terminal sem NUNCA ter tido branch.
# ---------------------------------------------------------------------------
"$BIN" order --create --title "Vai ser absorvida" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Absorvida pelo main — nunca teve branch próprio.
BODY
echo e >> "$P/f.txt"; git -C "$P" add f.txt
git -C "$P" -c user.email=t@t -c user.name=t commit -qm "main andou"
"$BIN" evidence --record --label main --project "$P" -- true >/dev/null
"$BIN" order --accept 5 --absorbed-by main --project "$P" --session dir-1 >/dev/null 2>&1
TXT5=$("$BIN" order --status 5 --project "$P" 2>&1)
ST5=$(head -1 <<<"$TXT5" | awk '{print $3}')
[[ "$ST5" == "absorvida" ]] \
  && ok "ordem 017 (v): 'absorvida' continua terminal (nunca teve branch próprio)" \
  || bad "ordem 017 (v): regressão — esperava 'absorvida', obtido '$ST5'"

# ---------------------------------------------------------------------------
# (vi) --json da fixture 1 (o caso do vulcan): terminal/pede_aceite/motivo são
# o contrato externo — supervisor e watcher.ts decidem por eles, não pela
# string crua de 'estado'. 'provada' já existia no switch de
# _order_json_acao_frag (lib/cmd-order-json.sh): NENHUMA mudança foi
# necessária ali — só _order_proof_tree (core) ganhou o fallback de árvore
# congelada para que 'prova.arvore' não fique null.
# ---------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  JSON1=$("$BIN" order --status 1 --project "$P" --json 2>&1)
  if jq -e . >/dev/null 2>&1 <<<"$JSON1"; then
    j_estado=$(jq -r '.estado' <<<"$JSON1")
    j_terminal=$(jq -r '.terminal' <<<"$JSON1")
    j_pede=$(jq -r '.pede_aceite' <<<"$JSON1")
    j_motivo=$(jq -r '.motivo' <<<"$JSON1")
    j_arvore=$(jq -r '.prova.arvore' <<<"$JSON1")
    if (( CORE_PATCHED == 0 )); then
      pending "ordem 017 (vi): --json do caso vulcan ainda sem o patch — estado='$j_estado' pede_aceite='$j_pede'"
    else
      [[ "$j_estado" == "provada" ]] && ok "(vi) --json: estado == 'provada' (nunca 'aberta')" \
        || bad "(vi) --json: estado == '$j_estado', esperava 'provada'"
      [[ "$j_terminal" == "false" ]] && ok "(vi) --json: terminal == false (não é fim de linha — humano ainda decide)" \
        || bad "(vi) --json: terminal == '$j_terminal', esperava 'false'"
      [[ "$j_pede" == "true" ]] && ok "(vi) --json: pede_aceite == true (é o sinal que interrompe humano)" \
        || bad "(vi) --json: pede_aceite == '$j_pede', esperava 'true'"
      [[ "$j_motivo" == "revisar e aceitar" ]] && ok "(vi) --json: motivo == 'revisar e aceitar' (mesmo texto de 'provada' com branch vivo)" \
        || bad "(vi) --json: motivo == '$j_motivo', esperado 'revisar e aceitar'"
      [[ -n "$j_arvore" && "$j_arvore" != "null" ]] && ok "(vi) --json: prova.arvore preenchida (árvore CONGELADA do recibo, sha=$j_arvore)" \
        || bad "(vi) --json: prova.arvore ficou null — o fallback de _order_proof_tree não pegou"
    fi
  else
    bad "(vi) --json não é JSON válido: $JSON1"
  fi
fi
if (( fail == 0 )); then echo "SUITE test-order-017-provada-sem-branch.sh: OK"; else echo "SUITE test-order-017-provada-sem-branch.sh: FALHAS" >&2; fi
exit $fail
