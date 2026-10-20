#!/usr/bin/env bash
# E28 — gate domain na forma da v1.27 da Enterprise (API_SPEC §5.4.2 e §5.4.5,
# DATA_MODEL domain_request e domain_decision). Par de test-gate-domain.sh. Cobre:
# rollback como <caminho>#<ancora> do projeto que resolve (CONTRATO v2); o reason fora
# da classificação (o roteador do ponte-daemon não o lê); a lista domain_requests
# que vai no director.ask; a forma da decisão do CONTRATO v2 (condições {texto,
# check_ref}, reason até 120 no charset da Ponte, escalate_to/escalation_class,
# revoked_at com o revoked antigo lido por compatibilidade, revogação só pelo espelho,
# campo domain_decisions só na raiz do resultado); e o run headless que espera por
# director.wait_for. Hermético (mktemp -d).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
GATE="$REPO/hooks/pre-tool-gate.sh"
STOP="$REPO/hooks/gate-report.sh"
WAIT="$REPO/hooks/post-director-wait.sh"
SS="$REPO/hooks/session-start.sh"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

SB=$(mktemp -d)
trap '[[ $$ == $BASHPID ]] && rm -rf "$SB"' EXIT
export MAESTRO_HOME="$SB/home" MAESTRO_NO_UPDATE_CHECK=1
P="$SB/proj"; mkdir -p "$P/.maestro" "$P/docs" "$MAESTRO_HOME/sessions" "$MAESTRO_HOME/logs"
export CLAUDE_PROJECT_DIR="$P"
body=$'## Problema\np\n'
printf '<!-- maestro-intent\nversion: 7\nhash: %s\n-->\n%s' "$(printf '%s' "$body" | sha256sum | head -c 8)" "$body" \
  > "$P/.maestro/INTENT.md"
