#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/baseline_engine.py"
CALC="$HERE/baseline-calc-metrics.py"

die() { printf 'baseline-metadado: %s\n' "$1" >&2; exit 1; }
PY="${LAYA_PYTHON:-python3.13}"
LOG="${LAYA_LOG:-$HOME/.maestro/logs/routing.jsonl}"

command -v jq >/dev/null 2>&1 || die "jq não encontrado"

# Prioridade 1: dependencia de terceiro ausente PULA com honestidade (exit 0),
# nunca reprova. numpy vive na venv; sem ela, nao ha o que medir aqui.
skip_sem_numpy() {
  command -v "$PY" >/dev/null 2>&1 || {
    printf 'baseline-metadado: PULADO — interpretador "%s" ausente (aponte LAYA_PYTHON para a venv)\n' "$PY"
    exit 0
  }
  "$PY" -c 'import numpy' >/dev/null 2>&1 || {
    printf 'baseline-metadado: PULADO — numpy ausente em "%s" (aponte LAYA_PYTHON para a venv)\n' "$PY"
    exit 0
  }
}

m1_pairs_json() {
  local log="$1"
  [[ -f "$log" ]] || { printf '[]'; return 0; }
  jq -R 'fromjson? // empty' "$log" 2>/dev/null | jq -rsf "$HERE/m1-pairs.jq"
}

measure() {
  skip_sem_numpy
  local pairs; pairs=$(m1_pairs_json "$LOG")
  local n; n=$(printf '%s' "$pairs" | jq 'length')
  [[ "$n" -eq 182 ]] || die "Esperava 182 pares, achei $n"
  
  pairs=$(printf '%s' "$pairs" | jq 'to_entries | map(.value + {id: "m1-\(.key)"})')
  
  local work; work=$(mktemp -d) || die "mktemp falhou"
  trap "rm -rf '$work'" RETURN
  
  printf '%s' "$pairs" | "$PY" "$ENGINE" > "$work/predictions.jsonl" 2> "$work/engine.stderr"
  local rc=$?
  [[ $rc -eq 0 ]] || { cat "$work/engine.stderr" >&2; die "engine falhou (rc=$rc)"; }
  
  local metrics; metrics=$(cat "$work/predictions.jsonl" | "$PY" "$CALC")
  
  local acc; acc=$(printf '%s' "$metrics" | jq -r '.acc')
  local ci_lower; ci_lower=$(printf '%s' "$metrics" | jq -r '.ci_lower')
  local ci_upper; ci_upper=$(printf '%s' "$metrics" | jq -r '.ci_upper')
  local n_test; n_test=$(printf '%s' "$metrics" | jq -r '.n_test')
  local brier; brier=$(printf '%s' "$metrics" | jq -r '.brier')
  local ece; ece=$(printf '%s' "$metrics" | jq -r '.ece')
  local auc; auc=$(printf '%s' "$metrics" | jq -r '.auc')
  
  local n_rework; n_rework=$(printf '%s' "$pairs" | jq 'map(select(.outcome == "rework")) | length')
  local n_rework_correct; n_rework_correct=$(printf '%s' "$metrics" | jq '.preds | map(select(.true_label == "rework" and .predicted == "rework")) | length')
  
  local recall_rework="0"
  if [[ "$n_rework" -gt 0 ]]; then
    recall_rework=$(printf '%s' "$metrics" | jq -r "(.preds | map(select(.true_label == \"rework\" and .predicted == \"rework\")) | length) / $n_rework")
  fi
  
  cat > "$HERE/baseline-metadado.tsv" << EOF
# tests/eval/baseline-metadado.tsv — baseline (L2=0.1), 5-fold CV, n=$n_test (corpus 182).
# base_rate (corpus) = 0.7857142857142857
# acuracia_geral (CV) = $acc · IC 95% [$ci_lower, $ci_upper]
# recall_rework (n=$n_rework) = $recall_rework
# Brier = $brier · ECE = $ece (15 faixas de largura igual, ponderadas pelo n) · AUC = $auc (empate = 0,5)
# L2 = 0.1 (fixo, declarado antes de qualquer medição).
# Colunas: id	true_label	predicted	p_pred	correct	fold
id	true_label	predicted	p_pred	correct	fold
EOF
  printf '%s' "$metrics" | jq -r '.preds[] | "\(.id)\t\(.true_label)\t\(.predicted)\t\(.p_pred)\t\(.correct)\t\(.fold)"' \
    >> "$HERE/baseline-metadado.tsv"
  
  printf 'Baseline: %s\n' "$HERE/baseline-metadado.tsv" >&2
}

selftest() {
  printf '## baseline-metadado --selftest\n'
  skip_sem_numpy
  local work; work=$(mktemp -d) || die "mktemp"
  trap "rm -rf '$work'" RETURN
  
  cat > "$work/fixture.json" << 'EOF'
[
  {"id": "s-0", "project": "p1", "workflow": "w1", "mode": "m", "agents": ["a"], "tool": "t", "file_ext": ".py", "outcome": "accepted"},
  {"id": "s-1", "project": "p1", "workflow": "w1", "mode": "m", "agents": ["a"], "tool": "t", "file_ext": ".py", "outcome": "accepted"},
  {"id": "s-2", "project": "p2", "workflow": "w2", "mode": "m", "agents": ["b"], "tool": "t", "file_ext": ".ts", "outcome": "rework"},
  {"id": "s-3", "project": "p2", "workflow": "w2", "mode": "m", "agents": ["b"], "tool": "t", "file_ext": ".ts", "outcome": "rework"},
  {"id": "s-4", "project": "p1", "workflow": "w1", "mode": "m", "agents": ["a"], "tool": "t", "file_ext": ".py", "outcome": "accepted"},
  {"id": "s-5", "project": "p2", "workflow": "w2", "mode": "m", "agents": ["b"], "tool": "t", "file_ext": ".ts", "outcome": "rework"}
]
EOF
  
  cat "$work/fixture.json" | "$PY" "$ENGINE" > "$work/predictions.jsonl" 2> "$work/engine.stderr"
  [[ $? -eq 0 ]] || { cat "$work/engine.stderr" >&2; die "selftest: engine"; }
  local n_preds; n_preds=$(wc -l < "$work/predictions.jsonl")
  [[ "$n_preds" -gt 0 ]] || die "selftest: nenhuma predição"
  printf 'selftest: OK ✓\n'
}

main() {
  case "${1:---help}" in
    --selftest) selftest ;;
    --measure) measure ;;
    *) die "opção desconhecida: $1" ;;
  esac
}
main "$@"
