#!/usr/bin/env bash
# Ordem 020 (INTENT v3, terceira rodada — 2026-09-17) — a VOLTA por MCP é NO
# STOP, no MESMO turno: hooks/gate-report.sh grava o arquivo de gate IGUAL A
# SEMPRE e, quando (a) há gate pendente, (b) o socket da Ponte existe e (c) a
# última rodada terminou com `[spock] aguardando:`, imprime
# `{"decision":"block","reason":"…"}` no stdout real. O formato do JSON e o
# campo `stop_hook_active` vêm de fora deste repo (documentação/ecossistema
# do Claude Code — ver o comentário de cabeçalho de hooks/gate-report.sh para
# os caminhos exatos); NENHUM hook deste repo usava `decision` antes desta
# ordem. O hook NUNCA espera: decide e sai.
#
# A PROVA PRINCIPAL desta suíte é o NÃO-LAÇO — não o socket ausente (que
# continua obrigatório, mas é o segundo). `stop_hook_active` é suposição
# sobre a plataforma: se o campo sumir, mudar de nome ou vier truncado, a
# rede baseada nele sozinha bloquearia TODA VEZ (reentry=0 é o default
# seguro para "não reconheço o campo"). Por isso há uma SEGUNDA rede,
# independente: um marcador com TTL de 40min por sessão+gate
# ($MAESTRO_HOME/herdr/mcp-asked/<sid>_<gate>). Os três casos abaixo são
# medidos, não assumidos:
#   1. stop_hook_active=true         → não bloqueia (rede 1)
#   2. stop_hook_active AUSENTE      → bloqueia na 1ª vez, NÃO bloqueia na 2ª
#                                       (rede 2 sozinha, sem rede 1 nenhuma)
#   3. stop_hook_active=false, novo  → bloqueia (primeira parada legítima)
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
STOP="$REPO/hooks/gate-report.sh"
SANDBOX=$(mktemp -d)
trap '[[ $$ == $BASHPID ]] && rm -rf "$SANDBOX"' EXIT

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

# stop <sid> <last_assistant_message-or-empty> <reentry-field: "true"|"false"|"absent"> [transcript_path]
stop() {
  local sid="$1" lam="$2" reentry="$3" tp="${4:-}" payload
  local reentry_field=""
  [[ "$reentry" != "absent" ]] && reentry_field=",\"stop_hook_active\":$reentry"
  if [[ -n "$tp" ]]; then
    payload=$(printf '{"session_id":"%s","transcript_path":"%s"%s}' "$sid" "$tp" "$reentry_field")
  else
    payload=$(printf '{"session_id":"%s","last_assistant_message":"%s"%s}' "$sid" "$lam" "$reentry_field")
  fi
  printf '%s' "$payload" \
    | env MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 HERDR_BIN_PATH="$FAKE" \
      CLAUDE_PROJECT_DIR="$SANDBOX/NetForge" PONTE_MCP_SOCKET="${PONTE_MCP_SOCKET_OVERRIDE:-$SANDBOX/no-such-socket}" \
      MCP_PRUNE_SAMPLE_RATE="${MCP_PRUNE_SAMPLE_RATE_OVERRIDE:-1}" \
      bash "$STOP" >"$SANDBOX/out" 2>"$SANDBOX/err"
  RC=$?; OUT=$(cat "$SANDBOX/out")
}
gate_file() { printf '%s/herdr/gates/w9_p9' "$H"; }
gv() { sed -n "s/^$1=\(.*\)$/\1/p" "$(gate_file)" 2>/dev/null | head -1; }
is_block() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d.get('decision')=='block' else 1)" "$1" 2>/dev/null; }

mkdir -p "$SANDBOX/NetForge"
SOCK="$SANDBOX/mcp.sock"; : > "$SOCK"   # "socket existe" — checagem é -e, não -S (E24/I-1, sem daemon real no teste)

