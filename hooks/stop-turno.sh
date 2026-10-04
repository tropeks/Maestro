#!/usr/bin/env bash
[[ "${MAESTRO_OFF:-0}" == "1" ]] && exit 0
# maestro hooks/stop-turno.sh — evento Stop (ordem 046, INTENT v6 Prioridade 3).
#
# O fim de turno tem CRITÉRIO MECÂNICO: a ordem em curso tem recibo VÁLIDO no tip?
# O hook não decide nada sozinho — chama `maestro order --turno-check`, que lê o
# ledger e compara o hash do recibo com a árvore do tip (a mesma comparação do
# `order --status`). Nunca executa o `fim:` da ordem. Rótulos do relatório são
# checagem ADICIONAL (entram na lista de faltas; sozinhos não bloqueiam).
#
# Dois orçamentos, medidos e declarados (ARCHITECTURE, NFRs):
#   caminho COMUM (sem ordem em curso, ou ordem sem bloco `## Turno`): <50 ms,
#     bash puro, ZERO fork — HEAD lido do .git por `read`, ordem achada por glob;
#   Stop de turno (ordem em curso COM bloco): roda uma vez por turno e pode gastar
#     até TURNO_TIMEOUT_S — é o teto do `timeout` que cerca a chamada ao CLI.
#     Medido na ordem 056 (worktree com 51 ordens, load 9-10 em 8 CPUs, mediana de
#     amostras do `order --turno-check`): ANTES ~1,7 s (busca da ordem ~600 ms, status
#     ~200 ms, verificação por área ~400 ms, 18 awk de _order_field, chave do ledger
#     resolvida ~8×); DEPOIS ~490 ms. A 046 mediu 708 ms no projeto de teste pequeno.
#     O teto NÃO sobe (decisão do Diretor): o conserto é cortar o custo, não esticar o
#     prazo.
#   Timeout (rc 124) deixou de ser silêncio (ordem 056, contrato (a) do Diretor): o hook
#     confere LOCALMENTE os 5 rótulos do relatório, sem chamar o CLI; faltou rótulo,
#     bloqueia com a lista; os 5 presentes, libera. Evento turno_timeout (só metadados).
#
# Por que hook PRÓPRIO e não o gate-report.sh: ele sai cedo fora do herdr
# (HERDR_ENV) e já está no teto de 400 linhas (oversized-file); o Stop de turno
# vale em QUALQUER terminal.
#
# REGRAS: sempre exit 0 (a Prioridade 1 vence a 3: o hook nunca prende o
# gerente); qualquer falha libera; a ÚNICA saída em stdout é o JSON de block;
# teto de bloqueios por ordem/sessão vive no CLI (_turno_gate, máx. 3).
TURNO_TIMEOUT_S=2   # teto do `timeout` que cerca o CLI; orçamento e medição no cabeçalho
exec 3>&1
exec 1>&2

raw=""
[[ -t 0 ]] || read -r -t 2 -N 262144 raw || :
[[ "$raw" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0   # reentrada de um block: libera
sid=""
[[ "$raw" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,64})\" ]] && sid="${BASH_REMATCH[1]}"
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || sid="${CLAUDE_SESSION_ID:-}"
[[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 0

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
[[ -d "$proj/.maestro/orders" ]] || exit 0

# Branch atual SEM fork: .git é diretório, ou arquivo "gitdir: …" num worktree.
gd="$proj/.git"
if [[ -f "$gd" ]]; then read -r gl < "$gd" || exit 0; gd="${gl#gitdir: }"; fi
head=""; [[ -r "$gd/HEAD" ]] && read -r head < "$gd/HEAD"
[[ "$head" == "ref: refs/heads/"* ]] || exit 0
br="${head#ref: refs/heads/}"
[[ "$br" =~ /([0-9]{3})- ]] || exit 0
n="${BASH_REMATCH[1]}"

# A ordem do branch e o bloco `## Turno` (glob + leitura, sem fork).
shopt -s nullglob
files=("$proj/.maestro/orders/$n"-*.md)
shopt -u nullglob
of="${files[0]:-}"; [[ -n "$of" && -r "$of" ]] || exit 0
has_turno=0
while IFS= read -r line; do
  [[ "$line" == "## Turno"* ]] && { has_turno=1; break; }
done < "$of"
(( has_turno == 1 )) || exit 0

# Rodada que termina PERGUNTANDO ao Diretor é fim legítimo: o gate-report cuida.
HERE="${BASH_SOURCE[0]%/*}"
# shellcheck source=lib/transcript.sh
source "$HERE/lib/transcript.sh" 2>/dev/null || exit 0
tpath=""; [[ "$raw" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && tpath="${BASH_REMATCH[1]}"
last=$(maestro_last_assistant_line "$tpath") || last=""
[[ "$last" =~ \[[Ss]pock\][[:space:]]*[Aa]guardando[[:space:]]*: ]] && exit 0

# Daqui em diante é o Stop de turno: relatório da rodada em arquivo, CLI com teto de 2 s.
rf=$(mktemp "${TMPDIR:-/tmp}/maestro-turno.XXXXXX") || exit 0
trap 'rm -f "$rf"' EXIT
printf '%s' "${last//\\n/$'\n'}" > "$rf"
bin="${CLAUDE_PLUGIN_ROOT:-$HERE/..}/bin/maestro"
[[ -x "$bin" ]] || exit 0
out=$(timeout "$TURNO_TIMEOUT_S" "$bin" order --turno-check --project "$proj" --session "$sid" --report-file "$rf" 2>/dev/null)
rc=$?
if (( rc == 124 )); then
  # O CLI estourou o teto: nada de liberar calado. Checagem barata e local — os 5 rótulos
  # do relatório fixo na última mensagem. Qualquer falha desta checagem libera (Prioridade 1).
  source "$HERE/../lib/core-order-turno.sh" 2>/dev/null || TURNO_REPORT_LABELS="feito provado aberto decisão próximo"
  source "$HERE/lib/common.sh" 2>/dev/null && log_event turno_timeout session_id="$sid" n="$((10#$n))" 2>/dev/null
  [[ -n "$last" ]] || exit 0                       # sem mensagem legível: não há o que conferir
  txt=$(<"$rf") || exit 0   # o 1º rótulo vem colado ao `"text":"` do JSON da linha: a classe aceita a aspa
  missing=""; nl=$'\n'; q='"'
  shopt -s nocasematch
  for l in $TURNO_REPORT_LABELS; do
    re="(^|[${nl}${q}])[[:space:]]*[-*]*[[:space:]]*\\**${l}\\**[[:space:]]*:"
    [[ "$txt" =~ $re ]] || missing+="${missing:+ }$l"
  done
  shopt -u nocasematch
  [[ -n "$missing" ]] || exit 0
  reason="maestro: o check do turno estourou ${TURNO_TIMEOUT_S} s (turno_timeout) e o relatório não tem os rótulos: ${missing}. Escreva feito:/provado:/aberto:/decisão:/próximo: e termine de novo."
else
  (( rc == 1 )) || exit 0          # 0 libera; qualquer outro erro libera também
  [[ -n "$out" ]] || exit 0
  reason="maestro: o turno desta ordem não tem recibo válido no tip. ${out}"
fi
reason="${reason//\\/\\\\}"; reason="${reason//\"/\\\"}"; reason="${reason//$'\n'/\\n}"
printf '{"decision":"block","reason":"%s"}\n' "$reason" >&3
exit 0
