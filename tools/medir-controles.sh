#!/usr/bin/env bash
# tools/medir-controles.sh — tempo por chamada dos controles do Maestro (ordem 061).
# SOMENTE LEITURA sobre o repo e sobre ~/.maestro: tudo roda em fixtures de sandbox
# (MAESTRO_HOME e projeto em mktemp -d), nunca contra projeto real. Sem rede.
# Método: tests/lib/latency.sh (mediana de N amostras, ms inteiros, sonda da máquina).
# Saída: TSV `controle<TAB>mediana_ms<TAB>min_ms<TAB>max_ms` em stdout; a sonda e a carga
# vão no cabeçalho (#). Só inteiros.
# Uso: tools/medir-controles.sh [N]    (default N=31, MAESTRO_LATENCY_N)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
[[ -n "${1:-}" ]] && export MAESTRO_LATENCY_N="$1"
source "$REPO/tests/lib/latency.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export MAESTRO_HOME="$TMP/home"
export MAESTRO_NO_UPDATE_CHECK=1
P="$TMP/proj"
mkdir -p "$MAESTRO_HOME/sessions" "$MAESTRO_HOME/logs" "$P/src" "$P/docs"
export CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_ROOT="$REPO"
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }
git -C "$P" init -q -b main
printf 'x\n' > "$P/README.md"; G add -A; G commit -qm base

SID=med061
cat > "$MAESTRO_HOME/gate-policy.sh" <<EOF
MAESTRO_GATE_MODE="block"
MAESTRO_GATE_ALLOW_EXT=".md .txt"
MAESTRO_GATE_ALLOW_PATHS=".maestro/ docs/"
MAESTRO_GATE_DENY_PATHS="agents/ bin/ hooks/ config/routing-table.yaml .claude/ .claude-plugin/ .github/workflows/"
MAESTRO_PLUGIN_ROOT="$REPO"
EOF
now=$(date -Iseconds); exp=$(date -Iseconds -d "@$(( $(date +%s) + 14400 ))")
printf '{"session_id":"%s","ts":"%s","expires_at":"%s","workflow":"fix","mode":"direct","reason":"medicao"}\n' "$SID" "$now" "$exp" > "$MAESTRO_HOME/sessions/$SID.json"

# arquivo com aninhamento profundo para o hook de habits
{ echo '#!/usr/bin/env bash'; for i in $(seq 1 40); do echo "f$i() { if true; then if true; then if true; then if true; then echo $i; fi; fi; fi; fi; }"; done; } > "$P/src/amostra.sh"

mk() { printf '%s' "$2" > "$TMP/$1.json"; }
mk gate_pass   "{\"session_id\":\"$SID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/src/amostra.sh\"}}"
mk gate_block  "{\"session_id\":\"$SID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/hooks/x.sh\"}}"
mk bash_ok     "{\"session_id\":\"$SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"}}"
mk bash_perigo "{\"session_id\":\"$SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /tmp/amostra-x\"}}"
mk agent       "{\"session_id\":\"$SID\",\"tool_name\":\"Agent\",\"tool_input\":{}}"
mk ask         "{\"session_id\":\"$SID\",\"tool_name\":\"mcp__ponte__director_ask\",\"tool_input\":{}}"
mk prompt_n    "{\"session_id\":\"$SID\",\"prompt\":\"oi\"}"
mk prompt_cmd  "{\"session_id\":\"$SID\",\"prompt\":\"/gstack-qa agora\"}"
mk habits      "{\"session_id\":\"$SID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/src/amostra.sh\"}}"
mk sstart      "{\"session_id\":\"$SID\",\"source\":\"startup\"}"
mk send        "{\"session_id\":\"$SID\",\"reason\":\"other\"}"
mk sastop      "{\"session_id\":\"$SID\"}"
mk stop        "{\"session_id\":\"$SID\",\"stop_hook_active\":false}"

echo "# tools/medir-controles.sh N=$MAESTRO_LATENCY_N"
maestro_latency_read_load
maestro_latency_probe "$REPO/hooks/pre-tool-gate.sh"
echo "# sonda_ms=${PROBE_MS} load1m=${MAESTRO_LATENCY_LOAD1M} ncpu=${MAESTRO_LATENCY_NCPU}"
printf 'controle\tmed_ms\tmin_ms\tmax_ms\n'

hook() { # <rotulo> <hook> <payload>
  ( cd "$P" && maestro_latency_measure "$REPO/hooks/$2" "$TMP/$3.json" && printf '%s\t%s\t%s\t%s\n' "$1" "$MED" "$MIN" "$MAX" )
}
cli() { # <rotulo> <cmd...>
  local lbl="$1"; shift
  local n="$MAESTRO_LATENCY_N" i t0 t1 ts=() sorted
  ( cd "$P" || exit
    for i in 1 2 3; do "$@" >/dev/null 2>&1; done
    for ((i = 0; i < n; i++)); do
      t0="${EPOCHREALTIME/./}"; "$@" >/dev/null 2>&1; t1="${EPOCHREALTIME/./}"
      ts+=( $(( (t1 - t0) / 1000 )) )
    done
    mapfile -t sorted < <(printf '%s\n' "${ts[@]}" | sort -n)
    printf '%s\t%s\t%s\t%s\n' "$lbl" "${sorted[$((n / 2))]}" "${sorted[0]}" "${sorted[$((n - 1))]}" )
}

hook hook:session-start            session-start.sh        sstart
hook hook:pre-tool-gate/passa      pre-tool-gate.sh        gate_pass
hook hook:pre-tool-gate/bloqueia   pre-tool-gate.sh        gate_block
hook hook:pre-bash-guard/passa     pre-bash-guard.sh       bash_ok
hook hook:pre-bash-guard/perigo    pre-bash-guard.sh       bash_perigo
hook hook:pre-agent                pre-agent.sh            agent
hook hook:pre-director-ask         pre-director-ask.sh     ask
hook hook:user-prompt-submit/texto user-prompt-submit.sh   prompt_n
hook hook:user-prompt-submit/comando user-prompt-submit.sh prompt_cmd
hook hook:post-edit-habits         post-edit-habits.sh     habits
hook hook:session-end              session-end.sh          send
hook hook:subagent-stop            subagent-stop.sh        sastop
hook hook:gate-report              gate-report.sh          stop
hook hook:stop-turno               stop-turno.sh           stop

# kill-switch: o piso de qualquer hook
( cd "$P" && export MAESTRO_OFF=1 && maestro_latency_measure "$REPO/hooks/pre-tool-gate.sh" "$TMP/gate_pass.json" && printf 'guarda:kill-switch\t%s\t%s\t%s\n' "$MED" "$MIN" "$MAX" )

BIN="$REPO/bin/maestro"
cli cli:habits-all     "$BIN" habits --all
cli cli:conform-check  "$BIN" conform --check "$P"
cli cli:doctor         "$BIN" doctor --ci
cli cli:verify-check   "$BIN" verify --check
cli cli:evidence       "$BIN" evidence
cli cli:order-list     "$BIN" order --list
