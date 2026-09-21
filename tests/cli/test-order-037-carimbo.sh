#!/usr/bin/env bash
# ordem 037 — arquivo sem carimbo vira ordem no --status: 10# em id vazio
# quebrava a saída. Arquivo PRÓPRIO (não em test-order.sh, que já está em
# 399/400 linhas) — mesmo motivo de tests/cli/test-order-issue13.sh.
#
# Causa-raiz (achada e provada na ordem 037, não refeita aqui): `--status`/
# `--accept` resolviam o arquivo por glob de id (lib/cmd-order.sh) sem aplicar
# `_order_valid_stamp` — a mesma guarda que `--list` já usa (issue #13). Um
# .md sem o carimbo `<!-- maestro-order v1 … id: …` faz `_order_field … id`
# devolver VAZIO, e `$((10#$id))` em lib/core-order-state.sh estourava
# "invalid integer constant" — erro de bash vazando pro usuário, com o
# estado saindo inventado ("aberta").
#
# Os quatro testes exigidos pela ordem, um bloco cada:
#   1. --status NNN sobre arquivo sem carimbo → mensagem nomeada, rc
#      previsível, zero stderr de bash puro.
#   2. --status N (um dígito) sobre arquivo carimbado (005-*.md) funciona,
#      nas DUAS variantes de rótulo de recibo (S-1802: order-N e order-00N) —
#      a não-regressão que o Capitão pediu por nome.
#   3. --accept sobre arquivo sem carimbo: recusa nomeada, nunca carimba.
#   4. --create com stdin aberto e vazio TERMINA (não pendura).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

P="$tmp/proj"; mkdir -p "$P/.maestro/orders"
git -C "$P" init -q
echo a > "$P/x.txt"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm base

# ---------------------------------------------------------------------------
# fixture: arquivo 005-*.md SEM carimbo — o caso real (repro do Capitão em
# ~/dev/worktrees/app-005-estado): começa direto no corpo, sem
# `<!-- maestro-order v1 … id: … -->`.
# ---------------------------------------------------------------------------
SEMCARIMBO="$P/.maestro/orders/005-estado-sem-carimbo.md"
cat > "$SEMCARIMBO" <<'EOF'
## 1. A causa-raiz

Documento solto — nunca teve o carimbo de ordem. Não é uma ordem.
EOF

# ===========================================================================
# teste 1 — --status sobre arquivo sem carimbo: mensagem nomeada, rc
# previsível, ZERO stderr vindo do bash (nunca "invalid integer constant").
# ===========================================================================
echo "-- teste 1: --status 5 sobre 005-*.md sem carimbo"
OUT1=$(mktemp); ERR1=$(mktemp)
"$BIN" order --status 5 --project "$P" >"$OUT1" 2>"$ERR1"
RC1=$?
chk "teste 1: rc previsível (1, validação)" "$RC1" "1"
if grep -qi 'invalid integer constant\|unbound variable\|: line [0-9]*:' "$ERR1"; then
  bad "teste 1: stderr vazou erro de bash puro ($(cat "$ERR1"))"
else
  ok "teste 1: zero stderr vindo do bash"
fi
if grep -q 'sem carimbo de ordem' "$ERR1"; then
  ok "teste 1: mensagem NOMEADA (mesma linguagem do --list: 'sem carimbo de ordem')"
else
  bad "teste 1: mensagem não usa a linguagem esperada ($(cat "$ERR1"))"
fi
if grep -q "$SEMCARIMBO" "$ERR1"; then
  ok "teste 1: mensagem cita o caminho do arquivo"
else
  bad "teste 1: mensagem não cita o caminho ($(cat "$ERR1"))"
fi
if grep -qi 'aberta' "$OUT1"; then
  bad "teste 1: estado inventado ('aberta') vazou no stdout ($(cat "$OUT1"))"
else
  ok "teste 1: nunca 'aberta' — nenhum estado inventado"
fi
rm -f "$OUT1" "$ERR1"

# ===========================================================================
# teste 2 — ordem de UM DÍGITO com carimbo funciona nas DUAS variantes de
# rótulo de recibo (S-1802: order-N canônico e order-00N acolchoado). Duas
# fixtures independentes para não deixar a segunda "herdar" a prova da
# primeira.
# ===========================================================================
echo "-- teste 2: --status 5 (um dígito) sobre 005-*.md carimbado, S-1802"

