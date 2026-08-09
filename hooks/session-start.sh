#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
maestro_killswitch

# Limpeza de decision records expirados (TTL — ADR-003 v1.1). Falha degrada.
{
  maestro_ensure_dirs
  now=$(date +%s)
  for f in "$MAESTRO_SESSIONS_DIR"/*.json; do
    [[ -e "$f" ]] || break
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo "$now")
    if (( now - mtime > MAESTRO_TTL_SECONDS )); then rm -f "$f" 2>/dev/null || true; fi
  done
} 2>/dev/null || true

# [E2/S-201] Injeção do bloco <maestro-routing> entra aqui. Por ora, marcador mínimo:
echo "<maestro-routing>Maestro v0.1 instalado (E1). Roteamento completo chega no E2. Kill-switch: MAESTRO_OFF=1.</maestro-routing>"
exit 0
