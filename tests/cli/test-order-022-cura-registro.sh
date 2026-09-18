#!/usr/bin/env bash
# ordem 022 — carimbo terminal SÓ-POR-ARQUIVO: `--accept` cura o registro
# ausente em vez de responder "nada a fazer" sem gravar nada.
#
# Causa, medida no Agenda_Studio (ver .maestro/orders/022-*.md): a ordem 021
# tirou o estado TERMINAL da árvore de trabalho (registro em
# `~/.maestro/order-state`, `_order_state_write`/`_order_status`), mas só
# para quem foi carimbado DEPOIS do patch — ordem fechada ANTES continua com
# o carimbo só no `.md` (commitado ou não), sem o registro fora da árvore, e
# volta a "reabrir" no próximo `git checkout`/clone. `maestro order --accept
# N --absorbed-by M` numa ordem nesse estado respondia "já absorvida — nada
# a fazer" e NUNCA gravava o registro — não havia comando para migrar.
#
# Arquivo PRÓPRIO (não em test-order.sh) — mesmo motivo de
# tests/cli/test-order-issue12.sh/issue13.sh/017/013-deferred.sh: não
# estourar o teto da catraca `oversized-file`.
#
# Fixture: em vez de aceitar pela CLI (que, já patchada, sempre grava os dois
# lados no mesmo passo — nunca reproduziria o buraco), o carimbo TERMINAL é
# injetado A MÃO no arquivo, como UMA MODIFICAÇÃO NÃO COMMITADA sobre uma
# base committada SEM carimbo — exatamente a descrição da causa (ordem 021,
# comentário em lib/core-order-state.sh) — e o registro fora da árvore nunca
# é criado por essa injeção. É o retrato fiel de "ordem fechada antes do
# patch": o arquivo tem o carimbo, o registro não existe.
#
# Lição da ordem 003/004A/012/013/017: o teste NÃO exige o patch já aplicado.
# Detecta o MECANISMO (a função `_order_accept_cura_absorvida`, que só existe
# com o conserto desta ordem) em lib/cmd-order.sh OU lib/cmd-order-accept.sh
# (a extração pode ou não estar aplicada quando este teste roda) — ausente →
# PENDENTE e prova o VERMELHO (o defeito reproduz contra o código de hoje,
# nas duas pontas: --accept não grava, e o checkout reabre a ordem); presente
# → cobra de verdade.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
# shellcheck source=hooks/lib/project-state.sh
source "$REPO/hooks/lib/project-state.sh"

CORE_PATCHED=0
grep -qF '_order_accept_cura_absorvida' "$REPO"/lib/cmd-order*.sh 2>/dev/null && CORE_PATCHED=1

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }
git_id() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

# <arquivo> <bloco> — insere <bloco> (multi-linha) antes do "-->" do cabeçalho,
# MESMA técnica de _order_accept_absorb (awk, sem depender do CLI patchado).
inject_header() {
  local of="$1" ins="$2"
  awk -v ins="$ins" '!done && $0 == "-->" { print ins; done=1 } { print }' "$of" > "$of.tmp.$$" \
    && mv -f "$of.tmp.$$" "$of"
}
# <arquivo> <chave> → valor gravado no REGISTRO fora da árvore para a ordem
# (arquivo lido diretamente — não pelo CLI, para o teste não depender de estado
# derivado em cima de estado derivado).
state_field() {
  local proj="$1" of="$2" key="$3" sf oid
  oid=$(awk -F': ' 'NR>20{exit} $1=="id"{print $2; exit}' "$of")
  sf=$(maestro_order_state_file "$proj" "$oid")
  [[ -f "$sf" ]] || { printf ''; return 0; }
  awk -F= -v k="$key" '$1==k{print substr($0,length(k)+2); exit}' "$sf"
}
state_file_of() {
  local proj="$1" of="$2" oid
  oid=$(awk -F': ' 'NR>20{exit} $1=="id"{print $2; exit}' "$of")
  maestro_order_state_file "$proj" "$oid"
}

# ═══════════════════════════════════════════════════════════ fixture (i): absorvida
P="$tmp/proj-abs"; mkdir -p "$P"
git -C "$P" init -q -b main
echo a > "$P/f.txt"; git -C "$P" add -A; git_id "$P" commit -qm base

"$BIN" order --create --title "Absorvida so por arquivo" --project "$P" --session criador <<'BODY' >/dev/null
## Objetivo
Simula uma ordem absorvida ANTES da ordem 021 — carimbo só no arquivo.
BODY
OF1="$P/.maestro/orders/001-absorvida-so-por-arquivo.md"
git -C "$P" add -A; git_id "$P" commit -qm "ordem 001 criada (sem carimbo terminal)"
TREE_LEGADO=$(git -C "$P" rev-parse HEAD^{tree})

