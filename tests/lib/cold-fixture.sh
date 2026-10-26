#!/usr/bin/env bash
# ordem 084 — fixture comum dos testes da revisão fria. Sourceável (o nome não casa com `test-*.sh`).
# Requer do chamador: REPO, tmp, MAESTRO_HOME exportado, ok/bad. Usa entry-fixture.sh e declare-order.sh.
#
# O roteamento do CLI (lib/cmd-order.sh, core-order-entry.sh, core-order-turno.sh, cmd-order-accept.sh)
# sai como patch em docs/patches/084-revisao-fria-roteamento.patch e o Capitão aplica. Para o teste não
# depender disso, `cold_setup` roda numa CÓPIA do repo e aplica o patch nela, se ainda não estiver aplicado.
# BIN passa a apontar para a cópia; REPO continua sendo o repo real.

cold_setup() {
  local copy="$tmp/maestro-copy" patch="$REPO/docs/patches/084-revisao-fria-roteamento.patch"
  mkdir -p "$copy"
  (cd "$REPO" && tar --exclude=.git -cf - .) | tar -xf - -C "$copy"
  if (cd "$copy" && git apply --check "$patch" 2>/dev/null); then (cd "$copy" && git apply "$patch"); fi
  grep -q 'core-order-cold.sh' "$copy/lib/cmd-order.sh" || { echo "FAIL fixture: patch 084 não aplicou na cópia"; exit 1; }
  BIN="$copy/bin/maestro"
  unset MAESTRO_COLD_REVIEW_REQUIRE MAESTRO_ENTRY_REQUIRE
}

TURNO_BAIXO="$TURNO_OK"
TURNO_ALTO="$TURNO_OK
- risco: alto"

cold_findings() { # <arquivo> <linhas...> — grava o arquivo de achados do revisor
  local f="$1"; shift
  printf '%s\n' "$@" > "$f"
}

cold_record() { # <id> <aprova|devolve> <arquivo> [extra...] — roda --cold-record no projeto $P
  local n="$1" v="$2" f="$3"; shift 3
  "$BIN" order --cold-record "$n" --verdict "$v" --findings "$f" --project "$P" --session s1 "$@" 2>&1
}
