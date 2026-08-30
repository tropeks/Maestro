#!/usr/bin/env bash
# maestro hooks/pre-tool-gate.sh — gate estrutural (E2/S-203)
# Evento PreToolUse, matcher Edit|Write|MultiEdit.
#
# Lógica NORMATIVA (API_SPEC §1), nesta ordem exata:
#   1. kill-switch
#   2. lê do stdin (JSON do Claude Code, via jq): tool_name, tool_input.file_path, session_id
#   3. denylist por caminho  → block SEMPRE (exit 2 + gate_block), mesmo com decisão registrada
#   4. allowlist caminho+extensão de não-código → exit 0
#   5. decision record válido e não expirado → exit 0 + gate_pass
#   6. senão, conforme MAESTRO_GATE_MODE: warn → exit 0 + gate_warn + mensagem
#                                          block → exit 2 + gate_block
#
# Filosofia (ADR-003 v1.1): o gate é **anti-descuido, best-effort**. Qualquer
# componente faltando ou quebrado degrada com **exit 0** — nunca bloqueia trabalho.
# Saem 2 apenas dois caminhos deliberados: a denylist de autoproteção e mode=block.
#
# Log: só metadados. O caminho do arquivo NUNCA é logado — só a extensão.
# Bash puro: jq + coreutils. Sem Bun, sem src/, sem rede, sem tocar no disco
# para resolver o caminho (normalização é 100% léxica: o arquivo do Write pode
# nem existir ainda, e realpath custaria um fork).

set -euo pipefail
# Sem `$(cd "$(dirname ...)" && pwd)`: são 2 forks (~3ms) num hook cujo NFR é
# 50ms. O source acontece antes de qualquer `cd`, então o caminho relativo basta.
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR="."
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ── 1. kill-switch ─────────────────────────────────────────────────────────
maestro_killswitch

# Globbing desligado: as listas da política são expandidas por word-splitting
# deliberado; sem isto um valor como `*` na política viraria expansão de arquivos.
set -f

_gate_debug() { [[ "${MAESTRO_DEBUG:-0}" == "1" ]] && echo "maestro: gate: $*" >&2 || true; }

# ---------------------------------------------------------------------------
# Normalização léxica de caminho. Absolutiza (relativo → $CLAUDE_PROJECT_DIR),
# colapsa `//`, remove `.` e resolve `..` sem tocar no filesystem.
# Publica em $_gate_norm (evita um fork de subshell por chamada).
# ---------------------------------------------------------------------------
#
# CUSTO: o laço é quadrático no tamanho da string (bash copia o resto do
# caminho a cada segmento) — 22 KB custam ~500ms, muito acima do NFR de 50ms.
# Por isso caminhos acima de MAESTRO_GATE_MAX_PATH são tratados fora daqui
# (ver "caminho patológico" adiante), nunca normalizados.
MAESTRO_GATE_MAX_PATH="${MAESTRO_GATE_MAX_PATH:-1024}"
[[ "$MAESTRO_GATE_MAX_PATH" =~ ^[0-9]{1,6}$ ]] || MAESTRO_GATE_MAX_PATH=1024

_gate_norm=""
_gate_normalize() {
  local p="${1:-}" seg rest stack=""
  [[ -n "$p" ]] || { _gate_norm=""; return 1; }

  if [[ "$p" != /* ]]; then
    local base="${CLAUDE_PROJECT_DIR:-$PWD}"
    [[ "$base" == /* ]] || base="$PWD"
    p="$base/$p"
  fi

  rest="$p"
  while [[ -n "$rest" ]]; do
    seg="${rest%%/*}"
    if [[ "$seg" == "$rest" ]]; then rest=""; else rest="${rest#*/}"; fi
    case "$seg" in
      "" | ".") ;;
      "..") stack="${stack%/*}" ;;   # clampa na raiz: "" continua ""
      *) stack="$stack/$seg" ;;
    esac
  done
  _gate_norm="${stack:-/}"
  return 0
}