# injeta o carimbo LEGADO como modificação NÃO COMMITADA — nenhum registro é
# criado por este passo (é exatamente o buraco que a ordem 022 fecha).
inject_header "$OF1" "$(printf 'absorbed_by: main\nabsorbed_tree: %s\nabsorbed_at: 2026-01-01T00:00:00-03:00\nabsorbed_session: legado-001' "$TREE_LEGADO")"

ST_ANTES=$("$BIN" order --status 1 --project "$P" 2>&1 | head -1)
[[ "$ST_ANTES" == "ordem 001: absorvida" ]] \
  && ok "(i) carimbo legado lê 'absorvida' HOJE (a leitura da ordem 021 já cobre isto)" \
  || bad "(i) esperava 'ordem 001: absorvida' antes de qualquer --accept, obtido '$ST_ANTES'"

SF1=$(state_file_of "$P" "$OF1")
[[ ! -f "$SF1" ]] && ok "(i) registro fora da árvore AINDA não existe (pré-condição da cura)" \
  || bad "(i) registro já existia antes do --accept — fixture não reproduz o buraco"

OUT1=$("$BIN" order --accept 1 --absorbed-by main --project "$P" --session curador 2>&1); RC1=$?

if (( CORE_PATCHED == 0 )); then
  if [[ ! -f "$SF1" && "$RC1" -eq 0 ]]; then
    ok "(i) vermelho confirmado (sem patch): --accept respondeu sem gravar o registro — $OUT1"
  else
    bad "(i) vermelho não reproduziu (sem patch): rc=$RC1 sf_existe=$([[ -f "$SF1" ]] && echo sim || echo nao) — $OUT1"
  fi
  git -C "$P" checkout -q -- "$OF1"
  ST_DEPOIS=$("$BIN" order --status 1 --project "$P" 2>&1 | head -1)
  if [[ "$ST_DEPOIS" != "ordem 001: absorvida" ]]; then
    ok "(i) vermelho confirmado (sem patch): git checkout reabriu a ordem — '$ST_DEPOIS'"
  else
    bad "(i) vermelho não reproduziu: ordem continuou 'absorvida' mesmo sem patch e sem registro (?)"
  fi
  pending "(i) cura de 'absorvida' — lib/cmd-order*.sh sem _order_accept_cura_absorvida; aplicar docs/patches/022-migracao-*.patch"
else
  [[ "$RC1" -eq 0 ]] || bad "(i) --accept --absorbed-by main devia curar com rc=0, obtido $RC1 — $OUT1"
  [[ -f "$SF1" ]] && ok "(i) cura: --accept GRAVOU o registro fora da árvore" \
    || bad "(i) cura: registro continua ausente depois do --accept — $OUT1"
  # reflete o ARQUIVO (legado), não o instante da cura nem a --session do curador.
  ab=$(state_field "$P" "$OF1" absorbed_by); se=$(state_field "$P" "$OF1" absorbed_session)
  at=$(state_field "$P" "$OF1" absorbed_at); tr=$(state_field "$P" "$OF1" absorbed_tree)
  [[ "$ab" == "main" ]] && ok "(i) registro: absorbed_by == 'main' (do arquivo)" || bad "(i) absorbed_by == '$ab'"
  [[ "$se" == "legado-001" ]] && ok "(i) registro: absorbed_session == 'legado-001' (do arquivo, NÃO 'curador')" \
    || bad "(i) absorbed_session == '$se' — a cura reescreveu com o autor de agora em vez do arquivo"
  [[ "$at" == "2026-01-01T00:00:00-03:00" ]] && ok "(i) registro: absorbed_at == o instante do arquivo, não o da cura" \
    || bad "(i) absorbed_at == '$at'"
  [[ "$tr" == "$TREE_LEGADO" ]] && ok "(i) registro: absorbed_tree == a árvore do arquivo" \
    || bad "(i) absorbed_tree == '$tr', esperado '$TREE_LEGADO'"

  # ponta 2: git checkout no arquivo — a ordem TEM de continuar terminal.
  git -C "$P" checkout -q -- "$OF1"
  grep -q '^absorbed_by:' "$OF1" \
    && bad "(i) fixture quebrada: checkout não removeu o carimbo do arquivo" \
    || ok "(i) checkout removeu o carimbo do ARQUIVO (fixture reproduz o cenário)"
  ST_DEPOIS=$("$BIN" order --status 1 --project "$P" 2>&1 | head -1)
  [[ "$ST_DEPOIS" == "ordem 001: absorvida" ]] \
    && ok "(i) CURA: continua 'absorvida' depois do checkout (o registro, não o arquivo, decidiu)" \
    || bad "(i) CURA falhou: '$ST_DEPOIS' depois do checkout — a ordem reabriu"

  # não-reescrita: registro não muda com uma segunda tentativa (idempotência,
  # mesmo depois do checkout ter apagado o arquivo).
  SNAP_ANTES=$(cat "$SF1")
  OUT1B=$("$BIN" order --accept 1 --absorbed-by main --project "$P" --session outro-curador 2>&1)
  SNAP_DEPOIS=$(cat "$SF1")
  grep -qi 'nada a fazer' <<<"$OUT1B" && ok "(i) não-reescrita: segunda tentativa é 'nada a fazer'" \
    || bad "(i) não-reescrita: segunda tentativa não disse 'nada a fazer' — $OUT1B"
  [[ "$SNAP_ANTES" == "$SNAP_DEPOIS" ]] && ok "(i) não-reescrita: o registro NÃO mudou byte a byte" \
    || bad "(i) não-reescrita: o registro mudou — cura virou recarimbo"
