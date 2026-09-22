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
# Exceção estreita do roster (ordem 039): agents/*.md abre SÓ para os campos
# de frontmatter `effort` (baixo|alto) e `omitClaudeMd` (true|false), e só
# eles — decisão do Capitão 01M325GBZFYMNFV9A44KJTYMSJ (2026-09-22, Ponte),
# emendando o INTENT (§Limites). Mecanismo: EQUIVALÊNCIA POR REMOÇÃO — tirando
# de AMBOS os lados as linhas das duas chaves, o resto tem de ser
# byte-idêntico. Falha FECHADA em qualquer ramo (payload sem os campos certos,
# arquivo ilegível/grande demais, `old_string` que não casa ou casa mais de
# uma vez, valor fora da gramática fechada, mudança fora do frontmatter, ou
# tool que não seja Edit/Write): a chamadora simplesmente não concede a
# exceção, e o bloqueio normal da denylist (adiante) prevalece. Não é bypass
# de nada — é um caminho A MAIS, automático e mais estreito que o
# `consent --grant roster` já existente (que continua intacto, ver 3b).
#
# CUSTO (medido; NFR do gate é 50ms): o driver de custo aqui são forks de
# `jq` (~9-10ms cada nesta classe de máquina) — por isso no máximo 2 por
# invocação (Edit: old_string + new_string; Write: content), nunca mais.
# Conteúdo grande NUNCA passa por herestring/process-substitution — medido
# ~20-28ms em 8KB nesta forge (mesma classe do "pipe lê byte-a-byte" já
# documentado em hooks/lib/common.sh para o stdin do próprio gate); em vez
# disso, todo conteúdo vira linhas via um arquivo de rascunho REAL
# (`printf > arquivo` + `mapfile < arquivo`, ambos builtin, sem fork, e um
# arquivo comum é sempre lido em bloco, nunca byte-a-byte) — medido 0ms no
# mesmo conteúdo de 8KB. O arquivo do roster em si é lido com `read -d ''`
# limitado a MAESTRO_GATE_ROSTER_MAX_BYTES+1 (builtin, sem fork, sem ler além
# do teto mesmo se o arquivo em disco for maior).
MAESTRO_GATE_ROSTER_MAX_BYTES="${MAESTRO_GATE_ROSTER_MAX_BYTES:-8192}"
_gate_roster_key_re='^(effort|omitClaudeMd):'
_gate_roster_grammar_re='^(effort: (baixo|alto)|omitClaudeMd: (true|false))$'
# rascunho PID-escopado, reaproveitado só DENTRO desta invocação do hook —
# sem mktemp (fork evitado); apagado no fim de _gate_roster_frontmatter_ok.
_gate_roster_scratch="${TMPDIR:-/tmp}/.maestro-gate-roster-$$"
_gate_roster_cleanup() { rm -f "$_gate_roster_scratch" 2>/dev/null || :; }