echo "== PROVA PRINCIPAL: NÃO-LAÇO, os três casos de stop_hook_active =="

echo "-- caso 1: stop_hook_active=true -> reentrada confirmada, NAO bloqueia"
next_home
record s1 feature "essencia: k; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s1 'pronto\n[spock] aguardando: aprovacao' true
chk "exit 0" "$RC" "0"
chk "reentrada confirmada: sem bloqueio" "$OUT" ""

echo "-- caso 2: stop_hook_active AUSENTE do payload — a prova de que a rede 2 sozinha basta"
next_home
record s2 feature "essencia: k; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s2 'pronto\n[spock] aguardando: aprovacao' absent
chk "1a chamada, campo ausente: exit 0" "$RC" "0"
is_block "$OUT" && ok "1a chamada, campo ausente: BLOQUEIA (episodio novo)" || bad "1a chamada nao bloqueou: $OUT"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s2 'ainda aqui\n[spock] aguardando: aprovacao' absent
chk "2a chamada, campo ausente: exit 0" "$RC" "0"
chk "2a chamada, campo ausente: SEM bloqueio (rede 2, TTL por sessao+gate)" "$OUT" ""

echo "-- caso 3: stop_hook_active=false, sessao/gate novos -> bloqueia (primeira parada legitima)"
next_home
record s3 feature "essencia: k; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s3 'pronto\n[spock] aguardando: aprovacao' false
chk "exit 0" "$RC" "0"
is_block "$OUT" && ok "primeira parada legitima: bloqueia" || bad "nao bloqueou: $OUT"

echo "-- o marcador é por sessão+gate: um NÃO suprime o outro"
next_home
record s4 ship "essencia: v2"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s4 'pronto\n[spock] aguardando: shipa?' absent
is_block "$OUT" && ok "gate ship, 1a vez: bloqueia" || bad "gate ship nao bloqueou: $OUT"
# muda o record para 'plan' pendente na MESMA sessão — chave de marcador diferente
record s4 feature "essencia: v2; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s4 'pronto\n[spock] aguardando: aprova o plano?' absent
is_block "$OUT" && ok "gate plan, mesma sessao, 1a vez: TAMBEM bloqueia (chave diferente)" || bad "gate plan nao bloqueou: $OUT"

echo "-- gate resolvido limpa o marcador: uma pergunta NOVA (mesma sessão) volta a poder bloquear"
next_home
record s5 feature "essencia: k; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s5 'pronto\n[spock] aguardando: aprovacao' absent
is_block "$OUT" && ok "1a pergunta: bloqueia" || bad "1a pergunta nao bloqueou: $OUT"
record s5 feature "essencia: k; approach: lib bash"   # resolvido
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s5 'segui em frente' absent
chk "gate resolvido: arquivo de gate some" "$( [[ -e "$(gate_file)" ]] && echo existe || echo sumiu )" "sumiu"
record s5 feature "essencia: k2; approach: pendente"  # nova rodada pendente
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s5 'pronto de novo\n[spock] aguardando: aprovacao do novo plano' absent
is_block "$OUT" && ok "gate resolvido e reaberto: volta a bloquear (marcador foi limpo)" || bad "nao bloqueou depois de reabrir: $OUT"

echo
echo "== PRUNE: 9 sessões × N gates não acumulam (correção do diretor) =="
next_home
mkdir -p "$H/herdr/mcp-asked"
OLD=$(( $(date +%s) - 3000 ))   # 3000s > ASK_TTL (2400s) — vencido de sobra
# 9 sessões "abandonadas", 2 gates cada (plan+ship) = 18 marcadores vencidos
for i in $(seq 1 9); do
  touch -d "@$OLD" "$H/herdr/mcp-asked/abandoned${i}_plan"
  touch -d "@$OLD" "$H/herdr/mcp-asked/abandoned${i}_ship"