printf '# Plano\n\n## Rollback\ngit revert\n\n## Reversão da imagem\ntag anterior\n' > "$P/docs/rollback.md"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
REC() { printf '%s/sessions/%s.json' "$MAESTRO_HOME" "$1"; }
st()  { jq -r '.domain.status' "$(REC "$1")"; }
decide() { OUT=$("$BIN" decide "$@" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err"); }

command -v jq >/dev/null || { echo "FAIL jq ausente"; exit 1; }
if ! command -v bun >/dev/null; then echo "skip sem Bun (decide é src/cli.ts)"; exit 0; fi

echo "-- --rollback: <caminho>#<ancora> do projeto, que resolve (alfabeto do REF_CAMINHO_RE do daemon)"
ln -s /etc "$P/fora"
printf '# Plano\n\n## Rollback\nx\n' | tee "$P/docs/a+b@x.md" "$P/.env.rb" >/dev/null
printf '# Plano\n\n## Rollback\nx\n\n## Rollback\ny\n' > "$P/docs/dup.md"
for rb in "git revert" "../x.md#rollback" "/etc/hostname" "docs/nao-existe.md#rollback" "docs/rollback.md#nao-ha" \
          "docs" "fora/hostname#rollback" "docs/rollback.md#Rollback" "docs//rollback.md#rollback" \
          "docs/rollback.md" "docs/a+b@x.md#rollback" ".env.rb#rollback" "docs/dup.md#rollback" \
          "docs/rollback.md#-rollback"; do
  decide --session dm-rb --workflow feature --mode direct \
    --brief "essencia: x; impacto: y; approach: le .env" --targets ".env" --effects "e" --rollback "$rb"
  chk "--rollback '$rb': exit 1" "$RC" "1"
  [[ "$ERR" == *"--rollback"* ]] || bad "erro não cita --rollback ($rb): $ERR"
done
LONGDIR="docs/$(printf 'd%.0s' {1..150})"; LONGA="rollback-$(printf 'a%.0s' {1..40})"
mkdir -p "$P/$LONGDIR" "$P/${LONGDIR}e"
printf '# Plano\n\n## Rollback\nx\n\n## %s\nx\n' "$LONGA" \
  | tee "$P/$LONGDIR/r.md" "$P/${LONGDIR}e/r.md" "$P/docs/TODO.md" "$P/docs/a...b.md" >/dev/null
for rb in "$LONGDIR/r.md#$LONGA" "${LONGDIR}e/r.md#rollback" "docs/TODO.md#rollback" "docs/a...b.md#rollback"; do
  decide --session dm-rb --workflow feature --mode direct \
    --brief "essencia: x; impacto: y; approach: le .env" --targets ".env" --effects "e" --rollback "$rb"
  chk "--rollback que a Ponte recusa (${#rb} chars ou placeholder): exit 1" "$RC" "1"
done
decide --session dm-rb --workflow feature --mode direct \
  --brief "essencia: x; impacto: y; approach: le .env" --targets ".env" --effects "e" --rollback "$LONGDIR/r.md#rollback"
chk "--rollback com caminho de 160 chars e âncora (até 200): exit 0" "$RC" "0"
rm -f "$(REC dm-rb)"
printf '# Plano\n\n## Roll_back\nx\n' > "$P/docs/sub.md"
decide --session dm-rb --workflow feature --mode direct \
  --brief "essencia: x; impacto: y; approach: le .env" --targets ".env" --effects "e" --rollback "docs/sub.md#roll_back"
chk "--rollback com '_' na âncora (slug do daemon): exit 0" "$RC" "0"
rm -f "$(REC dm-rb)"
[[ -f "$(REC dm-rb)" ]] && bad "gravou com rollback que não resolve" || ok "nada gravado com rollback que não resolve"
decide --session dm-rb --workflow feature --mode direct \
  --brief "essencia: x; impacto: y; approach: le .env" --targets ".env" --effects "e" \
  --rollback "docs/rollback.md#reversao-da-imagem"
chk "âncora de título com acento resolve: exit 0" "$RC" "0"
chk "rollback_ref gravado como veio" "$(jq -r '.domain.requests[0].rollback_ref' "$(REC dm-rb)")" \
  "docs/rollback.md#reversao-da-imagem"

echo "-- domain_requests: a lista que vai no director.ask"
DRQ=$(sed -n 's/^domain_requests: //p' <<<"$OUT")
chk "linha domain_requests = requests do record" "$(jq -c . <<<"$DRQ" 2>/dev/null)" \
  "$(jq -c '.domain.requests' "$(REC dm-rb)")"
[[ "$OUT" == *"pedido: {"* ]] && ok "linhas pedido: seguem (Ponte anterior à v1.27)" || bad "saída: $OUT"
[[ "$OUT" == *"director.wait_for"* ]] && ok "saída cobre o run com director.wait_for" || bad "saída: $OUT"

echo "-- --reason não classifica (o roteador da Ponte não o lê)"
decide --session dm-why --workflow feature --mode direct --reason "mexe no fluxo de auth" \
  --brief "essencia: botao; impacto: x; approach: componente React na tela de perfil" --targets "src/ui/perfil.tsx"
chk "palavra de domínio só no --reason: exit 0" "$RC" "0"
chk "palavra de domínio só no --reason: clear" "$(st dm-why)" "clear"

# ---------------------------------------------------------------- decisões
decide --session dm-cmp --workflow refactor --mode direct \
  --brief "essencia: servico novo; impacto: x; approach: container novo no stack" \
  --targets "deploy/compose.prod.yaml" --effects "sobe container" --rollback "docs/rollback.md#rollback"
chk "pedido de infra: exit 0" "$RC" "0"
RID=$(jq -r '.domain.requests[0].request_id' "$(REC dm-rb)")
CRID=$(jq -r '.domain.requests[0].request_id' "$(REC dm-cmp)")
IH=$(jq -r '.domain.requests[0].intent.hash' "$(REC dm-rb)")
VU=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
dec() { # dec <decision_id> <response> <domain> <request_id>
  jq -nc --arg did "$1" --arg r "$2" --arg d "$3" --arg rid "$4" --arg vu "$VU" --arg ih "$IH" '
    {decision_id:$did, request_id:$rid, response:$r,
     conditions:(if $r == "approved_with_conditions" then [{texto:"sem segredo no log", check_ref:null}] else [] end),
     reason:"plano verificado", decided_by:{role:"director_domain", domain:$d, label:"x"},
     policy_ref:"MANDATOS.md#v1", intent:{version:7, hash:$ih}, valid_until:$vu}'
}
cdd() { OUT=$("$BIN" conduct --session dm-rb --domain-decision "$1" 2>&1); RC=$?; }
wait_hook() { # wait_hook <sid> <decisão> — como o ponte-daemon devolve: a linha `decisao:` na nota e domain_decisions[] na raiz
  jq -nc --arg sid "$1" --arg note "decisao: $2" '
    {session_id:$sid, hook_event_name:"PostToolUse", tool_name:"mcp__ponte__director_wait",
     tool_response:[{type:"text", text:({status:"respondida", decision_id:"01ABC", resposta:$note,
       domain_decisions:[$note | ltrimstr("decisao: ") | fromjson? | objects]} | tojson)}]}' \
    | bash "$WAIT" >/dev/null 2>&1
}

echo "-- forma da decisão (CONTRATO v2): conditions, reason, escalada, revoked_at"
COND='[{"texto":"segredo so por referencia, conferido no recibo","check_ref":"maestro:evidence/e1"}]'
cdd "$(dec v1 approved_with_conditions security "$RID" | jq -c --argjson c "$COND" '.conditions = $c')"
chk "conditions como {texto, check_ref}: aceito" "$RC" "0"
cdd "$(dec v1b approved_with_conditions security "$RID")"
chk "check_ref null: aceito" "$RC" "0"
for c in '[{"texto":"x"}]' '["sem segredo no log"]' '[{"texto":"sem acentuação","check_ref":null}]' \
         '[{"texto":"a; b","check_ref":null}]' '[{"texto":"x","check_ref":null,"id":"c1"}]' \
         "$(jq -nc '[range(9) | {texto:"c\(.)", check_ref:null}]')"; do
  cdd "$(dec v2 approved_with_conditions security "$RID" | jq -c --argjson c "$c" '.conditions = $c')"
  chk "condição fora da forma recusada: $c" "$RC" "1"
done
cdd "$(dec v2 approved security "$RID" | jq -c --argjson c "$COND" '.conditions = $c')"
chk "conditions fora de approved_with_conditions recusado" "$RC" "1"
cdd "$(dec e0 escalate security "$RID")"
chk "escalate sem escalate_to recusado" "$RC" "1"
cdd "$(dec e1 escalate security "$RID" | jq -c '.escalate_to = "spock"')"
chk "escalate_to spock sem classe: aceito" "$RC" "0"
cdd "$(dec e2 escalate security "$RID" | jq -c '.escalate_to = "spock" | .escalation_class = "crash"')"
chk "escalate_to spock com classe recusado" "$RC" "1"
cdd "$(dec e3 escalate security "$RID" | jq -c '.escalate_to = "captain"')"
chk "escalate_to captain sem classe recusado" "$RC" "1"
cdd "$(dec e4 escalate security "$RID" | jq -c '.escalate_to = "captain" | .escalation_class = "desvio_de_curso"')"
chk "escalate_to captain com classe: aceito" "$RC" "0"
cdd "$(dec e5 escalate security "$RID" | jq -c '.escalate_to = "capitao" | .escalation_class = "crash"')"
chk "escalate_to fora do enum recusado" "$RC" "1"
cdd "$(dec e6 approved security "$RID" | jq -c '.escalate_to = "spock"')"
chk "escalate_to fora de escalate recusado" "$RC" "1"
cdd "$(dec v3 approved security "$RID" | jq -c --arg r "$(printf 'r%.0s' {1..120})" '.reason = $r')"
chk "reason de 120 chars: aceito" "$RC" "0"
for r in "$(printf 'r%.0s' {1..121})" "decisão com acento" "a; b" ""; do
  cdd "$(dec v4 approved security "$RID" | jq -c --arg r "$r" '.reason = $r')"
  chk "reason fora do charset ou do teto recusado (${#r} chars)" "$RC" "1"
done
cdd "$(dec v6 approved security "$RID" | jq -c '.revoked_at = "ontem"')"
chk "revoked_at que não é timestamp ISO recusado" "$RC" "1"
cdd "$(dec v6 approved security "$RID" | jq -c '.revoked = "2026-10-20T12:00:00Z"')"
chk "revoked em texto (forma antiga) recusado" "$RC" "1"
cdd "$(dec v6 approved security "$RID" | jq -c '.revoked = {"x":1}')"
chk "revoked fora da forma recusado" "$RC" "1"
for rv in '.revoked = true' '.revoked_at = "2026-10-20T12:00:00Z"'; do
  cdd "$(dec v7 approved security "$RID" | jq -c "$rv")"
  chk "revogação manual recusada ($rv)" "$RC" "1"
  [[ "$OUT" == *"só pela Ponte"* ]] && ok "motivo: revogação só pela Ponte" || bad "saída: $OUT"
done
cdd "$(dec v5 approved security "$RID" | jq -c '.revoked_at = null | .revoked = false')"
chk "revoked_at null (e revoked false antigo): aceito" "$RC" "0"
chk "gravado na forma v2: escalada e revoked_at nulos, sem revoked" \
  "$(jq -c '.domain.decisions[] | select(.decision_id == "v5") | [.escalate_to, .escalation_class, .revoked_at, has("revoked")]' "$(REC dm-rb)")" \
  '[null,null,null,false]'
chk "registros manuais não liberam" "$(st dm-rb)" "pending"

echo "-- revogação pelo espelho: a decisão deixa de cobrir"
printf '{"session_id":"dm-pol"}' | MAESTRO_HOME="$SB/h-pol" CLAUDE_PROJECT_DIR="$SB/p-pol" \
  PONTE_MCP_SOCKET="$SB/sem-ponte.sock" bash "$SS" >/dev/null 2>&1
printf 'MAESTRO_GATE_MODE="block"\nMAESTRO_GATE_ALLOW_EXT=".md .txt"\nMAESTRO_GATE_ALLOW_PATHS=".maestro/ docs/"\nMAESTRO_GATE_DENY_PATHS=".claude/"\nMAESTRO_PLUGIN_ROOT="/opt/maestro-plugin"\n%s\n' \
  "$(grep '^MAESTRO_GATE_DOMAIN_' "$SB/h-pol/gate-policy.sh")" > "$MAESTRO_HOME/gate-policy.sh"
edit() { # edit <sid> <caminho relativo>
  printf '{"tool_name":"Edit","session_id":"%s","tool_input":{"file_path":"%s/%s"}}' "$1" "$P" "$2" \
    | bash "$GATE" >/dev/null 2>&1
  GRC=$?
}
wait_hook dm-cmp "$(dec i1 approved infrastructure "$CRID")"
chk "infra aprovado pela Ponte" "$(st dm-cmp)" "approved"
edit dm-cmp "deploy/compose.prod.yaml"
chk "aprovado: alvo → passa" "$GRC" "0"
wait_hook dm-cmp "$(dec i9 approved infrastructure "$CRID" | jq -c '.revoked_at = "2026-10-20T12:00:00Z"')"
chk "revogação de decisão desconhecida: ignorada" "$(st dm-cmp)" "approved"
wait_hook dm-cmp "$(dec i1 denied infrastructure "$CRID" | jq -c '.revoked_at = "2026-10-20T12:00:00Z"')"
chk "revogação que difere da decisão registrada: ignorada" "$(st dm-cmp)" "approved"
wait_hook dm-cmp "$(dec i1 approved infrastructure "$CRID" | jq -c '.revoked_at = "2026-10-20T12:00:00Z"')"
chk "revogada: status volta a pending" "$(st dm-cmp)" "pending"
chk "revogada: nada liberado" "$(jq -c '[.domain.cleared, .domain.cleared_until]' "$(REC dm-cmp)")" '["",0]'
chk "revogada no lugar, sem duplicar" \
  "$(jq -c '[.domain.decisions[] | select(.decision_id == "i1") | .revoked_at]' "$(REC dm-cmp)")" '["2026-10-20T12:00:00Z"]'
edit dm-cmp "deploy/compose.prod.yaml"
chk "revogada: alvo volta a ficar suspenso → exit 2" "$GRC" "2"

echo "-- domain_decisions[] no resultado do director.wait"
I2=$(dec i2 approved infrastructure "$CRID")
jq -nc --argjson d "$I2" --arg note "decisao: $I2" '{session_id:"dm-cmp", hook_event_name:"PostToolUse",
  tool_name:"mcp__plugin_maestro_ponte__director_wait",
  tool_response:[{type:"text", text:({status:"respondida", decision_id:"01ABC", resposta:$note,
    domain_decisions:[$d]} | tojson)}]}' | bash "$WAIT" >/dev/null 2>&1
chk "decisão nova depois da revogação" "$(st dm-cmp)" "approved"
chk "nota e domain_decisions[] com a mesma decisão: espelhada uma vez" \
  "$(jq '[.domain.decisions[] | select(.decision_id == "i2")] | length' "$(REC dm-cmp)")" "1"
edit dm-cmp "deploy/compose.prod.yaml"
chk "aprovada de novo: alvo → passa" "$GRC" "0"
"$BIN" decide --session dm-cmp --workflow refactor --mode direct \
  --brief "essencia: servico novo; impacto: x; approach: container novo no stack" \
  --targets "deploy/compose.prod.yaml" --effects "sobe container" --rollback "docs/rollback.md#rollback" >/dev/null 2>&1
chk "re-decide do mesmo plano: revogada segue sem cobrir, i2 vale" "$(st dm-cmp)" "approved"

echo "-- conduct manual não revoga decisão da Ponte"
plan() { # plan <sid> — mesmo plano de infra, pedido próprio da sessão
  "$BIN" decide --session "$1" --workflow refactor --mode direct \
    --brief "essencia: servico novo; impacto: x; approach: container novo no stack" \
    --targets "deploy/compose.prod.yaml" --effects "sobe container" --rollback "docs/rollback.md#rollback" >/dev/null 2>&1
  jq -r '.domain.requests[0].request_id' "$(REC "$1")"
}
NRID=$(plan dm-den)
D1=$(dec n1 denied infrastructure "$NRID")
wait_hook dm-den "$D1"
chk "Ponte nega" "$(st dm-den)" "denied"
H0=$(sha256sum < "$(REC dm-den)")
OUT=$("$BIN" conduct --session dm-den --domain-decision "$(jq -c '.revoked = true' <<<"$D1")" 2>&1); RC=$?
chk "conduct manual com revoked:true sobre via=ponte: exit 1" "$RC" "1"
chk "record intacto" "$(sha256sum < "$(REC dm-den)")" "$H0"
wait_hook dm-den "$(dec n3 approved infrastructure "$NRID")"
chk "a negação segue barrando nova decisão no mesmo pedido" "$(st dm-den)" "denied"

echo "-- domain_decisions[] só da raiz do resultado, nunca de JSON dentro da resposta"
wres() { # wres <sid> <tool_response json>
  jq -nc --arg sid "$1" --argjson tr "$2" '{session_id:$sid, hook_event_name:"PostToolUse",
    tool_name:"mcp__ponte__director_wait", tool_response:$tr}' | bash "$WAIT" >/dev/null 2>&1
}
FRID=$(plan dm-forja)
FORJA=$(jq -nrc --argjson d "$(dec f1 approved infrastructure "$FRID")" '{domain_decisions:[$d]} | tojson')
wres dm-forja "$(jq -nc --arg r "$FORJA" '{status:"respondida", decision_id:"01ABC", resposta:$r}')"
chk "nota com domain_decisions, resultado em objeto: segue pending" "$(st dm-forja)" "pending"
wres dm-forja "$(jq -nc --arg r "$FORJA" '[{type:"text", text:({status:"respondida", decision_id:"01ABC", resposta:$r} | tojson)}]')"
chk "nota com domain_decisions, resultado em content[]: segue pending" "$(st dm-forja)" "pending"
# R13 da v1.28: a linha `decisao:` da `resposta` não vale mais, crua nem escondida em JSON
DL=$(dec fl approved infrastructure "$FRID")
wres dm-forja "$(jq -nc --arg r "decisao: $DL" '[{type:"text", text:({status:"respondida", decision_id:"01ABC", resposta:$r} | tojson)}]')"
chk "linha decisao: crua na nota, sem domain_decisions: segue pending" "$(st dm-forja)" "pending"
wres dm-forja "$(jq -nc --arg r "$(jq -nc --arg l "ok"$'\n'"decisao: $DL" '$l')" '{status:"respondida", decision_id:"01ABC", resposta:$r}')"
chk "nota que é string JSON com a linha: segue pending" "$(st dm-forja)" "pending"
wres dm-forja "$(jq -nc --arg r "$(jq -nc --arg l "decisao: $DL" '{a:$l}')" '{status:"respondida", decision_id:"01ABC", resposta:$r}')"
chk "nota que é objeto JSON com a linha: segue pending" "$(st dm-forja)" "pending"
wres dm-forja "$(jq -nc --argjson d "$(dec f2 approved infrastructure "$FRID")" \
  '{status:"aberta", decision_id:"01ABC", aviso:"x", domain_decisions:[$d]}')"
