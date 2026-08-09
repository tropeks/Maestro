#!/usr/bin/env bash
# S-205 / ADR-008 — hook UserPromptSubmit: detecta comando `/` e loga
# `override_manual` com APENAS o nome do comando.
#
# Este é o teste da métrica principal do projeto e, principalmente, da armadilha
# de privacidade: o prompt do usuário é o dado mais sensível do sistema. Os casos
# adversariais abaixo enfiam credencial, aspas, quebra de linha, JSON aninhado,
# unicode, caminho de arquivo e 10KB de texto no prompt e exigem que NADA disso
# apareça em lugar nenhum do routing.jsonl.
#
# Invariantes verificados em TODA submissão: exit 0, stdout vazio (stdout de um
# hook UserPromptSubmit é injetado no contexto do Claude) e JSONL válido.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/user-prompt-submit.sh"

tmp=$(mktemp -d)
export MAESTRO_HOME="$tmp"
LOG="$tmp/logs/routing.jsonl"
ERR="$tmp/stderr.txt"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL jq ausente — a suíte de S-205 exige jq" >&2
  exit 1
fi

# Caminhos realistas nos campos que o Claude Code manda junto do prompt: se o
# hook algum dia logar o payload cru, o grep de vazamento pega.
CWD_FAKE="/home/rcosta00/clientes/acme/proj"
payload() { # <session_id> <prompt>
  jq -nc --arg s "$1" --arg p "$2" --arg c "$CWD_FAKE" \
    '{session_id:$s, transcript_path:($c+"/transcript.jsonl"), cwd:$c,
      hook_event_name:"UserPromptSubmit", prompt:$p}'
}

log_lines() { [[ -f "$LOG" ]] && wc -l <"$LOG" | tr -d ' ' || echo 0; }
last_line() { [[ -f "$LOG" ]] && tail -1 "$LOG" || echo ""; }

# submit <descrição> <json>  → roda o hook; falha se rc≠0 ou se sujar o stdout.
submit() {
  local desc="$1" json="$2" out rc
  out=$(printf '%s' "$json" | "$HOOK" 2>"$ERR"); rc=$?
  [[ $rc -eq 0 ]]   || bad "$desc: exit $rc (devia ser 0)"
  [[ -z "$out" ]]   && ok "$desc: exit 0 e stdout vazio" \
                    || bad "$desc: escreveu em stdout ('$out') — seria injetado no contexto"
  return 0
}

# expect_cmd <descrição> <cmd esperado ou "" para nenhum> — checa a última linha.
expect_cmd() {
  local desc="$1" want="$2" line got
  line=$(last_line)
  got=$(printf '%s' "$line" | jq -r '.cmd // ""' 2>/dev/null) || got="<json invalido>"
  [[ "$got" == "$want" ]] && ok "$desc: cmd='$want'" \
                          || bad "$desc: cmd='$got', esperado '$want'"
}

expect_event() {
  local desc="$1" want="$2" got
  got=$(last_line | jq -r '.event // ""' 2>/dev/null) || got="<json invalido>"
  [[ "$got" == "$want" ]] && ok "$desc: event=$want" || bad "$desc: event='$got'"
}

echo "-- 1. caminho feliz"
before=$(log_lines)
submit "/review --fix src/" "$(payload sess-1 '/review --fix src/')"
[[ "$(log_lines)" -eq $((before+1)) ]] && ok "logou exatamente 1 linha" || bad "contagem de linhas"
expect_event "override_manual gravado" "override_manual"
expect_cmd   "só o nome do comando" "review"
[[ "$(last_line | jq -r '.session_id')" == "sess-1" ]] && ok "session_id preservado" || bad "session_id"

submit "/gstack-ship --force" "$(payload sess-1 '/gstack-ship --force')"
expect_cmd "hífen no nome do comando" "gstack-ship"
grep -qF -- "--force" "$LOG" && bad "VAZOU '--force' no log" || ok "argumento '--force' não vazou"

submit "/qa:full (com dois-pontos)" "$(payload sess-1 '/qa:full alguma coisa')"
expect_cmd "dois-pontos aceito pelo tipo cmd" "qa:full"

cmd48=$(printf 'a%.0s' $(seq 1 48))
submit "nome de comando no limite (48 chars)" "$(payload sess-1 "/$cmd48 arg")"
expect_cmd "48 chars é o limite do tipo cmd" "$cmd48"

echo "-- 2. prompt normal não é override"
before=$(log_lines)
submit "prompt sem barra" "$(payload sess-1 'corrige o bug do parser e roda os testes')"
[[ "$(log_lines)" -eq "$before" ]] && ok "prompt normal NÃO loga nada" || bad "prompt normal logou"
submit "barra no meio do prompt" "$(payload sess-1 'roda o /review depois, por favor')"
[[ "$(log_lines)" -eq "$before" ]] && ok "barra fora da posição 0 NÃO loga" || bad "barra no meio logou"
submit "espaço antes da barra" "$(payload sess-1 ' /review')"
[[ "$(log_lines)" -eq "$before" ]] && ok "prompt com espaço antes da barra NÃO loga" || bad "espaço+barra logou"

