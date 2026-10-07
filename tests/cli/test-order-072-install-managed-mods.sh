#!/usr/bin/env bash
# ordem 072 turno 2 — tools/install-managed-mods.sh: recusa destino/pai gravável por não-root, recusa destino
# largo ou relativo, `--check` não cria nada, e sem root o instalador não instala. A instalação de verdade
# (cópia, chown root:root, 755/644) é do Capitão, com sudo; este teste NUNCA a roda.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/install-managed-mods.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# rc esperado e trecho esperado da mensagem (stderr+stdout)
expect() {
  local name="$1" want_rc="$2" want_msg="$3"; shift 3
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == *"$want_msg"* ]]; then ok "$name"
  else bad "$name (rc=$rc, esperado $want_rc; saída: $out)"; fi
}

# 1. destino padrão, de root: --check passa
if [[ "$(stat -c '%u %a' /opt)" == "0 755" ]]; then
  expect "check do destino padrão passa" 0 "nada foi criado" "$TOOL" --check
else
  ok "check do destino padrão (pulado: /opt não é 0:755 aqui)"
fi

# 2. pai gravável por todos (/tmp, sticky) recusa
expect "pai /tmp recusa" 2 "RECUSADO" "$TOOL" --check --dest /tmp/maestro-mods-x/claude-plugins
if [[ ! -e /tmp/maestro-mods-x ]]; then ok "--check recusado não criou nada"; else bad "--check criou /tmp/maestro-mods-x"; fi

# 3. pai do usuário (dono não-root) recusa, mesmo com modo 755
mkdir -p "$tmp/pai"; chmod 755 "$tmp/pai"
expect "pai do usuário recusa" 2 "não é root" "$TOOL" --check --dest "$tmp/pai/claude-plugins"

# 4. destino já existente e do usuário recusa
mkdir -p "$tmp/pai/claude-plugins"
expect "destino do usuário recusa" 2 "RECUSADO" "$TOOL" --check --dest "$tmp/pai/claude-plugins"

# 5. destino relativo, raiz e primeiro nível recusam
expect "destino relativo recusa" 2 "absoluto" "$TOOL" --check --dest claude-plugins
expect "destino / recusa" 2 "largo demais" "$TOOL" --check --dest /
expect "destino /opt recusa" 2 "largo demais" "$TOOL" --check --dest /opt
expect "destino com .. que sobe à raiz recusa" 2 "largo demais" "$TOOL" --check --dest /opt/..

# 6. flag desconhecida e --dest sem valor
expect "flag desconhecida" 2 "uso:" "$TOOL" --foo
expect "--dest sem valor" 2 "uso:" "$TOOL" --dest

# 7. sem root, sem --check: recusa (com root real o teste não roda: não instala de verdade aqui)
if (( EUID != 0 )); then
  expect "sem root não instala" 2 "sudo" "$TOOL" --dest /usr/share/maestro-mods-teste/claude-plugins
  if [[ ! -e /usr/share/maestro-mods-teste ]]; then ok "sem root nada foi criado"; else bad "criou /usr/share/maestro-mods-teste"; fi
else
  ok "sem root não instala (pulado: o teste roda como root)"
fi

exit $fail