done
# um marcador FRESCO (dentro do TTL) — tem que sobreviver ao prune
touch "$H/herdr/mcp-asked/fresh_plan"
# um arquivo de nome que NÃO bate o padrão <sid>_<gate>, vencido — prova de
# que o prune não apaga por padrão de mtime sozinho, só o que valida o nome
touch -d "@$OLD" "$H/herdr/mcp-asked/nao-e-marcador.txt"
BEFORE=$(ls -1 "$H/herdr/mcp-asked" | wc -l)
chk "antes do prune: 20 arquivos no diretório" "$BEFORE" "20"

record acc feature "essencia: k; approach: pendente"
# QUALQUER Stop dentro do herdr aciona o prune — nem precisa ser gate pendente
# desta sessão; testo com uma sessão SEM gate (early exit) de propósito, para
# provar que o prune roda mesmo fora do caminho "gate pendente".
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop acc 'nada pendente por aqui' absent
AFTER=$(ls -1 "$H/herdr/mcp-asked" | wc -l)
chk "depois de UM Stop (sessão sem gate nenhum): 18 vencidos somem, 2 ficam" "$AFTER" "2"
[[ -f "$H/herdr/mcp-asked/fresh_plan" ]] && ok "o marcador fresco sobrevive" || bad "o marcador fresco foi apagado — prune matou coisa viva"
[[ -f "$H/herdr/mcp-asked/nao-e-marcador.txt" ]] && ok "arquivo de nome fora do padrão sobrevive (mtime vencido não basta)" || bad "prune apagou por nome fora do padrão — delimitação furou"
for i in $(seq 1 9); do
  [[ -f "$H/herdr/mcp-asked/abandoned${i}_plan" || -f "$H/herdr/mcp-asked/abandoned${i}_ship" ]] && bad "sobrou marcador da sessão abandonada $i"
done
ok "nenhum dos 9×2 marcadores abandonados sobrou — não acumula"

echo
echo "== AMOSTRAGEM 1 em 10 do prune (correção do diretor, quinta rodada) =="
echo "-- 18 arquivos ainda passa de 50ms mesmo com rm batelado + regex sem {1,N}; decisão gravada no comentário do hook --"
next_home
record acc feature "essencia: k; approach: pendente"
mkdir -p "$H/herdr/mcp-asked"
touch -d "@$OLD" "$H/herdr/mcp-asked/stale_plan"
# chamada direta (não por stop(), que força MCP_PRUNE_SAMPLE_RATE=1) — a
# taxa DEFAULT (10) é determinística por contador em arquivo, não $RANDOM
# ($RANDOM não é seedável de fora do processo — testado à mão antes de
# escolher o contador). Nove chamadas não devem prunar; a décima, sim.
# Precisa de gate pendente (achado da quarta rodada: prune só roda dentro do
# caminho "gate pendente", para não criar $MAESTRO_HOME/herdr/ em payload de
# lixo/sem record — ver o comentário do hook).
for i in $(seq 1 9); do
  printf '{"session_id":"acc","last_assistant_message":"sem pendencia"}' \
    | env MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 HERDR_BIN_PATH="$FAKE" \
      PONTE_MCP_SOCKET="$SANDBOX/no-such-socket" bash "$STOP" >/dev/null 2>&1
done
[[ -f "$H/herdr/mcp-asked/stale_plan" ]] && ok "9 chamadas com a taxa default (10): ainda não prunou" || bad "prunou antes da 10a chamada — amostragem errada"
printf '{"session_id":"acc","last_assistant_message":"sem pendencia"}' \
  | env MAESTRO_HOME="$H" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 HERDR_BIN_PATH="$FAKE" \
    PONTE_MCP_SOCKET="$SANDBOX/no-such-socket" bash "$STOP" >/dev/null 2>&1
[[ -f "$H/herdr/mcp-asked/stale_plan" ]] && bad "10a chamada não prunou" || ok "10a chamada: prunou (contador determinístico, sem flake)"

