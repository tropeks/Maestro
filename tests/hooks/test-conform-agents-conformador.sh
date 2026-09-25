#!/usr/bin/env bash
# ordem 042 (Parte B) — envelope agents/conformador.md: frontmatter válido
# (mesmo contrato de tests/hooks/test-roster.sh, ordem 039), fora do roster
# INJETADO pelo session-start (projeto com `experts:` — como o próprio
# Maestro) e fora de config/routing-table.yaml, e o corpo nomeia as
# proibições (gate, aceite, merge, ship, ponte.db) e os dois canais de
# pergunta (`/rc` na sessão · `director_ask`).
#
# `agents/` está na denylist do gate (mesma classe de `bin/`) — o arquivo só
# existe hoje em docs/patches/042-conform-agents-conformador.patch. A
# sandbox (tests/lib/conform-sandbox.sh) aplica o patch numa CÓPIA do
# roster; o teste roda de verdade agora e continua rodando depois que o
# Capitão aplicar o patch no repo real (detecta o arquivo já presente e não
# reaplica).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/conform-sandbox.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
info(){ printf 'info %s\n' "$1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
conform_sandbox_agents "$REPO" "$TMP" || { echo "FAIL sandbox: agents não montou"; exit 1; }
F="$AGENTS_SANDBOX/conformador.md"
[[ -f "$F" ]] && ok "agents/conformador.md existe na sandbox (patch aplicado)" \
  || { echo "FAIL: patch não gerou o arquivo"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Frontmatter — mesmo contrato de tests/hooks/test-roster.sh (ordem 039):
#    abre/fecha com ---, name casa com o arquivo, description de uma linha,
#    model no vocabulário fechado, tools com Agent/Skill e as três director_*
#    (o envelope roda como persona de sessão `--agent`, não como subagente).
# ---------------------------------------------------------------------------
# uma linha só: o corpo multi-linha do awk (chaves em várias linhas) confunde
# o contador de função do próprio habit hook (oversized-function não distingue
# `{`/`}` do awk embutido dos do bash) — mesma armadilha da regra de heredoc.
fm() { awk -v k="$1" 'FNR==1 && /^---[ \t]*$/{st=1;next} st==1 && /^---[ \t]*$/{exit} st==1 && index($0,k":")==1{v=substr($0,length(k)+2);gsub(/^[ \t]+|[ \t]+$/,"",v);print v;exit}' "$2"; }

[[ "$(fm name "$F")" == "conformador" ]] && ok "name casa com o arquivo" || bad "name não casa"
DESC="$(fm description "$F")"
[[ -n "$DESC" && "$DESC" != "|"* && "$DESC" != ">"* ]] && ok "description de uma linha, não vazia" \
  || bad "description vazia ou em bloco escalar"
MODEL="$(fm model "$F")"
case "$MODEL" in
  sonnet|opus) ok "model=$MODEL (vocabulário fechado)" ;;
  *) bad "model='$MODEL' fora de {sonnet,opus}" ;;
esac
EFFORT="$(fm effort "$F")"
[[ "$EFFORT" == "alto" || "$EFFORT" == "baixo" || -z "$EFFORT" ]] && ok "effort (se presente) no vocabulário da ordem 039" \
  || bad "effort='$EFFORT' fora de {baixo,alto}"
TOOLS="$(fm tools "$F")"
# Decisão do Diretor (25/09): numa sessão `--agent`, o que não está em tools:
# não existe — sem Agent/Skill não há swarm, sem director_* não há pergunta nem relato.
for t in Agent Skill mcp__plugin_maestro_ponte__director_ask mcp__plugin_maestro_ponte__director_wait mcp__plugin_maestro_ponte__director_report; do
  [[ ", $TOOLS," == *", $t,"* ]] && ok "tools traz $t" || bad "tools sem $t: $TOOLS"
done
[[ "$TOOLS" != *"Task"* ]] && ok "tools sem Task" || bad "tools inclui Task: $TOOLS"
[[ -n "$TOOLS" ]] && ok "tools não vazio" || bad "tools vazio"

# ---------------------------------------------------------------------------
# 2. Fora de config/routing-table.yaml.
# ---------------------------------------------------------------------------
if grep -q "conformador" "$REPO/config/routing-table.yaml" 2>/dev/null; then
  bad "conformador aparece em config/routing-table.yaml — não deveria"
else
  ok "conformador NÃO está em config/routing-table.yaml"
fi

# ---------------------------------------------------------------------------
# 3. Fora do roster INJETADO pelo session-start — projeto com `experts:`
#    (o próprio Maestro: experts: [dev-junior, dev-pleno, engenheiro,
#    typescript-pro, qa, revisor] — sem conformador).
# ---------------------------------------------------------------------------
IN=$(mktemp)
printf '{"session_id":"ses_conform042","hook_event_name":"SessionStart"}' > "$IN"
OUT=$(env MAESTRO_HOME="$(mktemp -d)" CLAUDE_PROJECT_DIR="$REPO" MAESTRO_AGENTS_DIR="$AGENTS_SANDBOX" \
  bash "$REPO/hooks/session-start.sh" < "$IN" 2>/tmp/conform-envelope-err)
[[ "$OUT" != *"- conformador ("* ]] && ok "projeto com experts: (o próprio Maestro) não injeta conformador" \
  || bad "conformador vazou na injeção do próprio Maestro"

# Nota de arquitetura (não é falha deste teste): projeto SEM `experts:`
# recebe o roster INTEIRO por padrão (S-303) — isso vale para QUALQUER
# agents/*.md novo, não é um problema introduzido por este envelope. Fechar
# esse caso exigiria mudar hooks/session-start.sh (CONGELADO nesta ordem) ou
# uma curadoria de `experts:` feita pelo Capitão ao instalar o patch —
# registrado no relato da ordem, não neste teste.
info "projeto SEM experts: injeta o roster inteiro por padrão (S-303) — mitigação é o Capitão declarar experts: ao aplicar o patch, não um mecanismo novo desta ordem"

# ---------------------------------------------------------------------------
# 4. O corpo nomeia as proibições e os dois canais.
# ---------------------------------------------------------------------------
BODY=$(awk 'f{print} /^---$/{c++; if(c==2)f=1}' "$F")
for termo in "gate" "aceitar ordem" "merge" "ship" "ponte.db"; do
  echo "$BODY" | grep -qi -- "$termo" && ok "corpo nomeia a proibição: $termo" || bad "corpo NÃO nomeia: $termo"
done
echo "$BODY" | grep -q "director_ask" && ok "corpo nomeia o canal director_ask" || bad "corpo não nomeia director_ask"
echo "$BODY" | grep -q "/rc" && ok "corpo nomeia o canal /rc (sessão do Capitão)" || bad "corpo não nomeia /rc"
echo "$BODY" | grep -qi "claude --agent" && ok "corpo diz que roda como persona de sessão (não subagente)" \
  || bad "corpo não explica a persona de sessão"

if (( fail == 0 )); then echo "OK: test-conform-agents-conformador"; else echo "FALHOU: test-conform-agents-conformador" >&2; fi
exit $fail
