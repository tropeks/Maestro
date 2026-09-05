#!/usr/bin/env bash
# E22/S-2201 — `maestro intent`: a direção do projeto como ARTEFATO versionado.
# Invariantes: seis seções obrigatórias (título sem texto = ausente); a versão
# só sobe com CONTEÚDO mudado (não é contador de saves); o hash é do corpo sem
# o carimbo; o bump troca o carimbo e não toca uma vírgula do texto; o log leva
# número e via, jamais título, hash ou caminho.
# Hermético: MAESTRO_HOME e projeto em mktemp -d.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q
echo a > "$P/a.txt"; git -C "$P" add -A
git -C "$P" -c user.email=t@t -c user.name=t commit -qm base
IF="$P/.maestro/INTENT.md"

# preenche <seção> <texto> — escreve uma linha de texto logo abaixo do título
preenche() {
  local sec="$1" txt="$2" f="$IF"
  awk -v sec="## $sec" -v txt="$txt" '
    { print }
    $0 == sec { print txt }
  ' "$f" > "$f.new" && mv -f "$f.new" "$f"
}

echo "-- sem direção: mostrar é fato, não erro; conferir é erro"
OUT=$("$BIN" intent --project "$P"); rc=$?
chk "sem arquivo, --show sai 0" "$rc" "0"
grep -q 'sem direção' <<<"$OUT" && ok "sem arquivo, --show ensina o --init" || bad "sem arquivo, --show ensina o --init"
"$BIN" intent --check --project "$P" >/dev/null 2>&1; rc=$?
chk "sem arquivo, --check sai 1" "$rc" "1"

echo "-- --init: template com as seis seções VAZIAS"
"$BIN" intent --init --project "$P" --session dir-1 >/dev/null
[[ -f "$IF" ]] && ok "INTENT.md em .maestro/ (viaja com o repo)" || bad "arquivo da direção"
grep -q '^<!-- maestro-intent v1$' "$IF" && ok "carimbo v1" || bad "carimbo v1"
chk "nasce em v1" "$(awk -F': ' '/^version: /{print $2; exit}' "$IF")" "1"
grep -q '^hash: [0-9a-f]\{8\}$' "$IF" && ok "carimbo guarda o hash do corpo (8 hex)" || bad "hash no carimbo"
n=0
for sec in Problema Público Resultado Prioridades Limites "Fora de escopo"; do
  grep -qx "## $sec" "$IF" && n=$((n + 1))
done
chk "as seis seções obrigatórias no template" "$n" "6"
"$BIN" intent --check --project "$P" >/dev/null 2>&1; rc=$?
chk "template recém-criado NÃO passa no --check (título não é direção)" "$rc" "1"
"$BIN" intent --check --project "$P" 2>&1 | grep -q 'falta Problema · Público · Resultado · Prioridades · Limites · Fora de escopo' \
  && ok "o --check lista TODAS as seções que faltam" || bad "o --check lista o que falta"
"$BIN" intent --init --project "$P" >/dev/null 2>&1; rc=$?
chk "--init sobre direção existente recusa (exit 1)" "$rc" "1"

echo "-- versão é conteúdo, não save"
"$BIN" intent --bump --project "$P" >/dev/null 2>&1; rc=$?
chk "--bump sem mudança recusa (exit 1)" "$rc" "1"
"$BIN" intent --bump --project "$P" 2>&1 | grep -q 'não um contador de saves' \
  && ok "a recusa do bump explica POR QUE (a versão é o que as ordens citam)" || bad "recusa do bump sem motivo"
chk "recusa não mexeu na versão" "$(awk -F': ' '/^version: /{print $2; exit}' "$IF")" "1"

echo "-- seção parcial continua incompleta; espaço em branco não é texto"
preenche Problema "o roteador não sabe para onde o projeto vai."
preenche Público "o Capitão e as sessões do Claude Code."
"$BIN" intent --check --project "$P" >/dev/null 2>&1; rc=$?
chk "2 de 6 seções → --check ainda sai 1" "$rc" "1"
"$BIN" intent --check --project "$P" 2>&1 | grep -q 'falta Resultado · Prioridades · Limites · Fora de escopo' \
  && ok "o --check lista só o que ainda falta" || bad "lista do que falta encolhe conforme preenche"
preenche Resultado "   "
"$BIN" intent --check --project "$P" 2>&1 | grep -q 'falta Resultado' \
  && ok "seção só com espaços conta como VAZIA" || bad "espaço em branco virou conteúdo"
preenche Resultado "ordem nasce citando a direção."
preenche Prioridades "- trilho determinístico antes de esperteza."
preenche Limites "- bash puro nos hooks."
preenche "Fora de escopo" "- virar orquestrador."
OUT=$("$BIN" intent --check --project "$P"); rc=$?
chk "seis seções preenchidas → --check sai 0" "$rc" "0"
grep -q 'direção OK: INTENT v1, 6/6 seções, hash [0-9a-f]\{8\}$' <<<"$OUT" \
  && ok "o veredito cita versão, seções e hash" || bad "veredito do --check ($OUT)"

echo "-- o hash é do CORPO, sem o carimbo (carimbar não é mudar)"
H_CLI=$("$BIN" intent --project "$P" | sed -n 's/^direção: INTENT v[0-9]* · hash \([0-9a-f]*\).*/\1/p')
H_REF=$(sed '1,/^-->$/d' "$IF" | sha256sum | head -c 8)
chk "hash do CLI == 8 hex do sha256 do corpo sem carimbo" "$H_CLI" "$H_REF"
"$BIN" intent --project "$P" | grep -q 'conteúdo editado desde o carimbo v1 → maestro intent --bump' \
  && ok "conteúdo editado sem bump é DENUNCIADO na leitura" || bad "edição sem bump passa em silêncio"

