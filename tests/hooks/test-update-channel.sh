#!/usr/bin/env bash
# E23c / S-2303 — o auto-update segue a tag `stable`, não o topo da main.
#
# O que este arquivo prova:
#   - canal default é `stable`: o ff-only para no commit que a CI aprovou, mesmo
#     com a main já vários commits à frente;
#   - `stable` é MÓVEL: quando a CI a reaponta, a máquina anda de novo (o fetch
#     precisa ser forçado, senão o git recusa reescrever uma tag que já existe);
#   - `stable` ausente no remoto é `no-stable`: sem update, sem erro, sem aviso
#     na injeção — só estado registrado para o doctor;
#   - canal `main` é o comportamento antigo, intacto (o contrato completo dele
#     está em test-update-check.sh e test-upgrade.sh);
#   - `maestro upgrade --channel` sobrepõe pontualmente, sem gravar config;
#   - `update_channel` inválido no config.yaml vale `stable` e o doctor reclama;
#   - o evento `upgrade` no log carrega `channel`.
#
# Hermético como os irmãos: remoto bare em file:// dentro do mktemp, clone de
# FIXTURE (nunca o repo real), MAESTRO_HOME isolado. Zero rede.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
BIN="$REPO/bin/maestro"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
has() { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1 (não achou: $2)"; fi; }
hasnt() { if grep -qF -- "$2" "$3"; then bad "$1 (achou: $2)"; else ok "$1"; fi; }

command -v git >/dev/null || { echo "FAIL git ausente (dependência declarada)"; exit 1; }
G() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# ---------------------------------------------------------------------------
# Fixture: "plugin" mínimo (hooks e config reais, para o SessionStart rodar de
# verdade) num remoto bare; os clones são o que o update mexe.
# ---------------------------------------------------------------------------
SRC="$SANDBOX/src"; mkdir -p "$SRC"
cp -r "$REPO/hooks" "$SRC/hooks"
cp -r "$REPO/config" "$SRC/config"
mkdir -p "$SRC/agents" "$SRC/.claude-plugin"
printf -- '---\nname: fixture-dev\ndescription: agente de fixture\nmodel: haiku\ntools: Read\n---\ncorpo\n' > "$SRC/agents/fixture-dev.md"
printf '{"name":"maestro","version":"1.0.0"}\n' > "$SRC/.claude-plugin/plugin.json"
printf '# CHANGELOG\n\n## [1.0.0]\n- base\n' > "$SRC/CHANGELOG.md"
G -C "$SRC" init -q -b main
G -C "$SRC" add -A && G -C "$SRC" commit -qm "v1.0.0"
BASE=$(git -C "$SRC" rev-parse HEAD)     # o commit da 1.0.0, sem tag

REMOTE="$SANDBOX/remote.git"
git clone -q --bare "$SRC" "$REMOTE"

new_clone() { # new_clone <nome> [rev] → clone em main, opcionalmente recuado até <rev>
  # O recuo é o que torna o teste honesto: clone recém-feito nasce no TOPO da
  # main, e aí "não atualizou" e "atualizou até o lugar certo" ficam iguais.
  local c="$SANDBOX/$1"
  git clone -q "$REMOTE" "$c" 2>/dev/null
  G -C "$c" checkout -q main 2>/dev/null || :
  [[ -n "${2:-}" ]] && G -C "$c" reset -q --hard "$2"
  printf '%s' "$c"
}

publish() { # publish <versão> — commit + push na main; NÃO aprova nada
  printf '{"name":"maestro","version":"%s"}\n' "$1" > "$SRC/.claude-plugin/plugin.json"
  printf '\n## [%s]\n- mudança %s\n' "$1" "$1" >> "$SRC/CHANGELOG.md"
  G -C "$SRC" add -A && G -C "$SRC" commit -qm "v$1"
  G -C "$SRC" tag -a "v$1" -m "v$1" 2>/dev/null || :
  G -C "$SRC" push -q "$REMOTE" main "v$1"
}

approve() { # approve <rev> — o que a CI faz na tag v* verde: move `stable` e força o push
  G -C "$SRC" tag -f stable "$1" >/dev/null 2>&1
  G -C "$SRC" push -q -f "$REMOTE" refs/tags/stable
}

sha_of() { git -C "$SRC" rev-parse "$1^{commit}"; }
head_of() { git -C "$1" rev-parse HEAD; }
state() { sed -n "s/^$2=\(.*\)$/\1/p" "$1/update-state" 2>/dev/null | head -1; }

OUTF="$SANDBOX/out"; ERRF="$SANDBOX/err"
run() { # run <home> <clone> [VAR=VAL ...] — o hook real, apontado para o clone
  local home="$1" clone="$2"; shift 2
  local proj="$SANDBOX/proj"; mkdir -p "$proj"
  printf '{"session_id":"chan-test-1"}' \
    | env MAESTRO_HOME="$home" CLAUDE_PROJECT_DIR="$proj" MAESTRO_UPDATE_REPO="$clone" \
          MAESTRO_NO_UPDATE_CHECK=0 MAESTRO_UPDATE_INTERVAL=0 MAESTRO_UPDATE_TIMEOUT=5 "$@" \
          bash "$HOOK" >"$OUTF" 2>"$ERRF"
  RC=$?
}
U() { # U <home> <clone> [VAR=VAL ...] -- <args de maestro upgrade>
  local home="$1" clone="$2"; shift 2
  local extra=()
  while [[ "${1:-}" != "--" ]]; do extra+=("$1"); shift; done
  shift
  env MAESTRO_HOME="$home" MAESTRO_UPDATE_REPO="$clone" MAESTRO_UPDATE_TIMEOUT=5 \
      MAESTRO_UPDATE_INTERVAL=0 "${extra[@]}" "$BIN" upgrade "$@" >"$OUTF" 2>"$ERRF"
  RC=$?
}
n=0; next_home() { n=$((n+1)); H="$SANDBOX/home$n"; mkdir -p "$H"; }

# ---------------------------------------------------------------------------
echo "-- remoto sem a tag stable: estado no-stable, sessão íntegra, nada aplicado"
C1=$(new_clone clone1)
publish 1.0.1                      # main andou, mas ninguém aprovou nada
BEFORE=$(head_of "$C1")
next_home; NOSTABLE_HOME="$H"; run "$H" "$C1"
chk "hook sai 0" "$RC" "0"
has "injeção íntegra" "INSTRUÇÃO CANÔNICA" "$OUTF"
chk "HEAD intacto (main nova é ignorada)" "$(head_of "$C1")" "$BEFORE"
chk "estado no-stable" "$(state "$H" result)" "no-stable"
chk "canal registrado" "$(state "$H" channel)" "stable"
chk "motivo nomeado" "$(state "$H" reason)" "no-stable-tag"
# Review E23c: no-stable é auto-update PARADO — a sessão precisa saber, senão é a
# staleness muda que o update-check existe para fechar.
has "injeção avisa que o auto-update está parado (no-stable)" "auto-update parado" "$OUTF"
chk "fetch foi ok (a tag ausente não é falha de rede)" "$(state "$H" fetch)" "ok"

echo "-- CLI no canal stable sem a tag: exit 0 e a explicação, nunca um erro"
U "$NOSTABLE_HOME" "$C1" -- --check
chk "--check sai 0" "$RC" "0"
has "linha explica o canal" "o origin ainda não tem a tag 'stable'" "$OUTF"
has "linha ensina a saída" "maestro upgrade --channel main" "$OUTF"
U "$NOSTABLE_HOME" "$C1" --
chk "upgrade sai 0" "$RC" "0"
has "upgrade explica em vez de aplicar" "nada a aplicar" "$OUTF"
chk "HEAD segue intacto" "$(head_of "$C1")" "$BEFORE"

# ---------------------------------------------------------------------------
echo "-- stable ATRÁS da main: o ff-only para na tag aprovada, não no topo"
publish 1.0.2
publish 1.0.3
approve "$(sha_of v1.0.1)"          # a CI só aprovou a 1.0.1
next_home; run "$H" "$C1"
chk "hook sai 0" "$RC" "0"
chk "HEAD == commit da tag stable" "$(head_of "$C1")" "$(sha_of v1.0.1)"
[[ "$(head_of "$C1")" != "$(sha_of v1.0.3)" ]] && ok "NÃO foi até o topo da main (1.0.3)" \
  || bad "seguiu a main em vez da tag stable"
chk "versão local é a aprovada" "$(state "$H" local)" "1.0.1"
chk "versão remota veio do plugin.json DA TAG, não do topo" "$(state "$H" remote)" "1.0.1"
chk "estado current" "$(state "$H" result)" "current"
chk "canal stable no estado" "$(state "$H" channel)" "stable"
has "sessão nasce na versão aprovada" "Maestro v1.0.1" "$OUTF"
if grep -q '"event":"upgrade"' "$H/logs/routing.jsonl" 2>/dev/null; then
  line=$(grep '"event":"upgrade"' "$H/logs/routing.jsonl" | head -1)
  [[ "$line" == *'"channel":"stable"'* ]] && ok "evento upgrade carrega channel=stable" \
    || bad "evento upgrade sem channel: $line"
  [[ "$line" == */* ]] && bad "log vazou caminho" || ok "log sem caminho"
else
  bad "evento upgrade ausente no log"
fi

echo "-- a CI move a tag: a máquina anda de novo (fetch forçado de tag existente)"
approve "$(sha_of v1.0.3)"
run "$H" "$C1"
chk "HEAD acompanha a tag movida" "$(head_of "$C1")" "$(sha_of v1.0.3)"
chk "versão local 1.0.3" "$(state "$H" local)" "1.0.3"
has "sessão nasce na 1.0.3" "Maestro v1.0.3" "$OUTF"

echo "-- trabalho local à frente da tag: blocked/ahead, com a razão certa no CLI"
echo local > "$C1/LOCAL.md"; G -C "$C1" add -A; G -C "$C1" commit -qm "trabalho local"
LOCAL_HEAD=$(head_of "$C1")
publish 1.0.4
approve "$(sha_of v1.0.4)"
next_home; run "$H" "$C1"
chk "estado blocked" "$(state "$H" result)" "blocked"
chk "motivo ahead" "$(state "$H" reason)" "ahead"
chk "HEAD intacto: trabalho local não é sobrescrito" "$(head_of "$C1")" "$LOCAL_HEAD"
U "$H" "$C1" --
chk "CLI sai 1" "$RC" "1"
has "mensagem fala da tag, não do origin" "à frente da tag stable (ainda não aprovados pela CI)" "$OUTF"
G -C "$C1" reset -q --hard "$(sha_of v1.0.4)"   # volta a ser exatamente a tag aprovada

echo "-- tag stable não sequestra o retrato de release (describe --match 'v*')"
chk "describe filtrado devolve a release" \
  "$(git -C "$C1" describe --tags --abbrev=0 --match 'v*' 2>/dev/null)" "v1.0.4"

# ---------------------------------------------------------------------------
echo "-- canal main: comportamento antigo intacto (segue o topo, ignora a tag)"
C2=$(new_clone clone2 "$BASE")
next_home; run "$H" "$C2" MAESTRO_UPDATE_CHANNEL=main
chk "HEAD == topo da main (1.0.4)" "$(head_of "$C2")" "$(sha_of v1.0.4)"
chk "canal main no estado" "$(state "$H" channel)" "main"
chk "estado current" "$(state "$H" result)" "current"
if grep -q '"event":"upgrade"' "$H/logs/routing.jsonl" 2>/dev/null; then
  grep '"event":"upgrade"' "$H/logs/routing.jsonl" | head -1 | grep -q '"channel":"main"' \
    && ok "evento upgrade carrega channel=main" || bad "evento upgrade sem channel=main"
else
  bad "evento upgrade ausente no log (canal main)"
fi

echo "-- canal vem do config.yaml quando não há env"
C3=$(new_clone clone3 "$BASE")
next_home; printf 'update_channel: main\n' > "$H/config.yaml"; run "$H" "$C3"
chk "config.yaml manda: seguiu a main" "$(head_of "$C3")" "$(sha_of v1.0.4)"
chk "canal main no estado" "$(state "$H" channel)" "main"

echo "-- update_channel inválido no config.yaml vale stable (fail-safe)"
C4=$(new_clone clone4 "$BASE")
next_home; INVALID_HOME="$H"; printf 'update_channel: nightly\n' > "$H/config.yaml"
run "$H" "$C4"
chk "canal resolvido para stable" "$(state "$H" channel)" "stable"
chk "parou na tag aprovada (1.0.4), não no topo" "$(head_of "$C4")" "$(sha_of v1.0.4)"

echo "-- troca de canal desarma o fast path (o ref-candidato é outro)"
run "$INVALID_HOME" "$C4" MAESTRO_UPDATE_INTERVAL=86400 MAESTRO_UPDATE_CHANNEL=stable
chk "mesmo canal, dentro do intervalo: fast path" "$(state "$INVALID_HOME" reason)" "fast-path"
run "$INVALID_HOME" "$C4" MAESTRO_UPDATE_INTERVAL=86400 MAESTRO_UPDATE_CHANNEL=main
[[ "$(state "$INVALID_HOME" reason)" != "fast-path" ]] \
  && ok "canal trocado: medição completa (nada de estado reaproveitado)" \
  || bad "fast path reaproveitou medição de outro canal"

# ---------------------------------------------------------------------------
echo "-- maestro upgrade --channel: override pontual, sem gravar config"
publish 1.0.5                      # main andou de novo; a CI ainda não aprovou
C5=$(new_clone clone5 "$(sha_of v1.0.4)")   # clone parado exatamente na tag stable
next_home; CLI_HOME="$H"
U "$CLI_HOME" "$C5" -- --check
chk "default stable: exit 0 (já está na tag)" "$RC" "0"
has "linha diz o canal" "canal stable" "$OUTF"
U "$CLI_HOME" "$C5" -- --check --channel main
chk "--channel main enxerga a 1.0.5 não aprovada: exit 1" "$RC" "1"
has "linha diz o canal main" "canal main" "$OUTF"
[[ -f "$CLI_HOME/config.yaml" ]] && bad "--channel gravou config.yaml (deveria ser pontual)" \
  || ok "--channel não tocou o config.yaml"
U "$CLI_HOME" "$C5" -- --channel main
chk "aplica no canal pedido" "$RC" "0"
chk "HEAD == topo da main (1.0.5, sem aprovação)" "$(head_of "$C5")" "$(sha_of v1.0.5)"
has "resumo nomeia o canal" "canal main)" "$OUTF"
U "$CLI_HOME" "$C5" -- --channel nightly
chk "canal inválido → exit 1" "$RC" "1"
has "erro ensina o domínio" "esperado stable|main" "$ERRF"

echo "-- maestro upgrade --set update_channel: grava e valida"
next_home
U "$H" "$C5" -- --set update_channel=main
chk "exit 0" "$RC" "0"
has "config.yaml gravado" "update_channel: main" "$H/config.yaml"
U "$H" "$C5" -- --set update_channel=nightly
chk "valor fora do domínio → exit 1" "$RC" "1"
has "config.yaml intacto" "update_channel: main" "$H/config.yaml"

# ---------------------------------------------------------------------------
echo "-- doctor: no-stable é ok (nunca falha) e o canal aparece na publicação"
FX="$SANDBOX/skills"; mkdir -p "$FX"
for s in systematic-debugging requesting-code-review gstack-qa gstack-ship gstack-cso gstack-office-hours; do
  mkdir -p "$FX/$s"; echo v1 > "$FX/$s/SKILL.md"
done
doctor_out() { # doctor_out <home> <repo>
  MAESTRO_HOME="$1" MAESTRO_SKILL_DIRS="$FX" MAESTRO_PLUGINS_DIR="$SANDBOX/plugins-vazio" \
    MAESTRO_UPDATE_REPO="$2" "$BIN" doctor >"$OUTF" 2>&1
  RC=$?
}
next_home
cat > "$H/update-state" <<EOF
schema=maestro-update-state-v1
checked=$(date +%s)
fetched=$(date +%s)
fetch=ok
channel=stable
result=no-stable
reason=no-stable-tag
local=1.0.3
remote=
behind=0
ahead=0
dirty=0
branch=main
prev=
upgraded=
EOF
doctor_out "$H" "$C5"
chk "doctor sai 0 com no-stable" "$RC" "0"
grep -q "^warn .*atualização: canal stable, e o origin ainda não tem a tag 'stable'" "$OUTF" \
  && ok "doctor avisa (warn, não fail) o no-stable" \
  || bad "doctor não explicou no-stable ($(grep -E '^(ok|warn) .*atualiza' "$OUTF" | head -1))"

next_home; doctor_out "$H" "$C1"     # C1 está exatamente na tag stable
grep -q '^ok .*canal de atualização: stable — HEAD é exatamente a tag aprovada pela CI' "$OUTF" \
  && ok "doctor situa o HEAD em relação à tag" \
  || bad "doctor não situou o HEAD ($(grep -E 'canal de atualização' "$OUTF" | head -1))"

next_home; printf 'update_channel: main\n' > "$H/config.yaml"; doctor_out "$H" "$C1"
grep -q '^ok .*canal de atualização: main (topo do origin/main, verde ou não)' "$OUTF" \
  && ok "doctor mostra o canal main e ensina o stable" \
  || bad "doctor não mostrou o canal main ($(grep -E 'canal de atualização' "$OUTF" | head -1))"

next_home; printf 'update_channel: nightly\n' > "$H/config.yaml"; doctor_out "$H" "$C1"
chk "doctor não falha por canal torto" "$RC" "0"
grep -q "^warn .*canal de atualização: valor inválido 'nightly' em config.yaml" "$OUTF" \
  && ok "doctor avisa canal inválido" \
  || bad "doctor calou o canal inválido ($(grep -E 'canal de atualização' "$OUTF" | head -1))"
has "aviso ensina o fix" "maestro upgrade --set update_channel=stable|main" "$OUTF"

if [[ $fail -eq 0 ]]; then echo "test-update-channel: OK"; else echo "test-update-channel: FALHOU"; fi
exit $fail
