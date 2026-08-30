#!/usr/bin/env bash
# S-203 — gate estrutural (hooks/pre-tool-gate.sh).
#
# Cobre as ACs do EPICS S-203 + a lógica normativa do API_SPEC §1 + a
# autoproteção do ADR-003 v1.1 / review P1-3, e os fixtures adversariais (S-204).
#
# Isolamento: MAESTRO_HOME em mktemp -d. O ~/.maestro real NUNCA é tocado.
# Projeto sintético /home/user/proj e plugin /opt/maestro-plugin: o gate resolve
# caminho de forma 100% léxica, então nada precisa existir em disco.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO/hooks/pre-tool-gate.sh"
FIX="$REPO/tests/fixtures"
PROJ="/home/user/proj"
PLUGIN="/opt/maestro-plugin"

fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export MAESTRO_HOME="$TMP/home"
export CLAUDE_PROJECT_DIR="$PROJ"
mkdir -p "$MAESTRO_HOME/sessions" "$MAESTRO_HOME/logs"

# --- política compilada (CONTRATO §2) --------------------------------------
write_policy() { # $1 = warn|block
  cat > "$MAESTRO_HOME/gate-policy.sh" <<EOF
# gerado por maestro session-start — nao editar
MAESTRO_GATE_MODE="${1:-warn}"
MAESTRO_GATE_ALLOW_EXT=".md .txt"
MAESTRO_GATE_ALLOW_PATHS=".maestro/ docs/"
MAESTRO_GATE_DENY_PATHS="agents/ bin/ hooks/ config/routing-table.yaml .claude/ .claude-plugin/ .github/workflows/"
MAESTRO_PLUGIN_ROOT="$PLUGIN"
EOF
}

# --- decision record (CONTRATO §3) -----------------------------------------
write_record() { # $1 = session_id, $2 = offset em segundos p/ expires_at
  local sid="$1" off="${2:-14400}" now exp
  now=$(date -Iseconds)
  exp=$(date -Iseconds -d "@$(( $(date +%s) + off ))")
  cat > "$MAESTRO_HOME/sessions/$sid.json" <<EOF
{"session_id":"$sid","ts":"$now","expires_at":"$exp","workflow":"fix","mode":"subagent","agents":["golang-pro"],"reason":"teste"}
EOF
}

LOG="$MAESTRO_HOME/logs/routing.jsonl"
reset_log() { : > "$LOG"; }
last_event() { tail -1 "$LOG" 2>/dev/null | jq -r '.event // ""' 2>/dev/null; }
log_lines()  { wc -l < "$LOG" 2>/dev/null | tr -d ' '; }

# run <fixture> -> define RC / OUT_ERR
run() {
  OUT_ERR=$("$GATE" < "$FIX/$1" 2>&1 >/dev/null)
  RC=$?
}
# run_payload <json string>
run_payload() {
  OUT_ERR=$(printf '%s' "$1" | "$GATE" 2>&1 >/dev/null)
  RC=$?
}

echo "-- S-203: modo warn (default)"
write_policy warn
reset_log
run edit-go.json
check "editar .go sem decisão → exit 0 (warn)" "$RC" "0"
check "editar .go sem decisão → evento gate_warn" "$(last_event)" "gate_warn"
if [[ "$OUT_ERR" == *"maestro decide"* ]]; then
  ok "warn traz mensagem instrutiva no stderr"
else
  bad "warn sem mensagem instrutiva (stderr='$OUT_ERR')"
fi
if [[ "$OUT_ERR" == *"MAESTRO_OFF"* ]]; then
  bad "mensagem divulga o kill-switch ao modelo (review P1-3)"
else
  ok "mensagem não divulga o kill-switch ao modelo"
fi

echo "-- S-203: modo block"
write_policy block
reset_log
run edit-go.json
check "editar .go sem decisão em mode=block → exit 2" "$RC" "2"
check "mode=block → evento gate_block" "$(last_event)" "gate_block"

