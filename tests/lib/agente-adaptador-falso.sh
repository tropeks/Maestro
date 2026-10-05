#!/usr/bin/env bash
# Adaptador FALSO da ordem 066 — prova o contrato do adaptador sem provedor real.
# O núcleo entrega as capacidades em AGENTE_CAP[] e os padrões de segredo em
# AGENTE_SEGREDOS_PADROES[]; o adaptador devolve AGENTE_CMD[] (argv sem os args
# do provedor), AGENTE_ENV[] (K=V) e AGENTE_ARQUIVOS[] (arquivos gerados).

agente_adaptador_montar() { # <perfil>
  AGENTE_CMD=(provedor-falso)
  local c
  for c in maestro ponte mcp plugins guardas segredos; do
    AGENTE_CMD+=("--cap-$c=${AGENTE_CAP[$c]}")
  done
  AGENTE_CMD+=("--segredos-n=${#AGENTE_SEGREDOS_PADROES[@]}")
  AGENTE_ENV=("FALSO_PERFIL=$1")
  AGENTE_ARQUIVOS=()
  return 0
}
