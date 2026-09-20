#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ENGINE="$HERE/baseline_engine.py"

die() { printf 'baseline-metadado: %s\n' "$1" >&2; exit 1; }
PY="${LAYA_PYTHON:-python3.13}"
LOG="${LAYA_LOG:-$HOME/.maestro/logs/routing.jsonl}"

command -v jq >/dev/null 2>&1 || die "jq não encontrado"

m1_pairs_json() {
  local log="$1"
  [[ -f "$log" ]] || { printf '[]'; return 0; }
  jq -R 'fromjson? // empty' "$log" 2>/dev/null | jq -rsf "$HERE/m1-pairs.jq"
}

measure() {
  local pairs; pairs=$(m1_pairs_json "$LOG")
  local n; n=$(printf '%s' "$pairs" | jq 'length')
  [[ "$n" -eq 182 ]] || die "Esperava 182 pares, achei $n"
  
  local split; split=$(printf '%s' "$pairs" | jq -L "$HERE" -f "$HERE/baseline-split.jq")
  
  local n_ajuste; n_ajuste=$(printf '%s' "$split" | jq '.ajuste | length')
  local n_teste; n_teste=$(printf '%s' "$split" | jq '.teste | length')
  
  printf 'M1: %d pares -> split %d ajuste + %d teste\n' "$n" "$n_ajuste" "$n_teste" >&2
  
  local work; work=$(mktemp -d) || die "mktemp falhou"
  trap "rm -rf '$work'" RETURN
  
  printf '%s' "$split" | "$PY" "$ENGINE" > "$work/predictions.jsonl" 2> "$work/engine.stderr"
  local rc=$?
  [[ $rc -eq 0 ]] || { cat "$work/engine.stderr" >&2; die "engine falhou (rc=$rc)"; }
  
  # Calcula métricas simples com jq
  jq -n \
    --slurpfile preds "$work/predictions.jsonl" \
    --argjson split "$split" \
    '
    ($preds | flatten) as $p
    | ($p | length) as $n_test
    | ($p | map(.correct) | add) as $correct_count
    | ($correct_count / $n_test) as $acc
    | ($split.ajuste | map(select(.outcome == "accepted")) | length) as $base_count
    | ($base_count / ($split.ajuste | length)) as $base_rate
    | ($split.teste | map(select(.outcome == "rework")) | length) as $n_rework
    | ($p | map(select(.true_label == "rework" and .predicted == "rework")) | length) as $n_rework_correct
    | (if $n_rework > 0 then ($n_rework_correct / $n_rework) else 0 end) as $recall_rework
    | ($p | map((.p_pred - .correct) * (.p_pred - .correct)) | add / $n_test) as $brier
    | {
        acc: $acc,
        base_rate: $base_rate,
        n_test: $n_test,
        recall_rework: $recall_rework,
        n_rework: $n_rework,
        brier: $brier,
        preds: $p
      }
    ' > "$work/metrics.json"
  
  local metrics; metrics=$(cat "$work/metrics.json")
  local acc; acc=$(printf '%s' "$metrics" | jq -r '.acc')
  local base_rate; base_rate=$(printf '%s' "$metrics" | jq -r '.base_rate')
  local n_test; n_test=$(printf '%s' "$metrics" | jq -r '.n_test')
  local recall_rework; recall_rework=$(printf '%s' "$metrics" | jq -r '.recall_rework')
  local n_rework; n_rework=$(printf '%s' "$metrics" | jq -r '.n_rework')
  local brier; brier=$(printf '%s' "$metrics" | jq -r '.brier')
  
  cat > "$HERE/baseline-metadado.tsv" << EOF
# tests/eval/baseline-metadado.tsv — baseline (regressão logística L2=0.1), ordem 035. n=$n_test.
# base_rate(accepted) = $base_rate
# acuracia_geral = $acc
# recall_rework (n=$n_rework) = $recall_rework
# Brier = $brier
# L2 = 0.1 (fixo, declarado antes de qualquer medição).
# Colunas: id	true_label	predicted	p_pred	correct
id	true_label	predicted	p_pred	correct
EOF
  printf '%s' "$metrics" | jq -r '.preds[] | "\(.id)\t\(.true_label)\t\(.predicted)\t\(.p_pred)\t\(.correct)"' \
    >> "$HERE/baseline-metadado.tsv"
  
  printf 'Baseline: %s\n' "$HERE/baseline-metadado.tsv" >&2
}

selftest() {
  printf '## baseline-metadado --selftest\n'
  local fixture; fixture=$(jq -n '[
    {project: "p1", workflow: "w1", mode: "m1", agents: ["a1"], tool: "t1", file_ext: ".py", outcome: "accepted"},
    {project: "p1", workflow: "w1", mode: "m1", agents: ["a1"], tool: "t1", file_ext: ".py", outcome: "accepted"},
    {project: "p2", workflow: "w2", mode: "m2", agents: ["a2"], tool: "t2", file_ext: ".ts", outcome: "rework"},
    {project: "p2", workflow: "w2", mode: "m2", agents: ["a2"], tool: "t2", file_ext: ".ts", outcome: "rework"},
    {project: "p1", workflow: "w1", mode: "m1", agents: ["a1"], tool: "t1", file_ext: ".py", outcome: "accepted"},
    {project: "p2", workflow: "w2", mode: "m2", agents: ["a2"], tool: "t2", file_ext: ".ts", outcome: "rework"}
  ]')
  local split; split=$(printf '%s' "$fixture" | jq '{ajuste: .[0:3], teste: .[3:6]}')
  local work; work=$(mktemp -d) || die "mktemp"
  trap "rm -rf '$work'" RETURN
  printf '%s' "$split" | "$PY" "$ENGINE" > "$work/predictions.jsonl" 2> "$work/engine.stderr"
  [[ $? -eq 0 ]] || { cat "$work/engine.stderr" >&2; die "selftest: engine"; }
  local n_preds; n_preds=$(wc -l < "$work/predictions.jsonl")
  [[ "$n_preds" -eq 3 ]] || die "selftest: esperava 3, achei $n_preds"
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
