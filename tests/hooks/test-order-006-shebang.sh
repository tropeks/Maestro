#!/usr/bin/env bash
# ordem 006 (E24 Lote 0, passo 0.2) — detecção por SHEBANG substitui o filtro
# por NOME que isentava todo executável sem ponto (bin/maestro incluído). O
# filtro estava DUPLICADO (hooks/post-edit-habits.sh + bin/maestro cmd_habits)
# e teria virado um TERCEIRO vocabulário se cada lado resolvesse sozinho —
# por isso a detecção vira `maestro_lang_ext` em hooks/lib/common.sh, sensor
# ÚNICO que os dois sourceiam (I-4).
#
# Lição das ordens 003/004/005: o teste NÃO exige o patch já aplicado.
# Ausente → PENDENTE (hooks/ está na denylist do gate; quem aplica
# docs/patches/006-lote0-shebang-*.patch é o Capitão). Presente → cobra de
# verdade e prova o TERCEIRO ESTADO — sabota a função e mostra que a MESMA
# asserção reprova.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
COMMON="$REPO/hooks/lib/common.sh"
HOOK="$REPO/hooks/post-edit-habits.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

PATCHED=0
grep -qF 'maestro_lang_ext()' "$COMMON" 2>/dev/null && PATCHED=1

if (( PATCHED == 0 )); then
  pending "ordem 006/0.2: hooks/lib/common.sh ainda sem maestro_lang_ext — aplicar docs/patches/006-lote0-shebang-common.patch (+ -hook.patch, -cli.patch)"
  exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
printf 'MIT License\n' > "$T/LICENSE"
printf '#!/usr/bin/env bash\necho hi\n' > "$T/tool"
printf '#!/usr/bin/env python3\nprint(1)\n' > "$T/pytool"
printf 'echo hi\n' > "$T/plain.sh"
mkfifo "$T/hot.sh" 2>/dev/null

lang() { bash -c "source '$COMMON'; maestro_lang_ext '$1'"; }

[[ "$(lang "$T/LICENSE")" == "" ]]  && ok "extensionless sem shebang (LICENSE) → vazio" \
  || bad "LICENSE deveria dar vazio"
[[ "$(lang "$T/tool")" == "sh" ]]   && ok "extensionless com shebang bash → sh" \
  || bad "tool(bash) deveria dar sh"
[[ "$(lang "$T/pytool")" == "py" ]] && ok "extensionless com shebang python → py" \
  || bad "pytool deveria dar py"
[[ "$(lang "$T/plain.sh")" == "sh" ]] && ok ".sh comum → sh (byte-idêntico ao comportamento antigo)" \
  || bad "plain.sh deveria dar sh"

# custo zero no caminho quente: arquivo COM extensão nunca é LIDO — provado
# com um FIFO sem escritor. Se o código tentasse ler, `read -r < fifo`
# bloquearia esperando um writer que não existe, e o `timeout` estouraria.
if timeout 2 bash -c "source '$COMMON'; maestro_lang_ext '$T/hot.sh'" >/dev/null 2>&1; then
  ok "arquivo COM extensão: zero leitura (FIFO sem writer não bloqueou)"
else
  bad "arquivo COM extensão tentou ler o conteúdo (FIFO travou/timeout)"
fi

# medição de latência real: NFR é <100ms/hook (S-901); load ALTO deixa a
# medição "inconclusiva sob carga" (mesmo protocolo declarado no plano do
# arquiteto para o E24 — não é regra nova deste teste).
LOAD1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)
t0=$(date +%s%N)
for _ in $(seq 1 50); do bash -c "source '$COMMON'; maestro_lang_ext '$T/plain.sh'" >/dev/null; done
t1=$(date +%s%N)
MS=$(( (t1 - t0) / 1000000 ))
LOAD_X100=$(awk -v l="$LOAD1" 'BEGIN{printf "%d", l*100}')
if (( LOAD_X100 > 200 )); then
  echo "INCONCLUSIVO sob carga — latência de maestro_lang_ext (${MS}ms/50 chamadas; load $LOAD1 — não conta como falha)"
else
  (( MS < 500 )) && ok "50 chamadas em ${MS}ms (custo zero no caminho quente)" \
    || bad "50 chamadas em ${MS}ms — mais lento que o esperado para arquivo COM extensão"
fi

# ---------------------------------------------------------------------------
# wiring: o HOOK de verdade (post-edit-habits.sh) sensoreia extensionless com
# shebang e ignora extensionless sem shebang — fim a fim, não só a função.
# ---------------------------------------------------------------------------
HOOKPATCHED=0
grep -qF 'maestro_lang_ext "$FILE"' "$HOOK" 2>/dev/null && HOOKPATCHED=1
if (( HOOKPATCHED == 0 )); then
  pending "ordem 006/0.2: hooks/post-edit-habits.sh ainda não usa maestro_lang_ext — aplicar docs/patches/006-lote0-shebang-hook.patch"
else
  PROJ="$T/proj"; mkdir -p "$PROJ"
  { printf '#!/usr/bin/env bash\n'; for i in $(seq 1 450); do echo "echo l$i"; done; } > "$PROJ/deploy"
  chmod +x "$PROJ/deploy"
  HOME_T="$T/home"; mkdir -p "$HOME_T"
  IN=$(printf '{"session_id":"s6","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$PROJ/deploy")
  OUT=$(printf '%s' "$IN" | MAESTRO_HOME="$HOME_T" CLAUDE_PROJECT_DIR="$PROJ" MAESTRO_HABITS_COOLDOWN=0 bash "$HOOK" 2>&1 >/dev/null)
  [[ "$OUT" == *"oversized-file"* ]] && ok "hook sensoreia executável extensionless com shebang" \
    || bad "hook deveria sensoriar 'deploy' (shebang bash, 450 linhas) — obtido: '$OUT'"

  # ---------------------------------------------------------------------------
  # terceiro estado: sabota maestro_lang_ext numa CÓPIA (sempre devolve vazio
  # para extensionless) e mostra que a MESMA asserção reprova.
  # ---------------------------------------------------------------------------
  SABTREE="$T/sabotado"; mkdir -p "$SABTREE/hooks/lib"
  cp "$COMMON" "$SABTREE/hooks/lib/common.sh"
  cp "$HOOK" "$SABTREE/hooks/post-edit-habits.sh"
  cp "$REPO/hooks/lib/habit-sensors.awk" "$SABTREE/hooks/lib/habit-sensors.awk"
  [[ -f "$REPO/hooks/lib/project-state.sh" ]] && cp "$REPO/hooks/lib/project-state.sh" "$SABTREE/hooks/lib/project-state.sh"
  sed -i 's/^maestro_lang_ext() {/maestro_lang_ext() { return 0; #SABOTADO/' "$SABTREE/hooks/lib/common.sh"
  if ! grep -q 'SABOTADO' "$SABTREE/hooks/lib/common.sh"; then
    bad "sabotagem não pegou (padrão do sed não bateu)"
  else
    OUT_SAB=$(printf '%s' "$IN" | MAESTRO_HOME="$T/home-sab" CLAUDE_PROJECT_DIR="$PROJ" MAESTRO_HABITS_COOLDOWN=0 \
      bash "$SABTREE/hooks/post-edit-habits.sh" 2>&1 >/dev/null)
    if [[ "$OUT_SAB" == *"oversized-file"* ]]; then
      bad "sabotagem não quebrou nada — a asserção passaria mesmo com a detecção morta"
    else
      ok "sabotado: hook para de sensoriar o executável (obtido: '$OUT_SAB') — o teste tem dente"
    fi
  fi
fi

exit $fail
