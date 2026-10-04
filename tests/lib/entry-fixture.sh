#!/usr/bin/env bash
# ordem 059 — fixture comum dos testes do contrato de entrada (--entry-check).
# Sourceável; o nome não casa com `test-*.sh`, então a suíte não o executa.
# Requer do chamador: REPO, BIN, tmp, e as funções ok/bad.
#
# lib/ está na denylist de autoproteção do gate: a mudança sai como patch em
# docs/patches/059-entrada-de-ordem.patch e o Capitão aplica. Mecanismo ausente
# → PENDENTE (nunca reprova); presente → cobra de verdade.
entry_pendente() {
  [[ -f "$REPO/lib/core-order-entry.sh" ]] && return 0
  echo "PENDENTE  ordem 059: aplique docs/patches/059-entrada-de-ordem.patch (git apply) e rode de novo"
  exit 0
}

G() { git -C "$P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

TURNO_OK='## Turno
- fatia: contrato e validador
- fim: bash tests/x.sh
- teto: 2
- fora: o despacho
- relatório: formato fixo'
CRIT_OK='## Critérios de aceite
- [oráculo: `bash tests/x.sh`] passa.
- [oráculo: teste: test-x] cobre o caso.
- [humano] o Diretor confere.'

entry_project() { # <nome> → $P: repo com INTENT válido e .maestro.yaml, no main
  P="$tmp/$1"; mkdir -p "$P/.maestro"
  git -C "$P" init -q -b main
  cp "$REPO/.maestro/INTENT.md" "$P/.maestro/INTENT.md"
  printf 'experts: [dev-pleno]\n' > "$P/.maestro.yaml"
  echo a > "$P/f.txt"
  G add -A; G commit -qm base
}

entry_order() { # <título> <corpo> → cria a ordem pelo CLI (no checkout atual); não commita
  printf '%s\n' "$2" | "$BIN" order --create --title "$1" --project "$P" --session s0 >/dev/null
}

entry_commit_on_branch() { # <arquivo> → vai ao branch da ordem e commita o arquivo lá
  local br; br=$(grep '^branch:' "$1" | awk '{print $2}')
  G checkout -qb "$br"; G add -A; G commit -qm "ordem"
}

entry_chk() { "$BIN" order --entry-check "$1" --project "$P" 2>&1; }   # stdout+stderr; rc via $?
