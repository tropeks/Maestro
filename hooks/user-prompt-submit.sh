#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
maestro_killswitch
# [E2/S-205] Detecção de override manual (prompt iniciando com /) entra aqui.
exit 0
