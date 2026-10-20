#!/usr/bin/env bash
# E28 — diretoria por domínio: `gate: domain` em feature/refactor.
#
# Pacote 03-Maestro.md: plano sem domínio segue sem gate; `.env` pede decisão de
# segurança; `compose` pede decisão de infra; `gate: ship` não muda. E o contrato:
# pedido sem placeholder, decisão espelhada do director_wait (via=ponte; conduct digitado
# não libera), gate em alvo e caminho de domínio, Stop pela Ponte — timeout nunca aprova.
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
intent_write() { # <corpo> — carimbo v7 com o hash REAL do corpo (regra do core-intent.sh)
  local h; h=$(printf '%s' "$1" | sha256sum | head -c 8)
  printf '<!-- maestro-intent\nversion: 7\nhash: %s\n-->\n%s' "$h" "$1" > "$P/.maestro/INTENT.md"
}
intent_write $'## Problema\np\n'
printf '# Plano\n\n## Rollback\ngit revert\n\n## Reversão da imagem\ntag\n' > "$P/docs/rollback.md" # v1.27: rollback resolve

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
REC() { printf '%s/sessions/%s.json' "$MAESTRO_HOME" "$1"; }
decide() { OUT=$("$BIN" decide "$@" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err"); }

command -v jq >/dev/null || { echo "FAIL jq ausente"; exit 1; }
if ! command -v bun >/dev/null; then echo "skip sem Bun (decide é src/cli.ts)"; exit 0; fi

echo "-- routing table: feature/refactor em gate domain, ship intocado"
gates=$(bun -e 'const d=Bun.YAML.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  console.log(["feature","refactor","ship","fix"].map(w=>w+"="+d.workflows[w].gate).join(" "),
  Object.keys(d.domains).join(","))' "$REPO/config/routing-table.yaml")
chk "gates da tabela" "$gates" "feature=domain refactor=domain ship=ship fix=none security,infrastructure"

echo "-- session-start compila domains.*.paths no gate-policy.sh"
printf '{"session_id":"dm-pol"}' | MAESTRO_HOME="$SB/h-pol" CLAUDE_PROJECT_DIR="$SB/p-pol" \
  PONTE_MCP_SOCKET="$SB/sem-ponte.sock" bash "$SS" >/dev/null 2>&1
DOMRE=$(grep '^MAESTRO_GATE_DOMAIN_' "$SB/h-pol/gate-policy.sh" 2>/dev/null)
chk "duas EREs (security, infrastructure)" "$(grep -c "_RE='^(" <<<"$DOMRE")" "2"
(
  # shellcheck source=/dev/null
  source "$SB/h-pol/gate-policy.sh"
  m() { [[ "${1,,}" =~ $2 ]] && echo y || echo n; }
  S="$MAESTRO_GATE_DOMAIN_SECURITY_RE" I="$MAESTRO_GATE_DOMAIN_INFRASTRUCTURE_RE"
  r="$(m .env.production "$S")$(m config/.env "$S")$(m src/auth/x.ts "$S")$(m src/authx.ts "$S")"
  r+=" $(m deploy/compose.prod.yml "$I")$(m Dockerfile "$I")$(m infra/app.service "$I")$(m docker/x.sh "$I")"
  [[ "$r" == "yyyn yyyn" ]] && echo "ok   globs com a semântica do decide" || echo "FAIL globs: $r"
) | tee "$SB/glob.out"
grep -q '^FAIL' "$SB/glob.out" && fail=1

echo "-- plano sem domínio: segue sem gate"
decide --session dm-clear --workflow feature --mode direct \
  --brief "essencia: botao novo; impacto: usuario ve x; approach: componente React na tela de perfil" \
  --targets "src/ui/perfil.tsx"
chk "exit 0" "$RC" "0"
chk "status clear" "$(jq -r '.domain.status' "$(REC dm-clear)")" "clear"
chk "nenhum pedido" "$(jq '.domain.requests | length' "$(REC dm-clear)")" "0"
[[ "$OUT" == *"não toca domínio"* ]] && ok "decide diz que segue sem pedido" || bad "saída: $OUT"

echo "-- approach pendente não é plano"
decide --session dm-pend --workflow refactor --mode direct --brief "essencia: x; impacto: y; approach: pendente"
chk "exit 1" "$RC" "1"
[[ -f "$(REC dm-pend)" ]] && bad "gravou record com plano pendente" || ok "nada gravado"
decide --session dm-nobrief --workflow feature --mode direct
chk "sem --brief: exit 1" "$RC" "1"
[[ "$ERR" == *"exige --brief"* ]] && ok "erro cita --brief" || bad "erro: $ERR"

echo "-- plano que toca .env: pedido de segurança"
decide --session dm-env --workflow feature --mode direct \
  --brief "essencia: chave nova; impacto: integra x; approach: le a chave no boot" \
  --targets ".env.example,src/config.ts" --effects "variavel nova no ambiente" --rollback "docs/rollback.md#rollback" --order 110
chk "exit 0" "$RC" "0"
R="$(REC dm-env)"
chk "status pending" "$(jq -r '.domain.status' "$R")" "pending"
chk "um pedido, de security" "$(jq -r '[.domain.requests[].domain] | join(",")' "$R")" "security"
chk "scope = targets" "$(jq -r '.domain.scope' "$R")" ".env.example src/config.ts"
chk "nada liberado ainda" "$(jq -c '[.domain.cleared, .domain.cleared_until]' "$R")" '["",0]'
chk "campos do contrato mínimo" "$(jq -r '.domain.requests[0] | keys | join(",")' "$R")" \
  "domain,effects,intent,order_ref,plan,project,request_id,rollback_ref,targets"
chk "order_ref" "$(jq -r '.domain.requests[0].order_ref' "$R")" "110"
chk "intent.version" "$(jq -r '.domain.requests[0].intent.version' "$R")" "7"
want=$(sed '1,/^-->$/d' "$P/.maestro/INTENT.md" | sha256sum | head -c 8)
chk "intent.hash = hash do corpo (core-intent.sh)" "$(jq -r '.domain.requests[0].intent.hash' "$R")" "$want"
[[ "$(jq -r '.domain.requests[0].plan.hash' "$R")" =~ ^[0-9a-f]{64}$ ]] && ok "plan.hash sha256" || bad "plan.hash"
# Receita do plan.hash (DATA_MODEL §3 v1.26) — a Ponte recalcula do record.
ph=$(jq -j '{brief, targets: .domain.requests[0].targets, effects: .domain.requests[0].effects,
  rollback_ref: .domain.requests[0].rollback_ref, order_ref: .domain.requests[0].order_ref}' -c "$R" | sha256sum | cut -c1-64)
chk "plan.hash = sha256 do JSON {brief,targets,effects,rollback_ref,order_ref}" "$(jq -r '.domain.requests[0].plan.hash' "$R")" "$ph"
[[ "$OUT" == *"pedido: {"* && "$OUT" == *"director.ask"* && "$OUT" == *"timeout não aprova"* ]] \
  && ok "decide imprime o pedido e o caminho pela Ponte" || bad "saída: $OUT"
[[ "$OUT" == *"conduct --session"* ]] && bad "decide ainda manda o gerente digitar a decisão" || ok "decide não manda digitar a decisão"
[[ "$(head -c 4096 "$R")" == *'"domain":{"status":"pending","scope":".env.example src/config.ts","cleared":"","cleared_until":0,'* ]] \
  && ok "status, scope, cleared e cleared_until dentro da janela de 4 KiB do gate" || bad "domain fora da janela do gate"

echo "-- plano que toca compose: pedido de infra"
decide --session dm-cmp --workflow refactor --mode direct \
  --brief "essencia: servico novo; impacto: x; approach: container novo no stack" \
  --targets "deploy/compose.prod.yaml" --effects "sobe container" --rollback "docs/rollback.md"
chk "exit 0" "$RC" "0"
chk "pedido de infrastructure" "$(jq -r '[.domain.requests[].domain] | join(",")' "$(REC dm-cmp)")" "infrastructure"

echo "-- gatilho por palavra do plano, sem caminho"
decide --session dm-kw --workflow feature --mode direct \
  --brief "essencia: api; impacto: x; approach: libera CORS para o app" \
  --targets "src/api/server.ts" --effects "origem nova aceita" --rollback "docs/rollback.md"
chk "cors → security" "$(jq -r '[.domain.requests[].domain] | join(",")' "$(REC dm-kw)")" "security"
decide --session dm-df --workflow feature --mode direct \
  --brief "essencia: imagem; impacto: x; approach: Dockerfile roda como USER app" \
  --targets "Dockerfile" --effects "imagem nova" --rollback "docs/rollback.md#reversao-da-imagem"
chk "Dockerfile com USER → security e infra" \
  "$(jq -r '[.domain.requests[].domain] | join(",")' "$(REC dm-df)")" "security,infrastructure"
decide --session dm-user --workflow feature --mode direct \
  --brief "essencia: perfil; impacto: o user ve x; approach: tela de user" --targets "src/user.ts"
chk "'user' minúsculo fora de Dockerfile não é gatilho" "$(jq -r '.domain.status' "$(REC dm-user)")" "clear"

echo "-- tocou domínio sem o contrato: recusa (nenhum placeholder)"
decide --session dm-falta --workflow feature --mode direct \
  --brief "essencia: x; impacto: y; approach: le .env" --targets ".env"
chk "exit 1" "$RC" "1"
[[ "$ERR" == *"--effects"* && "$ERR" == *"--rollback"* ]] && ok "erro lista os campos que faltam" || bad "erro: $ERR"
[[ -f "$(REC dm-falta)" ]] && bad "gravou pedido incompleto" || ok "nada gravado"
mv "$P/.maestro/INTENT.md" "$SB/intent.bak"
decide --session dm-semintent --workflow feature --mode direct \
  --brief "essencia: x; impacto: y; approach: le .env" --targets ".env" --effects "e" --rollback "docs/rollback.md"
chk "sem INTENT carimbado: exit 1" "$RC" "1"
mv "$SB/intent.bak" "$P/.maestro/INTENT.md"
cp "$P/.maestro/INTENT.md" "$SB/intent.bak"
printf 'linha nova sem bump\n' >> "$P/.maestro/INTENT.md"
decide --session dm-stale --workflow feature --mode direct \
  --brief "essencia: x; impacto: y; approach: le .env" --targets ".env" --effects "e" --rollback "docs/rollback.md"
chk "INTENT editado desde o carimbo: exit 1" "$RC" "1"
[[ "$ERR" == *"--bump"* ]] && ok "erro manda dar bump" || bad "erro: $ERR"
mv "$SB/intent.bak" "$P/.maestro/INTENT.md"

echo "-- tabela malformada: gate domain sem domains, domínio fora do vocabulário"
sed '/^domains:/,/^# O casamento/{/^# O casamento/!d}' "$REPO/config/routing-table.yaml" > "$SB/sem-domains.yaml"
MAESTRO_ROUTING_TABLE="$SB/sem-domains.yaml" decide --session dm-cfg --workflow fix --mode direct
chk "gate domain sem domains: exit 2 (config)" "$RC" "2"
sed 's/^  infrastructure:$/  financeiro:/' "$REPO/config/routing-table.yaml" > "$SB/dom-alheio.yaml"
MAESTRO_ROUTING_TABLE="$SB/dom-alheio.yaml" decide --session dm-cfg --workflow fix --mode direct
chk "domínio fora de security|infrastructure: exit 2" "$RC" "2"

echo "-- gate ship não muda"
decide --session dm-ship --workflow ship --mode direct
chk "ship sem brief: exit 0" "$RC" "0"
chk "record de ship sem bloco domain" "$(jq 'has("domain")' "$(REC dm-ship)")" "false"
decide --session dm-ship2 --workflow ship --mode direct --targets ".env"
chk "--targets fora de gate domain: exit 1" "$RC" "1"

# ---------------------------------------------------------------- decisões
RID=$(jq -r '.domain.requests[0].request_id' "$(REC dm-env)")
IH=$(jq -r '.domain.requests[0].intent.hash' "$(REC dm-env)")
VU=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
dec() { # dec <decision_id> <response> <role> <domain|null> [valid_until] [intent_hash] [request_id]
  jq -nc --arg did "$1" --arg rid "${7:-$RID}" --arg r "$2" --arg role "$3" --arg d "$4" \
     --arg vu "${5:-$VU}" --arg ih "${6:-$IH}" '
    {decision_id:$did, request_id:$rid, response:$r,
     conditions:(if $r == "approved_with_conditions" then ["sem segredo no log"] else [] end),
     reason:"plano verificado", decided_by:{role:$role, domain:(if $d == "null" then null else $d end), label:"eu mesmo"},
     policy_ref:"MANDATOS.md#security", intent:{version:7, hash:$ih}, valid_until:$vu}'
}
cdd() { OUT=$("$BIN" conduct --session dm-env --domain-decision "$1" 2>&1); RC=$?; }
# wait_hook <sid> <decisão...> — o resultado do director_wait como o servidor MCP o devolve:
# blocos de texto com o JSON do DirectorWaitOutput, e a nota com uma linha `decisao:` por pedido.
wait_hook() {
  local sid="$1" tool="${TOOL:-mcp__ponte__director_wait}" note=""; shift
  for d in "$@"; do note+="decisao: $d"$'\n'; done
  jq -nc --arg sid "$sid" --arg tool "$tool" --arg note "${note%$'\n'}" '
    {session_id:$sid, hook_event_name:"PostToolUse", tool_name:$tool, tool_input:{decision_id:"01ABC"},
     tool_response:[{type:"text", text:({status:"respondida", decision_id:"01ABC", resposta:$note,
       resolvido_em:"2026-10-20T00:00:00Z"} | tojson)}]}' | bash "$WAIT" >/dev/null 2>&1
  WRC=$?
}
st() { jq -r '.domain.status' "$(REC "$1")"; }

echo "-- conduct --domain-decision: recusas do contrato"
cdd "$(dec d1 approved director_domain infrastructure)"
chk "diretor de outro domínio: exit 1" "$RC" "1"
cdd "$(dec d1 approved mechanical null)"
chk "aprovação mecânica (timeout) recusada" "$RC" "1"
[[ "$OUT" == *"timeout nunca aprova"* ]] && ok "motivo: timeout nunca aprova" || bad "saída: $OUT"
cdd "$(dec d1 approved spock security)"
chk "spock com domínio recusado" "$RC" "1"
cdd "$(dec d1 approved director_domain security 2020-01-01T00:00:00Z)"
chk "decisão vencida recusada" "$RC" "1"
cdd "$(dec d1 approved director_domain security "$VU" deadbeef)"
chk "intent diferente do pedido recusado" "$RC" "1"
cdd "$(dec d1 approved director_domain security | jq -c '.extra = 1')"
chk "campo fora do contrato recusado" "$RC" "1"
cdd "$(dec d1 approved director_domain security | jq -c 'del(.policy_ref)')"
chk "campo faltando recusado" "$RC" "1"
cdd "$(dec d1 approved director_domain security | jq -c '.request_id = "dreq-0000000000000000"')"
chk "pedido de outro record recusado" "$RC" "1"
chk "recusas não mexem no status" "$(st dm-env)" "pending"

echo "-- conduct digitado não libera (identidade nunca sai de texto do cliente)"
cdd "$(dec m1 approved director_domain security)"
chk "aprovação digitada: registrada (exit 0)" "$RC" "0"
[[ "$OUT" == *"MANUAL"* && "$OUT" == *"não libera"* ]] && ok "saída diz que é manual e não libera" || bad "saída: $OUT"
chk "status segue pending" "$(st dm-env)" "pending"
chk "via manual, label derivado (nunca o do cliente)" \
  "$(jq -r '.domain.decisions[-1] | "\(.via) \(.decided_by.label)"' "$(REC dm-env)")" "manual diretor-seguranca"
cdd "$(dec m2 approved captain null)"
chk "capitão digitado: registrado, status pending" "$RC $(st dm-env)" "0 pending"
grep -q '"cmd":"domain_approved".*"via":"manual"' "$MAESTRO_HOME/logs/routing.jsonl" \
  && ok "log só com metadado (cmd=domain_<response>, via=manual)" || bad "log do conduct"

echo "-- post-director-wait: o resultado da tool da Ponte é a prova de runtime"
TOOL=mcp__outro__director_wait wait_hook dm-env "$(dec p0 approved director_domain security)"
chk "tool que não é da Ponte: ignorada" "$(st dm-env)" "pending"
wait_hook dm-env "$(dec p1 approved director_domain infrastructure)"
chk "diretor de outro domínio pela Ponte: ignorado" "$(st dm-env)" "pending"
wait_hook dm-env "$(dec p2 needs_evidence director_domain security)"
chk "hook exit 0" "$WRC" "0"
chk "needs_evidence espelhado" "$(st dm-env)" "needs_evidence"
wait_hook dm-env "$(dec p3 approved_with_conditions director_domain security)"
chk "approved_with_conditions espelhado" "$(st dm-env)" "approved_with_conditions"
chk "com condição: nada liberado" "$(jq -r '.domain.cleared' "$(REC dm-env)")" ""
grep -q '"cmd":"domain_approved_with_conditions".*"via":"auto"' "$MAESTRO_HOME/logs/routing.jsonl" \
  && ok "log do espelho: via=auto" || bad "log do hook"

echo "-- re-decide: mesmo plano preserva a decisão; plano novo reabre o pedido"
"$BIN" decide --session dm-env --workflow feature --mode direct \
  --brief "essencia: chave nova; impacto: integra x; approach: le a chave no boot" \
  --targets ".env.example,src/config.ts" --effects "variavel nova no ambiente" --rollback "docs/rollback.md#rollback" --order 110 >/dev/null 2>&1
chk "mesmo plano: status mantido" "$(st dm-env)" "approved_with_conditions"
# decisão vencida não sobrevive ao re-decide
jq -c '.domain.decisions |= map(.until_epoch = 1)' "$(REC dm-env)" > "$SB/t" && mv "$SB/t" "$(REC dm-env)"
"$BIN" decide --session dm-env --workflow feature --mode direct \
  --brief "essencia: chave nova; impacto: integra x; approach: le a chave no boot" \
  --targets ".env.example,src/config.ts" --effects "variavel nova no ambiente" --rollback "docs/rollback.md#rollback" --order 110 >/dev/null 2>&1
chk "mesmo plano com decisão vencida: pending de novo" "$(st dm-env)" "pending"
"$BIN" decide --session dm-env --workflow feature --mode direct \
  --brief "essencia: chave nova; impacto: integra x; approach: le a chave e grava em disco" \
  --targets ".env.example,src/config.ts" --effects "variavel nova no ambiente" --rollback "docs/rollback.md#rollback" >/dev/null 2>&1
chk "plano novo: pending" "$(st dm-env)" "pending"
chk "plano novo: decisão velha não vale" "$(jq '.domain.decisions // [] | length' "$(REC dm-env)")" "0"
RID=$(jq -r '.domain.requests[0].request_id' "$(REC dm-env)")

echo "-- trocar de workflow não apaga pedido aberto"
decide --session dm-env --workflow fix --mode direct
chk "pending → fix: exit 1" "$RC" "1"
chk "bloco domain intacto" "$(st dm-env)" "pending"
decide --session dm-env --workflow feature --mode direct \
  --brief "essencia: so tela; impacto: x; approach: componente novo sem tocar config" --targets "src/ui/x.tsx"
chk "plano novo sem domínio na mesma sessão: exit 0" "$RC" "0"
chk "status clear" "$(st dm-env)" "clear"
"$BIN" decide --session dm-env --workflow feature --mode direct \
  --brief "essencia: chave nova; impacto: integra x; approach: le a chave e grava em disco" \
  --targets ".env.example,src/config.ts" --effects "variavel nova no ambiente" --rollback "docs/rollback.md#rollback" >/dev/null 2>&1
chk "volta ao plano com domínio: pending" "$(st dm-env)" "pending"

echo "-- schema do record (doctor) aceita o bloco domain"
(
  # shellcheck disable=SC2034  # lido por record_schema_ok (lib/core-record.sh)
  RECORD_FIELDS=$(sed -n "s/^RECORD_FIELDS='\(.*\)'$/\1/p" "$BIN")
  # shellcheck source=/dev/null
  source "$REPO/lib/core-record.sh"
  for s in dm-clear dm-env dm-cmp dm-ship; do
    record_schema_ok "$(REC $s)" && ok "schema ok: $s" || bad "schema reprovou $s"
  done
  jq -c '.domain.status = "aprovado"' "$(REC dm-cmp)" > "$SB/bad.json"
  record_schema_ok "$SB/bad.json" && bad "status fora do enum passou" || ok "status fora do enum reprovado"
  jq -c '.domain.cleared = "financeiro"' "$(REC dm-cmp)" > "$SB/bad.json"
  record_schema_ok "$SB/bad.json" && bad "cleared fora do enum passou" || ok "cleared fora do enum reprovado"
) || fail=1

echo "-- pre-tool-gate: mutação dependente e caminho de domínio"
policy() {
  printf 'MAESTRO_GATE_MODE="%s"\nMAESTRO_GATE_ALLOW_EXT=".md .txt"\nMAESTRO_GATE_ALLOW_PATHS=".maestro/ docs/"\nMAESTRO_GATE_DENY_PATHS=".claude/"\nMAESTRO_PLUGIN_ROOT="/opt/maestro-plugin"\n%s\n' \
    "$1" "$DOMRE" > "$MAESTRO_HOME/gate-policy.sh"
}
edit() { # edit <sid> <caminho relativo>
  GERR=$(printf '{"tool_name":"Edit","session_id":"%s","tool_input":{"file_path":"%s/%s"}}' "$1" "$P" "$2" | bash "$GATE" 2>&1 >/dev/null)
  GRC=$?
}
policy block
edit dm-env ".env.example"
chk "block: alvo do pedido pendente → exit 2" "$GRC" "2"
[[ "$GERR" == *"gate domain"* && "$GERR" == *"Timeout não aprova"* ]] && ok "mensagem diz o caminho" || bad "stderr: $GERR"
[[ "$GERR" == *"conduct"* ]] && bad "mensagem manda digitar a decisão" || ok "mensagem não manda digitar a decisão"
edit dm-env "src/outra.ts"
chk "block: fora dos alvos e fora de domínio → passa" "$GRC" "0"
edit dm-cmp "deploy/compose.prod.yaml"
chk "block: compose do pedido de infra pendente → exit 2" "$GRC" "2"
edit dm-cmp "deploy/compose.yml"
chk "block: outro compose, fora dos alvos → exit 2 (caminho de domínio)" "$GRC" "2"
edit dm-cmp "infra/app.service"
chk "block: unit systemd fora dos alvos → exit 2" "$GRC" "2"
edit dm-clear "src/ui/perfil.tsx"
chk "block: plano sem domínio → passa" "$GRC" "0"
for f in .env.production deploy/docker-compose.yml src/auth/token.ts; do
  edit dm-clear "$f"
  chk "block: plano clear não cobre $f → exit 2" "$GRC" "2"
done
tail -1 "$MAESTRO_HOME/logs/routing.jsonl" | grep -q '"cmd":"domain_path"' && ok "gate_block com cmd=domain_path" || bad "log do gate"
decide --session dm-fix --workflow fix --mode direct
edit dm-fix ".env"
chk "block: workflow sem gate domain não cobre .env → exit 2" "$GRC" "2"
edit dm-fix "src/x.ts"
chk "block: workflow sem gate domain, código comum → passa" "$GRC" "0"

echo "-- pre-tool-gate: só aprovação da Ponte, válida e sem condição, libera"
cdd "$(dec m3 approved director_domain security)"
edit dm-env ".env.example"
chk "aprovação digitada (forja) não libera → exit 2" "$GRC" "2"
wait_hook dm-env "$(dec q1 approved_with_conditions director_domain security)"
edit dm-env ".env.example"
chk "approved_with_conditions não libera → exit 2" "$GRC" "2"
wait_hook dm-env "$(dec q2 approved director_domain security)"
chk "aprovado pela Ponte depois das condições" "$(st dm-env)" "approved"
chk "cleared security" "$(jq -r '.domain.cleared' "$(REC dm-env)")" "security"
edit dm-env ".env.example"
chk "aprovado: alvo de domínio → passa" "$GRC" "0"
edit dm-env "src/config.ts"
chk "aprovado: alvo comum do plano → passa" "$GRC" "0"
edit dm-env ".env.production"
chk "aprovado: caminho de domínio fora dos alvos → exit 2" "$GRC" "2"
wait_hook dm-env "$(dec q3 denied director_domain security)"
chk "segunda resolução da Ponte ignorada" "$(st dm-env)" "approved"
jq -c '.domain.cleared_until = 1' "$(REC dm-env)" > "$SB/t" && mv "$SB/t" "$(REC dm-env)"
edit dm-env ".env.example"
chk "aprovação vencida não libera → exit 2" "$GRC" "2"
tail -1 "$MAESTRO_HOME/logs/routing.jsonl" | grep -q '"cmd":"domain_expired"' && ok "gate_block com cmd=domain_expired" || bad "log do vencido"
edit dm-env "src/config.ts"
chk "aprovação vencida: alvo comum também espera" "$GRC" "2"
CRID=$(jq -r '.domain.requests[0].request_id' "$(REC dm-cmp)")
wait_hook dm-cmp "$(dec i1 approved director_domain infrastructure "$VU" "$IH" "$CRID")"
chk "infra aprovado pela Ponte" "$(st dm-cmp)" "approved"
edit dm-cmp "deploy/compose.prod.yaml"
chk "block: alvo com pedido aprovado → passa" "$GRC" "0"
edit dm-cmp ".env"
chk "aprovação de infra não cobre caminho de security → exit 2" "$GRC" "2"

echo "-- pre-tool-gate warn: avisa e segue o fluxo normal (orçamento conta)"
policy warn
decide --session dm-bud --workflow feature --mode direct --max-steps 5 \
  --brief "essencia: chave; impacto: x; approach: le a chave" \
  --targets ".env.local" --effects "variavel nova" --rollback "docs/rollback.md"
edit dm-bud ".env.local"
chk "warn: alvo pendente → passa com aviso" "$GRC" "0"
[[ "$GERR" == *"aviso"* ]] && ok "aviso no stderr" || bad "stderr: $GERR"
tail -1 "$MAESTRO_HOME/logs/routing.jsonl" | grep -q '"event":"gate_warn".*"cmd":"domain_pending"' \
  && ok "gate_warn com cmd=domain_pending, sem gate_pass depois" || bad "log do gate: $(tail -1 "$MAESTRO_HOME/logs/routing.jsonl")"
chk "orçamento contou o passo" "$(cut -f1 "$MAESTRO_HOME/sessions/budget-dm-bud" 2>/dev/null)" "1"
policy block

echo "-- gate-report (Stop): o pedido pendente segura a rodada pela Ponte"
FAKE="$SB/herdr"; CALLS="$SB/calls.log"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$CALLS" > "$FAKE"; chmod +x "$FAKE"
SOCK="$SB/ponte.sock"
stop() { # stop <sid> [socket]
  SOUT=$(printf '{"session_id":"%s","stop_hook_active":false}' "$1" | env HERDR_ENV=1 HERDR_PANE_ID=w9:p9 \
    HERDR_BIN_PATH="$FAKE" PONTE_MCP_SOCKET="${2:-$SB/sem-ponte.sock}" bash "$STOP" 2>/dev/null); SRC=$?
}
gv() { sed -n "s/^$1=\(.*\)$/\1/p" "$MAESTRO_HOME/herdr/gates/w9_p9" 2>/dev/null | head -1; }
stop dm-bud
chk "sem Ponte: exit 0" "$SRC" "0"
chk "sem Ponte: nada no stdout (fluxo manual)" "$SOUT" ""
chk "gate=domain no arquivo" "$(gv gate)" "domain"
[[ "$(gv message)" == "gate domain · proj · security · pending"* ]] && ok "mensagem regida com domínio e status" || bad "mensagem: $(gv message)"
: > "$SOCK"
stop dm-bud "$SOCK"
[[ "$SOUT" == *'"decision":"block"'* && "$SOUT" == *"gate domain"* && "$SOUT" == *"timeout nao aprova"* ]] \
  && ok "com Ponte: block com a reason do gate domain" || bad "stdout: $SOUT"
[[ "$SOUT" == *"security"* || "$SOUT" == *".env"* ]] && bad "reason vazou o pedido" || ok "reason não cita o pedido"
[[ "$SOUT" == *"conduct --domain"* ]] && bad "reason manda digitar a decisão" || ok "reason não manda digitar a decisão"
stop dm-bud "$SOCK"
chk "segunda parada no TTL: não bloqueia de novo" "$SOUT" ""
stop dm-cmp "$SOCK"
chk "pedido aprovado: sem block" "$SOUT" ""
[[ -e "$MAESTRO_HOME/herdr/gates/w9_p9" ]] && bad "gate de pedido aprovado ficou de pé" || ok "aprovado: arquivo de gate some"
jq -c '.brief = "essencia: x; impacto: y; approach: pendente"' "$(REC dm-clear)" > "$SB/t" && mv "$SB/t" "$(REC dm-clear)"
stop dm-clear "$SOCK"
[[ -e "$MAESTRO_HOME/herdr/gates/w9_p9" ]] && bad "record de gate domain virou gate plan" || ok "record de gate domain nunca vira gate plan"
stop dm-ship "$SOCK"
chk "gate ship de sempre" "$(gv gate)" "ship"

echo "-- injeção do SessionStart: o gate domain chega ao gerente"
INJ=$(printf '{"session_id":"dm-inj"}' | MAESTRO_HOME="$SB/h-inj" CLAUDE_PROJECT_DIR="$SB/p-inj" \
  PONTE_MCP_SOCKET="$SB/sem-ponte.sock" bash "$SS" 2>/dev/null)
[[ "$INJ" == *"- gate domain (feature, refactor): plano segue sem humano"* ]] && ok "bullet do gate domain" || bad "bullet ausente"
[[ "$INJ" != *"gate plan ("* ]] && ok "sem gate plan na injeção" || bad "gate plan ainda injetado"
[[ "$INJ" != *"pendente vale"* ]] && ok "sem 'pendente vale' sem gate plan" || bad "injeção ensina approach pendente"
[[ "$INJ" == *"- gate ship (ship)"* ]] && ok "gate ship intacto" || bad "gate ship sumiu"
[[ "$INJ" == *"- infra (opus)"* ]] && ok "infra no roster injetado" || bad "infra fora do roster"

exit $fail
