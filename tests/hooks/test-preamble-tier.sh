#!/usr/bin/env bash
# E25 / S-2502 — preâmbulo graduado: `preamble: full|standard|lean` no .maestro.yaml.
#
# O que este teste protege:
#  1. o DEFAULT é sagrado — projeto sem a chave recebe a injeção de sempre, byte
#     a byte. Um tier novo que mexesse na saída de quem não pediu nada seria uma
#     mudança silenciosa de contexto em todo projeto instalado.
#  2. nada some em silêncio — tier ≠ full anuncia no cabeçalho o que ficou de
#     fora e onde está o texto íntegro (mesmo princípio do `no-stable` do E19 e
#     do `direção: nenhuma` do E22).
#  3. o núcleo NUNCA cede — <maestro-routing>, session_id, instrução canônica do
#     `decide`, a linha do desfecho `killed` e o fechamento do bloco sobrevivem
#     em todo tier. Preâmbulo enxuto é menos catálogo, nunca menos contrato.
#
# Isolamento: MAESTRO_HOME e CLAUDE_PROJECT_DIR sempre em mktemp -d. NUNCA toca o
# ~/.maestro real. A routing table e o roster são os do repo de propósito: o que
# se mede aqui é a economia REAL do tier, não a de um fixture inventado.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$1" == "yes" ]]; then ok "$2"; else bad "$2${3:+ — $3}"; fi; }

IN="$SANDBOX/in.json"
printf '{"session_id":"ses_E25","hook_event_name":"SessionStart"}' >"$IN"

# run <tag> <conteúdo-do-.maestro.yaml|-> → arquivo em $SANDBOX/out.<tag>,
# conteúdo em $OUT, rc em $RC, tamanho em $BYTES.
run() {
  local tag="$1" yaml="${2:--}"
  local p; p=$(mktemp -d "$SANDBOX/proj.XXXXXX")
  [[ "$yaml" == "-" ]] || printf '%s\n' "$yaml" >"$p/.maestro.yaml"
  env MAESTRO_HOME="$(mktemp -d "$SANDBOX/home.XXXXXX")" CLAUDE_PROJECT_DIR="$p" \
    bash "$HOOK" <"$IN" >"$SANDBOX/out.$tag" 2>"$SANDBOX/err.$tag"
  RC=$?
  OUT=$(cat "$SANDBOX/out.$tag")
  BYTES=$(wc -c <"$SANDBOX/out.$tag" | tr -d ' ')
  return 0
}

HDR_ROUTES='## Rotas (intenção → workflow) e workflows'
HDR_HEUR='## Heurísticas de execução'
HDR_ROSTER='## Roster'

# nucleo <descrição> — o contrato que vale em TODOS os tiers.
nucleo() {
  local what="$1"
  [[ "$OUT" == *"<maestro-routing>"* ]] \
    && ok "$what: abre o bloco" || bad "$what: abre o bloco"
  [[ "$OUT" == *"session_id: ses_E25"* ]] \
    && ok "$what: session_id preservado" || bad "$what: session_id preservado"
  [[ "$OUT" == *"maestro decide --session ses_E25 --workflow"* ]] \
    && ok "$what: instrução canônica do decide intacta" || bad "$what: instrução canônica do decide intacta"
  [[ "$OUT" == *"maestro outcome --session ses_E25 killed --reason"* ]] \
    && ok "$what: linha do desfecho killed intacta" || bad "$what: linha do desfecho killed intacta"
  [[ "$OUT" == *"</maestro-routing>"* ]] \
    && ok "$what: fecha o bloco" || bad "$what: fecha o bloco"
  [[ $RC -eq 0 ]] && ok "$what: exit 0" || bad "$what: exit 0 (rc=$RC)"
}

# =============================================================================
echo "-- 1. default: a chave ausente é idêntica a preamble: full (byte a byte)"
# =============================================================================
run ausente -
B_AUSENTE=$BYTES
nucleo "sem .maestro.yaml"
[[ "$OUT" == *"$HDR_ROUTES"* && "$OUT" == *"$HDR_HEUR"* && "$OUT" == *"$HDR_ROSTER"* ]] \
  && chk yes "sem a chave: rotas, heurísticas e roster continuam na injeção" \
  || chk no "sem a chave: rotas, heurísticas e roster continuam na injeção"
[[ "$OUT" != *"preâmbulo:"* ]] \
  && chk yes "sem a chave: nenhuma linha de tier polui o cabeçalho" \
  || chk no "sem a chave: nenhuma linha de tier polui o cabeçalho"

run full 'preamble: full'
cmp -s "$SANDBOX/out.ausente" "$SANDBOX/out.full" \
  && chk yes "preamble: full sai byte a byte igual à ausência da chave ($BYTES B)" \
  || chk no "preamble: full sai byte a byte igual à ausência da chave" \
           "ausente=${B_AUSENTE}B full=${BYTES}B"
