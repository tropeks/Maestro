#!/usr/bin/env bash
# E19 / S-1903 — metade CLI do auto-update: `maestro upgrade` e os dois checks
# novos do doctor (check_update_state, check_upstream).
#
# `maestro upgrade` é AÇÃO EXPLÍCITA DO HUMANO: a lib recebe UPD_MANUAL=1 e por
# isso ignora update_check:false e MAESTRO_NO_UPDATE_CHECK — o CLI nunca fica
# mudo quando alguém pede satisfação diretamente (diferente do hook, que
# respeita as duas trancas). Hermético: remoto bare em file://, clone de
# FIXTURE nunca o repo real; MAESTRO_HOME em mktemp; MAESTRO_UPDATE_INTERVAL=0
# para toda checagem buscar sem depender de --force.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
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
# Fixture: um "plugin" mínimo o bastante para o ff-only e o changelog — sem
# hooks/bin (o CLI sob teste é sempre o $BIN do repo real; $UPD_REPO é só o
# alvo do git).
# ---------------------------------------------------------------------------
SRC="$SANDBOX/src"; mkdir -p "$SRC/.claude-plugin"
printf '{"name":"maestro","version":"1.0.0"}\n' > "$SRC/.claude-plugin/plugin.json"
printf '# CHANGELOG\n\n## [1.0.0]\n- base\n' > "$SRC/CHANGELOG.md"
G -C "$SRC" init -q -b main
G -C "$SRC" add -A && G -C "$SRC" commit -qm "v1.0.0"

REMOTE="$SANDBOX/remote.git"
git clone -q --bare "$SRC" "$REMOTE"
CLONE="$SANDBOX/clone"
git clone -q "$REMOTE" "$CLONE" 2>/dev/null
G -C "$CLONE" checkout -q main 2>/dev/null || :

publish() { # publish <versão> — versão nova no plugin.json + entrada no CHANGELOG, push
  printf '{"name":"maestro","version":"%s"}\n' "$1" > "$SRC/.claude-plugin/plugin.json"
  printf '\n## [%s]\n- mudança %s\n' "$1" "$1" >> "$SRC/CHANGELOG.md"
  G -C "$SRC" add -A && G -C "$SRC" commit -qm "v$1"
  G -C "$SRC" push -q "$REMOTE" main
}

OUTF="$SANDBOX/out"; ERRF="$SANDBOX/err"
U() { # U <home> [VAR=VAL ...] -- <args de maestro upgrade>
  local home="$1"; shift
  local extra=()
  while [[ "${1:-}" != "--" ]]; do extra+=("$1"); shift; done
  shift
  env MAESTRO_HOME="$home" MAESTRO_UPDATE_REPO="$CLONE" MAESTRO_UPDATE_TIMEOUT=5 \
      MAESTRO_UPDATE_INTERVAL=0 "${extra[@]}" "$BIN" upgrade "$@" >"$OUTF" 2>"$ERRF"
  RC=$?
}
state() { sed -n "s/^$2=\(.*\)$/\1/p" "$1/update-state" 2>/dev/null | head -1; }
head_of() { git -C "$1" rev-parse HEAD; }
n=0; next_home() { n=$((n+1)); H="$SANDBOX/home$n"; mkdir -p "$H"; }

# ---------------------------------------------------------------------------
echo "-- sem flag, em dia: mensagem e exit 0"
next_home; U "$H" --
chk "exit 0" "$RC" "0"
has "mensagem de 'já é a última versão'" "Maestro v1.0.0 já é a última versão (origin/main)" "$OUTF"
chk "estado current" "$(state "$H" result)" "current"

