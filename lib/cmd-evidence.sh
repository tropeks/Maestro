#!/usr/bin/env bash
# maestro lib/cmd-evidence.sh — E13/S-1301, extraído de bin/maestro na ordem
# 009 (E24, docs/designs/e24-nucleo-e-adaptadores.md).
#
# `maestro evidence`: recibo de execução amarrado a CONTEÚDO (padrão
# gstack-evidence). "Testes passaram" deixa de ser prosa: o recibo grava
# wtree (S-701) ANTES e DEPOIS da execução, hash do comando, exit e idade. A
# leitura só diz VÁLIDA se o conteúdo de AGORA é byte-idêntico ao provado, o
# comando é o mesmo, a idade cabe no teto e nada mexeu na árvore DURANTE a
# corrida. A IRON LAW vira checagem mecânica, não sistema de honra.
#
# O FORMATO do recibo (escrita/leitura crua) mora em lib/core-evidence.sh —
# esta lib só orquestra o CLI (parsing de flags, medição, execução do
# comando, impressão). Sourced por bin/maestro (via _ev_lib_load, I-2) DENTRO
# do mesmo processo — REPO_DIR, MAESTRO_HOME e die() já no escopo.
#
# `maestro_verif_load`/`maestro_verif_cmd`/`verif_record_hint` (lib/cmd-verify.sh,
# ordem 011) NÃO estão residentes: cada função que os usa chama
# `_verif_lib_load` antes (mesma técnica de `_ev_lib_load`), degradando por
# comando (I-2) em vez de assumir carregamento alheio — acoplamento mapeado
# pela ordem A e resolvido aqui.
#
# Convenção (lote do `order`, E24): parâmetro posicional, nenhuma função
# fecha sobre local de outra. Exceção documentada: EV_RUN_* abaixo, no molde
# de TEL_STATE/TEL_HOST (hooks/lib/telemetry-sync.sh) — a saída do comando
# medido precisa passar direto pro terminal (tee), então não pode virar
# `$(...)`; o retorno viaja por essas duas globals do MÓDULO, documentadas.