# 2a. recibo no formato CANÔNICO (order-5)
P2A="$tmp/proj2a"; mkdir -p "$P2A/.maestro/orders"
git -C "$P2A" init -q
echo a > "$P2A/x.txt"; git -C "$P2A" add -A
git -C "$P2A" -c user.email=t@t -c user.name=t commit -qm base
cat > "$P2A/.maestro/orders/005-com-carimbo.md" <<'EOF'
<!-- maestro-order v1
id: 005
ts: 2026-09-20T00:00:00-03:00
epoch: 1789900000
head: none
author_session: teste-037
-->
# Ordem 005 — com carimbo (S-1802a)

## Objetivo
Ordem carimbada de um dígito — recibo no formato canônico.
EOF
"$BIN" evidence --record --label order-5 --project "$P2A" -- true >/dev/null 2>&1
ST2A=$("$BIN" order --status 5 --project "$P2A" 2>&1)
if grep -q '^ordem 005: provada' <<<"$ST2A"; then
  ok "teste 2a: --status 5 com recibo order-5 (canônico) resolve 'provada'"
else
  bad "teste 2a: não resolveu 'provada' com order-5 ($ST2A)"
fi
if grep -q 'order-5' <<<"$ST2A"; then
  ok "teste 2a: prova cita o rótulo order-5"
else
  bad "teste 2a: prova não cita order-5 ($ST2A)"
fi

# 2b. recibo no formato ACOLCHOADO (order-005) — mesmo id, projeto separado.
P2B="$tmp/proj2b"; mkdir -p "$P2B/.maestro/orders"
git -C "$P2B" init -q
echo a > "$P2B/x.txt"; git -C "$P2B" add -A
git -C "$P2B" -c user.email=t@t -c user.name=t commit -qm base
cat > "$P2B/.maestro/orders/005-com-carimbo.md" <<'EOF'
<!-- maestro-order v1
id: 005
ts: 2026-09-20T00:00:00-03:00
epoch: 1789900000
head: none
author_session: teste-037
-->
# Ordem 005 — com carimbo (S-1802b)

## Objetivo
Ordem carimbada de um dígito — recibo no formato acolchoado.
EOF
"$BIN" evidence --record --label order-005 --project "$P2B" -- true >/dev/null 2>&1
ST2B=$("$BIN" order --status 5 --project "$P2B" 2>&1)
if grep -q '^ordem 005: provada' <<<"$ST2B"; then
  ok "teste 2b: --status 5 com recibo order-005 (acolchoado) resolve 'provada'"
else
  bad "teste 2b: não resolveu 'provada' com order-005 ($ST2B)"
fi
if grep -q 'order-005' <<<"$ST2B"; then
  ok "teste 2b: prova cita o rótulo order-005"
else
  bad "teste 2b: prova não cita order-005 ($ST2B)"
fi

# ===========================================================================
# teste 3 — --accept sobre arquivo sem carimbo: recusa NOMEADA, nunca carimba.
# ===========================================================================
echo "-- teste 3: --accept 5 sobre 005-*.md sem carimbo"
ANTES=$(cat "$SEMCARIMBO")
ERR3=$(mktemp)
"$BIN" order --accept 5 --project "$P" >/dev/null 2>"$ERR3"
RC3=$?
chk "teste 3: rc previsível (1, validação)" "$RC3" "1"
if grep -q 'sem carimbo de ordem' "$ERR3"; then
  ok "teste 3: recusa NOMEADA (mesma linguagem do --list)"
else
  bad "teste 3: recusa sem a linguagem esperada ($(cat "$ERR3"))"
fi
DEPOIS=$(cat "$SEMCARIMBO")
if [[ "$ANTES" == "$DEPOIS" ]]; then
  ok "teste 3: arquivo NUNCA foi carimbado (accepted_at ausente, conteúdo intacto)"
else
  bad "teste 3: arquivo foi alterado pelo --accept recusado"
fi
if grep -q 'accepted_at' "$SEMCARIMBO"; then
  bad "teste 3: accepted_at vazou no arquivo sem carimbo"
else
  ok "teste 3: sem accepted_at — não carimbou aceite"
fi
rm -f "$ERR3"