fi

# ═══════════════════════════════════ fixture (ii): absorvida com campo AUSENTE (v1.11: carimbo à mão)
P2="$tmp/proj-abs-manual"; mkdir -p "$P2"
git -C "$P2" init -q -b main
echo a > "$P2/f.txt"; git -C "$P2" add -A; git_id "$P2" commit -qm base
"$BIN" order --create --title "Carimbo manual so absorbed by" --project "$P2" --session criador <<'BODY' >/dev/null
## Objetivo
DATA_MODEL v1.11: absorbed_by carimbado a mao, sem os outros 3 campos.
BODY
OF2="$P2/.maestro/orders/001-carimbo-manual-so-absorbed-by.md"
git -C "$P2" add -A; git_id "$P2" commit -qm "ordem criada"
inject_header "$OF2" "absorbed_by: main"   # só isto — como o d394a47 real, v1.11

if (( CORE_PATCHED == 1 )); then
  "$BIN" order --accept 1 --absorbed-by main --project "$P2" --session curador >/tmp/.o22-out.$$ 2>&1
  OUT2=$(cat "/tmp/.o22-out.$$"); rm -f "/tmp/.o22-out.$$"
  SF2=$(state_file_of "$P2" "$OF2")
  tr2=$(state_field "$P2" "$OF2" absorbed_tree); at2=$(state_field "$P2" "$OF2" absorbed_at); se2=$(state_field "$P2" "$OF2" absorbed_session)
  [[ -f "$SF2" ]] && ok "(ii) campo ausente: cura mesmo assim gravou o registro" || bad "(ii) não gravou — $OUT2"
  [[ "$tr2" == "desconhecida" ]] && ok "(ii) absorbed_tree ausente vira sentinela 'desconhecida' (mesmo usado em accepted_tree)" \
    || bad "(ii) absorbed_tree == '$tr2', esperado 'desconhecida'"
  [[ "$at2" == "desconhecido" && "$se2" == "desconhecido" ]] \
    && ok "(ii) absorbed_at/absorbed_session ausentes viram 'desconhecido' (sem inventar o instante da cura)" \
    || bad "(ii) absorbed_at='$at2' absorbed_session='$se2', esperado 'desconhecido' nos dois"
else
  pending "(ii) campo ausente no carimbo legado — só testável com o conserto aplicado"
fi

# ═══════════════════════════════════════════════════════════ fixture (iii): aceita
P3="$tmp/proj-ace"; mkdir -p "$P3"
git -C "$P3" init -q -b main
echo a > "$P3/f.txt"; git -C "$P3" add -A; git_id "$P3" commit -qm base
"$BIN" order --create --title "Aceita so por arquivo" --project "$P3" --session criador <<'BODY' >/dev/null
## Objetivo
Simula uma ordem aceita ANTES da ordem 021 — carimbo só no arquivo, nada moveu depois.
BODY
OF3="$P3/.maestro/orders/001-aceita-so-por-arquivo.md"
BR3=$(grep '^branch:' "$OF3" | awk '{print $2}')
git -C "$P3" checkout -qb "$BR3"
echo b >> "$P3/f.txt"; git -C "$P3" add f.txt; git_id "$P3" commit -qm entrega
TREE_ACEITA=$(git -C "$P3" rev-parse HEAD^{tree})
git -C "$P3" checkout -q main
git -C "$P3" add -A; git_id "$P3" commit -qm "ordem criada (sem carimbo terminal)"

# stamp LEGADO anexado ao FINAL, exatamente como _order_accept_own grava —
# como modificação NÃO COMMITADA sobre a base commitada sem carimbo (mesma
# técnica da fixture i) — nenhum registro é criado por isto.
{
  printf 'accepted_at: 2026-01-02T00:00:00-03:00\n'
  printf 'accepted_session: legado-002\n'
  printf 'accepted_tree: %s\n' "$TREE_ACEITA"
} >> "$OF3"

