#!/usr/bin/env bash
# ordem 078 — recibo gravado por ESCRITA DIRETA do arquivo (formato maestro-evidence-v1, via _ev_write), para os
# testes que exercitam o LEITOR (order --status, evidence --check, veredito) com um rótulo que o CLI recusa
# gravar: `order-N-<dono8>` (a ordem vive no repo dono, não no do trabalho) ou `cmd_match=no`.
# Quem faz `source` já definiu REPO (raiz do plugin sob teste) e MAESTRO_HOME exportado.
#
#   write_receipt <projeto> <rótulo> [comando=true] [cmd_match=free] [exit=0]
#
# Grava em $MAESTRO_HOME/evidence o recibo de <rótulo> para <projeto>, com wtree antes == depois == árvore
# ATUAL do projeto (o mesmo que o --record mediria), carga 0 e nenhuma medição inconclusiva.

write_receipt() {
  local proj="$1" label="$2" cmd="${3:-true}" match="${4:-free}" rc="${5:-0}"
  REPO_DIR="$REPO" WR_PROJ="$proj" WR_LABEL="$label" WR_CMD="$cmd" WR_MATCH="$match" WR_RC="$rc" bash -c '
    source "$REPO_DIR/hooks/lib/common.sh"
    source "$REPO_DIR/lib/core-evidence.sh"
    ef=$(maestro_evidence_file "$WR_PROJ" "$WR_LABEL")
    wt=$("$REPO_DIR/bin/maestro-wtree" "$WR_PROJ" 2>/dev/null) || wt=none
    h=$(printf "%s" "$WR_CMD" | sha256sum | head -c 16)
    _ev_write "$ef" "$WR_LABEL" "$h" "$WR_RC" "$wt" "$wt" "$WR_MATCH" 0 1 0 0
  '
}
