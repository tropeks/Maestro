#!/usr/bin/env bash
# tests/eval/laya-spike.sh — ordem 034: spike do motor System 1 local (Laya) medido
# com o MESMO instrumento que a ordem 028 prescreve para o Jev — acc, Brier, ECE,
# p50/p95, disco e RSS. Fica FORA de tests/run-all.sh de propósito (mesma razão do
# run-eval.sh: um spike não derruba CI por dependência de terceiro ausente).
#
# Arquitetura: o motor mora inteiro em laya_engine.py (a ÚNICA função Python da
# ordem — `predict(state, questions) -> {answers, model, latency_ms}`). Este script
# só deriva os corpora, chama o motor via stdin/stdout JSONL, e faz a estatística
# (laya-lib.jq). Trocar Laya por Jev quando a 028 rodar é reescrever o CORPO de
# `predict()`; nada aqui precisa saber o nome do pacote.
#
# Uso:
#   bash tests/eval/laya-spike.sh --selftest         asserções do harness, com
#                                                     fixture sintética — NÃO exige
#                                                     venv/pacote/checkpoint.
#   bash tests/eval/laya-spike.sh --m1 [--out F]      mede M1 (desfecho, n do log)
#   bash tests/eval/laya-spike.sh --m2 [--out F]      mede M2 (roteamento, cases.yaml)
#   bash tests/eval/laya-spike.sh --report            roda M1+M2+calibração+custo de
#                                                      máquina e imprime o relatório
#
# Dependências opcionais (skip HONESTO, exit 0, se ausentes — Prioridades §1):
#   LAYA_PYTHON   caminho do python da venv com `laya` instalado (default: python3.13
#                 do PATH). A venv fica FORA do repo (scratchpad ou ~/.cache) —
#                 nunca commitada.
#   checkpoint    ~/.cache/huggingface/hub/models--convaiinnovations--laya/.../
#                 model.safetensors precisa existir (baixado na INSTALAÇÃO, nunca
#                 em runtime — ver ordem 034 "Por que esta ordem existe").
#
# Env:
#   LAYA_TORCH_THREADS   threads do torch, fixadas e impressas (default 4).
#   LAYA_LOG              log de origem do M1 (default ~/.maestro/logs/routing.jsonl).
#
# Sem efeito: não grava decision record, não chama `maestro decide`, não escreve em
# ~/.maestro/. Nenhum prompt nem texto de entrada sai nos TSV — só rótulo, predição,
# confiança e n (M2 usa o `prompt` de cases.yaml só como ENTRADA do motor, nunca como
# coluna de saída). Nenhum limiar é escrito em lugar nenhum.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ENGINE="$HERE/laya_engine.py"
PRESCRIBE="$HERE/prescribe.ts"

die() { printf 'laya-spike: %s\n' "$1" >&2; exit 1; }
skip() { printf 'laya-spike: SKIP — %s\n' "$1"; exit 0; }

PY="${LAYA_PYTHON:-python3.13}"
THREADS="${LAYA_TORCH_THREADS:-4}"
LOG="${LAYA_LOG:-$HOME/.maestro/logs/routing.jsonl}"

command -v jq  >/dev/null 2>&1 || die "jq não encontrado"
command -v bun >/dev/null 2>&1 || die "bun não encontrado (cases.yaml é lido por prescribe.ts, mesmo padrão do run-eval.sh)"

# ---------------------------------------------------------------------------
# Checagem de dependência opcional. Cada checagem guarda o MOTIVO (nunca
# 2>/dev/null puro — papercut de 2026-09-19: silenciar engole a causa e o
# sintoma reaparece dois passos depois).
# ---------------------------------------------------------------------------
_dep_reason=""
have_python() {
  command -v "$PY" >/dev/null 2>&1 && return 0
  _dep_reason="python (\$LAYA_PYTHON=$PY) não encontrado no PATH"
  return 1
}

have_laya_package() {
  local err
  err=$("$PY" -c 'import laya' 2>&1)
  if [[ $? -eq 0 ]]; then return 0; fi
  _dep_reason="pacote laya ausente em $PY: $(printf '%s' "$err" | tail -1)"
  return 1
}

have_checkpoint() {
  local cache="${HF_HOME:-$HOME/.cache/huggingface}"
  if find "$cache/hub" -path '*convaiinnovations--laya*/model.safetensors' 2>/dev/null | grep -q .; then
    return 0
  fi
  _dep_reason="checkpoint não encontrado em $cache/hub (convaiinnovations/laya) — baixe na instalação, não em runtime"
  return 1
}

# rc=0 e imprime "ok"/"skip:motivo" — usado tanto por --report (decide se mede)
# quanto por --selftest (confere que a checagem em si não explode).
check_deps() {
  have_python       || { printf 'skip: %s\n' "$_dep_reason"; return 1; }
  have_laya_package || { printf 'skip: %s\n' "$_dep_reason"; return 1; }
  have_checkpoint   || { printf 'skip: %s\n' "$_dep_reason"; return 1; }
  printf 'ok\n'
  return 0
}

# Corpo em arquivos sourced (cada um sob o teto de 400 linhas do habit
# sensor local): m1/m2 medem e escrevem TSV; calib faz Brier/ECE/custo de
# máquina; selftest são as asserções com fixture sintética.
source "$HERE/laya-spike-m1.sh"
source "$HERE/laya-spike-m2.sh"
source "$HERE/laya-spike-calib.sh"
source "$HERE/laya-spike-selftest.sh"

# --report: M1 + M2 + calibração + custo de máquina. Reusa m1_measure() para
# não chamar o motor duas vezes com o mesmo corpus M1 (uma vez para o TSV,
# outra para a calibração).
report_run() {
  local dep; dep=$(check_deps)
  [[ "$dep" == "ok" ]] || skip "${dep#skip: }"

  printf '## laya-spike --report (ordem 034)\n\n'

  local pairs; pairs=$(m1_pairs_json "$LOG")
  local work; work=$(mktemp -d) || die "mktemp falhou"

  m1_measure "$pairs" "$work"
  _m1_write_tsv "$work/joined.json" "$HERE/laya-m1.tsv"
  printf 'M1: %s registros -> %s\n' "$(jq length "$work/joined.json")" "$HERE/laya-m1.tsv"
  calibracao_run "$work/joined.json" "$HERE/laya-calibracao.tsv"
  # `rm` explícito, não `trap ... RETURN`: o trap não é local à função — uma
  # função chamada DEPOIS (m2_run/machine_cost) que também usasse `trap
  # RETURN` sobrescreveria este e dispararia de novo no retorno delas, com
  # $work fora de escopo (medido: essa pilha estourava "work: unbound
  # variable" com rc=1 antes deste fix — ver mesma nota em laya-spike-m1.sh).
  rm -rf "$work"

  m2_run "$HERE/laya-m2.tsv"

  printf '\n### custo de máquina\n'
  machine_cost
}

# ---------------------------------------------------------------------------
main() {
  case "${1:---help}" in
    --selftest) selftest ;;
    --m1) shift; local out=""; [[ "${1:-}" == "--out" ]] && out="${2:-}"; m1_run "$out" ;;
    --m2) shift; local out=""; [[ "${1:-}" == "--out" ]] && out="${2:-}"; m2_run "$out" ;;
    --report) report_run ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" ;;
    *) die "opção desconhecida: $1 (use --help)" ;;
  esac
}
main "$@"
