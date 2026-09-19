#!/usr/bin/env bash
# ordem 024 fatia 1 — swarm como modo: H6 ganha o eixo RECURSO ao lado do eixo
# ARQUIVO que já tinha. Causa medida (não hipótese): seis frentes despachadas
# juntas mediram load 17,4 em 8 CPUs, suíte 8m41s→9m52s, uma ordem presa 47min
# em fila e recibos consecutivos "fora do limiar de medição" — duas frentes
# podiam não tocar o mesmo arquivo e ainda assim se destruírem na CPU.
#
# Cobre, nesta ordem:
#   1. eixo ARQUIVO — `--fronts`: sobreposição entre frentes é RECUSADA
#      (decide-time, exit 1, mensagem que ensina o critério); frentes
#      disjuntas são aceitas e gravadas no record (DATA_MODEL §3 v1.21).
#   2. eixo RECURSO — `--measures`: outra sessão VIVA faz avisar (nunca
#      recusar — Prioridades §1); outra sessão EXPIRADA não avisa; guarda
#      degrada em silêncio sem `~/.maestro/sessions/`.
#   3. schema aditivo — record ANTIGO (sem fronts/measures) continua válido;
#      fronts/measures mal-formados são recusados pelo doctor.
#   4. `maestro evidence --record` avisa da carga ANTES de medir, nos dois
#      regimes (fora do limiar / dentro do limiar) — reaproveitando a MESMA
#      sonda (load1m_x100/ncpu) da issue #11/ordem 005, nenhuma sonda nova.
#   5. coluna model — H8 (config/routing-table.yaml) chega na injeção do
#      SessionStart, dentro do ratchet (tests/hooks/test-injection-budget.sh).
#
# Hermético: MAESTRO_HOME em mktemp, como os outros testes de ordem.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
HOOK="$REPO/hooks/session-start.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v jq  >/dev/null || { echo "FAIL jq ausente (dependência declarada)"; exit 1; }
command -v bun >/dev/null || { echo "FAIL bun ausente (maestro decide exige Bun)"; exit 1; }

H1=$(mktemp -d "$SANDBOX/h1.XXXXXX")
mkdir -p "$H1/sessions" "$H1/logs"

decide() { # decide <home> <args...> → OUT/RC (stdout+stderr juntos)
  local home="$1"; shift
  OUT=$(MAESTRO_HOME="$home" "$BIN" decide "$@" 2>&1); RC=$?
}

# ---------------------------------------------------------------------------
echo "-- eixo ARQUIVO: sobreposição entre frentes é recusada"
# ---------------------------------------------------------------------------
decide "$H1" --session ov-1 --workflow custom --mode multi --agents dev-pleno,qa \
  --fronts "a/ b/;a/sub/"
chk "sobreposição de prefixo (a/ contém a/sub/): exit 1" "$RC" "1"
grep -q "sobrepõe" <<<"$OUT" && ok "a mensagem nomeia a sobreposição" \
  || bad "a mensagem nomeia a sobreposição"
grep -q "DISJUNTOS" <<<"$OUT" && ok "a mensagem ENSINA o critério (caminhos disjuntos)" \
  || bad "a mensagem ensina o critério"
[[ ! -f "$H1/sessions/ov-1.json" ]] && ok "recusa não grava record" \
  || bad "recusa não grava record"

decide "$H1" --session ov-2 --workflow custom --mode multi --agents dev-pleno,qa \
  --fronts "b/;b/"
chk "sobreposição exata (mesma frente duas vezes): exit 1" "$RC" "1"

decide "$H1" --session ov-3 --workflow custom --mode subagent --agents dev-pleno \
  --fronts "a/;b/"
chk "--fronts fora de mode=multi: exit 1" "$RC" "1"
grep -q "mode multi" <<<"$OUT" && ok "a mensagem cita a exigência de mode multi" \
  || bad "a mensagem cita mode multi"

decide "$H1" --session ov-4 --workflow custom --mode multi --agents dev-pleno,qa \
  --fronts "a/"
chk "uma frente só (sem ';'): exit 1" "$RC" "1"

# ---------------------------------------------------------------------------
echo "-- eixo ARQUIVO: frentes disjuntas são aceitas"
# ---------------------------------------------------------------------------
decide "$H1" --session ok-1 --workflow custom --mode multi --agents dev-pleno,qa \
  --fronts "a/ b/;c/"
chk "frentes disjuntas: exit 0" "$RC" "0"
chk "fronts gravado (2 frentes)" "$(jq '.fronts | length' "$H1/sessions/ok-1.json")" "2"
chk "frente 1 tem 2 caminhos" "$(jq '.fronts[0] | length' "$H1/sessions/ok-1.json")" "2"
chk "frente 2 = [\"c/\"]" "$(jq -c '.fronts[1]' "$H1/sessions/ok-1.json")" '["c/"]'