echo "-- S-203: decisão válida libera código"
write_policy warn
write_record sess-abc123 14400
reset_log
run edit-go.json
check "com decisão válida → exit 0" "$RC" "0"
check "com decisão válida → evento gate_pass" "$(last_event)" "gate_pass"
run multiedit-ts.json
check "MultiEdit com decisão válida → exit 0" "$RC" "0"

echo "-- S-203: TTL 4h (record expirado não vale)"
write_record sess-abc123 -60      # expires_at no passado
reset_log
run edit-go.json
check "record expirado → não libera (warn)" "$RC" "0"
check "record expirado → gate_warn, não gate_pass" "$(last_event)" "gate_warn"
write_policy block
run edit-go.json
check "record expirado em mode=block → exit 2" "$RC" "2"
write_policy warn
write_record sess-abc123 14400

echo "-- S-203/P1-3: denylist bloqueia SEMPRE (mesmo com decisão válida)"
for f in deny-routing-table deny-hooks-lib deny-bin deny-claude-settings \
         deny-agents deny-workflow deny-plugin-abs deny-traversal-in deny-dotslash; do
  reset_log
  run "$f.json"
  check "denylist: $f → exit 2" "$RC" "2"
  check "denylist: $f → gate_block" "$(last_event)" "gate_block"
done
if [[ "$OUT_ERR" == *"denylist"* ]]; then
  ok "block da denylist explica o motivo no stderr"
else
  bad "block da denylist sem mensagem (stderr='$OUT_ERR')"
fi

echo "-- denylist vence a allowlist"
reset_log
run edit-md-in-hooks.json
check "hooks/README.md (.md na allowlist) → block mesmo assim" "$RC" "2"
check "hooks/README.md → gate_block" "$(last_event)" "gate_block"

echo "-- denylist em mode=block continua 2, e sai 2 sem decisão nenhuma"
write_policy block
run deny-hooks-lib.json
check "denylist em mode=block → exit 2" "$RC" "2"
write_policy warn

echo "-- S-203: allowlist de não-código"
reset_log
run edit-md-root.json
check "editar .md fora da denylist → exit 0" "$RC" "0"
check "allowlist não gera evento no log" "$(log_lines)" "0"
run edit-docs-yaml.json
check "docs/plano.yaml (caminho na allowlist) → exit 0" "$RC" "0"
# P1-3: .json/.yaml deixaram de ser "não-código" → exigem decisão
rm -f "$MAESTRO_HOME/sessions/sess-abc123.json"
reset_log
run edit-json-src.json
check "package.json fora de docs/ → exige decisão (gate_warn)" "$(last_event)" "gate_warn"
write_record sess-abc123 14400

echo "-- falso positivo: prefixo parecido e projeto alheio"
for f in lookalike-hooksfoo lookalike-binary other-project-agents escape-above-project; do
  run "$f.json"
  check "sem falso positivo: $f → exit 0" "$RC" "0"
done

echo "-- travessia de diretório"
run adv-traversal.json      # ../../../../etc/passwd → sai do projeto, não trava
check "travessia p/ fora do projeto → exit 0" "$RC" "0"
run deny-traversal-in.json  # docs/../hooks/ → volta p/ caminho protegido
check "travessia p/ DENTRO de caminho protegido → exit 2" "$RC" "2"

echo "-- degradação: nada disso pode bloquear"
# política ausente
mv "$MAESTRO_HOME/gate-policy.sh" "$TMP/policy.bak"
run deny-hooks-lib.json
check "política ausente → exit 0 (degrada)" "$RC" "0"
# política ilegível
: > "$MAESTRO_HOME/gate-policy.sh"; chmod 000 "$MAESTRO_HOME/gate-policy.sh"
run deny-hooks-lib.json
check "política ilegível → exit 0 (degrada)" "$RC" "0"
chmod 644 "$MAESTRO_HOME/gate-policy.sh"
# política com sintaxe quebrada
printf 'MAESTRO_GATE_MODE="warn\nif then fi(\n' > "$MAESTRO_HOME/gate-policy.sh"
run edit-go.json
check "política com sintaxe quebrada → exit 0 (degrada)" "$RC" "0"
# política parcial: denylist ausente NÃO desarma a autoproteção
printf 'MAESTRO_GATE_MODE="warn"\n' > "$MAESTRO_HOME/gate-policy.sh"
# Sem MAESTRO_PLUGIN_ROOT na política, o gate deriva a raiz da própria localização:
# política parcial NÃO pode desarmar a autoproteção.
run_payload "$(jq -nc --arg p "$REPO/hooks/lib/common.sh" \
  '{session_id:"sess-abc123",tool_name:"Edit",tool_input:{file_path:$p}}')"
