#!/usr/bin/env bash
# maestro hooks/lib/telemetry-sync.sh — E20 / S-2001
#
# Git como barramento de telemetria. Cada máquina publica SEUS logs
# (routing*.jsonl — metadados por construção: chaves tipadas, vocabulário
# fechado, nenhuma chave aceita `/`) num repo privado, em
# logs/<host-id>/, um escritor por arquivo: nunca há conflito de merge. O retro
# agrega a união (`maestro retro --all`). Nada mais sai da máquina: records,
# briefs, evidência e consentimentos continuam locais (DATA_MODEL §11).
#
# Mesmas regras do E19 — rede nunca é DEPENDÊNCIA:
#   - opt-in por máquina: `telemetry_remote: <url>` no config.yaml; sem isso,
#     zero efeito. MAESTRO_NO_TELEMETRY=1 desliga na hora;
#   - toda operação de git com rede passa por _upd_run_timed (timeout ou
#     watchdog), uma vez por intervalo (24h), sob lock não bloqueante;
#   - falha é silenciosa para a sessão e REGISTRADA em $MAESTRO_HOME/telemetry-state,
#     que o doctor lê — silêncio nunca é "publicado".
#
# Depende de hooks/lib/update-check.sh (primitivos _upd_run_timed, _upd_locked,
# _upd_kv_lookup, _upd_now, maestro_update_config_get). Bash puro, sem Bun.
#
# API (estado em TEL_*):
#   maestro_telemetry_enabled       rc=0 se há remoto configurado e não está desligada
#   maestro_telemetry_host_id       imprime o id da máquina (8 hex do sha256 do hostname)
#   maestro_telemetry_push [--force]
#       rc=0 sempre. Publica TEL_STATE ∈ disabled|pushed|nochange|skipped|failed,
#       TEL_REASON, TEL_FILES; grava telemetry-state. --force ignora o intervalo.
#   maestro_telemetry_pull          rc=0 se o clone local ficou em dia (para o retro)
#
# Overrides (testes e operação):
#   MAESTRO_NO_TELEMETRY=1        desliga
#   MAESTRO_TELEMETRY_REMOTE      sobrepõe telemetry_remote da config
#   MAESTRO_TELEMETRY_DIR         clone local (default $MAESTRO_HOME/telemetry)
#   MAESTRO_TELEMETRY_INTERVAL    segundos entre pushes (default 24h da config)
#   MAESTRO_TELEMETRY_TIMEOUT     segundos por operação de rede (default 10)
#   MAESTRO_HOST_ID               sobrepõe o id da máquina

TEL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F _upd_run_timed >/dev/null 2>&1; then
  # shellcheck source=update-check.sh
  source "$TEL_LIB_DIR/update-check.sh"
fi

TEL_HOME="${MAESTRO_HOME:-$HOME/.maestro}"
TEL_DIR="${MAESTRO_TELEMETRY_DIR:-$TEL_HOME/telemetry}"
TEL_STATE_FILE="$TEL_HOME/telemetry-state"
TEL_LOCK_FILE="$TEL_HOME/telemetry.lock"
TEL_LOG_DIR="${MAESTRO_LOG_DIR:-$TEL_HOME/logs}"

TEL_STATE=""; TEL_REASON=""; TEL_FILES=0; TEL_REMOTE=""; TEL_HOST=""

_tel_now() { _upd_now; }
_tel_timeout() { local t="${MAESTRO_TELEMETRY_TIMEOUT:-10}"; [[ "$t" =~ ^[0-9]{1,4}$ ]] || t=10; printf '%s' "$t"; }
_tel_locked() { local UPD_LOCK_FILE="$TEL_LOCK_FILE"; _upd_locked "$@"; }
_tel_git() { git -C "$TEL_DIR" -c user.name=maestro -c user.email=maestro@localhost -c commit.gpgsign=false "$@"; }
_tel_state_read() { _upd_kv_lookup "$TEL_STATE_FILE" "$1" "="; return 0; }

maestro_telemetry_remote() { # imprime a URL configurada (vazio = desligada)
  local r="${MAESTRO_TELEMETRY_REMOTE:-}"
  [[ -n "$r" ]] || r=$(_upd_kv_lookup "${MAESTRO_HOME:-$HOME/.maestro}/config.yaml" telemetry_remote ":" | tr -d '[:space:]')
  # URL de git: sem espaço, sem aspas, sem `;` — nada aqui é avaliado, mas o
  # valor vai para a linha de comando do git e o tipo fechado evita surpresa.
  [[ "$r" =~ ^[A-Za-z0-9@:/._~+-]{1,200}$ ]] || r=""
  printf '%s' "$r"
  return 0
}

