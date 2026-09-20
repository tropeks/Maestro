#!/usr/bin/env bash
# maestro hooks/gate-report.sh — evento Stop (E21 / S-2101)
#
# PROPÓSITO: quando o turno termina com um GATE HUMANO pendente (plan: brief com
# `approach: pendente` em workflow plan-gated; ship: workflow ship sem desfecho),
# deixa a pergunta num lugar que um transporte externo consegue ler — o herdr
# (runtime das sessões) e, por cima dele, o forwarder do Telegram (Legatus vNext).
#
# Duas saídas, ambas só dentro do herdr (HERDR_ENV=1 + HERDR_PANE_ID):
#   1. $MAESTRO_HOME/herdr/gates/<pane> — chave=valor: gate, session, project,
#      ts, message. É a mensagem LIMPA que o forwarder prefere ao scrape da tela.
#   2. `herdr pane report-agent … --state blocked --message …` — best-effort:
#      para o Claude Code a autoridade de estado é a leitura de tela do herdr
#      (docs "Status authority"), então este report pode ser ignorado; custa um
#      fork e não muda nada quando ignorado. Quem responde (UserPromptSubmit)
#      apaga o arquivo e libera a autoridade.
#
# Sem gate pendente, apaga um arquivo velho do mesmo pane (o gate foi resolvido
# por outro caminho) e sai. REGRAS: sempre exit 0; nada em stdout (um Stop hook
# com JSON no stdout vira decisão do Claude Code); só metadados + a essência
# do brief (texto regido, ≤200 chars, que o Capitão já leu); bash puro, sem jq.
#
# Ordem 020 (INTENT v3, correção de 2026-09-17) — a VOLTA por MCP É NO STOP,
# NO MESMO TURNO: quando gate pendente + socket da Ponte vivo + a última
# rodada terminou com a linha `[spock] aguardando:` (ENGINEERING_SPEC), este
# hook grava o arquivo de gate IGUAL A SEMPRE e, além disso, imprime
# `{"decision":"block","reason":"…"}` no stdout real — a exceção deliberada à
# regra "nada em stdout". Isso NÃO faz o hook esperar nada — ele decide e sai;
# é o Claude Code quem continua o turno do gerente com `reason` como próximo
# passo, e é o GERENTE quem chama `director.ask`/`director.wait`, no laço
# dele, com tool calls normais.
#
# NENHUM hook deste repo (nem em vendor/) emitia `decision` antes desta
# ordem — conferido nos nove hooks (gate-report, post-edit-habits, pre-agent,
# pre-bash-guard, pre-tool-gate, session-end, session-start, subagent-stop,
# user-prompt-submit): zero usos. Esta é a PRIMEIRA vez. O formato do JSON
# (`decision: approve|block` + `reason`, stdout, exit 0) vem de fora do
# repo — documentação/ecossistema do Claude Code, não precedente vivo aqui
# dentro: `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/
# ralph-loop/hooks/stop-hook.sh` (plugin instalado localmente, marketplace
# oficial) e `~/.claude/skills/gstack/bin/gstack-verify-gate` (skill
# instalado localmente, projeto irmão do mesmo autor, NÃO parte deste repo);
# confirmado também no skill oficial `hook-development` (`~/.claude/plugins/
# marketplaces/claude-plugins-official/plugins/plugin-dev/skills/
# hook-development/SKILL.md`). `stop_hook_active` já existia no VOCABULÁRIO
# deste repo antes da 020 (`tests/hooks/test-gate-report.sh`, `main`, sempre
# `false`) — mas nunca fora exercitado para um `block`; esta ordem é a
# primeira vez que o campo importa de verdade.
#
# NÃO-LAÇO, DUAS REDES INDEPENDENTES (a segunda não depende da primeira
# existir, porque `stop_hook_active` é suposição sobre payload de
# plataforma, não garantia deste código):
#   1. `stop_hook_active=true` no payload — reentrada confirmada pelo Claude
#      Code depois de um `block` anterior. Suprime sempre.
#   2. Marcador com TTL, por sessão+gate (`$MAESTRO_HOME/herdr/mcp-asked/
#      <sid>_<gate>`, um epoch dentro): se JÁ bloqueou para esta sessão+gate
#      nos últimos 40min (30min do teto do director_wait + folga), suprime —
#      MESMO que `stop_hook_active` tenha sumido do payload, mudado de nome,
#      ou vindo truncado. Sem a rede 2, a rede 1 sozinha bloquearia TODA VEZ
#      que o campo estivesse ausente (o default seguro de "não reconheço o
#      campo" seria reentry=0) — laço de verdade, não hipotético.
# O gerente pergunta uma vez, espera no laço dele (tool calls dentro do
# mesmo turno, não Stops repetidos) e o que vier depois — resposta ou
# desistência aos 30min — é a rodada que termina de verdade. A plataforma
# também tem um teto próprio (8 blocks consecutivos, ver changelog do
# Claude Code) — rede de segurança adicional, não o mecanismo principal.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
if ! source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null; then
  exit 0
