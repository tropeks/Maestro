#!/usr/bin/env bash
# hooks/lib/papercuts.sh — ordem 026: o registro de papercuts da MÁQUINA.
#
# Um papercut é uma falha de FERRAMENTA com conserto conhecido. Ele é
# descoberto por UM gerente e serve a NOVE — e hoje morre com a sessão que o
# descobriu: só em 2026-09-18, nesta máquina, cinco investigações, várias
# repetidas em sessões diferentes porque nenhum gerente enxerga o que o outro
# já pagou. Este módulo é a metade que ESCREVE (via `maestro papercut`); quem
# LÊ é o gerente, sob demanda, e o hooks/session-start.sh só diz que o arquivo
# existe e quantos papercuts tem.
#
# REGRAS DURAS (CLAUDE.md + CONTRATO):
#  - bash puro: nunca invoca Bun, nunca importa src/. `flock` é opcional.
#  - só metadado: nome de ferramenta, versão, código de saída, sintoma. NUNCA
#    caminho ABSOLUTO (vaza a topologia da máquina), nunca conteúdo de prompt.
#    A validação recusa — não reescreve nem mutila (mesmo contrato do log_event).
#  - falha aqui NUNCA bloqueia trabalho: quem chama é o CLI, não um hook de
#    caminho quente; o session-start jamais sourceia este arquivo.
#
# QUEM ESCREVE, e por que não é "cada sessão com >>":
#   O arquivo é lido por nove gerentes e escrito por qualquer um deles, a
#   qualquer hora, de repos diferentes. Duas coisas quebram com `>>` direto:
#   (1) a checagem de duplicata é leia-depois-escreva — duas sessões que batem
#   no MESMO papercut ao mesmo tempo gravam as duas; (2) sem validação, o
#   critério de "o que é papercut" vira decoração de documentação e o arquivo
#   é despejo em duas semanas. Então o escritor é ÚNICO e é este: valida,
#   deduplica e apende sob `flock` — a seção crítica cobre a leitura E a
#   escrita, que é o ponto. Sem `flock` na máquina, o append de uma linha curta
#   em fd O_APPEND continua atômico (write único < PIPE_BUF) e só a deduplicação
#   degrada: o pior caso vira uma linha repetida, nunca uma linha corrompida
#   nem uma linha perdida.
#   DIFERENÇA DELIBERADA para o log_event do common.sh: lá, contenção DESCARTA
#   a linha (log é telemetria; perder um evento é barato). Aqui não se descarta
#   nada — um papercut perdido é a investigação repetida que a ordem existe
#   para evitar. Por isso `flock -w`, com espera, e não `flock -n`.

# shellcheck source=project-state.sh
# maestro_set_papercuts_file vem de project-state.sh (carregado pelo common.sh).

# ---------------------------------------------------------------------------
# Cabeçalho do arquivo — o CRITÉRIO mora onde ele é lido, não num doc distante.
# Escrito uma única vez, na criação. Quem abre o arquivo para consultar vê,
# antes de qualquer papercut, o que NÃO entra ali.
# ---------------------------------------------------------------------------
_maestro_papercut_header() {
  cat <<'HDR'
# papercuts — falha de FERRAMENTA com conserto conhecido (uma linha cada)
#
# Formato: data · sintoma · conserto · projeto
# Escreva com: maestro papercut --add "<sintoma>" --fix "<conserto>"
# Leia ANTES de investigar uma falha estranha de ferramenta. É da MÁQUINA, não
# do projeto: o campo `projeto` é só a procedência de onde alguém bateu nisto.
#
# ENTRA: a ferramenta falhou de um jeito que não se deduz do sintoma e o
# conserto já é conhecido — versão com regressão, código de saída fora da
# tabela, guarda que barra o que devia passar, comando que conta o que não devia.
#
# NÃO ENTRA:
#   bug do PROJETO ............. é issue (tem dono e morre quando for corrigido)
#   lição de MÉTODO ............ é brief (como se trabalha, não o que quebrou)
#   armadilha de CÓDIGO ........ é comentário no código (quem edita tem de ver)
#   sintoma SEM conserto ....... é investigação em aberto — abra issue
#   caminho absoluto, segredo ou conteúdo de prompt ......... nunca
#
# Teste: outro gerente, em outro projeto, bate no MESMO sintoma amanhã. Se a
# linha não poupa a investigação dele, não é papercut — some com ela.
HDR
}