echo
echo "== O SEGUNDO TESTE MAIS IMPORTANTE: socket ausente, mesmo com a linha presente =="
next_home
record s6 feature "essencia: auto-update; impacto: x; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SANDBOX/no-such-socket" stop s6 'pronto\n[spock] aguardando: aprovacao do plano X' false
chk "exit 0" "$RC" "0"
chk "stdout vazio: SEM bloqueio sem socket" "$OUT" ""
chk "gate ainda escrito (comportamento de hoje)" "$(gv gate)" "plan"
[[ -f "$SANDBOX/no-such-socket" ]] && bad "criou o socket sozinho" || ok "socket continua ausente (nada foi inventado)"

echo
echo "== o resto do gatilho =="

echo "-- sem a linha [spock] aguardando:, mesmo com socket vivo"
next_home
record s7 feature "essencia: k; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s7 'terminei por aqui, sem pendencia nenhuma' false
chk "exit 0" "$RC" "0"
chk "stdout vazio: SEM bloqueio sem a linha" "$OUT" ""

echo "-- com socket E com a linha: o conteudo do JSON de bloqueio"
next_home
record s8 feature "essencia: k; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s8 'rodada concluida\n[spock] aguardando: aprovacao do plano' false
chk "gate ainda escrito (efeito de hoje continua)" "$(gv gate)" "plan"
case "$OUT" in
  *director.ask*director.wait*) ok "reason cita director.ask e director.wait, nessa ordem" ;;
  *) bad "reason nao cita as duas tools na ordem certa: $OUT" ;;
esac
case "$OUT" in
  *"30 min"*) ok "reason cita o teto de 30 min" ;;
  *) bad "reason sem o teto de 30 min: $OUT" ;;
esac
case "$OUT" in
  *desfecho*) ok "reason manda dizer o desfecho (nunca silencio)" ;;
  *) bad "reason nao cobra desfecho dito: $OUT" ;;
esac
case "$OUT" in
  *"Aprovo o plano"*|*"essencia: k"*) bad "reason vazou message/essencia do gate: $OUT" ;;
  *) ok "reason nao cita message/essencia do gate (texto fixo)" ;;
esac

echo "-- fallback: sem last_assistant_message no payload, olha o transcript_path"
next_home
record s9 feature "essencia: k; approach: pendente"
TP="$SANDBOX/transcript-s9.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"pronto\\n[spock] aguardando: aprovacao"}]}}\n' > "$TP"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s9 "" false "$TP"
is_block "$OUT" && ok "fallback do transcript tambem bloqueia" || bad "fallback do transcript nao bloqueou: $OUT"

echo "-- transcript_path ausente/ilegivel, sem last_assistant_message: nunca bloqueia"
next_home
record s10 feature "essencia: k; approach: pendente"
PONTE_MCP_SOCKET_OVERRIDE="$SOCK" stop s10 "" false "$SANDBOX/nao-existe.jsonl"
chk "exit 0" "$RC" "0"
chk "sem fonte legivel da linha: sem bloqueio" "$OUT" ""

echo "-- fora do herdr: continua no-op absoluto"
next_home; record s11 feature "essencia: k; approach: pendente"
printf '{"session_id":"s11","last_assistant_message":"[spock] aguardando: x"}' \
  | MAESTRO_HOME="$H" HERDR_ENV=0 HERDR_BIN_PATH="$FAKE" PONTE_MCP_SOCKET="$SOCK" bash "$STOP" >"$SANDBOX/out" 2>&1
chk "fora do herdr: exit 0" "$?" "0"
chk "fora do herdr: stdout vazio" "$(cat "$SANDBOX/out")" ""

echo
if [[ $fail -eq 0 ]]; then echo "test-order-020-mcp-ask: OK"; else echo "test-order-020-mcp-ask: FALHOU"; fi
exit $fail
