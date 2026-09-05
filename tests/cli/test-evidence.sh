#!/usr/bin/env bash
# E13 / S-1301 + S-1302 — `maestro evidence`: recibo amarrado a conteúdo.
# Invariante: VÁLIDA só quando conteúdo byte-idêntico + comando igual + idade
# no teto + exit 0 + árvore parada durante a corrida. Tudo o mais nomeia o
# motivo. Hermético: MAESTRO_HOME/projeto em mktemp.
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

P="$tmp/proj"; mkdir -p "$P"; git -C "$P" init -q
echo base > "$P/f"; git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm x

echo "-- gravação e veredito feliz"
"$BIN" evidence --record --project "$P" -- true >/dev/null; rc=$?
chk "record de exit 0 → rc 0 (espelha o comando)" "$rc" "0"
EF=$(ls "$MAESTRO_HOME/evidence/" | head -1); [[ -n "$EF" ]] && ok "recibo gravado" || bad "recibo gravado"
head -1 "$MAESTRO_HOME/evidence/$EF" | grep -q 'maestro-evidence-v1' && ok "schema versionado" || bad "schema"
out=$("$BIN" evidence --project "$P")
grep -q 'VÁLIDA' <<<"$out" && ok "conteúdo idêntico + exit 0 → VÁLIDA" || bad "VÁLIDA ($out)"
"$BIN" evidence --check --project "$P" >/dev/null; chk "--check válida → 0" "$?" "0"

echo "-- cada modo de invalidação nomeia o motivo"
echo suja >> "$P/f"
out=$("$BIN" evidence --project "$P")
grep -q 'conteúdo mudou desde a prova' <<<"$out" && ok "conteúdo mudou → VENCIDA nomeando" || bad "conteúdo ($out)"
"$BIN" evidence --check --project "$P" >/dev/null; chk "--check vencida → 1" "$?" "1"
git -C "$P" checkout -q -- f
"$BIN" evidence --record --project "$P" -- false >/dev/null; rc=$?
chk "record de exit 1 → rc 1, mas GRAVA (falha é dado)" "$rc" "1"
out=$("$BIN" evidence --project "$P")
grep -q 'provou FALHA (exit 1)' <<<"$out" && ok "exit != 0 → VENCIDA por falha" || bad "falha ($out)"
"$BIN" evidence --record --project "$P" -- bash -c 'echo x >> f' >/dev/null
out=$("$BIN" evidence --project "$P")
grep -q 'árvore mudou durante a corrida' <<<"$out" && ok "comando que suja a árvore → contaminado" || bad "contaminado ($out)"
git -C "$P" checkout -q -- f
"$BIN" evidence --record --project "$P" -- true >/dev/null
out=$(MAESTRO_EVIDENCE_MAX_AGE=0 "$BIN" evidence --project "$P")
grep -q 'idade' <<<"$out" && ok "teto de idade estourado → VENCIDA" || bad "idade ($out)"

echo "-- rótulos separam provas"
"$BIN" evidence --record --label build --project "$P" -- true >/dev/null
n=$(ls "$MAESTRO_HOME/evidence/" | wc -l)
chk "suite e build são recibos distintos" "$n" "2"
out=$("$BIN" evidence --label build --project "$P")
grep -q 'VÁLIDA' <<<"$out" && ok "leitura por rótulo" || bad "leitura por rótulo"

echo "-- degradações e validação"
out=$("$BIN" evidence --label inexistente --project "$P"); rc=$?
chk "sem recibo → exit 0 informativo" "$rc" "0"
grep -q 'NENHUMA' <<<"$out" && ok "diz que não há e como registrar" || bad "NENHUMA ($out)"
"$BIN" evidence --record --project "$P" >/dev/null 2>&1; rc=$?
chk "record sem comando → exit 1" "$rc" "1"
"$BIN" evidence --label 'Ruim!' --project "$P" >/dev/null 2>&1; rc=$?
chk "rótulo inválido → exit 1" "$rc" "1"
printf 'lixo\n' > "$MAESTRO_HOME/evidence/$EF"
out=$("$BIN" evidence --project "$P")
grep -q 'ilegível' <<<"$out" && ok "recibo corrompido → regrave, sem crash" || bad "corrompido ($out)"

