#!/usr/bin/env bash
# tests/hooks/test-order-038-rodada-corrente.sh — ordem 038: o detector de
# aguardo olha a RODADA CORRENTE, não 8 KB de transcrito.
#
# A janela do fallback é de BYTES (`tail -c 8192`) e cobre muitas rodadas:
# qualquer ocorrência antiga da linha canônica — de outra rodada, de uma
# citação do humano, de um relato que descreva o mecanismo — re-disparava o
# Stop. A rodada corrente é a ÚLTIMA mensagem do ASSISTENTE no JSONL.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO/hooks/gate-report.sh"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# Igual à 029: a canônica é MONTADA, nunca escrita literal — um teste que a
# transcreve vira gatilho de si mesmo quando o próprio arquivo passa pelo
# tail de um transcrito.
LB='['; RB=']'
CANON="${LB}spock${RB} aguardando:"

command -v python3 >/dev/null 2>&1 || { echo "ok   (sem python3: fixtures puladas)"; exit 0; }
sock="$tmp/mcp.sock"
python3 - "$sock" <<'PY' 2>/dev/null || { echo "ok   (socket indisponível: fixtures puladas)"; exit 0; }
import socket,sys
s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])
PY

# transcrito <arquivo> <papel:texto>... — uma mensagem JSONL por argumento
transcrito() {
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json,sys
out=sys.argv[1]; linhas=[]
for arg in sys.argv[2:]:
    papel, texto = arg.split(":", 1)
    if papel == "meta":
        linhas.append(json.dumps({"type": "last-prompt", "value": texto}, separators=(",", ":")))
    else:
        linhas.append(json.dumps({"type": papel,
                                  "message": {"role": papel,
                                              "content": [{"type": "text", "text": texto}]}},
                                 separators=(",", ":")))
open(out, "w").write("\n".join(linhas) + "\n")
PY
}

# stop <arquivo-de-transcrito> → stdout do hook (payload SEM a linha, para
# forçar o caminho do transcrito, que é o que esta ordem conserta)
stop() {
  local h; h=$(mktemp -d "$tmp/h.XXXXXX")
  printf '{"session_id":"s038","stop_hook_active":false,"transcript_path":"%s"}' "$1" \
    | MAESTRO_HOME="$h" CLAUDE_PROJECT_DIR="$tmp/proj" PONTE_MCP_SOCKET="$sock" \
      bash "$GATE" 2>/dev/null
}
mkdir -p "$tmp/proj"
enche() { printf 'Terminei e relatei. Nada pendente nesta rodada. %s' "$(printf 'x%.0s' {1..200})"; }

echo "-- 038/1: canônica numa rodada ANTIGA, rodada corrente limpa → NÃO bloqueia"
t1="$tmp/antiga.jsonl"
transcrito "$t1" "user:faz a coisa" "assistant:Feito.

$CANON posso seguir com a ordem 12?" \
  "user:continua" "assistant:$(enche)" "user:e depois" "assistant:$(enche)" \
  "user:mais" "assistant:$(enche)"
out=$(stop "$t1")
if grep -q '"decision":"block"' <<<"$out"; then
  bad "038/1: bloqueou por ocorrência de rodada ANTIGA (o defeito da ordem)"
else
  ok "038/1: ocorrência antiga não dispara — a janela deixou de ser de bytes"
fi

echo "-- 038/2: canônica na rodada CORRENTE → bloqueia (não-regressão da 029)"
t2="$tmp/corrente.jsonl"
transcrito "$t2" "user:faz" "assistant:ok" "user:e agora" "assistant:Fiz.

$CANON aplico no main?"
out=$(stop "$t2")
if grep -q 'linha canonica de aguardo' <<<"$out"; then
  ok "038/2: canônica na rodada corrente segura a rodada"
else
  bad "038/2: canônica corrente NÃO segurou ($out)"
fi

echo "-- 038/3: paráfrase na rodada corrente → reprova (caminho 1 da 029)"
t3="$tmp/parafrase.jsonl"
transcrito "$t3" "user:faz" "assistant:ok" "user:e agora" "assistant:Fiz. Fico aguardando sua decisao: aplico no main?"
out=$(stop "$t3")
if grep -q 'SEM a linha canonica' <<<"$out"; then
  ok "038/3: paráfrase ainda é reprovada com instrução de reescrever"
else
  bad "038/3: paráfrase deixou de reprovar ($out)"
fi

echo "-- 038/4: canônica só numa mensagem do USUÁRIO → não bloqueia"
t4="$tmp/usuario.jsonl"
transcrito "$t4" "user:repete a linha $CANON isso aqui é citação" \
  "assistant:Entendi — não há pergunta minha. Segui e terminei."
out=$(stop "$t4")
if grep -q '"decision":"block"' <<<"$out"; then
  bad "038/4: citação do humano disparou o hook"
else
  ok "038/4: mensagem de usuário não dispara — só o assistente fala pelo gerente"
fi

echo "-- 038/5: sem linha de assistente na janela → não bloqueia (degrada honesto)"
t5="$tmp/sem-assistente.jsonl"
transcrito "$t5" "user:oi" "meta:x"
out=$(stop "$t5")
if grep -q '"decision":"block"' <<<"$out"; then
  bad "038/5: bloqueou sem ter rodada de assistente para julgar"
else
  ok "038/5: sem assistente na janela, não afirma pergunta pendente"
fi

echo "-- 038/6: latência do caminho do transcrito, pelo instrumento da 016"
# NADA de teto cravado à mão: a ordem 016 já resolveu medir latência nesta
# forge compartilhada — sonda de baseline, teto com folga quando a carga está
# acima do limiar, e "inconclusivo sob carga" em vez de FAIL quando há carga
# para culpar. Reusar é o ponto; um 50ms cravado aqui mediria o vizinho.
# shellcheck source=tests/lib/latency.sh
. "$REPO/tests/lib/latency.sh"

t6="$tmp/grande.jsonl"
args=("user:inicio" "assistant:$CANON pergunta velha")
for i in $(seq 1 40); do args+=("user:r$i" "assistant:$(enche)"); done
transcrito "$t6" "${args[@]}"
payload="$tmp/payload-038.json"
printf '{"session_id":"s038perf","stop_hook_active":false,"transcript_path":"%s"}' "$t6" > "$payload"

h6=$(mktemp -d "$tmp/h.XXXXXX")
export MAESTRO_HOME="$h6" CLAUDE_PROJECT_DIR="$tmp/proj" PONTE_MCP_SOCKET="$sock"
maestro_latency_read_load
maestro_latency_probe "$GATE"
maestro_latency_measure "$GATE" "$payload"
maestro_latency_report "transcrito-16KB" "$MIN" "$MED" "$MAX" 50
case "$MAESTRO_LATENCY_VERDICT" in
  ok) ok "038/6: mediana ${MED}ms < teto ${MAESTRO_LATENCY_TETO}ms [$MAESTRO_LATENCY_TETO_MOTIVO]" ;;
  inconclusivo)
    echo "INCONCLUSIVO sob carga — 038/6 (mediana ${MED}ms >= teto ${MAESTRO_LATENCY_TETO}ms; load ${MAESTRO_LATENCY_LOAD1M}/${MAESTRO_LATENCY_NCPU} CPUs — não conta como falha)" ;;
  fail) bad "038/6: regressão de latência (mediana ${MED}ms >= teto ${MAESTRO_LATENCY_TETO}ms; load ${MAESTRO_LATENCY_LOAD1M}/${MAESTRO_LATENCY_NCPU} CPUs — sem carga para culpar)" ;;
esac

exit $fail
