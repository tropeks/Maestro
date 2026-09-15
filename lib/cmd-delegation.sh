#!/usr/bin/env bash
# maestro lib/cmd-delegation.sh — E23a/S-2301, extraído de bin/maestro na
# ordem 010 (E24, ledger e record).
#
# O funil da delegação, contado no log: decide --agents diz que VAI delegar
# (planned); o hook pre-agent.sh diz que delegou (started); o
# subagent-stop.sh diz que colheu (received); o order --accept diz que o
# diretor aceitou (accepted). `_delegation_n` também é chamado por
# `cmd_outcome` (lib/cmd-outcome.sh, mesma ordem) — cada sítio chama
# `_delegation_lib_load` antes, mesma técnica de `_order_lib_load`.
#
# Sourced por bin/maestro (via _delegation_lib_load, I-2) DENTRO do mesmo
# processo — nenhum fork. `DELEG_FILES` é estado global de módulo sourceado
# de dentro de função: `declare -g` obrigatório, senão o array é LOCAL e some
# ao a função retornar (bug pago na ordem 009). REPO_DIR, MAESTRO_LOG_DIR, die
# e o `source hooks/lib/common.sh` do chamador já no escopo. Convenção
# (firmada no lote do `order`, E24): parâmetro posicional, nenhuma função
# fecha sobre local de outra.

# Os logs que valem para o funil: o corrente e os rotacionados do mês
# (DATA_MODEL §4). Publica em DELEG_FILES para não pagar um subshell por consulta.
declare -g DELEG_FILES=()
_delegation_files() {
  DELEG_FILES=()
  local f
  shopt -s nullglob
  for f in "$MAESTRO_LOG_DIR"/routing.jsonl "$MAESTRO_LOG_DIR"/routing-*.jsonl; do
    [[ -f "$f" ]] && DELEG_FILES+=("$f")
  done
  shopt -u nullglob
  return 0
}

_delegation_n() { # _delegation_n <session_id> <fase> → contagem no log
  local sid="$1" ph="$2" n=""
  _delegation_files
  if [[ ${#DELEG_FILES[@]} -gt 0 ]]; then
    # `index` em vez de regex: os dois emissores (log_event do common.sh e o
    # JSON.stringify do cli.ts) escrevem JSON compacto, e o sid já vem tipado
    # pelo chamador — casamento literal é exato e não interpreta o valor.
    n=$(awk -v sid="$sid" -v ph="$ph" '
      index($0, "\"event\":\"delegation\"") == 0 { next }
      index($0, "\"session_id\":\"" sid "\"") == 0 { next }
      index($0, "\"phase\":\"" ph "\"") > 0 { n++ }
      END { print n + 0 }
    ' "${DELEG_FILES[@]}" 2>/dev/null) || n=""
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s\n' "$n"
  return 0
}

_delegation_print_all() { # imprime o funil das últimas sessões (--all)
  _delegation_files
  if [[ ${#DELEG_FILES[@]} -eq 0 ]]; then
    echo "delegação: nenhum log em $MAESTRO_LOG_DIR"
    return 0
  fi
  printf 'delegação — últimas sessões (planned → started → received → accepted)\n'
  printf '  %-28s %7s %7s %8s %8s\n' "sessão" "planned" "started" "received" "accepted"
  awk '
    index($0, "\"event\":\"delegation\"") == 0 { next }
    {
      sid = ""; ph = ""
      if (match($0, /"session_id":"[A-Za-z0-9_-]+"/)) sid = substr($0, RSTART + 14, RLENGTH - 15)
      if (match($0, /"phase":"[a-z]+"/))              ph  = substr($0, RSTART + 9,  RLENGTH - 10)
      if (sid == "" || ph == "") next
      if (!(sid in seen)) { seen[sid] = ++n; order[n] = sid }
      c[sid, ph]++
    }
    END {
      if (n == 0) { print "  (nenhuma delegação registrada)"; exit }
      start = (n > 20) ? n - 19 : 1
      for (i = start; i <= n; i++) {
        s = order[i]
        printf "  %-28s %7d %7d %8d %8d\n", s, c[s,"planned"] + 0, c[s,"started"] + 0, \
               c[s,"received"] + 0, c[s,"accepted"] + 0
      }
    }
  ' "${DELEG_FILES[@]}"
  return 0
}

_delegation_print_session() { # <session_id> → imprime o funil de uma sessão
  local sid="$1" pl st rc ac
  pl=$(_delegation_n "$sid" planned)
  st=$(_delegation_n "$sid" started)
  rc=$(_delegation_n "$sid" received)
  ac=$(_delegation_n "$sid" accepted)
  printf 'delegação — sessão %s\n' "$sid"
  printf '  planned : %s   (maestro decide --agents)\n'   "$pl"
  printf '  started : %s   (hook pre-agent — Task/Agent)\n' "$st"
  printf '  received: %s   (hook subagent-stop)\n'        "$rc"
  printf '  accepted: %s   (maestro order --accept)\n'    "$ac"
  if (( pl == 0 && st == 0 && rc == 0 && ac == 0 )); then
    echo '  sem delegação registrada nesta sessão (mode direct não passa por aqui)'
  elif (( st == 0 )); then
    echo '  ATENÇÃO: planejada e NÃO disparada — nenhum subagente saiu do papel nesta sessão'
  elif (( rc == 0 )); then
    echo '  ATENÇÃO: disparada sem retorno registrado — subagente ainda em voo ou morto no meio'
  else
    echo '  delegação provada: disparo e retorno no log'
  fi
  return 0
}

cmd_delegation() { # E23a/S-2301: o funil da delegação, contado no log
  # O buraco entre uma fase e a seguinte é o diagnóstico: planned sem started
  # é aposta que não saiu do papel; started sem received é subagente que
  # morreu no meio.
  local sid="" all=0
  while (( $# )); do
    case "$1" in
      --session) sid="${2:-}"; shift ;;
      --all)     all=1 ;;
      *) die validation "flag desconhecida '$1'" \
           "maestro delegation --session <id> | --all" 1 ;;
    esac
    shift
  done
  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"

  if (( all == 1 )); then
    _delegation_print_all
    return 0
  fi

  [[ "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || die validation "session_id obrigatório" \
    "maestro delegation --session <id> | --all" 1
  _delegation_print_session "$sid"
}