decide "$H1" --session ok-2 --workflow custom --mode multi --agents dev-pleno,qa \
  --fronts "a/x/y;a/z"
chk "prefixos irmãos SEM sobreposição (a/x/y vs a/z): exit 0" "$RC" "0"

# ---------------------------------------------------------------------------
echo "-- eixo RECURSO: --measures avisa com outra sessão VIVA, nunca recusa"
# ---------------------------------------------------------------------------
HM=$(mktemp -d "$SANDBOX/hm.XXXXXX")   # home PRÓPRIO — nada de fronts/ok-*/ov-* alheios
mkdir -p "$HM/sessions"
decide "$HM" --session live-1 --workflow custom --mode direct --measures
chk "primeira sessão medidora (sem outra viva): exit 0" "$RC" "0"
grep -q "aviso" <<<"$OUT" && bad "sem outra sessão: NÃO deveria avisar" \
  || ok "sem outra sessão: silêncio (nada para avisar)"

decide "$HM" --session live-2 --workflow custom --mode direct --measures
chk "segunda sessão medidora (live-1 ainda viva): exit 0 — aviso, NUNCA bloqueio" "$RC" "0"
grep -q -- "--measures" <<<"$OUT" && grep -q "aviso" <<<"$OUT" \
  && ok "avisa: outra sessão viva e não expirada" \
  || bad "avisa: outra sessão viva e não expirada"
[[ -f "$HM/sessions/live-2.json" ]] && ok "o record foi gravado apesar do aviso" \
  || bad "o record foi gravado apesar do aviso"

echo "-- eixo RECURSO: --measures NÃO avisa quando a outra sessão está EXPIRADA"
H2=$(mktemp -d "$SANDBOX/h2.XXXXXX")
mkdir -p "$H2/sessions"
jq -n '{session_id:"expired-1", ts:"2020-01-01T00:00:00-03:00",
        expires_at:"2020-01-01T04:00:00-03:00", workflow:"fix", mode:"direct"}' \
  > "$H2/sessions/expired-1.json"
decide "$H2" --session live-3 --workflow custom --mode direct --measures
chk "só sessão expirada ao redor: exit 0" "$RC" "0"
grep -q "aviso" <<<"$OUT" && bad "sessão expirada NÃO deveria disparar o aviso" \
  || ok "sessão expirada: sem aviso (só sessão VIVA conta)"

echo "-- eixo RECURSO: sem ~/.maestro/sessions/, a guarda cala e o decide segue"
H3=$(mktemp -d "$SANDBOX/h3.XXXXXX")   # nem MAESTRO_HOME existe ainda
decide "$H3/nao-existe" --session first-1 --workflow custom --mode direct --measures
chk "MAESTRO_HOME/sessions ausente: decide sai 0 mesmo assim" "$RC" "0"
grep -q "aviso" <<<"$OUT" && bad "diretório ausente NÃO deveria produzir aviso" \
  || ok "diretório ausente: guarda muda, decide sai 0"

echo "-- eixo RECURSO: sessão JSON corrompida não derruba a guarda"
H4=$(mktemp -d "$SANDBOX/h4.XXXXXX")
mkdir -p "$H4/sessions"
printf 'isto não é json {{{' > "$H4/sessions/lixo.json"
decide "$H4" --session first-2 --workflow custom --mode direct --measures
chk "JSON corrompido ao lado: decide sai 0 mesmo assim" "$RC" "0"

# ---------------------------------------------------------------------------
echo "-- schema aditivo: record ANTIGO (sem fronts/measures) continua válido"
# ---------------------------------------------------------------------------
H5=$(mktemp -d "$SANDBOX/h5.XXXXXX")
mkdir -p "$H5/sessions"
exp="$(date -Iseconds -d '+4 hours' 2>/dev/null)" || exp="$(date -Iseconds)"
jq -n --arg exp "$exp" '{session_id:"legacy-1", ts:"2026-01-01T00:00:00-03:00",
  expires_at:$exp, workflow:"fix", mode:"subagent", agents:["dev-pleno"]}' \
  > "$H5/sessions/legacy-1.json"
doc_out=$(MAESTRO_HOME="$H5" "$BIN" doctor 2>&1)
grep -q "decision records: 1 válido" <<<"$doc_out" \
  && ok "record antigo (sem fronts/measures) segue válido no schema" \
  || bad "record antigo (sem fronts/measures) segue válido no schema: $(grep 'decision records' <<<"$doc_out")"

echo "-- schema aditivo: fronts/measures BEM-formados passam"
jq -n --arg exp "$exp" '{session_id:"new-1", ts:"2026-01-01T00:00:00-03:00",
  expires_at:$exp, workflow:"custom", mode:"multi", agents:["dev-pleno","qa"],
  fronts:[["a/","b/"],["c/"]], measures:true}' \
  > "$H5/sessions/new-1.json"
