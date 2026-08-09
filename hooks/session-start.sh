#!/usr/bin/env bash
# maestro hooks/session-start.sh — E2 / S-201
#
# Injeta o bloco <maestro-routing> no contexto da sessão (stdout), compila a
# política do gate para $MAESTRO_HOME/gate-policy.sh (fonte de verdade única:
# config/routing-table.yaml), limpa decision records expirados e rotaciona o log.
#
# REGRAS DURAS (CLAUDE.md + CONTRATO):
#  - bash puro: NUNCA invoca Bun, nunca importa src/. `jq` é opcional aqui.
#  - kill-switch é a primeira coisa executada depois do source.
#  - QUALQUER falha degrada com exit 0 + aviso no stderr. Uma sessão que não
#    abre por causa do Maestro é o pior desfecho possível — nada aqui bloqueia.
#  - orçamento de saída: 8000 bytes (API_SPEC §1, proxy de ~2k tokens).
#    Ordem de truncamento: heurísticas → índice do roster → (rede de segurança)
#    rotas/workflows → profile → bindings → gates humanos. session_id e
#    instrução canônica NUNCA truncam.
#
# S-401 — o bloco `bindings:` do YAML (step → skill:/agent:/native:) é injetado
# como seção própria: é ele que transforma `investigate` de palavra solta em
# comando verificável. Fica ACIMA das rotas na prioridade de orçamento porque é
# instrução de execução; rotas e roster são material de referência.
#
# S-501 — gates humanos. O gate NÃO é hook novo: `workflows.*.gate` vira uma
# instrução curta na injeção ("pare, pergunte, espere resposta"). `gate: plan`
# casa com o plan mode nativo (aprovação de um toque, que é o que torna o gate
# aprovável do telefone); `gate: ship` é confirmação explícita em texto. A lista
# de workflows de cada gate é DERIVADA do YAML — o texto da pergunta é curado
# aqui porque quem responde está no telefone e precisa de 1 palavra.
#
# Overrides de ambiente (usados pelos testes; os defaults valem em produção):
#   MAESTRO_ROUTING_TABLE      caminho do routing-table.yaml
#   MAESTRO_AGENTS_DIR         diretório do roster
#   MAESTRO_INJECTION_BUDGET   teto em bytes da injeção
#   CLAUDE_PROJECT_DIR         raiz do projeto (onde mora o .maestro.yaml)
#
# S-303 — filtro do roster por `experts:` do .maestro.yaml (DATA_MODEL §2).
# Semântica decidida aqui (a spec só fixa o caso feliz; o resto é degradação):
#   `experts` ausente/nulo ....... sem opinião do projeto → roster INTEIRO
#   `experts: [golang-pro]` ...... só os nomes listados que existam no roster
#   `experts: []` ................ intenção explícita de "nenhum" → roster VAZIO
#                                  (a seção continua existindo, dizendo o porquê)
#   nome que não existe no roster  avisa no stderr, ignora o nome e segue com o
#                                  resto da lista — nunca quebra a sessão
#   TODOS os nomes inexistentes .. é erro de config, não intenção: avisa e volta
#                                  ao roster inteiro (perder o roster por causa
#                                  de um typo é pior do que exibi-lo demais)
# O filtro roda ANTES do orçamento de 8000 bytes: declarar `experts` é também a
# forma de caber mais coisa útil na injeção, nunca de estourá-la.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
maestro_killswitch

# LC_ALL=C dá semântica de BYTE para ${#s} e ${s:0:n} — o orçamento do API_SPEC
# é em bytes e o conteúdo é pt-BR (multibyte). Todo corte acontece em fronteira
# de '\n' ou ' ' (ASCII), então nenhum caractere UTF-8 é partido ao meio.
export LC_ALL=C LANG=C

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTING_TABLE="${MAESTRO_ROUTING_TABLE:-$REPO_DIR/config/routing-table.yaml}"
AGENTS_DIR="${MAESTRO_AGENTS_DIR:-$REPO_DIR/agents}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROFILE_FILE="$PROJECT_DIR/.maestro.yaml"

