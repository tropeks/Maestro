#!/usr/bin/env bash
# tools/armar-mods.sh — o comando único que arma o mod (instalador + settings gerenciados A e B juntos).
# Tudo contra uma RAIZ FALSA (--root) e um claude falso: nunca toca /etc nem /opt, nunca roda sudo.
# A cópia real para root:root e o chown são do tools/install-managed-mods.sh (testado à parte, exige root).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/armar-mods.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# shellcheck disable=SC2016  # o '$1 $2' do claude falso é do script gerado, não deste
# claude falso: o arquivo contém as chaves (a conferência lê o executável); versão e validate controlados
mkfake() { # <arquivo> <versão> <chaves...>
  local f="$1" v="$2"; shift 2
  {
    printf '#!/usr/bin/env bash\n'
    printf '# chaves presentes neste executável: %s\n' "$*"
    printf 'case "$1 $2" in\n  "--version "*) echo "%s (Claude Code)" ;;\n  "plugin validate") exit 0 ;;\n  *) exit 0 ;;\nesac\n' "$v"
  } > "$f"
  chmod +x "$f"
}
ALL=(allowManagedModsOnly prependPlugins cc-plugin-sec-default extraKnownMarketplaces enabledPlugins pluginConfigs)
mkfake "$tmp/claude-ok" "2.1.293" "${ALL[@]}"
mkfake "$tmp/claude-velho" "2.1.280" "${ALL[@]}"
mkfake "$tmp/claude-semchave" "2.1.293" prependPlugins cc-plugin-sec-default extraKnownMarketplaces enabledPlugins pluginConfigs

run() { # <raiz> args... → saída e rc em $out / $rc (sem tty: setsid -w)
  local root="$1"; shift
  out=$(setsid -w "$TOOL" --root "$root" --claude "$tmp/claude-ok" "$@" 2>&1 </dev/null); rc=$?
}
has() { [[ "$out" == *"$1"* ]]; }
eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (obtido: $2; esperado: $3)"; fi; }

# 1. --so-diff sem arquivo: mostra o diff e NÃO cria nada
R1="$tmp/r1"; mkdir -p "$R1"
run "$R1" --so-diff
if [[ $rc == 0 ]] && has "allowManagedModsOnly" && has "maestro-guard@maestro-managed" && has "--so-diff: nada foi escrito"; then ok "--so-diff mostra o diff"; else bad "--so-diff (rc=$rc): $out"; fi
if [[ ! -e "$R1/etc" && ! -e "$R1/opt" ]]; then ok "--so-diff não escreveu nada"; else bad "--so-diff criou arquivos"; fi

# 2. sem --yes e sem tty: mostra o diff, não aplica
run "$R1"
if [[ $rc == 0 ]] && has "nada foi alterado" && [[ ! -e "$R1/etc" && ! -e "$R1/opt" ]]; then ok "sem --yes e sem tty não aplica"; else bad "sem confirmação aplicou (rc=$rc): $out"; fi

# 3. --yes numa raiz sem arquivo anterior: grava A e B juntos
run "$R1" --yes
S1="$R1/etc/claude-code/managed-settings.json"
if [[ $rc == 0 && -f "$S1" ]]; then ok "--yes grava os settings"; else bad "--yes não gravou (rc=$rc): $out"; fi
j() { jq -r "$1" "$S1" 2>/dev/null; }
eq "allowManagedModsOnly na chave ANINHADA" "$(j '.pluginConfigs["cc-plugin-sec-default@builtin"].options.allowManagedModsOnly')" "true"
eq "sem allowManagedModsOnly de topo" "$(j 'has("allowManagedModsOnly")')" "false"
eq "marketplace de root em /opt/maestro/claude-plugins (caminho real no JSON)" "$(j '.extraKnownMarketplaces["maestro-managed"].source.path')" "/opt/maestro/claude-plugins"
eq "marketplace é do tipo directory" "$(j '.extraKnownMarketplaces["maestro-managed"].source.source')" "directory"
eq "plugin habilitado" "$(j '.enabledPlugins["maestro-guard@maestro-managed"]')" "true"
eq "maestro-guard primeiro e sec-default na lista" "$(j '.prependPlugins | join(",")')" "maestro-guard@maestro-managed,sec-default@builtin"
eq "sem disableSideloadFlags (quebraria --agents e --mcp-config)" "$(j 'has("disableSideloadFlags")')" "false"
if [[ -f "$R1/opt/maestro/claude-plugins/.claude-plugin/marketplace.json" && -f "$R1/opt/maestro/claude-plugins/maestro-guard/.claude-plugin/plugin.json" ]]; then ok "mods copiados para o destino"; else bad "mods não copiados"; fi
eq "estado: sem arquivo anterior (backup=AUSENTE)" "$(sed -n 's/^backup=//p' "$R1/etc/claude-code/managed-settings.json.armar-estado")" "AUSENTE"
if has "Desfazer: sudo"; then ok "imprime o comando para desfazer"; else bad "sem o comando para desfazer"; fi

