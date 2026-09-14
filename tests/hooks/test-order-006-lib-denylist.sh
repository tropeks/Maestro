#!/usr/bin/env bash
# ordem 006 (E24 Lote 0, decisão A) — `lib/` nasce DENYLISTED na autoproteção
# do gate. Os módulos do split do E24 vão morar em `lib/`; sem isto, ~85% do
# CLI bash migraria para uma zona sem a guarda do ADR-003 v1.2 — vencida por
# MUDANÇA DE ENDEREÇO, não por remoção.
#
# Origem única (session-start.sh compila a política; pre-tool-gate.sh:150 só
# tem o override por env, usado quando a política nem chega a definir a
# variável) — por isso o patch mexe SÓ em hooks/session-start.sh
# (SELF_FALLBACK), nunca em pre-tool-gate.sh.
#
# Ausente → PENDENTE (hooks/ está na denylist do gate). Presente → cobra de
# verdade e prova o TERCEIRO ESTADO.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SS="$REPO/hooks/session-start.sh"
GATE="$REPO/hooks/pre-tool-gate.sh"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

PATCHED=0
grep -qE '^SELF_FALLBACK=.*[[:space:]]lib/[[:space:]]' "$SS" 2>/dev/null && PATCHED=1
if (( PATCHED == 0 )); then
  pending "ordem 006 (decisão A): hooks/session-start.sh ainda sem lib/ no SELF_FALLBACK — aplicar docs/patches/006-lote0-lib-denylist.patch"
  exit 0
fi

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
YAML="$T/routing-no-self.yaml"
cat > "$YAML" <<'EOF'
version: 2
gate:
  mode: block
  allowlist:
    extensions: [.md, .txt]
    paths: [.maestro/, docs/]
  denylist:
    paths: [.claude/, .github/workflows/]
workflows:
  fix: {steps: [investigate], gate: none}
EOF

compile_policy() { # <ss-script> <home>
  local ss="$1" home="$2"
  printf '{"session_id":"lib-deny-1"}' \
    | MAESTRO_HOME="$home" CLAUDE_PROJECT_DIR="$T/proj" MAESTRO_ROUTING_TABLE="$YAML" \
      MAESTRO_PLUGIN_ROOT="$REPO" bash "$ss" >/dev/null 2>&1
}

H1="$T/home1"; mkdir -p "$H1"
compile_policy "$SS" "$H1"
if [[ -f "$H1/gate-policy.sh" ]] && grep -q 'lib/' "$H1/gate-policy.sh"; then
  ok "self_paths ausente no YAML → fallback embutido inclui lib/ na política compilada"
else
  bad "gate-policy.sh compilado não protege lib/ (fallback não aplicado)"
fi

# ---------------------------------------------------------------------------
# fim a fim: o GATE de verdade nega edição em lib/ mesmo com decision record
# válido — igual a bin/ e hooks/.
# ---------------------------------------------------------------------------
write_record() {
  local sid="$1" home="$2" now exp
  mkdir -p "$home/sessions"
  now=$(date +%s); exp=$(( now + 14400 ))
  cat > "$home/sessions/$sid.json" <<EOF
{"session_id":"$sid","workflow":"fix","mode":"direct","ts":$now,"expires_at":$exp}
EOF
}
write_record "lib-deny-1" "$H1"
LIBFILE="$REPO/lib/cmd-fake.sh"
PAYLOAD=$(printf '{"session_id":"lib-deny-1","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$LIBFILE")
OUT_G=$(printf '%s' "$PAYLOAD" | MAESTRO_HOME="$H1" CLAUDE_PROJECT_DIR="$REPO" bash "$GATE" 2>&1 >/dev/null)
RC_G=$?
[[ $RC_G -eq 2 ]] && ok "edição em lib/ é BLOQUEADA mesmo com decision record válido (rc=2)" \
  || bad "lib/ deveria ser bloqueada como bin/ e hooks/ (rc=$RC_G, saída: '$OUT_G')"

# ---------------------------------------------------------------------------
# terceiro estado: sabota SELF_FALLBACK numa CÓPIA (tira lib/) e mostra que a
# MESMA edição deixa de ser bloqueada — o teste tem dente.
# ---------------------------------------------------------------------------
SAB="$T/session-start-sabotado.sh"
cp "$SS" "$SAB"
sed -i 's#^SELF_FALLBACK=.*#SELF_FALLBACK="agents/ bin/ src/ hooks/ config/routing-table.yaml .claude-plugin/"#' "$SAB"
if grep -qE '^SELF_FALLBACK=.*[[:space:]]lib/[[:space:]]' "$SAB"; then
  bad "sabotagem não pegou (padrão do sed não bateu)"
else
  H2="$T/home2"; mkdir -p "$H2"
  compile_policy "$SAB" "$H2"
  write_record "lib-deny-1" "$H2"
  OUT_SAB=$(printf '%s' "$PAYLOAD" | MAESTRO_HOME="$H2" CLAUDE_PROJECT_DIR="$REPO" bash "$GATE" 2>&1 >/dev/null)
  RC_SAB=$?
  [[ $RC_SAB -eq 2 ]] && bad "sabotagem não quebrou nada — lib/ ainda seria bloqueada sem o fallback" \
    || ok "sabotado: lib/ deixa de ser bloqueada sem o patch (rc=$RC_SAB) — o teste tem dente"
fi

exit $fail