BUDGET="${MAESTRO_INJECTION_BUDGET:-8000}"
[[ "$BUDGET" =~ ^[0-9]{1,7}$ ]] || BUDGET=8000

MARK=$'… (truncado pelo orçamento de injeção)\n'

# Denylist de autoproteção (ADR-003 v1.1). Só entra em cena se o YAML estiver
# ilegível/corrompido: perder a denylist é pior do que uma política levemente
# desatualizada, então ela tem default embutido — a allowlist não tem (allowlist
# vazia só torna o gate mais rigoroso, denylist vazia abriria o próprio Maestro).
DENY_FALLBACK=".claude/ .github/workflows/"
SELF_FALLBACK="agents/ bin/ src/ hooks/ config/routing-table.yaml .claude-plugin/"

warn() { printf 'maestro: session-start: %s\n' "$1" >&2 || :; }

# ---------------------------------------------------------------------------
# 1. session_id — vem do JSON do Claude Code no stdin.
# Regex bash primeiro (zero fork, cobre o payload real), jq como reforço.
# Nunca trava e nunca falha: stdin ausente/tty/lixo → 'desconhecido'.
# ---------------------------------------------------------------------------
SESSION_ID="desconhecido"
SESSION_ID_OK=0
read_session_id() {
  local raw="" sid=""
  if [[ ! -t 0 ]]; then
    # -N limita o consumo; -t evita ficar pendurado num stdin que nunca fecha.
    read -r -t 2 -N 262144 raw || :
  fi
  if [[ -n "$raw" ]] && [[ "$raw" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,64})\" ]]; then
    sid="${BASH_REMATCH[1]}"
  elif [[ -n "$raw" ]] && command -v jq >/dev/null 2>&1; then
    sid=$(printf '%s' "$raw" | jq -r '.session_id // empty' 2>/dev/null) || sid=""
  fi
  [[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || sid="${CLAUDE_SESSION_ID:-}"
  if [[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
    SESSION_ID="$sid"
    SESSION_ID_OK=1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 2. routing-table.yaml — subconjunto necessário extraído com awk (bash puro,
# sem Bun). Formato fixo e simples (DATA_MODEL §1): listas inline `[a, b, c]`.
# NADA que sai daqui é avaliado: cada token passa por regex antes de virar valor
# no gate-policy.sh — que o GATE vai *sourcear*.
# ---------------------------------------------------------------------------
GATE_MODE=""; ALLOW_EXT=""; ALLOW_PATHS=""; DENY_PATHS=""; DENY_SELF=""
HEURISTICS=""; ROUTES=""; WORKFLOWS=""; BINDINGS=""
GATE_PLAN_WFS=""; GATE_SHIP_WFS=""

yaml_inline_list() { # yaml_inline_list "[a, b, c]" <regex-de-token>
  local s="${1:-}" re="${2:-}" out="" tok
  s="${s#*[}"; s="${s%%]*}"
  local IFS=','
  for tok in $s; do
    tok="${tok#"${tok%%[![:space:]]*}"}"
    tok="${tok%"${tok##*[![:space:]]}"}"
    tok="${tok%\"}"; tok="${tok#\"}"; tok="${tok%\'}"; tok="${tok#\'}"
    [[ -n "$tok" ]] || continue
    [[ "$tok" =~ $re ]] || { warn "token descartado da routing table (não passou na validação)"; continue; }
    out="$out $tok"
  done
  printf '%s' "${out# }"
}

# bind_add "<step> <alvo> [<alvo>]" — S-401. Mesmo contrato do yaml_inline_list:
# nada entra na injeção sem passar por regex. Alvo malformado é DESCARTADO com
# aviso (nunca mutilado), e um step sem alvo válido simplesmente não aparece —
# quem grita sobre binding faltando é o `maestro doctor`, não a sessão.
bind_add() {
  local raw="${1:-}" step rest tok out=""
  step="${raw%% *}"; rest="${raw#* }"
  [[ -n "$step" && "$rest" != "$raw" ]] || return 0
  [[ "$step" =~ ^[a-z][a-z0-9-]{0,31}$ ]] \
    || { warn "step com nome inválido no bloco bindings (descartado)"; return 0; }
  for tok in $rest; do
    [[ "$tok" =~ ^(skill|agent|native):[A-Za-z0-9][A-Za-z0-9._-]{0,47}$ ]] \
      || { warn "binding de '$step' descartado (fora de skill:|agent:|native:)"; continue; }
    out+="${out:+ + }$tok"
  done
  [[ -n "$out" ]] || return 0
  BINDINGS+="- $step → $out"$'\n'
  return 0
}

# Gates humanos (S-501): quais workflows declaram `gate: plan` / `gate: ship`.
# Derivado das linhas de workflow já parseadas — o YAML continua sendo a fonte
# única; aqui só se decide o texto da pergunta.
collect_gates() {
  local line name g
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    line="${line#- }"
    name="${line%%:*}"
    [[ "$name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || continue
    [[ "$line" =~ gate:[[:space:]]*([a-z-]{1,16}) ]] || continue
    g="${BASH_REMATCH[1]}"
    case "$g" in
      plan) GATE_PLAN_WFS+="$name, " ;;
      ship) GATE_SHIP_WFS+="$name, " ;;
    esac
  done <<<"$WORKFLOWS"
  GATE_PLAN_WFS="${GATE_PLAN_WFS%, }"; GATE_SHIP_WFS="${GATE_SHIP_WFS%, }"
  return 0
}

parse_routing_table() {
  [[ -f "$ROUTING_TABLE" && -r "$ROUTING_TABLE" ]] || { warn "routing table ilegível ou ausente"; return 1; }
  local key val
  while IFS=$'\t' read -r key val; do
    case "$key" in
      MODE)        GATE_MODE="$val" ;;
      allow_EXT)   ALLOW_EXT=$(yaml_inline_list "$val" '^\.[A-Za-z0-9]{1,12}$') ;;
      allow_PATHS) ALLOW_PATHS=$(yaml_inline_list "$val" '^[A-Za-z0-9._/-]{1,64}$') ;;
      deny_PATHS)  DENY_PATHS=$(yaml_inline_list "$val" '^[A-Za-z0-9._/-]{1,64}$') ;;
      deny_SELF)   DENY_SELF=$(yaml_inline_list "$val" '^[A-Za-z0-9._/-]{1,64}$') ;;
      HEUR)        HEURISTICS+="- $val"$'\n' ;;
      ROUTE)       ROUTES+="- $val"$'\n' ;;
      WORKFLOW)    WORKFLOWS+="- $val"$'\n' ;;
      BIND)        bind_add "$val" ;;
    esac
  done < <(awk '
    function clean(s) { sub(/[ \t]*#.*$/, "", s); gsub(/\t/, " ", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function tidy(s)  { gsub(/\t/, " ", s); gsub(/[{}]/, "", s); gsub(/  +/, " ", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[^ \t#]/ {
      ingate   = ($0 ~ /^gate:[ \t]*(#.*)?$/)                 ? 1 : 0
      inheur   = ($0 ~ /^execution_heuristics:[ \t]*(#.*)?$/) ? 1 : 0
      inroutes = ($0 ~ /^routes:[ \t]*(#.*)?$/)               ? 1 : 0
      inwf     = ($0 ~ /^workflows:[ \t]*(#.*)?$/)            ? 1 : 0
      inbind   = ($0 ~ /^bindings:[ \t]*(#.*)?$/)             ? 1 : 0
      sub_ = ""
      next
    }
    inbind == 1 && /^[ \t]+[a-z][A-Za-z0-9_-]*:/ {
      v = $0; sub(/[ \t]*#.*$/, "", v)
      i = index(v, ":"); k = substr(v, 1, i - 1); r = substr(v, i + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      gsub(/[][,]/, " ", r); r = tidy(r)
      if (k != "" && r != "") print "BIND\t" k " " r
      next
    }
    ingate == 1 {
      if      ($0 ~ /^  mode:/)        { print "MODE\t"        clean(substr($0, 8))  }
      else if ($0 ~ /^  allowlist:/)   { sub_ = "allow" }
      else if ($0 ~ /^  denylist:/)    { sub_ = "deny"  }
      else if ($0 ~ /^    extensions:/ && sub_ != "") { print sub_ "_EXT\t"   clean(substr($0, 16)) }
      else if ($0 ~ /^    paths:/      && sub_ != "") { print sub_ "_PATHS\t" clean(substr($0, 11)) }
      else if ($0 ~ /^    self_paths:/ && sub_ != "") { print sub_ "_SELF\t"  clean(substr($0, 16)) }
      next
    }
    inheur == 1 && /^[ \t]+[^ \t#]/ {
      v = $0; sub(/^[ \t]*-[ \t]*/, "", v); gsub(/^"|"$/, "", v); v = tidy(v)
      if (v != "") print "HEUR\t" v
      next
    }
    inroutes == 1 && /^[ \t]+[^ \t#]/ {
      v = $0; sub(/^[ \t]*-[ \t]*/, "", v); v = tidy(v)
      if (v != "") print "ROUTE\t" v
      next
    }
    inwf == 1 && /^[ \t]+[A-Za-z0-9_-]+:/ {
      v = $0; sub(/[ \t]*#.*$/, "", v); v = tidy(v)
      if (v != "") print "WORKFLOW\t" v
      next
    }
  ' "$ROUTING_TABLE" 2>/dev/null)
  return 0
}

# ---------------------------------------------------------------------------
# 3. Profile do projeto — $CLAUDE_PROJECT_DIR/.maestro.yaml (DATA_MODEL §2).
# Opcional: ausência não é erro, só significa "defaults globais".
# ---------------------------------------------------------------------------
P_PROJECT=""; P_LANGS=""; P_EXPERTS=""; P_PIPELINE=""; P_NOTES=""
# `experts: []` (lista explicitamente vazia) é diferente de `experts` ausente:
# a primeira é uma decisão do projeto, a segunda é silêncio. Só o texto bruto
# distingue as duas, então o flag é levantado aqui, antes da normalização.
P_EXPERTS_EMPTY=0

parse_profile() {
  [[ -f "$PROFILE_FILE" && -r "$PROFILE_FILE" ]] || return 0
  local key val
  while IFS=$'\t' read -r key val; do
    case "$key" in
      PROJECT)  [[ "$val" =~ ^[A-Za-z0-9._-]{1,48}$ ]] && P_PROJECT="$val" ;;
      PIPELINE) [[ "$val" =~ ^[A-Za-z0-9._-]{1,32}$ ]] && P_PIPELINE="$val" ;;
      LANGS)    P_LANGS=$(yaml_inline_list "$val" '^[A-Za-z0-9+._-]{1,24}$') ;;
      EXPERTS)  [[ "$val" =~ ^\[[[:space:]]*\]$ ]] && P_EXPERTS_EMPTY=1
                P_EXPERTS=$(yaml_inline_list "$val" '^[a-z0-9-]{1,40}$') ;;
      NOTES)    P_NOTES="$val" ;;
    esac
  done < <(awk '
    function clean(s) { sub(/[ \t]*#.*$/, "", s); gsub(/\t/, " ", s); gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/^"|"$/, "", s); return s }
    /^project:/   { print "PROJECT\t"  clean(substr($0, 9));  next }
    /^pipeline:/  { print "PIPELINE\t" clean(substr($0, 10)); next }
    /^languages:/ { print "LANGS\t"    clean(substr($0, 11)); next }
    /^experts:/   { print "EXPERTS\t"  clean(substr($0, 9));  next }
    /^notes:/     { v = substr($0, 7); gsub(/\t/, " ", v); gsub(/^[ \t]+|[ \t]+$/, "", v); gsub(/^"|"$/, "", v); print "NOTES\t" v; next }
  ' "$PROFILE_FILE" 2>/dev/null)

  # `notes` é texto livre do usuário: tira o que quebraria o bloco ou o shell.
  if [[ -n "$P_NOTES" ]]; then
    P_NOTES="${P_NOTES//[<>\"\\\`\$]/}"
    P_NOTES="${P_NOTES//$'\r'/}"
    if (( ${#P_NOTES} > 140 )); then
      P_NOTES="${P_NOTES:0:140}"
      P_NOTES="${P_NOTES% *}…"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 4. Índice do roster — agents/*.md (DATA_MODEL §5), filtrado pelo `experts:`
# do projeto (S-303 — semântica documentada no cabeçalho deste arquivo).
# Roster ausente/vazio degrada para um aviso de uma linha, nunca para um erro.
# Um único awk sobre todos os arquivos — N forks quebrariam o NFR de 100ms.
# ---------------------------------------------------------------------------
ROSTER=""            # linhas já filtradas, prontas para a injeção
ROSTER_COUNT=0       # agentes exibidos
ROSTER_TOTAL=0       # agentes lidos de agents/*.md (antes do filtro)
ROSTER_FILTERED=0    # omitidos pelo filtro `experts`
EXPERTS_KEEP=""      # experts declarados QUE existem no roster
EXPERTS_UNKNOWN=""   # experts declarados que não existem — avisados e ignorados
EXPERTS_APPLIED=0    # 1 = o filtro do .maestro.yaml valeu de fato
parse_roster() {
  [[ -d "$AGENTS_DIR" ]] || return 0
  local files=() nm md ds
  shopt -s nullglob
  files=("$AGENTS_DIR"/*.md)
  shopt -u nullglob
  (( ${#files[@]} > 0 )) || return 0

  # Lê o roster inteiro primeiro: sem o conjunto completo de nomes não dá para
  # dizer quais `experts` são inexistentes (e esse aviso é a metade acionável
  # da S-303 — um typo silencioso esconderia o agente sem explicar por quê).
  local names=() lines=()
  while IFS=$'\t' read -r nm md ds; do
    [[ "$nm" =~ ^[a-z0-9-]{1,40}$ ]] || continue
    [[ "$md" =~ ^(haiku|sonnet|opus)$ ]] || md="?"
    names+=("$nm")
    # Só nome + modelo. A DESCRIÇÃO é deliberadamente omitida: o Claude Code já
    # carrega a description de todo agents/*.md always-on (é ela o gate MoE), e
    # repeti-la aqui punha o roster duas vezes no contexto — 1163 dos 2466 bytes
    # da injeção eram redundância pura, medido com o plugin instalado. O modelo,
    # sim, é nosso: o harness não o expõe e ele É a decisão de tiering (ADR-004).
    # A NFR diz que o Maestro não pode causar o inchaço que combate.
    lines+=("- $nm ($md)")
  done < <(awk '
    function clean(s) { gsub(/\t/, " ", s); gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/^"|"$/, "", s); gsub(/[<>]/, "", s); return s }
    FNR == 1 { st = 0; nm = ""; md = ""; ds = "" }
    FNR == 1 && /^---[ \t]*$/ { st = 1; next }
    st == 1 && /^---[ \t]*$/ {
      if (nm != "") {
        if (length(ds) > 100) { ds = substr(ds, 1, 100); sub(/[^ ]*$/, "", ds); ds = ds "…" }
        print nm "\t" md "\t" ds
      }
      st = 2; next
    }
    st == 1 && /^name:/        { nm = clean(substr($0, 6));  next }
    st == 1 && /^model:/       { md = clean(substr($0, 7));  next }
    st == 1 && /^description:/ { ds = clean(substr($0, 13)); next }
  ' "${files[@]}" 2>/dev/null)

  ROSTER_TOTAL=${#names[@]}
  (( ROSTER_TOTAL > 0 )) || return 0

  # --- filtro do .maestro.yaml (S-303) --------------------------------------
  local all=" ${names[*]} " e i
  if [[ -n "$P_EXPERTS" ]]; then
    for e in $P_EXPERTS; do
      if [[ "$all" == *" $e "* ]]; then
        [[ " $EXPERTS_KEEP " == *" $e "* ]] || EXPERTS_KEEP+="$e "
      else
        EXPERTS_UNKNOWN+="$e "
      fi
    done
    EXPERTS_KEEP="${EXPERTS_KEEP% }"; EXPERTS_UNKNOWN="${EXPERTS_UNKNOWN% }"
    [[ -n "$EXPERTS_UNKNOWN" ]] \
      && warn "experts do .maestro.yaml que não existem no roster, ignorado(s): ${EXPERTS_UNKNOWN// /, }"
    if [[ -n "$EXPERTS_KEEP" ]]; then
      EXPERTS_APPLIED=1
    else
      warn "nenhum expert declarado existe no roster; injetando o roster inteiro"
    fi
  elif (( P_EXPERTS_EMPTY == 1 )); then
    # `experts: []` é decisão explícita do projeto, não erro de digitação.
    EXPERTS_APPLIED=1
  fi

  for i in "${!names[@]}"; do
    if (( EXPERTS_APPLIED == 1 )) && [[ " $EXPERTS_KEEP " != *" ${names[i]} "* ]]; then
      ROSTER_FILTERED=$(( ROSTER_FILTERED + 1 ))
      continue
    fi
    ROSTER+="${lines[i]}"$'\n'
    ROSTER_COUNT=$(( ROSTER_COUNT + 1 ))
  done
  return 0
}

# ---------------------------------------------------------------------------
# 5. Compilação da política do gate (CONTRATO §2). Escrita atômica (tmp + mv):
# o GATE nunca vê um arquivo pela metade.
# ---------------------------------------------------------------------------
GATE_MODE_EFFECTIVE="warn"
write_gate_policy() {
  local mode="$GATE_MODE" deny="$DENY_PATHS" self="$DENY_SELF"
  if [[ ! "$mode" =~ ^(warn|block)$ ]]; then
    [[ -n "$mode" ]] && warn "gate.mode inválido no YAML; assumindo 'warn'"
    mode="warn"
  fi
  if [[ -z "$deny" ]]; then
    warn "denylist.paths ausente/ilegível no YAML; usando a embutida"
    deny="$DENY_FALLBACK"
  fi
  if [[ -z "$self" ]]; then
    warn "denylist.self_paths ausente/ilegível no YAML; usando a autoproteção embutida"
    self="$SELF_FALLBACK"
  fi
  GATE_MODE_EFFECTIVE="$mode"

  maestro_ensure_dirs
  local dst="$MAESTRO_HOME/gate-policy.sh" tmp="$MAESTRO_HOME/.gate-policy.$$.tmp"
  {
    printf '# gerado por maestro session-start — nao editar\n'
    printf 'MAESTRO_GATE_MODE="%s"\n'        "$mode"
    printf 'MAESTRO_GATE_ALLOW_EXT="%s"\n'   "$ALLOW_EXT"
    printf 'MAESTRO_GATE_ALLOW_PATHS="%s"\n' "$ALLOW_PATHS"
    printf 'MAESTRO_GATE_DENY_PATHS="%s"\n'  "$deny"
    printf 'MAESTRO_GATE_DENY_SELF="%s"\n'   "$self"
    printf 'MAESTRO_PLUGIN_ROOT="%s"\n'      "$REPO_DIR"
  } >"$tmp" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null || :
    warn "falha ao escrever gate-policy.sh (gate degrada para exit 0)"
    return 0
  }
  chmod 0644 "$tmp" 2>/dev/null || :
  mv -f "$tmp" "$dst" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null || :
    warn "falha ao publicar gate-policy.sh"
  }
  return 0
}

# ---------------------------------------------------------------------------
# 6. Limpeza de decision records expirados (TTL 4h) + rotação do log.
# maestro_record_valid é a fonte de verdade do TTL (expires_at, fallback mtime);
# maestro_rotate_log cuida do 10MB. Nada disso é reimplementado aqui.
# ---------------------------------------------------------------------------
cleanup_records() {
  maestro_ensure_dirs
  local f base sid
  shopt -s nullglob
  for f in "$MAESTRO_SESSIONS_DIR"/*.json; do
    base="${f##*/}"; sid="${base%.json}"
    maestro_record_valid "$sid" || rm -f "$f" 2>/dev/null || :
  done
  shopt -u nullglob
  maestro_rotate_log
  return 0
}

# ---------------------------------------------------------------------------
# 7. Montagem do bloco + orçamento de 8000 bytes.
# ---------------------------------------------------------------------------
build_and_emit() {
  local sec_head sec_instr sec_gate sec_bind sec_profile sec_routes sec_heur sec_roster sec_tail

  sec_head="<maestro-routing>"$'\n'
  sec_head+="Maestro v0.1 — roteamento MoE. Kill-switch: MAESTRO_OFF=1."$'\n'
  if (( SESSION_ID_OK == 1 )); then
    sec_head+="session_id: $SESSION_ID"$'\n'
  else
    sec_head+="session_id: $SESSION_ID (não veio no stdin do hook — confirme o id real antes de registrar)"$'\n'
  fi

  sec_instr=$'\n'"INSTRUÇÃO CANÔNICA — antes de editar código nesta sessão, registre a decisão:"$'\n'
  sec_instr+="  maestro decide --session $SESSION_ID --workflow <fix|feature|refactor|ship|audit|custom> --mode <direct|subagent|multi> [--agents a,b] [--reason \"por quê\"]"$'\n'
  sec_instr+="Sem decision record válido, o gate registra aviso em toda edição (gate.mode: $GATE_MODE_EFFECTIVE)."$'\n'

  # S-501 — gate humano. Duas linhas no máximo: quem aprova está no telefone,
  # então a instrução precisa caber num olhar e a pergunta ser de uma palavra.
  sec_gate=""
  if [[ -n "$GATE_PLAN_WFS$GATE_SHIP_WFS" ]]; then
    sec_gate=$'\n'"## Gates humanos — PARE, pergunte e espere resposta explícita."$'\n'
    [[ -n "$GATE_PLAN_WFS" ]] && sec_gate+="- gate plan ($GATE_PLAN_WFS): entre em plan mode, plano em ≤10 linhas, pergunte \"Aprovo o plano? (aprovo | ajusta: …)\" — nenhuma edição de código antes do aprovo."$'\n'
    [[ -n "$GATE_SHIP_WFS" ]] && sec_gate+="- gate ship ($GATE_SHIP_WFS): liste em ≤5 linhas o que vai sair e pergunte \"Shipo agora? (shipa | espera)\" — sem resposta, não shipa."$'\n'
  fi

  # S-401 — o step deixa de ser palavra solta.
  sec_bind=""
  if [[ -n "$BINDINGS" ]]; then
    sec_bind=$'\n'"## Bindings (step → o que roda; \"a + b\" = método + quem executa). Siga o binding."$'\n'"$BINDINGS"
  fi

  sec_profile=""
  if [[ -n "$P_PROJECT$P_LANGS$P_EXPERTS$P_PIPELINE$P_NOTES" ]] || (( P_EXPERTS_EMPTY == 1 )); then
    sec_profile=$'\n'"## Profile do projeto (.maestro.yaml)"$'\n'
    [[ -n "$P_PROJECT"  ]] && sec_profile+="projeto: $P_PROJECT"$'\n'
    [[ -n "$P_LANGS"    ]] && sec_profile+="linguagens: ${P_LANGS// /, }"$'\n'
    [[ -n "$P_PIPELINE" ]] && sec_profile+="pipeline: $P_PIPELINE"$'\n'
    # O que sai aqui é o filtro EFETIVO, não o texto cru do YAML: o Claude só
    # deve ver como ativo o que realmente sobreviveu ao cruzamento com o roster.
    if (( EXPERTS_APPLIED == 1 )); then
      if [[ -n "$EXPERTS_KEEP" ]]; then
        sec_profile+="experts ativos: ${EXPERTS_KEEP// /, }"$'\n'
      else
        sec_profile+="experts ativos: nenhum (experts: [] declarado no projeto)"$'\n'
      fi
      [[ -n "$EXPERTS_UNKNOWN" ]] \
        && sec_profile+="experts ignorados (fora do roster): ${EXPERTS_UNKNOWN// /, }"$'\n'
    elif [[ -n "$P_EXPERTS" ]]; then
      if (( ROSTER_TOTAL > 0 )); then
        sec_profile+="experts declarados: ${P_EXPERTS// /, } (nenhum existe no roster — filtro ignorado)"$'\n'
      else
        sec_profile+="experts ativos: ${P_EXPERTS// /, }"$'\n'
      fi
    fi
    [[ -n "$P_NOTES"    ]] && sec_profile+="nota: $P_NOTES"$'\n'
  fi

  sec_routes=""
  if [[ -n "$ROUTES$WORKFLOWS" ]]; then
    sec_routes=$'\n'"## Rotas (intenção → workflow) e workflows"$'\n'"$ROUTES$WORKFLOWS"
  fi

  sec_heur=""
  if [[ -n "$HEURISTICS" ]]; then
    sec_heur=$'\n'"## Heurísticas de execução"$'\n'"$HEURISTICS"
  fi

  sec_roster=$'\n'"## Roster — nome (modelo). A descrição de cada agente já está no contexto."$'\n'
  if (( ROSTER_COUNT > 0 )); then
    (( ROSTER_FILTERED > 0 )) \
      && sec_roster+="(filtrado por experts do .maestro.yaml: $ROSTER_COUNT de $ROSTER_TOTAL)"$'\n'
    sec_roster+="$ROSTER"
  elif (( ROSTER_TOTAL > 0 )); then
    sec_roster+="(nenhum agente ativo: experts do .maestro.yaml omitiu os $ROSTER_TOTAL do roster)"$'\n'
  else
    sec_roster+="(vazio — nenhum agents/*.md instalado; use os agentes nativos disponíveis)"$'\n'
  fi

  # Orçamento: head/instr/tail são intocáveis (session_id e instrução canônica).
  # O resto cede na ordem do API_SPEC (heurísticas → roster) e, como rede de
  # segurança além da spec, rotas → profile → bindings → gates: uma routing
  # table gigante estoura 8000 bytes sozinha, e o teto vale SEMPRE.
  # Gates e bindings são os últimos a ceder (= primeiros no laço) porque são
  # instrução de ação; rotas e roster são material de referência.
  sec_tail="</maestro-routing>"$'\n'
  local fixed=$(( ${#sec_head} + ${#sec_instr} + ${#sec_tail} ))
  local remaining=$(( BUDGET - fixed ))
  (( remaining < 0 )) && remaining=0

  local name cur allowed cut
  for name in sec_gate sec_bind sec_profile sec_routes sec_roster sec_heur; do
    cur="${!name}"
    [[ -n "$cur" ]] || continue
    if (( ${#cur} <= remaining )); then
      remaining=$(( remaining - ${#cur} ))
      continue
    fi
    allowed=$(( remaining - ${#MARK} ))
    if (( allowed <= 0 )); then
      printf -v "$name" '%s' ""
    else
      cut="${cur:0:allowed}"
      if [[ "$cut" != *$'\n'* ]]; then
        printf -v "$name" '%s' ""
      else
        cut="${cut%$'\n'*}"   # descarta a linha parcial: corte em fronteira ASCII
        printf -v "$name" '%s' "$cut"$'\n'"$MARK"
      fi
    fi
    remaining=0
  done

  local out="$sec_head$sec_instr$sec_gate$sec_bind$sec_profile$sec_routes$sec_heur$sec_roster$sec_tail"
  # Cinto e suspensório: o teto vale mesmo com env exótica ou seção inesperada.
  if (( ${#out} > BUDGET )); then
    out="${out:0:BUDGET}"
    warn "injeção truncada no limite duro de $BUDGET bytes"
  fi
  printf '%s' "$out"
  return 0
}

main() {
  read_session_id   || :
  parse_routing_table || :
  collect_gates     || :
  parse_profile     || :
  parse_roster      || :
  write_gate_policy || :
  cleanup_records   || :
  build_and_emit    || :
  return 0
}

main || warn "degradou (a sessão segue sem a injeção completa)"
exit 0