echo "-- 3. degenerados: '/', '//', '/ review' — sem lixo"
for p in '/' '//' '/ review' '/   ' '/Review' '/1234567890123456789012345678901234567890123456789'; do
  before=$(log_lines)
  submit "prompt degenerado '$(printf '%s' "$p" | tr '\n' ' ')'" "$(payload sess-1 "$p")"
  after=$(log_lines)
  if [[ "$after" -ne $((before+1)) ]]; then
    bad "degenerado '$p': esperava 1 linha (override aconteceu), veio $((after-before))"
  else
    # Contrato: par `cmd` descartado (nunca forçado), evento preservado.
    expect_cmd "degenerado '$p' sem cmd" ""
    expect_event "degenerado '$p' ainda conta p/ a métrica" "override_manual"
  fi
done

echo "-- 4. ADVERSARIAL: vazamento de prompt"
SECRETS=()
add_case() { # <descrição> <prompt> <cmd esperado> <agulha1> [agulha2...]
  local desc="$1" prompt="$2" want="$3"; shift 3
  submit "adversarial: $desc" "$(payload sess-1 "$prompt")"
  expect_cmd "adversarial: $desc" "$want"
  local s
  for s in "$@"; do SECRETS+=("$s"); done
}

add_case "credencial AWS depois do comando" \
  '/deploy AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY' \
  'deploy' 'wJalrXUtnFEMI' 'AWS_SECRET_ACCESS_KEY'

add_case "aspas simples, duplas e escapadas" \
  '/ship "aspas duplas" '"'"'aspas simples'"'"' \"escapada\" `crase`' \
  'ship' 'aspas duplas' 'crase'

add_case "quebra de linha e segredo na 2a linha" \
  "$(printf '/audit primeira linha\nsenha=hunter2\n{"tok":"ghp_LINHA3"}')" \
  'audit' 'hunter2' 'ghp_LINHA3'

add_case "JSON aninhado dentro do prompt" \
  '/fix {"password":"p4ssw0rd-embutido","db":{"host":"db.acme.internal"}}' \
  'fix' 'p4ssw0rd-embutido' 'db.acme.internal'

add_case "unicode e emoji" \
  '/refactor café — ação 日本語 🔥 ünïcödé' \
  'refactor' 'café' '日本語' 'ünïcödé'

add_case "caminho de arquivo nos argumentos" \
  '/review /home/rcosta00/clientes/acme/faturamento_segredo.py' \
  'review' 'faturamento_segredo' 'clientes'

# Prompt que COMEÇA com caminho: houve `/`, mas o token não é nome de comando
# → par descartado (jamais logar o primeiro segmento do caminho).
add_case "prompt começando com caminho absoluto" \
  '/home/rcosta00/clientes/acme/segredo.py precisa de fix' \
  '' 'segredo.py' 'rcosta00'

big=$(printf 'S%.0s' $(seq 1 10240))
add_case "prompt de 10KB" \
  "/audit $big" \
  'audit' "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSS"

add_case "backslash, \$(subshell) e ; no prompt" \
  '/ship $(rm -rf /) ; echo INJETADO \\ backslash' \
  'ship' 'INJETADO' 'rm -rf'

# 49 chars seguidos de argumento: se o hook truncasse em 48 em vez de descartar,
# um pedaço do prompt viraria `cmd`. Tem de sair sem cmd.
add_case "nome de comando com 49 chars (não pode truncar)" \
  "/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb argumento" \
  '' 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

add_case "nome de comando MAIÚSCULO com segredo" \
  '/DEPLOY token=segredo-maiusculo' \
  '' 'segredo-maiusculo' 'DEPLOY'

# prompt que não é string (JSON aninhado no CAMPO prompt)
before=$(log_lines)
submit "adversarial: campo prompt é objeto, não string" \
  '{"session_id":"sess-1","prompt":{"password":"objeto-hunter2"},"cwd":"'"$CWD_FAKE"'"}'
[[ "$(log_lines)" -eq "$before" ]] && ok "prompt não-string NÃO loga" || bad "prompt não-string logou"
SECRETS+=('objeto-hunter2')

echo "-- 5. varredura de vazamento no routing.jsonl inteiro"
for s in "${SECRETS[@]}"; do
  if grep -qF -- "$s" "$LOG"; then
    bad "VAZOU no log: '$s'"
  else
    ok "não vazou: '$(printf '%s' "$s" | cut -c1-32)'"
  fi
