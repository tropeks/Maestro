#!/usr/bin/env bash
# Provedor FALSO da ordem 066: registra que foi lançado (e com que args) e sai com FALSO_RC.
# FALSO_REGISTRO aponta o arquivo de registro; sem ele, não registra nada.
[[ -n "${FALSO_REGISTRO:-}" ]] && printf '%s\n' "$@" > "$FALSO_REGISTRO"
exit "${FALSO_RC:-0}"
