#!/usr/bin/env bash
# maestro hooks/lib/common.sh — regras canônicas (ENGINEERING_SPEC + CONTRATO §1)
#
# REGRA: kill-switch é a PRIMEIRA coisa checada por todo hook (via maestro_killswitch).
# REGRA: log nunca bloqueia operação — log_event SEMPRE retorna 0 e NUNCA aborta o chamador.
# REGRA: log só carrega metadados — jamais prompt, jamais caminho completo de arquivo.
#
# API pública (estável, CONTRATO §1):
#   maestro_killswitch                 exit 0 imediato se MAESTRO_OFF=1
#   maestro_ensure_dirs                mkdir -p logs/ sessions/; nunca falha
#   maestro_now_epoch                  epoch em segundos, com fallback sem `date`
#   log_event <event> [k=v]...         append no JSONL; sempre rc=0
#   maestro_record_valid <session_id>  0 = record existe e não expirou
#   maestro_rotate_log                 rotaciona routing.jsonl >10MB p/ routing-YYYY-MM.jsonl
#
# Bash puro. Depende apenas de coreutils; `jq` e `flock` são usados quando existem,
# com degradação silenciosa quando faltam. Sem Bun, sem src/, sem rede.

set -euo pipefail

MAESTRO_HOME="${MAESTRO_HOME:-$HOME/.maestro}"
MAESTRO_LOG_DIR="${MAESTRO_LOG_DIR:-$MAESTRO_HOME/logs}"
MAESTRO_SESSIONS_DIR="${MAESTRO_SESSIONS_DIR:-$MAESTRO_HOME/sessions}"
MAESTRO_LOG_FILE="${MAESTRO_LOG_FILE:-$MAESTRO_LOG_DIR/routing.jsonl}"
MAESTRO_TTL_SECONDS="${MAESTRO_TTL_SECONDS:-14400}"        # 4h (ADR-003 v1.1)
MAESTRO_LOG_MAX_BYTES="${MAESTRO_LOG_MAX_BYTES:-10485760}" # 10MB (DATA_MODEL §4)

# Se MAESTRO_HOME mudar depois do source (cenário típico de teste), os caminhos
# derivados são recalculados. Overrides explícitos valem só até essa mudança.
_maestro_paths_home="$MAESTRO_HOME"
_maestro_refresh_paths() {
  local home="${MAESTRO_HOME:-$HOME/.maestro}"
  [[ "$home" == "$_maestro_paths_home" ]] && return 0
  MAESTRO_HOME="$home"
  MAESTRO_LOG_DIR="$MAESTRO_HOME/logs"
  MAESTRO_SESSIONS_DIR="$MAESTRO_HOME/sessions"
  MAESTRO_LOG_FILE="$MAESTRO_LOG_DIR/routing.jsonl"
  _maestro_paths_home="$MAESTRO_HOME"
  return 0
}

# ---------------------------------------------------------------------------
# Kill-switch (S-102): sai do hook inteiro com exit 0, sem efeito algum.
# ---------------------------------------------------------------------------
maestro_killswitch() {
  if [[ "${MAESTRO_OFF:-0}" == "1" ]]; then
    exit 0
  fi
}

maestro_ensure_dirs() {
  _maestro_refresh_paths || true
  # `mkdir` custa um fork (~3ms); o teste é builtin. Hook chama isso em todo evento.
  [[ -d "$MAESTRO_LOG_DIR" && -d "$MAESTRO_SESSIONS_DIR" ]] && return 0
  mkdir -p "$MAESTRO_LOG_DIR" "$MAESTRO_SESSIONS_DIR" 2>/dev/null || true
  return 0
}

# ---------------------------------------------------------------------------
# Tempo — nunca depende de `date` existir/funcionar (review P1-2).
# Ordem deliberada: printf builtin %(...)T (bash 4.2+) → EPOCHSECONDS (bash 5)
# → date(1) → 0. O builtin vem PRIMEIRO porque `date` custa um fork (~3ms
# medidos) e o hook chama isso em todo evento — o NFR é 100ms/hook.
# ---------------------------------------------------------------------------
# Estado situacional por projeto (brief E8 + grafo E11) mora em lib próprio —
# a catraca do E9 cobrou quando este arquivo cruzou 400 linhas. Ausência
# degrada: hooks que não usam brief/grafo seguem inteiros.
# shellcheck source=project-state.sh
[[ -f "${BASH_SOURCE[0]%/*}/project-state.sh" ]] && source "${BASH_SOURCE[0]%/*}/project-state.sh"

