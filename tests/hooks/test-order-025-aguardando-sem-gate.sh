#!/usr/bin/env bash
# Ordem 025 (INTENT v3, correção de 2026-09-18) — o gatilho da Ponte MCP sobe
# para ANTES do `exit 0` de "sem gate" em hooks/gate-report.sh e passa a
# valer para TODA rodada que termina com `[spock] aguardando:`, não só
# quando há gate humano pendente (feature/refactor com approach pendente, ou
# ship sem desfecho). A ordem 020 entregou o mecanismo com o gatilho 135
# linhas DEPOIS do `exit 0` — nunca disparava fora do gate, e a maioria dos
# workflows (fix, custom, audit, verify, codereview) nunca abre gate.
#
# Esta suíte cobre só o caminho NOVO (sem gate); o caminho COM gate pendente
# continua coberto, sem alteração de comportamento, por
# tests/hooks/test-order-020-mcp-ask.sh (regressão: roda igual, sem editar).
#
# PROVA DAS DUAS PONTAS (primeira seção): a mesma rodada roda contra o hook
# de `main` (a causa medida na ordem 025 — sai no `:145` sem olhar a linha) e
# contra o hook patchado deste worktree. Se `main` não existir localmente
# (worktree isolado, sem fetch), cai para uma cópia do HEAD do worktree
# ANTES do patch (git show HEAD:hooks/gate-report.sh) — o commit desta
# branch nunca altera hooks/gate-report.sh diretamente (contrato de entrega:
# patch em docs/patches/), então HEAD:hooks/gate-report.sh é sempre a mesma
# base pré-025.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PATCHED="$REPO/hooks/gate-report.sh"
SANDBOX=$(mktemp -d)
trap '[[ $$ == $BASHPID ]] && rm -rf "$SANDBOX"' EXIT

BASELINE="$SANDBOX/gate-report-baseline.sh"
if ! git -C "$REPO" show main:hooks/gate-report.sh > "$BASELINE" 2>/dev/null; then
  git -C "$REPO" show HEAD:hooks/gate-report.sh > "$BASELINE" 2>/dev/null
fi
[[ -s "$BASELINE" ]] || { echo "SKIP: sem base pré-025 para comparar (nem main, nem HEAD)"; exit 0; }
chmod +x "$BASELINE"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

FAKE="$SANDBOX/herdr"; CALLS="$SANDBOX/calls.log"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$CALLS" > "$FAKE"; chmod +x "$FAKE"

n=0; next_home() { n=$((n+1)); H="$SANDBOX/home$n"; mkdir -p "$H/sessions" "$H/logs"; }
record() { # record <sid> <workflow> <brief>
  printf '{"session_id":"%s","ts":"2026-09-02T00:00:00-03:00","expires_at":"2099-01-01T00:00:00-03:00","workflow":"%s","mode":"direct","reason":"segredo","brief":"%s"}\n' "$1" "$2" "$3" > "$H/sessions/$1.json"
}
# stop <hook> <sid> <last_assistant_message> <reentry: true|false|absent>
stop() {
  local hook="$1" sid="$2" lam="$3" reentry="$4" reentry_field=""
  [[ "$reentry" != "absent" ]] && reentry_field=",\"stop_hook_active\":$reentry"
  printf '{"session_id":"%s","last_assistant_message":"%s"%s}' "$sid" "$lam" "$reentry_field" \
    | env MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 HERDR_BIN_PATH="$FAKE" \
      CLAUDE_PROJECT_DIR="$SANDBOX/NetForge" PONTE_MCP_SOCKET="${PONTE_MCP_SOCKET_OVERRIDE:-$SANDBOX/no-such-socket}" \
      MCP_PRUNE_SAMPLE_RATE="${MCP_PRUNE_SAMPLE_RATE_OVERRIDE:-1}" \
      bash "$hook" >"$SANDBOX/out" 2>"$SANDBOX/err"
  RC=$?; OUT=$(cat "$SANDBOX/out")
}
is_block() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d.get('decision')=='block' else 1)" "$1" 2>/dev/null; }
gate_file() { printf '%s/herdr/gates/w9_p9' "$H"; }
marker() { printf '%s/herdr/mcp-asked/%s_%s' "$H" "$1" "$2"; }

mkdir -p "$SANDBOX/NetForge"
SOCK="$SANDBOX/mcp.sock"; : > "$SOCK"   # "socket existe" — checagem é -e (E24/I-1)

