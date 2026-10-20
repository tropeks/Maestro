#!/usr/bin/env bash
# E28 — diretoria por domínio: `gate: domain` em feature/refactor.
#
# Prova o que o pacote pede (tropeks/spock:docs/ideias/especialistas/projetos/
# 03-Maestro.md): plano sem domínio segue sem gate; plano que toca `.env` pede
# decisão de segurança; plano que toca `compose` pede decisão de infra;
# `gate: ship` não muda. E o resto do contrato: pedido com os campos mínimos
# (nenhum placeholder), decisão espelhada pelo `conduct --domain-decision`
# com as recusas, suspensão SÓ da mutação dependente no pre-tool-gate e o
# Stop (gate-report) segurando a rodada pela Ponte — timeout nunca aprova.
#
# Hermético: MAESTRO_HOME, projeto e herdr falso em mktemp -d.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
GATE="$REPO/hooks/pre-tool-gate.sh"
STOP="$REPO/hooks/gate-report.sh"
SS="$REPO/hooks/session-start.sh"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

SB=$(mktemp -d)
trap '[[ $$ == $BASHPID ]] && rm -rf "$SB"' EXIT
export MAESTRO_HOME="$SB/home" MAESTRO_NO_UPDATE_CHECK=1
P="$SB/proj"; mkdir -p "$P/.maestro" "$MAESTRO_HOME/sessions" "$MAESTRO_HOME/logs"
export CLAUDE_PROJECT_DIR="$P"
cat > "$P/.maestro/INTENT.md" <<'EOF'
<!-- maestro-intent
version: 7
hash: 00000000
-->
## Problema
p
EOF

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
  --targets ".env.example,src/config.ts" --effects "variavel nova no ambiente" --rollback "git revert do commit" --order 110
chk "exit 0" "$RC" "0"
R="$(REC dm-env)"
chk "status pending" "$(jq -r '.domain.status' "$R")" "pending"
chk "um pedido, de security" "$(jq -r '[.domain.requests[].domain] | join(",")' "$R")" "security"
chk "scope = targets" "$(jq -r '.domain.scope' "$R")" ".env.example src/config.ts"
chk "campos do contrato mínimo" "$(jq -r '.domain.requests[0] | keys | join(",")' "$R")" \
  "domain,effects,intent,order_ref,plan,project,request_id,rollback_ref,targets"
chk "order_ref" "$(jq -r '.domain.requests[0].order_ref' "$R")" "110"
chk "intent.version" "$(jq -r '.domain.requests[0].intent.version' "$R")" "7"
want=$(sed '1,/^-->$/d' "$P/.maestro/INTENT.md" | sha256sum | head -c 8)
chk "intent.hash = hash do corpo (core-intent.sh)" "$(jq -r '.domain.requests[0].intent.hash' "$R")" "$want"
[[ "$(jq -r '.domain.requests[0].plan.hash' "$R")" =~ ^[0-9a-f]{64}$ ]] && ok "plan.hash sha256" || bad "plan.hash"
[[ "$OUT" == *"pedido: {"* && "$OUT" == *"director.ask"* && "$OUT" == *"timeout não aprova"* ]] \
  && ok "decide imprime o pedido e o caminho pela Ponte" || bad "saída: $OUT"
[[ "$(head -c 4096 "$R")" == *'"domain":{"status":"pending","scope":'* ]] \
  && ok "status e scope dentro da janela de 4 KiB do gate" || bad "domain fora da janela do gate"

echo "-- plano que toca compose: pedido de infra"
decide --session dm-cmp --workflow refactor --mode direct \
  --brief "essencia: servico novo; impacto: x; approach: container novo no stack" \
  --targets "deploy/compose.prod.yaml" --effects "sobe container" --rollback "docs/rollback.md"
chk "exit 0" "$RC" "0"
chk "pedido de infrastructure" "$(jq -r '[.domain.requests[].domain] | join(",")' "$(REC dm-cmp)")" "infrastructure"

echo "-- gatilho por palavra do plano, sem caminho"
decide --session dm-kw --workflow feature --mode direct \
  --brief "essencia: api; impacto: x; approach: libera CORS para o app" \
  --targets "src/api/server.ts" --effects "origem nova aceita" --rollback "git revert"