maestro_now_epoch() {
  local e=""
  printf -v e '%(%s)T' -1 2>/dev/null || e=""
  if [[ ! "$e" =~ ^[0-9]+$ ]]; then e="${EPOCHSECONDS:-}"; fi
  if [[ ! "$e" =~ ^[0-9]+$ ]]; then e=$(date +%s 2>/dev/null) || e=""; fi
  [[ "$e" =~ ^[0-9]+$ ]] || e=0
  printf '%s\n' "$e"
  return 0
}

# Timestamp ISO-8601 com offset `-03:00` (DATA_MODEL §3/§4).
# `date -Iseconds` é GNU-only e forka; o builtin dá `-0300`, então o `:` entra
# por manipulação de string — tudo em builtin, zero fork.
# Publica em $_maestro_ts em vez de escrever no stdout: `$(...)` forkaria um
# subshell a cada evento, e o caminho é quente.
_maestro_ts=""
_maestro_set_now_iso() {
  local ts=""
  printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1 2>/dev/null || ts=""
  if [[ "$ts" =~ ^(.*T[0-9:]+)([+-][0-9]{2})([0-9]{2})$ ]]; then
    ts="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
  fi
  if [[ -z "$ts" ]]; then ts=$(date -Iseconds 2>/dev/null) || ts=""; fi
  if [[ -z "$ts" ]]; then ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || ts=""; fi
  # Nada de aspas/barra invertida/quebra de linha vazando para o JSON.
  if [[ ! "$ts" =~ ^[A-Za-z0-9:+.-]{1,40}$ ]]; then ts="1970-01-01T00:00:00Z"; fi
  _maestro_ts="$ts"
  return 0
}

_maestro_year_month() {
  local ym=""
  printf -v ym '%(%Y-%m)T' -1 2>/dev/null || ym=""
  if [[ ! "$ym" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then ym=$(date +%Y-%m 2>/dev/null) || ym=""; fi
  [[ "$ym" =~ ^[0-9]{4}-[0-9]{2}$ ]] || ym="0000-00"
  printf '%s' "$ym"
  return 0
}

# ---------------------------------------------------------------------------
# Vocabulário fechado de eventos (DATA_MODEL §4). Qualquer outro valor é descartado.
# ---------------------------------------------------------------------------
_maestro_event_valid() {
  case "${1:-}" in
    decision|gate_pass|gate_warn|gate_block|override_manual|killswitch|session_end|habit_warn|consent_grant|consent_revoke|outcome|budget_warn|order_create|order_accept) return 0 ;;
    *) return 1 ;;
  esac
}

# Regex de validação POR CHAVE (CONTRATO §1). Chave desconhecida → rc=1.
# NENHUMA regex admite `/`: garantia estrutural contra logar caminho (review P2-2).
# Publica em $_maestro_re (sem `$(...)`: seria um fork por chave, por evento).
_maestro_re=""
_maestro_set_key_regex() {
  case "${1:-}" in
    session_id) _maestro_re='^[A-Za-z0-9_-]{1,64}$' ;;
    workflow)   _maestro_re='^(fix|feature|refactor|ship|audit|custom)$' ;;
    mode)       _maestro_re='^(direct|subagent|multi)$' ;;
    agents)     _maestro_re='^[a-z0-9-]+(,[a-z0-9-]+)*$' ;;
    tool)       _maestro_re='^[A-Za-z]{1,32}$' ;;
    file_ext)   _maestro_re='^\.[A-Za-z0-9]{1,12}$' ;;
    cmd)        _maestro_re='^[a-z0-9:_-]{1,48}$' ;;
    project)    _maestro_re='^[A-Za-z0-9._-]{1,48}$' ;;
    gate_mode)  _maestro_re='^(warn|block)$' ;;
    smell)      _maestro_re='^[a-z][a-z-]{2,23}$' ;;
    scope)      _maestro_re='^[a-z][a-z-]{2,23}$' ;;
    outcome)    _maestro_re='^(accepted|rework|reverted)$' ;;
    suite)      _maestro_re='^(pass|fail)$' ;;
    cap)        _maestro_re='^(steps|minutes)$' ;;
    n)          _maestro_re='^[0-9]{1,9}$' ;;
    *)          _maestro_re=""; return 1 ;;
  esac
  return 0
}

# agents=a,b,c  →  ["a","b","c"]   (DATA_MODEL §4 exige array, não string)
# Publica em $_maestro_arr.
_maestro_arr=""
_maestro_set_agents_array() {
  local csv="${1:-}" out="" a
  local IFS=','
  for a in $csv; do
    [[ -n "$a" ]] || continue
    out="$out,\"$a\""
  done
  _maestro_arr="[${out#,}]"
  return 0
}

