#!/usr/bin/env bash
# tests/eval/laya-spike-selftest.sh — asserções do harness com fixture
# sintética; NÃO exige venv/pacote/checkpoint. Sourced por laya-spike.sh.
#
# Cada bloco de asserção é uma função nomeada por RESPONSABILIDADE (m1-pairs,
# engine, lib de estatística, TSV) — `selftest()` só soma os `$?`.
t()   { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; echo "       esperado: $2"; echo "       obtido:   $3"; return 1; fi; }
has() { if [[ "$2" == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1 (obtido: $2)"; return 1; fi; }

# m1-pairs.jq: outcome sem decision antes fica de fora; tool/file_ext vêm do
# gate mais recente DA SESSÃO e carregam entre decisões se não houver gate
# novo (é o que o comentário do m1-pairs.jq documenta: "antes do outcome",
# não "desde a decision"); sessão sem gate nenhum -> null.
_selftest_m1() {
  local fail=0 tmp="$1"
  cat >"$tmp/log.jsonl" <<'EOF'
{"event":"decision","session_id":"s1","workflow":"fix","mode":"direct","project":"p1"}
{"event":"gate_pass","session_id":"s1","tool":"Edit","file_ext":".go"}
{"event":"outcome","session_id":"s1","outcome":"accepted"}
{"event":"decision","session_id":"s1","workflow":"feature","mode":"multi","agents":["python-pro"],"project":"p1"}
{"event":"outcome","session_id":"s1","outcome":"rework"}
{"event":"outcome","session_id":"s2","outcome":"killed"}
{"event":"decision","session_id":"s3","workflow":"custom","mode":"direct","project":"p3"}
{"event":"outcome","session_id":"s3","outcome":"accepted"}
EOF
  local pairs; pairs=$(m1_pairs_json "$tmp/log.jsonl")
  t "(m1) 3 pares (s2 sem decision antes fica de fora)" "3" "$(printf '%s' "$pairs" | jq 'length')" || fail=1
  t "(m1) 1o par herda tool/file_ext do gate" ".go" "$(printf '%s' "$pairs" | jq -r '.[0].file_ext')" || fail=1
  t "(m1) 2o par carrega o MESMO gate (nenhum gate novo entre decisions)" ".go" "$(printf '%s' "$pairs" | jq -r '.[1].file_ext')" || fail=1
  t "(m1) sessão sem gate nenhum -> null" "null" "$(printf '%s' "$pairs" | jq -r '.[2].file_ext')" || fail=1
  t "(m1) rótulos na ordem certa" "accepted rework accepted" "$(printf '%s' "$pairs" | jq -r '[.[].outcome] | join(" ")')" || fail=1
  return $fail
}

# laya_engine.py: contrato stdin/stdout em modo stub (sem torch/laya).
_selftest_engine() {
  local fail=0 tmp="$1"
  local eng_out
  eng_out=$(printf '{"id":"x1","state":{"a":1},"questions":{"q1":{"type":"choice","criteria":{"y":"","n":""}}}}\n' \
    | LAYA_ENGINE_STUB=1 "$PY" "$ENGINE" --predict 2>"$tmp/eng.err")
  has "(engine) --predict devolve id" "$eng_out" '"id": "x1"' || fail=1
  has "(engine) --predict devolve choice" "$eng_out" '"choice"' || fail=1
  has "(engine) --predict devolve confidence" "$eng_out" '"confidence"' || fail=1

  local eng_bad_rc
  printf '{"id":"x2","state":{},"questions":"nao-e-um-dict"}\n' \
    | LAYA_ENGINE_STUB=1 "$PY" "$ENGINE" --predict >"$tmp/eng-bad.out" 2>/dev/null
  eng_bad_rc=$?
  has "(engine) registro malformado não derruba o processo" "$(cat "$tmp/eng-bad.out")" '"error"' || fail=1
  t "(engine) rc=1 quando algum registro falhou" "1" "$eng_bad_rc" || fail=1

  local info_out; info_out=$(LAYA_ENGINE_STUB=1 "$PY" "$ENGINE" --info)
  has "(engine) --info em modo stub não importa torch" "$info_out" '"torch": "stub"' || fail=1
  return $fail
}

# laya-lib.jq: valores hand-computed.
_selftest_lib() {
  local fail=0
  local stat
  stat=$(jq -n -L "$HERE" 'import "laya-lib" as lib;
    [{id:"a",correct:1,confidence:1.0},{id:"b",correct:0,confidence:1.0}] as $xs
    | {brier: lib::brier($xs), acc: lib::accuracy($xs)}')
  t "(lib) brier de confiança perfeita errada = 0.5" "0.5" "$(printf '%s' "$stat" | jq -r '.brier')" || fail=1
  t "(lib) accuracy 1/2" "0.5" "$(printf '%s' "$stat" | jq -r '.acc')" || fail=1

  local ece_n
  ece_n=$(jq -n -L "$HERE" 'import "laya-lib" as lib;
    [range(0;20) | {id: ("i" + (.|tostring)), correct: (if . < 16 then 1 else 0 end), confidence: 0.8}] as $xs
    | lib::ece_table($xs; 15).rows | map(select(.n > 0)) | length')
  has "(lib) ece_table só produz linhas para faixas com n>0" "$ece_n" "1" || fail=1

  local split_ok
  split_ok=$(jq -n -L "$HERE" 'import "laya-lib" as lib;
    [range(0;10) | {id: ("i" + (.|tostring)), cls: "x", correct: 1, confidence: 0.9}] as $xs
    | lib::split_stratified($xs; "id"; "cls") | (.ajuste|length) + (.teste|length)')
  t "(lib) split estratificado preserva o total" "10" "$split_ok" || fail=1
  return $fail
}

# deps check não explode quando ausente; TSV writer produz cabeçalho
# comentado + linhas.
_selftest_deps_and_tsv() {
  local fail=0 tmp="$1"
  local dep_out; dep_out=$(LAYA_PYTHON=/bin/nao-existe check_deps 2>&1) || true
  has "(deps) python ausente vira skip com motivo, não crash" "$dep_out" "skip:" || fail=1

  local fake='[{"id":"m1-0","true_label":"accepted","predicted":"accepted","confidence":0.9,"correct":1},{"id":"m1-1","true_label":"rework","predicted":"accepted","confidence":0.6,"correct":0}]'
  printf '%s' "$fake" | jq . >"$tmp/joined.json"
  _m1_write_tsv "$tmp/joined.json" "$tmp/out.tsv"
  has "(tsv) header comentado com base_rate" "$(cat "$tmp/out.tsv")" "base_rate" || fail=1
  t "(tsv) 2 linhas de dado + 7 linhas de header" "9" "$(wc -l <"$tmp/out.tsv" | tr -d ' ')" || fail=1
  return $fail
}

selftest() {
  local fail=0
  local tmp; tmp=$(mktemp -d) || die "mktemp falhou"

  _selftest_m1 "$tmp"            || fail=1
  _selftest_engine "$tmp"        || fail=1
  _selftest_lib                  || fail=1
  _selftest_deps_and_tsv "$tmp"  || fail=1

  rm -rf "$tmp"
  return $fail
}
