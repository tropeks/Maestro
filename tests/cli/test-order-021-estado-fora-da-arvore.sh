#!/usr/bin/env bash
# ordem 021 — o carimbo terminal (accepted_at/absorbed_by) só existia como
# modificação NÃO COMMITADA no arquivo da ordem: `maestro order --accept`
# escreve na árvore de trabalho e para aí. Qualquer `git checkout` que
# restaure o HEAD apaga o carimbo em silêncio, e a ordem "reabre" sozinha.
#
# Caso real, medido no Agenda_Studio (2026-09-18):
#   git status --porcelain .maestro/orders/  →  M nos cinco arquivos (012-016)
#   git show HEAD:…/012-…md | grep -c '^absorbed_by:'   → 0
#   grep -c '^absorbed_by:' …/012-…md                    → 1
# O diretor fechou 012-016 como absorvidas, mergeou o PR, main andou — as
# cinco voltaram a 'provada' em `maestro order --list` E na ronda da Ponte.
# O refechamento FUNCIONOU (_order_accept_absorb não disse "já absorvida"):
# prova de que o carimbo tinha mesmo sumido, não que um leitor mentia.
#
# O TESTE QUE É A ORDEM (DATA_MODEL §9, emenda v1.18): carimba → git
# checkout no arquivo da ordem → o estado CONTINUA terminal — nos dois
# desfechos (absorvida e aceita) — porque a FONTE passa a ser o registro
# fora da árvore (`~/.maestro/order-state/`, `maestro_order_state_file`,
# hooks/lib/project-state.sh), e o arquivo vira conveniência de leitura.
#
# Lição da ordem 003/004A/013/017, contrato desta ordem: o teste NÃO exige
# os patches já aplicados. Detecta o MECANISMO: ausente → PENDENTE (nunca
# reprova — lib/ e hooks/ estão na denylist de autoproteção do gate, quem
# aplica docs/patches/ é o Capitão); presente → cobra de verdade e REPROVA
# se o mecanismo não funcionar.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
COS="$REPO/lib/core-order-state.sh"
PST="$REPO/hooks/lib/project-state.sh"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

# Mecanismo desta ordem: o registro fora da árvore E a leitura que o prefere.
CORE_PATCHED=0
if grep -qF '_order_state_write' "$COS" 2>/dev/null && grep -qF 'maestro_order_state_file' "$PST" 2>/dev/null; then
  CORE_PATCHED=1
fi

git_init_main() { # <dir> → git init com o branch de topo chamado 'main'
  local d="$1"
  git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD refs/heads/main
}
git_id() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

state_file_for() { # <id> → caminho do registro fora da árvore, se existir (glob por sufixo -NNN)
  find "$MAESTRO_HOME/order-state" -maxdepth 1 -type f -name "*-$(printf '%03d' "$1")" 2>/dev/null | head -1
}

P="$tmp/proj"; mkdir -p "$P"
git_init_main "$P"
echo a > "$P/f.txt"; git_id "$P" add f.txt
git_id "$P" commit -qm base

# ===========================================================================
# fixture 1 — DESFECHO absorvida. A ordem é COMMITADA (é assim que o
# Agenda_Studio versiona .maestro/orders/, e é o `M` que a reprodução real
# mostra: arquivo RASTREADO, carimbo NÃO commitado). Carimba, confere
# concordância (precedência caso 3), faz `git checkout` no arquivo (apaga o
# carimbo — a causa raiz), confere que o estado sobrevive (precedência
# caso 2) contra o registro fora da árvore.
# ===========================================================================
"$BIN" order --create --title "Vai ser absorvida" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Absorvida pelo main — reproduz o caso do Agenda_Studio (arquivo commitado, carimbo não).
BODY
OF1="$P/.maestro/orders/001-vai-ser-absorvida.md"
git_id "$P" add "$OF1"
git_id "$P" commit -qm "ordem 1 versionada (pré-carimbo)"

echo b >> "$P/f.txt"; git_id "$P" add f.txt
git_id "$P" commit -qm "main andou"
"$BIN" evidence --record --label main --project "$P" -- true >/dev/null
"$BIN" order --accept 1 --absorbed-by main --project "$P" --session dir-1 >/dev/null 2>&1

ST1A=$(head -1 <<<"$("$BIN" order --status 1 --project "$P" 2>&1)" | awk '{print $3}')
[[ "$ST1A" == "absorvida" ]] \
  && ok "(i.a) antes do checkout: 'absorvida' — arquivo carimbado e (se patched) registro concordando" \
  || bad "(i.a) antes do checkout: esperava 'absorvida', obtido '$ST1A'"

