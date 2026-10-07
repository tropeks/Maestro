#!/usr/bin/env bash
# ordem 072, revisão de segurança P2-3 — o patch protegido 072 (remove o pre-bash-guard) só se aplica
# depois do mod ARMADO:
#   1) tools/verificar-mod-armado.sh confere settings gerenciados, plugin em prepend, diretório de root
#      e `claude plugin list`; só então --gravar escreve `estado: 903-CONFIRMADO`;
#   2) o patch exige essa linha como contexto: com `903-PENDENTE`, `git apply --check` RECUSA.
# Tudo em fixtures de pasta temporária; nunca toca /etc nem o repo real.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/verificar-mod-armado.sh"
PATCH="$REPO/docs/patches/072-guard-remocao-e-mods-self-paths.patch"
GATE_REL="docs/mods/GATE-PATCH-072.md"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
me="$(id -u)"

# claude falso: `plugin list` com o plugin habilitado (ou sem ele, conforme FAKE_LIST)
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude-ok" <<'EOF'
#!/usr/bin/env bash
printf 'Installed plugins:\n\n  ❯ maestro-guard@maestro-managed\n    Version: 0.1.0\n    Scope: user\n    Status: ✔ enabled\n'
EOF
cat > "$tmp/bin/claude-sem" <<'EOF'
#!/usr/bin/env bash
printf 'Installed plugins:\n\n  ❯ maestro@maestro\n    Version: 1.23.0\n    Status: ✔ enabled\n'
EOF
chmod +x "$tmp/bin/claude-ok" "$tmp/bin/claude-sem"

# marketplace fixture completo
mp="$tmp/opt/claude-plugins"
mkdir -p "$mp/.claude-plugin" "$mp/maestro-guard/.claude-plugin"
echo '{}' > "$mp/.claude-plugin/marketplace.json"
echo '{}' > "$mp/maestro-guard/.claude-plugin/plugin.json"

settings_ok() {
  cat > "$1" <<EOF
{
  "extraKnownMarketplaces": { "maestro-managed": { "source": { "source": "directory", "path": "$mp" } } },
  "enabledPlugins": { "maestro-guard@maestro-managed": true },
  "prependPlugins": ["maestro-guard@maestro-managed", "sec-default@builtin"],
  "pluginConfigs": { "cc-plugin-sec-default@builtin": { "options": { "allowManagedModsOnly": true } } }
}
EOF
  chmod 644 "$1"
}

gate="$tmp/GATE.md"
printf '# gate\n\nestado: 903-PENDENTE\n\nconfirmado-em: -\n' > "$gate"

run() { # <settings> <claude> [args...] → saída e rc
  local s="$1" c="$2"; shift 2
  MANAGED_SETTINGS="$s" CLAUDE_BIN="$c" GATE_FILE="$gate" MAESTRO_VERIFICAR_UID="$me" "$TOOL" "$@" 2>&1
}
expect() { # <nome> <rc> <trecho> <saída> <rc-real>
  if [[ "$5" == "$2" && "$4" == *"$3"* ]]; then ok "$1"; else bad "$1 (rc=$5, esperado $2; saída: $4)"; fi
}

# --- o verificador ---
settings_ok "$tmp/s-ok.json"
out=$(run "$tmp/s-ok.json" "$tmp/bin/claude-ok"); rc=$?
expect "tudo armado: sai 0 e diz ARMADO" 0 "ARMADO" "$out" "$rc"

out=$(run "$tmp/nao-existe.json" "$tmp/bin/claude-ok"); rc=$?
expect "settings ausentes: sai 1 e diz NÃO ARMADO" 1 "NÃO ARMADO" "$out" "$rc"

# allowManagedModsOnly de topo (a forma errada da pesquisa de 07/10) não vale
jq 'del(.pluginConfigs) | . + {allowManagedModsOnly: true}' "$tmp/s-ok.json" > "$tmp/s-topo.json"
out=$(run "$tmp/s-topo.json" "$tmp/bin/claude-ok"); rc=$?
expect "allowManagedModsOnly de topo não vale (chave aninhada)" 1 "chave aninhada" "$out" "$rc"

jq '.prependPlugins = ["sec-default@builtin", "maestro-guard@maestro-managed"]' "$tmp/s-ok.json" > "$tmp/s-ordem.json"
out=$(run "$tmp/s-ordem.json" "$tmp/bin/claude-ok"); rc=$?
expect "plugin fora do primeiro lugar de prependPlugins recusa" 1 "primeiro de prependPlugins" "$out" "$rc"

jq '.prependPlugins = ["maestro-guard@maestro-managed"]' "$tmp/s-ok.json" > "$tmp/s-semguard.json"
out=$(run "$tmp/s-semguard.json" "$tmp/bin/claude-ok"); rc=$?
expect "sec-default fora da lista recusa" 1 "sec-default@builtin" "$out" "$rc"