# ---------------------------------------------------------------------------
echo "-- sem flag, disponível: aplica, HEAD acompanha origin, changelog e log"
publish 1.0.1
BEFORE_101=$(head_of "$CLONE")
next_home; U "$H" --
chk "exit 0" "$RC" "0"
has "resumo com as duas versões e a contagem" "Maestro v1.0.0 → v1.0.1 (1 commit(s))" "$OUTF"
chk "HEAD == origin/main" "$(head_of "$CLONE")" "$(git -C "$CLONE" rev-parse refs/remotes/origin/main)"
has "delta do changelog: cabeçalho" "## [1.0.1]" "$OUTF"
has "delta do changelog: linha" "mudança 1.0.1" "$OUTF"
has "linha de rollback com sha curto" "maestro upgrade --rollback (volta para ${BEFORE_101:0:7})" "$OUTF"
has "fallback do doctor (repo de update != repo do CLI)" "doctor: rode maestro doctor no plugin atualizado" "$OUTF"
if grep -q '"event":"upgrade"' "$H/logs/routing.jsonl" 2>/dev/null; then
  line=$(grep '"event":"upgrade"' "$H/logs/routing.jsonl" | head -1)
  [[ "$line" == *'"from":"1.0.0"'* && "$line" == *'"to":"1.0.1"'* && "$line" == *'"via":"manual"'* ]] \
    && ok "evento upgrade carrega from/to/via=manual" || bad "evento upgrade incompleto: $line"
else
  bad "evento upgrade ausente no log"
fi

# ---------------------------------------------------------------------------
echo "-- blocked/dirty: exit 1, HEAD intacto, mensagem certa"
publish 1.0.2
BEFORE_DIRTY=$(head_of "$CLONE")
echo dirty >> "$CLONE/CHANGELOG.md"
next_home; U "$H" --
chk "exit 1" "$RC" "1"
chk "HEAD intacto" "$(head_of "$CLONE")" "$BEFORE_DIRTY"
has "mensagem de árvore suja" "árvore suja — commite ou guarde (git stash) antes" "$OUTF"
chk "estado blocked" "$(state "$H" result)" "blocked"
chk "motivo dirty" "$(state "$H" reason)" "dirty"
git -C "$CLONE" checkout -q -- CHANGELOG.md

echo "-- blocked/ahead: exit 1, HEAD intacto (nada mergeado)"
echo local > "$CLONE/LOCAL.md"; G -C "$CLONE" add -A; G -C "$CLONE" commit -qm "local"
BEFORE_AHEAD=$(head_of "$CLONE")
next_home; U "$H" --
chk "exit 1" "$RC" "1"
chk "HEAD intacto" "$(head_of "$CLONE")" "$BEFORE_AHEAD"
has "mensagem de árvore à frente" "à frente do origin — máquina de desenvolvimento: git push, não pull" "$OUTF"
chk "motivo ahead" "$(state "$H" reason)" "ahead"
G -C "$CLONE" reset -q --hard "$BEFORE_DIRTY"   # volta para 1.0.1, limpo, 1.0.2 pendente

# ---------------------------------------------------------------------------
echo "-- sem flag, disponível de novo: aplica 1.0.1 → 1.0.2 (para o rollback a seguir)"
next_home; U "$H" --
chk "exit 0" "$RC" "0"
chk "HEAD == origin/main (1.0.2)" "$(head_of "$CLONE")" "$(git -C "$CLONE" rev-parse refs/remotes/origin/main)"
RB_HOME="$H"   # reaproveita este home para os testes de --rollback

echo "-- --rollback: HEAD volta ao anterior, evento via=rollback, exit 0"
U "$RB_HOME" -- --rollback
chk "exit 0" "$RC" "0"
chk "HEAD volta ao commit anterior (1.0.1)" "$(head_of "$CLONE")" "$BEFORE_DIRTY"
has "mensagem de rollback" "Maestro v1.0.2 → v1.0.1 (rollback); maestro upgrade reaplica" "$OUTF"
if grep -q '"via":"rollback"' "$RB_HOME/logs/routing.jsonl" 2>/dev/null; then
  ok "evento upgrade via=rollback no log"
else
  bad "evento upgrade via=rollback ausente"
fi