chk "cors → security" "$(jq -r '[.domain.requests[].domain] | join(",")' "$(REC dm-kw)")" "security"
decide --session dm-df --workflow feature --mode direct \
  --brief "essencia: imagem; impacto: x; approach: Dockerfile roda como USER app" \
  --targets "Dockerfile" --effects "imagem nova" --rollback "tag anterior"
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
  --brief "essencia: x; impacto: y; approach: le .env" --targets ".env" --effects "e" --rollback "r"
chk "sem INTENT carimbado: exit 1" "$RC" "1"
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

echo "-- conduct --domain-decision: espelho da decisão da Ponte"
RID=$(jq -r '.domain.requests[0].request_id' "$(REC dm-env)")
IH=$(jq -r '.domain.requests[0].intent.hash' "$(REC dm-env)")
VU=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
dec() { # dec <decision_id> <response> <role> <domain|null> [valid_until] [intent_hash]
  jq -nc --arg did "$1" --arg rid "$RID" --arg r "$2" --arg role "$3" --arg d "$4" \
     --arg vu "${5:-$VU}" --arg ih "${6:-$IH}" '
    {decision_id:$did, request_id:$rid, response:$r,
     conditions:(if $r == "approved_with_conditions" then ["sem segredo no log"] else [] end),
     reason:"plano verificado", decided_by:{role:$role, domain:(if $d == "null" then null else $d end), label:"diretor-seguranca"},
     policy_ref:"MANDATOS.md#security", intent:{version:7, hash:$ih}, valid_until:$vu}'
}
cdd() { OUT=$("$BIN" conduct --session dm-env --domain-decision "$1" 2>&1); RC=$?; }
cdd "$(dec d1 approved director_domain infrastructure)"
chk "diretor de outro domínio: exit 1" "$RC" "1"
cdd "$(dec d1 approved mechanical null)"
chk "aprovação mecânica (timeout) recusada" "$RC" "1"
[[ "$OUT" == *"timeout nunca aprova"* ]] && ok "motivo: timeout nunca aprova" || bad "saída: $OUT"
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
chk "recusas não mexem no status" "$(jq -r '.domain.status' "$(REC dm-env)")" "pending"
cdd "$(dec d1 needs_evidence director_domain security)"
chk "needs_evidence: exit 0" "$RC" "0"
chk "status needs_evidence" "$(jq -r '.domain.status' "$(REC dm-env)")" "needs_evidence"
cdd "$(dec d2 approved_with_conditions director_domain security)"
chk "aprovado com condição depois da evidência: exit 0" "$RC" "0"
chk "status approved_with_conditions" "$(jq -r '.domain.status' "$(REC dm-env)")" "approved_with_conditions"
cdd "$(dec d3 denied director_domain security)"
chk "segunda resolução de pedido resolvido recusada" "$RC" "1"
"$BIN" conduct --session dm-env --approach "outro plano" >/dev/null 2>&1
chk "conduct --approach em record de gate domain: exit 1" "$?" "1"
grep -q '"cmd":"domain_approved_with_conditions"' "$MAESTRO_HOME/logs/routing.jsonl" \
  && ok "log só com metadado (cmd=domain_<response>)" || bad "log do conduct"

echo "-- re-decide: mesmo plano preserva a decisão; plano novo reabre o pedido"
"$BIN" decide --session dm-env --workflow feature --mode direct \
  --brief "essencia: chave nova; impacto: integra x; approach: le a chave no boot" \
  --targets ".env.example,src/config.ts" --effects "variavel nova no ambiente" --rollback "git revert do commit" --order 110 >/dev/null 2>&1
chk "mesmo plano: status mantido" "$(jq -r '.domain.status' "$(REC dm-env)")" "approved_with_conditions"
"$BIN" decide --session dm-env --workflow feature --mode direct \
  --brief "essencia: chave nova; impacto: integra x; approach: le a chave e grava em disco" \
  --targets ".env.example,src/config.ts" --effects "variavel nova no ambiente" --rollback "git revert do commit" >/dev/null 2>&1
chk "plano novo: pending de novo" "$(jq -r '.domain.status' "$(REC dm-env)")" "pending"
chk "plano novo: decisão velha não vale" "$(jq '.domain.decisions // [] | length' "$(REC dm-env)")" "0"

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
) || fail=1