check "política parcial → autoproteção do plugin ainda bloqueia" "$RC" "2"
cp "$TMP/policy.bak" "$MAESTRO_HOME/gate-policy.sh"
# jq ausente: PATH sandbox com coreutils, sem jq (não dá para esvaziar o PATH —
# `env bash` do shebang some junto e o teste viraria um falso 127).
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
for c in bash env cat date dirname stat flock mkdir mv grep sed head tail wc tr sort seq chmod ls; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$NOJQ/$c"
done
if command -v jq >/dev/null 2>&1 && ! PATH="$NOJQ" command -v jq >/dev/null 2>&1; then
  ok "sandbox sem jq montado"
else
  bad "sandbox sem jq não ficou de pé"
fi
OUT_ERR=$(PATH="$NOJQ" "$GATE" < "$FIX/deny-hooks-lib.json" 2>&1 >/dev/null); RC=$?
check "jq ausente → exit 0 (degrada)" "$RC" "0"
# MAESTRO_HOME read-only (log inacessível) não pode derrubar o hook
mkdir -p "$TMP/ro"; chmod 500 "$TMP/ro"
OUT_ERR=$(MAESTRO_HOME="$TMP/ro" "$GATE" < "$FIX/edit-go.json" 2>&1 >/dev/null); RC=$?
check "MAESTRO_HOME read-only → exit 0 (sem política, degrada)" "$RC" "0"
chmod 700 "$TMP/ro"
# kill-switch continua soberano, inclusive sobre a denylist
OUT_ERR=$(MAESTRO_OFF=1 "$GATE" < "$FIX/deny-hooks-lib.json" 2>&1); RC=$?
check "MAESTRO_OFF=1 sobre a denylist → exit 0" "$RC" "0"
check "MAESTRO_OFF=1 → sem saída" "$OUT_ERR" ""
# CLAUDE_PROJECT_DIR ausente: sem raiz não há denylist relativa, mas o plugin
# continua protegido em termos absolutos.
OUT_ERR=$(env -u CLAUDE_PROJECT_DIR "$GATE" < "$FIX/deny-plugin-abs.json" 2>&1 >/dev/null); RC=$?
check "sem CLAUDE_PROJECT_DIR → plugin ainda protegido (exit 2)" "$RC" "2"
OUT_ERR=$(CLAUDE_PROJECT_DIR=/ "$GATE" < "$FIX/edit-go.json" 2>&1 >/dev/null); RC=$?
check "CLAUDE_PROJECT_DIR=/ não transforma tudo em caminho do projeto" "$RC" "0"