B_FULL=$BYTES

# `preamble:` sem valor é silêncio, não escolha: cai em full sem reclamar.
run vazio 'preamble:'
cmp -s "$SANDBOX/out.ausente" "$SANDBOX/out.vazio" \
  && chk yes "preamble: sem valor degrada para full, sem linha de aviso" \
  || chk no "preamble: sem valor degrada para full, sem linha de aviso"

# =============================================================================
echo "-- 2. standard: rotas fora; heurísticas e roster ficam"
# =============================================================================
run standard 'preamble: standard'
B_STD=$BYTES
nucleo "standard"
[[ "$OUT" != *"$HDR_ROUTES"* ]] \
  && chk yes "standard: seção de rotas fora da injeção" || chk no "standard: seção de rotas fora da injeção"
[[ "$OUT" == *"$HDR_HEUR"* ]] \
  && chk yes "standard: heurísticas de execução continuam" || chk no "standard: heurísticas de execução continuam"
[[ "$OUT" == *"$HDR_ROSTER"* ]] \
  && chk yes "standard: roster continua" || chk no "standard: roster continua"
[[ $B_STD -lt $B_FULL ]] \
  && chk yes "standard é menor que full (${B_STD}B < ${B_FULL}B; -$(( B_FULL - B_STD ))B)" \
  || chk no "standard é menor que full" "std=${B_STD}B full=${B_FULL}B"

# =============================================================================
echo "-- 3. lean: rotas, heurísticas e roster fora"
# =============================================================================
run lean 'preamble: lean'
B_LEAN=$BYTES
nucleo "lean"
[[ "$OUT" != *"$HDR_ROUTES"* ]] \
  && chk yes "lean: rotas fora" || chk no "lean: rotas fora"
[[ "$OUT" != *"$HDR_HEUR"* ]] \
  && chk yes "lean: heurísticas fora" || chk no "lean: heurísticas fora"
[[ "$OUT" != *"$HDR_ROSTER"* ]] \
  && chk yes "lean: roster fora" || chk no "lean: roster fora"
[[ $B_LEAN -lt $B_STD ]] \
  && chk yes "lean é menor que standard (${B_LEAN}B < ${B_STD}B; -$(( B_FULL - B_LEAN ))B contra o full)" \
  || chk no "lean é menor que standard" "lean=${B_LEAN}B std=${B_STD}B"

# =============================================================================
echo "-- 4. nada some em silêncio: o cabeçalho declara o tier e o que ficou fora"
# =============================================================================
# tier_line <arquivo> → a linha do preâmbulo (vazia se não houver)
tier_line() { grep -m1 '^preâmbulo: ' "$1" 2>/dev/null || printf ''; }

L=$(tier_line "$SANDBOX/out.standard")
[[ "$L" == *"standard"* ]] \
  && chk yes "standard: linha do tier presente" || chk no "standard: linha do tier presente" "'$L'"
[[ "$L" == *"rotas"* ]] \
  && chk yes "standard: a linha nomeia as rotas como omitidas" || chk no "standard: a linha nomeia as rotas" "'$L'"
[[ "$L" == *"config/routing-table.yaml"* ]] \
  && chk yes "standard: a linha aponta onde está o texto íntegro" \
  || chk no "standard: a linha aponta onde está o texto íntegro" "'$L'"

L=$(tier_line "$SANDBOX/out.lean")
[[ "$L" == *"lean"* ]] \
  && chk yes "lean: linha do tier presente" || chk no "lean: linha do tier presente" "'$L'"
[[ "$L" == *"rotas"* && "$L" == *"heurísticas"* && "$L" == *"roster"* ]] \
  && chk yes "lean: a linha nomeia as TRÊS seções omitidas" || chk no "lean: a linha nomeia as três seções" "'$L'"
[[ "$L" == *"config/routing-table.yaml"* && "$L" == *"agents/"* ]] \
  && chk yes "lean: a linha aponta routing-table.yaml E agents/" \
  || chk no "lean: a linha aponta routing-table.yaml E agents/" "'$L'"

# a linha mora no CABEÇALHO (que nunca trunca), antes da instrução canônica
n_tier=$(grep -n '^preâmbulo: ' "$SANDBOX/out.lean" | head -1 | cut -d: -f1)
n_instr=$(grep -n '^INSTRUÇÃO CANÔNICA' "$SANDBOX/out.lean" | head -1 | cut -d: -f1)
[[ -n "$n_tier" && -n "$n_instr" && $n_tier -lt $n_instr ]] \
  && chk yes "a linha do tier fica no cabeçalho (antes da instrução canônica)" \
  || chk no "a linha do tier fica no cabeçalho" "tier=$n_tier instr=$n_instr"