# Casamento de prefixo de uma lista separada por espaço, contra caminho
# RELATIVO à raiz do projeto. Entrada terminada em `/` = diretório (prefixo);
# entrada sem `/` = arquivo exato ou diretório com tudo abaixo.
# Falso positivo evitado: `hooks/` não casa `hooksfoo/x.go`.
_gate_prefix_match() {
  local rel="${1:-}" list="${2:-}" e
  [[ -n "$rel" && -n "$list" ]] || return 1
  for e in $list; do
    e="${e#./}"
    [[ -n "$e" ]] || continue
    if [[ "$e" == */ ]]; then
      [[ "$rel" == "$e"* ]] && return 0
    else
      [[ "$rel" == "$e" || "$rel" == "$e"/* ]] && return 0
    fi
  done
  return 1
}

# Casamento CONSERVADOR usado só em caminho patológico (acima do teto E com
# segmentos `.`/`..`, isto é, longo demais para normalizar e enfeitado com
# travessia). Casa a entrada da denylist em QUALQUER posição do caminho.
# Over-block deliberado: entre liberar um bypass e barrar um caminho de >1 KB
# recheado de `../`, barra-se — nenhum arquivo real do usuário se parece com isso.
_gate_deny_anywhere() {
  local p="/${1#/}/" list="${2:-}" e
  [[ -n "$list" ]] || return 1
  for e in $list; do
    e="${e#./}"; e="${e%/}"
    [[ -n "$e" ]] || continue
    [[ "$p" == *"/$e/"* ]] && return 0
  done
  return 1
}

_gate_ext_match() {
  local ext="${1:-}" list="${2:-}" e
  [[ -n "$ext" && -n "$list" ]] || return 1
  for e in $list; do
    [[ "$ext" == "${e,,}" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Política compilada (CONTRATO §2), escrita pelo session-start a partir de
# config/routing-table.yaml — fonte de verdade única.
# Ausente/ilegível/insourceável → degrada com exit 0.
# ---------------------------------------------------------------------------
_maestro_refresh_paths 2>/dev/null || true
POLICY_FILE="${MAESTRO_GATE_POLICY:-$MAESTRO_HOME/gate-policy.sh}"
if [[ ! -f "$POLICY_FILE" || ! -r "$POLICY_FILE" ]]; then
  _gate_debug "politica ausente, degradando"
  exit 0
fi
# shellcheck source=/dev/null
if ! source "$POLICY_FILE" 2>/dev/null; then
  _gate_debug "politica insourceavel, degradando"
  exit 0
fi

# Defaults só para o caso de política PARCIAL (variável ausente, não vazia:
# `${VAR-}` e não `${VAR:-}`). A denylist é a exceção: uma política truncada
# não pode desarmar a autoproteção do ADR-003 v1.1 / review P1-3.
GATE_MODE="${MAESTRO_GATE_MODE-warn}"
[[ "$GATE_MODE" == "warn" || "$GATE_MODE" == "block" ]] || GATE_MODE="warn"
ALLOW_EXT="${MAESTRO_GATE_ALLOW_EXT-}"
ALLOW_PATHS="${MAESTRO_GATE_ALLOW_PATHS-}"
# Defaults conservadores para o caso de a policy não ter sido compilada ainda.
# paths = universais (qualquer projeto); self = só ancorados no plugin root.
DENY_PATHS="${MAESTRO_GATE_DENY_PATHS-.claude/ .github/workflows/}"
ORDER_FROZEN="${MAESTRO_GATE_ORDER_FROZEN-}"
DENY_SELF="${MAESTRO_GATE_DENY_SELF-agents/ bin/ src/ hooks/ config/routing-table.yaml .claude-plugin/}"
PLUGIN_ROOT="${MAESTRO_PLUGIN_ROOT-}"
# A autoproteção só age ancorada na raiz do plugin. Se a política não foi
# compilada ainda (ou veio parcial), derivamos a raiz da localização do próprio
# gate — ele mora dentro do plugin. Sem isso, política ausente desarmaria a
# autoproteção inteira, que é justamente o que ela não pode permitir.
if [[ -z "$PLUGIN_ROOT" ]]; then
  _gate_self="${BASH_SOURCE[0]}"
  _gate_self_dir="${_gate_self%/*}"
  [[ "$_gate_self_dir" == "$_gate_self" ]] && _gate_self_dir="."
  PLUGIN_ROOT="${_gate_self_dir%/*}"
  [[ -z "$PLUGIN_ROOT" ]] && PLUGIN_ROOT="/"
fi

# ── 2. stdin ───────────────────────────────────────────────────────────────
# Leitura sem fork (`read -d ''` consome tudo até EOF).
# Duas defesas contra pendurar o hook — um PreToolUse travado congela a edição
# do usuário, que é pior do que qualquer latência:
#   - stdin em tty: não há payload, degrada na hora;
#   - stdin que nunca fecha: `-t` corta e o parse falha adiante (exit 0).
MAESTRO_GATE_STDIN_TIMEOUT="${MAESTRO_GATE_STDIN_TIMEOUT:-2}"
[[ "$MAESTRO_GATE_STDIN_TIMEOUT" =~ ^[0-9]{1,3}$ ]] || MAESTRO_GATE_STDIN_TIMEOUT=2
PAYLOAD=""
if [[ ! -t 0 ]]; then
  IFS= read -r -d '' -t "$MAESTRO_GATE_STDIN_TIMEOUT" PAYLOAD 2>/dev/null || true
fi
if [[ -z "$PAYLOAD" ]]; then
  _gate_debug "stdin vazio, degradando"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  _gate_debug "jq ausente, degradando"
  exit 0
fi

# Um único fork de jq para os três campos.
#
# Separador: RS (0x1e), não NUL — NUL não sobrevive a `$( )`, e substituição de
# comando é a única leitura em bloco disponível: `read -d`/`mapfile -d` leem
# byte a byte quando a origem é um pipe (num caminho de 22 KB são 22 mil
# syscalls; medido em 25-40ms, quase o NFR inteiro).
# Não se usa @tsv: ele ESCAPA tab/newline, e caminho escapado é caminho
# alterado — seria decisão de gate tomada sobre outra coisa.
# `tool_name` e `session_id` saem truncados: são campos curtos por contrato, e
# o truncamento garante que os três separadores caibam na janela lida abaixo.
# Sentinela "M": se o jq falhar (JSON malformado, topo não-objeto), a saída não
# começa com ela e o hook degrada.
_gate_rs=$'\x1e'
_gate_raw=$(jq -j '
    def s: if type == "string" then . else "" end;
    "M", "\u001e",
    ((.tool_name? // "") | s)[0:64], "\u001e",
    ((.session_id? // "") | s)[0:96], "\u001e",
    ((.tool_input?.file_path? // "") | s), "\u001e"
  ' <<< "$PAYLOAD" 2>/dev/null) || _gate_raw=""

# A JANELA é o truque de desempenho: `${v%%pat*}` e `${v#*pat}` são O(n²) em
# bash (medido: 600ms num caminho de 22 KB). Só a cabeça — sentinela, tool e
# session_id, todos curtos — passa por casamento de padrão; o caminho sai por
# offset, uma cópia só.
_gate_head="${_gate_raw:0:256}"
if [[ "$_gate_head" != "M$_gate_rs"*"$_gate_rs"*"$_gate_rs"* ]]; then
  _gate_debug "json malformado ou campo fora do formato, degradando"
  exit 0
fi
_gate_head="${_gate_head#M"$_gate_rs"}"
TOOL="${_gate_head%%"$_gate_rs"*}"
_gate_head="${_gate_head#*"$_gate_rs"}"
SID="${_gate_head%%"$_gate_rs"*}"
# 4 = "M" + os três separadores que antecedem o caminho.
FPATH="${_gate_raw:$(( 4 + ${#TOOL} + ${#SID} ))}"
FPATH="${FPATH%"$_gate_rs"}"

if [[ -z "$FPATH" ]]; then
  _gate_debug "file_path ausente, degradando"
  exit 0
fi

# Extensão — a ÚNICA informação do caminho que pode ser logada (CONTRATO §1).
# Dotfile sem segunda extensão (`.gitignore`) não tem extensão.
EXT=""
_gate_base="${FPATH##*/}"
# `?*.*` exige ao menos um caractere ANTES do ponto: `a.go` tem extensão,
# `.gitignore` não tem (o nome inteiro não é extensão), `.bashrc.bak` tem `.bak`.
if [[ "$_gate_base" == ?*.* ]]; then
  EXT=".${_gate_base##*.}"
fi
EXT="${EXT,,}"
[[ "$EXT" =~ ^\.[a-z0-9]{1,12}$ ]] || EXT=""

# Argumentos de log: só pares que a common.sh aceita — par inválido geraria
# aviso no stderr do hook, ruído visível para o usuário.
LOG_ARGS=()
if [[ "$TOOL" =~ ^[A-Za-z]{1,32}$ ]]; then LOG_ARGS+=("tool=$TOOL"); fi
if [[ -n "$EXT" ]]; then LOG_ARGS+=("file_ext=$EXT"); fi
if [[ "$SID" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then LOG_ARGS+=("session_id=$SID"); fi

# Caminho normalizado + posição relativa à raiz do projeto.
#
# Caminho patológico (acima do teto): normalizar custaria centenas de ms.
# Duas situações, tratadas diferente para não punir o inocente:
#   - "limpo" (sem `.`, `..` ou `//`): já ESTÁ canônico — casa direto, exato,
#     custo zero. É o caso de um caminho apenas muito profundo.
#   - "sujo": longo E enfeitado com travessia. Não dá para saber onde ele
#     aterrissa sem normalizar, então cai na checagem conservadora da denylist.
LONG=""
if [[ ${#FPATH} -gt $MAESTRO_GATE_MAX_PATH ]]; then
  if [[ "/$FPATH/" == *"/../"* || "/$FPATH/" == *"/./"* || "$FPATH" == *"//"* ]]; then
    LONG="dirty"
  else
    LONG="clean"
  fi
fi

if [[ -n "$LONG" ]]; then
  ABS="$FPATH"
  if [[ "$ABS" != /* ]]; then
    _gate_projbase="${CLAUDE_PROJECT_DIR:-$PWD}"
    [[ "$_gate_projbase" == /* ]] || _gate_projbase="$PWD"
    ABS="$_gate_projbase/$ABS"
  fi
else
  _gate_normalize "$FPATH" || true
  ABS="$_gate_norm"
fi

PROJ=""
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  _gate_normalize "$CLAUDE_PROJECT_DIR" || true
  PROJ="$_gate_norm"
fi
# Raiz como projeto tornaria QUALQUER caminho "relativo à raiz do projeto" e a
# denylist casaria fora do repo — trata-se como projeto indefinido.
if [[ "$PROJ" == "/" ]]; then PROJ=""; fi

REL=""
if [[ -n "$PROJ" && "$ABS" == "$PROJ"/* ]]; then
  REL="${ABS#"$PROJ"/}"
fi

# ── 3. denylist → block SEMPRE (mesmo com decisão registrada) ──────────────
# (a) prefixos relativos à raiz do projeto: nunca casam trabalho legítimo em
#     OUTRO repo — `agents/` de um projeto alheio fica fora do REL.
# (b) proteção absoluta de tudo sob o plugin: o mecanismo de enforcement se
#     protege esteja onde estiver (review P1-3).
DENIED=""
DENIED_PLUGIN_REL=""
if _gate_prefix_match "$REL" "$DENY_PATHS"; then DENIED="1"; fi
# (c) caminho patológico "sujo": não foi normalizado, então o prefixo acima não
#     é confiável — vale a checagem conservadora em qualquer posição.
if [[ -z "$DENIED" && "$LONG" == "dirty" ]]; then
  if _gate_deny_anywhere "$ABS" "$DENY_PATHS $DENY_SELF"; then DENIED="1"; fi
fi
if [[ -z "$DENIED" && -n "$PLUGIN_ROOT" ]]; then
  _gate_normalize "$PLUGIN_ROOT" || true
  _gate_proot="$_gate_norm"
  if [[ -n "$_gate_proot" && "$_gate_proot" != "/" && "$ABS" == "$_gate_proot"/* ]]; then
    # Só os MESMOS prefixos da denylist, agora ancorados no plugin — não a
    # árvore inteira. Proteger tudo sob o plugin root bloquearia até o
    # README.md e o docs/ do próprio repo, tornando o dogfood do Maestro no
    # Maestro inviável; e o que o ADR-003 v1.1 manda proteger é o caminho de
    # enforcement (hooks, CLI, roster, routing table), não cada arquivo.
    # Vindo de OUTRO projeto, isto continua barrando quem tentar reescrever o
    # plugin instalado em ~/.claude/plugins/ (review P1-3).
    if _gate_prefix_match "${ABS#"$_gate_proot"/}" "$DENY_SELF $DENY_PATHS"; then
      DENIED="1"
      DENIED_PLUGIN_REL="${ABS#"$_gate_proot"/}"
    fi
  fi
fi

# ── 3b. consentimento (E10/S-1005, ADR-003 v1.2) ───────────────────────────
# Consentimento explícito do humano (maestro consent --grant) levanta a
# denylist SÓ para DADOS — routing table e roster — e SÓ no ramo ancorado no
# plugin (caminho normalizado; o ramo "dirty" nunca é consentível). hooks/,
# bin/, src/ e .claude-plugin/ não têm escopo mapeado: nenhum arquivo de
# consentimento, forjado ou não, os destrava. TTL curto; arquivo malformado
# falha FECHADO (bloqueia). O resto do gate segue valendo — consent não é
# bypass do decision record.
if [[ -n "$DENIED" && -n "${DENIED_PLUGIN_REL:-}" ]]; then
  _gate_scope=""
  case "$DENIED_PLUGIN_REL" in
    config/routing-table.yaml) _gate_scope="routing-table" ;;
    agents/*)                  _gate_scope="roster" ;;
  esac
  if [[ -n "$_gate_scope" && -f "$MAESTRO_HOME/consents/$_gate_scope" ]]; then
    _gate_exp=$(awk -F= '/^expires=/ { print $2; exit }'       "$MAESTRO_HOME/consents/$_gate_scope" 2>/dev/null)
    if [[ "$_gate_exp" =~ ^[0-9]+$ ]] && (( _gate_exp > $(maestro_now_epoch) )); then
      DENIED=""
      LOG_ARGS+=("scope=$_gate_scope")
    fi
  fi
fi

if [[ -n "$DENIED" ]]; then
  # A mensagem sai ANTES do log de propósito: `log_event` da common.sh termina
  # com `exec 9>&- 2>/dev/null`, e um `exec` sem comando aplica a redireção ao
  # shell inteiro — depois dele o stderr do hook vira /dev/null e a mensagem
  # instrutiva (que o Claude Code devolve ao modelo no exit 2) se perderia.
  cat >&2 <<'EOF'
maestro: edição bloqueada — este caminho é protegido pela denylist de
autoproteção do Maestro (ADR-003 v1.1): roteador, roster, gate, CLI e configs
executáveis não são reescritos por agente, nem com decisão registrada.
Se a alteração é intencional, peça ao humano responsável para aplicá-la.
EOF
  log_event gate_block "${LOG_ARGS[@]}" "gate_mode=$GATE_MODE"
  exit 2
fi

# ── 3c. frozen zones de work orders (E15/S-1504, padrão BMAD) ──────────────
# Zona congelada por ordem NÃO-aceita: em fluxo AUTÔNOMO (subagent/multi)
# bloqueia — o executor da ordem não pode tocar o que a ordem congelou, e
# outro agente também não sem coordenação; com humano no volante (direct/sem
# record), avisa e deixa passar (mesma assimetria do guarda destrutivo S-502).
if [[ -n "$ORDER_FROZEN" ]] && _gate_prefix_match "$REL" "$ORDER_FROZEN"; then
  _fz_mode=""
  if [[ -n "$SID" ]]; then
    _fz_rec="$MAESTRO_SESSIONS_DIR/$SID.json"
    _fz_json=""
    IFS= read -r -d '' -n 4096 _fz_json < "$_fz_rec" 2>/dev/null || true
    [[ "$_fz_json" =~ \"mode\":\"(subagent|multi)\" ]] && _fz_mode="${BASH_REMATCH[1]}"
  fi
  if [[ -n "$_fz_mode" ]]; then
    printf '%s\n' >&2 \
      "maestro: edição bloqueada — este caminho está em ZONA CONGELADA por uma" \
      "work order pendente deste projeto (maestro order --list). Zonas congeladas" \
      "existem para o trabalho paralelo não pisar no contrato da ordem. Termine a" \
      "ordem, ou peça ao humano para editar a ordem e descongelar a zona."
    log_event gate_block "${LOG_ARGS[@]}" "cmd=frozen_zone" "gate_mode=block"
    exit 2
  fi
  printf 'maestro: aviso — editando ZONA CONGELADA por work order pendente (maestro order --list); com humano no volante segue, mas coordene com a ordem.\n' >&2
  log_event gate_warn "${LOG_ARGS[@]}" "cmd=frozen_zone" "gate_mode=warn"
fi

# ── 4. allowlist de não-código → passa sem exigir decisão ──────────────────
# Extensão OU caminho: `.md` em qualquer lugar, mais tudo sob os caminhos
# permitidos. A allowlist de extensões é estreita de propósito (review P1-3:
# .json/.yaml/.toml não são "não-código" — package.json tem `scripts`).
if _gate_ext_match "$EXT" "$ALLOW_EXT" || _gate_prefix_match "$REL" "$ALLOW_PATHS"; then
  exit 0
fi

# ── 5. decision record válido e não expirado (TTL 4h) ──────────────────────
if [[ -n "$SID" ]] && maestro_record_valid "$SID"; then
  # ── E14/S-1402: orçamento declarado — AND-of-caps, WARN-ONLY, 1 aviso/cap ──
  # steps = gate_pass acumulado (contador próprio; ler o log no hot path
  # estouraria o NFR); minutes = agora - ts do record. cents é declarativo (o
  # hook não enxerga custo) — vive no record para o retro correlacionar.
  # Estouro NUNCA bloqueia: orçamento é sinal de deriva, não trava (pesquisa
  # RAD, Contract 2). Falha de qualquer parte degrada em silêncio.
  _b_rec="$MAESTRO_SESSIONS_DIR/$SID.json"
  _b_json=""
  IFS= read -r -d '' -n 4096 _b_json < "$_b_rec" 2>/dev/null || true
  if [[ "$_b_json" == *'"budget"'* ]]; then
    _b_steps=""; _b_min=""
    [[ "$_b_json" =~ \"steps\":([0-9]{1,4}) ]] && _b_steps="${BASH_REMATCH[1]}"
    [[ "$_b_json" =~ \"minutes\":([0-9]{1,4}) ]] && _b_min="${BASH_REMATCH[1]}"
    _b_cnt_f="$MAESTRO_SESSIONS_DIR/budget-$SID"
    _b_cnt=0; _b_warned=""
    if [[ -f "$_b_cnt_f" ]]; then
      IFS=$'\t' read -r _b_cnt _b_warned < "$_b_cnt_f" 2>/dev/null || true
      [[ "$_b_cnt" =~ ^[0-9]+$ ]] || _b_cnt=0
    fi
    _b_cnt=$(( _b_cnt + 1 ))
    if [[ -n "$_b_steps" && $_b_cnt -gt $_b_steps && "$_b_warned" != *s* ]]; then
      _b_warned+="s"
      printf 'maestro: orçamento — passo %s de %s declarados: a sessão passou do plano. Continue se fizer sentido, mas diga ao humano que estourou.\n' \
        "$_b_cnt" "$_b_steps" >&2
      log_event budget_warn "${LOG_ARGS[@]}" "cap=steps"
    fi
    if [[ -n "$_b_min" && "$_b_warned" != *m* ]]; then
      _b_ts=""
      [[ "$_b_json" =~ \"ts\":\"([0-9T:+-]{19,25})\" ]] && _b_ts="${BASH_REMATCH[1]}"
      if [[ -n "$_b_ts" ]]; then
        _b_start=$(date -d "$_b_ts" +%s 2>/dev/null) || _b_start=""
        if [[ "$_b_start" =~ ^[0-9]+$ ]] && \
           (( ( $(maestro_now_epoch) - _b_start ) / 60 > _b_min )); then
          _b_warned+="m"
          printf 'maestro: orçamento — janela de %smin declarada estourou. Continue se fizer sentido, mas diga ao humano.\n' "$_b_min" >&2
          log_event budget_warn "${LOG_ARGS[@]}" "cap=minutes"
        fi
      fi
    fi
    printf '%s\t%s\n' "$_b_cnt" "$_b_warned" > "$_b_cnt_f.tmp.$$" 2>/dev/null \
      && mv -f "$_b_cnt_f.tmp.$$" "$_b_cnt_f" 2>/dev/null || rm -f "$_b_cnt_f.tmp.$$" 2>/dev/null || :
  fi
  log_event gate_pass "${LOG_ARGS[@]}"
  exit 0
fi

# ── 6. sem decisão: warn (default) ou block ────────────────────────────────
if [[ "$GATE_MODE" == "block" ]]; then
  cat >&2 <<'EOF'
maestro: edição bloqueada — nenhuma decisão de roteamento registrada para esta
sessão (ou a decisão expirou; TTL 4h).
Registre antes de editar código:
  maestro decide --session <session_id> --workflow <fix|feature|refactor|ship|audit|custom> \
                 --mode <direct|subagent|multi> [--agents a,b] [--reason "..."]
O <session_id> foi injetado no bloco <maestro-routing> no início da sessão.
EOF
  log_event gate_block "${LOG_ARGS[@]}" "gate_mode=block"
  exit 2
fi

cat >&2 <<'EOF'
maestro: aviso — editando código sem decisão de roteamento registrada
(modo warn: a edição segue, o evento fica no log).
Registre a decisão:
  maestro decide --session <session_id> --workflow <fix|feature|refactor|ship|audit|custom> \
                 --mode <direct|subagent|multi> [--agents a,b] [--reason "..."]
EOF
log_event gate_warn "${LOG_ARGS[@]}" "gate_mode=warn"
exit 0