echo "-- fixtures adversariais (S-204): nunca trava, nunca vaza caminho"
reset_log
adv_fail=0
for f in "$FIX"/*.json; do
  b="$(basename "$f")"
  OUT_ERR=$("$GATE" < "$f" 2>&1 >/dev/null); rc=$?
  if [[ $rc -ne 0 && $rc -ne 2 ]]; then
    bad "adversarial $b saiu com rc=$rc (só 0 ou 2 são aceitáveis)"; adv_fail=1
  fi
  case "$b" in
    deny-*) [[ $rc -eq 2 ]] || { bad "adversarial $b deveria bloquear"; adv_fail=1; } ;;
    adv-*|lookalike-*|other-*|escape-*) \
      [[ $rc -eq 0 ]] || { bad "adversarial $b não podia bloquear (rc=$rc)"; adv_fail=1; } ;;
  esac
done
[[ $adv_fail -eq 0 ]] && ok "todos os $(ls -1 "$FIX"/*.json | wc -l | tr -d ' ') fixtures saem com código previsto"

# Nenhum efeito colateral de injeção pode ter acontecido.
if [[ -e /tmp/maestro-pwned ]]; then
  bad "fixture de injeção executou comando (/tmp/maestro-pwned criado)"; rm -f /tmp/maestro-pwned
else
  ok "fixture de injeção via nome de arquivo não executou nada"
fi

# O log inteiro é auditado: nenhuma linha pode conter '/' fora de ts, nem
# fragmento de caminho, nem valor de chave não prevista.
leak=0
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  if ! printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
    bad "linha de log não é JSON válido: $line"; leak=1; continue
  fi
  vals=$(printf '%s' "$line" | jq -r 'del(.ts) | to_entries[] | .value | tostring')
  if printf '%s' "$vals" | grep -q '/'; then
    bad "log vazou '/' (caminho): $line"; leak=1
  fi
  for frag in proj etc passwd segmento relat home user opt maestro-plugin; do
    if printf '%s' "$vals" | grep -qi -- "$frag"; then
      bad "log vazou fragmento de caminho '$frag': $line"; leak=1
    fi
  done
  keys=$(printf '%s' "$line" | jq -r 'keys[]')
  for k in $keys; do
    case "$k" in
      ts|event|tool|file_ext|session_id|gate_mode) ;;
      *) bad "log com chave fora do contrato: '$k'"; leak=1 ;;
    esac
  done
done < "$LOG"
[[ $leak -eq 0 ]] && ok "nenhum caminho vazou para o log em $(log_lines) eventos adversariais"

# session_id adversarial (com '/', ou >64 chars) não pode entrar no log.
reset_log
run adv-sid-injection.json
if grep -q 'session_id' "$LOG"; then bad "session_id com '/' foi logado"; else ok "session_id com '/' rejeitado no log"; fi
reset_log
run adv-sid-long.json
if grep -q 'session_id' "$LOG"; then bad "session_id de 300 chars foi logado"; else ok "session_id gigante rejeitado no log"; fi
reset_log
run adv-tool-weird.json
if grep -q '"tool"' "$LOG"; then bad "tool_name com metacaracteres foi logado"; else ok "tool_name inválido rejeitado no log"; fi
reset_log
run adv-ext-bogus.json
if grep -q 'file_ext' "$LOG"; then bad "extensão de 20 chars foi logada"; else ok "extensão fora do contrato rejeitada no log"; fi
reset_log
run adv-dotfile.json
if grep -q 'file_ext' "$LOG"; then bad ".gitignore virou file_ext"; else ok ".gitignore não produz file_ext"; fi

echo "-- caminho patológico (acima do teto de normalização)"
# limpo e muito profundo: continua sendo casado com exatidão, sem over-block
long_clean="$PROJ/src"
for _ in $(seq 1 40); do long_clean="$long_clean/segmento-bem-comprido-para-inchar-o-caminho"; done
run_payload "$(jq -n --arg p "$long_clean/x.go" '{session_id:"sess-abc123",tool_name:"Edit",tool_input:{file_path:$p}}')"
check "caminho longo limpo fora da denylist → exit 0" "$RC" "0"
long_deny="$PROJ/hooks"
for _ in $(seq 1 40); do long_deny="$long_deny/segmento-bem-comprido-para-inchar-o-caminho"; done
run_payload "$(jq -n --arg p "$long_deny/x.go" '{session_id:"sess-abc123",tool_name:"Edit",tool_input:{file_path:$p}}')"
check "caminho longo limpo dentro de hooks/ → exit 2" "$RC" "2"
# sujo: travessia usada como enchimento para estourar o teto e cair em hooks/
long_dirty="$PROJ/src"
for _ in $(seq 1 40); do long_dirty="$long_dirty/segmento-bem-comprido-para-inchar/.."; done
run_payload "$(jq -n --arg p "$long_dirty/../hooks/gate.sh" '{session_id:"sess-abc123",tool_name:"Edit",tool_input:{file_path:$p}}')"
check "travessia usada como enchimento p/ furar o teto → exit 2" "$RC" "2"

echo "-- caminho relativo é resolvido contra CLAUDE_PROJECT_DIR"
reset_log
run edit-relative.json
check "file_path relativo → tratado como do projeto (gate_pass)" "$(last_event)" "gate_pass"
run_payload '{"session_id":"sess-abc123","tool_name":"Edit","tool_input":{"file_path":"hooks/x.sh"}}'
check "file_path relativo dentro da denylist → exit 2" "$RC" "2"

echo "-- integração com a política REAL compilada pelo session-start (CONTRATO §2)"
# Não é mock: gera a política a partir de config/routing-table.yaml pelo caminho
# de produção e confere que o gate a honra. Pula (sem falhar) se o session-start
# ainda não compilar política — o GATE não pode depender do relógio do SESSION.
IHOME="$TMP/integra"; mkdir -p "$IHOME"
MAESTRO_HOME="$IHOME" CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_ROOT="$REPO" \
  "$REPO/hooks/session-start.sh" >/dev/null 2>&1 || true
if [[ -s "$IHOME/gate-policy.sh" ]]; then
  # gate.mode: block (promoção 2026-08-29): as sondas de "não é denylist" exigem
  # decision record válido — sem ele, TUDO que é código bloqueia por desenho.
  MAESTRO_HOME="$IHOME" "$REPO/bin/maestro" decide --session sess-abc123 \
    --workflow fix --mode direct >/dev/null 2>&1 || true
  # Configuração REAL: o plugin fica instalado fora do projeto do usuário
  # (~/.claude/plugins/...), então a denylist relativa é o que atua no projeto.
  igate() { # $1 = caminho absoluto, $2 = raiz do projeto → RC
    RC=0
    jq -n --arg p "$1" '{session_id:"sess-abc123",tool_name:"Edit",tool_input:{file_path:$p}}' \
      | MAESTRO_HOME="$IHOME" CLAUDE_PROJECT_DIR="$2" "$GATE" >/dev/null 2>&1 || RC=$?
  }
  # Autoproteção é ancorada no plugin: hooks/ e config/ de um projeto ALHEIO são
  # trabalho legítimo e não podem travar (seriam falso positivo — brief §8).
  igate "$PROJ/hooks/lib/common.sh" "$PROJ"
  check "projeto alheio: hooks/ local não bloqueia" "$RC" "0"
  igate "$PROJ/config/routing-table.yaml" "$PROJ"
  check "projeto alheio: config/ local não bloqueia" "$RC" "0"
  igate "$PROJ/src/app.go" "$PROJ"
  check "projeto alheio: src/ local não bloqueia" "$RC" "0"
  # ...mas alcançar o plugin INSTALADO a partir dele continua bloqueado.
  igate "$REPO/hooks/lib/common.sh" "$PROJ"
  check "de projeto alheio: alcançar hooks/ do plugin → exit 2" "$RC" "2"
  igate "$REPO/config/routing-table.yaml" "$PROJ"
  check "de projeto alheio: alcançar a routing table → exit 2" "$RC" "2"
  igate "$PROJ/.claude/settings.json" "$PROJ"
  check "política real: .claude/settings.json → exit 2" "$RC" "2"
  igate "$PROJ/README.md" "$PROJ"
  check "política real: README.md → exit 0" "$RC" "0"
  igate "$PROJ/src/algo.ts" "$PROJ"
  check "política real: src/algo.ts COM decisão → exit 0" "$RC" "0"
  # block promovido: SEM record, código bloqueia — a fresta do one-shot fechou
  RC=0
  jq -n --arg p "$PROJ/src/app.go" '{session_id:"sess-sem-record",tool_name:"Edit",tool_input:{file_path:$p}}' \
    | MAESTRO_HOME="$IHOME" CLAUDE_PROJECT_DIR="$PROJ" "$GATE" >/dev/null 2>&1 || RC=$?
  check "política real: código SEM decisão → exit 2 (block promovido)" "$RC" "2"
  # Dogfood (projeto == repo do plugin): a autoproteção cobre o caminho de
  # enforcement, NÃO a árvore inteira. Fechar o repo todo — inclusive README e
  # docs — inviabilizaria desenvolver o Maestro com agente, e o ADR-003 v1.1
  # manda proteger as regras do roteador, não cada arquivo do repo.
  igate "$REPO/README.md" "$REPO"
  check "dogfood: README.md do próprio repo passa" "$RC" "0"
  igate "$REPO/docs/PROJECT_BRIEF.md" "$REPO"
  check "dogfood: docs/ do próprio repo passa" "$RC" "0"
  igate "$REPO/hooks/pre-tool-gate.sh" "$REPO"
  check "dogfood: o próprio gate continua fechado" "$RC" "2"
  igate "$REPO/src/cli.ts" "$REPO"
  check "dogfood: o CLI continua fechado" "$RC" "2"
  if grep -q "^MAESTRO_PLUGIN_ROOT=" "$IHOME/gate-policy.sh"; then
    ok "política real declara MAESTRO_PLUGIN_ROOT (proteção absoluta do plugin)"
  else
    bad "política real sem MAESTRO_PLUGIN_ROOT"
  fi
else
  echo "     (pulado: session-start ainda não compila gate-policy.sh)"
fi

echo "-- NFR: latência < 50ms"
write_policy warn
write_record sess-abc123 14400
# Cronometragem com $EPOCHREALTIME (builtin): `date +%s%N` forkaria duas vezes
# por amostra e mediria mais o fork do que o hook.
# Critério é a MEDIANA: a máquina pode estar carregada (aqui, com outros agentes
# no mesmo repo) e uma média é refém de um único outlier de escalonamento.
measure() { # $1 = fixture  → define MED / MIN / MAX
  local f="$1" n=25 i t0 t1 ts=()
  for i in 1 2 3; do "$GATE" < "$FIX/$f" >/dev/null 2>&1; done   # aquece
  for ((i = 0; i < n; i++)); do
    t0="${EPOCHREALTIME/./}"
    "$GATE" < "$FIX/$f" >/dev/null 2>&1
    t1="${EPOCHREALTIME/./}"
    ts+=( $(( (t1 - t0) / 1000 )) )
  done
  local sorted
  mapfile -t sorted < <(printf '%s\n' "${ts[@]}" | sort -n)
  MED="${sorted[$((n / 2))]}"; MIN="${sorted[0]}"; MAX="${sorted[$((n - 1))]}"
}
# Critério: o MÍNIMO é o estimador do custo do CÓDIGO (o resto da distribuição
# é ruído de escalonamento — esta máquina é compartilhada). A mediana entra
# como guarda de regressão a 2x o orçamento: foi ela que pegou a versão em que
# `${v#*pat}` fazia o caminho de 22 KB custar 634ms.
# `adv-huge-path` (22 KB) não é carga real — nenhum arquivo tem esse caminho.
# O orçamento dele existe só para provar que o gate não degenera.
for pair in "gate_pass:edit-go.json:50" "denylist:deny-hooks-lib.json:50" \
            "allowlist:edit-md-root.json:50" "caminho-22KB(patológico):adv-huge-path.json:150"; do
  nome="${pair%%:*}"; resto="${pair#*:}"; fx="${resto%%:*}"; lim="${resto##*:}"
  measure "$fx"
  printf '     %-24s min=%sms  mediana=%sms  max=%sms  (orçamento %sms)\n' "$nome" "$MIN" "$MED" "$MAX" "$lim"
  if [[ "$MIN" -lt "$lim" ]]; then
    ok "latência <${lim}ms — $nome (min ${MIN}ms)"
  else
    bad "latência estourada — $nome (min ${MIN}ms >= ${lim}ms)"
  fi
  if [[ "$MED" -lt $(( lim * 2 )) ]]; then
    ok "sem regressão de latência — $nome (mediana ${MED}ms)"
  else
    bad "regressão de latência — $nome (mediana ${MED}ms >= $(( lim * 2 ))ms)"
  fi
done

# Sanidade final: o ~/.maestro real não foi tocado por este teste.
if [[ "$MAESTRO_HOME" == "$TMP/home" ]]; then ok "estado isolado em mktemp -d"; else bad "MAESTRO_HOME escapou do tmpdir"; fi

exit $fail
