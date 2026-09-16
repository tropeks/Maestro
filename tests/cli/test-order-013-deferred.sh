#!/usr/bin/env bash
# ordem 013 — recibo de ordem ADIADA vence todo dia. Quinto sintoma da mesma
# família (#6/#12/#13/#18/#20): o modelo não representava "trabalho adiado
# POR DECISÃO" e o veredito genérico de `maestro evidence` (idade + mudança
# de árvore) acusava VENCIDA sobre trabalho que ninguém abandonou. Caso real:
# ordem 004 do Vitali, `deferred_by:` escrito à mão no cabeçalho porque o
# modelo não tinha a palavra.
#
# Arquivo PRÓPRIO (não em test-order.sh) — mesmo motivo de
# tests/cli/test-order-issue6.sh/issue12.sh/issue13.sh: não estourar o teto
# da catraca `oversized-file`.
#
# `adiada` é SUSPENSA, distinta de `absorvida` (TERMINAL, issue #12) — a
# ordem continua VISÍVEL em --list/--status, sem cobrar aceite e sem acusar
# prova vencida enquanto o campo existir.
#
# Lição da ordem 003/004A: o teste NÃO exige o patch já aplicado. Detecta o
# MECANISMO em lib/core-order-state.sh, lib/cmd-order.sh e
# hooks/session-start.sh (lib/ e hooks/ estão na denylist de autoproteção do
# gate — quem aplica docs/patches/013-deferred-by-*.patch é o Capitão);
# ausente → PENDENTE (nunca reprova); presente → cobra de verdade E prova o
# terceiro estado — sabota o mecanismo (numa CÓPIA) e mostra que a MESMA
# asserção reprova.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
CORE="$REPO/lib/core-order-state.sh"
CMD="$REPO/lib/cmd-order.sh"
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

git_init_main() { # <dir> → git init com branch de topo 'main', independente do init.defaultBranch
  local d="$1"
  git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD refs/heads/main
}

# ---------------------------------------------------------------------------
# mecanismo: presença nos 3 arquivos que a ordem 013 toca.
# ---------------------------------------------------------------------------
CORE_PATCHED=0; grep -qF '_order_deferred_tree' "$CORE" 2>/dev/null && CORE_PATCHED=1
CMD_PATCHED=0;  grep -qF 'ADIADA por' "$CMD" 2>/dev/null && CMD_PATCHED=1
HOOK_PATCHED=0; grep -qF 'deferred_by' "$SS" 2>/dev/null && HOOK_PATCHED=1

# ---------------------------------------------------------------------------
# fixture: um projeto com DUAS ordens — a 1 vai ganhar deferred_by (adiada),
# a 2 fica NORMAL (controle da regressão: sem o campo, continua vencendo).
# ---------------------------------------------------------------------------
P="$tmp/proj"; mkdir -p "$P"
git_init_main "$P"
echo base > "$P/f.txt"; git -C "$P" add -A
git -C "$P" -c user.email=t@t -c user.name=t commit -qm base

"$BIN" order --create --title "Adiada por decisao" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Caso Vitali: o Capitao adiou este trabalho POR DECISAO. Nao andou desde entao.
BODY
OF1="$P/.maestro/orders/001-adiada-por-decisao.md"
BR1=$(grep '^branch:' "$OF1" | awk '{print $2}')
git -C "$P" checkout -qb "$BR1"
echo entrega1 >> "$P/f.txt"; git -C "$P" add f.txt
git -C "$P" -c user.email=t@t -c user.name=t commit -qm entrega1
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null
git -C "$P" checkout -q main

"$BIN" order --create --title "Normal sem o campo" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Controle da regressao: SEM deferred_by, continua vencendo exatamente como hoje.
BODY
OF2="$P/.maestro/orders/002-normal-sem-o-campo.md"
BR2=$(grep '^branch:' "$OF2" | awk '{print $2}')
git -C "$P" checkout -qb "$BR2"
echo entrega2 >> "$P/f.txt"; git -C "$P" add f.txt
git -C "$P" -c user.email=t@t -c user.name=t commit -qm entrega2
"$BIN" evidence --record --label order-2 --project "$P" -- true >/dev/null
git -C "$P" checkout -q main

# carimba deferred_by: no CABEÇALHO da ordem 1 (mesma técnica de absorbed_by,
# issue #12: insere antes do "-->" — dentro das 20 linhas que _order_field lê).
awk -v ins='deferred_by: Capitao' '!done && $0 == "-->" { print ins; done=1 } { print }' \
  "$OF1" > "$OF1.tmp.$$" && mv -f "$OF1.tmp.$$" "$OF1"