ST3_ANTES=$("$BIN" order --status 1 --project "$P3" 2>&1 | head -1)
[[ "$ST3_ANTES" == "ordem 001: aceita" ]] \
  && ok "(iii) carimbo legado lê 'aceita' HOJE" || bad "(iii) esperava 'ordem 001: aceita', obtido '$ST3_ANTES'"
SF3=$(state_file_of "$P3" "$OF3")
[[ ! -f "$SF3" ]] && ok "(iii) registro fora da árvore ainda não existe (pré-condição)" \
  || bad "(iii) registro já existia — fixture não reproduz o buraco"

OUT3=$("$BIN" order --accept 1 --project "$P3" --session curador 2>&1); RC3=$?
if (( CORE_PATCHED == 0 )); then
  if [[ ! -f "$SF3" && "$RC3" -eq 0 ]]; then
    ok "(iii) vermelho confirmado (sem patch): --accept respondeu sem gravar o registro — $OUT3"
  else
    bad "(iii) vermelho não reproduziu: rc=$RC3 sf=$([[ -f "$SF3" ]] && echo sim || echo nao) — $OUT3"
  fi
  git -C "$P3" checkout -q -- "$OF3"
  ST3_DEPOIS=$("$BIN" order --status 1 --project "$P3" 2>&1 | head -1)
  [[ "$ST3_DEPOIS" != "ordem 001: aceita" ]] \
    && ok "(iii) vermelho confirmado (sem patch): checkout reabriu a ordem — '$ST3_DEPOIS'" \
    || bad "(iii) vermelho não reproduziu: continuou 'aceita' sem registro (?)"
  pending "(iii) cura de 'aceita' — lib/cmd-order*.sh sem _order_accept_cura_absorvida; aplicar docs/patches/022-migracao-*.patch"
else
  [[ "$RC3" -eq 0 ]] || bad "(iii) --accept devia curar com rc=0, obtido $RC3 — $OUT3"
  [[ -f "$SF3" ]] && ok "(iii) cura: --accept GRAVOU o registro fora da árvore" \
    || bad "(iii) cura: registro continua ausente — $OUT3"
  at3=$(state_field "$P3" "$OF3" accepted_at); se3=$(state_field "$P3" "$OF3" accepted_session); tr3=$(state_field "$P3" "$OF3" accepted_tree)
  [[ "$se3" == "legado-002" ]] && ok "(iii) registro: accepted_session == 'legado-002' (do arquivo, NÃO 'curador')" \
    || bad "(iii) accepted_session == '$se3'"
  [[ "$at3" == "2026-01-02T00:00:00-03:00" ]] && ok "(iii) registro: accepted_at == o instante do arquivo" \
    || bad "(iii) accepted_at == '$at3'"
  [[ "$tr3" == "$TREE_ACEITA" ]] && ok "(iii) registro: accepted_tree == a árvore do arquivo" \
    || bad "(iii) accepted_tree == '$tr3', esperado '$TREE_ACEITA'"

  git -C "$P3" checkout -q -- "$OF3"
  grep -q '^accepted_at:' "$OF3" \
    && bad "(iii) fixture quebrada: checkout não removeu o carimbo do arquivo" \
    || ok "(iii) checkout removeu o carimbo do ARQUIVO (fixture reproduz o cenário)"
  ST3_DEPOIS=$("$BIN" order --status 1 --project "$P3" 2>&1 | head -1)
  [[ "$ST3_DEPOIS" == "ordem 001: aceita" ]] \
    && ok "(iii) CURA: continua 'aceita' depois do checkout" \
    || bad "(iii) CURA falhou: '$ST3_DEPOIS' depois do checkout"

  SNAP3_ANTES=$(cat "$SF3")
  OUT3B=$("$BIN" order --accept 1 --project "$P3" --session outro-curador 2>&1)
  SNAP3_DEPOIS=$(cat "$SF3")
  grep -qi 'já aceita' <<<"$OUT3B" && ok "(iii) não-reescrita: segunda tentativa é 'já aceita'" \
    || bad "(iii) não-reescrita: segunda tentativa não disse 'já aceita' — $OUT3B"
  [[ "$SNAP3_ANTES" == "$SNAP3_DEPOIS" ]] && ok "(iii) não-reescrita: o registro NÃO mudou byte a byte" \
    || bad "(iii) não-reescrita: o registro mudou — cura virou recarimbo"
fi

if (( fail == 0 )); then echo "SUITE test-order-022-cura-registro.sh: OK"; else echo "SUITE test-order-022-cura-registro.sh: FALHAS" >&2; fi
exit $fail
