#!/usr/bin/env bash
# E24 ordem 011 — GUARDA de execução isolada contra a classe de bug pago nas
# ordens 009 e 010, nas duas: um módulo sai de bin/maestro para lib/*.sh, um
# consumidor continua chamando a função assumindo que ela já está carregada
# (sem passar pelo `_X_lib_load` do consumidor), e a falta vira
#
#   lib/cmd-evidence.sh: line 38: maestro_verif_load: command not found
#
# mascarada em silêncio quando alguém redireciona com `>/dev/null 2>&1`. Esta
# suíte NUNCA faz isso: cada comando roda num PROCESSO LIMPO (`bash "$BIN"
# ...`, não a função do shell atual) com stdout e stderr CAPTURADOS em
# arquivos separados, e reprova se `command not found` aparecer em stderr —
# não importa QUAL função sumiu, então cobre a classe inteira, não só verify.
#
# Hermético: MAESTRO_HOME e CLAUDE_PROJECT_DIR em mktemp -d, igual ao resto
# da suíte. MAESTRO_NO_UPDATE_CHECK=1 — E19, a suíte nunca toca rede.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
export MAESTRO_NO_UPDATE_CHECK=1
PROJ="$tmp/proj"; mkdir -p "$PROJ"
git -C "$PROJ" init -qb main
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
export CLAUDE_PROJECT_DIR="$PROJ"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# run_clean <desc> -- <argv...>
# Roda "$BIN" <argv...> num processo bash LIMPO (nunca a função do shell
# atual — um builtin/função já resolvida não reproduziria "command not
# found"). stdout/stderr vão para arquivos separados: nunca >/dev/null 2>&1,
# que foi exatamente o que mascarou o bug das ordens 009/010.
OUT="$tmp/out"; ERR="$tmp/err"
run_clean() {
  local desc="$1"; shift; [[ "$1" == "--" ]] && shift
  bash "$BIN" "$@" >"$OUT" 2>"$ERR"
  if grep -qi 'command not found' "$ERR"; then
    bad "$desc (command not found: $(grep -i 'command not found' "$ERR" | head -1))"
    return
  fi
  ok "$desc"
}

echo "-- classe inteira: cada comando do CLI, processo limpo, stderr capturado"

run_clean "doctor"                            -- doctor
run_clean "decide (seed p/ outcome/status)"   -- decide --session loaders-1 --workflow fix --mode direct
run_clean "status"                            -- status --session loaders-1
run_clean "log --summary"                     -- log --summary
run_clean "brief"                             -- brief
run_clean "habits"                            -- habits
run_clean "consent"                           -- consent
# outcome accepted é o único caminho que chama _outcome_verif_gate (E23b) —
# maestro_verif_load só roda quando o veredito é accepted (S-2302).
run_clean "outcome accepted (_outcome_verif_gate)" -- outcome --session loaders-1 accepted --suite pass
run_clean "conduct"                           -- conduct --session loaders-1 --approach "guarda de execucao isolada"
run_clean "retro"                             -- retro
run_clean "graph"                             -- graph
# evidence (mode=read default) chama _ev_cmd_verdict → maestro_verif_load
run_clean "evidence (_ev_cmd_verdict)"        -- evidence
# order (--list default) chama maestro_verif_load incondicionalmente em cmd_order
run_clean "order (cmd_order)"                 -- order
run_clean "docs"                              -- docs
run_clean "upgrade (flag inválida, sem rede)" -- upgrade --flag-inexistente
run_clean "telemetry (status default)"        -- telemetry
run_clean "intent --show"                     -- intent --show
# verify: a família inteira (maestro_verif_load/verif_base_ref/verif_required/
# verif_record_hint/cmd_verify) — o alvo nomeado desta ordem
run_clean "verify (cmd_verify)"               -- verify
run_clean "delegation --all"                  -- delegation --all
run_clean "sem subcomando"                    --
run_clean "comando desconhecido"              -- comando-que-nao-existe

echo "-- prova negativa: a guarda REPROVA quando o loader falta (ordens 009/010 ao vivo)"
pend() { printf 'PEND %s\n' "$1"; }
# Sem isto a guarda seria decoração: gera uma cópia SÓ para este teste, com o
# `_verif_lib_load` do consumidor removido — reproduz byte a byte o modo de
# falha das ordens 009/010 e prova que ESTA suíte o pega. Só roda depois que
# o patch da ordem 011 for aplicado (docs/patches/011-*): antes disso o
# marcador não existe em lib/cmd-evidence.sh — `maestro_verif_load` ainda é
# residente de bin/maestro, e não haveria nada para quebrar de propósito.
if grep -q '^  _verif_lib_load   #' "$REPO/lib/cmd-evidence.sh" 2>/dev/null; then
  broken=$(mktemp -d)
  # Cópia do WORKING TREE, não do histórico git: o clone tem de refletir o
  # disco AGORA, não o último commit — REPO_DIR (bin/maestro) resolve pelo
  # próprio caminho do script, então basta preservar bin/+hooks/+lib/+src/
  # na mesma árvore.
  for d in bin hooks lib src; do
    [[ -d "$REPO/$d" ]] && cp -a "$REPO/$d" "$broken/$d"
  done
  sed -i '/^  _verif_lib_load   #/d' "$broken/lib/cmd-evidence.sh"
  bout="$tmp/bout"; berr="$tmp/berr"
  bash "$broken/bin/maestro" evidence >"$bout" 2>"$berr"
  if grep -qi 'command not found' "$berr"; then
    ok "sem _verif_lib_load em cmd-evidence.sh, a guarda VÊ 'command not found' ($(grep -i 'command not found' "$berr" | head -1))"
  else
    bad "guarda não detectou o loader ausente (falso negativo — ver $berr)"
  fi
  rm -rf "$broken"
else
  pend "prova negativa aguarda o patch da ordem 011 (docs/patches/011-*) — lib/cmd-verify.sh ainda não existe neste checkout"
fi

if [[ $fail -eq 0 ]]; then echo "SUITE OK (test-loaders.sh)"; else echo "FALHAS em test-loaders.sh" >&2; fi
exit $fail
