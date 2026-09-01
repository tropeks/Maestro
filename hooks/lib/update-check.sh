#!/usr/bin/env bash
# maestro hooks/lib/update-check.sh — E19 / S-1901
#
# Auto-update via git. O plugin roda DIRETO do clone (ADR-001: marketplace de
# diretório), então "atualizar" é `git fetch` + `merge --ff-only` — nada de
# cópia, nada de instalador. Esta lib é a ÚNICA porta de rede em runtime do
# Maestro, e a regra da casa vale por construção (Capitão, 2026-09-01: "pode
# usar rede, desde que nunca quebre a execução"):
#
#   - rede tem timeout curto (MAESTRO_UPDATE_TIMEOUT, 5s) e falha em silêncio;
#   - rede acontece no máximo uma vez por intervalo (24h) — o resto é git local;
#   - toda função devolve rc=0 (exceto apply/rollback/snooze, que devolvem 1
#     quando NÃO fizeram) e publica estado em variáveis UPD_*; quem chama
#     decide o que fazer (o hook injeta uma linha; o CLI fala com o humano);
#   - a MÁQUINA DE DESENVOLVIMENTO nunca é sobrescrita: árvore suja, commits à
#     frente do remoto ou branch fora da rastreada bloqueiam o merge — o ff-only
#     já é estritamente seguro (não perde trabalho local), e mesmo assim só roda
#     quando não há trabalho local para perder;
#   - "silêncio" NUNCA significa "atualizado": o resultado da checagem (inclusive
#     a falha) fica em $MAESTRO_HOME/update-state, que o doctor lê e reporta.
#     Lição do gstack #1974 — 45 releases de staleness silenciosa.
#
# Bash puro, sem Bun (CLAUDE.md). Sourceada por hooks/session-start.sh e por
# bin/maestro (cmd_upgrade). Não depende de common.sh; se ele estiver
# sourceado, o chamador loga o evento `upgrade` (DATA_MODEL §4) — esta lib não
# escreve no routing.jsonl.
#
# API (estado em UPD_*):
#   maestro_update_config_get <chave> <default>
#       lê `chave: valor` de $MAESTRO_HOME/config.yaml (DATA_MODEL §10)
#   maestro_update_config_set <chave> <valor>
#   maestro_update_check [--force]
#       rc=0 sempre. Publica UPD_STATE ∈ disabled|current|available|blocked|failed,
#       UPD_LOCAL/UPD_REMOTE_VER (versões do plugin.json), UPD_BEHIND, UPD_AHEAD,
#       UPD_DIRTY, UPD_BRANCH_CUR, UPD_REASON, UPD_FETCH (ok|failed|skipped),
#       UPD_SNOOZED (0|1), UPD_AUTO (0|1); grava $MAESTRO_HOME/update-state.
#       --force ignora o intervalo.
#   maestro_update_apply
#       ff-only para o ref remoto já buscado (SEM rede). rc=0 aplicou (UPD_PREV
#       = SHA anterior, UPD_FROM = versão anterior); rc=1 não aplicou (UPD_REASON).
#   maestro_update_rollback
#       volta para o `prev` do update-state com `git reset --keep` (recusa se
#       perderia alteração local). rc=0/1.
#   maestro_update_snooze
#       adia o aviso da versão remota atual: 24h → 48h → 7d (escalonado).
#
# Overrides de ambiente (testes e operação):
#   MAESTRO_NO_UPDATE_CHECK=1   desliga tudo (equivale a update_check: false)
#   UPD_MANUAL=1                o CLI: ignora o desligamento (ação explícita do humano)
#   MAESTRO_AUTO_UPGRADE=0|1    sobrepõe auto_upgrade da config
#   MAESTRO_UPDATE_INTERVAL     segundos entre fetches (default 24h da config)
#   MAESTRO_UPDATE_TIMEOUT      segundos de timeout do fetch (default 5)
#   MAESTRO_UPDATE_REPO         clone a verificar (default: o repo desta lib)
#   MAESTRO_UPDATE_REMOTE       nome do remoto (default origin)
#   MAESTRO_UPDATE_BRANCH       branch rastreada (default main)