echo "-- segundo --rollback no mesmo home: nada para desfazer, exit 1"
U "$RB_HOME" -- --rollback
chk "exit 1" "$RC" "1"
has "mensagem 'nada para desfazer' (die vai para stderr)" "nada para desfazer — nenhum upgrade registrado" "$ERRF"

# ---------------------------------------------------------------------------
echo "-- --check: disponível → exit 1 (clone em 1.0.1, 1.0.2 pendente no origin)"
next_home; U "$H" -- --check
chk "exit 1" "$RC" "1"
has "linha de status com as duas versões" "atualização: v1.0.1 → v1.0.2 disponível (1 commit(s)) — maestro upgrade" "$OUTF"

echo "-- --check --force: nunca aplica, mesmo com o comando explícito"
BEFORE_CHECK=$(head_of "$CLONE")
next_home; U "$H" -- --check --force
chk "exit 1" "$RC" "1"
chk "HEAD intacto: --check nunca aplica" "$(head_of "$CLONE")" "$BEFORE_CHECK"

echo "-- --check: em dia → exit 0"
next_home; U "$H" --                      # aplica 1.0.1 -> 1.0.2
next_home; U "$H" -- --check
chk "exit 0" "$RC" "0"
has "linha 'em dia'" "atualização: em dia (v1.0.2)" "$OUTF"

echo "-- --check: falhou (sem origin) → exit 2"
git -C "$CLONE" remote rename origin upstream
next_home; U "$H" -- --check
chk "exit 2" "$RC" "2"
has "linha 'falhou'" "atualização: falhou (no-remote)" "$OUTF"
git -C "$CLONE" remote rename upstream origin

# ---------------------------------------------------------------------------
echo "-- --snooze três vezes: 24h -> 48h -> 7 dias, arquivo com nível 3"
publish 1.0.3
next_home
U "$H" -- --snooze
chk "exit 0" "$RC" "0"
has "primeiro snooze: 24h" "aviso adiado por 24h (v1.0.3)" "$OUTF"
U "$H" -- --snooze
has "segundo snooze: 48h" "aviso adiado por 48h (v1.0.3)" "$OUTF"
U "$H" -- --snooze
has "terceiro snooze: 7 dias" "aviso adiado por 7 dias (v1.0.3)" "$OUTF"
[[ -f "$H/update-snoozed" ]] && lvl=$(awk 'NR==1{print $3}' "$H/update-snoozed") || lvl=""
chk "update-snoozed no nível 3" "$lvl" "3"

echo "-- --snooze quando já em dia: 'nada a adiar'"
next_home; U "$H" --                      # aplica 1.0.2 -> 1.0.3
next_home; U "$H" -- --snooze
chk "exit 0" "$RC" "0"
has "mensagem 'nada a adiar'" "nada a adiar: já na última versão" "$OUTF"

# ---------------------------------------------------------------------------
echo "-- --set: chave válida grava em config.yaml"
next_home
U "$H" -- --set update_check=false
chk "exit 0" "$RC" "0"
has "confirmação no stdout" "config.yaml: update_check = false" "$OUTF"
has "config.yaml gravado" "update_check: false" "$H/config.yaml"

U "$H" -- --set auto_upgrade=false
has "auto_upgrade gravado" "auto_upgrade: false" "$H/config.yaml"

U "$H" -- --set update_interval_hours=48
has "update_interval_hours gravado" "update_interval_hours: 48" "$H/config.yaml"

echo "-- --set: chave/valor inválidos saem 1"
U "$H" -- --set update_check=talvez
chk "valor fora do domínio → exit 1" "$RC" "1"
U "$H" -- --set update_interval_hours=0
chk "fora do intervalo 1..720 → exit 1" "$RC" "1"
U "$H" -- --set update_interval_hours=999
chk "acima de 720 → exit 1" "$RC" "1"
U "$H" -- --set chave_desconhecida=1
chk "chave fora do vocabulário → exit 1" "$RC" "1"
U "$H" -- --set semigual
chk "sem '=' → exit 1" "$RC" "1"

