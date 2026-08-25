#!/usr/bin/env bash
# maestro hooks/pre-bash-guard.sh — guarda destrutivo (E5/S-502)
# Evento PreToolUse, matcher Bash.
#
# POR QUE ELE EXISTE
# O gate estrutural (pre-tool-gate.sh) só intercepta Edit|Write|MultiEdit. A
# Emenda v1.1 do ADR-003 admite `Bash` como escape conhecido, e o PROJECT_BRIEF
# §8 lista "subagentes autônomos agirem sem gate → ação destrutiva" como pior
# caso, a ser mitigado por "política tipo /careful ativa por default em fluxos
# autônomos". Este hook é essa política — em trilho determinístico, não em skill.
#
# Lógica NORMATIVA, nesta ordem exata:
#   1. kill-switch (MAESTRO_OFF) e, depois, kill-switch local (MAESTRO_GUARD_OFF)
#   2. stdin (JSON do Claude Code, via jq): tool_name, session_id, cwd,
#      tool_input.command
#   3. desofusca o comando (continuações de linha, aspas, `\`, espaços) e o
#      quebra em segmentos por `;` `&&` `||` `|` `&` `$( )` backtick
#   4. classifica cada segmento pelo VERBO NA CABEÇA (não por substring solta:
#      é isso que evita gritar em `echo "cuidado com rm -rf /"`)
#   5. sem categoria de risco → exit 0 SILENCIOSO, sem log (o caminho comum de
#      uma sessão é feito de dezenas de comandos inofensivos: logar todos
#      encheria o routing.jsonl de ruído)
#   6. com risco, o modo da sessão decide:
#        mode: subagent|multi (decision record VÁLIDO) → exit 2 + gate_block
#        mode: direct, record ausente/expirado/ilegível → aviso + exit 0 + gate_warn
#      Racional: em fluxo autônomo não há humano no loop para confirmar; no
#      modo direto, há — e barrar o humano é o falso positivo mais caro de todos.
#
# FILOSOFIA (ADR-003 v1.1): anti-descuido, best-effort. Qualquer componente
# ausente (jq, decision record, stdin) degrada com exit 0. O único exit 2 é o
# do passo 6 em modo autônomo. Ele não é uma sandbox: um comando determinado a
# escapar escapa (ver "LIMITES CONHECIDOS" no fim do arquivo).
#
# FALSO POSITIVO É O RISCO PRINCIPAL. Um guarda que barra `rm -rf node_modules`
# vira ruído, o usuário desliga, e ele deixa de proteger de qualquer coisa. Por
# isso a análise de `rm` é por ALVO (artefato de build dentro do projeto passa;
# caminho fora da raiz do projeto, não) e `--force-with-lease` nunca é barrado.
#
# Log: só metadados. O comando NUNCA é logado — só a CATEGORIA do risco, que é
# de vocabulário fechado (a lib rejeita qualquer valor com `/`, e um comando
# quase sempre tem um).
#
# Bash puro: jq + coreutils. Sem Bun, sem src/, sem rede, sem tocar no disco
# para resolver caminho (a análise é 100% léxica).

set -euo pipefail
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR="."
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ── 1. kill-switches ───────────────────────────────────────────────────────
maestro_killswitch
# Kill-switch local: desliga SÓ a guarda destrutiva, mantendo o resto do
# Maestro de pé. Existe porque o custo de um falso positivo aqui é trabalho
# travado, e o brief §8 exige que desligar seja trivial.
if [[ "${MAESTRO_GUARD_OFF:-0}" == "1" ]]; then exit 0; fi

# Globbing desligado: o comando é fatiado com word-splitting deliberado e um
# `*` no meio dele viraria expansão de arquivos do diretório do hook.
set -f

_guard_debug() { [[ "${MAESTRO_DEBUG:-0}" == "1" ]] && echo "maestro: guard: $*" >&2 || true; }