# ---------------------------------------------------------------------------
# Validação de campo. rc=0 válido; rc=1 inválido (com a razão no stderr).
# Chame SEMPRE como `_maestro_papercut_field_ok ... || return 1`: chamada nua a
# função que devolve 1 mata o processo sob `set -e` em qualquer ponto do corpo.
# ---------------------------------------------------------------------------
_maestro_papercut_field_ok() { # <rótulo> <texto> <máx-bytes>
  local rotulo="$1" txt="$2" max="$3"
  if [[ -z "$txt" ]]; then
    printf 'maestro: papercut: %s vazio\n' "$rotulo" >&2
    return 1
  fi
  if [[ "$txt" == *"·"* ]]; then
    printf 'maestro: papercut: %s usa "·", que é o separador de campo\n' "$rotulo" >&2
    return 1
  fi
  if [[ "$txt" =~ [[:cntrl:]] ]]; then
    printf 'maestro: papercut: %s tem caractere de controle (a linha é UMA linha)\n' "$rotulo" >&2
    return 1
  fi
  # Caminho ABSOLUTO (token que começa em / ou ~/) vaza a topologia da máquina —
  # mesma regra do log_event, que recusa qualquer valor com "/". Aqui a recusa é
  # mais frouxa de propósito: `hooks/lib/common.sh` é referência útil e relativa;
  # `/home/fulano/dev/...` é metadado de outra pessoa.
  if [[ "$txt" =~ (^|[[:space:]])~?/[^[:space:]] ]]; then
    printf 'maestro: papercut: %s tem caminho absoluto — cite o caminho relativo ou só a ferramenta\n' "$rotulo" >&2
    return 1
  fi
  local n=${#txt}
  if (( n > max )); then
    printf 'maestro: papercut: %s tem %s caracteres (máx %s) — papercut é UMA linha que outro gerente lê de relance\n' \
      "$rotulo" "$n" "$max" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# maestro_papercut_add <sintoma> <conserto> [projeto]
#   rc=0  registrado (ou já registrado: idempotente de propósito — nove
#         gerentes batendo no mesmo papercut não devem virar nove linhas)
#   rc=1  recusado pela validação (a razão já foi ao stderr)
#   rc=2  arquivo inacessível (ambiente, não conteúdo — API_SPEC §3)
# ---------------------------------------------------------------------------
maestro_papercut_add() {
  local sintoma="${1:-}" conserto="${2:-}" projeto="${3:-}"
  _maestro_papercut_field_ok "sintoma"  "$sintoma"  120 || return 1
  _maestro_papercut_field_ok "conserto" "$conserto" 240 || return 1
  if [[ ! "$projeto" =~ ^[a-z0-9][a-z0-9._-]{0,31}$ ]]; then
    printf 'maestro: papercut: projeto "%s" fora do formato (slug minúsculo, até 32)\n' "$projeto" >&2
    return 1
  fi

  maestro_set_papercuts_file || :
  local f="$_maestro_papercuts_file" dir="${_maestro_papercuts_file%/*}"
  [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || :
  if ! { exec 9>>"$f"; } 2>/dev/null; then
    printf 'maestro: papercut: registro inacessível (%s)\n' "${f##*/}" >&2
    return 2
  fi
  # Espera, não desiste: a seção crítica cobre leitura+escrita, e perder um
  # papercut é o custo que a ordem existe para não pagar. 5s é folga enorme
  # para um append de uma linha; se nem isso, segue sem lock (append de linha
  # curta em O_APPEND continua atômico) e só a deduplicação degrada.
  if command -v flock >/dev/null 2>&1; then
    flock -w "${MAESTRO_PAPERCUT_LOCK_WAIT:-5}" 9 2>/dev/null || :
  fi

  [[ -s "$f" ]] || _maestro_papercut_header >&9 2>/dev/null || :

  # Deduplicação por SINTOMA (o conserto pode melhorar; o sintoma é a chave de
  # busca de quem consulta). Laço builtin: o arquivo é de dezenas de linhas.
  local linha="" resto="" achado=""
  while IFS= read -r linha; do
    # Só linha de papercut conta: o cabeçalho também cita "· sintoma ·" ao
    # explicar o formato, e sem este teste ele seria uma duplicata fantasma.
    [[ "$linha" == [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" · "* ]] || continue
    resto="${linha#* · }"
    if [[ "${resto%% · *}" == "$sintoma" ]]; then achado="${linha%% · *}"; break; fi
  done < "$f"
  if [[ -n "$achado" ]]; then
    { exec 9>&-; } 2>/dev/null || :
    printf 'papercut já registrado em %s — nada a fazer\n' "$achado"
    return 0
  fi

  local hoje=""
  printf -v hoje '%(%Y-%m-%d)T' -1 2>/dev/null || hoje=""
  [[ "$hoje" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || hoje=$(date +%F 2>/dev/null) || hoje=""
  [[ "$hoje" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || hoje="0000-00-00"

  printf '%s · %s · %s · %s\n' "$hoje" "$sintoma" "$conserto" "$projeto" >&9 \
    || { { exec 9>&-; } 2>/dev/null || :; printf 'maestro: papercut: falha de escrita\n' >&2; return 2; }
  { exec 9>&-; } 2>/dev/null || :
  printf 'papercut registrado: %s · %s\n' "$hoje" "$sintoma"
  return 0
}

# maestro_papercut_count — quantos papercuts há. Publica em $_maestro_papercut_n.
# Mesma regra de reconhecimento de linha que o session-start usa (glob de data),
# para que a contagem que o gerente vê na injeção seja a mesma daqui.
_maestro_papercut_n=0
maestro_papercut_count() {
  _maestro_papercut_n=0
  maestro_set_papercuts_file || :
  local f="$_maestro_papercuts_file" linha=""
  [[ -f "$f" && -r "$f" ]] || return 0
  while IFS= read -r linha; do
    if [[ "$linha" == [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" · "* ]]; then
      _maestro_papercut_n=$(( _maestro_papercut_n + 1 ))
    fi
  done < "$f"
  return 0
}

# ---------------------------------------------------------------------------
# cmd_papercut — a metade CLI (`maestro papercut`).
# ---------------------------------------------------------------------------
_maestro_papercut_usage() {
  cat <<'U'
maestro papercut                     lista os papercuts desta máquina
  --add "<sintoma>" --fix "<conserto>" [--project <slug>]
                                     registra (valida, deduplica, apende sob lock)
  --path                             caminho do registro
  --count                            quantos papercuts há

Papercut é falha de FERRAMENTA com conserto conhecido. Bug do projeto é issue;
lição de método é brief; armadilha de código é comentário no código.
U
}

# Braço `--add` do CLI, em função própria (o sensor oversized-function do E9
# cobrou quando cmd_papercut cruzou as 60 linhas — mesma catraca que tirou o
# project-state.sh de dentro do common.sh).
_maestro_papercut_cmd_add() { # <sintoma> <conserto> <projeto-ou-vazio>
  local sintoma="$1" conserto="$2" projeto="$3" bf="" rc=0
  if [[ -z "$conserto" ]]; then
    printf 'maestro: papercut: --add sem --fix. Sintoma sem conserto conhecido não é\n' >&2
    printf 'papercut: é investigação em aberto — abra uma issue.\n' >&2
    return 1
  fi
  if [[ -z "$projeto" ]]; then
    # Mesma identidade de projeto do resto do Maestro (brief/evidência):
    # worktree e repo principal são o MESMO projeto, e o slug já vem saneado.
    bf=$(maestro_brief_file "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null) || bf=""
    bf="${bf##*/}"; bf="${bf%.md}"; projeto="${bf%-*}"
    projeto="${projeto,,}"
    projeto="${projeto//[^a-z0-9._-]/-}"
    [[ -n "$projeto" ]] || projeto="desconhecido"
  fi
  maestro_papercut_add "$sintoma" "$conserto" "$projeto" || rc=$?
  return "$rc"
}

cmd_papercut() {
  local acao="list" sintoma="" conserto="" projeto=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --add)     [[ $# -ge 2 ]] || { printf 'maestro: papercut: --add exige o sintoma\n' >&2; return 1; }
                 acao="add"; sintoma="$2"; shift 2 ;;
      --fix)     [[ $# -ge 2 ]] || { printf 'maestro: papercut: --fix exige o conserto\n' >&2; return 1; }
                 conserto="$2"; shift 2 ;;
      --project) [[ $# -ge 2 ]] || { printf 'maestro: papercut: --project exige o slug\n' >&2; return 1; }
                 projeto="$2"; shift 2 ;;
      --list)    acao="list"; shift ;;
      --path)    acao="path"; shift ;;
      --count)   acao="count"; shift ;;
      -h|--help) _maestro_papercut_usage; return 0 ;;
      *) printf 'maestro: papercut: argumento desconhecido "%s"\n' "$1" >&2
         _maestro_papercut_usage >&2; return 1 ;;
    esac
  done

  # hooks/lib/common.sh dá MAESTRO_HOME e, por tabela, o project-state.sh com a
  # derivação do caminho. Molde dos outros comandos (lib/cmd-brief.sh:97).
  if ! declare -f maestro_set_papercuts_file >/dev/null 2>&1; then
    if [[ -f "${REPO_DIR:-}/hooks/lib/common.sh" ]]; then
      # shellcheck source=common.sh
      source "${REPO_DIR}/hooks/lib/common.sh"
    else
      printf 'maestro: papercut: hooks/lib/common.sh não encontrado\n' >&2; return 2
    fi
  fi
  maestro_set_papercuts_file || :
  local f="$_maestro_papercuts_file"

  case "$acao" in
    path)  printf '%s\n' "$f"; return 0 ;;
    count) maestro_papercut_count || :; printf '%s\n' "$_maestro_papercut_n"; return 0 ;;
    list)
      if [[ -f "$f" && -r "$f" ]]; then
        cat -- "$f"
      else
        printf 'nenhum papercut registrado nesta máquina (%s)\n' "$f"
        printf 'registre o primeiro: maestro papercut --add "<sintoma>" --fix "<conserto>"\n'
      fi
      return 0 ;;
    add) _maestro_papercut_cmd_add "$sintoma" "$conserto" "$projeto" ;;
  esac
  return 0
}
