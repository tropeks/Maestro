#!/usr/bin/env bash
# Blindagem de hooks/lib/common.sh (review Opus P1-1, P1-2, P2-1, P2-2, P2-3).
#
# Cobre: log_event nunca aborta o chamador; validação de chave POR TIPO com
# rejeição (nunca mutilação); chave duplicada; `agents` como array; valor com
# `/` rejeitado; TTL por expires_at e fallback por mtime; rotação; fd 9 fechado.
#
# NUNCA toca ~/.maestro real: todo caso isola MAESTRO_HOME em mktemp -d.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/lib/common.sh"
fail=0
tmproot=$(mktemp -d)
cleanup() { chmod -R u+rwX "$tmproot" 2>/dev/null || true; rm -rf "$tmproot"; }
trap cleanup EXIT

ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }
check(){ if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (esperava '$2', veio '$1')"; fi; }

newhome() { local d; d=$(mktemp -d "$tmproot/home.XXXXXX"); printf '%s' "$d"; }

# Roda um snippet num bash filho com common.sh sourceado (errexit ativo, como
# num hook real). Imprime "<saida>|rc=<rc>".
run() {
  local home="$1" snippet="$2" out rc
  out=$(MAESTRO_HOME="$home" bash -c "source '$LIB'; $snippet" 2>/dev/null); rc=$?
  printf '%s|rc=%s' "$out" "$rc"
}

# ---------------------------------------------------------------------------
echo "-- P1-2: log_event nunca derruba o chamador"
# ---------------------------------------------------------------------------

h=$(newhome)
check "$(run "$h" 'date(){ return 1; }; log_event decision workflow=fix; echo SOBREVIVEU')" \
      "SOBREVIVEU|rc=0" "date falhando nao aborta o chamador"
if [[ -s "$h/logs/routing.jsonl" ]]; then
  ok "linha gravada mesmo com date quebrado"
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$h/logs/routing.jsonl" >/dev/null 2>&1 \
      && ok "JSONL valido com timestamp de fallback" \
      || bad "JSONL invalido com timestamp de fallback"
  fi
else
  bad "linha nao gravada com date quebrado"
fi

h=$(newhome); mkdir -p "$h/logs/routing.jsonl"   # log file é um DIRETÓRIO
check "$(run "$h" 'log_event decision workflow=fix; echo SOBREVIVEU')" \
      "SOBREVIVEU|rc=0" "log file sendo diretorio nao aborta o chamador"

h=$(newhome); chmod 500 "$h"                     # MAESTRO_HOME read-only
check "$(run "$h" 'log_event gate_block tool=Edit; echo SOBREVIVEU')" \
      "SOBREVIVEU|rc=0" "MAESTRO_HOME read-only nao aborta o chamador"
chmod 700 "$h" 2>/dev/null || true

h=$(newhome)
check "$(run "$h" 'log_event evento_que_nao_existe foo=bar; echo SOBREVIVEU')" \
      "SOBREVIVEU|rc=0" "evento fora do vocabulario nao aborta o chamador"

h=$(newhome)
check "$(run "$h" 'log_event; echo SOBREVIVEU')" \
      "SOBREVIVEU|rc=0" "log_event sem argumento nenhum nao aborta"

h=$(newhome)
check "$(run "$h" 'stat(){ return 1; }; mkdir(){ return 1; }; flock(){ return 1; }; log_event decision mode=direct; echo SOBREVIVEU')" \
      "SOBREVIVEU|rc=0" "stat/mkdir/flock quebrados nao abortam o chamador"

h=$(newhome)
check "$(run "$h" 'maestro_ensure_dirs; maestro_rotate_log; maestro_now_epoch >/dev/null; echo SOBREVIVEU')" \
      "SOBREVIVEU|rc=0" "ensure_dirs/rotate_log/now_epoch nao abortam"

h=$(newhome)
epoch=$(MAESTRO_HOME="$h" bash -c "source '$LIB'; date(){ return 1; }; maestro_now_epoch" 2>/dev/null)
[[ "$epoch" =~ ^[0-9]{10,}$ ]] \
  && ok "maestro_now_epoch tem fallback sem date ($epoch)" \
  || bad "maestro_now_epoch sem fallback (veio '$epoch')"

# ---------------------------------------------------------------------------
echo "-- P1-1: validacao por tipo rejeita, nunca mutila"
# ---------------------------------------------------------------------------

h=$(newhome)
err=$(MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event decision Session_ID=abc file2=x workflow=fix" 2>&1 >/dev/null)
line=$(cat "$h/logs/routing.jsonl" 2>/dev/null)
grep -q "ession_" <<<"$line"   && bad "chave mutilada: 'Session_ID' virou 'ession_'" || ok "'Session_ID' rejeitada, nao mutilada"
grep -q '"file"'  <<<"$line"   && bad "chave mutilada: 'file2' virou 'file'"        || ok "'file2' rejeitada, nao mutilada"
grep -q '"workflow":"fix"' <<<"$line" \
  && ok "evento gravado com as chaves validas restantes" \
  || bad "chaves validas perdidas junto com as invalidas"
grep -qi "chave desconhecida" <<<"$err" \
  && ok "aviso de chave desconhecida no stderr" \
  || bad "sem aviso no stderr (veio '$err')"

h=$(newhome)
MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event decision workflow=deploy mode=turbo tool=Ed1t file_ext=go n=abc gate_mode=off session_id='a b'" 2>/dev/null
check "$(cat "$h/logs/routing.jsonl" 2>/dev/null | sed 's/"ts":"[^"]*"/"ts":"T"/')" \
      '{"ts":"T","event":"decision"}' "todos os valores fora do tipo sao rejeitados"

h=$(newhome)
MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event decision workflow=fix mode=subagent tool=Edit file_ext=.go cmd=gstack:ship project=maestro-e1 gate_mode=warn n=3 session_id=Sess-01_X" 2>/dev/null
check "$(cat "$h/logs/routing.jsonl" 2>/dev/null | sed 's/"ts":"[^"]*"/"ts":"T"/')" \
      '{"ts":"T","event":"decision","workflow":"fix","mode":"subagent","tool":"Edit","file_ext":".go","cmd":"gstack:ship","project":"maestro-e1","gate_mode":"warn","n":"3","session_id":"Sess-01_X"}' \
      "todos os valores dentro do tipo passam intactos"

# ---------------------------------------------------------------------------
echo "-- P1-1: chave duplicada"
# ---------------------------------------------------------------------------

h=$(newhome)
err=$(MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event gate_block tool=Edit tool=Write" 2>&1 >/dev/null)
line=$(cat "$h/logs/routing.jsonl" 2>/dev/null)
check "$(grep -o '"tool"' <<<"$line" | wc -l | tr -d ' ')" "1" "chave duplicada aparece uma unica vez no JSON"
grep -q '"tool":"Edit"' <<<"$line" && ok "primeira ocorrencia vence" || bad "primeira ocorrencia perdida ($line)"
grep -qi "duplicada" <<<"$err" && ok "aviso de duplicata no stderr" || bad "sem aviso de duplicata (veio '$err')"
if command -v jq >/dev/null 2>&1; then
  # jq -S mantém só a última chave repetida: se o byte-count mudar, houve duplicata.
  raw=$(tr -d ' \n' <<<"$line" | wc -c)
  viajq=$(jq -c . <<<"$line" | tr -d ' \n' | wc -c)
  check "$raw" "$viajq" "jq nao descarta nenhuma chave (sem perda silenciosa)"
fi

# ---------------------------------------------------------------------------
echo "-- DATA_MODEL §4: agents e array JSON"
# ---------------------------------------------------------------------------

h=$(newhome)
MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event decision agents=golang-pro,python-pro" 2>/dev/null
line=$(cat "$h/logs/routing.jsonl" 2>/dev/null)
grep -q '"agents":\["golang-pro","python-pro"\]' <<<"$line" \
  && ok "agents sai como array JSON" || bad "agents nao e array ($line)"
if command -v jq >/dev/null 2>&1; then
  check "$(jq -r '.agents | type' <<<"$line" 2>/dev/null)" "array" "jq confirma tipo array"
  check "$(jq -r '.agents | length' <<<"$line" 2>/dev/null)" "2" "jq confirma 2 elementos"
fi

h=$(newhome)
MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event decision agents=solo" 2>/dev/null
if command -v jq >/dev/null 2>&1; then
  check "$(jq -r '.agents | type' < "$h/logs/routing.jsonl" 2>/dev/null)" "array" "agente unico tambem vira array"
fi

h=$(newhome)
MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event decision agents=Golang_Pro,\$(id)" 2>/dev/null
grep -q '"agents"' "$h/logs/routing.jsonl" 2>/dev/null \
  && bad "agents fora do tipo foi aceito" || ok "agents fora do tipo rejeitado"

# ---------------------------------------------------------------------------
echo "-- P2-2: nenhum valor com '/' entra no log"
# ---------------------------------------------------------------------------

h=$(newhome)
err=$(MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event gate_block file_ext=/home/rcosta00/segredo/cliente.go project=a/b cmd=usr/bin/x" 2>&1 >/dev/null)
line=$(cat "$h/logs/routing.jsonl" 2>/dev/null)
grep -q '/' <<<"$line" && bad "barra vazou para o log ($line)" || ok "nenhum valor com '/' entra no log"
grep -q "segredo" <<<"$line" && bad "caminho vazou para o log" || ok "caminho completo nao vaza"
grep -qi "rejeitado" <<<"$err" && ok "aviso de rejeicao no stderr" || bad "sem aviso de rejeicao"

# ---------------------------------------------------------------------------
echo "-- P2-1: fd 9 fechado apos a escrita"
# ---------------------------------------------------------------------------

h=$(newhome)
out=$(MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event decision mode=direct; ls /proc/self/fd/9 >/dev/null 2>&1 && echo VAZOU || echo FECHADO" 2>/dev/null)
if [[ -d /proc/self/fd ]]; then
  check "$out" "FECHADO" "fd 9 fechado apos log_event (nao vaza p/ filhos)"
else
  ok "fd 9: /proc indisponivel, checagem pulada"
fi

# ---------------------------------------------------------------------------
echo "-- DATA_MODEL §4: vocabulario fechado continua fechado"
# ---------------------------------------------------------------------------

h=$(newhome)
for e in decision gate_pass gate_warn gate_block override_manual killswitch session_end; do
  MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event $e" 2>/dev/null
done
check "$(wc -l < "$h/logs/routing.jsonl" 2>/dev/null | tr -d ' ')" "7" "os 7 eventos canonicos sao aceitos"

h=$(newhome)
for e in deploy DECISION decisio gate 'decision;rm -rf /' ''; do
  MAESTRO_HOME="$h" bash -c "source '$LIB'; log_event '$e' workflow=fix" 2>/dev/null
done
if [[ -s "$h/logs/routing.jsonl" ]]; then
  bad "evento fora do vocabulario foi gravado ($(cat "$h/logs/routing.jsonl"))"
else
  ok "nenhum evento fora do vocabulario e gravado"
fi

# ---------------------------------------------------------------------------
echo "-- P2-3: maestro_record_valid (expires_at e fallback por mtime)"
# ---------------------------------------------------------------------------

mkrec() { # <home> <sid> <json>
  mkdir -p "$1/sessions"; printf '%s\n' "$3" > "$1/sessions/$2.json"
}
rv() { MAESTRO_HOME="$1" bash -c "source '$LIB'; maestro_record_valid '$2' && echo VALIDO || echo INVALIDO" 2>/dev/null; }

h=$(newhome)
future=$(date -Iseconds -d '+4 hours' 2>/dev/null || date -u -v+4H +%Y-%m-%dT%H:%M:%SZ)
past=$(date -Iseconds -d '-1 hour' 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)

mkrec "$h" fresco  "{\"session_id\":\"fresco\",\"expires_at\":\"$future\",\"workflow\":\"fix\",\"mode\":\"direct\"}"
mkrec "$h" expirado "{\"session_id\":\"expirado\",\"expires_at\":\"$past\",\"workflow\":\"fix\",\"mode\":\"direct\"}"
check "$(rv "$h" fresco)"   "VALIDO"   "expires_at no futuro => record valido"
check "$(rv "$h" expirado)" "INVALIDO" "expires_at no passado => record expirado"

# expires_at manda MESMO com mtime recente (a fonte de verdade e o campo).
touch "$h/sessions/expirado.json"
check "$(rv "$h" expirado)" "INVALIDO" "expires_at vence o mtime recente (fonte de verdade)"

# Fallback por mtime: record SEM expires_at.
h=$(newhome)
mkrec "$h" semcampo '{"session_id":"semcampo","workflow":"fix","mode":"direct"}'
check "$(rv "$h" semcampo)" "VALIDO" "sem expires_at + mtime recente => valido (fallback)"
touch -d '-5 hours' "$h/sessions/semcampo.json" 2>/dev/null || touch -t "$(date -v-5H +%Y%m%d%H%M 2>/dev/null)" "$h/sessions/semcampo.json"
check "$(rv "$h" semcampo)" "INVALIDO" "sem expires_at + mtime velho => expirado (fallback)"
check "$(MAESTRO_HOME="$h" MAESTRO_TTL_SECONDS=99999 bash -c "source '$LIB'; maestro_record_valid semcampo && echo VALIDO || echo INVALIDO" 2>/dev/null)" \
      "VALIDO" "fallback respeita MAESTRO_TTL_SECONDS"

# expires_at ilegivel cai no fallback por mtime.
h=$(newhome)
mkrec "$h" lixo '{"session_id":"lixo","expires_at":"nao-e-data","workflow":"fix","mode":"direct"}'
check "$(rv "$h" lixo)" "VALIDO" "expires_at ilegivel cai no fallback por mtime"

# Casos negativos.
h=$(newhome); mkdir -p "$h/sessions"
check "$(rv "$h" inexistente)"   "INVALIDO" "record ausente => invalido"
check "$(rv "$h" '../../etc/x')" "INVALIDO" "session_id com path traversal => invalido"
check "$(rv "$h" '')"            "INVALIDO" "session_id vazio => invalido"

# ---------------------------------------------------------------------------
echo "-- maestro_rotate_log"
# ---------------------------------------------------------------------------

h=$(newhome); mkdir -p "$h/logs"
head -c 11000000 /dev/zero | tr '\0' 'x' > "$h/logs/routing.jsonl"
MAESTRO_HOME="$h" bash -c "source '$LIB'; maestro_rotate_log" 2>/dev/null
rotated=$(ls "$h/logs"/routing-[0-9][0-9][0-9][0-9]-[0-9][0-9].jsonl 2>/dev/null | wc -l | tr -d ' ')
check "$rotated" "1" "log >10MB rotacionado para routing-YYYY-MM.jsonl"
[[ ! -s "$h/logs/routing.jsonl" ]] && ok "routing.jsonl zerado apos rotacao" || bad "routing.jsonl nao foi liberado"

h=$(newhome); mkdir -p "$h/logs"; printf 'pequeno\n' > "$h/logs/routing.jsonl"
MAESTRO_HOME="$h" bash -c "source '$LIB'; maestro_rotate_log" 2>/dev/null
check "$(ls "$h/logs" | wc -l | tr -d ' ')" "1" "log pequeno nao e rotacionado"

# ---------------------------------------------------------------------------
[[ $fail -eq 0 ]] && echo "ok   suite de robustez do log_event"
exit $fail
