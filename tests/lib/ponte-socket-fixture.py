#!/usr/bin/env python3
"""Fixture da ordem 066: servidor Unix que REGISTRA cada conexão recebida.

uso: ponte-socket-fixture.py <socket> <log>
Cada conexão vira uma linha "conexao" no <log> (só metadado, nenhum byte do cliente).
Imprime "pronto" na stdout quando o socket já escuta. Termina com SIGTERM.
"""
import os
import signal
import socket
import sys

sock_path, log_path = sys.argv[1], sys.argv[2]
if os.path.exists(sock_path):
    os.unlink(sock_path)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(sock_path)
srv.listen(16)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
print("pronto", flush=True)
while True:
    conn, _ = srv.accept()
    with open(log_path, "a") as fh:
        fh.write("conexao\n")
    conn.close()