echo "== AS DUAS PONTAS: rodada SEM gate, com a linha e com socket =="

echo "-- PONTA 1: hoje (hook pré-025) NÃO dispara — a causa medida (sai no :145)"
next_home
record s1 fix "essencia: bug qualquer"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$BASELINE" s1 'terminei\n[spock] aguardando: qual das duas' absent
chk "baseline: exit 0" "$RC" "0"
chk "baseline: NAO bloqueia (fix nunca abre gate; gatilho fica 135 linhas depois do exit)" "$OUT" ""
[[ -e "$(gate_file)" ]] && bad "baseline escreveu gate para workflow fix" || ok "baseline: sem gate (comportamento de hoje)"

echo "-- PONTA 2: patchado DISPARA — o gatilho subiu para antes do exit 0"
next_home
record s1 fix "essencia: bug qualquer"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s1 'terminei\n[spock] aguardando: qual das duas' absent
chk "patchado: exit 0" "$RC" "0"
is_block "$OUT" && ok "patchado: BLOQUEIA (a mudança da 025)" || bad "patchado nao bloqueou: $OUT"
[[ -e "$(gate_file)" ]] && bad "patchado escreveu gate para workflow fix (nao deveria)" || ok "patchado: sem gate escrito, só a decisão MCP"
case "$OUT" in
  *director.ask*director.wait*) ok "reason cita director.ask e director.wait" ;;
  *) bad "reason nao cita as tools: $OUT" ;;
esac
case "$OUT" in
  *"Aprovo o plano"*|*"essencia:"*|*segredo*) bad "reason vazou texto do gate/record: $OUT" ;;
  *) ok "reason nao vaza gate/record (texto fixo, generico)" ;;
esac

echo
echo "== sem a linha, ou sem socket: nada dispara, sessão termina normal =="

echo "-- sem a linha [spock] aguardando:, com socket vivo"
next_home
record s2 custom "essencia: k"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s2 'terminei sem pendencia nenhuma' absent
chk "exit 0" "$RC" "0"
chk "sem a linha: sem bloqueio" "$OUT" ""

echo "-- com a linha, SEM socket"
next_home
record s3 audit "essencia: k"
PONTE_MCP_SOCKET_OVERRIDE="$SANDBOX/no-such-socket" stop "$PATCHED" s3 'pronto\n[spock] aguardando: decisao' absent
chk "exit 0" "$RC" "0"
chk "sem socket: sem bloqueio" "$OUT" ""
[[ -f "$SANDBOX/no-such-socket" ]] && bad "criou o socket sozinho" || ok "socket continua ausente"

echo
echo "== NÃO-LAÇO no caminho sem gate: os três casos de stop_hook_active =="

echo "-- stop_hook_active=true: reentrada confirmada, NAO bloqueia"
next_home
record s4 verify "essencia: k"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s4 'pronto\n[spock] aguardando: aprovacao' true
chk "exit 0" "$RC" "0"
chk "reentrada: sem bloqueio" "$OUT" ""

echo "-- stop_hook_active AUSENTE: 1a chamada bloqueia, 2a (mesma pergunta) nao — rede 2 sozinha"
next_home
record s5 codereview "essencia: k"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s5 'pronto\n[spock] aguardando: qual abordagem' absent
is_block "$OUT" && ok "1a chamada, campo ausente: BLOQUEIA" || bad "1a chamada nao bloqueou: $OUT"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s5 'ainda pensando\n[spock] aguardando: qual abordagem' absent
chk "2a chamada, mesma pergunta: SEM bloqueio (TTL por sessao+aviso)" "$OUT" ""

echo "-- stop_hook_active=false, sessão nova: bloqueia (primeira parada legítima)"
next_home
record s6 fix "essencia: k"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s6 'pronto\n[spock] aguardando: aprovacao' false
is_block "$OUT" && ok "primeira parada legitima: bloqueia" || bad "nao bloqueou: $OUT"