echo "-- flag desconhecida sai 1"
U "$H" -- --bogus
chk "flag desconhecida → exit 1" "$RC" "1"

# ---------------------------------------------------------------------------
echo "-- update_check:false em config.yaml NÃO impede maestro upgrade manual"
next_home; printf 'update_check: false\n' > "$H/config.yaml"
U "$H" -- --check
hasnt "não fica 'desligada' — a checagem manual roda de verdade" "verificação desligada" "$OUTF"
[[ -f "$H/update-state" ]] && ok "update-state foi gravado (checagem real aconteceu)" \
  || bad "update-state ausente — a checagem manual foi ignorada"

echo "-- MAESTRO_NO_UPDATE_CHECK=1 também NÃO impede maestro upgrade manual"
next_home
U "$H" MAESTRO_NO_UPDATE_CHECK=1 -- --check
hasnt "não fica 'desligada' mesmo com o env" "verificação desligada" "$OUTF"
[[ -f "$H/update-state" ]] && ok "update-state foi gravado (env não bloqueou o CLI)" \
  || bad "update-state ausente — MAESTRO_NO_UPDATE_CHECK bloqueou o CLI"

# ---------------------------------------------------------------------------
echo "-- doctor: check_update_state a partir de um update-state escrito à mão"
FX="$SANDBOX/skills"; mkdir -p "$FX"
for s in systematic-debugging requesting-code-review gstack-qa gstack-ship gstack-cso gstack-office-hours; do
  mkdir -p "$FX/$s"; echo v1 > "$FX/$s/SKILL.md"
done
doctor_out() { # doctor_out <home>
  MAESTRO_HOME="$1" MAESTRO_SKILL_DIRS="$FX" MAESTRO_PLUGINS_DIR="$SANDBOX/plugins-vazio" \
    "$BIN" doctor >"$OUTF" 2>&1
  RC=$?
}
update_line() { grep -E '^(ok|warn) .*atualiza' "$OUTF" | head -1; }

next_home
cat > "$H/update-state" <<EOF
schema=maestro-update-state-v1
checked=$(date +%s)
fetched=$(date +%s)
fetch=ok
result=available
reason=
local=1.0.3
remote=1.0.4
behind=1
ahead=0
dirty=0
branch=main
prev=
upgraded=
EOF
doctor_out "$H"
grep -q 'warn atualização disponível: v1.0.3 → v1.0.4 (1 commit(s))' "$OUTF" \
  && ok "doctor avisa atualização disponível" || bad "doctor não avisou disponível ($(update_line))"

next_home
cat > "$H/update-state" <<EOF
schema=maestro-update-state-v1
checked=$(date +%s)
fetched=0
fetch=failed
result=failed
reason=no-remote-ref
local=1.0.3
remote=
behind=0
ahead=0
dirty=0
branch=main
prev=
upgraded=
EOF
doctor_out "$H"
grep -q 'warn verificação de atualização falhou (no-remote-ref)' "$OUTF" \
  && ok "doctor avisa falha na verificação" || bad "doctor não avisou falha ($(update_line))"

next_home
doctor_out "$H"
grep -q 'ok   atualização: ainda não verificada' "$OUTF" \
  && ok "sem update-state: ok, nunca aviso" || bad "ausência de update-state não deu ok ($(update_line))"

echo
# ---------------------------------------------------------------------------
# Achados do review (2026-09-01): --set sem valor, check_upstream testável,
# rollback recusa quando há commit local depois do upgrade.
# ---------------------------------------------------------------------------
echo "-- --set como último argumento: die de validação, não erro cru do bash"
next_home; U "$H" -- --set
chk "exit 1" "$RC" "1"
has "mensagem de formato" "formato inválido (esperado chave=valor)" "$ERRF"
hasnt "sem erro cru de shift" "shift count" "$ERRF"

