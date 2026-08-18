#!/usr/bin/env bash
# E7 / S-702 — eval-on-diff da routing table (Tier 1, determinístico, hermético).
#
# O instrumento (A) do eval (tests/eval/prescribe.ts) é determinístico: dado o
# TEXTO da tabela, o veredito prescrito por caso é função pura. Este teste pina
# esses vereditos em tests/eval/prescribed-baseline.tsv e falha NOMEANDO os
# casos cujo veredito mudou — uma edição na tabela vira diff comportamental
# revisável, não fé. O SCORE fica fora do CI de propósito (cabeçalho do
# run-eval.sh: "score abaixo de 100% é informação, não regressão"); só o DIFF
# contra o baseline gateia. Baseline sempre pinado por arquivo versionado —
# nunca "o run mais recente" (lição gstack v1.63: o eval deles se comparou com
# o próprio acumulador parcial e imprimiu "no regressions" por releases).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BASELINE="$REPO/tests/eval/prescribed-baseline.tsv"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v bun >/dev/null || { echo "FAIL bun ausente (necessário no E2)"; exit 1; }
[[ -f "$BASELINE" ]] || { bad "baseline existe ($BASELINE)"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

extract() { # tsv do prescribe → caso\twf\tmode\tagents (só linhas de caso)
  awk -F'\t' 'NR>1 && NF>=12 {print $1"\t"$4"\t"$7"\t"$10}'
}

bun "$REPO/tests/eval/prescribe.ts" --tsv 2>/dev/null | extract > "$tmp/current.tsv"
grep -v '^#' "$BASELINE" > "$tmp/baseline.tsv"

[[ -s "$tmp/current.tsv" ]] || { bad "prescribe.ts produziu vereditos"; exit 1; }
ok "prescribe.ts produziu $(wc -l < "$tmp/current.tsv") veredito(s)"

# Determinismo: duas execuções idênticas (pré-condição de tudo acima).
bun "$REPO/tests/eval/prescribe.ts" --tsv 2>/dev/null | extract > "$tmp/again.tsv"
if diff -q "$tmp/current.tsv" "$tmp/again.tsv" >/dev/null; then
  ok "instrumento (A) é determinístico (2 execuções idênticas)"
else
  bad "instrumento (A) é determinístico"
fi

if diff -q "$tmp/baseline.tsv" "$tmp/current.tsv" >/dev/null; then
  ok "vereditos por caso conferem com o baseline pinado"
else
  bad "vereditos por caso conferem com o baseline pinado"
  echo "     Casos com veredito alterado (baseline → atual):"
  tab=$(printf '\t')
  # join por id (ids são [a-z0-9-], grep literal basta); add/remove também aparece
  while IFS=$'\t' read -r id rest; do
    cur=$(grep "^${id}${tab}" "$tmp/current.tsv" || true)
    base="${id}${tab}${rest}"
    if [[ -z "$cur" ]]; then
      echo "       - $id: presente no baseline, ausente no atual"
    elif [[ "$cur" != "$base" ]]; then
      echo "       - $id: '$rest' → '${cur#*${tab}}'"
    fi
  done < "$tmp/baseline.tsv"
  while IFS=$'\t' read -r id rest; do
    grep -q "^${id}${tab}" "$tmp/baseline.tsv" || \
      echo "       - $id: novo caso sem baseline"
  done < "$tmp/current.tsv"
  echo "     Mudança intencional? Regenere o baseline no MESMO PR (comando no cabeçalho do .tsv)."
fi

exit $fail
