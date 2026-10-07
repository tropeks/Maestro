#!/usr/bin/env bash
# tools/armar-mods.sh — ARMA o mod maestro-guard numa só passada (decisão do Spock, 07/10):
#   passo 2: instala mods/ em /opt/maestro/claude-plugins (root:root) pelo tools/install-managed-mods.sh;
#   passo 3: grava os settings gerenciados das etapas A e B juntas em /etc/claude-code/managed-settings.json.
# Mostra o diff PRIMEIRO, pede confirmação, só então aplica, e guarda backup do arquivo gerenciado anterior.
# As chaves são conferidas contra o executável do Claude Code INSTALADO antes de qualquer escrita.
#
# Uso:  tools/armar-mods.sh --so-diff        só mostra o que mudaria (não precisa de root, não escreve nada)
#       sudo tools/armar-mods.sh             mostra o diff, pergunta, aplica
#       sudo tools/armar-mods.sh --yes       sem a pergunta
#       sudo tools/armar-mods.sh --desfazer  restaura o arquivo gerenciado anterior (e remove o diretório, se foi criado aqui)
# Teste: --root DIR usa DIR como "/" (sem root, sem chown, sem o instalador); --claude BIN aponta o executável.
# Sem rede. Passo a passo e limites: docs/mods/INSTALACAO.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/mods"
ROOT=""
CLAUDE="${CLAUDE_BIN:-}"
YES=0
MODE=armar
MIN_VERSION="2.1.287"
PLUGIN="maestro-guard@maestro-managed"
MKT="maestro-managed"
GUARD="sec-default@builtin"
MP_PATH="/opt/maestro/claude-plugins"   # o que vai DENTRO do JSON; com --root o diretório real fica sob DIR
# as chaves que o JSON usa; cada uma tem de existir no executável instalado
KEYS=(allowManagedModsOnly prependPlugins cc-plugin-sec-default extraKnownMarketplaces enabledPlugins pluginConfigs)

usage() { echo "uso: tools/armar-mods.sh [--so-diff | --desfazer] [--yes] [--root DIR] [--claude BIN]" >&2; exit 2; }
die() { echo "armar-mods: RECUSADO: $*" >&2; exit 1; }