done
# Metadados do payload que não são prompt, mas também são sensíveis.
for s in "$CWD_FAKE" 'rcosta00' 'transcript' 'UserPromptSubmit'; do
  grep -qF -- "$s" "$LOG" && bad "VAZOU metadado do payload: '$s'" || ok "metadado não vazou: '$s'"
done
# Invariante estrutural do DATA_MODEL §4: nenhuma chave do log aceita '/'.
grep -q '/' "$LOG" && bad "log contém '/' — vazamento de caminho" || ok "nenhum '/' no log inteiro"
# Nenhuma linha pode ser maior que o razoável para um registro de metadados.
if awk 'length($0)>220{exit 1}' "$LOG"; then ok "toda linha ≤220 bytes (só metadados)"; else bad "linha longa demais no log"; fi

echo "-- 6. JSONL continua válido"
n=0; badjson=0
while IFS= read -r line; do
  n=$((n+1))
  printf '%s' "$line" | jq -e . >/dev/null 2>&1 || { badjson=1; bad "linha $n não é JSON válido"; }
  ev=$(printf '%s' "$line" | jq -r '.event')
  [[ "$ev" == "override_manual" ]] || bad "linha $n com event inesperado: $ev"
  keys=$(printf '%s' "$line" | jq -r 'keys_unsorted|join(",")')
  case "$keys" in
    ts,event,session_id|ts,event,session_id,cmd) : ;;
    *) bad "linha $n com chaves fora do contrato: $keys" ;;
  esac
done <"$LOG"
[[ $badjson -eq 0 ]] && ok "as $n linhas são JSON válido e só carregam ts/event/session_id/cmd"

echo "-- 7. degradação: sempre exit 0"
# 7a. kill-switch
rm -rf "$tmp/logs"
out=$(printf '%s' "$(payload sess-1 '/review segredo-killswitch')" | MAESTRO_OFF=1 "$HOOK" 2>&1); rc=$?
[[ $rc -eq 0 && -z "$out" ]] && ok "kill-switch: exit 0 e silencioso" || bad "kill-switch (rc=$rc out='$out')"
[[ -e "$LOG" ]] && bad "kill-switch escreveu no log" || ok "kill-switch não escreveu no log"

# 7b. stdin vazio
out=$(printf '' | "$HOOK" 2>"$ERR"); rc=$?
[[ $rc -eq 0 && -z "$out" ]] && ok "stdin vazio: exit 0, stdout vazio" || bad "stdin vazio (rc=$rc)"
[[ -e "$LOG" ]] && bad "stdin vazio escreveu no log" || ok "stdin vazio não escreveu no log"

# 7c. JSON malformado
for j in 'isto não é json' '{"prompt":' '[1,2,3]' 'null' '{"prompt":"/review"' ; do
  out=$(printf '%s' "$j" | "$HOOK" 2>"$ERR"); rc=$?
  [[ $rc -eq 0 && -z "$out" ]] || bad "JSON malformado '$j' (rc=$rc out='$out')"
done
ok "JSON malformado: exit 0 e stdout vazio em todos"
[[ -e "$LOG" ]] && bad "JSON malformado escreveu no log" || ok "JSON malformado não escreveu no log"

# 7d. sem jq no PATH
fakebin="$tmp/bin"; mkdir -p "$fakebin"
for b in bash env sh dirname mkdir date stat cat flock tail wc tr; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$fakebin/$b"
done
out=$(printf '%s' "$(payload sess-1 '/review segredo-sem-jq')" | PATH="$fakebin" "$HOOK" 2>"$ERR"); rc=$?
[[ $rc -eq 0 && -z "$out" ]] && ok "sem jq: exit 0, stdout vazio" || bad "sem jq (rc=$rc out='$out')"
[[ -e "$LOG" ]] && bad "sem jq escreveu no log" || ok "sem jq não escreveu no log"

# 7e. MAESTRO_HOME não escrevível → log falha, hook não
ro="$tmp/ro"; mkdir -p "$ro"; chmod 500 "$ro"
out=$(printf '%s' "$(payload sess-1 '/review')" | MAESTRO_HOME="$ro" "$HOOK" 2>"$ERR"); rc=$?
[[ $rc -eq 0 && -z "$out" ]] && ok "log inacessível: exit 0, stdout vazio" || bad "log inacessível (rc=$rc)"
chmod 700 "$ro"

# 7f. o hook nunca escreve no ~/.maestro real (o teste roda com MAESTRO_HOME isolado)
[[ "${MAESTRO_HOME:-}" == "$tmp" ]] && ok "MAESTRO_HOME isolado em tmpdir" || bad "MAESTRO_HOME não isolado"

if [[ $fail -eq 0 ]]; then echo "test-override: OK"; else echo "test-override: FALHOU" >&2; fi
exit $fail