fi
maestro_killswitch

# Ordem 020: cópia do stdout real em fd 3, ANTES de qualquer coisa assumir o
# terminal — é o único canal por onde a decisão de bloqueio (abaixo) pode
# sair. Tudo o mais no script continua indo para stderr, como sempre.
exec 3>&1
exec 1>&2

[[ "${HERDR_ENV:-}" == "1" ]] || exit 0
PANE="${HERDR_PANE_ID:-}"
[[ "$PANE" =~ ^[A-Za-z0-9:_-]{1,32}$ ]] || exit 0
GATES_DIR="$MAESTRO_HOME/herdr/gates"
GATE_FILE="$GATES_DIR/${PANE//:/_}"

raw=""
[[ -t 0 ]] || read -r -t 2 -N 262144 raw || :
sid=""
if [[ -n "$raw" && "$raw" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,64})\" ]]; then
  sid="${BASH_REMATCH[1]}"
fi
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || sid="${CLAUDE_SESSION_ID:-}"
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 0

# Época sem fork: builtin do bash (mesma técnica de maestro_now_epoch em
# lib/common.sh, só sem o `$(...)` que forçaria um subshell aqui). Uma
# leitura de relógio só, reaproveitada pelo prune e pela rede 2 (abaixo).
now_epoch=""
printf -v now_epoch '%(%s)T' -1 2>/dev/null || now_epoch="${EPOCHSECONDS:-}"
[[ "$now_epoch" =~ ^[0-9]+$ ]] || now_epoch=$(date +%s 2>/dev/null) || now_epoch=0

ASK_TTL=2400   # 40min = 30min do teto do director_wait + folga
MCP_ASKED_DIR="$MAESTRO_HOME/herdr/mcp-asked"

# ---------------------------------------------------------------------------
# Ordem 025 (INTENT v3, correção de 2026-09-18) — o gatilho da Ponte MCP SOBE
# para ANTES do `exit 0` de "sem gate" (abaixo) e passa a valer para TODA
# rodada que termina com `[spock] aguardando:`, não só quando há gate humano
# pendente. Causa medida na 020: o gatilho vivia 135 linhas depois do
# `exit 0`, e a maioria dos workflows (fix, custom, audit, verify,
# codereview) NUNCA abre gate (só feature/refactor com approach pendente, ou
# ship sem desfecho — ver o `case "$wf"` abaixo) — o hook sempre saía antes
# de olhar a linha. Decisão do diretor: o volume que chega à pane não muda (a
# linha já chega hoje pelo eco do bridge); muda o canal — decisão no daemon,
# com id, em vez de texto solto. O caminho de gate pendente fica EXATAMENTE
# como estava, por cima — só reaproveita o cálculo de mcp_ask/reentry, que
# agora roda uma vez só, cedo, para os dois caminhos.
#
# Duas funções, definidas antes de qualquer `exit 0` que precise delas:
#
#   _maestro_mcp_prune_stale  — poda marcadores vencidos em $MCP_ASKED_DIR.
#     Chamada de DOIS lugares agora: (a) sempre que há gate pendente (posição
#     e comportamento inalterados desde a 020 — ver a chamada logo antes de
#     "Há gate pendente?" mais abaixo), e (b) no caminho novo sem gate, só
#     quando uma pergunta nova vai mesmo escrever um marcador `_aviso` —
#     nunca em rodada que não escreveria nada de qualquer forma (mesma regra
#     de sempre: nunca introduz um caminho de escrita que não existiria já).
#     Sem o item (b), um projeto que só roda workflows sem gate (só
#     fix/custom/…) nunca teria uma rodada "gate pendente" para acionar a
#     poda, e os marcadores `_aviso` acumulariam para sempre — a ARMADILHA 1
#     da ordem 025.
#
#   _maestro_mcp_ask_gate <sufixo> — escreve o JSON de bloqueio (uma vez por
#     sid+sufixo dentro do TTL) e o marcador correspondente. Sufixo é
#     `plan`/`ship` (gate humano, comportamento de sempre) OU `aviso` (sem
#     gate — sufixo NOVO da 025). O prune (acima) reconhece as três chaves.
#     `f && return 0; return 1` não se aplica aqui: a função nunca devolve
#     erro, sempre termina em `return 0` explícito — chamada nua seria letal
#     sob `set -e` se o corpo pudesse devolver 1 em algum ponto.
# ---------------------------------------------------------------------------