while (( $# )); do
  case "$1" in
    --so-diff) MODE="diff"; shift ;;
    --desfazer) MODE="desfazer"; shift ;;
    --yes) YES=1; shift ;;
    --root) [[ $# -ge 2 && "$2" == /* ]] || usage; ROOT="${2%/}"; shift 2 ;;
    --claude) [[ $# -ge 2 && -n "$2" ]] || usage; CLAUDE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

SET_DIR="$ROOT/etc/claude-code"
SET="$SET_DIR/managed-settings.json"
DEST="$ROOT$MP_PATH"
STATE="$SET_DIR/managed-settings.json.armar-estado"

command -v jq >/dev/null 2>&1 || die "jq não encontrado"
if [[ "$MODE" != diff && -z "$ROOT" ]] && (( EUID != 0 )); then die "rode com sudo (grava em /etc e /opt como root); para só ver o diff: --so-diff"; fi

# roda um comando como o usuário que chamou o sudo (o claude lê ~/.claude desse usuário, não o de root)
as_user() {
  if (( EUID == 0 )) && [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then sudo -u "$SUDO_USER" -H -- "$@"; else "$@"; fi
}

find_claude() {
  [[ -n "$CLAUDE" ]] && return 0
  CLAUDE="$(command -v claude 2>/dev/null || true)"
  if [[ -z "$CLAUDE" && -n "${SUDO_USER:-}" ]]; then
    local h; h="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    [[ -x "$h/.local/bin/claude" ]] && CLAUDE="$h/.local/bin/claude"
  fi
  [[ -n "$CLAUDE" ]] || die "claude não encontrado (passe --claude CAMINHO ou CLAUDE_BIN=CAMINHO)"
}

# 1. a versão instalada tem mods e as chaves que vamos escrever
check_claude() {
  find_claude
  local bin ver found k
  bin="$(readlink -f -- "$CLAUDE")"
  [[ -f "$bin" ]] || die "executável do claude não é arquivo: $bin"
  ver="$(as_user "$CLAUDE" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [[ -n "$ver" ]] || die "não consegui ler a versão de $CLAUDE --version"
  [[ "$(printf '%s\n%s\n' "$MIN_VERSION" "$ver" | sort -V | head -1)" == "$MIN_VERSION" ]] \
    || die "Claude Code $ver é mais antigo que $MIN_VERSION (os mods exigem >= $MIN_VERSION)"
  found="$(grep -a -o -E "$(IFS='|'; echo "${KEYS[*]}")" -- "$bin" | sort -u || true)"
  for k in "${KEYS[@]}"; do
    grep -qxF -- "$k" <<<"$found" || die "a chave '$k' não existe no Claude Code instalado ($ver): a API de mods mudou; não escrevi nada. Reabra o desenho com o vigia (ordem 075)"
  done
  echo "claude: $ver em $bin; chaves conferidas no executável: ${KEYS[*]}"
  as_user "$CLAUDE" plugin validate "$SRC/maestro-guard" >/dev/null 2>&1 \
    || die "claude plugin validate $SRC/maestro-guard falhou: o mod não passa na versão instalada"
  echo "claude plugin validate mods/maestro-guard: ok"
}

# 2. os settings alvo: o arquivo atual (se houver) + as chaves das etapas A e B; o resto fica como está
build_new() { # <arquivo-atual-ou-vazio> → JSON ordenado em stdout
  local cur="$1" base='{}'
  if [[ -n "$cur" && -f "$cur" ]]; then
    jq -e 'type == "object"' "$cur" >/dev/null 2>&1 || die "$cur não é um objeto JSON válido; não mexi em nada"
    base="$(cat -- "$cur")"
  fi
  jq -S --arg plugin "$PLUGIN" --arg mkt "$MKT" --arg guard "$GUARD" --arg path "$MP_PATH" '
    .pluginConfigs["cc-plugin-sec-default@builtin"].options.allowManagedModsOnly = true
    | .extraKnownMarketplaces[$mkt] = {source: {source: "directory", path: $path}}
    | .enabledPlugins[$plugin] = true
    | .prependPlugins = ([$plugin, $guard] + ((.prependPlugins // []) | map(select(. != $plugin and . != $guard))))
  ' <<<"$base"
}

tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT

confirm() { # <pergunta>
  (( YES )) && return 0
  local ans=n
  { read -r -p "$1 [s/N] " ans </dev/tty; } 2>/dev/null || ans=n
  [[ "$ans" == [sSyY]* ]]
}

# ------------------------------------------------------------------ desfazer
if [[ "$MODE" == desfazer ]]; then
  [[ -f "$STATE" ]] || die "não há estado de arme em $STATE: nada a desfazer por aqui"
  backup="$(sed -n 's/^backup=//p' "$STATE")"; dest_existia="$(sed -n 's/^dest_existia=//p' "$STATE")"
  echo "desfazer:"
  if [[ "$backup" == "AUSENTE" ]]; then echo "  - remove $SET (não existia antes de armar)"
  else echo "  - restaura $SET a partir de $SET_DIR/$backup"; [[ -f "$SET_DIR/$backup" ]] || die "backup $SET_DIR/$backup sumiu"; fi
  if [[ "$dest_existia" == "0" ]]; then echo "  - remove $DEST (foi criado ao armar)"; else echo "  - $DEST já existia antes e é mantido (o instalador não guarda a cópia anterior)"; fi
  confirm "Desfazer?" || { echo "nada foi alterado"; exit 0; }
  if [[ "$backup" == "AUSENTE" ]]; then rm -f -- "$SET"
  else cp -p -- "$SET_DIR/$backup" "$SET.restaurando" && mv -f -- "$SET.restaurando" "$SET"; fi
  [[ "$dest_existia" == "0" ]] && rm -rf -- "$DEST"
  rm -f -- "$STATE"
  echo "desfeito. Reinicie as panes. O backup (se havia) segue em $SET_DIR."
  exit 0
fi

# ------------------------------------------------------------------ armar / so-diff
check_claude
build_new "$SET" > "$tmp/novo.json"

if [[ -f "$SET" ]]; then
  diff -u --label "atual: $SET" --label "novo: $SET" "$SET" "$tmp/novo.json" > "$tmp/diff.txt" || true
  MUDA=0; [[ -s "$tmp/diff.txt" ]] && MUDA=1
else
  diff -u --label "(não existe): $SET" --label "novo: $SET" /dev/null "$tmp/novo.json" > "$tmp/diff.txt" || true
  MUDA=1
fi

echo
echo "== settings gerenciados =="
if (( MUDA )); then cat "$tmp/diff.txt"; else echo "(já está no estado alvo: nada a mudar em $SET)"; fi
echo
echo "== diretório dos mods =="
echo "  $SRC  ->  $DEST   (root:root, 755/644; o que existir lá é substituído por inteiro)"
[[ -e "$DEST" ]] && echo "  AVISO: $DEST já existe e será substituído"
echo
cat <<AVISO
Efeito de armar: nenhum mod de usuário carrega mais (plugin instalado, --plugin-dir, mod escrito pela sessão).
Isso inclui as provas que usam --plugin-dir. Hooks de settings, status line e /goal seguem. Reinicie as panes depois.
AVISO

[[ "$MODE" == diff ]] && { echo; echo "(--so-diff: nada foi escrito)"; exit 0; }

echo
confirm "Aplicar?" || { echo "nada foi alterado"; exit 0; }

# passo 2: o instalador (com --root, cópia simples: o instalador exige root de verdade)
dest_existia=0; [[ -e "$DEST" ]] && dest_existia=1
if [[ -n "$ROOT" ]]; then
  rm -rf -- "$DEST"; mkdir -p -- "$DEST"; cp -a -- "$SRC/." "$DEST/"
else
  "$HERE/tools/install-managed-mods.sh" --dest "$DEST"
fi

# passo 3: os settings, com backup do anterior
if (( MUDA )); then
  if [[ -n "$ROOT" ]]; then mkdir -p -- "$SET_DIR"; else install -d -m 755 -o root -g root -- "$SET_DIR"; fi
  bakname="AUSENTE"
  if [[ -f "$SET" ]]; then
    bakname="managed-settings.json.bak-$(date +%Y%m%dT%H%M%S)"
    cp -p -- "$SET" "$SET_DIR/$bakname"
    echo "backup: $SET_DIR/$bakname"
  fi
  new="$SET_DIR/.managed-settings.new.$$"
  cat -- "$tmp/novo.json" > "$new"
  chmod 644 -- "$new"
  [[ -z "$ROOT" ]] && chown root:root -- "$new"
  mv -f -- "$new" "$SET"
  printf 'backup=%s\ndest_existia=%s\nts=%s\n' "$bakname" "$dest_existia" "$(date -Iseconds)" > "$STATE"
  echo "gravado: $SET"
else
  echo "settings já no estado alvo: não gravei nem fiz backup"
fi

echo
echo "== conferência pós-arme =="
if [[ -n "$ROOT" ]]; then
  echo "(raiz falsa: conferência da máquina pulada)"
else
  as_user "$HERE/tools/verificar-mod-armado.sh" || echo "(a conferência acima aponta o que falta; para voltar atrás: sudo $0 --desfazer)"
fi
cat <<FIM

Próximos passos (humano):
  1. Reinicie as panes (os settings gerenciados são lidos na partida).
  2. Em uma sessão nova: claude --debug e procure 'hooks module maestro-guard@maestro-managed loaded' com 'tier prepend'.
  3. Só então: tools/verificar-mod-armado.sh --gravar --vi-tier-prepend  (destrava o patch 072 de remoção do pre-bash-guard).
Desfazer: sudo $0 --desfazer
FIM
