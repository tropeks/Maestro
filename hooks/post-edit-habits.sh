#!/usr/bin/env bash
# hooks/post-edit-habits.sh — habit hook pós-edição (E9 / S-901).
#
# PostToolUse em Edit|Write|MultiEdit: roda os habit sensors (uma passada de
# awk — hooks/lib/habit-sensors.awk) no arquivo recém-editado e, quando um
# smell dispara, devolve ao agente o ACHADO + o GUIA qualitativo
# (config/habit-guides/<smell>.md) — sensor e guia juntos, para corrigir o
# design em vez de burlar a métrica (padrão habit-hooks, MIT).
#
# Contrato de PostToolUse: a edição JÁ aconteceu — nada aqui bloqueia nada.
#   exit 2 + stderr  → o texto chega ao agente (o cutucão do hábito)
#   exit 0           → silêncio
# Toda falha interna degrada para exit 0 (fronteira: hook quebrado não pode
# atrapalhar trabalho). MAESTRO_OFF=1 desliga, como em todo hook.
#
# Anti-ruído (um sensor que grita demais ensina o agente a ignorá-lo):
#   - cooldown de 15min por (arquivo, smell), estado em $MAESTRO_HOME/sessions/
#   - no máximo 3 achados e 2 guias por emissão, guia capado em 700B
#   - arquivos não-código, gigantes (>500KB / >8000 linhas) e vendor/ ficam fora
#
# Log: só metadados (habit_warn: smell + n + file_ext) — jamais caminho/linha.
# Costuras de teste: MAESTRO_HABITS (lista de sensores), MAESTRO_HABITS_COOLDOWN,
# MAESTRO_HABIT_GUIDES (dir dos guias), CLAUDE_PROJECT_DIR.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
maestro_killswitch

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$SCRIPT_DIR/lib/habit-sensors.awk"
GUIDES="${MAESTRO_HABIT_GUIDES:-$REPO_DIR/config/habit-guides}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
COOLDOWN="${MAESTRO_HABITS_COOLDOWN:-900}"
[[ "$COOLDOWN" =~ ^[0-9]{1,7}$ ]] || COOLDOWN=900

[[ -f "$ENGINE" ]] || exit 0

# ---------------------------------------------------------------------------
# stdin: tool_name + tool_input.file_path + session_id (padrão dos outros hooks:
# regex bash primeiro, jq de reforço; stdin lixo/tty → silêncio, exit 0).
# ---------------------------------------------------------------------------
RAW=""
[[ ! -t 0 ]] && read -r -t 2 -N 262144 RAW || :
[[ -n "$RAW" ]] || exit 0

