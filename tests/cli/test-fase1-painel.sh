#!/usr/bin/env bash
# Fase 1 — tools/fase1-painel.sh: painel dos 7 dias, somente leitura, fonte ausente = FALHA (exit 3).
# Fixtures: ledger jsonl e um banco sqlite da Ponte mínimo (decision + decision_resolution), nunca o real.
#   1. janela com 4 sessões de código (3 espontâneas) e 4 com decisão (2 subagent/multi) → 75% e 50%;
#   2. os critérios saem PASS/FAIL/INSUFICIENTE conforme o mínimo de 10 sessões;
#   3. prompts/allow/deny da Ponte contados na janela e fora dela (baseline);
#   4. sem o banco da Ponte → exit 3 e a seção marcada FALHA; sem --inicio → exit 2;
#   5. início no futuro → AGUARDANDO INÍCIO; o painel não escreve nada no ledger nem no banco.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PAINEL="$REPO/tools/fase1-painel.sh"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v sqlite3 >/dev/null && command -v jq >/dev/null || { echo "ok   (sem sqlite3 ou jq: teste pulado)"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export MAESTRO_HOME="$TMP/home"; mkdir -p "$MAESTRO_HOME/logs"
LEDGER="$MAESTRO_HOME/logs/routing.jsonl"
export PONTE_DB="$TMP/ponte.db"
export FASE1_REPOS="$TMP/sem-repo"

# início fixo: 2026-10-10 00:00 -03:00; janela de 7 dias; baseline = 14 dias antes
INI="2026-10-10T00:00:00-03:00"
ev() { printf '{"ts":"%s","event":"%s","session_id":"%s"%s}\n' "$1" "$2" "$3" "$4" >> "$LEDGER"; }
D1="2026-10-11T10:00:00-03:00"; D2="2026-10-11T10:05:00-03:00"

# s1 espontânea (decisão antes do gate) · modo subagent
ev "$D1" decision s1 ',"mode":"subagent"'; ev "$D2" gate_pass s1 ',"tool":"Edit"'
# s2 espontânea · direct
ev "$D1" decision s2 ',"mode":"direct"'; ev "$D2" gate_pass s2 ',"tool":"Write"'
# s3 espontânea · multi
ev "$D1" decision s3 ',"mode":"multi"'; ev "$D2" gate_pass s3 ',"tool":"Edit"'
# s4 NÃO espontânea: gate sem decisão primeiro, decisão depois · direct
ev "$D1" gate_warn s4 ',"tool":"Write","gate_mode":"warn"'; ev "$D2" decision s4 ',"mode":"direct"'
# s5 só self_path_write (tem cmd): não conta como sessão com código
ev "$D1" gate_warn s5 ',"tool":"Edit","cmd":"frozen_zone"'
# fora da janela (baseline): uma sessão com decisão em subagent
ev "2026-10-02T09:00:00-03:00" decision b1 ',"mode":"subagent"'; ev "2026-10-02T09:01:00-03:00" gate_pass b1 ',"tool":"Edit"'

sqlite3 "$PONTE_DB" "create table decision(id text, kind text, project text, created_at text);
create table decision_resolution(id text, decision_id text, choice text);
insert into decision values('d1','permission','p','2026-10-11T12:00:00.000Z'),('d2','permission','p','2026-10-11T12:01:00.000Z'),
  ('d3','permission','p','2026-10-11T12:02:00.000Z'),('d4','permission','p','2026-10-02T12:00:00.000Z'),('d5','question','p','2026-10-11T12:03:00.000Z');
insert into decision_resolution values('r1','d1','allow'),('r2','d2','allow'),('r3','d3','deny'),('r4','d4','allow');"

run() { bash "$PAINEL" --inicio "$INI" --dias 7 "$@" 2>"$TMP/err"; }

echo "-- 1: A/B do gate na janela"
OUT=$(run); RC=$?
check "painel sai 0 com as fontes presentes" "$RC" "0"
grep -qE '^\| janela \| 4 \| 3 \| 75 \| 4 \| 2 \| 50 \|' <<<"$OUT" \
  && ok "janela: 4 sessões com código, 3 espontâneas (75%), 4 com decisão, 2 subagent/multi (50%)" || bad "linha da janela do A/B não bate: $(grep '^| janela' <<<"$OUT" | tail -1)"
grep -qE '^\| baseline \| 1 \| 1 \| 100 \| 1 \| 1 \| 100 \|' <<<"$OUT" \
  && ok "baseline: 1 sessão, 100% e 100%" || bad "linha do baseline do A/B não bate: $(grep '^| baseline' <<<"$OUT" | tail -1)"

echo "-- 2: critérios respeitam o mínimo de 10 sessões"
grep -q 'decisões espontâneas ≥ 50%: \*\*INSUFICIENTE\*\*' <<<"$OUT" \
  && ok "4 sessões < 10: INSUFICIENTE, não PASS" || bad "critério 3 devia ser INSUFICIENTE"
grep -q 'incidentes destrutivos = 0: \*\*PASS\*\*' <<<"$OUT" && ok "incidentes = 0: PASS" || bad "critério de incidentes devia ser PASS"

echo "-- 3: Ponte — prompts, allow e deny na janela e no baseline"
grep -qE '^\| janela \| 3 \| 2 \| 1 \|' <<<"$OUT" && ok "janela: 3 prompts (2 allow, 1 deny); a 'question' fica de fora" || bad "linha da Ponte (janela) não bate: $(grep '^| janela' <<<"$OUT" | head -1)"
grep -qE '^\| baseline \| 1 \| 1 \| 0 \|' <<<"$OUT" && ok "baseline: 1 prompt (allow)" || bad "linha da Ponte (baseline) não bate"

echo "-- 4: fonte ausente é FALHA com exit 3; sem --inicio é uso inválido"
PONTE_DB="$TMP/nao-existe.db" bash "$PAINEL" --inicio "$INI" >"$TMP/out4" 2>"$TMP/err4"; RC=$?
check "sem o banco da Ponte: exit 3" "$RC" "3"
grep -q 'FALHA' "$TMP/err4" && ok "FALHA nomeada em stderr" || bad "stderr sem FALHA"
grep -q '\*\*FALHA:\*\*' "$TMP/out4" && ok "a seção da Ponte sai marcada FALHA no painel" || bad "painel sem a marca de FALHA"
mkdir -p "$TMP/x/tools"; cp "$PAINEL" "$TMP/x/tools/fase1-painel.sh"
bash "$TMP/x/tools/fase1-painel.sh" >/dev/null 2>&1; check "sem --inicio e sem docs/fase1/INICIO: exit 2 (uso inválido)" "$?" "2"

echo "-- 5: início no futuro; o painel não escreve nada"
sum_antes=$(sha256sum "$LEDGER" "$PONTE_DB" | awk '{print $1}' | tr '\n' ' ')
OUTF=$(bash "$PAINEL" --inicio "2099-01-01T00:00:00-03:00" 2>/dev/null)
grep -q 'AGUARDANDO INÍCIO' <<<"$OUTF" && ok "início futuro: AGUARDANDO INÍCIO" || bad "início futuro não diz AGUARDANDO INÍCIO"
sum_depois=$(sha256sum "$LEDGER" "$PONTE_DB" | awk '{print $1}' | tr '\n' ' ')
check "ledger e banco byte a byte iguais depois (somente leitura)" "$sum_depois" "$sum_antes"

exit $fail