echo "-- --bump: sobe a versão e não toca no texto"
BODY_ANTES=$(sed '1,/^-->$/d' "$IF" | sha256sum)
OUT=$("$BIN" intent --bump --project "$P" --session dir-2); rc=$?
chk "--bump com conteúdo mudado sai 0" "$rc" "0"
chk "versão vai a 2" "$(awk -F': ' '/^version: /{print $2; exit}' "$IF")" "2"
chk "o corpo sai byte-idêntico do bump" "$(sed '1,/^-->$/d' "$IF" | sha256sum)" "$BODY_ANTES"
chk "o carimbo passa a guardar o hash do conteúdo de agora" \
    "$(awk -F': ' '/^hash: /{print $2; exit}' "$IF")" "$H_REF"
chk "o carimbo registra a sessão que versionou" \
    "$(awk -F': ' '/^author_session: /{print $2; exit}' "$IF")" "dir-2"
chk "o carimbo registra o HEAD" \
    "$(awk -F': ' '/^head: /{print $2; exit}' "$IF")" "$(git -C "$P" rev-parse HEAD)"
grep -q 'v1 → v2' <<<"$OUT" && ok "o bump diz de onde para onde" || bad "bump silencioso"
"$BIN" intent --project "$P" | grep -q 'conteúdo editado desde o carimbo' \
  && bad "depois do bump ainda acusa edição pendente" || ok "depois do bump o carimbo e o conteúdo concordam"
"$BIN" intent --bump --project "$P" >/dev/null 2>&1; rc=$?
chk "segundo --bump seguido recusa de novo (exit 1)" "$rc" "1"

echo "-- --show: versão, hash, carimbo e o estado de cada seção"
OUT=$("$BIN" intent --show --project "$P")
grep -q '^direção: INTENT v2 · hash ' <<<"$OUT" && ok "--show abre com versão e hash" || bad "cabeçalho do --show"
grep -q '^  carimbo : ts .* · head .* · sessão dir-2$' <<<"$OUT" && ok "--show mostra o carimbo" || bad "carimbo no --show"
chk "--show conta as seis seções" "$(grep -c 'linha(s)$' <<<"$OUT")" "6"

echo "-- a ordem das seções no arquivo é livre; o que exige é a presença"
P2="$tmp/proj2"; mkdir -p "$P2/.maestro"
cat > "$P2/.maestro/INTENT.md" <<'INTENT'
<!-- maestro-intent v1
version: 7
ts: 2026-09-05T10:00:00-03:00
head: none
author_session: desconhecido
hash: 00000000
-->
# Direção — invertido

## Fora de escopo
- virar orquestrador.

## Limites
- bash puro.

## Prioridades
- trilho.

## Resultado
- ordem citada.

## Público
- o Capitão.

## Problema
- sem norte.
INTENT
"$BIN" intent --check --project "$P2" >/dev/null 2>&1; rc=$?
chk "seções fora de ordem passam no --check" "$rc" "0"
chk "versão arbitrária ≥1 é respeitada (não recontada)" \
    "$("$BIN" intent --show --project "$P2" | sed -n 's/^direção: INTENT v\([0-9]*\).*/\1/p')" "7"

echo "-- carimbo ilegível: acusa, e mesmo assim não quebra a leitura"
P3="$tmp/proj3"; mkdir -p "$P3/.maestro"
sed 's/^version: 7$/version: sete/' "$P2/.maestro/INTENT.md" > "$P3/.maestro/INTENT.md"
"$BIN" intent --check --project "$P3" >/dev/null 2>&1; rc=$?
chk "carimbo ilegível → --check sai 1" "$rc" "1"
OUT=$("$BIN" intent --show --project "$P3"); rc=$?
chk "carimbo ilegível → --show sai 0 (degrada, não quebra)" "$rc" "0"
grep -q 'sem carimbo legível' <<<"$OUT" && ok "--show nomeia o defeito do carimbo" || bad "defeito do carimbo nomeado"

echo "-- log: número e via, nunca título/hash/caminho"
LOG="$MAESTRO_HOME/logs/routing.jsonl"
chk "um evento intent por mutação (init + 1 bump)" "$(grep -c '"event":"intent"' "$LOG")" "2"
grep -q '"event":"intent","session_id":"dir-2","n":"2","via":"manual"' "$LOG" \
  && ok "o evento leva n=<versão> e via=manual" || bad "chaves do evento intent ($(grep '"event":"intent"' "$LOG" | tail -1))"
grep -q "$H_REF" "$LOG" && bad "o hash da direção vazou para o log" || ok "hash NÃO vai para o log"
grep -qi 'INTENT.md\|Direção —\|/proj' "$LOG" && bad "caminho ou título vazou para o log" || ok "caminho e título NÃO vão para o log"
"$BIN" intent --check --project "$P" >/dev/null 2>&1 || :
"$BIN" intent --show --project "$P" >/dev/null
chk "leitura não loga (só mutação registra)" "$(grep -c '"event":"intent"' "$LOG")" "2"

echo "-- validações e higiene"
"$BIN" intent --xpto --project "$P" >/dev/null 2>&1; rc=$?
chk "flag desconhecida → exit 1" "$rc" "1"
n=$(find "$P/.maestro" -name '*.tmp.*' -o -name '.INTENT.body.*' | wc -l | tr -d ' ')
chk "escrita atômica não deixa temporário para trás" "$n" "0"

exit $fail