grep -q '^deferred_by: Capitao$' "$OF1" && ok "fixture: deferred_by gravado no cabeçalho da ordem 1" \
  || bad "fixture: deferred_by não gravou (não deveria acontecer — bug no teste)"

if (( CORE_PATCHED == 0 || CMD_PATCHED == 0 )); then
  pending "ordem 013: mecanismo de 'adiada' ainda ausente em lib/core-order-state.sh/lib/cmd-order.sh; aplicar docs/patches/013-deferred-by-core-order-state.patch e docs/patches/013-deferred-by-cmd-order.patch"
else
  ok "mecanismo presente: lib/core-order-state.sh (_order_deferred_tree) e lib/cmd-order.sh ('ADIADA por')"

  # -------------------------------------------------------------------------
  # (a) leitura: 'adiada', 'ADIADA por Capitao', prova congelada, SEM VENCIDA.
  # -------------------------------------------------------------------------
  OUT1=$("$BIN" order --status 1 --project "$P" 2>&1)
  grep -q '^ordem 001: adiada$' <<<"$OUT1" && ok "(a) status derivado é 'adiada'" \
    || bad "(a) status não é 'adiada' ($(head -1 <<<"$OUT1"))"
  grep -q 'ADIADA por Capitao' <<<"$OUT1" && ok "(a) leitura diz ADIADA por <quem>" \
    || bad "(a) leitura não diz ADIADA por Capitao ($OUT1)"
  grep -q 'prova congelada em' <<<"$OUT1" && ok "(a) leitura cita a árvore congelada" \
    || bad "(a) leitura não cita árvore congelada ($OUT1)"
  if grep -q 'VENCIDA' <<<"$OUT1"; then bad "(a) leitura contém VENCIDA — mentira sobre trabalho que ninguém abandonou ($OUT1)"
  else ok "(a) leitura NUNCA diz VENCIDA para ordem adiada"; fi
  ORIG_TREE=$(grep -o 'congelada em [0-9a-f]\{12\}' <<<"$OUT1" | awk '{print $3}')
  [[ -n "$ORIG_TREE" ]] && ok "(a) árvore congelada capturada: $ORIG_TREE" || bad "(a) não consegui capturar a árvore congelada"

  # -------------------------------------------------------------------------
  # (b) não vence por IDADE: envelhece o recibo da ordem 1 e relê.
  # -------------------------------------------------------------------------
  EF1=$(ls "$MAESTRO_HOME/evidence"/*-order-1 2>/dev/null | head -1)
  sed -i 's/^epoch=.*/epoch=1/' "$EF1"
  OUT1B=$("$BIN" order --status 1 --project "$P" 2>&1)
  if grep -q 'VENCIDA' <<<"$OUT1B"; then bad "(b) recibo ENVELHECIDO ainda venceu por idade ($OUT1B)"
  else ok "(b) recibo envelhecido não vence por idade — trabalho adiado não anda"; fi
  grep -q "congelada em $ORIG_TREE" <<<"$OUT1B" && ok "(b) árvore congelada não mudou" \
    || bad "(b) árvore congelada mudou depois de envelhecer o recibo ($OUT1B)"

  # -------------------------------------------------------------------------
  # (c) não vence por MUDANÇA DE ÁRVORE: o branch anda SEM prova nova.
  # -------------------------------------------------------------------------
  git -C "$P" checkout -q "$BR1"
  echo mexeu >> "$P/f.txt"; git -C "$P" add f.txt
  git -C "$P" -c user.email=t@t -c user.name=t commit -qm "mexeu depois de adiada"
  git -C "$P" checkout -q main
  OUT1C=$("$BIN" order --status 1 --project "$P" 2>&1)
  if grep -q 'VENCIDA' <<<"$OUT1C"; then bad "(c) árvore mudou e o recibo venceu ($OUT1C)"
  else ok "(c) árvore do branch mudou e o recibo NÃO venceu"; fi
  grep -q "congelada em $ORIG_TREE" <<<"$OUT1C" && ok "(c) árvore mostrada continua sendo a CONGELADA, não o tip novo" \
    || bad "(c) árvore mostrada mudou para o tip novo em vez de ficar congelada ($OUT1C)"

  # -------------------------------------------------------------------------
  # (d) --list: ordem adiada continua VISÍVEL (distinta de absorvida/sumida).
  # -------------------------------------------------------------------------
  OUTL=$("$BIN" order --list --project "$P" 2>&1)
  grep -q '^001  \[adiada\]' <<<"$OUTL" && ok "(d) --list mostra [adiada] — ordem continua visível" \
    || bad "(d) --list não mostra [adiada] para a ordem 1 ($OUTL)"

  # -------------------------------------------------------------------------
  # (e) regressão que importa: ordem 2 SEM deferred_by continua vencendo
  # exatamente como hoje (idade).
  # -------------------------------------------------------------------------
  EF2=$(ls "$MAESTRO_HOME/evidence"/*-order-2 2>/dev/null | head -1)
  sed -i 's/^epoch=.*/epoch=1/' "$EF2"
  OUT2=$("$BIN" order --status 2 --project "$P" 2>&1)
  grep -q 'VENCIDA' <<<"$OUT2" && ok "(e) REGRESSÃO: ordem SEM deferred_by continua vencendo por idade" \
    || bad "(e) REGRESSÃO QUEBRADA: ordem sem deferred_by parou de vencer ($OUT2)"
  grep -q '^ordem 002: adiada$' <<<"$OUT2" && bad "(e) ordem SEM deferred_by virou 'adiada' — vazamento do mecanismo" \
    || ok "(e) ordem sem deferred_by não é afetada pelo mecanismo novo"

  # -------------------------------------------------------------------------
  # (f) hooks/session-start.sh: adiada não conta como pendente; normal conta.
  # -------------------------------------------------------------------------
  if (( HOOK_PATCHED == 0 )); then
    pending "ordem 013 (f): deferred_by ainda não excluído da contagem de pendentes em hooks/session-start.sh"
  else
    OUTH=$(printf '{"session_id":"o13-hook"}' | CLAUDE_PROJECT_DIR="$P" bash "$SS" 2>/dev/null)
    if grep -q 'ordens: 1 pendente' <<<"$OUTH"; then
      ok "(f) só a ordem NORMAL (sem deferred_by) conta como pendente — a adiada não"
    else
      bad "(f) contagem de pendentes errada: $(grep -o 'ordens: [^ ]* pendente(s)' <<<"$OUTH")"
    fi
  fi

  # -------------------------------------------------------------------------
  # (g) terceiro estado: sabota o mecanismo NUMA CÓPIA e mostra que a MESMA
  # asserção de (c) reprova — nunca `git archive`, sempre cópia patchada.
  # -------------------------------------------------------------------------
  SABROOT="$tmp/sabotado"; mkdir -p "$SABROOT/bin" "$SABROOT/lib"
  cp "$BIN" "$SABROOT/bin/maestro"; chmod +x "$SABROOT/bin/maestro"
  ln -s "$REPO/hooks" "$SABROOT/hooks"
  ln -s "$REPO/agents" "$SABROOT/agents" 2>/dev/null || :
  ln -s "$REPO/bin/maestro-wtree" "$SABROOT/bin/maestro-wtree"
  cp "$REPO"/lib/*.sh "$SABROOT/lib/"
  SABCORE="$SABROOT/lib/core-order-state.sh"
  # inverte -n para -z: o campo deferred_by NÃO-VAZIO deixa de ativar 'adiada'
  # (volta a cair no fluxo velho de branch/evidência — o bug original).
  sed -i "s/\[\[ -n \"\$(_order_field \"\$f\" deferred_by)\" \]\]/[[ -z \"\$(_order_field \"\$f\" deferred_by)\" ]]/" "$SABCORE"
  if ! grep -qF '[[ -z "$(_order_field "$f" deferred_by)" ]]' "$SABCORE"; then
    bad "(g) sabotagem não pegou (padrão do sed não bateu — mecanismo mudou de forma?)"
  else
    SAB="$SABROOT/bin/maestro"
    OUT_SAB=$("$SAB" order --status 1 --project "$P" 2>&1)
    if grep -q 'VENCIDA' <<<"$OUT_SAB"; then
      ok "(g) sabotado: a MESMA asserção de (c) REPROVA (voltou a VENCIDA) — o teste tem dente ($OUT_SAB)"
    else
      bad "(g) sabotagem não quebrou nada — a asserção passaria mesmo com o mecanismo invertido ($OUT_SAB)"
    fi
  fi
fi

exit $fail
