#!/usr/bin/env bash
# S-103 — teste de MUTAÇÃO do `maestro doctor`.
#
# Um doctor que não reprova instalação quebrada é pior que doctor nenhum (review P0-2).
# Por isso o teste não se contenta em ver o doctor passar no repo íntegro: ele copia o
# repo para um tmpdir, quebra a cópia de UM jeito por vez e exige que o doctor FALHE em
# cada caso, com o exit code certo (API_SPEC §3: 1 validação · 2 ambiente) e uma linha
# FAIL que aponte para o defeito real.
#
# Cobre ainda: P1-4 (CLI acessado por symlink), P2-6 (--ci de verdade),
# P2-7 (jq ausente não é reportado como "arquivo inválido") e a limpeza de TTL.
#
# NUNCA escreve no ~/.maestro real: todo MAESTRO_HOME aponta para dentro do tmpdir.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"' EXIT

fail=0
MATRIX=()

ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

# --------------------------------------------------------------------- helpers

fresh() { # fresh <nome> → ecoa o diretório de uma cópia íntegra do repo
  local d="$TMPROOT/$1"
  cp -a "$ROOT" "$d"
  rm -rf "$d/.git"
  mkdir -p "$d/.state"
  printf '%s\n' "$d"
}

OUT=''
doctor_run() { # doctor_run <dir> [args...] → OUT recebe stdout+stderr, retorna o exit code
  local d="$1"; shift
  OUT="$(MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor "$@" 2>&1)"
  return $?
}

shim_path() { # shim_path <dir> [cmd_a_omitir...] → PATH mínimo, sem os comandos listados
  local d="$1"; shift
  mkdir -p "$d"
  local c x p
  for c in bash env readlink dirname basename date stat grep sed awk tr mkdir touch rm flock jq bun; do
    for x in "$@"; do [[ "$c" == "$x" ]] && continue 2; done
    p="$(command -v "$c" 2>/dev/null)" || continue
    ln -sf "$p" "$d/$c"
  done
  printf '%s\n' "$d"
}

