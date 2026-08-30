#!/usr/bin/env bash
# E16 — docs canônicos como contrato. Invariantes: drift por FRONTEIRA com
# quitação (emenda OU reviewed re-atesta; "mesmo commit" estrito foi rejeitado
# pela pesquisa); commits, não dias; catraca versionada; regra de citação na
# injeção + nag TARDIO único; tudo warn-first. Hermético.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
SS="$REPO/hooks/session-start.sh"
HAB="$REPO/hooks/post-edit-habits.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

P="$tmp/p"; mkdir -p "$P/src" "$P/docs"; git -C "$P" init -q
cat > "$P/docs/SPEC.md" <<'DOC'
---
covers:
  - src/**
---
# Spec
DOC
echo a > "$P/src/app.py"
printf 'version: 1\ndocs: [docs/SPEC.md]\n' > "$P/.maestro.yaml"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm base
ci() { git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm "$1"; }

echo "-- drift por fronteira"
chk "recém-commitado → FRESCO" "$("$BIN" docs --project "$P" | grep -c FRESCO)" "1"
echo b >> "$P/src/app.py"; ci m1
echo c >> "$P/src/app.py"; ci m2
"$BIN" docs --project "$P" | grep -q 'STALE — 2 commit(s)' && ok "2 commits na área → STALE contando" || bad "STALE contando"
echo '## Emenda' >> "$P/docs/SPEC.md"; ci emenda
chk "emenda commitada QUITA (fronteira, não mesmo-commit)" "$("$BIN" docs --project "$P" | grep -c FRESCO)" "1"

echo "-- quitação por reviewed (provenance stamp, sem edição cosmética)"
echo d >> "$P/src/app.py"; ci m3
SHA=$(git -C "$P" rev-parse HEAD)
python3 - "$P/docs/SPEC.md" "$SHA" <<'PY'
import sys
p, sha = sys.argv[1], sys.argv[2]
s = open(p).read().replace('covers:', f'reviewed: {sha}\ncovers:', 1)
open(p, 'w').write(s)
PY
ci reviewed
"$BIN" docs --project "$P" | grep -q FRESCO && ok "reviewed re-atesta sem tocar o corpo" || bad "reviewed re-atesta"

echo "-- catraca (cenário limpo)"
"$BIN" docs --baseline --project "$P" >/dev/null; ci baseline
chk "baseline versionado no projeto" "$(grep -c 'SPEC.md' "$P/.maestro-docs.tsv")" "1"
"$BIN" docs --check --project "$P" >/dev/null; chk "dentro da catraca → exit 0" "$?" "0"
echo e >> "$P/src/app.py"; ci m4
out=$("$BIN" docs --check --project "$P"); rc=$?
chk "drift NOVO acima do baseline → exit 1" "$rc" "1"
grep -q 'CATRACA DE DOCS' <<<"$out" && ok "reprova nomeando doc e contagens" || bad "reprova nomeando"
echo '## E2' >> "$P/docs/SPEC.md"; ci emenda2
"$BIN" docs --check --project "$P" >/dev/null; chk "emenda quita a catraca" "$?" "0"

echo "-- degradações e avisos"
python3 - "$P/.maestro.yaml" <<'PY'
import sys
p = sys.argv[1]
open(p,'a').write('') 
PY
printf 'version: 1\ndocs: [docs/NAOEXISTE.md]\n' > "$P/.maestro.yaml"
out=$("$BIN" docs --check --project "$P"); rc=$?
grep -q 'AUSENTE' <<<"$out" && ok "doc declarado inexistente é acusado" || bad "doc ausente acusado"
chk "e reprova no --check" "$rc" "1"
printf 'version: 1\n' > "$P/.maestro.yaml"
out=$("$BIN" docs --project "$P"); rc=$?
chk "sem docs: declarado → informativo, exit 0" "$rc" "0"
cat > "$P/docs/SEMCOVERS.md" <<'DOC'
# Doc sem frontmatter
DOC
printf 'version: 1\ndocs: [docs/SEMCOVERS.md]\n' > "$P/.maestro.yaml"; ci semcovers
"$BIN" docs --project "$P" | grep -q 'sem covers' && ok "doc sem covers é prosa, dito com todas as letras" || bad "sem covers"
cat > "$P/docs/LARGO.md" <<'DOC'
---
covers:
  - "**"
---
# Tudo
DOC
# fan-out só liga com >20 arquivos (guarda anti-ruído em repo minúsculo)
for i in $(seq 1 25); do echo x > "$P/src/f$i.py"; done
printf 'version: 1\ndocs: [docs/LARGO.md]\n' > "$P/.maestro.yaml"; ci largo
"$BIN" docs --project "$P" | grep -q 'largo demais' && ok "glob que engole o repo é acusado (fan-out)" || bad "fan-out"

echo "-- injeção (S-1603a) e nag tardio (S-1603b)"
printf 'version: 1\ndocs: [docs/SPEC.md]\n' > "$P/.maestro.yaml"; ci volta
OUT=$(printf '{"session_id":"dc1"}' | CLAUDE_PROJECT_DIR="$P" bash "$SS" 2>/dev/null)
grep -q 'docs canônicos: 1' <<<"$OUT" && ok "injeção conta os canônicos" || bad "injeção conta"
grep -q 'cita doc+seção' <<<"$OUT" && ok "regra positiva de citação na injeção" || bad "regra de citação"
nag() { printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" | CLAUDE_PROJECT_DIR="$P" bash "$HAB" 2>&1 >/dev/null; echo "$?"; }
out2=$(printf '{"session_id":"dcn","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$P/src/app.py" | CLAUDE_PROJECT_DIR="$P" bash "$HAB" 2>&1 >/dev/null); rc=$?
chk "1º edit em área governada → nag (exit 2)" "$rc" "2"
grep -q 'governado por docs/SPEC.md' <<<"$out2" && ok "nag nomeia o doc dono" || bad "nag nomeia o doc"
chk "2º edit → silêncio (nag é único)" "$(nag dcn "$P/src/app.py")" "0"

echo "-- ordem carrega o doc (S-1604)"
"$BIN" order --create --title "Nova rota" --doc docs/SPEC.md --project "$P" <<< "## Objetivo x" >/dev/null
OF=$(ls "$P/.maestro/orders/"*nova-rota*.md)
grep -q '^doc: docs/SPEC.md$' "$OF" && ok "ordem referencia o doc que autoriza" || bad "ordem referencia doc"
grep -q 'EMENDE o doc no mesmo changeset' "$OF" && ok "contrato da ordem cobra a emenda" || bad "contrato cobra emenda"
"$BIN" order --status 1 --project "$P" | grep -q 'doc     : docs/SPEC.md' && ok "status mostra o doc e o frescor" || bad "status mostra doc"

exit $fail