_maestro_mcp_prune_stale() {
  # Ordem 020 (histórico completo dos três achados de custo: docs/patches/
  # 020-NOTAS.md) + Ordem 025 (sufixo `aviso` somado a plan|ship: docs/
  # patches/025-NOTAS.md). Poda marcadores de $MCP_ASKED_DIR vencidos (mtime
  # +40min), só por chave exata `<sid>_<plan|ship|aviso>` — nunca
  # `find -delete` nem glob livre (ver pre-bash-guard.sh); `rm` em lote, um
  # fork só; regex com `+`, nunca `{1,N}` (glibc ~O(N²) pra quantificador
  # limitado, mesmo bug do `tpath` abaixo). Ainda não cabe em 50ms na escala
  # medida; autorização do diretor: amostragem 1 em 10 via contador
  # determinístico em arquivo (não `$RANDOM` — não seedável entre
  # processos). `MCP_PRUNE_SAMPLE_RATE` overridável (testes usam `=1`).
  local _rate _do_prune=1 _prune_counter _count _approved _stale _base
  _rate="${MCP_PRUNE_SAMPLE_RATE:-10}"
  [[ "$_rate" =~ ^[0-9]+$ && "$_rate" -ge 1 ]] || _rate=10
  if (( _rate > 1 )); then
    _do_prune=0
    _prune_counter="$MAESTRO_HOME/herdr/mcp-asked-prune-counter"
    _count=0
    if [[ -f "$_prune_counter" ]]; then
      IFS= read -r _count < "$_prune_counter" 2>/dev/null || :
      [[ "$_count" =~ ^[0-9]+$ ]] || _count=0
    fi
    _count=$(( (_count + 1) % _rate ))
    [[ -d "$MAESTRO_HOME/herdr" ]] || mkdir -p "$MAESTRO_HOME/herdr" 2>/dev/null || :
    printf '%s' "$_count" > "$_prune_counter.tmp.$$" 2>/dev/null \
      && mv -f "$_prune_counter.tmp.$$" "$_prune_counter" 2>/dev/null || rm -f -- "$_prune_counter.tmp.$$" 2>/dev/null || :
    (( _count == 0 )) && _do_prune=1
  fi

  if (( _do_prune == 1 )) && [[ -d "$MCP_ASKED_DIR" ]]; then
    _approved=()
    while IFS= read -r -d '' _stale; do
      _base="${_stale##*/}"
      if [[ "$_base" =~ ^[A-Za-z0-9_-]+_(plan|ship|aviso)$ ]] && (( ${#_base} <= 70 )); then
        _approved+=("$_stale")
      fi
    done < <(find "$MCP_ASKED_DIR" -maxdepth 1 -type f -mmin +40 -print0 2>/dev/null)
    # `if` explícito, não `(( n>0 )) && cmd`: sob set -e, a aritmética
    # SOZINHA devolvendo 1 (array vazio) mataria o script aqui — mesma
    # armadilha já paga na ordem 015. `if` é isento de errexit por natureza.
    if (( ${#_approved[@]} > 0 )); then
      rm -f -- "${_approved[@]}" 2>/dev/null || :
    fi
  fi
  return 0
}

_maestro_mcp_ask_gate() {
  local _suffix="$1" _marker _prev _recent=0
  _marker="$MCP_ASKED_DIR/${sid}_${_suffix}"
  if [[ -f "$_marker" ]]; then
    _prev=""
    IFS= read -r _prev < "$_marker" 2>/dev/null || :
    if [[ "$_prev" =~ ^[0-9]+$ ]] && (( now_epoch - _prev < ASK_TTL )); then
      _recent=1
    fi
  fi
  if (( _recent == 0 )); then
    [[ -d "$MCP_ASKED_DIR" ]] || mkdir -p "$MCP_ASKED_DIR" 2>/dev/null || :
    printf '%s' "$now_epoch" > "$_marker.tmp.$$" 2>/dev/null \
      && mv -f "$_marker.tmp.$$" "$_marker" 2>/dev/null || rm -f -- "$_marker.tmp.$$" 2>/dev/null || :
    printf '%s' "$MCP_ASK_REASON_JSON" >&3 2>/dev/null || :
  fi
  return 0
}

# Reason única para os dois caminhos (com gate e sem gate): texto fixo,
# nunca cita `message`/`essencia` do gate (E25/S-2501 já cobrava isso; ordem
# 025 generaliza o texto para não mencionar "gate" — a maioria das rodadas
# que passam por aqui agora não tem gate nenhum).
# Ordem 029 — a razão NUNCA transcreve o marcador: ia para o transcript e o `tail -c`
# da rodada SEGUINTE a re-disparava (3 falsos positivos medidos). Descreva, não cite.
MCP_ASK_REASON_JSON='{"decision":"block","reason":"maestro: a rodada terminou com uma pergunta pendente (linha canonica de aguardo) e a Ponte MCP esta disponivel nesta pane. Em vez de esperar resposta digitada, chame a tool MCP do servidor ponte: director.ask uma vez, e depois director.wait em laco (ate 5 min por chamada), com teto de 30 min no total. Se expirar sem resposta, diga isso como o desfecho da rodada e nao repita a linha canonica de aguardo para esta mesma pergunta."}'
MCP_NUDGE_REASON_JSON='{"decision":"block","reason":"maestro: esta rodada termina pedindo decisao ao Diretor, mas SEM a linha canonica. Reescreva o fecho da rodada com a linha exata: colchete-s-p-o-c-k-colchete espaco aguardando: <sua pergunta> — e so essa forma aciona a Ponte; parafrase nao aciona. Depois de reescrever, chame a tool MCP director.ask uma vez e director.wait em laco. Se nao ha decisao pendente de verdade, encerre a rodada sem pedir nada."}'

# ---------------------------------------------------------------------------
# Ordem 020, gatilho da VOLTA por MCP — Ordem 025: SOBE para cá, antes do
# `exit 0` de "sem gate" logo abaixo, e passa a rodar sempre (não só com gate
# pendente). Socket da Ponte presente E a linha `[spock] aguardando:` na
# última rodada. Checa primeiro em `$raw` (o próprio payload do Stop — cobre
# `last_assistant_message`, se o build do Claude Code tiver o campo); sem
# achar ali, cai para o transcript (`tail -c`, bounded, sem parser). Escrito
# com `+` no regex, nunca `{1,N}` grande: `{1,4096}` mediu ~2,7s nesta forge
# (glibc é ~O(N²) para compilar/casar quantificador limitado) contra ~7ms de
# `+`.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Ordem 029 (decisão do Capitão): o Stop deixa de liberar por TEXTO. Três
# caminhos — (1) paráfrase sem a canônica → REPROVA; (2) canônica → SEGURA até haver
# EVIDÊNCIA de director.ask (marcador do pre-director-ask.sh, PreToolUse); (3) sem
# socket → passa e REGISTRA (Prioridade 1). O desenho inteiro está na ordem 029.
# Canônica estreita (contrato, ENSINADO na injeção) × paráfrase larga (é o que
# se quer PEGAR). Sem `{1,N}` grande (#42): `[^:]{0,24}` custou ~640µs em 8KB.
# ---------------------------------------------------------------------------
MAESTRO_ASK_CANON='\[[Ss]pock\][[:space:]]*[Aa]guardando[[:space:]]*:'
MAESTRO_ASK_LOOSE='[Aa]guard(o|ando)[^:]{0,24}:'

mcp_ask=0        # (2) canônica presente → segurar até a evidência
mcp_nudge=0      # (1) paráfrase sem canônica → reprovar e mandar reescrever
ponte_sock="${PONTE_MCP_SOCKET:-$HOME/.ponte/mcp.sock}"
if [[ -e "$ponte_sock" ]]; then
  ask_txt="$raw"
  if [[ ! "$ask_txt" =~ $MAESTRO_ASK_CANON && ! "$ask_txt" =~ $MAESTRO_ASK_LOOSE ]]; then
    tpath=""
    if [[ "$raw" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      tpath="${BASH_REMATCH[1]:0:4096}"
    fi
    if [[ -n "$tpath" && -f "$tpath" && -r "$tpath" ]]; then
      tail_txt=$(tail -c 8192 -- "$tpath" 2>/dev/null) || tail_txt=""
      [[ -n "$tail_txt" ]] && ask_txt="$tail_txt"
    fi
  fi
  if [[ "$ask_txt" =~ $MAESTRO_ASK_CANON ]]; then
    mcp_ask=1
  elif [[ "$ask_txt" =~ $MAESTRO_ASK_LOOSE ]]; then
    mcp_nudge=1
  fi
else
  # (3) registrado: "passou sem Ponte" é fato no log, não silêncio.
  if [[ "$raw" =~ $MAESTRO_ASK_CANON || "$raw" =~ $MAESTRO_ASK_LOOSE ]]; then
    log_event director_ask session_id="$sid" phase=sem_socket
  fi
fi

# (2) a EVIDÊNCIA: marcador por sessão, escrito no PreToolUse da tool.
DIRECTOR_ASKED_DIR="$MAESTRO_HOME/herdr/director-asked"
if (( mcp_ask == 1 )) && [[ -n "$sid" && -e "$DIRECTOR_ASKED_DIR/$sid" ]]; then
  mcp_ask=0
fi

# NÃO-LAÇO, rede 1: `stop_hook_active=true` = este Stop já é reentrada de um
# `block` anterior. Suprime sempre — mesmo que a linha ainda apareça. Regex
# sobre `$raw` já lido: zero custo extra.
reentry=0
[[ "$raw" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && reentry=1

# ---------------------------------------------------------------------------
# Há gate pendente? Leitura por regex do record (presença + enums), como no
# session-end.sh — nada de parser.
# ---------------------------------------------------------------------------
rec="${MAESTRO_SESSIONS_DIR:-$MAESTRO_HOME/sessions}/$sid.json"
gate=""; essencia=""
if [[ -f "$rec" && -r "$rec" ]]; then
  body=$(head -c 65536 -- "$rec" 2>/dev/null) || body=""
  wf=""; [[ "$body" =~ \"workflow\"[[:space:]]*:[[:space:]]*\"([a-z]+)\" ]] && wf="${BASH_REMATCH[1]}"
  # E25/S-2501: `killed` conta como fechado — o gate ship não cobra shipar o que
  # foi descartado.
  settled=0; [[ "$body" =~ \"outcome\"[[:space:]]*:[[:space:]]*\"(accepted|rework|reverted|killed)\" ]] && settled=1
  case "$wf" in
    feature|refactor)
      # gate plan: approach ainda pendente no brief regido. `settled` entra aqui
      # também (E25/S-2501): matar uma feature ANTES do plano aprovado é o kill
      # mais comum, e sem esta guarda o herdr seguiria perguntando "Aprovo o
      # plano?" — no telefone inclusive — sobre trabalho já descartado.
      if (( settled == 0 )) && [[ "$body" =~ approach:[[:space:]]*pendente ]]; then gate="plan"; fi ;;
    ship)
      (( settled == 0 )) && gate="ship" ;;
  esac
  # Ancorado ao campo "brief" de propósito: o record tem outros campos de texto do
  # diretor (`reason`, e desde o E25 `kill_reason`), e um deles contendo a substring
  # `essencia:` sairia desta máquina pela ponte do herdr. A promessa do API_SPEC §1 é
  # que só a essência do brief sai.
  if [[ "$body" =~ \"brief\"[[:space:]]*:[[:space:]]*\"[^\"]*essencia:[[:space:]]*([^;\"]{1,200}) ]]; then
    essencia="${BASH_REMATCH[1]}"
    essencia="${essencia%"${essencia##*[![:space:]]}"}"
  fi
fi

if [[ -z "$gate" ]]; then
  rm -f -- "$GATE_FILE" 2>/dev/null || :
  # Ordem 020: gate resolvido — limpa os marcadores de "já bloqueei por isto"
  # das duas chaves possíveis (nunca sabemos aqui qual delas foi usada).
  rm -f -- "$MCP_ASKED_DIR/${sid}_plan" "$MCP_ASKED_DIR/${sid}_ship" 2>/dev/null || :

  # Ordem 025, ARMADILHA 1 (sufixo do marcador sem gate): sem gate não há
  # `${gate}` para nomear a chave — sufixo novo `aviso`, ensinado ao prune
  # acima (regex `plan|ship|aviso`).
  #
  # ARMADILHA 2 (limpeza sem evento de resolução): o caminho COM gate limpa
  # o marcador quando o RECORD muda de estado (approach deixa de ser
  # pendente, ship ganha desfecho) — um evento observável fora deste hook.
  # Sem gate não existe esse evento; a única coisa que este hook pode
  # observar, rodada a rodada, é se a linha `[spock] aguardando:` ainda está
  # lá. DECISÃO (registrada aqui, não é hipótese): se esta rodada NÃO tem a
  # linha (ou não tem como perguntar — sem socket, ou reentrada confirmada),
  # tratamos como resolvida e limpamos o marcador de aviso — a MESMA sessão
  # pode perguntar de novo na rodada seguinte sem esperar o TTL de 40min. Só
  # quando a MESMA pergunta se repete rodada após rodada (sem resposta
  # ainda) é que o TTL/marcador seguram — exatamente o papel que já tinham
  # no caminho com gate: proteção contra laço numa pergunta ainda aberta,
  # não um período de silêncio imposto entre perguntas distintas. Na
  # prática, como o gerente resolve a pergunta por MCP no mesmo turno
  # (director.ask/director.wait), a rodada SEGUINTE quase sempre já não
  # repete a linha — o TTL de 40min raramente chega a valer de verdade.
  if (( mcp_ask == 1 && reentry == 0 )); then
    _maestro_mcp_prune_stale
    _maestro_mcp_ask_gate aviso
  elif (( mcp_nudge == 1 && reentry == 0 )); then
    # 029 (1): a reentrada já é a rede de não-laço; TTL aqui deixaria a rodada
    # seguinte escapar com a paráfrase, que é o que esta ordem impede.
    log_event gate_block session_id="$sid" gate_mode=parafrase
    printf '%s' "$MCP_NUDGE_REASON_JSON" >&3 2>/dev/null || :
    exit 0
  else
    rm -f -- "$MCP_ASKED_DIR/${sid}_aviso" 2>/dev/null || :
  fi
  exit 0
fi

_maestro_mcp_prune_stale

project="${CLAUDE_PROJECT_DIR:-$PWD}"; project="${project##*/}"
[[ "$project" =~ ^[A-Za-z0-9._-]{1,48}$ ]] || project="projeto"
case "$gate" in
  plan) message="gate plan · $project${essencia:+ · $essencia} — Aprovo o plano? (aprovo | ajusta: …)" ;;
  ship) message="gate ship · $project${essencia:+ · $essencia} — Shipo agora? (shipa | espera)" ;;
esac
# uma linha só: quebras viram espaço (o arquivo é chave=valor por linha)
message="${message//$'\n'/ }"; message="${message//$'\r'/ }"

mkdir -p "$GATES_DIR" 2>/dev/null || exit 0
tmp="$GATE_FILE.tmp.$$"
{
  printf 'gate=%s\n' "$gate"
  printf 'session=%s\n' "$sid"
  printf 'project=%s\n' "$project"
  printf 'ts=%s\n' "$(maestro_now_epoch 2>/dev/null || date +%s)"
  printf 'message=%s\n' "$message"
} > "$tmp" 2>/dev/null && mv -f "$tmp" "$GATE_FILE" 2>/dev/null || { rm -f "$tmp"; exit 0; }

# best-effort: report ao herdr (pode ser ignorado pela autoridade de tela)
bin="${HERDR_BIN_PATH:-herdr}"
if command -v "$bin" >/dev/null 2>&1 || [[ -x "$bin" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    timeout 2 "$bin" pane report-agent "$PANE" --source custom:maestro --agent claude \
      --state blocked --message "$message" --seq "$(date +%s%N 2>/dev/null || date +%s)" >/dev/null 2>&1 || :
  else
    "$bin" pane report-agent "$PANE" --source custom:maestro --agent claude \
      --state blocked --message "$message" --seq "$(date +%s%N 2>/dev/null || date +%s)" >/dev/null 2>&1 || :
  fi
fi

# NÃO-LAÇO: mcp_ask/reentry já calculados lá em cima (Ordem 025 — mesmo
# cálculo serve os dois caminhos). Rede 1 (stop_hook_active) já aplicada na
# condição; rede 2 (marcador com TTL por sessão+chave) é _maestro_mcp_ask_gate,
# aqui com a chave de sempre (plan|ship) — comportamento inalterado desde a
# 020, só a implementação foi extraída para função e reaproveitada pelo
# caminho novo sem gate (chave `aviso`, tratado mais acima).
(( mcp_ask == 1 && reentry == 0 )) && _maestro_mcp_ask_gate "$gate"
# 029 (1) vale também com gate pendente: a convenção é de toda rodada.
if (( mcp_nudge == 1 && reentry == 0 )); then
  log_event gate_block session_id="$sid" gate_mode=parafrase
  printf '%s' "$MCP_NUDGE_REASON_JSON" >&3 2>/dev/null || :
  exit 0
fi
exit 0