# --------------------------------------------------------- medição (record)
_ev_cmd_measure_load() { # → "load1m_x100<US>ncpu" (US=\x1f; TAB é IFS-whitespace e engoliria campo vazio) — issue #11, ordem 005
  local load1m_x100=0 ncpu=1 _loadavg
  if read -r _loadavg _ < /proc/loadavg 2>/dev/null; then
    load1m_x100="${_loadavg/./}"
    [[ "$load1m_x100" =~ ^[0-9]+$ ]] && load1m_x100=$((10#$load1m_x100)) || load1m_x100=0
  fi
  ncpu=$(nproc 2>/dev/null) || ncpu=1
  [[ "$ncpu" =~ ^[0-9]+$ ]] || ncpu=1
  printf '%s\x1f%s\n' "$load1m_x100" "$ncpu"
  return 0
}

# ordem 016 PR1: sonda de baseline. N invocações NO-OP do próprio hook pelo
# caminho do kill-switch (MAESTRO_OFF=1) — o piso já documentado no modelo de
# custo de tests/lib/latency.sh ("~3ms bash+source, custo do kill-switch
# sozinho"): mesmo binário, mesmo interpretador, mesmo `source` de
# lib/common.sh, zero trabalho depois disso. Mede a CAPACIDADE desta máquina
# NESTA corrida — carga (acima) mede contenção; a sonda mede quão rápido a
# forge executa um piso fixo. hooks/pre-tool-gate.sh é o alvo: já é tratado
# como o hook de referência do comportamento do plugin em bin/maestro (lista
# de arquivos que o doctor considera "definem comportamento"); o piso medido
# aqui é o do KILL-SWITCH em si, que é o MESMO custo em qualquer hook
# (maestro_killswitch roda antes de qualquer lógica específica de cada um).
# PR1 só MEDE e GRAVA (probe_ms no recibo, ver _ev_write / core-evidence.sh);
# o teto de latência continua decidido como hoje — o fator ÷SONDA_REF é do
# PR2, depois que a CI publicar o número de referência.
#
# N=11: mesma técnica de amostragem de tests/lib/latency.sh (mediana contra
# outlier de scheduler), só que menor — a sonda roda a CADA
# `evidence --record` (potencialmente muitas vezes por sessão), então
# repetir as 31 amostras da suíte de teste aqui seria desperdício; 11 é
# ímpar (mediana sem empate) e já estabiliza o bastante para o que o PR1
# precisa provar (razão estável entre faixas de carga). `/dev/null` como
# stdin: o kill-switch sai antes de qualquer leitura de payload
# (hooks/lib/common.sh:maestro_killswitch).
_ev_cmd_measure_probe() { # → probe_ms (mediana de N invocações no-op via MAESTRO_OFF=1)
  local bin="$REPO_DIR/hooks/pre-tool-gate.sh" n=11 i t0 t1 ts=() probe_ms=0
  if [[ -x "$bin" ]]; then
    for ((i = 0; i < n; i++)); do
      t0="${EPOCHREALTIME/./}"
      MAESTRO_OFF=1 "$bin" < /dev/null >/dev/null 2>&1
      t1="${EPOCHREALTIME/./}"
      ts+=( $(( (t1 - t0) / 1000 )) )
    done
    local sorted
    mapfile -t sorted < <(printf '%s\n' "${ts[@]}" | sort -n)
    probe_ms="${sorted[$((n / 2))]}"
  fi
  [[ "$probe_ms" =~ ^[0-9]+$ ]] || probe_ms=0
  printf '%s' "$probe_ms"
  return 0
}

_ev_cmd_match() { # <proj> <label> <cmd_str> → "decl<US>cmd_match" (US=\x1f: decl pode vir vazio, TAB perderia o campo)
  local proj="$1" label="$2" cmd_str="$3" decl cmd_match="free"
  _verif_lib_load   # ordem 011: maestro_verif_load não é mais residente
  maestro_verif_load
  decl=$(maestro_verif_cmd "$proj" "$label") || decl=""
  if [[ -n "$decl" ]]; then
    [[ "$decl" == "$cmd_str" ]] && cmd_match="yes" || cmd_match="no"
  fi
  printf '%s\x1f%s\n' "$decl" "$cmd_match"
  return 0
}

EV_RUN_RC=0            # saída do último _ev_cmd_run — ver nota de convenção acima
EV_RUN_INCONCLUSIVE=0  # idem: nº de linhas com a palavra do protocolo de latência compartilhado

_ev_cmd_run() { # <proj> -- <comando...> → roda em $proj; grava EV_RUN_RC/EV_RUN_INCONCLUSIVE
  local proj="$1"; shift
  [[ "${1:-}" == "--" ]] && shift
  EV_RUN_RC=0; EV_RUN_INCONCLUSIVE=0
  local out_tmp
  out_tmp=$(mktemp 2>/dev/null) || out_tmp=""
  # set -e: exit != 0 é DADO (a falha é o que mais precisa de recibo), nunca
  # aborto — o || blinda a captura. Ver bin/maestro (comentário original,
  # issue #11) para o porquê do `if` em vez de `| ... || true` (reseta
  # PIPESTATUS e mascara o exit real do comando medido).
  if [[ -n "$out_tmp" ]]; then
    if ( cd "$proj" && "$@" ) 2>&1 | tee "$out_tmp"; then
      EV_RUN_RC=0
    else
      EV_RUN_RC="${PIPESTATUS[0]}"
    fi
    EV_RUN_INCONCLUSIVE=$(grep -ci -- 'inconclusivo' "$out_tmp" 2>/dev/null) || EV_RUN_INCONCLUSIVE=0
    [[ "$EV_RUN_INCONCLUSIVE" =~ ^[0-9]+$ ]] || EV_RUN_INCONCLUSIVE=0
    rm -f "$out_tmp" 2>/dev/null
  else
    ( cd "$proj" && "$@" ) || EV_RUN_RC=$?
  fi
  return 0
}

_ev_cmd_record() { # <proj> <label> <arquivo do recibo> -- <comando...> → grava; rc = exit do comando
  local proj="$1" label="$2" ef="$3"; shift 3
  [[ "${1:-}" == "--" ]] && shift
  [[ $# -gt 0 ]] || die validation "comando ausente" \
    "maestro evidence --record -- bash tests/run-all.sh" 1
  local w_before="none" w_after="none" cmd_str cmd_hash
  [[ -x "$REPO_DIR/bin/maestro-wtree" ]] && \
    w_before=$("$REPO_DIR/bin/maestro-wtree" "$proj" 2>/dev/null) || w_before="none"
  cmd_str="$*"
  cmd_hash=$(printf '%s' "$cmd_str" | sha256sum 2>/dev/null | head -c 16) || cmd_hash="none"
  local decl cmd_match load1m_x100 ncpu probe_ms
  IFS=$'\x1f' read -r decl cmd_match <<<"$(_ev_cmd_match "$proj" "$label" "$cmd_str")"
  IFS=$'\x1f' read -r load1m_x100 ncpu <<<"$(_ev_cmd_measure_load)"
  # ordem 016 PR1: sonda medida no INÍCIO da corrida, antes do comando sob
  # prova rodar — mede a capacidade da máquina, não o efeito do comando nela.
  probe_ms=$(_ev_cmd_measure_probe)
  _ev_cmd_run "$proj" -- "$@"
  [[ -x "$REPO_DIR/bin/maestro-wtree" ]] && \
    w_after=$("$REPO_DIR/bin/maestro-wtree" "$proj" 2>/dev/null) || w_after="none"
  _ev_write "$ef" "$label" "$cmd_hash" "$EV_RUN_RC" "$w_before" "$w_after" "$cmd_match" \
    "$load1m_x100" "$ncpu" "$EV_RUN_INCONCLUSIVE" "$probe_ms" \
    || die env "falha ao gravar recibo" "cheque permissões/MAESTRO_HOME" 2
  if [[ "$w_before" != "$w_after" ]]; then
    printf 'evidência gravada: %s — exit %s, mas a árvore MUDOU durante a execução (recibo nasce contaminado)\n' \
      "$label" "$EV_RUN_RC"
  else
    printf 'evidência gravada: %s — exit %s, conteúdo %s\n' "$label" "$EV_RUN_RC" "${w_after:0:12}"
  fi
  if [[ "$cmd_match" == "no" ]]; then
    printf '  ATENÇÃO: não é o comando declarado em .maestro.yaml (commands.%s: %s) — este recibo NÃO conta como verificação\n' \
      "$label" "$decl"
  fi
  return "$EV_RUN_RC"
}

# ------------------------------------------------------------ leitura/veredito
_ev_cmd_reasons() { # <label> <proj> <maxage> <age> <e_wb> <e_wa> <e_exit> <e_match> <e_hash> <decl_r> → motivos (vazio = válida)
  local label="$1" proj="$2" maxage="$3" age="$4" e_wb="$5" e_wa="$6" \
        e_exit="$7" e_match="$8" e_hash="$9" decl_r="${10}"
  local reasons="" w_now="none"
  [[ "$e_wb" != "$e_wa" ]] && reasons+="${reasons:+; }árvore mudou durante a corrida"
  (( age >= maxage )) && reasons+="${reasons:+; }idade no teto (${maxage}s)"
  [[ -x "$REPO_DIR/bin/maestro-wtree" ]] && \
    w_now=$("$REPO_DIR/bin/maestro-wtree" "$proj" 2>/dev/null) || w_now="none"
  [[ "$w_now" == "none" || "$e_wa" == "none" ]] && reasons+="${reasons:+; }sem git para comparar conteúdo"
  [[ "$w_now" != "none" && "$e_wa" != "none" && "$w_now" != "$e_wa" ]] \
    && reasons+="${reasons:+; }conteúdo mudou desde a prova"
  [[ "$e_exit" != "0" ]] && reasons+="${reasons:+; }a execução provou FALHA (exit $e_exit)"
  if [[ "$e_match" == "no" ]]; then
    reasons+="${reasons:+; }comando diferente do declarado em .maestro.yaml"
  elif [[ -n "$decl_r" && -n "$e_hash" && "$e_hash" != "none" ]] \
    && [[ "$e_hash" != "$(maestro_verif_hash "$decl_r")" ]]; then
    reasons+="${reasons:+; }comando do recibo ≠ commands.$label (.maestro.yaml)"
  fi
  printf '%s' "$reasons"
  return 0
}

_ev_cmd_qualifiers() { # <e_load> <load_limiar> <e_inc> → "load_qualif<US>inc_qualif" (US=\x1f: qualif pode vir vazio)
  local e_load="$1" load_limiar="$2" e_inc="$3" load_qualif="" load_str="" inc_qualif=""
  if [[ -n "$e_load" ]]; then
    load_str="$(( e_load / 100 )).$(printf '%02d' $(( e_load % 100 )))"
    if (( e_load > load_limiar )); then
      load_qualif=", mas fora do limiar de medição (load $load_str)"
    else
      load_qualif=" (load $load_str)"
    fi
  fi
  if [[ -n "$e_inc" ]] && (( e_inc > 0 )); then
    inc_qualif="; ${e_inc} medição(ões) INCONCLUSIVA(S) sob carga durante a corrida"
  fi
  printf '%s\x1f%s\n' "$load_qualif" "$inc_qualif"
  return 0
}

_ev_cmd_verdict() { # <proj> <label> <maxage> <load_limiar> <check> → imprime veredito; rc conforme --check
  local proj="$1" label="$2" maxage="$3" load_limiar="$4" check="$5" ef
  ef=$(maestro_evidence_file "$proj" "$label")
  _verif_lib_load   # ordem 011: maestro_verif_load não é mais residente
  maestro_verif_load
  if [[ ! -f "$ef" || ! -r "$ef" ]]; then
    echo "evidência ($label): NENHUMA — registre com: $(verif_record_hint "$proj" "$label")"
    (( check == 1 )) && return 1 || return 0
  fi
  local e_epoch="" e_exit="" e_wb="" e_wa="" e_hash="" e_match="" e_load="" e_ncpu="" e_inc="" e_probe=""
  eval "$(_ev_read_vars "$ef")" 2>/dev/null || :
  [[ -n "$e_match" ]] || e_match="free"
  if [[ -z "$e_epoch" || -z "$e_wa" ]]; then
    echo "evidência ($label): recibo ilegível — regrave"
    (( check == 1 )) && return 1 || return 0
  fi
  local age=$(( $(maestro_now_epoch) - e_epoch ))
  (( age < 0 )) && age=0
  local decl_r; decl_r=$(maestro_verif_cmd "$proj" "$label") || decl_r=""
  local reasons; reasons=$(_ev_cmd_reasons "$label" "$proj" "$maxage" "$age" \
    "$e_wb" "$e_wa" "$e_exit" "$e_match" "$e_hash" "$decl_r")
  local load_qualif inc_qualif
  IFS=$'\x1f' read -r load_qualif inc_qualif <<<"$(_ev_cmd_qualifiers "$e_load" "$load_limiar" "$e_inc")"
  if [[ -z "$reasons" ]]; then
    printf 'evidência (%s): VÁLIDA%s — exit 0 há %smin, conteúdo byte-idêntico ao provado%s\n' \
      "$label" "$load_qualif" "$(( age / 60 ))" "$inc_qualif"
    return 0
  fi
  if [[ -n "$decl_r" ]]; then
    printf 'evidência (%s): VENCIDA — %s%s. Re-rode e regrave: %s\n' "$label" "$reasons" "$inc_qualif" \
      "$(verif_record_hint "$proj" "$label")"
  else
    printf 'evidência (%s): VENCIDA — %s%s. Re-rode e regrave.\n' "$label" "$reasons" "$inc_qualif"
  fi
  (( check == 1 )) && return 1 || return 0
}

# ------------------------------------------------------------------ comando
cmd_evidence() { # S-1301: recibo de execução amarrado a CONTEÚDO (padrão gstack-evidence)
  local mode="read" label="suite" check=0 proj="${CLAUDE_PROJECT_DIR:-$PWD}" \
        maxage="${MAESTRO_EVIDENCE_MAX_AGE:-86400}"
  # issue #11 (ordem 005): limiar de carga para a QUALIFICAÇÃO da leitura —
  # mesmo número (load 1min ABSOLUTO ≤ 2,0) de tests/lib/latency.sh
  # (ARCHITECTURE.md §NFRs); duplicado de propósito — bin/ não sourceia
  # tests/. Override só para depurar.
  local load_limiar="${MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100:-200}"
  local cmd_args=()
  while (( $# )); do
    case "$1" in
      --record)  mode="record" ;;
      --check)   check=1 ;;
      --label)   label="${2:-}"; shift ;;
      --project) proj="${2:-}"; shift ;;
      --)        shift; cmd_args=("$@"); break ;;
      *) die validation "flag desconhecida '$1'" \
           "maestro evidence [--label l] [--check] | --record [--label l] -- <comando...>" 1 ;;
    esac
    shift
  done
  [[ "$label" =~ ^[a-z][a-z0-9-]{0,23}$ ]] || die validation "rótulo inválido" "minúsculas/dígitos/hífen, ≤24" 1
  [[ "$maxage" =~ ^[0-9]{1,8}$ ]] || maxage=86400
  [[ "$load_limiar" =~ ^[0-9]{1,6}$ ]] || load_limiar=200

  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  local ef; ef=$(maestro_evidence_file "$proj" "$label")

  if [[ "$mode" == "record" ]]; then
    _ev_cmd_record "$proj" "$label" "$ef" -- "${cmd_args[@]}"
    return $?
  fi
  _ev_cmd_verdict "$proj" "$label" "$maxage" "$load_limiar" "$check"
  return $?
}
