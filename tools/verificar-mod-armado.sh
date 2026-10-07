#!/usr/bin/env bash
# tools/verificar-mod-armado.sh — confere se o mod maestro-guard está ARMADO nesta máquina (ordem 072, P2-3).
# "Armado" = settings gerenciados com allowManagedModsOnly, o plugin habilitado e em prepend, o diretório de
# root no lugar e o `claude plugin list` mostrando o plugin habilitado. Sem tudo isso, aplicar o patch 072
# (que remove o pre-bash-guard) deixa a máquina sem guarda.
# Uso: tools/verificar-mod-armado.sh                           só confere e imprime
#      tools/verificar-mod-armado.sh --gravar --vi-tier-prepend  confere e, se tudo passar, grava
#                                                              `estado: 903-CONFIRMADO` em docs/mods/GATE-PATCH-072.md
# Somente leitura, exceto o --gravar. Sem rede. Sai 0 = armado; 1 = falta algo (lista o que); 2 = uso.
# Variáveis só para teste: MANAGED_SETTINGS, CLAUDE_BIN, GATE_FILE e MAESTRO_VERIFICAR_UID (uid dono esperado,
# padrão 0 = root; diferente de 0 também pula a conferência da cadeia de root do marketplace).
# shellcheck disable=SC2016  # $p e $g são variáveis do jq (--arg), não do shell
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="${MANAGED_SETTINGS:-/etc/claude-code/managed-settings.json}"
CLAUDE="${CLAUDE_BIN:-claude}"
GATE="${GATE_FILE:-$HERE/docs/mods/GATE-PATCH-072.md}"
PLUGIN="maestro-guard@maestro-managed"
GUARD="sec-default@builtin"
UID_DONO="${MAESTRO_VERIFICAR_UID:-0}"
GRAVAR=0
VI=0

usage() { echo "uso: tools/verificar-mod-armado.sh [--gravar --vi-tier-prepend]" >&2; exit 2; }
while (( $# )); do
  case "$1" in
    --gravar) GRAVAR=1; shift ;;
    --vi-tier-prepend) VI=1; shift ;;
    *) usage ;;
  esac
done
if (( GRAVAR )); then
  (( VI )) || { echo "verificar-mod-armado: --gravar exige --vi-tier-prepend (a atestação de que você viu 'tier prepend' no claude --debug)" >&2; exit 2; }
fi

falhas=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FALTA %s\n' "$1"; falhas=$((falhas + 1)); }
chk() { local oktxt="$1" notxt="$2"; shift 2; if "$@" >/dev/null 2>&1; then ok "$oktxt"; else nok "$notxt"; fi; }
command -v jq >/dev/null 2>&1 || { echo "verificar-mod-armado: jq não encontrado" >&2; exit 2; }

# 1. o arquivo de settings gerenciados: existe, é de root, ninguém além de root grava
if [[ ! -f "$SETTINGS" ]]; then
  nok "settings gerenciados ausentes: $SETTINGS"
else
  if [[ "$(stat -c '%u' -- "$SETTINGS")" == "$UID_DONO" ]] && (( (8#$(stat -c '%a' -- "$SETTINGS") & 8#022) == 0 )); then ok "settings gerenciados do uid $UID_DONO e não graváveis por outros"
  else nok "settings gerenciados não são do uid $UID_DONO (root) ou são graváveis por grupo/outros: $SETTINGS"; fi

  if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
    nok "settings gerenciados não são JSON válido"
  else
    # 2. allowManagedModsOnly na chave ANINHADA que o guard lê (não de topo)
    chk "allowManagedModsOnly = true em pluginConfigs[cc-plugin-sec-default@builtin].options" \
        "allowManagedModsOnly ausente ou diferente de true na chave aninhada pluginConfigs[cc-plugin-sec-default@builtin].options" \
        jq -e '.pluginConfigs["cc-plugin-sec-default@builtin"].options.allowManagedModsOnly == true' "$SETTINGS"
    # 3. o plugin habilitado, em prepend na frente, com o guard embutido na lista
    chk "$PLUGIN habilitado" "$PLUGIN não está em enabledPlugins = true (etapa B do 903)" \
        jq -e --arg p "$PLUGIN" '.enabledPlugins[$p] == true' "$SETTINGS"
    chk "$PLUGIN é o primeiro de prependPlugins" "$PLUGIN não é o primeiro de prependPlugins" \
        jq -e --arg p "$PLUGIN" '(.prependPlugins // [])[0] == $p' "$SETTINGS"
    chk "$GUARD está na lista de prependPlugins" "$GUARD fora de prependPlugins (sem ele o guard embutido não carrega)" \
        jq -e --arg g "$GUARD" '(.prependPlugins // []) | index($g) != null' "$SETTINGS"
    # 4. o marketplace aponta para um diretório de root com o plugin dentro
    mp="$(jq -r '.extraKnownMarketplaces["maestro-managed"].source.path // ""' "$SETTINGS")"
    if [[ -z "$mp" || "$mp" != /* ]]; then nok "extraKnownMarketplaces[maestro-managed].source.path ausente ou relativo"
    elif [[ ! -f "$mp/.claude-plugin/marketplace.json" || ! -f "$mp/maestro-guard/.claude-plugin/plugin.json" ]]; then nok "marketplace instalado incompleto em $mp (rode sudo tools/install-managed-mods.sh)"
    elif [[ "$UID_DONO" == "0" ]] && ! "$HERE/tools/install-managed-mods.sh" --check --dest "$mp" >/dev/null 2>&1; then nok "$mp ou um pai é gravável por não-root"
    else ok "marketplace instalado em $mp"; fi
  fi
fi

# 5. o Claude Code enxerga o plugin habilitado
if lista="$("$CLAUDE" plugin list 2>&1)"; then
  if grep -A5 -F "$PLUGIN" <<<"$lista" | grep -qi 'enabled'; then ok "claude plugin list: $PLUGIN habilitado"
  else nok "claude plugin list não mostra $PLUGIN habilitado"; fi
else
  nok "claude plugin list falhou"
fi

if (( falhas )); then
  printf 'NÃO ARMADO: %d item(ns) faltando. O patch 072 NÃO deve ser aplicado.\n' "$falhas"
  exit 1
fi
printf 'ARMADO: todas as conferências passaram.\n'

if (( GRAVAR )); then
  [[ -f "$GATE" ]] || { echo "verificar-mod-armado: $GATE não existe" >&2; exit 2; }
  grep -q '^estado: ' "$GATE" || { echo "verificar-mod-armado: $GATE sem linha 'estado: '" >&2; exit 2; }
  tmp="$GATE.tmp.$$"
  if sed -e 's/^estado: .*/estado: 903-CONFIRMADO/' -e "s/^confirmado-em: .*/confirmado-em: $(date -Iseconds)/" "$GATE" > "$tmp"; then
    mv -f "$tmp" "$GATE"
  else
    rm -f "$tmp"; echo "verificar-mod-armado: falha ao gravar $GATE" >&2; exit 2
  fi
  echo "gravado: estado: 903-CONFIRMADO em $GATE (commite este arquivo; só então o patch 072 se aplica)"
fi
exit 0