TOOL=""; FILE=""; SID="desconhecido"
[[ "$RAW" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([A-Za-z]{1,32})\" ]] && TOOL="${BASH_REMATCH[1]}"
[[ "$RAW" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,64})\" ]] && SID="${BASH_REMATCH[1]}"
if command -v jq >/dev/null 2>&1; then
  FILE=$(printf '%s' "$RAW" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE=""
fi
if [[ -z "$FILE" && "$RAW" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]{1,1024})\" ]]; then
  FILE="${BASH_REMATCH[1]}"
  [[ "$FILE" == *'\'* ]] && FILE=""   # escape no caminho: só o jq decodifica com segurança
fi

case "$TOOL" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
[[ -n "$FILE" && -f "$FILE" && -r "$FILE" ]] || exit 0
case "$FILE" in */vendor/*|*/node_modules/*|*/.git/*) exit 0 ;; esac

base="${FILE##*/}"
ext="${base##*.}"
[[ "$ext" != "$base" ]] || exit 0
case "$ext" in
  py|js|jsx|ts|tsx|go|rs|java|rb|php|c|h|cpp|hpp|cs|lua|sh|bash|zsh) ;;
  *) exit 0 ;;
esac

size=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ') || exit 0
[[ "$size" =~ ^[0-9]+$ ]] && (( size <= 512000 )) || exit 0

is_test=0
case "$base" in
  test*|*_test.*|*.test.*|*.spec.*|conftest.py) is_test=1 ;;
esac
case "$FILE" in */tests/*|*/test/*|*/__tests__/*) is_test=1 ;; esac

# ---------------------------------------------------------------------------
# sensores ativos: MAESTRO_HABITS (teste) > .maestro.yaml `habits:` > todos.
# `habits: []` = projeto desligou de propósito.
# ---------------------------------------------------------------------------
ENABLED="all"
if [[ -n "${MAESTRO_HABITS+x}" ]]; then
  ENABLED="$MAESTRO_HABITS"
elif [[ -f "$PROJECT_DIR/.maestro.yaml" && -r "$PROJECT_DIR/.maestro.yaml" ]]; then
  hline=$(awk '/^habits:/ { sub(/^habits:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' \
    "$PROJECT_DIR/.maestro.yaml" 2>/dev/null) || hline=""
  if [[ -n "$hline" ]]; then
    if [[ "$hline" =~ ^\[[[:space:]]*\]$ ]]; then
      ENABLED=""
    elif [[ "$hline" =~ ^\[.*\]$ ]]; then
      ENABLED=$(printf '%s' "$hline" | tr -d '[]" ' | tr ',' '\n' \
        | grep -E '^[a-z-]{1,24}$' | paste -sd, -) || ENABLED=""
    fi
  fi
fi
[[ -n "$ENABLED" ]] || exit 0

# ---------------------------------------------------------------------------
# sensores por arquivo (awk) + sensor de sessão (test-gap).
# ---------------------------------------------------------------------------
# S-1808: mesma classificação de código gerado do CLI — hook e CLI têm de
# responder igual, senão o gate diverge do relatório.
is_gen=0
case "$FILE" in */migrations/*.py|*_pb2.py|*_pb2_grpc.py|*.generated.*|*/gen/*) is_gen=1 ;; esac
findings=$(awk -v EXT="$ext" -v ENABLED="$ENABLED" -v ISTEST="$is_test" -v ISGEN="$is_gen" \
  -f "$ENGINE" "$FILE" 2>/dev/null | head -50) || findings=""

# test-gap: N edições de src na sessão sem NENHUMA edição de teste. Nunca por
# arquivo — por sessão, com nag só nos degraus (5ª, 15ª, 40ª edição de src).
if [[ "$ENABLED" == "all" || ",$ENABLED," == *",test-gap,"* ]]; then
  gapf="$MAESTRO_SESSIONS_DIR/habits-gap-$SID"
  if mkdir -p "$MAESTRO_SESSIONS_DIR" 2>/dev/null; then
    src_n=0; test_n=0
    [[ -f "$gapf" ]] && IFS=$'\t' read -r src_n test_n < "$gapf" 2>/dev/null || :
    [[ "$src_n" =~ ^[0-9]+$ ]] || src_n=0
    [[ "$test_n" =~ ^[0-9]+$ ]] || test_n=0
    if (( is_test == 1 )); then test_n=$(( test_n + 1 )); else src_n=$(( src_n + 1 )); fi
    printf '%s\t%s\n' "$src_n" "$test_n" > "$gapf" 2>/dev/null || :
    if (( test_n == 0 )) && { (( src_n == 5 )) || (( src_n == 15 )) || (( src_n == 40 )); }; then
      findings+="${findings:+$'\n'}test-gap	0	$src_n edições de código nesta sessão, zero em testes"
    fi
  fi
fi
# E16/S-1603b — reforço TARDIO da regra de citação (o SessionStart decai:
# −5,6%/função gerada, arXiv 2605.10039). No PRIMEIRO edit da sessão que toca
# área governada por doc canônico, UMA linha lembra o contrato. Nunca por doc,
# nunca repetido: é cutucão, não sermão.
if [[ "$ENABLED" == "all" || ",$ENABLED," == *",doc-governed,"* ]]; then
  docg="$MAESTRO_SESSIONS_DIR/habits-docg-$SID"
  if [[ ! -f "$docg" && -f "$PROJECT_DIR/.maestro.yaml" ]]; then
    _dlist=$(awk '/^docs:/ { sub(/^docs:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' \
      "$PROJECT_DIR/.maestro.yaml" 2>/dev/null | tr -d '[]" ' | tr ',' ' ')
    _hit=""
    for _dd in $_dlist; do
      _cov=$(awk 'NR==1 && $0 != "---" { exit } NR>40 { exit }
        /^---$/ { fm++; next } fm != 1 { next }
        /^covers:/ { inc=1; next }
        inc && /^[ \t]*-[ \t]*/ { s=$0; sub(/^[ \t]*-[ \t]*/, "", s); gsub(/["\x27 ]/, "", s); print s; next }
        inc { inc=0 }' "$PROJECT_DIR/$_dd" 2>/dev/null || true)
      _rel="${FILE#"$PROJECT_DIR"/}"
      set -f
      for _cg in $_cov; do
        case "$_rel" in
          ${_cg%\*\*}*|$_cg) _hit="$_dd"; break 2 ;;
        esac
      done
      set +f
    done
    set +f
    if [[ -n "$_hit" ]]; then
      mkdir -p "$MAESTRO_SESSIONS_DIR" 2>/dev/null && : > "$docg" 2>/dev/null || :
      findings+="${findings:+$'\n'}doc-governed	0	este arquivo é governado por $_hit — o plano cita doc+seção? mudou contrato? emende no MESMO changeset (maestro docs)"
    fi
  fi
fi
# S-1704 — sensor de regência: lembra, nos degraus 15 e 40, que o contato com
# o Capitão segue o formato REGIDO (essencia · impacto · approach) — a
# partitura técnica só entra sob demanda. Contador de sessão, mesma forma do
# test-gap (S-901), mas sobre TODO edit elegível (src ou teste).
if [[ "$ENABLED" == "all" || ",$ENABLED," == *",regencia,"* ]]; then
  regf="$MAESTRO_SESSIONS_DIR/habits-regencia-$SID"
  if mkdir -p "$MAESTRO_SESSIONS_DIR" 2>/dev/null; then
    reg_n=0
    [[ -f "$regf" ]] && read -r reg_n < "$regf" 2>/dev/null || :
    [[ "$reg_n" =~ ^[0-9]+$ ]] || reg_n=0
    reg_n=$(( reg_n + 1 ))
    printf '%s\n' "$reg_n" > "$regf" 2>/dev/null || :
    if (( reg_n == 15 )) || (( reg_n == 40 )); then
      findings+="${findings:+$'\n'}regencia	0	$reg_n edições nesta sessão — contato com o Capitão é REGIDO: essencia · impacto · approach; partitura técnica só sob demanda; flags Critical/High sobem, o resto o diretor consolida"
    fi
  fi
fi
[[ -n "$findings" ]] || exit 0

# ---------------------------------------------------------------------------
# cooldown por (arquivo, smell): o mesmo aviso não se repete por 15min —
# refatoração em curso não é reincidência.
# ---------------------------------------------------------------------------
now=$(maestro_now_epoch)
fkey=5381
for (( i = 0; i < ${#FILE}; i++ )); do
  printf -v c '%d' "'${FILE:i:1}" 2>/dev/null || c=63
  fkey=$(( ((fkey * 33) + c) & 0xFFFFFFFF ))
done
seen="$MAESTRO_SESSIONS_DIR/habits-seen-$SID"
fresh=""
declare -A skip=()
if [[ -f "$seen" ]]; then
  while IFS=$'\t' read -r k s e; do
    [[ "$e" =~ ^[0-9]+$ ]] || continue
    (( now - e < COOLDOWN )) && [[ "$k" == "$fkey" ]] && skip["$s"]=1
  done < "$seen"
fi
while IFS=$'\t' read -r smell lineno detail; do
  [[ -n "$smell" ]] || continue
  [[ -n "${skip[$smell]:-}" ]] && continue
  fresh+="$smell	$lineno	$detail"$'\n'
done <<<"$findings"
fresh="${fresh%$'\n'}"
[[ -n "$fresh" ]] || exit 0

# ---------------------------------------------------------------------------
# issue #9 (ordem 005): a mensagem dizia "warn-only" e parava aí — verdade
# para ESTE hook (PostToolUse não bloqueia edição já feita), mas o MESMO
# achado alimenta `maestro habits --all` (catraca `.maestro-habits.tsv`,
# S-905), que REPROVA com exit 1 e pode derrubar a CI. Caso real: arquivo de
# teste foi de 399 para 418 linhas, cruzou o teto de 400 (oversized-file),
# virou o 13º acima do baseline de 12 — o PostToolUse disse "warn-only", a CI
# do PR #8 ficou vermelha.
#
# O item que mais paga: o aviso deveria disparar quando a edição CRUZA o
# baseline, não só quando encontra achado. Rodar `--all` aqui para saber ISSO
# de verdade custaria uma varredura do repo inteiro POR EDIÇÃO — medido neste
# repo (223 arquivos rastreados): ~970ms (`time maestro habits --all`),
# contra o orçamento deste hook (dezenas de ms, S-901). Inviável a cada Edit.
#
# Alternativa mais barata implementada: compara o sensor no conteúdo NOVO
# (já computado acima, em `fresh`) contra o MESMO sensor no conteúdo de ANTES
# da edição — um único blob via `git show HEAD:<rel>` (~7ms medidos) + uma
# passada extra de awk NO MESMO ARQUIVO (~7ms medidos), nunca no repo
# inteiro. Um smell presente AGORA e AUSENTE antes desta edição é candidato a
# ter cruzado o total do repo para aquele smell — é uma APROXIMAÇÃO por
# arquivo, honesta sobre o que é: não sabe o total exato do repo (só
# `--all` decide de verdade; outro arquivo pode já estar sobre o baseline, ou
# esta pode ser só a Nª ocorrência de um smell que já estava estourado). Sem
# git, ou arquivo novo (sem HEAD anterior), tudo em `fresh` conta como
# "novo" — é exatamente o caso do arquivo novo: contribuição nova para
# qualquer smell que carregue.
crossing=""
if command -v git >/dev/null 2>&1; then
  rel="${FILE#"$PROJECT_DIR"/}"
  old_smells=""
  old_tmp="$MAESTRO_SESSIONS_DIR/.habits-old-$$"
  if mkdir -p "$MAESTRO_SESSIONS_DIR" 2>/dev/null \
    && git -C "$PROJECT_DIR" show "HEAD:$rel" > "$old_tmp" 2>/dev/null; then
    old_smells=$(awk -v EXT="$ext" -v ENABLED="$ENABLED" -v ISTEST="$is_test" -v ISGEN="$is_gen" \
      -f "$ENGINE" "$old_tmp" 2>/dev/null | cut -f1 | sort -u)
  fi
  rm -f "$old_tmp" 2>/dev/null
  for _sm in $(cut -f1 <<<"$fresh" | awk '!seen[$0]++'); do
    grep -qxF "$_sm" <<<"$old_smells" || crossing+="${crossing:+, }$_sm"
  done
fi

if mkdir -p "$MAESTRO_SESSIONS_DIR" 2>/dev/null; then
  {
    # compacta o estado: só entradas ainda dentro do cooldown
    if [[ -f "$seen" ]]; then
      while IFS=$'\t' read -r k s e; do
        [[ "$e" =~ ^[0-9]+$ ]] && (( now - e < COOLDOWN )) && printf '%s\t%s\t%s\n' "$k" "$s" "$e"
      done < "$seen"
    fi
    while IFS=$'\t' read -r smell _ _; do
      [[ -n "$smell" ]] && printf '%s\t%s\t%s\n' "$fkey" "$smell" "$now"
    done <<<"$fresh"
  } > "$seen.tmp.$$" 2>/dev/null && mv -f "$seen.tmp.$$" "$seen" 2>/dev/null || rm -f "$seen.tmp.$$" 2>/dev/null || :
fi

# ---------------------------------------------------------------------------
# emissão: até 3 achados + até 2 guias (sensor E guia juntos — o guia explica
# o PORQUÊ para a correção ser de design, não de métrica).
# ---------------------------------------------------------------------------
n_total=$(grep -c . <<<"$fresh" || true)
first_smell=$(head -1 <<<"$fresh" | cut -f1)

{
  printf '<maestro-habit>\n'
  if [[ -n "$crossing" ]]; then
    printf 'Habit sensor no arquivo editado (%s): %s achado(s) — CRUZOU o baseline em: %s (novo neste arquivo). Aqui é warn-only (a edição já valeu), mas o MESMO achado alimenta a catraca `maestro habits --all` (.maestro-habits.tsv, S-905), que REPROVA com exit 1 e pode derrubar a CI — confirme com `maestro habits --all` antes do commit.\n' \
      "$base" "$n_total" "$crossing"
  else
    printf 'Habit sensor no arquivo editado (%s): %s achado(s). Aqui é warn-only (a edição já valeu; considere resolver ANTES de seguir) — mas o MESMO achado também alimenta a catraca `maestro habits --all` (.maestro-habits.tsv, S-905), que REPROVA com exit 1 e pode derrubar a CI.\n' \
      "$base" "$n_total"
  fi
  i=0
  while IFS=$'\t' read -r smell lineno detail; do
    [[ -n "$smell" ]] || continue
    i=$(( i + 1 )); (( i > 3 )) && { printf '… (+%s achado(s))\n' $(( n_total - 3 )); break; }
    if [[ "$lineno" == "0" ]]; then printf -- '- %s: %s\n' "$smell" "$detail"
    else printf -- '- %s @ linha %s: %s\n' "$smell" "$lineno" "$detail"; fi
  done <<<"$fresh"
  g=0
  for smell in $(cut -f1 <<<"$fresh" | awk '!seen[$0]++'); do
    gf="$GUIDES/$smell.md"
    [[ -f "$gf" && -r "$gf" ]] || continue
    g=$(( g + 1 )); (( g > 2 )) && break
    printf '\n'
    head -c 700 -- "$gf" 2>/dev/null || :
    printf '\n'
  done
  printf '</maestro-habit>\n'
} >&2

log_event habit_warn session_id="$SID" smell="$first_smell" n="$n_total" file_ext=".$ext"
exit 2