# =============================================================================
echo "-- 5. valor inválido: degrada para full E diz que o .maestro.yaml está errado"
# =============================================================================
run invalido 'preamble: turbo'
nucleo "valor inválido"
[[ "$OUT" == *"$HDR_ROUTES"* && "$OUT" == *"$HDR_HEUR"* && "$OUT" == *"$HDR_ROSTER"* ]] \
  && chk yes "inválido: as três seções continuam (comporta-se como full)" \
  || chk no "inválido: as três seções continuam"
L=$(tier_line "$SANDBOX/out.invalido")
[[ "$L" == *"inválido"* && "$L" == *".maestro.yaml"* ]] \
  && chk yes "inválido: a linha acusa o valor inválido no .maestro.yaml" \
  || chk no "inválido: a linha acusa o valor inválido" "'$L'"
[[ "$L" == *"full | standard | lean"* ]] \
  && chk yes "inválido: a linha ensina os valores aceitos" || chk no "inválido: a linha ensina os valores aceitos" "'$L'"
# tirada a linha do aviso, o resto é exatamente o full
grep -v '^preâmbulo: ' "$SANDBOX/out.invalido" >"$SANDBOX/out.invalido.sem-linha"
grep -v '^preâmbulo: ' "$SANDBOX/out.full"     >"$SANDBOX/out.full.sem-linha"
cmp -s "$SANDBOX/out.invalido.sem-linha" "$SANDBOX/out.full.sem-linha" \
  && chk yes "inválido: fora a linha de aviso, a injeção é a do full" \
  || chk no "inválido: fora a linha de aviso, a injeção é a do full"

# Valor hostil: a linha só ecoa de volta o que é seguro ecoar. (O grep é na LINHA
# do tier, não na injeção inteira: "typescript-pro" no roster casaria com "script"
# e o teste viraria alarme falso.)
run hostil 'preamble: "<script>;id"'
[[ $RC -eq 0 ]] && chk yes "valor hostil: exit 0" || chk no "valor hostil: exit 0" "rc=$RC"
L=$(tier_line "$SANDBOX/out.hostil")
[[ "$L" != *"script"* && "$L" != *";id"* && "$L" != *"<"* ]] \
  && chk yes "valor hostil não é ecoado de volta na linha do tier" \
  || chk no "valor hostil não é ecoado de volta na linha do tier" "'$L'"
[[ "$L" == *"inválido"* && "$L" == *"'?'"* ]] \
  && chk yes "valor hostil ainda assim é reportado como inválido (com '?' no lugar)" \
  || chk no "valor hostil ainda assim é reportado como inválido" "'$L'"
[[ "$OUT" == *"$HDR_ROUTES"* && "$OUT" == *"$HDR_ROSTER"* ]] \
  && chk yes "valor hostil degrada para full, não para injeção mutilada" \
  || chk no "valor hostil degrada para full, não para injeção mutilada"

# =============================================================================
echo "-- 6. o tier convive com o resto do profile e degrada sem drama"
# =============================================================================
run combo 'version: 1
project: projeto-enxuto
languages: [go]
preamble: lean'
nucleo "lean + profile"
[[ "$OUT" == *"projeto: projeto-enxuto"* ]] \
  && chk yes "lean não engole o profile do projeto" || chk no "lean não engole o profile do projeto"
[[ "$OUT" != *"$HDR_ROSTER"* ]] \
  && chk yes "lean com profile continua sem roster" || chk no "lean com profile continua sem roster"

CORROMPIDO="$SANDBOX/corrompido"
mkdir -p "$CORROMPIDO"
printf 'preamble: \x00[[[ lean\n\t- - -\n' >"$CORROMPIDO/.maestro.yaml"
env MAESTRO_HOME="$(mktemp -d "$SANDBOX/home.XXXXXX")" CLAUDE_PROJECT_DIR="$CORROMPIDO" \
  bash "$HOOK" <"$IN" >"$SANDBOX/out.corrompido" 2>/dev/null
rc=$?
OUT=$(cat "$SANDBOX/out.corrompido"); RC=$rc
nucleo ".maestro.yaml corrompido"

# =============================================================================
echo "-- 7. kill-switch acima de tudo"
# =============================================================================
P=$(mktemp -d "$SANDBOX/proj.XXXXXX"); printf 'preamble: lean\n' >"$P/.maestro.yaml"
out=$(env MAESTRO_HOME="$(mktemp -d "$SANDBOX/home.XXXXXX")" CLAUDE_PROJECT_DIR="$P" \
       MAESTRO_OFF=1 bash "$HOOK" <"$IN" 2>&1); rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && chk yes "MAESTRO_OFF=1 não emite nada, com tier declarado" \
  || chk no "MAESTRO_OFF=1 não emite nada, com tier declarado" "rc=$rc out='$out'"

# =============================================================================
printf -- '-- conta: full=%sB standard=%sB lean=%sB\n' "$B_FULL" "$B_STD" "$B_LEAN"
[[ $fail -eq 0 ]] && echo "test-preamble-tier: OK" || echo "test-preamble-tier: FALHAS" >&2
exit $fail