git_id "$P" checkout -q -- "$OF1"   # restaura do HEAD — apaga o carimbo NÃO commitado
if grep -q '^absorbed_by:' "$OF1" 2>/dev/null; then
  bad "(i.b) checkout não removeu o carimbo do arquivo — fixture não reproduz o Agenda_Studio"
else
  ok "(i.b) checkout removeu o carimbo do arquivo (fixture reproduz o Agenda_Studio)"
fi

TXT1B=$("$BIN" order --status 1 --project "$P" 2>&1)
ST1B=$(head -1 <<<"$TXT1B" | awk '{print $3}')
if (( CORE_PATCHED == 0 )); then
  pending "(i.c) sem o patch: estado depois do checkout = '$ST1B' — aplicar docs/patches/021-estado-terminal-*.patch"
  # a asserção que PROVA o defeito hoje, contra o código sem o patch — vermelha:
  [[ "$ST1B" != "absorvida" ]] \
    && ok "vermelho confirmado (sem patch): checkout apaga o estado terminal (absorvida) — $TXT1B" \
    || bad "vermelho não reproduziu: esperava a REGRESSÃO (≠absorvida) sem patch, obtido '$ST1B'"
else
  [[ "$ST1B" == "absorvida" ]] \
    && ok "(i.c) DEPOIS do checkout: continua 'absorvida' — registro fora da árvore sustenta o estado" \
    || bad "(i.c) DEPOIS do checkout: esperava 'absorvida', obtido '$ST1B' — $TXT1B"
fi

# ===========================================================================
# fixture 2 — DESFECHO aceita. MESMO mecanismo, outro carimbo (accepted_at,
# ANEXADO ao final do arquivo, não no cabeçalho) — os dois desfechos têm o
# MESMO defeito, o teste cobre os dois.
# ===========================================================================
"$BIN" order --create --title "Vai aceitar" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Prova o próprio trabalho e aceita — depois o arquivo sofre checkout.
BODY
OF2="$P/.maestro/orders/002-vai-aceitar.md"
git_id "$P" add "$OF2"
git_id "$P" commit -qm "ordem 2 versionada (pré-carimbo)"
BR2=$(grep '^branch:' "$OF2" | awk '{print $2}')
git_id "$P" checkout -qb "$BR2"
echo c >> "$P/f.txt"; git_id "$P" add f.txt
git_id "$P" commit -qm entrega2
"$BIN" evidence --record --label order-2 --project "$P" -- true >/dev/null
"$BIN" order --accept 2 --project "$P" --session dir-1 >/dev/null 2>&1

ST2A=$(head -1 <<<"$("$BIN" order --status 2 --project "$P" 2>&1)" | awk '{print $3}')
[[ "$ST2A" == "aceita" ]] \
  && ok "(ii.a) antes do checkout: 'aceita' — arquivo carimbado e (se patched) registro concordando" \
  || bad "(ii.a) antes do checkout: esperava 'aceita', obtido '$ST2A'"

git_id "$P" checkout -q -- "$OF2"
if grep -q '^accepted_at:' "$OF2" 2>/dev/null; then
  bad "(ii.b) checkout não removeu o carimbo do arquivo — fixture não reproduz o Agenda_Studio"
else
  ok "(ii.b) checkout removeu o carimbo do arquivo (fixture reproduz o Agenda_Studio)"
fi

TXT2B=$("$BIN" order --status 2 --project "$P" 2>&1)
ST2B=$(head -1 <<<"$TXT2B" | awk '{print $3}')
if (( CORE_PATCHED == 0 )); then
  pending "(ii.c) sem o patch: estado depois do checkout = '$ST2B' — aplicar docs/patches/021-estado-terminal-*.patch"
  [[ "$ST2B" != "aceita" ]] \
    && ok "vermelho confirmado (sem patch): checkout apaga o estado terminal (aceita) — $TXT2B" \
    || bad "vermelho não reproduziu: esperava a REGRESSÃO (≠aceita) sem patch, obtido '$ST2B'"
else
  [[ "$ST2B" == "aceita" ]] \
    && ok "(ii.c) DEPOIS do checkout: continua 'aceita' — registro fora da árvore sustenta o estado" \
    || bad "(ii.c) DEPOIS do checkout: esperava 'aceita', obtido '$ST2B' — $TXT2B"