# ── 2. stdin ───────────────────────────────────────────────────────────────
# Mesmas duas defesas do gate contra pendurar: tty (sem payload) e stdin que
# nunca fecha. Um PreToolUse travado congela a sessão, o que é pior que tudo.
MAESTRO_GUARD_STDIN_TIMEOUT="${MAESTRO_GUARD_STDIN_TIMEOUT:-2}"
[[ "$MAESTRO_GUARD_STDIN_TIMEOUT" =~ ^[0-9]{1,3}$ ]] || MAESTRO_GUARD_STDIN_TIMEOUT=2
PAYLOAD=""
if [[ ! -t 0 ]]; then
  IFS= read -r -d '' -t "$MAESTRO_GUARD_STDIN_TIMEOUT" PAYLOAD 2>/dev/null || true
fi
if [[ -z "$PAYLOAD" ]]; then
  _guard_debug "stdin vazio, degradando"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  _guard_debug "jq ausente, degradando"
  exit 0
fi

# Teto de análise. Comando gigante é quase sempre heredoc de dados; a análise
# léxica em bash é linear mas os `${v//x/y}` copiam a string inteira a cada
# passe, então há um teto para o NFR de 50 ms valer sempre.
MAESTRO_GUARD_MAX_CMD="${MAESTRO_GUARD_MAX_CMD:-8192}"
[[ "$MAESTRO_GUARD_MAX_CMD" =~ ^[0-9]{1,6}$ ]] || MAESTRO_GUARD_MAX_CMD=8192