# ===========================================================================
# teste 4 — --create com stdin aberto e vazio TERMINA. Fifo com escritor que
# mantém a outra ponta aberta SEM mandar byte — reproduz exatamente o hang
# medido (147s em pipe_read). timeout EXTERNO generoso (8s) só reprova se o
# conserto falhar e o processo pendurar; o conserto interno (timeout curto
# sobre o `head -c 16384`) tem de terminar bem antes disso.
# ===========================================================================
echo "-- teste 4: --create com stdin pipe aberto e vazio"
FIFO="$tmp/stdin.fifo"; mkfifo "$FIFO"
( exec sleep 30 > "$FIFO" ) &   # mantém a ponta de escrita aberta, sem escrever nada
WPID=$!
T0=$(date +%s)
timeout 8 "$BIN" order --create --title "Stdin aberto e vazio" \
  --project "$P" --session teste-037-t4 < "$FIFO" >/tmp/.037-t4-out.$$ 2>/tmp/.037-t4-err.$$
RC4=$?
T1=$(date +%s)
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null
OUT4=$(cat /tmp/.037-t4-out.$$); ERR4=$(cat /tmp/.037-t4-err.$$)
rm -f /tmp/.037-t4-out.$$ /tmp/.037-t4-err.$$

if (( RC4 == 124 )); then
  bad "teste 4: pendurou — o timeout EXTERNO (8s) teve de matar o processo"
else
  ok "teste 4: terminou por si só em $((T1 - T0))s (não pendurou)"
fi
chk "teste 4: --create completa com sucesso (stdin vazio é caminho normal)" "$RC4" "0"
if grep -q 'ordem [0-9]* criada' <<<"$OUT4"; then
  ok "teste 4: ordem foi criada mesmo sem corpo via stdin"
else
  bad "teste 4: --create não confirmou criação ($OUT4 / $ERR4)"
fi

# ===========================================================================
# teste 5 — limitar a espera NÃO pode trazer de volta o corte silencioso
# (a lição da 032/issue #43). Três desfechos, três comportamentos:
#   zero byte + sem EOF  → sem corpo, caminho normal   (teste 4, acima)
#   byte lido + sem EOF  → corpo PELA METADE ⇒ RECUSA, nada gravado
#   corpo acima do teto  → RECUSA com os três números, nada gravado
# A primeira versão do conserto usava `head` sob `timeout`, que PERDE o que já
# leu quando é morto: o parcial virava "sem corpo" e a ordem nascia mutilada em
# silêncio. Este teste é o que prende isso.
# ===========================================================================
echo "-- teste 5: corpo parcial e corpo acima do teto são RECUSADOS"
antes=$(ls "$P/.maestro/orders" | wc -l)

FIFO5="$tmp/parcial.fifo"; mkfifo "$FIFO5"
( printf 'metade do corpo'; exec sleep 30 ) > "$FIFO5" &
W5=$!
OUT5=$(timeout 12 "$BIN" order --create --title "Corpo parcial" \
  --project "$P" --session teste-037-t5 < "$FIFO5" 2>&1); RC5=$?
kill "$W5" 2>/dev/null; wait "$W5" 2>/dev/null

chk "teste 5: corpo parcial → rc=1 (recusa, não grava)" "$RC5" "1"
if grep -q 'pela metade' <<<"$OUT5"; then
  ok "teste 5: a recusa DIZ que o corpo veio pela metade"
else
  bad "teste 5: recusa sem nomear o motivo ($OUT5)"
fi
if grep -qE '15 bytes' <<<"$OUT5"; then
  ok "teste 5: a recusa cita quantos bytes chegaram (15)"
else
  bad "teste 5: recusa sem o número de bytes lidos ($OUT5)"
fi

OUT6=$(python3 -c "print('x'*17000)" | "$BIN" order --create --title "Corpo gigante" \
  --project "$P" --session teste-037-t6 2>&1); RC6=$?
chk "teste 5: corpo acima do teto → rc=1" "$RC6" "1"
if grep -q 'excede o teto de 16384' <<<"$OUT6"; then
  ok "teste 5: a recusa cita entrada, teto e excesso"
else
  bad "teste 5: recusa do teto sem os números ($OUT6)"
fi

depois=$(ls "$P/.maestro/orders" | wc -l)
chk "teste 5: NENHUMA ordem foi gravada pelas duas recusas" "$depois" "$antes"

exit $fail