matrix_add() { # padding por caractere (printf %-Ns conta bytes e desalinha com acentos)
  local c="$1" pad='' n=$(( 38 - ${#1} ))
  [[ $n -gt 0 ]] && pad="$(printf '%*s' "$n" '')"
  MATRIX+=("${c}${pad}$(printf '%-5s %-5s %s' "$2" "$3" "$4")")
}

expect_break() { # expect_break <caso> <dir> <rc_esperado> <regex na saída>
  local caso="$1" d="$2" want="$3" re="$4" rc
  doctor_run "$d"; rc=$?
  if [[ $rc -eq $want ]] && printf '%s\n' "$OUT" | grep -qE "$re"; then
    ok "mutação reprovada: $caso (rc=$rc)"
    matrix_add "$caso" "$want" "$rc" "REPROVOU"
  else
    bad "mutação NÃO reprovada como esperado: $caso (rc=$rc, esperado=$want, regex='$re')"
    matrix_add "$caso" "$want" "$rc" "ESCAPOU <<<"
    printf '%s\n' "$OUT" | sed 's/^/       | /'
  fi
}

# =============================================================== 1. controle (repo íntegro)

BASE="$(fresh base)"
doctor_run "$BASE"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$OUT" | grep -q 'instalação saudável'; then
  ok "repo íntegro: doctor aprova (rc=0)"
  matrix_add "(controle) repo íntegro" "0" "$rc" "APROVOU"
else
  bad "repo íntegro: doctor deveria aprovar (rc=$rc)"
  matrix_add "(controle) repo íntegro" "0" "$rc" "REPROVOU <<<"
  printf '%s\n' "$OUT" | sed 's/^/       | /'
fi

# =============================================================== 2. matriz de mutação

# --- AC da S-103, caso A: YAML inválido -------------------------------------
d="$(fresh yaml-sintaxe)"
cat >"$d/config/routing-table.yaml" <<'Y'
version: 1
gate:
  mode: [warn
  allowlist: {extensions: [.md]}
Y
expect_break "YAML sintaticamente inválido" "$d" 1 'FAIL routing-table.yaml: schema válido'

d="$(fresh yaml-mode)"
sed -i 's/^  mode: block/  mode: yolo/' "$d/config/routing-table.yaml"
expect_break "gate.mode fora de {warn,block}" "$d" 1 'gate.mode deve ser warn\|block'

d="$(fresh yaml-sem-chaves)"
printf 'version: 1\ngate:\n  mode: warn\n' >"$d/config/routing-table.yaml"
expect_break "YAML sem workflows/routes" "$d" 1 'workflows ausente'

d="$(fresh yaml-ausente)"
rm -f "$d/config/routing-table.yaml"
expect_break "routing-table.yaml apagado" "$d" 2 'FAIL routing-table.yaml presente'

# --- AC da S-103, caso B: hook não registrado -------------------------------
d="$(fresh hooks-vazio)"
printf '{"hooks":{}}\n' >"$d/hooks/hooks.json"
expect_break "hooks.json = {\"hooks\":{}}" "$d" 1 'FAIL hooks.json registra os 4 eventos'

d="$(fresh hooks-sem-pretooluse)"
if command -v jq >/dev/null 2>&1; then
  jq 'del(.hooks.PreToolUse)' "$d/hooks/hooks.json" >"$d/hooks/hooks.json.tmp" \
    && mv "$d/hooks/hooks.json.tmp" "$d/hooks/hooks.json"
  expect_break "evento PreToolUse desregistrado" "$d" 1 'faltando: PreToolUse'
else
  echo "skip evento PreToolUse desregistrado (requer jq)"
fi

d="$(fresh hooks-matcher)"
sed -i 's/"Edit|Write|MultiEdit"/"Edit"/' "$d/hooks/hooks.json"
expect_break "matcher do PreToolUse incompleto" "$d" 1 'não coberto\(s\): Write MultiEdit'

d="$(fresh hooks-command-fantasma)"
sed -i 's#/hooks/pre-tool-gate.sh#/hooks/nao-existe.sh#' "$d/hooks/hooks.json"
expect_break "command aponta p/ arquivo inexistente" "$d" 2 'nao-existe.sh: inexistente'

d="$(fresh hooks-json-quebrado)"
printf '{"hooks": {\n' >"$d/hooks/hooks.json"
expect_break "hooks.json não é JSON válido" "$d" 1 'FAIL hooks.json é JSON válido'

d="$(fresh hooks-json-ausente)"
rm -f "$d/hooks/hooks.json"
expect_break "hooks.json apagado" "$d" 2 'FAIL hooks.json presente'

# --- hooks no disco ----------------------------------------------------------
d="$(fresh hook-sem-x)"
chmod -x "$d/hooks/pre-tool-gate.sh"
expect_break "hook sem bit de execução" "$d" 2 'FAIL hook pre-tool-gate.sh presente e executável'

d="$(fresh hook-apagado)"
rm -f "$d/hooks/session-start.sh"
expect_break "hook apagado do disco" "$d" 2 'FAIL hook session-start.sh presente e executável'

d="$(fresh common-apagado)"
rm -f "$d/hooks/lib/common.sh"
expect_break "lib/common.sh apagada" "$d" 2 'FAIL lib/common.sh presente'

# --- manifesto ---------------------------------------------------------------
d="$(fresh plugin-json-quebrado)"
printf '{ "name": "maestro",\n' >"$d/.claude-plugin/plugin.json"
expect_break "plugin.json não é JSON válido" "$d" 1 'FAIL plugin.json é JSON válido'

d="$(fresh plugin-json-sem-name)"
printf '{"description":"sem name nem version"}\n' >"$d/.claude-plugin/plugin.json"
expect_break "plugin.json sem name/version" "$d" 1 'FAIL plugin.json tem name e version'

# --- estado ------------------------------------------------------------------
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "skip diretório de estado read-only (rodando como root: permissões não se aplicam)"
else
  d="$(fresh estado-readonly)"
  chmod 500 "$d/.state"
  expect_break "diretório de estado read-only" "$d" 2 'FAIL diretório de estado gravável'
  chmod 700 "$d/.state"
fi

d="$(fresh record-invalido)"
mkdir -p "$d/.state/sessions"
printf '{"session_id":"abc","mode":"telepatia"}\n' >"$d/.state/sessions/abc.json"
if command -v jq >/dev/null 2>&1; then
  expect_break "decision record fora do schema §3" "$d" 1 'FAIL decision records: schema DATA_MODEL'
else
  echo "skip decision record fora do schema (requer jq)"
fi

d="$(fresh record-campo-extra)"
mkdir -p "$d/.state/sessions"
cat >"$d/.state/sessions/xyz.json" <<J
{"session_id":"xyz","ts":"$(date -Iseconds)","expires_at":"$(date -d '+4 hours' -Iseconds)",
 "workflow":"fix","mode":"direct","prompt":"texto do usuário vazando"}
J
if command -v jq >/dev/null 2>&1; then
  expect_break "decision record com campo extra" "$d" 1 'FAIL decision records: schema DATA_MODEL'
else
  echo "skip decision record com campo extra (requer jq)"
fi

# Emenda v1.5 (E10/S-1001): `maestro outcome` grava outcome/outcome_ts/suite no
# record. O RECORD_FIELDS nao os listava, entao o doctor reprovava exatamente o
# record de quem fez a coisa certa (registrou o desfecho) — e a CI nunca viu,
# porque a suite roda o doctor com MAESTRO_HOME temporario e zero record.
d="$(fresh record-outcome-valido)"
mkdir -p "$d/.state/sessions"
cat >"$d/.state/sessions/fechado.json" <<J
{"session_id":"fechado","ts":"$(date -Iseconds)","expires_at":"$(date -d '+4 hours' -Iseconds)","workflow":"ship","mode":"direct","reason":"release autorizada","outcome":"accepted","outcome_ts":"$(date -Iseconds)","suite":"pass"}
J
if command -v jq >/dev/null 2>&1; then
  doctor_run "$d"; rc=$?
  if [[ $rc -eq 0 ]] && printf '%s\n' "$OUT" | grep -q 'ok   decision records'; then
    ok "decision record com desfecho (E10) passa no schema §3"
  else
    bad "decision record com desfecho reprovado pelo doctor (rc=$rc)"
    printf '%s\n' "$OUT" | grep -i 'decision record' | sed 's/^/       | /'
  fi
else
  echo "skip decision record com desfecho (requer jq)"
fi

d="$(fresh record-outcome-enum)"
mkdir -p "$d/.state/sessions"
cat >"$d/.state/sessions/torto.json" <<J
{"session_id":"torto","ts":"$(date -Iseconds)","expires_at":"$(date -d '+4 hours' -Iseconds)","workflow":"ship","mode":"direct","outcome":"talvez"}
J
if command -v jq >/dev/null 2>&1; then
  expect_break "decision record com outcome fora do enum" "$d" 1 'FAIL decision records: schema DATA_MODEL'
else
  echo "skip decision record com outcome fora do enum (requer jq)"
fi

d="$(fresh record-suite-orfa)"
mkdir -p "$d/.state/sessions"
cat >"$d/.state/sessions/orfa.json" <<J
{"session_id":"orfa","ts":"$(date -Iseconds)","expires_at":"$(date -d '+4 hours' -Iseconds)","workflow":"ship","mode":"direct","suite":"pass"}
J
if command -v jq >/dev/null 2>&1; then
  expect_break "decision record com suite sem outcome" "$d" 1 'FAIL decision records: schema DATA_MODEL'
else
  echo "skip decision record com suite sem outcome (requer jq)"
fi

# =============================================================== 3. TTL (API_SPEC §1)

d="$(fresh ttl)"
mkdir -p "$d/.state/sessions"
cat >"$d/.state/sessions/velho.json" <<J
{"session_id":"velho","ts":"$(date -d '-9 hours' -Iseconds)","expires_at":"$(date -d '-5 hours' -Iseconds)","workflow":"fix","mode":"direct"}
J
cat >"$d/.state/sessions/novo.json" <<J
{"session_id":"novo","ts":"$(date -Iseconds)","expires_at":"$(date -d '+4 hours' -Iseconds)","workflow":"fix","mode":"subagent","agents":["golang-pro"],"reason":"bug em 1 módulo"}
J
doctor_run "$d"; rc=$?
if [[ $rc -eq 0 && ! -e "$d/.state/sessions/velho.json" && -e "$d/.state/sessions/novo.json" ]] \
   && printf '%s\n' "$OUT" | grep -q '1 válido(s), 1 expirado(s) removido(s)'; then
  ok "TTL: record expirado removido, record válido preservado"
else
  bad "TTL: limpeza incorreta (rc=$rc)"
  printf '%s\n' "$OUT" | sed 's/^/       | /'
  ls -1 "$d/.state/sessions" 2>&1 | sed 's/^/       | /'
fi

# =============================================================== 4. symlink (P1-4)

d="$(fresh symlink)"
mkdir -p "$TMPROOT/binlink" "$TMPROOT/binlink2"
ln -sf "$d/bin/maestro" "$TMPROOT/binlink/maestro"
ln -sf "$TMPROOT/binlink/maestro" "$TMPROOT/binlink2/maestro"

out="$(MAESTRO_HOME="$d/.state" NO_COLOR=1 "$TMPROOT/binlink/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && ! printf '%s\n' "$out" | grep -q '^FAIL'; then
  ok "P1-4: CLI invocado por symlink resolve o REPO_DIR (rc=0)"
else
  bad "P1-4: CLI por symlink falhou (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

out="$(MAESTRO_HOME="$d/.state" NO_COLOR=1 "$TMPROOT/binlink2/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && ! printf '%s\n' "$out" | grep -q '^FAIL'; then
  ok "P1-4: symlink de symlink também resolve (rc=0)"
else
  bad "P1-4: cadeia de symlinks falhou (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

# o symlink não pode virar um verde falso: quebre o alvo e o doctor tem de reprovar
printf '{"hooks":{}}\n' >"$d/hooks/hooks.json"
out="$(MAESTRO_HOME="$d/.state" NO_COLOR=1 "$TMPROOT/binlink/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 1 ]]; then
  ok "P1-4: por symlink, instalação quebrada continua reprovando (rc=1)"
else
  bad "P1-4: por symlink, instalação quebrada passou (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

# =============================================================== 5. --ci (P2-6)

d="$(fresh ci)"
out="$(MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor --ci 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && ! printf '%s\n' "$out" | grep -q '^ok ' \
   && printf '%s\n' "$out" | grep -q '^doctor: ok —'; then
  ok "--ci: saída enxuta (sem linhas ok) + resumo, rc=0"
else
  bad "--ci: saída inesperada no repo íntegro (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

out="$(MAESTRO_HOME="$d/.state" TERM=xterm NO_COLOR= "$d/bin/maestro" doctor --ci 2>&1)"
if ! printf '%s\n' "$out" | grep -q $'\033'; then
  ok "--ci: nunca emite código de cor"
else
  bad "--ci: emitiu código de cor"
fi

printf '{"hooks":{}}\n' >"$d/hooks/hooks.json"
out="$(MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor --ci 2>&1)"; rc=$?
if [[ $rc -eq 1 ]] && printf '%s\n' "$out" | grep -q '^doctor: FALHOU'; then
  ok "--ci: instalação quebrada → resumo de falha + rc=1"
else
  bad "--ci: instalação quebrada não reprovou direito (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

out="$(MAESTRO_HOME="$d/.state" "$d/bin/maestro" doctor --nao-existe 2>&1)"; rc=$?
if [[ $rc -eq 1 ]] && printf '%s\n' "$out" | grep -q '^maestro: validation:'; then
  ok "flag desconhecida → envelope de erro do API_SPEC §3 + rc=1"
else
  bad "flag desconhecida: envelope/rc errados (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

# =============================================================== 6. dependências (P2-7)

d="$(fresh sem-jq)"
P="$(shim_path "$TMPROOT/path-sem-jq" jq)"
out="$(PATH="$P" MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 2 ]] \
   && printf '%s\n' "$out" | grep -q 'FAIL dependência: jq' \
   && ! printf '%s\n' "$out" | grep -q 'FAIL hooks.json é JSON válido' \
   && ! printf '%s\n' "$out" | grep -q 'FAIL plugin.json é JSON válido'; then
  ok "P2-7: jq ausente vira FAIL de dependência, não 'JSON inválido'"
else
  bad "P2-7: diagnóstico errado com jq ausente (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

d="$(fresh sem-bun)"
P="$(shim_path "$TMPROOT/path-sem-bun" bun)"
out="$(PATH="$P" MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$out" | grep -q 'warn dependência: bun ausente' \
   && printf '%s\n' "$out" | grep -q 'checagem estrutural — Bun ausente'; then
  ok "doctor funciona sem Bun (repo íntegro, validação estrutural em bash)"
else
  bad "doctor quebrou sem Bun (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

d="$(fresh sem-bun-yaml-quebrado)"
cat >"$d/config/routing-table.yaml" <<'Y'
version: 1
gate:
  mode: [warn
  allowlist: {extensions: [.md]}
Y
out="$(PATH="$P" MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 1 ]] && printf '%s\n' "$out" | grep -q 'FAIL routing-table.yaml: schema válido (sem Bun)'; then
  ok "sem Bun, YAML inválido continua sendo reprovado"
  matrix_add "YAML inválido (sem Bun no PATH)" "1" "$rc" "REPROVOU"
else
  bad "sem Bun, YAML inválido passou (rc=$rc)"
  matrix_add "YAML inválido (sem Bun no PATH)" "1" "$rc" "ESCAPOU <<<"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

d="$(fresh sem-jq-hooks-vazio)"
printf '{"hooks":{}}\n' >"$d/hooks/hooks.json"
P="$(shim_path "$TMPROOT/path-sem-jq" jq)"
out="$(PATH="$P" MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 2 ]] && printf '%s\n' "$out" | grep -q 'FAIL hooks.json registra os 4 eventos'; then
  ok "sem jq, hook desregistrado continua sendo detectado (modo degradado)"
  matrix_add "hooks vazio (sem jq no PATH)" "2" "$rc" "REPROVOU"
else
  bad "sem jq, hook desregistrado escapou (rc=$rc)"
  matrix_add "hooks vazio (sem jq no PATH)" "2" "$rc" "ESCAPOU <<<"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

# =============================================================== matriz final

echo
echo "matriz de mutação (rc 1 = validação · rc 2 = ambiente quebrado):"
printf '     %-38s%-5s %-5s %s\n' "caso" "esp" "obt" "veredito"
for l in "${MATRIX[@]}"; do printf '     %s\n' "$l"; done
echo

exit $fail
