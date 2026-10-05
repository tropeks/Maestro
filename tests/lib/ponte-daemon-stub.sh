#!/usr/bin/env bash
# Stub do `ponte-daemon mcp` para a fixture da ordem 066: só conecta no
# PONTE_MCP_SOCKET (o da fixture) e sai. Nunca toca o ~/.ponte real.
[[ -n "${PONTE_MCP_SOCKET:-}" ]] || exit 2
exec python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.close()' "$PONTE_MCP_SOCKET"
