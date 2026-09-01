#!/usr/bin/env bash
# E17 / S-1702 — conduct: mutação genérica do decision record (regência).
# item 4 do design: flags[] tipadas (sev|decisao|tradeoff|mitigacao) + fecha o
# "approach: pendente" do brief. Records sintéticos direto via jq — não
# depende do lado `decide` (TS) em paralelo, só do formato do record (DATA_MODEL §3).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
mkdir -p "$MAESTRO_HOME/sessions" "$MAESTRO_HOME/logs"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v jq >/dev/null || { echo "FAIL jq ausente"; exit 1; }

# fixture: record sintético válido (brief com os 3 marcadores, approach pendente)
mk_record() { # mk_record <sid> [json extra p/ merge, default '{}']
  local sid="$1" extra="${2-}" ts exp
  [[ -z "$extra" ]] && extra='{}'
  ts="$(date -Iseconds)"
  exp="$(date -Iseconds -d '+4 hours' 2>/dev/null)" || exp="$ts"
  jq -n --arg sid "$sid" --arg ts "$ts" --arg exp "$exp" \
    --arg brief "essencia: teste impacto: teste approach: pendente" \
    --argjson extra "$extra" \
    '{session_id:$sid, ts:$ts, expires_at:$exp, workflow:"fix", mode:"direct", brief:$brief} + $extra' \
    > "$MAESTRO_HOME/sessions/$sid.json"
}

REC() { printf '%s/sessions/%s.json' "$MAESTRO_HOME" "$1"; }
LOG="$MAESTRO_HOME/logs/routing.jsonl"

echo "-- --flag válida acumula em .flags"
mk_record cnd-1
"$BIN" conduct --session cnd-1 --flag "high|decisao um|tradeoff um|mitigacao um" >/dev/null; rc=$?
chk "conduct --flag → exit 0" "$rc" "0"
chk "flags[0].sev" "$(jq -r '.flags[0].sev' "$(REC cnd-1)")" "high"
chk "flags[0].decisao" "$(jq -r '.flags[0].decisao' "$(REC cnd-1)")" "decisao um"
chk "flags length == 1" "$(jq '.flags | length' "$(REC cnd-1)")" "1"

echo "-- segunda --flag acumula (não sobrescreve)"
"$BIN" conduct --session cnd-1 --flag "low|decisao dois|tradeoff dois|mitigacao dois" >/dev/null; rc=$?
chk "segunda --flag → exit 0" "$rc" "0"
chk "flags length == 2" "$(jq '.flags | length' "$(REC cnd-1)")" "2"
chk "flags[1].sev" "$(jq -r '.flags[1].sev' "$(REC cnd-1)")" "low"

echo "-- --approach troca o pendente"
"$BIN" conduct --session cnd-1 --approach "approach real definido" >/dev/null; rc=$?
chk "conduct --approach → exit 0" "$rc" "0"
BRIEF="$(jq -r '.brief' "$(REC cnd-1)")"
[[ "$BRIEF" == *"approach: approach real definido" ]] \
  && ok "brief.approach substituído" || bad "brief.approach substituído (brief='$BRIEF')"
[[ "$BRIEF" != *"pendente"* ]] && ok "pendente removido do brief" || bad "pendente removido do brief"
[[ "$BRIEF" == "essencia: teste impacto: teste"* ]] \
  && ok "essencia/impacto preservados" || bad "essencia/impacto preservados (brief='$BRIEF')"

echo "-- record sem brief não aceita --approach"
mk_record cnd-nobrief '{}'
jq 'del(.brief)' "$(REC cnd-nobrief)" > "$(REC cnd-nobrief).tmp" && mv -f "$(REC cnd-nobrief).tmp" "$(REC cnd-nobrief)"
"$BIN" conduct --session cnd-nobrief --approach "x" >/dev/null 2>&1; rc=$?
chk "sem brief + --approach → exit 1" "$rc" "1"

echo "-- negativos"
"$BIN" conduct --session sessao-inexistente --flag "high|d|t|m" >/dev/null 2>&1; rc=$?
chk "sem record → exit 1" "$rc" "1"

"$BIN" conduct --session cnd-1 --flag "urgentissimo|d|t|m" >/dev/null 2>&1; rc=$?
chk "sev fora do enum → exit 1" "$rc" "1"

LONGO=$(printf 'a%.0s' $(seq 1 121))
"$BIN" conduct --session cnd-1 --flag "high|$LONGO|t|m" >/dev/null 2>&1; rc=$?
chk "campo acima de 120 chars → exit 1" "$rc" "1"

"$BIN" conduct --session cnd-1 --flag "high|d|t" >/dev/null 2>&1; rc=$?
chk "--flag com 3 campos → exit 1" "$rc" "1"