# 4. idempotente: de novo, nada a mudar, sem backup novo
run "$R1" --yes
nbak=$(find "$R1/etc/claude-code" -name 'managed-settings.json.bak-*' | wc -l)
if [[ $rc == 0 ]] && has "já está no estado alvo" && [[ "$nbak" == 0 ]]; then ok "idempotente: sem diff e sem backup"; else bad "não idempotente (rc=$rc, backups=$nbak): $out"; fi

# 5. desfazer sem arquivo anterior: remove settings e diretório criados
run "$R1" --desfazer --yes
if [[ $rc == 0 && ! -e "$S1" && ! -e "$R1/opt/maestro/claude-plugins" && ! -e "$R1/etc/claude-code/managed-settings.json.armar-estado" ]]; then ok "desfazer remove o que armar criou"; else bad "desfazer (rc=$rc): $out"; fi

# 6. com arquivo gerenciado anterior: mostra diff -/+, faz backup, preserva as outras chaves
R2="$tmp/r2"; mkdir -p "$R2/etc/claude-code"
S2="$R2/etc/claude-code/managed-settings.json"
cat > "$S2" <<'EOF'
{
  "permissions": { "deny": ["Bash(rm -rf /)"] },
  "prependPlugins": ["outro@x", "sec-default@builtin"],
  "pluginConfigs": { "cc-plugin-sec-default@builtin": { "options": { "allowModsToOverrideDenyRules": false } } }
}
EOF
cp -p "$S2" "$tmp/original.json"
run "$R2" --so-diff
if has "-  \"prependPlugins\"" || has "+    \"maestro-guard@maestro-managed\","; then ok "diff mostra o antes e o depois"; else bad "diff sem mudanças: $out"; fi
run "$R2" --yes
bak=$(find "$R2/etc/claude-code" -name 'managed-settings.json.bak-*' | head -1)
if [[ $rc == 0 && -n "$bak" ]] && cmp -s "$bak" "$tmp/original.json"; then ok "backup do arquivo anterior, idêntico ao original"; else bad "backup (rc=$rc, bak=$bak): $out"; fi
eq "outras chaves preservadas (permissions)" "$(jq -r '.permissions.deny[0]' "$S2")" "Bash(rm -rf /)"
eq "opções do guard preservadas e allowManagedModsOnly somada" "$(jq -r '.pluginConfigs["cc-plugin-sec-default@builtin"].options | [.allowManagedModsOnly, .allowModsToOverrideDenyRules] | @csv' "$S2")" "true,false"
eq "prependPlugins: guard primeiro, sec-default, depois os outros" "$(jq -r '.prependPlugins | join(",")' "$S2")" "maestro-guard@maestro-managed,sec-default@builtin,outro@x"

# 7. desfazer restaura o original byte a byte
run "$R2" --desfazer --yes
if [[ $rc == 0 ]] && cmp -s "$S2" "$tmp/original.json"; then ok "desfazer restaura o arquivo gerenciado anterior"; else bad "desfazer não restaurou (rc=$rc): $out"; fi

# 8. recusas: nada é escrito
R3="$tmp/r3"; mkdir -p "$R3"
out=$(setsid -w "$TOOL" --root "$R3" --claude "$tmp/claude-velho" --yes 2>&1 </dev/null); rc=$?
if [[ $rc == 1 && "$out" == *"mais antigo"* && ! -e "$R3/etc" ]]; then ok "versão antiga recusa"; else bad "versão antiga (rc=$rc): $out"; fi
out=$(setsid -w "$TOOL" --root "$R3" --claude "$tmp/claude-semchave" --yes 2>&1 </dev/null); rc=$?
if [[ $rc == 1 && "$out" == *"allowManagedModsOnly"* && "$out" == *"não existe"* && ! -e "$R3/etc" ]]; then ok "chave ausente no executável recusa"; else bad "chave ausente (rc=$rc): $out"; fi
R4="$tmp/r4"; mkdir -p "$R4/etc/claude-code"; echo '{ não é json' > "$R4/etc/claude-code/managed-settings.json"
cp -p "$R4/etc/claude-code/managed-settings.json" "$tmp/invalido.json"
run "$R4" --yes
if [[ $rc == 1 && "$out" == *"JSON válido"* ]] && cmp -s "$R4/etc/claude-code/managed-settings.json" "$tmp/invalido.json" && [[ ! -e "$R4/opt" ]]; then ok "arquivo atual inválido recusa sem mexer em nada"; else bad "inválido (rc=$rc): $out"; fi

# 9. sem root e sem --root, só o --so-diff é permitido
if [[ "$(id -u)" != "0" ]]; then
  out=$("$TOOL" --claude "$tmp/claude-ok" --yes 2>&1 </dev/null); rc=$?
  if [[ $rc == 1 && "$out" == *"rode com sudo"* ]]; then ok "sem root e sem --root recusa (pede sudo)"; else bad "sem root (rc=$rc): $out"; fi
fi

# 10. desfazer sem estado
run "$R3" --desfazer --yes
if [[ $rc == 1 && "$out" == *"nada a desfazer"* ]]; then ok "desfazer sem estado recusa"; else bad "desfazer sem estado (rc=$rc): $out"; fi

exit "$fail"