# Um único fork de jq para os quatro campos. Separador RS (0x1e) e sentinela
# "M", pelas mesmas razões documentadas no pre-tool-gate.sh: NUL não sobrevive
# a `$( )`, e @tsv escaparia o conteúdo (analisar comando escapado seria
# analisar outra coisa).
_g_rs=$'\x1e'
_g_raw=$(jq -j --argjson cap "$MAESTRO_GUARD_MAX_CMD" '
    def s: if type == "string" then . else "" end;
    "M", "\u001e",
    ((.tool_name? // "") | s)[0:64], "\u001e",
    ((.session_id? // "") | s)[0:96], "\u001e",
    ((.cwd? // "") | s)[0:1024], "\u001e",
    ((.tool_input?.command? // "") | s)[0:$cap], "\u001e"
  ' <<< "$PAYLOAD" 2>/dev/null) || _g_raw=""

# Janela: só a cabeça (curta e de tamanho limitado por contrato) passa por
# casamento de padrão; o comando sai por offset, uma cópia só.
_g_head="${_g_raw:0:1400}"
if [[ "$_g_head" != "M$_g_rs"*"$_g_rs"*"$_g_rs"*"$_g_rs"* ]]; then
  _guard_debug "json malformado ou campo fora do formato, degradando"
  exit 0
fi
_g_head="${_g_head#M"$_g_rs"}"
TOOL="${_g_head%%"$_g_rs"*}"
_g_head="${_g_head#*"$_g_rs"}"
SID="${_g_head%%"$_g_rs"*}"
_g_head="${_g_head#*"$_g_rs"}"
CWD="${_g_head%%"$_g_rs"*}"
# 5 = "M" + os quatro separadores que antecedem o comando.
CMD="${_g_raw:$(( 5 + ${#TOOL} + ${#SID} + ${#CWD} ))}"
CMD="${CMD%"$_g_rs"}"

# Defensivo: o matcher do hooks.json já é `Bash`, mas o hook não confia nisso.
if [[ -n "$TOOL" && "$TOOL" != "Bash" ]]; then
  _guard_debug "tool != Bash, degradando"
  exit 0
fi
if [[ -z "$CMD" ]]; then
  _guard_debug "command ausente, degradando"
  exit 0
fi

# Raiz do projeto: `cwd` do payload é a fonte mais fiel (é onde o Bash roda).
G_ROOT="${CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[[ "$G_ROOT" == /* ]] || G_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[[ "$G_ROOT" == /* ]] || G_ROOT=""
# `%/` também zera a raiz "/": ela tornaria QUALQUER caminho "dentro do
# projeto" e a análise de alvo perderia o sentido. Raiz vazia = projeto
# indefinido = nenhum alvo é provavelmente seguro (conservador).
G_ROOT="${G_ROOT%/}"
G_CWD="$G_ROOT"
G_CWD_TRUST=1
[[ -n "$G_ROOT" ]] || G_CWD_TRUST=0

# ── 3a. heredoc que escreve ARQUIVO: o corpo é dado, não comando ───────────
# `cat > cleanup.sh <<EOF ... rm -rf /tmp/x ... EOF` é um agente ESCREVENDO um
# script, não executando um. Sem esta poda, escrever qualquer script de limpeza
# dispararia a guarda — falso positivo caro e frequente.
# A poda é condicionada a a linha de abertura ter um `>`: se o heredoc alimenta
# um intérprete (`bash <<EOF`) ou um cliente de banco (`psql <<EOF`), o corpo
# CONTINUA sendo analisado, que é justamente onde ele é perigoso.
#
# Publica em $_g_hd (e não no stdout): `$( )` custaria um fork de subshell num
# hook cujo orçamento inteiro é 50 ms — mesmo padrão de $_gate_norm no gate.
_g_hd=""
_g_strip_heredocs() {
  local src="$1" lines=() line out="" word="" body=0 t
  _g_hd="$src"
  case "$src" in *'<<'*) ;; *) return 0 ;; esac
  local IFS=$'\n'
  # shellcheck disable=SC2206
  lines=($src)
  IFS=' '
  for line in "${lines[@]}"; do
    if [[ $body -eq 1 ]]; then
      t="${line#"${line%%[![:space:]]*}"}"
      t="${t%"${t##*[![:space:]]}"}"
      [[ "$t" == "$word" ]] && body=0
      continue
    fi
    out="$out$line"$'\n'
    if [[ "$line" == *'<<'* && "$line" == *'>'* ]]; then
      word="${line##*<<}"
      word="${word#-}"
      word="${word%%>*}"
      word="${word//\'/}"
      word="${word//\"/}"
      word="${word// /}"
      [[ -n "$word" ]] && body=1
    fi
  done
  _g_hd="$out"
  return 0
}
_g_strip_heredocs "$CMD"
CMD="$_g_hd"

# ── 3b. desofuscação ───────────────────────────────────────────────────────
# Objetivo: neutralizar ofuscação BARATA (a que um modelo produz sem querer, e
# a que um `set -x` produziria), não ofuscação adversária. Ordem importa.
FLAT="$CMD"
FLAT="${FLAT//\\$'\n'/ }"      # continuação de linha
FLAT="${FLAT//$'\n'/;}"        # nova linha É separador de comando
FLAT="${FLAT//$'\r'/ }"
FLAT="${FLAT//$'\t'/ }"
FLAT="${FLAT//\"/}"            # aspas: r"m" -rf  →  rm -rf
FLAT="${FLAT//\'/}"
FLAT="${FLAT//\\/}"            # escapes: r\m -rf  →  rm -rf
while [[ "$FLAT" == *"  "* ]]; do FLAT="${FLAT//  / }"; done
LOW="${FLAT,,}"

# Categorias acumuladas. Vocabulário fechado: são elas, e só elas, que vão
# para o log (`cmd=` aceita ^[a-z0-9:_-]{1,48}$).
G_CATS=""
_g_flag() {
  case " $G_CATS " in
    *" $1 "*) ;;
    *) G_CATS="${G_CATS:+$G_CATS }$1" ;;
  esac
  return 0
}

# ── detectores que NÃO dependem de verbo na cabeça ─────────────────────────
# `curl | sh` — o download-and-execute clássico. Casa também `| sudo bash`.
if [[ "$LOW" =~ (curl|wget)[^\;\|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|ksh|python3?|perl|ruby|node)([[:space:]]|\;|$) ]]; then
  _g_flag remote_pipe_shell
fi
# Escrita direta em dispositivo de bloco: `> /dev/sda`, `of=/dev/nvme0n1`.
if [[ "$LOW" =~ (\>|of=)[[:space:]]*/dev/(sd|hd|nvme|vd|disk|mmcblk) ]]; then
  _g_flag device_write
fi

# ── artefatos de build: o que `rm -rf` pode apagar sem perguntar ───────────
# Lista deliberadamente CURTA e nominal. Tudo que não está aqui e não é
# scratch (/tmp) exige confirmação em fluxo autônomo.
_g_artifact() {
  case "$1" in
    node_modules|dist|build|out|target|coverage|obj|Pods|DerivedData) return 0 ;;
    .next|.nuxt|.svelte-kit|.output|.turbo|.parcel-cache|.cache|.angular) return 0 ;;
    __pycache__|.pytest_cache|.mypy_cache|.ruff_cache|.venv|venv|.tox) return 0 ;;
    .gradle|.dart_tool|tmp|.tmp|.terraform) return 0 ;;
    *) return 1 ;;
  esac
}

# _g_target_safe <alvo>  → 0 se apagar recursivamente isto é ROTINA.
# Conservador por construção: qualquer coisa que não dê para provar léxicamente
# (variável, glob no basename, `..`, caminho fora da raiz) é insegura.
_g_target_safe() {
  local t="${1:-}" abs base
  [[ -n "$t" ]] || return 1
  # Substituição não resolvida ou HOME: não dá para saber onde aterrissa.
  # O `~` aqui é LITERAL de propósito (é o texto do comando que estamos
  # analisando, não um caminho a expandir) — daí o disable do SC2088.
  # shellcheck disable=SC2088
  case "$t" in
    *'$'* | *'`'* | '~' | '~/'*) return 1 ;;
  esac
  t="${t%/}"
  # `dist/*` e `node_modules/*` são a mesma rotina que `dist` — o glob final
  # não muda o alvo. `/*` vira vazio e é rejeitado logo abaixo.
  while [[ "$t" == */\* ]]; do t="${t%/\*}"; t="${t%/}"; done
  [[ -n "$t" ]] || return 1
  [[ "$t" != "." && "$t" != ".." && "$t" != "/" ]] || return 1
  case "/$t/" in */../*) return 1 ;; esac

  if [[ "$t" == /* ]]; then
    abs="$t"
  else
    [[ "$G_CWD_TRUST" == "1" && -n "$G_CWD" ]] || return 1
    abs="$G_CWD/${t#./}"
  fi

  # Scratch: agente que cria e apaga diretório temporário é comportamento
  # esperado, e /tmp não guarda trabalho. `/tmp` NU (sem componente) não entra.
  case "$abs" in
    /tmp/?* | /var/tmp/?* | /private/var/folders/?*) return 0 ;;
  esac

  [[ -n "$G_ROOT" ]] || return 1
  [[ "$abs" == "$G_ROOT"/?* ]] || return 1   # fora da raiz do projeto = perigo
  base="${abs##*/}"
  case "$base" in *'*'* | *'?'* | *'['*) return 1 ;; esac  # glob no basename
  _g_artifact "$base"
}