"$BIN" conduct --session cnd-1 >/dev/null 2>&1; rc=$?
chk "sem --flag e sem --approach → exit 1" "$rc" "1"

# nenhum dos negativos deve ter mutado o record além do já esperado (2 flags, approach fechado)
chk "record cnd-1 intacto após negativos (flags)" "$(jq '.flags | length' "$(REC cnd-1)")" "2"

echo "-- evento conduct no log"
grep -q '"event":"conduct".*"session_id":"cnd-1"' "$LOG" \
  && ok "evento conduct logado (session_id)" || bad "evento conduct logado"
grep -q '"event":"conduct".*"flags_n":"1".*"approach":"no"' "$LOG" \
  && ok "primeira chamada: flags_n=1, approach=no" || bad "flags_n/approach da 1a chamada"
grep -q '"event":"conduct".*"flags_n":"0".*"approach":"yes"' "$LOG" \
  && ok "chamada de approach: flags_n=0, approach=yes" || bad "flags_n/approach da chamada de approach"

echo "-- doctor: WARN (nunca FAIL) em outcome + approach pendente"
mk_record cnd-pend '{"outcome":"accepted","outcome_ts":"2026-01-01T00:00:00-03:00"}'
out=$(MAESTRO_HOME="$MAESTRO_HOME" "$BIN" doctor --ci 2>&1); rc=$?
chk "doctor com record pendente → exit 0 (WARN não é FAIL)" "$rc" "0"
grep -q 'record cnd-pend: outcome registrado com approach pendente (rode maestro conduct --approach)' <<<"$out" \
  && ok "doctor avisa o record com approach pendente" || bad "doctor avisa approach pendente ($out)"
"$BIN" conduct --session cnd-pend --approach "fechado agora" >/dev/null
out=$(MAESTRO_HOME="$MAESTRO_HOME" "$BIN" doctor --ci 2>&1)
grep -q 'cnd-pend: outcome registrado com approach pendente' <<<"$out" \
  && bad "aviso deveria sumir após --approach" || ok "aviso some depois que conduct --approach fecha o pendente"
rm -f "$(REC cnd-pend)"

# ---------------------------------------------------------------------------
# S-1708 — flags[] é trilha de sessão: sobrevive a um re-decide posterior na
# MESMA sessão, mesmo que o novo decide mude workflow/mode (o record é
# idempotente por sessão — write+rename reescreve do zero em src/cli.ts).
# ---------------------------------------------------------------------------
command -v bun >/dev/null || { echo "FAIL bun ausente (necessário p/ decide, S-1708)"; exit 1; }

echo "-- S-1708: flags[] sobrevivem ao re-decide da mesma sessão"
# workflow fix tem gate:none — não exige --brief.
"$BIN" decide --session s1708-a --workflow fix --mode direct >/dev/null; rc=$?
chk "decide inicial (sem flags) → exit 0" "$rc" "0"
chk "record recém-decidido não tem flags" "$(jq -r 'has("flags")' "$(REC s1708-a)")" "false"

# injeta flags no record, no mesmo shape que `maestro conduct --flag` gravaria
jq '.flags = [{"sev":"high","decisao":"x","tradeoff":"y","mitigacao":"z"}]' \
  "$(REC s1708-a)" > "$(REC s1708-a).tmp" && mv -f "$(REC s1708-a).tmp" "$(REC s1708-a)"
chk "fixture: flags injetadas" "$(jq '.flags | length' "$(REC s1708-a)")" "1"

# re-decide na MESMA sessão, mudando workflow/mode — a trilha é da sessão, não do workflow
"$BIN" decide --session s1708-a --workflow audit --mode direct >/dev/null; rc=$?
chk "re-decide (workflow/mode mudam) → exit 0" "$rc" "0"
chk "workflow atualizado pelo re-decide" "$(jq -r .workflow "$(REC s1708-a)")" "audit"
chk "flags sobrevivem ao re-decide" "$(jq '.flags | length' "$(REC s1708-a)")" "1"
chk "conteúdo da flag intacto (decisao)" "$(jq -r '.flags[0].decisao' "$(REC s1708-a)")" "x"
chk "conteúdo da flag intacto (sev)" "$(jq -r '.flags[0].sev' "$(REC s1708-a)")" "high"

echo "-- S-1708: sessão sem flags prévias não ganha o campo no re-decide"
"$BIN" decide --session s1708-b --workflow fix --mode direct >/dev/null; rc=$?
chk "decide sem flags prévias → exit 0" "$rc" "0"
"$BIN" decide --session s1708-b --workflow audit --mode direct >/dev/null; rc=$?
chk "re-decide sem flags prévias → exit 0" "$rc" "0"
chk "record sem flags prévias não ganha o campo" \
    "$(jq -r 'has("flags")' "$(REC s1708-b)")" "false"

exit $fail