jq '.enabledPlugins = {}' "$tmp/s-ok.json" > "$tmp/s-desab.json"
out=$(run "$tmp/s-desab.json" "$tmp/bin/claude-ok"); rc=$?
expect "plugin não habilitado recusa" 1 "enabledPlugins" "$out" "$rc"

out=$(run "$tmp/s-ok.json" "$tmp/bin/claude-sem"); rc=$?
expect "claude plugin list sem o plugin recusa" 1 "claude plugin list" "$out" "$rc"

rm -rf "$mp/maestro-guard"
out=$(run "$tmp/s-ok.json" "$tmp/bin/claude-ok"); rc=$?
expect "marketplace instalado incompleto recusa" 1 "incompleto" "$out" "$rc"
mkdir -p "$mp/maestro-guard/.claude-plugin"; echo '{}' > "$mp/maestro-guard/.claude-plugin/plugin.json"

chmod 666 "$tmp/s-ok.json"
out=$(run "$tmp/s-ok.json" "$tmp/bin/claude-ok"); rc=$?
expect "settings graváveis por todos recusam" 1 "graváveis" "$out" "$rc"
chmod 644 "$tmp/s-ok.json"

# dono errado (o padrão é root: o usuário de teste não é root)
out=$(MANAGED_SETTINGS="$tmp/s-ok.json" CLAUDE_BIN="$tmp/bin/claude-ok" GATE_FILE="$gate" "$TOOL" 2>&1); rc=$?
if [[ "$me" != "0" ]]; then expect "dono que não é root recusa (padrão uid 0)" 1 "não são do uid 0" "$out" "$rc"
else ok "dono não-root (pulado: o teste roda como root)"; fi

# --- o --gravar ---
out=$(run "$tmp/s-ok.json" "$tmp/bin/claude-ok" --gravar); rc=$?
expect "--gravar sem --vi-tier-prepend recusa (uso)" 2 "vi-tier-prepend" "$out" "$rc"
if grep -q '^estado: 903-PENDENTE$' "$gate"; then ok "recusa não gravou o gate"; else bad "gate mudou na recusa"; fi

out=$(run "$tmp/s-semguard.json" "$tmp/bin/claude-ok" --gravar --vi-tier-prepend); rc=$?
expect "--gravar com mod desarmado recusa" 1 "NÃO ARMADO" "$out" "$rc"
if grep -q '^estado: 903-PENDENTE$' "$gate"; then ok "desarmado não gravou o gate"; else bad "gate mudou com mod desarmado"; fi

out=$(run "$tmp/s-ok.json" "$tmp/bin/claude-ok" --gravar --vi-tier-prepend); rc=$?
expect "--gravar com tudo armado grava" 0 "903-CONFIRMADO" "$out" "$rc"
if grep -q '^estado: 903-CONFIRMADO$' "$gate" && grep -qE '^confirmado-em: 20[0-9]{2}-' "$gate"; then ok "gate gravado com estado e data"; else bad "gate sem estado/data: $(cat "$gate")"; fi

# --- o patch exige o gate ---
[[ -f "$PATCH" ]] || { bad "patch 072 ausente: $PATCH"; exit 1; }
work="$tmp/clone"; mkdir -p "$work"
( cd "$REPO" && { grep '^diff --git' "$PATCH" | sed -E 's#^diff --git a/([^ ]+) b/.*#\1#'; echo "$GATE_REL"; } | sort -u | while read -r f; do
    mkdir -p "$work/$(dirname "$f")"; cp -p "$f" "$work/$f"; done )
git -C "$work" init -q 2>/dev/null

estado() { sed -i "s/^estado: .*/estado: $1/" "$work/$GATE_REL"; }

estado "903-PENDENTE"
if git -C "$work" apply --check "$PATCH" 2>/dev/null; then bad "patch 072 aplicou com o gate 903-PENDENTE"; else ok "patch 072 RECUSADO com o gate 903-PENDENTE"; fi
estado "903-CONFIRMADO"
if git -C "$work" apply --check "$PATCH" 2>/dev/null; then ok "patch 072 aplica com o gate 903-CONFIRMADO"; else bad "patch 072 não aplica nem com 903-CONFIRMADO"; fi
estado "PATCH-072-APLICADO"
if git -C "$work" apply --check "$PATCH" 2>/dev/null; then bad "patch 072 reaplicou sobre PATCH-072-APLICADO"; else ok "patch 072 não reaplica (gate já PATCH-072-APLICADO)"; fi

# o gate do repo real continua PENDENTE até o Capitão confirmar
if grep -q '^estado: 903-PENDENTE$' "$REPO/$GATE_REL" || grep -q '^estado: 903-CONFIRMADO$' "$REPO/$GATE_REL"; then ok "gate do repo em estado válido"; else bad "gate do repo com estado inesperado"; fi

exit "$fail"