# ── 4. varredura por segmento, classificando pelo verbo na cabeça ──────────
G_SEGS=()
G_DB=0            # algum segmento invoca cliente de banco
G_MAX_SEGS=64     # teto de trabalho (inclui os segmentos aninhados que criamos)

_g_push_seg() { G_SEGS+=("$1"); return 0; }

_g_split() { # quebra o comando em segmentos e enfileira
  local s="$1" part
  s="${s//&&/;}"
  s="${s//||/;}"
  s="${s//|/;}"
  s="${s//&/;}"
  s="${s//\$(/;}"     # substituição de comando: o conteúdo TAMBÉM é comando
  s="${s//\`/;}"
  s="${s//)/;}"
  local IFS=';'
  for part in $s; do
    [[ -n "$part" ]] || continue
    _g_push_seg "$part"
  done
  return 0
}

_g_split "$FLAT"

_g_scan_seg() {
  local seg="$1" toks=() t head="" rest="" sub_i=0 i n j k
  local IFS=' '
  # shellcheck disable=SC2206
  toks=($seg)
  IFS=' '
  n=${#toks[@]}
  [[ $n -gt 0 ]] || return 0

  # (a) descasca envelopes até achar o verbo: `sudo`, `env FOO=1`, `timeout 5`,
  #     `nohup`, `xargs`, palavras-chave de shell, flags e números.
  i=0
  while [[ $i -lt $n ]]; do
    t="${toks[$i]}"
    case "$t" in
      '#'*) return 0 ;;                       # daqui pra frente é comentário
      sudo | doas) _g_flag privilege_escalation; i=$(( i + 1 )); continue ;;
      env | nohup | time | timeout | command | builtin | exec | nice | ionice | \
      setsid | stdbuf | xargs | watch | flock | then | do | else | elif | fi | \
      done | if | while | until | '{' | '(' | '!' | '[' | '[[')
        i=$(( i + 1 )); continue ;;
      *=*) i=$(( i + 1 )); continue ;;        # atribuição de ambiente
      -*) i=$(( i + 1 )); continue ;;         # flag do envelope
      [0-9]*[smhd] | [0-9]*) i=$(( i + 1 )); continue ;;  # duração do timeout
    esac
    break
  done
  [[ $i -lt $n ]] || return 0
  head="${toks[$i]}"
  head="${head##*/}"      # /bin/rm → rm
  sub_i=$(( i + 1 ))
  rest=""
  if [[ $sub_i -lt $n ]]; then rest="${toks[*]:$sub_i}"; fi

  case "$head" in
    # (b) intérpretes: o resto do segmento é OUTRO comando. Um nível de
    #     desaninhamento fecha `bash -c "rm -rf /"`, que é o escape mais óbvio.
    sh | bash | zsh | ksh | dash | eval)
      [[ ${#G_SEGS[@]} -lt $G_MAX_SEGS && -n "$rest" ]] && _g_push_seg "$rest"
      return 0 ;;
    ssh | su)
      # descarta o primeiro posicional (host/usuário) antes de reanalisar
      local j=$sub_i skipped=0
      while [[ $j -lt $n ]]; do
        case "${toks[$j]}" in
          -*) j=$(( j + 1 )) ;;
          *) if [[ $skipped -eq 0 ]]; then skipped=1; j=$(( j + 1 )); else break; fi ;;
        esac
      done
      if [[ $j -lt $n && ${#G_SEGS[@]} -lt $G_MAX_SEGS ]]; then _g_push_seg "${toks[*]:$j}"; fi
      return 0 ;;

    # (c) mudança de diretório: move a base de resolução dos alvos relativos.
    #     `cd frontend && rm -rf node_modules` continua rotina; `cd / && rm -rf
    #     home` não. Alvo que não dá para resolver derruba a confiança.
    cd | pushd)
      local d=""
      for ((j = sub_i; j < n; j++)); do
        case "${toks[$j]}" in -*) continue ;; *) d="${toks[$j]}"; break ;; esac
      done
      if [[ -z "$d" || "$d" == "-" || "$d" == *'$'* || "$d" == *'`'* || "$d" == *".."* || "$d" == '~'* ]]; then
        G_CWD_TRUST=0
      elif [[ "$d" == /* ]]; then
        G_CWD="${d%/}"; G_CWD_TRUST=1
      elif [[ "$G_CWD_TRUST" == "1" && -n "$G_CWD" ]]; then
        G_CWD="${G_CWD%/}/${d#./}"; G_CWD="${G_CWD%/}"
      fi
      return 0 ;;

    # (d) rm: análise POR ALVO — o coração do anti-falso-positivo.
    rm)
      local rec=0 ntargets=0 unsafe=0
      for ((j = sub_i; j < n; j++)); do
        t="${toks[$j]}"
        case "$t" in
          '#'*) break ;;
          --no-preserve-root) rec=1; unsafe=1; continue ;;
          --recursive | --dir) rec=1; continue ;;
          --) continue ;;
          --*) continue ;;
          -*) case "$t" in *[rR]*) rec=1 ;; esac; continue ;;
        esac
        ntargets=$(( ntargets + 1 ))
        if ! _g_target_safe "$t"; then unsafe=1; fi
      done
      if [[ $rec -eq 1 ]]; then
        # Sem alvo explícito (`... | xargs rm -rf`) o alvo é desconhecido:
        # trata-se como inseguro em vez de como no-op.
        if [[ $ntargets -eq 0 || $unsafe -eq 1 ]]; then _g_flag rm_recursive; fi
      fi
      return 0 ;;

    # (e) git: só as subcomandos que perdem trabalho.
    git)
      local sub="" j=$sub_i
      while [[ $j -lt $n ]]; do
        case "${toks[$j]}" in
          -C | --git-dir | --work-tree) j=$(( j + 2 )) ;;
          -*) j=$(( j + 1 )) ;;
          *) sub="${toks[$j]}"; break ;;
        esac
      done
      case "$sub" in
        push)
          local forced=0 leased=0
          for ((k = j + 1; k < n; k++)); do
            case "${toks[$k]}" in
              --force-with-lease*| --force-if-includes) leased=1 ;;
              --force | -f | --mirror) forced=1 ;;
              +*:* | +*) forced=1 ;;      # refspec com `+` é force
            esac
          done
          if [[ $forced -eq 1 && $leased -eq 0 ]]; then _g_flag git_force_push; fi
          ;;
        reset)
          for ((k = j + 1; k < n; k++)); do
            if [[ "${toks[$k]}" == "--hard" ]]; then _g_flag git_reset_hard; fi
          done
          ;;
        clean)
          local cf=0 cd_=0 dry=0
          for ((k = j + 1; k < n; k++)); do
            case "${toks[$k]}" in
              --dry-run) dry=1 ;;
              --force) cf=1 ;;
              -*) case "${toks[$k]}" in *n*) dry=1 ;; esac
                  case "${toks[$k]}" in *f*) cf=1 ;; esac
                  case "${toks[$k]}" in *[dx]*) cd_=1 ;; esac ;;
            esac
          done
          if [[ $cf -eq 1 && $cd_ -eq 1 && $dry -eq 0 ]]; then _g_flag git_clean; fi
          ;;
        checkout | restore)
          for ((k = j + 1; k < n; k++)); do
            if [[ "${toks[$k]}" == "." ]]; then _g_flag git_discard; fi
          done
          ;;
        filter-branch) _g_flag git_force_push ;;
      esac
      return 0 ;;

    # (f) clientes de banco: marcam o comando inteiro para varredura SQL.
    #     Exigir o cliente na cabeça é o que impede `grep -r "DROP TABLE" .` de
    #     virar alarme — e ele é comando de rotina numa pasta de migrations.
    psql | mysql | mariadb | sqlite3 | mongo | mongosh | sqlcmd | cockroach | \
    clickhouse-client | pg_restore | redis-cli | usql)
      G_DB=1
      if [[ "$head" == "redis-cli" && "$LOW" =~ flush(all|db) ]]; then _g_flag db_flush; fi
      return 0 ;;

    # (g) resto: um verbo, uma regra.
    truncate)
      for ((k = sub_i; k < n; k++)); do
        if [[ "${toks[$k]}" == -s* || "${toks[$k]}" == "--size" ]]; then _g_flag truncate_file; fi
      done
      return 0 ;;
    mkfs | mkfs.* | fdisk | sfdisk | parted | wipefs | shred | mkswap | zpool)
      _g_flag disk_format; return 0 ;;
    dd)
      for ((k = sub_i; k < n; k++)); do
        if [[ "${toks[$k]}" == of=* ]]; then _g_flag dd_overwrite; fi
      done
      return 0 ;;
    chmod | chown)
      local recur=0 wide=0
      for ((k = sub_i; k < n; k++)); do
        case "${toks[$k]}" in
          --recursive) recur=1 ;;
          -*[rR]*) recur=1 ;;
          777 | 0777 | a+rwx | a=rwx) wide=1 ;;
        esac
      done
      if [[ $recur -eq 1 && $wide -eq 1 ]]; then _g_flag chmod_world_writable; fi
      return 0 ;;
    kubectl | oc)
      case "$rest" in
        delete\ * | delete | drain\ *) _g_flag kubectl_delete ;;
      esac
      return 0 ;;
    docker | podman)
      case "$rest" in
        *"system prune"* | *"volume rm"* | *"volume prune"* | rm\ -f* | rmi\ -f* | *"down -v"*)
          _g_flag container_destructive ;;
      esac
      return 0 ;;
    terraform | tofu | pulumi)
      case "$rest" in
        destroy* | *"-auto-approve"*) _g_flag iac_destroy ;;
      esac
      return 0 ;;
    shutdown | reboot | halt | poweroff)
      _g_flag system_power; return 0 ;;
  esac
  return 0
}

_g_i=0
while [[ $_g_i -lt ${#G_SEGS[@]} && $_g_i -lt $G_MAX_SEGS ]]; do
  _g_scan_seg "${G_SEGS[$_g_i]}"
  _g_i=$(( _g_i + 1 ))
done

# SQL destrutivo: só conta se um cliente de banco aparece no comando — assim
# `echo "DROP TABLE x" | psql` casa e `grep "DROP TABLE" *.sql` não.
if [[ $G_DB -eq 1 ]]; then
  if [[ "$LOW" =~ drop[[:space:]]+(table|database|schema) ]]; then _g_flag sql_drop; fi
  if [[ "$LOW" =~ truncate[[:space:]]+(table[[:space:]]|[a-z_]) ]]; then _g_flag sql_truncate; fi
fi

# ── 5. sem risco → silêncio absoluto ───────────────────────────────────────
if [[ -z "$G_CATS" ]]; then
  exit 0
fi

# Categoria primária (a primeira detectada) e contagem — é isso, e só isso,
# que vai para o log.
PRIMARY="${G_CATS%% *}"
NCATS=0
for _c in $G_CATS; do NCATS=$(( NCATS + 1 )); done

LOG_ARGS=("tool=Bash")
if [[ "$PRIMARY" =~ ^[a-z0-9:_-]{1,48}$ ]]; then LOG_ARGS+=("cmd=$PRIMARY"); fi
if [[ "$SID" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then LOG_ARGS+=("session_id=$SID"); fi
LOG_ARGS+=("n=$NCATS")

# ── 6. modo da sessão decide bloquear ou avisar ────────────────────────────
# O record só é lido AQUI: no caminho comum (comando inofensivo) o hook nem
# toca no disco de sessões.
#
# Ordem deliberada por CUSTO: o `mode` sai do arquivo com o builtin `read`
# (zero fork) e só se ele for autônomo é que `maestro_record_valid` roda — e
# ela custa dois forks (jq + date). Assim o caminho de AVISO (o mais frequente,
# porque o default de uma sessão sem decisão é justamente esse) não paga nada,
# e o caminho de bloqueio paga os dois forks uma única vez.
MODE=""
if [[ "$SID" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
  _maestro_refresh_paths 2>/dev/null || true
  _g_rec="$MAESTRO_SESSIONS_DIR/$SID.json"
  if [[ -f "$_g_rec" && -r "$_g_rec" ]]; then
    _g_json=""
    IFS= read -r -d '' -n 4096 _g_json < "$_g_rec" 2>/dev/null || true
    if [[ "$_g_json" =~ \"mode\"[[:space:]]*:[[:space:]]*\"(direct|subagent|multi)\" ]]; then
      MODE="${BASH_REMATCH[1]}"
    fi
  fi
  # Record expirado não descreve mais a sessão: vale como "sem decisão".
  if [[ "$MODE" == "subagent" || "$MODE" == "multi" ]]; then
    maestro_record_valid "$SID" || MODE=""
  fi
fi

# ── 5b. consent ops (E10/S-1006, ADR-003 v1.2) ────────────────────────────
# Consentimento humano explícito (`maestro consent --grant ops`) rebaixa o
# BLOQUEIO para AVISO — mas SÓ quando TODAS as categorias levantadas são
# OPERACIONAIS (sudo/containers/kubectl). Basta UMA categoria de destruição de
# dados (rm_recursive, git_force_push, sql_drop, dd, disk_format…) para o
# bloqueio valer integral: ops libera infraestrutura, nunca apagão. Fail
# closed: consent ausente/expirado/malformado = sem rebaixamento.
OPS_CONSENTED=""
if [[ "$MODE" == "subagent" || "$MODE" == "multi" ]]; then
  _g_all_ops=1
  for _g_cat in $G_CATS; do
    case "$_g_cat" in
      privilege_escalation | container_destructive | kubectl_delete) ;;
      *) _g_all_ops=0; break ;;
    esac
  done
  if [[ $_g_all_ops -eq 1 && -f "$MAESTRO_HOME/consents/ops" ]]; then
    _g_exp=$(awk -F= '/^expires=/ { print $2; exit }' "$MAESTRO_HOME/consents/ops" 2>/dev/null)
    if [[ "$_g_exp" =~ ^[0-9]+$ ]] && (( _g_exp > $(maestro_now_epoch) )); then
      OPS_CONSENTED=1
      LOG_ARGS+=("scope=ops")
    fi
  fi
fi

if [[ -z "$OPS_CONSENTED" && ( "$MODE" == "subagent" || "$MODE" == "multi" ) ]]; then
  # Mensagem ANTES do log: `log_event` fecha o fd 9 com `exec` e, apesar do
  # grupo protetor na common.sh, a ordem mantida aqui é a mesma do gate —
  # a mensagem instrutiva é o produto do exit 2 e não pode se perder.
  # Ela NÃO menciona o kill-switch: ensinar o modelo a desarmar a guarda
  # anularia a guarda (mesma disciplina do pre-tool-gate, review P1-3).
  # `printf` builtin, não `cat <<EOF`: o heredoc custa um fork + um arquivo
  # temporário, e este é o caminho de bloqueio, o mais caro do hook.
  printf '%s\n' >&2 \
    "maestro: comando bloqueado — risco destrutivo em fluxo autônomo (S-502)." \
    "Categoria: $G_CATS" \
    "A sessão está em modo de execução autônomo (subagent/multi): não há humano no" \
    "loop para confirmar uma ação irreversível. NÃO repita o comando como está." \
    "Faça uma destas coisas:" \
    "  1. peça confirmação explícita ao humano, descrevendo o efeito exato; ou" \
    "  2. use a variante reversível — --force-with-lease no lugar de --force," \
    "     --dry-run antes de apagar, git stash no lugar de reset --hard," \
    "     alvo restrito a artefato de build dentro do diretório do projeto." \
    "Operação de INFRA (sudo/docker/kubectl, sem destruição de dados)? Com o" \
    "aval EXPLÍCITO do humano nesta conversa, rode:" \
    "  maestro consent --grant ops --ttl 30m --session $SID" \
    "e repita o comando — vira aviso auditado. Revogue ao terminar."
  log_event gate_block "${LOG_ARGS[@]}" "gate_mode=block"
  exit 2
fi

printf '%s\n' >&2 \
  "maestro: aviso — comando potencialmente destrutivo (categoria: $G_CATS)." \
  "Modo direto ou sem decisão de roteamento registrada: o humano está no volante," \
  "o comando segue. Em fluxo autônomo ele seria bloqueado."
log_event gate_warn "${LOG_ARGS[@]}" "gate_mode=warn"
exit 0

# ── LIMITES CONHECIDOS (honestidade > cobertura falsa) ─────────────────────
# Documentados em docs/architecture/ARCHITECTURE.md (ADR-003 v1.1): esta guarda
# é anti-descuido, NÃO é sandbox. Escapam dela, por construção:
#   - valor de variável: `X=/; rm -rf $X` é barrado (o `$` torna o alvo
#     inseguro), mas `rm -rf "$SAFE_DIR"` também é — não distinguimos os dois;
#   - script indireto: `./deploy.sh`, `make clean`, `npm run reset` — o perigo
#     está dentro do arquivo, que este hook não lê;
#   - linguagem hospedeira: `python -c "shutil.rmtree('/')"`, `node -e ...`;
#   - `find . -delete`, `rsync --delete`, `git worktree remove --force`;
#   - codificação: `echo cm0gLXJmIC8= | base64 -d | sh` casa remote_pipe_shell
#     só quando há curl/wget; `base64 -d | sh` puro NÃO é detectado;
#   - heredoc SEM terminador na janela analisada: o resto do comando é podado
#     junto com o corpo e deixa de ser inspecionado;
#   - comando acima do teto de análise (MAESTRO_GUARD_MAX_CMD, 8 KB): só a
#     cabeça é lida — perigo escondido na cauda de um comando gigante escapa;
#   - ordem semântica: analisamos léxico, não executamos — `false && rm -rf /`
#     é barrado embora nunca fosse rodar (falso positivo deliberado, barato);
#   - SQL fora de cliente conhecido (ORM, migration runner, driver embutido);
#   - `session_id` do subagente: a decisão de bloquear depende do decision
#     record da sessão. Se o Claude Code entregar ao hook de um subagente um
#     session_id DIFERENTE do da sessão principal, não haverá record e a guarda
#     degrada para AVISO — falha para o lado permissivo, que é o lado errado
#     aqui. Verificável em uma sessão de dogfood; não foi possível medir com o
#     log real vazio.