# ---------------------------------------------------------------------------
# log_event <event> [chave=valor]...
#
# Contrato duro:
#  - evento fora do vocabulário → descartado, rc=0
#  - par inválido → REJEITADO com aviso no stderr (nunca reescrito/mutilado)
#  - chave duplicada → segunda ocorrência rejeitada (review P1-1)
#  - `agents` sai como array JSON
#  - corpo inteiro protegido: NUNCA aborta o chamador (review P1-2)
#  - fd 9 fechado após a escrita (review P2-1)
# ---------------------------------------------------------------------------
log_event() {
  # `|| :` desliga errexit para todo o corpo do impl — é o que garante que
  # nenhuma falha interna (date, mkdir, flock, disco cheio) derrube o hook.
  _maestro_log_event_impl "$@" || :
  return 0
}

_maestro_log_event_impl() {
  local event="${1:-}"
  shift || :

  if ! _maestro_event_valid "$event"; then
    echo "maestro: log: evento invalido descartado" >&2
    return 0
  fi

  _maestro_refresh_paths || :
  maestro_ensure_dirs || :
  # A checagem de rotação custa um `stat` (fork). Uma vez por processo basta:
  # um hook loga 1-3 eventos e o gatilho é 10MB.
  if [[ -z "${_maestro_rotate_checked:-}" ]]; then
    _maestro_rotate_checked=1
    maestro_rotate_log || :
  fi

  local ts pairs="" seen=" " kv k v
  _maestro_set_now_iso || :
  ts="${_maestro_ts:-1970-01-01T00:00:00Z}"

  for kv in "$@"; do
    # Sem `=` → não é par.
    if [[ "$kv" != *"="* ]]; then
      echo "maestro: log: par sem '=' rejeitado" >&2
      continue
    fi
    k="${kv%%=*}"
    v="${kv#*=}"

    if ! _maestro_set_key_regex "$k"; then
      echo "maestro: log: chave desconhecida rejeitada: '$k'" >&2
      continue
    fi

    if [[ "$seen" == *" $k "* ]]; then
      echo "maestro: log: chave duplicada rejeitada: '$k'" >&2
      continue
    fi

    # Defesa em profundidade: nenhuma regex aceita `/`, mas a checagem é
    # explícita para que a garantia sobreviva a uma futura edição da tabela.
    if [[ "$v" == */* ]]; then
      echo "maestro: log: valor com '/' rejeitado para a chave '$k'" >&2
      continue
    fi

    if [[ ! "$v" =~ $_maestro_re ]]; then
      echo "maestro: log: valor invalido rejeitado para a chave '$k'" >&2
      continue
    fi

    seen="$seen$k "
    if [[ "$k" == "agents" ]]; then
      _maestro_set_agents_array "$v" || :
      pairs="$pairs,\"agents\":$_maestro_arr"
    else
      pairs="$pairs,\"$k\":\"$v\""
    fi
  done

  local line
  printf -v line '{"ts":"%s","event":"%s"%s}' "$ts" "$event" "$pairs"

  # Append atômico, lock NÃO bloqueante (flock -n): contenção descarta a linha.
  if ! { exec 9>>"$MAESTRO_LOG_FILE"; } 2>/dev/null; then
    echo "maestro: log: arquivo de log inacessivel, linha descartada" >&2
    return 0
  fi

  if command -v flock >/dev/null 2>&1; then
    # flock -n primeiro (custo zero no caso comum). Sob contenção, algumas
    # tentativas com espera curta: o teto total (MAESTRO_LOCK_TRIES x 10ms)
    # fica bem abaixo do NFR de 100ms/hook e o log NUNCA bloqueia de fato.
    local tries="${MAESTRO_LOCK_TRIES:-5}" i=0 got=""
    [[ "$tries" =~ ^[0-9]{1,3}$ ]] || tries=5
    if flock -n 9 2>/dev/null; then
      got=1
    else
      while [[ $i -lt $tries ]]; do
        if flock -w 0.01 9 2>/dev/null; then got=1; break; fi
        i=$(( i + 1 ))
      done
    fi
    if [[ -n "$got" ]]; then
      printf '%s\n' "$line" >&9 || echo "maestro: log: falha de escrita, linha descartada" >&2
    else
      echo "maestro: log: contencao, linha descartada" >&2
    fi
  else
    # Sem flock: append best-effort (O_APPEND já dá atomicidade p/ linhas curtas).
    printf '%s\n' "$line" >&9 || echo "maestro: log: falha de escrita, linha descartada" >&2
  fi

  # P2-1: fecha o fd para não vazar para processos filhos nem reter o lock
  # até o fim do processo.
  # O grupo { } é OBRIGATÓRIO: `exec` sem comando aplica a redireção ao shell
  # INTEIRO, então `exec 9>&- 2>/dev/null` mandaria o stderr do hook chamador
  # para /dev/null permanentemente — silenciando a mensagem instrutiva do gate
  # no exit 2 e toda degradação posterior. Achado pelo agente GATE na integração.
  { exec 9>&-; } 2>/dev/null || :
  return 0
}

# ---------------------------------------------------------------------------
# maestro_record_valid <session_id>
#   rc=0  record existe e NÃO expirou
#   rc=1  ausente, ilegível, id inválido ou expirado
#
# Fonte de verdade do TTL é `expires_at` do JSON (review P2-3);
# fallback para mtime + MAESTRO_TTL_SECONDS quando o campo falta ou é ilegível.
# ---------------------------------------------------------------------------
maestro_record_valid() {
  local sid="${1:-}"
  [[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || return 1

  _maestro_refresh_paths || :
  local f="$MAESTRO_SESSIONS_DIR/$sid.json"
  [[ -f "$f" && -r "$f" ]] || return 1

  local now exp="" exp_epoch=""
  now=$(maestro_now_epoch)

  if command -v jq >/dev/null 2>&1; then
    exp=$(jq -r '.expires_at // empty' "$f" 2>/dev/null) || exp=""
  fi
  if [[ -z "$exp" ]]; then
    # Fallback sem jq: extração textual do campo.
    exp=$(grep -o '"expires_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null \
          | head -1 | sed 's/.*"\([^"]*\)"$/\1/') || exp=""
  fi

  if [[ -n "$exp" ]]; then
    exp_epoch=$(date -d "$exp" +%s 2>/dev/null) || exp_epoch=""
    if [[ ! "$exp_epoch" =~ ^[0-9]+$ ]]; then
      # BSD/macOS
      exp_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "${exp:0:19}" +%s 2>/dev/null) || exp_epoch=""
    fi
  fi

  if [[ "$exp_epoch" =~ ^[0-9]+$ ]]; then
    if [[ "$now" -lt "$exp_epoch" ]]; then return 0; else return 1; fi
  fi

  # Fallback: mtime + TTL.
  local mtime=""
  mtime=$(stat -c %Y "$f" 2>/dev/null) || mtime=""
  if [[ ! "$mtime" =~ ^[0-9]+$ ]]; then
    mtime=$(stat -f %m "$f" 2>/dev/null) || mtime=""
  fi
  [[ "$mtime" =~ ^[0-9]+$ ]] || return 1

  local ttl="${MAESTRO_TTL_SECONDS:-14400}"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=14400
  if [[ $(( now - mtime )) -lt "$ttl" ]]; then return 0; else return 1; fi
}

# ---------------------------------------------------------------------------
# maestro_rotate_log — routing.jsonl acima de 10MB vira routing-YYYY-MM.jsonl.
# Nunca falha, nunca aborta o chamador.
# ---------------------------------------------------------------------------
maestro_rotate_log() {
  _maestro_rotate_log_impl || :
  return 0
}

_maestro_rotate_log_impl() {
  _maestro_refresh_paths || :
  [[ -f "$MAESTRO_LOG_FILE" ]] || return 0

  local max="${MAESTRO_LOG_MAX_BYTES:-10485760}" size=""
  [[ "$max" =~ ^[0-9]+$ ]] || max=10485760

  size=$(stat -c %s "$MAESTRO_LOG_FILE" 2>/dev/null) || size=""
  if [[ ! "$size" =~ ^[0-9]+$ ]]; then
    size=$(stat -f %z "$MAESTRO_LOG_FILE" 2>/dev/null) || size=""
  fi
  if [[ ! "$size" =~ ^[0-9]+$ ]]; then
    size=$(wc -c < "$MAESTRO_LOG_FILE" 2>/dev/null | tr -d ' ') || size=""
  fi
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  [[ "$size" -gt "$max" ]] || return 0

  local target="$MAESTRO_LOG_DIR/routing-$(_maestro_year_month).jsonl"
  if [[ -e "$target" ]]; then
    { cat "$MAESTRO_LOG_FILE" >>"$target" 2>/dev/null && : >"$MAESTRO_LOG_FILE"; } 2>/dev/null || :
  else
    mv "$MAESTRO_LOG_FILE" "$target" 2>/dev/null || :
  fi
  return 0
}