echo
echo "== DECISÃO da ordem 025 (armadilha 2): sem evento de resolução, o marcador"
echo "   de aviso limpa quando a rodada SEGUINTE não repete a linha =="
next_home
record s7 fix "essencia: k"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s7 'pronto\n[spock] aguardando: pergunta 1' absent
is_block "$OUT" && ok "pergunta 1: bloqueia" || bad "pergunta 1 nao bloqueou: $OUT"
[[ -f "$(marker s7 aviso)" ]] && ok "marcador aviso existe apos a pergunta 1" || bad "marcador aviso nao foi criado"
# rodada seguinte SEM a linha — resolvida (por MCP, no mesmo turno do gerente)
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s7 'segui em frente, sem pendencia' absent
chk "rodada sem a linha: sem bloqueio" "$OUT" ""
[[ -f "$(marker s7 aviso)" ]] && bad "marcador aviso sobreviveu a rodada resolvida" || ok "marcador aviso limpo (nao precisa esperar o TTL de 40min)"
# pergunta NOVA na mesma sessão, imediatamente depois — não deveria esperar TTL
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" s7 'nova rodada\n[spock] aguardando: pergunta 2' absent
is_block "$OUT" && ok "pergunta 2, mesma sessao, sem esperar TTL: bloqueia de novo" || bad "pergunta 2 nao bloqueou (ficou preso no TTL): $OUT"

echo
echo "== ACÚMULO: 9 sessões × 3 chaves (plan, ship, aviso) não acumulam =="
next_home
mkdir -p "$H/herdr/mcp-asked"
OLD=$(( $(date +%s) - 3000 ))   # 3000s > ASK_TTL (2400s), vencido de sobra
for i in $(seq 1 9); do
  touch -d "@$OLD" "$H/herdr/mcp-asked/abandoned${i}_plan"
  touch -d "@$OLD" "$H/herdr/mcp-asked/abandoned${i}_ship"
  touch -d "@$OLD" "$H/herdr/mcp-asked/abandoned${i}_aviso"
done
touch "$H/herdr/mcp-asked/fresh_aviso"           # dentro do TTL — tem que sobreviver
touch -d "@$OLD" "$H/herdr/mcp-asked/nao-e-marcador.txt"  # nome fora do padrão
BEFORE=$(ls -1 "$H/herdr/mcp-asked" | wc -l)
chk "antes do prune: 29 arquivos" "$BEFORE" "29"

# sessão SEM gate, mas com a linha + socket — é o ÚNICO ponto que aciona o
# prune no caminho novo (mesma regra de sempre: só quando já ia escrever de
# qualquer forma, aqui porque vai escrever o marcador "_aviso" da própria
# sessão "acc")
record acc fix "essencia: k"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop "$PATCHED" acc 'pronto\n[spock] aguardando: pergunta da acc' absent
AFTER=$(ls -1 "$H/herdr/mcp-asked" | wc -l)
# 27 vencidos somem (9x3), sobra fresh_aviso + nao-e-marcador.txt + acc_aviso (novo)
chk "depois de UM Stop sem gate (com pergunta nova): 27 vencidos somem, 3 ficam" "$AFTER" "3"
[[ -f "$H/herdr/mcp-asked/fresh_aviso" ]] && ok "marcador aviso fresco sobrevive" || bad "prune matou marcador aviso vivo"
[[ -f "$H/herdr/mcp-asked/nao-e-marcador.txt" ]] && ok "nome fora do padrão sobrevive" || bad "prune apagou por nome fora do padrão"
[[ -f "$H/herdr/mcp-asked/acc_aviso" ]] && ok "marcador novo da propria pergunta existe" || bad "marcador novo nao foi criado"
for i in $(seq 1 9); do
  [[ -f "$H/herdr/mcp-asked/abandoned${i}_plan" || -f "$H/herdr/mcp-asked/abandoned${i}_ship" || -f "$H/herdr/mcp-asked/abandoned${i}_aviso" ]] \
    && bad "sobrou marcador da sessao abandonada $i"
done
ok "nenhum dos 9×3 marcadores abandonados sobrou — sufixo aviso podado igual plan/ship"

echo
echo "== fora do herdr: continua no-op absoluto =="
next_home; record s8 fix "essencia: k"
printf '{"session_id":"s8","last_assistant_message":"[spock] aguardando: x"}' \
  | MAESTRO_HOME="$H" HERDR_ENV=0 HERDR_BIN_PATH="$FAKE" PONTE_MCP_SOCKET="$SOCK" bash "$PATCHED" >"$SANDBOX/out" 2>&1
chk "fora do herdr: exit 0" "$?" "0"
chk "fora do herdr: stdout vazio" "$(cat "$SANDBOX/out")" ""

echo
if [[ $fail -eq 0 ]]; then echo "test-order-025-aguardando-sem-gate: OK"; else echo "test-order-025-aguardando-sem-gate: FALHOU"; fi
exit $fail