doc_out=$(MAESTRO_HOME="$H5" "$BIN" doctor 2>&1)
grep -q "decision records: 2 válido" <<<"$doc_out" \
  && ok "fronts/measures bem-formados: schema aceita" \
  || bad "fronts/measures bem-formados: schema aceita: $(grep 'decision records' <<<"$doc_out")"

echo "-- schema aditivo: fronts/measures MAL-formados são recusados"
H6=$(mktemp -d "$SANDBOX/h6.XXXXXX")
mkdir -p "$H6/sessions"
jq -n --arg exp "$exp" '{session_id:"bad-fronts", ts:"2026-01-01T00:00:00-03:00",
  expires_at:$exp, workflow:"fix", mode:"multi", agents:["dev-pleno","qa"],
  fronts:[["a/"]]}' \
  > "$H6/sessions/bad-fronts.json"   # só 1 frente — schema exige >= 2
doc_out=$(MAESTRO_HOME="$H6" "$BIN" doctor 2>&1)
grep -q "inválido" <<<"$doc_out" && grep -q "bad-fronts" <<<"$doc_out" \
  && ok "fronts com 1 frente só: doctor reprova nomeando o arquivo" \
  || bad "fronts com 1 frente só: doctor deveria reprovar: $(grep 'decision records' <<<"$doc_out")"

H7=$(mktemp -d "$SANDBOX/h7.XXXXXX")
mkdir -p "$H7/sessions"
jq -n --arg exp "$exp" '{session_id:"bad-measures", ts:"2026-01-01T00:00:00-03:00",
  expires_at:$exp, workflow:"fix", mode:"direct", measures:false}' \
  > "$H7/sessions/bad-measures.json"   # measures só pode ser `true`
doc_out=$(MAESTRO_HOME="$H7" "$BIN" doctor 2>&1)
grep -q "inválido" <<<"$doc_out" \
  && ok "measures:false é recusado (só existe measures:true)" \
  || bad "measures:false deveria ser recusado: $(grep 'decision records' <<<"$doc_out")"

# ---------------------------------------------------------------------------
echo "-- evidence --record: aviso de carga ANTES de medir, nos dois regimes"
# ---------------------------------------------------------------------------
H8=$(mktemp -d "$SANDBOX/h8.XXXXXX")
PROJ=$(mktemp -d "$SANDBOX/proj.XXXXXX")
git -C "$PROJ" init -q
git -C "$PROJ" -c user.email=t@t -c user.name=t commit --allow-empty -q -m init

out=$(MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100=0 MAESTRO_HOME="$H8" "$BIN" evidence \
  --record --project "$PROJ" -- true 2>&1)
grep -q "carga já fora do limiar de medição ANTES de medir" <<<"$out" \
  && ok "limiar 0 (qualquer carga real excede): avisa ANTES de medir" \
  || bad "limiar 0: deveria avisar antes de medir — saída: $out"
grep -q "evidência gravada" <<<"$out" \
  && ok "o aviso não impede o recibo de ser gravado" \
  || bad "o aviso não impede o recibo de ser gravado"

out=$(MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100=999999 MAESTRO_HOME="$H8" "$BIN" evidence \
  --record --project "$PROJ" -- true 2>&1)
grep -q "carga já fora do limiar" <<<"$out" \
  && bad "limiar 999999 (nenhuma carga real excede): NÃO deveria avisar" \
  || ok "limiar folgado: sem aviso"
grep -q "evidência gravada" <<<"$out" \
  && ok "recibo gravado normalmente sem o aviso" \
  || bad "recibo gravado normalmente sem o aviso"

# ---------------------------------------------------------------------------
echo "-- coluna model: H8 chega na injeção do SessionStart, dentro do ratchet"
# ---------------------------------------------------------------------------
H9=$(mktemp -d "$SANDBOX/h9.XXXXXX")
P9=$(mktemp -d "$SANDBOX/p9.XXXXXX")
inj=$(printf '{"session_id":"h8-test"}' \
  | MAESTRO_HOME="$H9" CLAUDE_PROJECT_DIR="$P9" MAESTRO_NO_UPDATE_CHECK=1 bash "$HOOK" 2>/dev/null)
grep -q '^- H8 modelo por PERFIL' <<<"$inj" \
  && ok "H8 (coluna model, ADR-004) chega na injeção" \
  || bad "H8 (coluna model) deveria chegar na injeção"
grep -q 'haiku' <<<"$inj" && grep -q 'sonnet' <<<"$inj" && grep -q 'opus' <<<"$inj" \
  && ok "H8 nomeia os três tiers (haiku/sonnet/opus)" \
  || bad "H8 deveria nomear os três tiers"
bytes=$(printf '%s' "$inj" | wc -c | tr -d ' ')
(( bytes <= 8000 )) && ok "injeção com H8: dentro do teto duro de 8000B (${bytes}B)" \
  || bad "injeção com H8: estourou o teto duro (${bytes}B)"

exit $fail