UPD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPD_REPO="${MAESTRO_UPDATE_REPO:-$(cd "$UPD_LIB_DIR/../.." && pwd)}"
UPD_REMOTE="${MAESTRO_UPDATE_REMOTE:-origin}"
UPD_BRANCH="${MAESTRO_UPDATE_BRANCH:-main}"
UPD_HOME="${MAESTRO_HOME:-$HOME/.maestro}"
UPD_STATE_FILE="$UPD_HOME/update-state"
UPD_SNOOZE_FILE="$UPD_HOME/update-snoozed"
UPD_CONFIG_FILE="$UPD_HOME/config.yaml"
UPD_LOCK_FILE="$UPD_HOME/update.lock"

UPD_STATE=""; UPD_LOCAL=""; UPD_REMOTE_VER=""; UPD_BEHIND=0; UPD_AHEAD=0
UPD_DIRTY=0; UPD_BRANCH_CUR=""; UPD_REASON=""; UPD_FETCH="skipped"
UPD_SNOOZED=0; UPD_AUTO=0; UPD_PREV=""; UPD_FROM=""; UPD_UPGRADED_AT=""
UPD_REMOTE_SHA=""; UPD_LOCAL_SHA=""; UPD_SNOOZE_HUMAN=""

_upd_has() { command -v "$1" >/dev/null 2>&1; }
_upd_git() { git -C "$UPD_REPO" "$@"; }
_upd_now() { date +%s 2>/dev/null || echo 0; }
_upd_git_path() { # <nome> → caminho ABSOLUTO em $GIT_DIR (vale em worktree vinculado, onde .git é arquivo)
  local p; p=$(_upd_git rev-parse --git-path "$1" 2>/dev/null) || p=""
  [[ -n "$p" ]] || { printf '%s' "$UPD_REPO/.git/$1"; return 0; }
  [[ "$p" == /* ]] && printf '%s' "$p" || printf '%s/%s' "$UPD_REPO" "$p"
  return 0
}

# ---------------------------------------------------------------------------
# config.yaml — `chave: valor`, uma por linha, sem aninhamento. Valor só
# [A-Za-z0-9_.-]; nada é avaliado.
# ---------------------------------------------------------------------------
maestro_update_config_get() {
  local key="${1:-}" def="${2:-}" v=""
  if [[ -n "$key" && -f "$UPD_CONFIG_FILE" && -r "$UPD_CONFIG_FILE" ]]; then
    v=$(sed -n "s/^${key}:[[:space:]]*\([A-Za-z0-9_.-]*\)[[:space:]]*\(#.*\)\{0,1\}$/\1/p" \
          "$UPD_CONFIG_FILE" 2>/dev/null | head -1) || v=""
  fi
  printf '%s' "${v:-$def}"
  return 0
}

maestro_update_config_set() { # <chave> <valor> — cria/substitui a linha
  local key="${1:-}" val="${2:-}"
  [[ "$key" =~ ^[a-z_]{1,32}$ && "$val" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || return 1
  mkdir -p "$UPD_HOME" 2>/dev/null || return 1
  local tmp="$UPD_CONFIG_FILE.tmp.$$"
  {
    if [[ -f "$UPD_CONFIG_FILE" ]]; then
      grep -v -E "^${key}:" "$UPD_CONFIG_FILE" 2>/dev/null || :
    else
      printf '# maestro — config por máquina (DATA_MODEL §10)\n'
    fi
    printf '%s: %s\n' "$key" "$val"
  } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$UPD_CONFIG_FILE" 2>/dev/null || { rm -f "$tmp"; return 1; }
  return 0
}

_upd_version_of() { # <ref-git|caminho> → versão do plugin.json
  local src="${1:-}" json=""
  if [[ -f "$src" ]]; then
    json=$(cat "$src" 2>/dev/null) || json=""
  else
    json=$(_upd_git show "$src:.claude-plugin/plugin.json" 2>/dev/null) || json=""
  fi
  printf '%s' "$json" \
    | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' \
    | head -1
  return 0
}

_upd_state_read() { # <chave> → valor do update-state (vazio se ausente)
  [[ -f "$UPD_STATE_FILE" ]] || return 0
  sed -n "s/^${1}=\(.*\)$/\1/p" "$UPD_STATE_FILE" 2>/dev/null | head -1
  return 0
}

_upd_state_write() { # grava o estado inteiro (atômico); preserva prev/head/upgraded
  local prev up fetched head
  prev=$(_upd_state_read prev); up=$(_upd_state_read upgraded)
  fetched=$(_upd_state_read fetched); head=$(_upd_state_read head)
  [[ "$UPD_FETCH" == "ok" ]] && fetched=$(_upd_now)
  [[ -n "$UPD_PREV" ]] && prev="$UPD_PREV"
  [[ -n "$UPD_UPGRADED_AT" ]] && { up="$UPD_UPGRADED_AT"; head="$UPD_LOCAL_SHA"; }
  mkdir -p "$UPD_HOME" 2>/dev/null || return 0
  local tmp="$UPD_STATE_FILE.tmp.$$"
  {
    printf 'schema=maestro-update-state-v1\n'
    printf 'checked=%s\n' "$(_upd_now)"
    printf 'fetched=%s\n' "${fetched:-0}"
    printf 'fetch=%s\n' "$UPD_FETCH"
    printf 'result=%s\n' "$UPD_STATE"
    printf 'reason=%s\n' "$UPD_REASON"
    printf 'local=%s\n' "$UPD_LOCAL"
    printf 'remote=%s\n' "$UPD_REMOTE_VER"
    printf 'behind=%s\n' "$UPD_BEHIND"
    printf 'ahead=%s\n' "$UPD_AHEAD"
    printf 'dirty=%s\n' "$UPD_DIRTY"
    printf 'branch=%s\n' "$UPD_BRANCH_CUR"
    printf 'prev=%s\n' "${prev:-}"
    printf 'head=%s\n' "${head:-}"
    printf 'upgraded=%s\n' "${up:-}"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$UPD_STATE_FILE" 2>/dev/null || rm -f "$tmp"
  return 0
}

_upd_fetch() { # a ÚNICA linha de rede do Maestro. rc = do git.
  # O teto de tempo é INEGOCIÁVEL: sem `timeout` (macOS de fábrica, imagem
  # mínima), um watchdog em bash faz o papel — nunca um fetch sem limite, porque
  # uma conexão que trava (não falha) travaria o SessionStart inteiro.
  local to="${MAESTRO_UPDATE_TIMEOUT:-5}"; [[ "$to" =~ ^[0-9]{1,4}$ ]] || to=5
  export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"
  if _upd_has timeout; then
    timeout "$to" git -C "$UPD_REPO" fetch -q "$UPD_REMOTE" "$UPD_BRANCH" >/dev/null 2>&1
    return $?
  fi
  local pid wd rc=0
  git -C "$UPD_REPO" fetch -q "$UPD_REMOTE" "$UPD_BRANCH" >/dev/null 2>&1 </dev/null &
  pid=$!
  ( sleep "$to"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wd=$!
  wait "$pid" 2>/dev/null || rc=$?
  kill "$wd" 2>/dev/null || :
  wait "$wd" 2>/dev/null || :
  return "$rc"
}

_upd_locked() { # _upd_locked <função> — seção crítica NÃO bloqueante (rc 99 = ocupada)
  # flock quando existe; sem ele, mkdir atômico (lock de diretório) com o
  # mesmo contrato: quem chega segundo pula, nunca espera. Lock órfão (>120s,
  # processo morto) é removido — um crash não pode trancar o update para sempre.
  if _upd_has flock; then
    ( flock -n 9 || exit 99; "$@" ) 9>"$UPD_LOCK_FILE"
    return $?
  fi
  local d="$UPD_LOCK_FILE.d" age now rc=0
  if ! mkdir "$d" 2>/dev/null; then
    now=$(_upd_now); age=$(( now - $(stat -c %Y "$d" 2>/dev/null || stat -f %m "$d" 2>/dev/null || echo "$now") ))
    (( age > 120 )) && rmdir "$d" 2>/dev/null && mkdir "$d" 2>/dev/null || return 99
  fi
  "$@" || rc=$?
  rmdir "$d" 2>/dev/null || :
  return "$rc"
}

# ---------------------------------------------------------------------------
# A checagem.
# ---------------------------------------------------------------------------
_upd_disabled() { # env vence config; UPD_MANUAL=1 (CLI) ignora o desligamento
  [[ "${UPD_MANUAL:-0}" == "1" ]] && return 1
  [[ "${MAESTRO_NO_UPDATE_CHECK:-0}" == "1" ]] && return 0
  [[ "$(maestro_update_config_get update_check true)" == "false" ]]
}

_upd_resolve_auto() { # publica UPD_AUTO (env vence config; default: ligado)
  case "${MAESTRO_AUTO_UPGRADE:-}" in
    1) UPD_AUTO=1 ;;
    0) UPD_AUTO=0 ;;
    *) if [[ "$(maestro_update_config_get auto_upgrade true)" == "true" ]]; then UPD_AUTO=1; else UPD_AUTO=0; fi ;;
  esac
  return 0
}

_upd_maybe_fetch() { # <force> — respeita o intervalo; publica UPD_FETCH
  local force="${1:-0}" interval="${MAESTRO_UPDATE_INTERVAL:-}" fetched now
  if [[ ! "$interval" =~ ^[0-9]{1,9}$ ]]; then
    local h; h=$(maestro_update_config_get update_interval_hours 24)
    [[ "$h" =~ ^[0-9]{1,4}$ ]] || h=24
    interval=$(( h * 3600 ))
  fi
  fetched=$(_upd_state_read fetched); [[ "$fetched" =~ ^[0-9]+$ ]] || fetched=0
  now=$(_upd_now)
  if (( force == 1 )) || (( now - fetched >= interval )); then
    mkdir -p "$UPD_HOME" 2>/dev/null || :
    if _upd_locked _upd_fetch; then UPD_FETCH="ok"; else UPD_FETCH="failed"; fi
  fi
  return 0
}

_upd_measure() { # posição local vs ref remoto — git local. rc=1 sem o ref.
  local ref="refs/remotes/$UPD_REMOTE/$UPD_BRANCH"
  _upd_git rev-parse --verify -q "$ref" >/dev/null 2>&1 || return 1
  UPD_REMOTE_SHA=$(_upd_git rev-parse "$ref" 2>/dev/null) || UPD_REMOTE_SHA=""
  UPD_LOCAL_SHA=$(_upd_git rev-parse HEAD 2>/dev/null) || UPD_LOCAL_SHA=""
  UPD_REMOTE_VER=$(_upd_version_of "$ref")
  UPD_BEHIND=$(_upd_git rev-list --count "HEAD..$ref" 2>/dev/null) || UPD_BEHIND=0
  UPD_AHEAD=$(_upd_git rev-list --count "$ref..HEAD" 2>/dev/null) || UPD_AHEAD=0
  [[ "$UPD_BEHIND" =~ ^[0-9]+$ ]] || UPD_BEHIND=0
  [[ "$UPD_AHEAD"  =~ ^[0-9]+$ ]] || UPD_AHEAD=0
  UPD_BRANCH_CUR=$(_upd_git branch --show-current 2>/dev/null) || UPD_BRANCH_CUR=""
  if [[ -n "$(_upd_git status --porcelain --untracked-files=no 2>/dev/null | head -1)" ]]; then
    UPD_DIRTY=1
  fi
  return 0
}

_upd_classify() { # UPD_STATE/UPD_REASON a partir da medição — as guardas da máquina de dev
  if (( UPD_BEHIND == 0 )); then
    UPD_STATE="current"
  elif [[ "$UPD_BRANCH_CUR" != "$UPD_BRANCH" ]]; then
    UPD_STATE="blocked"; UPD_REASON="branch"
  elif (( UPD_AHEAD > 0 )); then
    UPD_STATE="blocked"; UPD_REASON="ahead"
  elif (( UPD_DIRTY == 1 )); then
    UPD_STATE="blocked"; UPD_REASON="dirty"
  elif [[ -e "$(_upd_git_path MERGE_HEAD)" || -d "$(_upd_git_path rebase-merge)" || -d "$(_upd_git_path rebase-apply)" ]]; then
    UPD_STATE="blocked"; UPD_REASON="in-progress"
  else
    UPD_STATE="available"
  fi
  return 0
}

_upd_read_snooze() { # só silencia o AVISO da versão adiada; nunca muda o estado
  [[ "$UPD_STATE" == "available" && -f "$UPD_SNOOZE_FILE" ]] || return 0
  local s_sha s_until now
  s_sha=$(awk 'NR==1 {print $1}' "$UPD_SNOOZE_FILE" 2>/dev/null) || s_sha=""
  s_until=$(awk 'NR==1 {print $2}' "$UPD_SNOOZE_FILE" 2>/dev/null) || s_until=0
  [[ "$s_until" =~ ^[0-9]+$ ]] || s_until=0
  now=$(_upd_now)
  [[ "$s_sha" == "$UPD_REMOTE_SHA" ]] && (( now < s_until )) && UPD_SNOOZED=1
  return 0
}

maestro_update_check() {
  local force=0
  [[ "${1:-}" == "--force" ]] && force=1

  UPD_STATE=""; UPD_REASON=""; UPD_FETCH="skipped"; UPD_SNOOZED=0
  UPD_BEHIND=0; UPD_AHEAD=0; UPD_DIRTY=0; UPD_BRANCH_CUR=""; UPD_PREV=""
  UPD_REMOTE_VER=""; UPD_REMOTE_SHA=""; UPD_LOCAL_SHA=""
  UPD_LOCAL=$(_upd_version_of "$UPD_REPO/.claude-plugin/plugin.json")

  if _upd_disabled; then UPD_STATE="disabled"; UPD_REASON="config"; return 0; fi
  _upd_resolve_auto

  # É um clone git com o remoto? Sem isso não há o que atualizar.
  if ! _upd_has git || ! _upd_git rev-parse --git-dir >/dev/null 2>&1; then
    UPD_STATE="failed"; UPD_REASON="not-a-repo"; _upd_state_write; return 0
  fi
  if ! _upd_git remote get-url "$UPD_REMOTE" >/dev/null 2>&1; then
    UPD_STATE="failed"; UPD_REASON="no-remote"; _upd_state_write; return 0
  fi

  _upd_maybe_fetch "$force"
  if ! _upd_measure; then
    UPD_STATE="failed"; UPD_REASON="no-remote-ref"; _upd_state_write; return 0
  fi
  _upd_classify
  _upd_read_snooze
  _upd_state_write
  return 0
}

# ---------------------------------------------------------------------------
# Aplicar: ff-only para o ref já buscado. Sem rede.
# ---------------------------------------------------------------------------
_upd_merge() { # sob o lock: só merge se o HEAD ainda é o que foi MEDIDO (rc 98 = outro processo já mexeu)
  local head; head=$(git -C "$UPD_REPO" rev-parse HEAD 2>/dev/null) || return 1
  [[ "$head" == "$UPD_LOCAL_SHA" ]] || return 98
  GIT_TERMINAL_PROMPT=0 git -C "$UPD_REPO" merge --ff-only -q "refs/remotes/$UPD_REMOTE/$UPD_BRANCH" >/dev/null 2>&1
}

maestro_update_apply() {
  local prev rc=0
  UPD_PREV=""; UPD_FROM=""
  if [[ "$UPD_STATE" != "available" ]]; then
    [[ -n "$UPD_REASON" ]] || UPD_REASON="$UPD_STATE"
    return 1
  fi
  prev="$UPD_LOCAL_SHA"
  [[ -n "$prev" ]] || { UPD_REASON="no-head"; return 1; }
  # Race entre duas sessões: a segunda mediu "available" antes do merge da
  # primeira. Sem esta guarda ela faria um merge vazio e SOBRESCREVERIA o prev
  # do rollback com o HEAD já novo — rollback viraria no-op silencioso.
  _upd_locked _upd_merge || rc=$?
  if (( rc != 0 )); then
    UPD_REASON="merge"
    (( rc == 99 )) && UPD_REASON="locked"
    (( rc == 98 )) && UPD_REASON="raced"
    return 1
  fi
  UPD_PREV="$prev"
  UPD_UPGRADED_AT=$(_upd_now)
  UPD_FROM="$UPD_LOCAL"
  UPD_LOCAL=$(_upd_version_of "$UPD_REPO/.claude-plugin/plugin.json")
  UPD_LOCAL_SHA=$(_upd_git rev-parse HEAD 2>/dev/null) || UPD_LOCAL_SHA=""
  UPD_STATE="current"; UPD_REASON="upgraded"; UPD_BEHIND=0
  _upd_state_write
  return 0
}

maestro_update_rollback() {
  local prev head cur; prev=$(_upd_state_read prev); head=$(_upd_state_read head)
  UPD_REASON=""; UPD_FROM=""
  [[ "$prev" =~ ^[0-9a-f]{7,40}$ ]] || { UPD_REASON="no-prev"; return 1; }
  _upd_git cat-file -e "$prev^{commit}" 2>/dev/null || { UPD_REASON="prev-missing"; return 1; }
  # --keep protege só o NÃO commitado. Commit local feito DEPOIS do upgrade
  # ficaria órfão (só o reflog o acharia): se o HEAD não é mais o que o upgrade
  # produziu, o rollback é manual — a ferramenta não desfaz trabalho de gente.
  cur=$(_upd_git rev-parse HEAD 2>/dev/null) || cur=""
  if [[ -n "$head" && "$cur" != "$head" ]]; then UPD_REASON="diverged"; return 1; fi
  UPD_FROM=$(_upd_version_of "$UPD_REPO/.claude-plugin/plugin.json")
  _upd_git reset -q --keep "$prev" >/dev/null 2>&1 || { UPD_REASON="reset"; return 1; }
  # prev consumido (rollback do rollback é `maestro upgrade`); o estado gravado
  # é o MEDIDO de novo, nunca um "available" fixo — árvore e branch podem ter mudado.
  UPD_PREV=""; UPD_UPGRADED_AT=""
  if [[ -f "$UPD_STATE_FILE" ]]; then
    sed -i 's/^prev=.*$/prev=/; s/^head=.*$/head=/' "$UPD_STATE_FILE" 2>/dev/null || :
  fi
  UPD_LOCAL=$(_upd_version_of "$UPD_REPO/.claude-plugin/plugin.json")
  UPD_BEHIND=0; UPD_AHEAD=0; UPD_DIRTY=0; UPD_STATE=""; UPD_REASON=""
  if _upd_measure; then _upd_classify; else UPD_STATE="failed"; UPD_REASON="no-remote-ref"; fi
  [[ "$UPD_STATE" == "available" ]] && UPD_REASON="rolled-back"
  _upd_state_write
  return 0
}

maestro_update_snooze() { # 24h → 48h → 7d para a MESMA versão remota
  local sha="${UPD_REMOTE_SHA:-}" level=0 s_sha now until
  [[ -n "$sha" ]] || sha=$(_upd_git rev-parse "refs/remotes/$UPD_REMOTE/$UPD_BRANCH" 2>/dev/null) || sha=""
  [[ -n "$sha" ]] || { UPD_REASON="no-remote-ref"; return 1; }
  if [[ -f "$UPD_SNOOZE_FILE" ]]; then
    s_sha=$(awk 'NR==1 {print $1}' "$UPD_SNOOZE_FILE" 2>/dev/null) || s_sha=""
    if [[ "$s_sha" == "$sha" ]]; then
      level=$(awk 'NR==1 {print $3}' "$UPD_SNOOZE_FILE" 2>/dev/null) || level=0
      [[ "$level" =~ ^[0-9]+$ ]] || level=0
    fi
  fi
  level=$(( level + 1 )); (( level > 3 )) && level=3
  now=$(_upd_now)
  case "$level" in
    1) until=$(( now + 86400 ));  UPD_SNOOZE_HUMAN="24h" ;;
    2) until=$(( now + 172800 )); UPD_SNOOZE_HUMAN="48h" ;;
    *) until=$(( now + 604800 )); UPD_SNOOZE_HUMAN="7 dias" ;;
  esac
  mkdir -p "$UPD_HOME" 2>/dev/null || :
  printf '%s %s %s\n' "$sha" "$until" "$level" > "$UPD_SNOOZE_FILE" 2>/dev/null || return 1
  return 0
}
