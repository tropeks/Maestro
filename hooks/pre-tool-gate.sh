#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
maestro_killswitch
# [E2/S-203] Política compilada + verificação de decision record entram aqui (modo warn default).
exit 0