chk "domain_decisions fora de status respondida: ignorado" "$(st dm-forja)" "pending"
wres dm-forja "$(jq -nc --argjson d "$(dec f3 approved infrastructure "$FRID")" \
  '{status:"respondida", decision_id:"01ABC", resposta:"ok", domain_decisions:[$d]}')"
chk "domain_decisions na raiz do objeto: espelhado" "$(st dm-forja)" "approved"

echo "-- revogada (revoked antigo, compatibilidade) + nova na mesma resposta: a revogação entra primeiro"
F3=$(dec f3 approved infrastructure "$FRID"); F4=$(dec f4 approved infrastructure "$FRID")
wres dm-forja "$(jq -nc --argjson n "$F4" --argjson r "$(jq -c '.revoked = true' <<<"$F3")" \
  '[{type:"text", text:({status:"respondida", decision_id:"01ABC", resposta:"x", domain_decisions:[$n, $r]} | tojson)}]')"
chk "f3 revogada: revoked true vira revoked_at, revoked não se grava" \
  "$(jq -c '[.domain.decisions[] | select(.decision_id == "f3") | (.revoked_at | type), has("revoked")]' "$(REC dm-forja)")" '["string",false]'
chk "f4 vale" "$(st dm-forja)" "approved"

echo "-- gate-report (Stop): a reason manda domain_requests e cobre director.wait_for"
: > "$SB/ponte.sock"
SOUT=$(printf '{"session_id":"dm-rb","stop_hook_active":false}' | env HERDR_ENV=1 HERDR_PANE_ID=w9:p9 \
  HERDR_BIN_PATH=/bin/true PONTE_MCP_SOCKET="$SB/ponte.sock" bash "$STOP" 2>/dev/null)
[[ "$SOUT" == *'"decision":"block"'* && "$SOUT" == *"domain_requests"* && "$SOUT" == *"director.wait_for"* ]] \
  && ok "reason com domain_requests e director.wait_for" || bad "stdout: $SOUT"
[[ "$SOUT" == *"security"* || "$SOUT" == *".env"* ]] && bad "reason vazou o pedido" || ok "reason não cita o pedido"

exit $fail
