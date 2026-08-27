#!/usr/bin/env bash
# E7 / S-705 + S-706 — capability envelope (maestro.capabilities.v1) + drift de
# resolução de bindings + integridade do vendor/.
# Isolado: MAESTRO_HOME e fixtures em mktemp -d; skills via MAESTRO_SKILL_DIRS
# (nunca as reais — regra da suíte hermética, memória do projeto).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v jq >/dev/null || { echo "FAIL jq ausente (dependência declarada)"; exit 1; }
command -v sha256sum >/dev/null || { echo "FAIL sha256sum ausente (coreutils)"; exit 1; }

# fixture de skills: uma pasta por skill: citada nos bindings (padrão do
# test-routing-table.sh — hermético, CI sem packs continua verde)
FX="$tmp/skills"; mkdir -p "$FX"
for s in systematic-debugging requesting-code-review gstack-qa gstack-ship gstack-cso; do
  mkdir -p "$FX/$s"; echo 'v1' > "$FX/$s/SKILL.md"
done

HOME1="$tmp/home1"
doc() { MAESTRO_HOME="$1" MAESTRO_SKILL_DIRS="$FX" "$BIN" doctor "${@:2}" >"$tmp/out" 2>&1; rc=$?; }

# ---------------------------------------------------------------------------
echo "-- S-705: envelope maestro.capabilities.v1"
# ---------------------------------------------------------------------------
doc "$HOME1"
chk "doctor sai 0 com fixture íntegra" "$rc" "0"
CAP="$HOME1/capabilities.json"
[[ -f "$CAP" ]] && ok "capabilities.json gravado" || bad "capabilities.json gravado"
chk "schema versionado" "$(jq -r .schema "$CAP")" "maestro.capabilities.v1"
chk "generated_epoch é inteiro" "$(jq -r '.generated_epoch | type' "$CAP")" "number"
chk "runtime.bun.present=true (bun está no PATH da suíte)" \
    "$(jq -r .runtime.bun.present "$CAP")" "true"
chk "bindings.resolved é inteiro > 0" \
    "$(jq -r '.bindings.resolved > 0' "$CAP")" "true"
chk "roster.agents = 10" "$(jq -r .roster.agents "$CAP")" "10"
grep -q 'ok   capabilities.json' "$tmp/out" \
  && ok "doctor reporta a gravação do envelope" || bad "doctor reporta a gravação do envelope"

# consumidor: delegate sem bun cita o envelope (PATH mínimo, sem ~/.bun nem ~/.local)
run_nobun() { MAESTRO_HOME="$HOME1" PATH=/usr/bin:/bin "$BIN" decide --session x --workflow fix --mode direct >"$tmp/out" 2>"$tmp/err"; rc=$?; }
if PATH=/usr/bin:/bin command -v bun >/dev/null 2>&1; then
  ok "SKIP consumidor sem-bun: bun existe em /usr/bin — cenário não simulável aqui"
else
  run_nobun
  chk "sem bun: exit 2 (env)" "$rc" "2"
  grep -q 'último doctor:' "$tmp/err" \
    && ok "erro cita o envelope (último doctor + idade)" \
    || bad "erro cita o envelope (último doctor + idade)"
  grep -q 'envelope velho' "$tmp/err" \
    && bad "envelope fresco NÃO é marcado velho" \
    || ok  "envelope fresco NÃO é marcado velho"
  # envelope com 25h → marcado velho
  old=$(( $(date +%s) - 90000 ))
  jq --argjson e "$old" '.generated_epoch = $e' "$CAP" > "$CAP.n" && mv "$CAP.n" "$CAP"
  run_nobun
  grep -q 'envelope velho' "$tmp/err" \
    && ok "envelope de 25h é marcado velho" || bad "envelope de 25h é marcado velho"
  # sem envelope nenhum → erro seco original, sem hint
  rm -f "$CAP"; run_nobun
  chk "sem envelope: ainda exit 2" "$rc" "2"
  grep -q 'último doctor' "$tmp/err" \
    && bad "sem envelope não inventa hint" || ok "sem envelope não inventa hint"
fi

# ---------------------------------------------------------------------------
echo "-- S-706: drift de resolução de bindings"
# ---------------------------------------------------------------------------
HOME2="$tmp/home2"
doc "$HOME2"
grep -q 'snapshot de resolução inicial gravado' "$tmp/out" \
  && ok "primeira rodada grava snapshot inicial" || bad "primeira rodada grava snapshot inicial"
[[ -f "$HOME2/bindings-snapshot.tsv" ]] && ok "bindings-snapshot.tsv existe" \
                                        || bad "bindings-snapshot.tsv existe"
doc "$HOME2"
grep -q 'drift zero' "$tmp/out" \
  && ok "segunda rodada sem mudança: drift zero" || bad "segunda rodada sem mudança: drift zero"

echo 'mudou' >> "$FX/gstack-qa/SKILL.md"
doc "$HOME2"
chk "drift é AVISO, nunca falha (exit 0)" "$rc" "0"
grep -q 'binding-resolution-drift: skill:gstack-qa (conteúdo mudou)' "$tmp/out" \
  && ok "conteúdo mudado → drift nomeando o alvo" || bad "conteúdo mudado → drift nomeando o alvo"
doc "$HOME2"
grep -q 'drift zero' "$tmp/out" \
  && ok "snapshot avança: aviso some na rodada seguinte" \
  || bad "snapshot avança: aviso some na rodada seguinte"

# caminho mudou: mesma skill passa a resolver noutra raiz (raiz nova na frente)
FX2="$tmp/skills2"; mkdir -p "$FX2/gstack-qa"; cp "$FX/gstack-qa/SKILL.md" "$FX2/gstack-qa/SKILL.md"
MAESTRO_HOME="$HOME2" MAESTRO_SKILL_DIRS="$FX2:$FX" "$BIN" doctor >"$tmp/out" 2>&1
grep -q 'binding-resolution-drift: skill:gstack-qa (caminho mudou)' "$tmp/out" \
  && ok "resolução migrando de raiz → drift 'caminho mudou'" \
  || bad "resolução migrando de raiz → drift 'caminho mudou'"

# ---------------------------------------------------------------------------
echo "-- S-706: integridade do vendor/"
# ---------------------------------------------------------------------------
doc "$tmp/home3"
grep -qE 'ok   vendor/: íntegro vs manifesto \([0-9]+ arquivo\(s\)\)' "$tmp/out" \
  && ok "vendor/ confere com config/vendor.sha256" \
  || bad "vendor/ confere com config/vendor.sha256"

badman="$tmp/vendor-bad.sha256"
cp "$REPO/config/vendor.sha256" "$badman"
printf '%s  vendor/arquivo-que-nao-existe\n' \
  "0000000000000000000000000000000000000000000000000000000000000000" >> "$badman"
MAESTRO_HOME="$tmp/home4" MAESTRO_SKILL_DIRS="$FX" MAESTRO_VENDOR_MANIFEST="$badman" \
  "$BIN" doctor >"$tmp/out" 2>&1; rc=$?
chk "manifesto divergente → exit 1 (validação)" "$rc" "1"
grep -q 'FAIL.*vendor/' "$tmp/out" \
  && ok "divergência reportada como FAIL de conteúdo" \
  || bad "divergência reportada como FAIL de conteúdo"

exit $fail
