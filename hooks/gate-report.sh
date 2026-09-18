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
  exit 0
fi

# ---------------------------------------------------------------------------
# Ordem 020 (correção do diretor, terceira rodada) — PRUNE dos marcadores
# vencidos, a cada execução COM GATE PENDENTE (não antes: um teste
# pré-existente prova "payload de lixo/pane inválido não escreve nada" —
# achado da quarta rodada, colocar o prune antes de saber se há gate
# quebrava essa garantia, porque o `mkdir` do contador de amostragem é efeito
# colateral por si só. "Gate pendente" já é a MESMA condição que o
# `mkdir -p "$GATES_DIR"` de sempre usa — nunca introduz um caminho de escrita
# novo, só reaproveita o que já ia escrever de qualquer forma): o mesmo hook
# que cria o marcador apaga os que já passaram do TTL. Sem isto, TTL vencido
# só faz o CÓDIGO ignorar o arquivo — o arquivo em si fica para sempre, e com
# N sessões × gates isso acumula sem limite (sessão abandonada nunca mais
# roda o Stop dela para se autolimpar; é OUTRA sessão, nesta mesma execução,
# que varre por todas).
#
# Delimitação (apagar por padrão de nome errado é como se apaga a coisa
# errada — ver o aviso sobre `find -delete` em pre-bash-guard.sh): o `find`
# só ENCONTRA candidatos por diretório exato + idade; quem decide apagar é
# este loop, que revalida CADA nome contra o padrão exato `<sid>_<gate>`
# (mesmo charset de sid validado acima, gate travado em plan|ship). Nunca
# `-delete` do find sozinho, nunca glob livre.
#
# Custo medido (achado da rodada anterior): não é o prune, é um `rm` por
# arquivo — 18 forks para 18 arquivos, ~5-6ms cada. Correção do diretor:
# acumula os nomes APROVADOS num array e apaga tudo num `rm -f --` só. Um
# fork, não N. `"${_approved[@]}"` vazio não vira erro nem apaga nada
# (bash expande para zero argumentos, `rm -f --` sem alvo é no-op); o `--`
# protege nome de marcador que por algum motivo comece com `-`.
#
# Segundo achado, medindo a versão com o rm batelado: o que sobrava caro era
# o PRÓPRIO regex `{1,64}` repetido por candidato — mesma família do bug de
# `{1,N}` já corrigido no `tpath` (glibc é ~O(N²) para compilar/casar
# quantificador limitado), só que agora por REPETIÇÃO em vez de por N grande
# numa string só: 100 candidatos ~77ms com `{1,64}`, ~15ms com `+` (medido).
# `+` sem limite no regex; o teto de tamanho vira aritmética (`${#_base}`,
# builtin, sem regex) — mesma técnica de sempre neste arquivo.
#
# TERCEIRO achado, com as duas correções acima já aplicadas: ainda não cabe
# em 50ms na escala pedida pelo diretor (18 arquivos ~75-80ms mediana, 100
# ~99-110ms, interleaved contra baseline, mínimo já acima de 50ms nos dois —
# ver docs/patches/020-NOTAS.md para a tabela completa). O que resta é o
# `find` + o loop em si, que já não têm gordura óbvia para cortar sem trocar
# de mecanismo. Autorização do diretor para esta saída (decisão já dada, não
# pergunte de novo): AMOSTRAGEM 1 em 10 — o prune só roda a cada 10ª
# execução (com gate pendente) do hook dentro do herdr. Contador
# determinístico em arquivo (`$MAESTRO_HOME/herdr/mcp-asked-prune-counter`),
# não `$RANDOM`: `$RANDOM` não é seedável de fora do processo bash (testado —
# `RANDOM=N bash -c '...'` não reproduz), então um teste de "isto amostra
# mesmo" ficaria probabilístico; o contador é 100% determinístico e
# testável. Custo do contador em si: um `read`/`printf` builtin + um `mv`
# (mesmo padrão do `GATE_FILE`), muito mais barato que o próprio `find` que
# ele evita rodar na maioria das vezes. `MCP_PRUNE_SAMPLE_RATE` overridável
# (testes usam `=1` para tornar o prune determinístico de novo).
MCP_PRUNE_SAMPLE_RATE="${MCP_PRUNE_SAMPLE_RATE:-10}"
[[ "$MCP_PRUNE_SAMPLE_RATE" =~ ^[0-9]+$ && "$MCP_PRUNE_SAMPLE_RATE" -ge 1 ]] || MCP_PRUNE_SAMPLE_RATE=10
_do_prune=1
if (( MCP_PRUNE_SAMPLE_RATE > 1 )); then
  _do_prune=0
  _prune_counter="$MAESTRO_HOME/herdr/mcp-asked-prune-counter"
  _count=0
  if [[ -f "$_prune_counter" ]]; then
    IFS= read -r _count < "$_prune_counter" 2>/dev/null || :
    [[ "$_count" =~ ^[0-9]+$ ]] || _count=0
  fi
  _count=$(( (_count + 1) % MCP_PRUNE_SAMPLE_RATE ))
  [[ -d "$MAESTRO_HOME/herdr" ]] || mkdir -p "$MAESTRO_HOME/herdr" 2>/dev/null || :
  printf '%s' "$_count" > "$_prune_counter.tmp.$$" 2>/dev/null \
    && mv -f "$_prune_counter.tmp.$$" "$_prune_counter" 2>/dev/null || rm -f -- "$_prune_counter.tmp.$$" 2>/dev/null || :
  (( _count == 0 )) && _do_prune=1