maestro_telemetry_enabled() {
  [[ "${MAESTRO_NO_TELEMETRY:-0}" == "1" ]] && return 1
  TEL_REMOTE=$(maestro_telemetry_remote)
  [[ -n "$TEL_REMOTE" ]]
}

maestro_telemetry_host_id() {
  local id="${MAESTRO_HOST_ID:-}" hn=""
  if [[ ! "$id" =~ ^[a-z0-9]{4,16}$ ]]; then
    hn=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)
    if _upd_has sha256sum; then id=$(printf '%s' "$hn" | sha256sum | cut -c1-8)
    elif _upd_has shasum; then id=$(printf '%s' "$hn" | shasum -a 256 | cut -c1-8)
    else id=$(printf '%s' "$hn" | cksum | cut -d' ' -f1); fi
  fi
  printf '%s' "$id"
  return 0
}

_tel_state_write() {
  local pushed; pushed=$(_tel_state_read pushed)
  [[ "$TEL_STATE" == "pushed" ]] && pushed=$(_tel_now)
  mkdir -p "$TEL_HOME" 2>/dev/null || return 0
  local tmp="$TEL_STATE_FILE.tmp.$$"
  {
    printf 'schema=maestro-telemetry-state-v1\n'
    printf 'checked=%s\n' "$(_tel_now)"
    printf 'pushed=%s\n' "${pushed:-0}"
    printf 'result=%s\n' "$TEL_STATE"
    printf 'reason=%s\n' "$TEL_REASON"
    printf 'host=%s\n' "$TEL_HOST"
    printf 'files=%s\n' "$TEL_FILES"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$TEL_STATE_FILE" 2>/dev/null || rm -f "$tmp"
  return 0
}

_tel_push_due() {
  local interval="${MAESTRO_TELEMETRY_INTERVAL:-}" pushed now
  if [[ ! "$interval" =~ ^[0-9]{1,9}$ ]]; then
    local h; h=$(maestro_update_config_get telemetry_interval_hours 24)
    [[ "$h" =~ ^[0-9]{1,4}$ ]] || h=24
    interval=$(( h * 3600 ))
  fi
  pushed=$(_tel_state_read pushed); [[ "$pushed" =~ ^[0-9]+$ ]] || pushed=0
  now=$(_tel_now)
  (( now - pushed >= interval ))
}

_tel_ensure_clone() { # rc=0 com $TEL_DIR sendo um clone do remoto (cria se preciso)
  if git -C "$TEL_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    local cur; cur=$(git -C "$TEL_DIR" remote get-url origin 2>/dev/null) || cur=""
    [[ "$cur" == "$TEL_REMOTE" ]] || git -C "$TEL_DIR" remote set-url origin "$TEL_REMOTE" 2>/dev/null || return 1
    return 0
  fi
  mkdir -p "$(dirname "$TEL_DIR")" 2>/dev/null || return 1
  # clone de repo vazio funciona (só avisa); rede com teto.
  _upd_run_timed "$(_tel_timeout)" git clone -q "$TEL_REMOTE" "$TEL_DIR" || return 1
  git -C "$TEL_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  # O barramento vive em `main`, sempre. Se o HEAD do remoto aponta para outro
  # nome (bare recém-criado: `master`) o clone nasce órfão — parte de origin/main
  # quando ele existe; num remoto vazio, fixa o branch unborn como main.
  git -C "$TEL_DIR" rev-parse --verify -q HEAD >/dev/null 2>&1 && return 0
  if git -C "$TEL_DIR" rev-parse --verify -q refs/remotes/origin/main >/dev/null 2>&1; then
    git -C "$TEL_DIR" checkout -q -B main refs/remotes/origin/main >/dev/null 2>&1 || return 1
  else
    git -C "$TEL_DIR" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1 || :
  fi
  return 0
}

_tel_sync_logs() { # copia routing*.jsonl para logs/<host>/; imprime quantos arquivos
  local dest="$TEL_DIR/logs/$TEL_HOST" f n=0 name
  mkdir -p "$dest" 2>/dev/null || { echo 0; return 1; }
  shopt -s nullglob
  for f in "$TEL_LOG_DIR"/routing.jsonl "$TEL_LOG_DIR"/routing-*.jsonl; do
    [[ -s "$f" ]] || continue
    name="${f##*/}"; [[ "$name" == "routing.jsonl" ]] && name="routing-current.jsonl"
    cp -f -- "$f" "$dest/$name" 2>/dev/null && n=$(( n + 1 ))
  done
  shopt -u nullglob
  hostname 2>/dev/null > "$dest/HOST" || :
  echo "$n"
  return 0
}

_tel_branch() { # branch do clone (unborn incluído); vazio nunca — o barramento usa `main`
  local b; b=$(git -C "$TEL_DIR" branch --show-current 2>/dev/null) || b=""
  [[ -n "$b" ]] || b="main"
  printf '%s' "$b"
}

_tel_commit_push() { # sob o lock: add, commit (se mudou), rebase no remoto, push do que falta
  _tel_git add -A logs >/dev/null 2>&1 || return 1
  if ! _tel_git diff --cached --quiet 2>/dev/null; then
    _tel_git commit -q -m "telemetry: $TEL_HOST $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" >/dev/null 2>&1 || return 1
  fi
  _tel_rebase_on_remote || return 2
  # Nada local além do remoto (inclusive commit de um push que falhou antes)? Então
  # não há o que publicar — e "sem mudança" é um resultado, não uma falha.
  local base head; base=$(_tel_remote_base); head=$(git -C "$TEL_DIR" rev-parse HEAD 2>/dev/null) || head=""
  [[ -n "$head" ]] || return 3
  [[ -n "$base" && "$base" == "$head" ]] && return 3
  _upd_run_timed "$(_tel_timeout)" git -C "$TEL_DIR" push -q -u origin "$(_tel_branch)" || return 1
  return 0
}

_tel_remote_base() { # SHA do ramo remoto correspondente ao local (senão origin/HEAD); vazio = remoto vazio
  git -C "$TEL_DIR" rev-parse --verify -q "refs/remotes/origin/$(_tel_branch)" 2>/dev/null \
    || git -C "$TEL_DIR" rev-parse --verify -q refs/remotes/origin/HEAD 2>/dev/null \
    || :
}

_tel_rebase_on_remote() { # outro host pode ter publicado; diretórios distintos → rebase limpo
  # Fetch falho não é erro aqui: o push vai falhar sozinho se estiver atrás.
  _upd_run_timed "$(_tel_timeout)" git -C "$TEL_DIR" fetch -q origin || return 0
  local base; base=$(_tel_remote_base)
  [[ -n "$base" ]] || return 0
  _tel_git rebase -q "$base" >/dev/null 2>&1 && return 0
  # nunca deixa o clone num estado a meio
  _tel_git rebase --abort >/dev/null 2>&1 || :
  return 1
}

maestro_telemetry_push() {
  local force=0; [[ "${1:-}" == "--force" ]] && force=1
  TEL_STATE=""; TEL_REASON=""; TEL_FILES=0
  if ! maestro_telemetry_enabled; then TEL_STATE="disabled"; TEL_REASON="config"; return 0; fi
  TEL_HOST=$(maestro_telemetry_host_id)
  if (( force == 0 )) && ! _tel_push_due; then TEL_STATE="skipped"; TEL_REASON="interval"; return 0; fi
  if ! _upd_has git; then TEL_STATE="failed"; TEL_REASON="no-git"; _tel_state_write; return 0; fi
  if ! _tel_ensure_clone; then TEL_STATE="failed"; TEL_REASON="clone"; _tel_state_write; return 0; fi
  TEL_FILES=$(_tel_sync_logs) || { TEL_STATE="failed"; TEL_REASON="copy"; _tel_state_write; return 0; }
  local rc=0
  _tel_locked _tel_commit_push || rc=$?
  case "$rc" in
    0)  TEL_STATE="pushed" ;;
    3)  TEL_STATE="nochange" ;;
    2)  TEL_STATE="failed"; TEL_REASON="rebase" ;;
    99) TEL_STATE="failed"; TEL_REASON="locked" ;;
    *)  TEL_STATE="failed"; TEL_REASON="push" ;;
  esac
  _tel_state_write
  return 0
}

maestro_telemetry_pull() { # deixa $TEL_DIR em dia com o remoto (para o retro --all)
  TEL_REASON=""
  maestro_telemetry_enabled || { TEL_REASON="config"; return 1; }
  _upd_has git || { TEL_REASON="no-git"; return 1; }
  _tel_ensure_clone || { TEL_REASON="clone"; return 1; }
  local to; to=$(_tel_timeout)
  _upd_run_timed "$to" git -C "$TEL_DIR" fetch -q origin || { TEL_REASON="fetch"; return 1; }
  local base; base=$(_tel_remote_base)
  [[ -n "$base" ]] || return 0   # remoto vazio: nada a puxar
  _tel_git merge -q --ff-only "$base" >/dev/null 2>&1 || { TEL_REASON="merge"; return 1; }
  return 0
}