echo "-- doctor: check_upstream (higiene de publicação) nos três ramos"
UPCLONE="$SANDBOX/upclone"; git clone -q "$REMOTE" "$UPCLONE" 2>/dev/null
G -C "$UPCLONE" checkout -q main 2>/dev/null || :
doctor_up() { # doctor_up <home> <repo>
  MAESTRO_HOME="$1" MAESTRO_SKILL_DIRS="$FX" MAESTRO_PLUGINS_DIR="$SANDBOX/plugins-vazio" \
    MAESTRO_UPDATE_REPO="$2" "$BIN" doctor >"$OUTF" 2>&1
  RC=$?
}
pub_line() { grep -E '^(ok|warn|skip) .*publicação' "$OUTF" | head -1; }
next_home; doctor_up "$H" "$UPCLONE"
grep -q '^ok .*publicação: em dia com origin/main' "$OUTF" \
  && ok "clone limpo com upstream: em dia" || bad "esperava 'em dia' ($(pub_line))"
G -C "$UPCLONE" branch --unset-upstream >/dev/null 2>&1
next_home; doctor_up "$H" "$UPCLONE"
grep -q '^warn .*publicação: branch main sem upstream' "$OUTF" \
  && ok "main sem upstream vira warn" || bad "esperava warn de upstream ($(pub_line))"
grep -q 'git branch --set-upstream-to=origin/main main' "$OUTF" \
  && ok "warn ensina o comando" || bad "warn sem o comando"
echo x > "$UPCLONE/x.md"; G -C "$UPCLONE" add -A; G -C "$UPCLONE" commit -qm local
next_home; doctor_up "$H" "$UPCLONE"
grep -q '^warn .*publicação: 1 commit(s) sem push — outras máquinas não recebem' "$OUTF" \
  && ok "commit sem push vira warn (vence o upstream)" || bad "esperava warn de push ($(pub_line))"
next_home; doctor_up "$H" "$SANDBOX/nao-e-repo-$$"
grep -q '^skip .*publicação: fora de um clone git' "$OUTF" \
  && ok "fora de git: skip" || bad "esperava skip ($(pub_line))"

echo "-- --rollback recusa quando há commit local depois do upgrade"
CLONE2="$SANDBOX/clone2"; git clone -q "$REMOTE" "$CLONE2" 2>/dev/null
G -C "$CLONE2" checkout -q main 2>/dev/null || :
G -C "$CLONE2" reset -q --hard "$(git -C "$CLONE2" rev-list --max-parents=0 HEAD | tail -1)"
next_home; DIV_HOME="$H"
U "$DIV_HOME" MAESTRO_UPDATE_REPO="$CLONE2" -- 
chk "upgrade aplica no clone2" "$RC" "0"
UPGRADED_HEAD=$(head_of "$CLONE2")
[[ -n "$(state "$DIV_HOME" prev)" ]] && ok "prev gravado" || bad "prev ausente"
chk "head gravado = HEAD pós-upgrade" "$(state "$DIV_HOME" head)" "$UPGRADED_HEAD"
echo meu > "$CLONE2/meu.md"; G -C "$CLONE2" add -A; G -C "$CLONE2" commit -qm "trabalho local"
LOCAL_HEAD=$(head_of "$CLONE2")
U "$DIV_HOME" MAESTRO_UPDATE_REPO="$CLONE2" -- --rollback
chk "exit 1" "$RC" "1"
has "mensagem nomeia o commit local" "há commit local depois do upgrade" "$ERRF"
chk "HEAD intacto (commit local preservado)" "$(head_of "$CLONE2")" "$LOCAL_HEAD"
G -C "$CLONE2" reset -q --keep "$UPGRADED_HEAD"
U "$DIV_HOME" MAESTRO_UPDATE_REPO="$CLONE2" -- --rollback
chk "sem o commit local, o rollback volta a funcionar" "$RC" "0"
chk "estado após rollback é o MEDIDO (available)" "$(state "$DIV_HOME" result)" "available"
chk "prev consumido" "$(state "$DIV_HOME" prev)" ""

if [[ $fail -eq 0 ]]; then echo "test-upgrade: OK"; else echo "test-upgrade: FALHOU"; fi
exit $fail