echo "-- pre-tool-gate: só a mutação dependente fica suspensa"
policy() { printf 'MAESTRO_GATE_MODE="%s"\nMAESTRO_GATE_ALLOW_EXT=".md .txt"\nMAESTRO_GATE_ALLOW_PATHS=".maestro/ docs/"\nMAESTRO_GATE_DENY_PATHS=".claude/"\nMAESTRO_PLUGIN_ROOT="/opt/maestro-plugin"\n' "$1" > "$MAESTRO_HOME/gate-policy.sh"; }
edit() { # edit <sid> <caminho relativo>
  GERR=$(printf '{"tool_name":"Edit","session_id":"%s","tool_input":{"file_path":"%s/%s"}}' "$1" "$P" "$2" | bash "$GATE" 2>&1 >/dev/null)
  GRC=$?
}
policy block
edit dm-env ".env.example"
chk "block: alvo do pedido pendente → exit 2" "$GRC" "2"
[[ "$GERR" == *"gate domain"* && "$GERR" == *"Timeout não aprova"* ]] && ok "mensagem diz o caminho" || bad "stderr: $GERR"
edit dm-env "src/outra.ts"
chk "block: fora dos alvos do plano → passa" "$GRC" "0"
edit dm-cmp "deploy/compose.prod.yaml"
chk "block: compose do pedido de infra pendente → exit 2" "$GRC" "2"
edit dm-clear "src/ui/perfil.tsx"
chk "block: plano sem domínio → passa" "$GRC" "0"
policy warn
edit dm-env ".env.example"
chk "warn: alvo pendente → passa com aviso" "$GRC" "0"
[[ "$GERR" == *"aviso"* ]] && ok "aviso no stderr" || bad "stderr: $GERR"
tail -1 "$MAESTRO_HOME/logs/routing.jsonl" | grep -q '"cmd":"domain_pending"' && ok "gate_warn com cmd=domain_pending" || bad "log do gate"
policy block
"$BIN" conduct --session dm-cmp --domain-decision "$(RID=$(jq -r '.domain.requests[0].request_id' "$(REC dm-cmp)"); \
  jq -nc --arg rid "$RID" --arg vu "$VU" --arg ih "$IH" '{decision_id:"i1", request_id:$rid, response:"approved", conditions:[], reason:"ok",
   decided_by:{role:"director_domain", domain:"infrastructure", label:"diretor-infra"}, policy_ref:"MANDATOS.md#infrastructure",
   intent:{version:7, hash:$ih}, valid_until:$vu}')" >/dev/null 2>&1
chk "infra aprovado" "$(jq -r '.domain.status' "$(REC dm-cmp)")" "approved"
edit dm-cmp "deploy/compose.prod.yaml"
chk "block: alvo com pedido aprovado → passa" "$GRC" "0"

echo "-- gate-report (Stop): o pedido pendente segura a rodada pela Ponte"
FAKE="$SB/herdr"; CALLS="$SB/calls.log"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$CALLS" > "$FAKE"; chmod +x "$FAKE"
SOCK="$SB/ponte.sock"
stop() { # stop <sid> [socket]
  SOUT=$(printf '{"session_id":"%s","stop_hook_active":false}' "$1" | env HERDR_ENV=1 HERDR_PANE_ID=w9:p9 \
    HERDR_BIN_PATH="$FAKE" PONTE_MCP_SOCKET="${2:-$SB/sem-ponte.sock}" bash "$STOP" 2>/dev/null); SRC=$?
}
gv() { sed -n "s/^$1=\(.*\)$/\1/p" "$MAESTRO_HOME/herdr/gates/w9_p9" 2>/dev/null | head -1; }
stop dm-env
chk "sem Ponte: exit 0" "$SRC" "0"
chk "sem Ponte: nada no stdout (fluxo manual)" "$SOUT" ""
chk "gate=domain no arquivo" "$(gv gate)" "domain"
[[ "$(gv message)" == "gate domain · proj · security · pending"* ]] && ok "mensagem regida com domínio e status" || bad "mensagem: $(gv message)"
: > "$SOCK"
stop dm-env "$SOCK"
[[ "$SOUT" == *'"decision":"block"'* && "$SOUT" == *"gate domain"* && "$SOUT" == *"timeout nao aprova"* ]] \
  && ok "com Ponte: block com a reason do gate domain" || bad "stdout: $SOUT"
[[ "$SOUT" == *"security"* || "$SOUT" == *".env"* ]] && bad "reason vazou o pedido" || ok "reason não cita o pedido"
stop dm-env "$SOCK"
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
[[ "$INJ" == *"- gate ship (ship)"* ]] && ok "gate ship intacto" || bad "gate ship sumiu"
[[ "$INJ" == *"- infra (opus)"* ]] && ok "infra no roster injetado" || bad "infra fora do roster"

exit $fail