fi

if (( _do_prune == 1 )) && [[ -d "$MCP_ASKED_DIR" ]]; then
  _approved=()
  while IFS= read -r -d '' _stale; do
    _base="${_stale##*/}"
    if [[ "$_base" =~ ^[A-Za-z0-9_-]+_(plan|ship)$ ]] && (( ${#_base} <= 70 )); then
      _approved+=("$_stale")
    fi
  done < <(find "$MCP_ASKED_DIR" -maxdepth 1 -type f -mmin +40 -print0 2>/dev/null)
  # `if` explícito, não `(( n>0 )) && cmd`: sob set -e, a aritmética SOZINHA
  # devolvendo 1 (array vazio) mataria o script aqui — a mesma armadilha já
  # paga na ordem 015. `if` é isento de errexit por natureza.
  if (( ${#_approved[@]} > 0 )); then
    rm -f -- "${_approved[@]}" 2>/dev/null || :
  fi
fi

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

# ---------------------------------------------------------------------------
# Ordem 020 — gatilho da VOLTA por MCP: socket da Ponte presente E a linha
# `[spock] aguardando:` na última rodada. Checa primeiro em `$raw` (o próprio
# payload do Stop — cobre `last_assistant_message`, se o build do Claude Code
# tiver o campo); sem achar ali, cai para o transcript (`tail -c`, bounded,
# sem parser — mesmo padrão do resto do arquivo). Escrito com `+` no regex,
# nunca `{1,N}` grande: `{1,4096}` mediu ~2,7s nesta forge (glibc é ~O(N²)
# para compilar/casar quantificador limitado) contra ~7ms de `+`.
# ---------------------------------------------------------------------------
mcp_ask=0
ponte_sock="${PONTE_MCP_SOCKET:-$HOME/.ponte/mcp.sock}"
if [[ -e "$ponte_sock" ]]; then
  if [[ "$raw" =~ \[spock\][[:space:]]aguardando: ]]; then
    mcp_ask=1
  else
    tpath=""
    if [[ "$raw" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      tpath="${BASH_REMATCH[1]:0:4096}"
    fi
    if [[ -n "$tpath" && -f "$tpath" && -r "$tpath" ]]; then
      tail_txt=$(tail -c 8192 -- "$tpath" 2>/dev/null) || tail_txt=""
      [[ "$tail_txt" =~ \[spock\][[:space:]]aguardando: ]] && mcp_ask=1
    fi
  fi
fi

# NÃO-LAÇO, rede 1: `stop_hook_active=true` = este Stop já é reentrada de um
# `block` anterior. Suprime sempre — mesmo que a linha ainda apareça. Regex
# sobre `$raw` já lido: zero custo extra.
reentry=0
[[ "$raw" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && reentry=1

# NÃO-LAÇO, rede 2 (independente da rede 1): marcador com TTL por sessão+gate.
# Não depende de `stop_hook_active` existir no payload — é o que segura o
# caso do campo ausente/renomeado/truncado, onde a rede 1 sozinha deixaria
# `reentry=0` para sempre e bloquearia a cada Stop. Só toca o disco quando as
# duas condições de cima já valem — no caminho comum (mcp_ask=0, a maioria
# dos gates pendentes) isto custa zero além do prune acima, que já rodou.
if (( mcp_ask == 1 && reentry == 0 )); then
  asked_marker="$MCP_ASKED_DIR/${sid}_${gate}"
  asked_recent=0
  if [[ -f "$asked_marker" ]]; then
    prev=""
    IFS= read -r prev < "$asked_marker" 2>/dev/null || :
    if [[ "$prev" =~ ^[0-9]+$ ]] && (( now_epoch - prev < ASK_TTL )); then
      asked_recent=1
    fi
  fi

  if (( asked_recent == 0 )); then
    [[ -d "$MCP_ASKED_DIR" ]] || mkdir -p "$MCP_ASKED_DIR" 2>/dev/null || :
    printf '%s' "$now_epoch" > "$asked_marker.tmp.$$" 2>/dev/null \
      && mv -f "$asked_marker.tmp.$$" "$asked_marker" 2>/dev/null || rm -f -- "$asked_marker.tmp.$$" 2>/dev/null || :
    printf '{"decision":"block","reason":"maestro: gate pendente e a Ponte MCP esta disponivel nesta pane. Em vez de esperar resposta digitada, chame a tool MCP do servidor ponte: director.ask uma vez, e depois director.wait em laco (ate 5 min por chamada), com teto de 30 min no total. Se expirar sem resposta, diga isso como o desfecho da rodada e nao repita a linha [spock] aguardando: para esta mesma pergunta."}' >&3 2>/dev/null || :
  fi
fi
exit 0