echo "-- integração com outcome (S-1302)"
"$BIN" decide --session evt --workflow fix --mode direct >/dev/null 2>&1
cd "$P"
out=$(CLAUDE_PROJECT_DIR="$P" "$BIN" outcome --session evt accepted --suite pass 2>&1)
grep -q 'SEM evidência' <<<"$out" && ok "pass sem ledger → aviso de palavra de honra" || bad "aviso ($out)"
"$BIN" evidence --record --project "$P" -- true >/dev/null
out=$(CLAUDE_PROJECT_DIR="$P" "$BIN" outcome --session evt accepted --suite pass 2>&1)
grep -q 'CITANDO evidência válida' <<<"$out" && ok "pass com ledger válido → citação mecânica" || bad "citação ($out)"
chk "record carrega suite_evidence=cited" "$(jq -r .suite_evidence "$MAESTRO_HOME/sessions/evt.json")" "cited"
cd "$REPO"

echo "-- E23b: o recibo casa com o COMANDO DECLARADO (.maestro.yaml)"
PV="$tmp/verif"; mkdir -p "$PV"; git -C "$PV" init -q
echo base > "$PV/f"; git -C "$PV" add -A; git -C "$PV" -c user.email=t@t -c user.name=t commit -qm x
EFV="$MAESTRO_HOME/evidence/$(basename "$("$BIN" brief --path --project "$PV")" .md)-suite"
# 1) projeto SEM commands: nada a casar — o recibo nasce `free` e vale como antes.
"$BIN" evidence --record --project "$PV" -- true >/dev/null
chk "sem commands declarado → cmd_match=free" "$(awk -F= '/^cmd_match=/{print $2}' "$EFV")" "free"
grep -q 'VÁLIDA' <<<"$("$BIN" evidence --project "$PV")" && ok "free segue VÁLIDA (regra antiga intacta)" || bad "free VÁLIDA"
# 2) com commands.suite declarado, `-- true` deixa de valer como prova da suíte.
printf 'commands:\n  suite: bash tests/run-all.sh\n' > "$PV/.maestro.yaml"
out=$("$BIN" evidence --record --project "$PV" -- true)
chk "comando diferente do declarado → cmd_match=no" "$(awk -F= '/^cmd_match=/{print $2}' "$EFV")" "no"
grep -q 'não é o comando declarado' <<<"$out" && ok "a gravação AVISA na hora" || bad "aviso na gravação ($out)"
out=$("$BIN" evidence --project "$PV")
grep -q 'VENCIDA — comando diferente do declarado' <<<"$out" \
  && ok "leitura: comando errado é VENCIDA (o buraco do \`-- true\` fechado)" || bad "VENCIDA por comando ($out)"
grep -q 'regrave: maestro evidence --record --label suite -- bash tests/run-all.sh' <<<"$out" \
  && ok "e diz o comando exato para regravar" || bad "sugestão com o comando declarado ($out)"
"$BIN" evidence --check --project "$PV" >/dev/null 2>&1; chk "--check com comando errado → 1" "$?" "1"
# 3) o comando declarado casa e prova.
mkdir -p "$PV/tests"; printf 'exit 0\n' > "$PV/tests/run-all.sh"
git -C "$PV" add -A; git -C "$PV" -c user.email=t@t -c user.name=t commit -qm suite
"$BIN" evidence --record --project "$PV" -- bash tests/run-all.sh >/dev/null
chk "comando idêntico ao declarado → cmd_match=yes" "$(awk -F= '/^cmd_match=/{print $2}' "$EFV")" "yes"
grep -q 'VÁLIDA' <<<"$("$BIN" evidence --project "$PV")" && ok "yes → VÁLIDA" || bad "yes VÁLIDA"
# 4) recibo ANTERIOR ao E23b (sem a linha) continua válido: ausência = free.
grep -v '^cmd_match=' "$EFV" > "$EFV.old" && mv -f "$EFV.old" "$EFV"
grep -q 'cmd_match' "$EFV" && bad "fixture de recibo antigo" || ok "fixture: recibo sem a linha cmd_match"
grep -q 'VÁLIDA' <<<"$("$BIN" evidence --project "$PV")" \
  && ok "recibo antigo (sem a linha) segue VÁLIDA quando o hash bate" || bad "recibo antigo VÁLIDA"
# 5) ...mas o hash, que sempre foi gravado e nunca comparado, agora vale:
#    recibo velho de OUTRO comando não sobrevive à declaração de commands.suite.
sed -i 's/^cmd_hash=.*/cmd_hash=0123456789abcdef/' "$EFV"
out=$("$BIN" evidence --project "$PV")
grep -q 'VENCIDA — comando do recibo ≠ commands.suite' <<<"$out" \
  && ok "cmd_hash divergente do declarado → VENCIDA" || bad "hash divergente ($out)"

echo "-- fronteiras: nada vaza para o routing.jsonl"
grep -q 'evidence\|wtree_' "$MAESTRO_HOME/logs/routing.jsonl" 2>/dev/null \
  && bad "ledger não aparece no log" || ok "ledger não aparece no log"

exit $fail
