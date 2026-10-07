#!/usr/bin/env bash
# tools/install-managed-mods.sh — instala os mods do Maestro como plugins "da organização" (ordem 072).
# Copia mods/ para /opt/maestro/claude-plugins com dono root:root, modo 755 (pastas) e 644 (arquivos).
# RECUSA se o destino, ou qualquer pai dele, for gravável por quem não é root: um diretório que o
# usuário da sessão consegue reescrever não é "da organização".
# Quem roda é o Capitão, com sudo. A fábrica (agentes, gerente headless) NÃO roda este script.
# Uso: sudo tools/install-managed-mods.sh [--dest DIR]
#      tools/install-managed-mods.sh --check [--dest DIR]   (só confere a recusa; não cria nem copia nada)
# Sem rede. Passo a passo e limites: docs/mods/INSTALACAO.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/mods"
DEST="/opt/maestro/claude-plugins"
CHECK=0

usage() { echo "uso: tools/install-managed-mods.sh [--check] [--dest DIR]" >&2; exit 2; }

while (( $# )); do
  case "$1" in
    --check) CHECK=1; shift ;;
    --dest) [[ $# -ge 2 && -n "$2" ]] || usage; DEST="$2"; shift 2 ;;
    *) usage ;;
  esac
done

die() { echo "install-managed-mods: RECUSADO: $*" >&2; exit 2; }

[[ "$DEST" == /* ]] || die "o destino precisa ser caminho absoluto: $DEST"
# o destino é substituído por inteiro: nunca a raiz nem um diretório de primeiro nível (/opt, /usr)
[[ "$(readlink -m -- "$DEST")" =~ ^/[^/]+/.+ ]] || die "destino largo demais (precisa de ao menos dois níveis): $DEST"
[[ -f "$SRC/.claude-plugin/marketplace.json" ]] || die "mods/.claude-plugin/marketplace.json não existe em $SRC"
[[ -f "$SRC/maestro-guard/.claude-plugin/plugin.json" ]] || die "mods/maestro-guard/.claude-plugin/plugin.json não existe em $SRC"

# Um diretório é "de root" quando o dono é uid 0 e nem o grupo nem os outros podem gravar nele.
# Link simbólico no caminho não vale: resolve-se antes (readlink -f) e confere-se o real.
dir_is_root_only() {
  local d="$1" owner mode
  owner="$(stat -c '%u' -- "$d")"
  mode="$(stat -c '%a' -- "$d")"
  [[ "$owner" == "0" ]] || { echo "$d tem dono uid $owner (não é root)" >&2; return 1; }
  (( (8#$mode & 8#022) == 0 )) || { echo "$d tem modo $mode (gravável por grupo ou outros)" >&2; return 1; }
}

# Do alvo até a raiz: todo componente que já existe tem de ser de root, não gravável por não-root.
check_chain() {
  local p cur
  p="$(readlink -m -- "$DEST")"
  cur="$p"
  while [[ -n "$cur" ]]; do
    if [[ -e "$cur" ]]; then
      [[ -d "$cur" ]] || die "$cur existe e não é diretório"
      dir_is_root_only "$cur" || die "destino ou pai gravável por não-root: $cur"
    fi
    [[ "$cur" == "/" ]] && break
    cur="$(dirname -- "$cur")"
  done
  # o primeiro pai que existe é onde o install vai criar o resto: já foi conferido no laço
  DEST="$p"
}

check_chain

if (( CHECK )); then
  echo "install-managed-mods: ok (--check): $DEST e os pais são de root e não graváveis por não-root; nada foi criado"
  exit 0
fi

(( EUID == 0 )) || die "rode com sudo (precisa ser root para entregar os arquivos a root:root)"

PARENT="$(dirname -- "$DEST")"
install -d -m 755 -o root -g root -- "$PARENT"
check_chain

STAGE="$(mktemp -d -- "$PARENT/.claude-plugins.new.XXXXXX")"
cleanup() { rm -rf -- "$STAGE"; }
trap cleanup EXIT

cp -a -- "$SRC/." "$STAGE/"
# node_modules e logs de teste não entram: o mod não tem dependência de runtime
find "$STAGE" -name node_modules -prune -exec rm -rf -- {} +
chown -R root:root -- "$STAGE"
find "$STAGE" -type d -exec chmod 755 -- {} +
find "$STAGE" -type f -exec chmod 644 -- {} +

if [[ -e "$DEST" ]]; then
  OLD="$PARENT/.claude-plugins.old.$$"
  mv -- "$DEST" "$OLD"
  mv -- "$STAGE" "$DEST"
  rm -rf -- "$OLD"
else
  mv -- "$STAGE" "$DEST"
fi
trap - EXIT

check_chain
dir_is_root_only "$DEST" || die "pós-instalação: $DEST não ficou de root"
echo "install-managed-mods: instalado em $DEST (root:root, 755/644)"
echo "próximo passo (humano): registrar o marketplace nos settings gerenciados — docs/mods/INSTALACAO.md"