fi
git_id "$P" checkout -q main

# ===========================================================================
# fixture 3 — precedência caso 1 (MIGRAÇÃO): ordem carimbada sob o código
# ANTIGO (nenhum registro jamais existiu para ela) não pode "reabrir" quando
# este código entra. Simulado apagando o registro logo depois de um --accept
# normal — o arquivo, sozinho, ainda tem de bastar.
# ===========================================================================
if (( CORE_PATCHED == 0 )); then
  pending "(iii) precedência caso 1 (migração): sem o patch não há registro para apagar — nada a testar ainda"
else
  "$BIN" order --create --title "Migracao" --project "$P" --session dir-1 <<'BODY' >/dev/null
## Objetivo
Simula ordem aceita sob o código anterior a esta emenda (sem registro nunca gravado).
BODY
  OF3="$P/.maestro/orders/003-migracao.md"
  BR3=$(grep '^branch:' "$OF3" | awk '{print $2}')
  git_id "$P" checkout -qb "$BR3"
  echo d >> "$P/f.txt"; git_id "$P" add f.txt
  git_id "$P" commit -qm entrega3
  "$BIN" evidence --record --label order-3 --project "$P" -- true >/dev/null
  "$BIN" order --accept 3 --project "$P" --session dir-1 >/dev/null 2>&1
  git_id "$P" checkout -q main

  SF3=$(state_file_for 3)
  if [[ -z "$SF3" || ! -f "$SF3" ]]; then
    bad "(iii) setup: --accept não gravou registro fora da árvore para a ordem 3 (nada pra apagar)"
  else
    rm -f "$SF3"   # apaga o registro — reproduz "nunca existiu" (código anterior a esta emenda)
    ST3=$(head -1 <<<"$("$BIN" order --status 3 --project "$P" 2>&1)" | awk '{print $3}')
    [[ "$ST3" == "aceita" ]] \
      && ok "(iii) precedência caso 1 (migração): arquivo carimbado + registro AUSENTE → 'aceita', nunca 'aberta'" \
      || bad "(iii) precedência caso 1 (migração): esperava 'aceita', obtido '$ST3' — regressão que reabriria ordens já aceitas em outros projetos desta máquina"
  fi
fi

# ===========================================================================
# (iv) --json da fixture 1 (pós-checkout): terminal/absorvido_por são o
# contrato externo — supervisor e watcher.ts decidem por eles. Confere que a
# LEITURA de exibição (absorbed_by) também sobrevive ao checkout, não só o
# 'estado' cru — sem isso, 'absorvida' com 'absorvido_por' vazio seria uma
# regressão de qualidade (o consumidor vê terminal:true mas não sabe por quem).
# ===========================================================================
if command -v jq >/dev/null 2>&1; then
  JSON1=$("$BIN" order --status 1 --project "$P" --json 2>&1)
  if jq -e . >/dev/null 2>&1 <<<"$JSON1"; then
    j_estado=$(jq -r '.estado' <<<"$JSON1")
    j_terminal=$(jq -r '.terminal' <<<"$JSON1")
    j_abs=$(jq -r '.absorvido_por' <<<"$JSON1")
    if (( CORE_PATCHED == 0 )); then
      pending "(iv) --json pós-checkout ainda sem o patch — estado='$j_estado' absorvido_por='$j_abs'"
    else
      [[ "$j_estado" == "absorvida" ]] && ok "(iv) --json: estado == 'absorvida' depois do checkout" \
        || bad "(iv) --json: estado == '$j_estado', esperava 'absorvida'"
      [[ "$j_terminal" == "true" ]] && ok "(iv) --json: terminal == true" \
        || bad "(iv) --json: terminal == '$j_terminal', esperava 'true'"
      [[ "$j_abs" == "main" ]] && ok "(iv) --json: absorvido_por == 'main' (leitura de exibição também sobrevive ao checkout)" \
        || bad "(iv) --json: absorvido_por == '$j_abs', esperava 'main'"
    fi
  else
    bad "(iv) --json não é JSON válido: $JSON1"
  fi
else
  pending "(iv) jq ausente — pulando as asserções de --json"
fi

if (( fail == 0 )); then echo "SUITE test-order-021-estado-fora-da-arvore.sh: OK"; else echo "SUITE test-order-021-estado-fora-da-arvore.sh: FALHAS" >&2; fi
exit $fail