_gate_read_capped() {  # $1=arquivo -> $_gate_content; rc=1 se ilegível/>teto
  local f="$1" content=""
  [[ -f "$f" && -r "$f" ]] || { _gate_content=""; return 1; }
  IFS= read -r -d '' -n "$(( MAESTRO_GATE_ROSTER_MAX_BYTES + 1 ))" content < "$f" 2>/dev/null
  if (( ${#content} > MAESTRO_GATE_ROSTER_MAX_BYTES )); then _gate_content=""; return 1; fi
  _gate_content="$content"
  return 0
}

# .tool_input.<campo> do $PAYLOAD — string obrigatória, senão rc=1 (falha
# fechada: campo ausente, null, número, array etc. nunca vira "casou vazio").
_gate_jq_str_field() {  # $1=expressão jq -> $_gate_jf
  local out=""
  out=$(jq -j --exit-status "
    (${1}?) as \$v |
    if (\$v == null) or ((\$v|type) != \"string\") then error(\"bad\") else \$v end
  " <<< "$PAYLOAD" 2>/dev/null) || { _gate_jf=""; return 1; }
  (( ${#out} <= MAESTRO_GATE_ROSTER_MAX_BYTES )) || { _gate_jf=""; return 1; }
  _gate_jf="$out"
  return 0
}

# string -> array de linhas, via o arquivo de rascunho (nunca herestring —
# ver nota de custo acima).
_gate_roster_lines_from_str() {  # $1=conteúdo $2=nome do array destino
  local -n _dst="$2"
  printf '%s' "$1" > "$_gate_roster_scratch" 2>/dev/null
  _dst=()
  mapfile -t _dst < "$_gate_roster_scratch" 2>/dev/null || :
}

# localiza a única ocorrência CONTÍGUA de $1 (array de linhas) dentro de $2
# (idem) — publica $_gate_loc_count (0/1/N) e $_gate_loc_start (índice
# 0-based da primeira linha do match, só válido quando count==1). É assim que
# `old_string` "casa" com o arquivo: por LINHAS inteiras, nunca por
# substring bruta — old_string/new_string fragmentado no meio de uma linha
# não é o caso de uso real do Edit tool para trocar valor de chave YAML, e
# tratá-lo como "não casa" (falha fechada) é a escolha segura.
_gate_roster_locate() {
  local -n _needle="$1" _hay="$2"
  local nk="${#_needle[@]}" nh="${#_hay[@]}" i j ok
  _gate_loc_count=0
  _gate_loc_start=-1
  (( nk > 0 && nk <= nh )) || return 0
  for (( i = 0; i + nk <= nh; i++ )); do
    ok=1
    for (( j = 0; j < nk; j++ )); do
      [[ "${_hay[i+j]}" == "${_needle[j]}" ]] || { ok=0; break; }
    done
    (( ok == 1 )) || continue
    _gate_loc_count=$(( _gate_loc_count + 1 ))
    (( _gate_loc_count == 1 )) && _gate_loc_start=$i
  done
}

# equivalência por remoção sobre um ARRAY de linhas: publica $_gate_stripped
# (as linhas que sobram, unidas por \n) e $_gate_removed (as linhas
# retiradas, uma por linha) — iteração de array, nunca padrão glob sobre
# string grande (armadilha conhecida: `${x##*"$pat"}`/`${x%%"$pat"*}` em
# conteúdo de alguns KB já mediu dezenas de ms neste mesmo sandbox).
_gate_roster_strip_lines() {  # $1=nome do array de linhas
  local -n _src="$1"
  local line first=1
  _gate_stripped=""
  _gate_removed=""
  for line in "${_src[@]}"; do
    if [[ "$line" =~ $_gate_roster_key_re ]]; then
      _gate_removed+="$line"$'\n'
    else
      if (( first == 1 )); then _gate_stripped="$line"; first=0
      else _gate_stripped+=$'\n'"$line"; fi
    fi
  done
}

# linha de fechamento do frontmatter (1-based) de um array de linhas: a
# linha 1 tem de ser exatamente "---" e precisa existir uma segunda linha
# "---" mais adiante. $_gate_fm_close=0 (rc=1) se o arquivo não tem
# frontmatter válido — sem isso, nada pode estar "dentro" dele.
_gate_roster_fm_close() {  # $1=nome do array
  local -n _a="$1"
  _gate_fm_close=0
  (( ${#_a[@]} >= 2 )) || return 1
  [[ "${_a[0]}" == "---" ]] || return 1
  local i
  for (( i = 1; i < ${#_a[@]}; i++ )); do
    if [[ "${_a[i]}" == "---" ]]; then _gate_fm_close=$(( i + 1 )); return 0; fi
  done
  return 1
}

# TODA linha que mencione effort:/omitClaudeMd: (mudada ou não) tem de estar
# dentro do frontmatter — mais estrito que checar só a linha alterada, e
# mais simples/seguro (não precisa alinhar diffs entre antes/depois).
_gate_roster_keys_in_frontmatter() {  # $1=nome do array
  local -n _a="$1"
  _gate_roster_fm_close "$1" || return 1
  local close="$_gate_fm_close" i
  for (( i = 0; i < ${#_a[@]}; i++ )); do
    if [[ "${_a[i]}" =~ $_gate_roster_key_re ]]; then
      local ln=$(( i + 1 ))
      (( ln > 1 && ln < close )) || return 1
    fi
  done
  return 0
}

# monta o array "depois" a partir do Edit (old_string/new_string do
# $PAYLOAD contra $1=nome do array "antes"): localiza old_string em disk
# (única ocorrência, por linhas inteiras) e substitui por new_string no
# lugar. $2=nome do array de saída. rc=1 falha fechado em qualquer ramo.
_gate_roster_build_edit_after() {  # $1=array disk_lines  $2=array de saída
  local -n _disk="$1" _out="$2"
  _gate_jq_str_field '.tool_input.old_string' || return 1
  local old="$_gate_jf"
  _gate_jq_str_field '.tool_input.new_string' || return 1
  local new="$_gate_jf"
  [[ -n "$old" ]] || return 1
  local -a old_lines=() new_lines=()
  _gate_roster_lines_from_str "$old" old_lines
  _gate_roster_lines_from_str "$new" new_lines
  _gate_roster_locate old_lines _disk
  (( _gate_loc_count == 1 )) || return 1
  local start="$_gate_loc_start" nk="${#old_lines[@]}" i
  _out=()
  for (( i = 0; i < start; i++ )); do _out+=("${_disk[i]}"); done
  for (( i = 0; i < ${#new_lines[@]}; i++ )); do _out+=("${new_lines[i]}"); done
  for (( i = start + nk; i < ${#_disk[@]}; i++ )); do _out+=("${_disk[i]}"); done
  return 0
}

# gramática fechada em toda linha removida (de qualquer lado) + no máx. 1
# linha de cada chave por lado (sem duplicidade ambígua). $1/$2 são NO
# MÁXIMO umas poucas linhas curtas — herestring aqui não tem o custo do
# conteúdo grande já documentado acima.
_gate_roster_removed_ok() {  # $1=before_removed  $2=after_removed
  local n_eff_b n_omit_b n_eff_a n_omit_a
  _gate_roster_count_keys "$1" || return 1
  n_eff_b="$_gate_n_eff"; n_omit_b="$_gate_n_omit"
  _gate_roster_count_keys "$2" || return 1
  n_eff_a="$_gate_n_eff"; n_omit_a="$_gate_n_omit"
  (( n_eff_b <= 1 && n_omit_b <= 1 && n_eff_a <= 1 && n_omit_a <= 1 ))
}

# conta linhas "effort:"/"omitClaudeMd:" em $1 (um lado só), validando a
# gramática fechada de CADA uma no caminho — publica $_gate_n_eff/$_gate_n_omit.
_gate_roster_count_keys() {  # $1=linhas removidas (de um lado)
  local line
  _gate_n_eff=0; _gate_n_omit=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    [[ "$line" =~ $_gate_roster_grammar_re ]] || return 1
    case "$line" in
      effort:*)        _gate_n_eff=$(( _gate_n_eff + 1 )) ;;
      omitClaudeMd:*)  _gate_n_omit=$(( _gate_n_omit + 1 )) ;;
    esac
  done <<< "$1"
  return 0
}

# ponto de entrada: rc=0 concede a exceção; rc!=0 falha fechado (chamadora
# não altera DENIED). Usa $ABS (caminho já normalizado), $TOOL, $PAYLOAD —
# todos já resolvidos pelo corpo principal do gate antes desta função rodar.
_gate_roster_frontmatter_ok() {
  local file="$ABS"
  _gate_read_capped "$file" || return 1
  local -a disk_lines=() after_lines=()
  _gate_roster_lines_from_str "$_gate_content" disk_lines

  case "$TOOL" in
    Edit)
      _gate_roster_build_edit_after disk_lines after_lines
      local edit_rc=$?
      _gate_roster_cleanup
      (( edit_rc == 0 )) || return 1
      ;;
    Write)
      _gate_jq_str_field '.tool_input.content' || { _gate_roster_cleanup; return 1; }
      local content="$_gate_jf"
      _gate_roster_lines_from_str "$content" after_lines
      _gate_roster_cleanup
      ;;
    *)
      _gate_roster_cleanup; return 1
      ;;
  esac

  _gate_roster_strip_lines disk_lines
  local before_stripped="$_gate_stripped" before_removed="$_gate_removed"
  _gate_roster_strip_lines after_lines
  local after_stripped="$_gate_stripped" after_removed="$_gate_removed"

  [[ "$before_stripped" == "$after_stripped" ]] || return 1
  _gate_roster_removed_ok "$before_removed" "$after_removed" || return 1

  _gate_roster_keys_in_frontmatter disk_lines || return 1
  _gate_roster_keys_in_frontmatter after_lines || return 1

  return 0
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

# ── 3a-bis. worktree do PRÓPRIO plugin (ordem 012, correção pós-suíte) ─────
# PLUGIN_ROOT é gravado como REPO_DIR pelo session-start (hooks/session-start.sh)
# na sessão que compilou a política — o caminho de UMA árvore de trabalho. Um
# `git worktree` do mesmo repositório tem raiz de ARQUIVOS diferente (não bate
# com o prefixo checado acima), mas é a MESMA árvore Git — mesmo endereço de
# enforcement, checkout novo. Sem isto a autoproteção é vencida por mudança de
# endereço (a mesma classe que a decisão A do Lote 0 recusou para lib/), nunca
# removida: o bloco 3a-anchored acima simplesmente nunca casa.
#
# Barato-primeiro: só dispara `git` (fork) quando REL já pareceria autoproteção
# SE este projeto fosse o plugin — casamento de string, sem custo, cobre a
# imensa maioria das edições que não chegam nem perto de bin/hooks/src/agents.
if [[ -z "$DENIED" && -n "$PLUGIN_ROOT" && -n "$PROJ" && -n "$REL" ]] \
   && _gate_prefix_match "$REL" "$DENY_SELF $DENY_PATHS"; then
  _gate_proj_common=""
  _gate_plugin_common=""
  if command -v git >/dev/null 2>&1; then
    _gate_proj_common=$(git -C "$PROJ" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || _gate_proj_common=""
    _gate_plugin_common=$(git -C "$PLUGIN_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || _gate_plugin_common=""
  fi
  # Degradação NEUTRA (a versão anterior deste patch tratava "não deu para
  # saber" como "é a mesma árvore" e ISSO ESTAVA ERRADO — corrigido aqui).
  # Worktree NÃO EXISTE sem git: sem evidência POSITIVA de que as duas árvores
  # são a MESMA, não há cenário de worktree a proteger, então o bloco cai no
  # comportamento PRÉ-EXISTENTE (nem mais restritivo, nem menos — a checagem
  # ancorada de 3a acima, sozinha). Só bloqueia AQUI quando os DOIS
  # `git rev-parse` tiveram sucesso, os dois valores são não-vazios E são
  # iguais — git ausente, projeto que não é repositório, comando falhando ou
  # `--path-format` indisponível caem todos no "não bloqueia aqui", sem
  # marcar DENIED. O caso real que expôs o defeito da versão anterior:
  # tests/hooks/test-gate.sh cria o projeto sintético com `mktemp -d`, sem
  # `git init` — sem esta correção, QUALQUER diretório não-git cujo caminho
  # relativo batesse a denylist (src/, bin/, hooks/…) virava bloqueio
  # universal, o modo de falha oposto ao que esta ordem existe para consertar.
  if [[ -n "$_gate_proj_common" && -n "$_gate_plugin_common" && \
        "$_gate_proj_common" == "$_gate_plugin_common" ]]; then
    DENIED="1"
    DENIED_PLUGIN_REL="$REL"
  fi
fi

# ── 3a-quater. exceção estreita do roster (ordem 039) ──────────────────────
# agents/*.md abre SÓ para `effort`/`omitClaudeMd`, só no frontmatter, só
# Edit/Write, e só por equivalência-por-remoção (ver as funções `_gate_roster_*`
# acima). Roda depois de 3a-anchored E 3a-bis: pega DENIED_PLUGIN_REL de
# qualquer um dos dois ramos que a tenham marcado. Nunca é bypass do
# `consent --grant roster` (3b, abaixo) — é caminho A MAIS, automático,
# mais estreito, e falha fechado em qualquer ambiguidade.
if [[ -n "$DENIED" && -n "${DENIED_PLUGIN_REL:-}" && "$DENIED_PLUGIN_REL" == agents/*.md ]]; then
  case "$TOOL" in
    Edit|Write)
      if command -v jq >/dev/null 2>&1 && _gate_roster_frontmatter_ok; then
        DENIED=""
        LOG_ARGS+=("scope=roster-frontmatter")
        log_event gate_pass "${LOG_ARGS[@]}"
      fi
      ;;
  esac
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
