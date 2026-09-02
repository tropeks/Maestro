#!/usr/bin/env bash
# E19 / S-1901 — auto-update via git no SessionStart.
#
# Invariantes: rede nunca quebra a sessão (fetch falho → exit 0, injeção íntegra,
# estado diz "failed"); a máquina de desenvolvimento nunca é sobrescrita (árvore
# suja ou à frente → blocked, nada mergeado); ff-only aplica só quando é
# estritamente seguro e a sessão inteira nasce na versão nova (re-exec do hook
# novo); o intervalo segura o fetch; snooze cala só o aviso; kill-switch e
# MAESTRO_NO_UPDATE_CHECK desligam tudo. Silêncio NUNCA é "atualizado": o
# update-state registra o resultado, inclusive a falha.
#
# Hermético: remoto bare em file:// dentro do mktemp; MAESTRO_UPDATE_REPO aponta
# para um clone de FIXTURE (nunca o repo real); MAESTRO_HOME isolado.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
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
# Fixture: um "plugin" mínimo (hooks reais copiados + config + plugin.json) num
# remoto bare; o clone é o que o hook vai atualizar.
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

REMOTE="$SANDBOX/remote.git"
git clone -q --bare "$SRC" "$REMOTE"
CLONE="$SANDBOX/clone"
git clone -q "$REMOTE" "$CLONE" 2>/dev/null
G -C "$CLONE" checkout -q main 2>/dev/null || :

# publica uma versão nova no remoto (via o working copy de origem)
publish() { # publish <versão> [linha-extra-no-ethos]
  printf '{"name":"maestro","version":"%s"}\n' "$1" > "$SRC/.claude-plugin/plugin.json"
  printf '\n## [%s]\n- mudança %s\n' "$1" "$1" >> "$SRC/CHANGELOG.md"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" >> "$SRC/config/execution-ethos.md"
  G -C "$SRC" add -A && G -C "$SRC" commit -qm "v$1"
  G -C "$SRC" push -q "$REMOTE" main
}

# run <home> [VAR=VAL ...] → OUT/ERR/RC; o hook real roda, apontado para o clone
run() {
  local home="$1"; shift
  local outf="$SANDBOX/out" errf="$SANDBOX/err" proj="$SANDBOX/proj"
  mkdir -p "$proj"
  printf '{"session_id":"upd-test-1"}' \
    | env MAESTRO_HOME="$home" CLAUDE_PROJECT_DIR="$proj" MAESTRO_UPDATE_REPO="$CLONE" \
          MAESTRO_NO_UPDATE_CHECK=0 MAESTRO_UPDATE_INTERVAL=0 MAESTRO_UPDATE_TIMEOUT=5 "$@" \
          bash "$HOOK" >"$outf" 2>"$errf"
  RC=$?
  OUT="$outf"; ERR="$errf"
}
state() { sed -n "s/^$2=\(.*\)$/\1/p" "$1/update-state" 2>/dev/null | head -1; }
head_of() { git -C "$1" rev-parse HEAD; }
n=0; next_home() { n=$((n+1)); H="$SANDBOX/home$n"; mkdir -p "$H"; }  # sem subshell: o contador precisa avançar

# ---------------------------------------------------------------------------
echo "-- em dia: nenhuma linha de atualização; estado current"
next_home; run "$H"
chk "hook sai 0" "$RC" "0"
has "injeção íntegra" "INSTRUÇÃO CANÔNICA" "$OUT"
hasnt "sem aviso quando em dia" "atualização:" "$OUT"
chk "estado current" "$(state "$H" result)" "current"
chk "fetch ok" "$(state "$H" fetch)" "ok"
chk "versão local lida" "$(state "$H" local)" "1.0.0"

echo "-- desligada por env: nada roda, nada é gravado"
next_home; run "$H" MAESTRO_NO_UPDATE_CHECK=1
chk "hook sai 0" "$RC" "0"
[[ -f "$H/update-state" ]] && bad "estado gravado com checagem desligada" || ok "sem update-state"

echo "-- desligada por config.yaml (update_check: false)"
next_home; printf 'update_check: false\n' > "$H/config.yaml"; run "$H"
[[ -f "$H/update-state" ]] && bad "config ignorada" || ok "config.yaml desliga a checagem"

echo "-- kill-switch: nem a lib entra"
next_home; run "$H" MAESTRO_OFF=1
chk "hook sai 0" "$RC" "0"
[[ -f "$H/update-state" ]] && bad "kill-switch não segurou o update" || ok "kill-switch vence"

# ---------------------------------------------------------------------------
echo "-- versão nova no origin, auto_upgrade desligado: avisa, não merge"
publish 1.0.1
BEFORE=$(head_of "$CLONE")
next_home; run "$H" MAESTRO_AUTO_UPGRADE=0
chk "hook sai 0" "$RC" "0"
has "aviso com as duas versões" "atualização: v1.0.0 → v1.0.1 (1 commit(s) no origin)" "$OUT"
has "aviso ensina o comando" "maestro upgrade" "$OUT"
chk "HEAD intacto" "$(head_of "$CLONE")" "$BEFORE"
chk "estado available" "$(state "$H" result)" "available"
chk "remote 1.0.1" "$(state "$H" remote)" "1.0.1"
chk "behind 1" "$(state "$H" behind)" "1"
hasnt "sem auto, o hook velho segue (nada re-executado)" "atualizado agora" "$OUT"

echo "-- snooze cala o aviso da versão adiada, estado continua available"
sha=$(git -C "$CLONE" rev-parse refs/remotes/origin/main)
printf '%s %s 1\n' "$sha" "$(( $(date +%s) + 3600 ))" > "$H/update-snoozed"
run "$H" MAESTRO_AUTO_UPGRADE=0
hasnt "snooze silencia" "atualização:" "$OUT"
chk "estado segue available" "$(state "$H" result)" "available"
printf '%s %s 1\n' "$sha" "$(( $(date +%s) - 10 ))" > "$H/update-snoozed"
run "$H" MAESTRO_AUTO_UPGRADE=0
has "snooze vencido volta a avisar" "atualização: v1.0.0 → v1.0.1" "$OUT"
printf 'outrosha %s 1\n' "$(( $(date +%s) + 3600 ))" > "$H/update-snoozed"
run "$H" MAESTRO_AUTO_UPGRADE=0
has "snooze de OUTRA versão não cala esta" "atualização: v1.0.0 → v1.0.1" "$OUT"

# ---------------------------------------------------------------------------
echo "-- máquina de desenvolvimento: árvore suja → blocked, nada mergeado"
echo dirty >> "$CLONE/CHANGELOG.md"
next_home; run "$H"
chk "hook sai 0" "$RC" "0"
chk "HEAD intacto" "$(head_of "$CLONE")" "$BEFORE"
chk "estado blocked" "$(state "$H" result)" "blocked"
chk "motivo dirty" "$(state "$H" reason)" "dirty"
has "aviso nomeia a máquina de dev" "máquina de desenvolvimento: push, não pull" "$OUT"
has "aviso diz 'suja'" "está suja" "$OUT"
git -C "$CLONE" checkout -q -- CHANGELOG.md

echo "-- máquina de desenvolvimento: commit local à frente → blocked"
echo local > "$CLONE/LOCAL.md"; G -C "$CLONE" add -A; G -C "$CLONE" commit -qm "local"
AHEAD=$(head_of "$CLONE")
next_home; run "$H"
chk "HEAD intacto" "$(head_of "$CLONE")" "$AHEAD"
chk "estado blocked" "$(state "$H" result)" "blocked"
chk "motivo ahead" "$(state "$H" reason)" "ahead"
chk "ahead 1" "$(state "$H" ahead)" "1"
has "aviso diz 'à frente'" "está à frente" "$OUT"
G -C "$CLONE" reset -q --hard "$BEFORE"

echo "-- fora da branch rastreada → blocked (branch)"
G -C "$CLONE" checkout -q -b feature
next_home; run "$H"
chk "estado blocked" "$(state "$H" result)" "blocked"
chk "motivo branch" "$(state "$H" reason)" "branch"
has "aviso genérico com o motivo" "merge bloqueado (branch)" "$OUT"
G -C "$CLONE" checkout -q main; G -C "$CLONE" branch -q -D feature

# ---------------------------------------------------------------------------
echo "-- auto_upgrade (default): ff-only aplica e a sessão nasce na versão nova"
publish 1.0.2 "LINHA-NOVA-DO-ETHOS-102"
next_home; run "$H"
chk "hook sai 0" "$RC" "0"
chk "HEAD == origin/main" "$(head_of "$CLONE")" "$(git -C "$CLONE" rev-parse refs/remotes/origin/main)"
has "aviso 'atualizado agora' com as versões" "atualizado agora: v1.0.0 → v1.0.2" "$OUT"
has "aviso ensina o rollback" "maestro upgrade --rollback" "$OUT"
has "cabeçalho já na versão nova (hook novo re-executado)" "Maestro v1.0.2" "$OUT"
has "conteúdo novo do repo injetado na MESMA sessão" "LINHA-NOVA-DO-ETHOS-102" "$OUT"
has "session_id preservado no re-exec" "session_id: upd-test-1" "$OUT"
chk "estado current após aplicar" "$(state "$H" result)" "current"
chk "motivo upgraded" "$(state "$H" reason)" "upgraded"
chk "prev guardado para rollback" "$(state "$H" prev)" "$BEFORE"
[[ "$(state "$H" upgraded)" =~ ^[0-9]+$ ]] && ok "carimbo upgraded" || bad "carimbo upgraded ausente"
if [[ -f "$H/logs/routing.jsonl" ]] && grep -q '"event":"upgrade"' "$H/logs/routing.jsonl"; then
  ok "evento upgrade no log"
  line=$(grep '"event":"upgrade"' "$H/logs/routing.jsonl" | head -1)
  [[ "$line" == *'"from":"1.0.0"'* && "$line" == *'"to":"1.0.2"'* && "$line" == *'"via":"auto"'* ]] \
    && ok "evento carrega from/to/via" || bad "evento upgrade sem from/to/via: $line"
  [[ "$line" == */* ]] && bad "log vazou caminho" || ok "log sem caminho"
else
  bad "evento upgrade ausente no log"
fi
# a segunda sessão está em dia e não repete o aviso
run "$H"
hasnt "sessão seguinte silenciosa" "atualizado agora" "$OUT"
hasnt "sem aviso de atualização" "atualização:" "$OUT"

# ---------------------------------------------------------------------------
echo "-- intervalo: dentro dele não há fetch (versão nova fica invisível)"
publish 1.0.3
next_home; run "$H"      # primeiro contato: fetch + auto-merge → 1.0.3
chk "primeiro contato atualiza" "$(state "$H" local)" "1.0.3"
publish 1.0.4
run "$H" MAESTRO_UPDATE_INTERVAL=86400
chk "dentro do intervalo: sem fetch" "$(state "$H" fetch)" "skipped"
chk "dentro do intervalo: segue 1.0.3" "$(state "$H" local)" "1.0.3"
hasnt "sem aviso do que não foi buscado" "1.0.4" "$OUT"
run "$H"                      # intervalo 0 → busca e aplica
chk "intervalo vencido: atualiza para 1.0.4" "$(state "$H" local)" "1.0.4"
has "sessão nasce na 1.0.4" "Maestro v1.0.4" "$OUT"

# ---------------------------------------------------------------------------
echo "-- rede quebrada: sessão íntegra, exit 0, estado diz que falhou"
publish 1.0.5
git -C "$CLONE" remote set-url origin "$SANDBOX/nao-existe.git"
next_home; run "$H"
chk "hook sai 0" "$RC" "0"
has "injeção íntegra" "INSTRUÇÃO CANÔNICA" "$OUT"
has "session_id presente" "session_id: upd-test-1" "$OUT"
hasnt "sem aviso quando a rede falhou" "atualização:" "$OUT"
chk "fetch failed registrado" "$(state "$H" fetch)" "failed"
chk "posição medida contra o último ref conhecido" "$(state "$H" result)" "current"
chk "não avançou" "$(state "$H" local)" "1.0.4"
git -C "$CLONE" remote set-url origin "$REMOTE"

echo "-- remoto ausente: failed/no-remote, sessão íntegra"
git -C "$CLONE" remote rename origin upstream
next_home; run "$H"
chk "hook sai 0" "$RC" "0"
has "injeção íntegra" "INSTRUÇÃO CANÔNICA" "$OUT"
chk "estado failed" "$(state "$H" result)" "failed"
chk "motivo no-remote" "$(state "$H" reason)" "no-remote"
git -C "$CLONE" remote rename upstream origin

echo "-- não é repositório: failed/not-a-repo, sessão íntegra"
NOREPO="$SANDBOX/norepo"; mkdir -p "$NOREPO/.claude-plugin"
printf '{"name":"maestro","version":"9.9.9"}\n' > "$NOREPO/.claude-plugin/plugin.json"
next_home
printf '{"session_id":"upd-test-1"}' | env MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$SANDBOX/proj" \
  MAESTRO_UPDATE_REPO="$NOREPO" MAESTRO_NO_UPDATE_CHECK=0 MAESTRO_UPDATE_INTERVAL=0 \
  bash "$HOOK" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?
chk "hook sai 0" "$RC" "0"
has "injeção íntegra" "INSTRUÇÃO CANÔNICA" "$SANDBOX/out"
chk "motivo not-a-repo" "$(state "$H" reason)" "not-a-repo"

# ---------------------------------------------------------------------------
echo "-- re-exec: a trava anti-loop e o aviso vindo do env"
next_home
printf '{"session_id":"upd-test-1"}' | env MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$SANDBOX/proj" \
  MAESTRO_UPDATE_REPO="$CLONE" MAESTRO_NO_UPDATE_CHECK=0 MAESTRO_UPDATE_INTERVAL=0 \
  MAESTRO_UPDATE_REEXEC=1 MAESTRO_UPDATED_FROM=1.0.0 MAESTRO_UPDATED_TO=1.0.5 \
  bash "$HOOK" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?
chk "hook sai 0" "$RC" "0"
has "aviso composto do env" "atualizado agora: v1.0.0 → v1.0.5" "$SANDBOX/out"
[[ -f "$H/update-state" ]] && bad "re-exec voltou a checar (loop)" || ok "re-exec não checa de novo"
printf '{"session_id":"upd-test-1"}' | env MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$SANDBOX/proj" \
  MAESTRO_UPDATE_REPO="$CLONE" MAESTRO_NO_UPDATE_CHECK=0 MAESTRO_UPDATE_REEXEC=1 \
  MAESTRO_UPDATED_FROM='1.0.0"; rm -rf /' MAESTRO_UPDATED_TO='$(id)' \
  bash "$HOOK" >"$SANDBOX/out" 2>"$SANDBOX/err"
has "versão inválida no env vira '?'" "atualizado agora: v? → v?" "$SANDBOX/out"
hasnt "payload não entra na injeção" "rm -rf" "$SANDBOX/out"

# ---------------------------------------------------------------------------
echo "-- orçamento: a linha de atualização não estoura o teto"
publish 1.0.6
next_home; run "$H" MAESTRO_AUTO_UPGRADE=0
bytes=$(wc -c < "$OUT" | tr -d ' ')
(( bytes <= 8000 )) && ok "injeção com aviso: ${bytes}B ≤ 8000B" || bad "injeção estourou: ${bytes}B"
run "$H" MAESTRO_AUTO_UPGRADE=0 MAESTRO_INJECTION_BUDGET=600
has "no orçamento mínimo, o aviso sobrevive (cabeçalho nunca trunca)" "atualização: v" "$OUT"
has "instrução canônica sobrevive" "INSTRUÇÃO CANÔNICA" "$OUT"

echo
# ---------------------------------------------------------------------------
# Achados do review (2026-09-01): race entre duas sessões não pode sobrescrever
# o prev do rollback; sem `timeout` e sem `flock` o fetch continua com teto e
# a seção crítica continua não bloqueante.
# ---------------------------------------------------------------------------
echo "-- race: HEAD mudou entre a medição e o apply → raced, prev intacto"
publish 1.0.7
next_home
( export MAESTRO_HOME="$H" MAESTRO_UPDATE_REPO="$CLONE" MAESTRO_UPDATE_INTERVAL=0 MAESTRO_NO_UPDATE_CHECK=0
  source "$REPO/hooks/lib/update-check.sh"
  maestro_update_check
  echo "state1=$UPD_STATE"
  git -C "$CLONE" merge -q --ff-only refs/remotes/origin/main >/dev/null 2>&1   # "outra sessão" aplicou
  if maestro_update_apply; then echo "apply=0"; else echo "apply=1 reason=$UPD_REASON"; fi
) > "$SANDBOX/race.out" 2>&1
has "mediu available" "state1=available" "$SANDBOX/race.out"
has "apply recusa com raced" "apply=1 reason=raced" "$SANDBOX/race.out"
chk "prev NÃO foi sobrescrito" "$(state "$H" prev)" ""
chk "clone acompanha o origin (o merge da 'outra sessão' ficou)" "$(head_of "$CLONE")" "$(git -C "$CLONE" rev-parse refs/remotes/origin/main)"

echo "-- sem timeout e sem flock: fetch travado não trava a sessão (watchdog + lock mkdir)"
TB="$SANDBOX/tbin"; WB="$SANDBOX/wbin"; mkdir -p "$TB" "$WB"
for f in /usr/bin/* /bin/*; do
  b="${f##*/}"; [[ "$b" == timeout || "$b" == flock ]] && continue
  [[ -e "$TB/$b" ]] || ln -s "$f" "$TB/$b" 2>/dev/null || :
done
REALGIT=$(command -v git)
cat > "$WB/git" <<WRAP
#!/bin/bash
for a in "\$@"; do [[ "\$a" == fetch ]] && { sleep 30; exit 1; }; done
exec "$REALGIT" "\$@"
WRAP
chmod +x "$WB/git"
publish 1.0.8
next_home
t0=$(date +%s)
printf '{"session_id":"upd-test-1"}' | env -i HOME="$HOME" PATH="$WB:$TB" MAESTRO_HOME="$H" \
  CLAUDE_PROJECT_DIR="$SANDBOX/proj" MAESTRO_UPDATE_REPO="$CLONE" MAESTRO_NO_UPDATE_CHECK=0 \
  MAESTRO_UPDATE_INTERVAL=0 MAESTRO_UPDATE_TIMEOUT=1 bash "$HOOK" >"$SANDBOX/out" 2>"$SANDBOX/err"; RC=$?
t1=$(date +%s)
chk "hook sai 0" "$RC" "0"
(( t1 - t0 < 10 )) && ok "sessão livre em $((t1 - t0))s (fetch travado, teto de 1s)" || bad "hook demorou $((t1 - t0))s — fetch sem teto"
has "injeção íntegra" "INSTRUÇÃO CANÔNICA" "$SANDBOX/out"
chk "fetch registrado como failed" "$(state "$H" fetch)" "failed"
[[ -d "$H/update.lock.d" ]] && bad "lock mkdir ficou órfão" || ok "lock mkdir liberado"
hasnt "1.0.8 invisível (não buscou)" "1.0.8" "$SANDBOX/out"

echo "-- fast path (S-1810): dentro do intervalo e sem mudança, nada de status/rev-list"
FB="$SANDBOX/fbin"; mkdir -p "$FB"
cat > "$FB/git" <<WRAP
#!/bin/bash
for a in "\$@"; do case "\$a" in status|rev-list|show|branch) echo "\$a" >> "$SANDBOX/git-heavy.log";; esac; done
exec "$REALGIT" "\$@"
WRAP
chmod +x "$FB/git"
next_home; run "$H"                       # checagem completa: grava local_sha/remote_sha
chk "estado current" "$(state "$H" result)" "current"
[[ "$(state "$H" local_sha)" =~ ^[0-9a-f]{40}$ ]] && ok "local_sha gravado" || bad "local_sha ausente"
: > "$SANDBOX/git-heavy.log"
run "$H" MAESTRO_UPDATE_INTERVAL=86400 PATH="$FB:$PATH"
chk "segue current" "$(state "$H" result)" "current"
chk "motivo fast-path" "$(state "$H" reason)" "fast-path"
[[ -s "$SANDBOX/git-heavy.log" ]] && bad "fast path chamou git pesado: $(tr '\n' ' ' < "$SANDBOX/git-heavy.log")" || ok "só rev-parse: nenhum status/rev-list/show/branch"
echo local2 > "$CLONE/LOCAL2.md"; G -C "$CLONE" add -A; G -C "$CLONE" commit -qm "local2"
: > "$SANDBOX/git-heavy.log"
run "$H" MAESTRO_UPDATE_INTERVAL=86400 PATH="$FB:$PATH"
[[ -s "$SANDBOX/git-heavy.log" ]] && ok "HEAD mudou: medição completa de novo" || bad "HEAD mudou e o fast path não desarmou"
chk "ahead 1 medido" "$(state "$H" ahead)" "1"
G -C "$CLONE" reset -q --hard "$(git -C "$CLONE" rev-parse refs/remotes/origin/main)"

echo "-- tags viajam com o fetch (S-1904): release tag chega na máquina que só segue main"
publish 1.0.9
G -C "$SRC" tag -a v1.0.9 -m "v1.0.9"; G -C "$SRC" push -q "$REMOTE" v1.0.9
next_home; run "$H"
chk "atualizou para 1.0.9" "$(state "$H" local)" "1.0.9"
chk "tag v1.0.9 presente no clone" "$(git -C "$CLONE" tag -l v1.0.9)" "v1.0.9"
chk "describe vê a release nova" "$(git -C "$CLONE" describe --tags --abbrev=0 2>/dev/null)" "v1.0.9"

if [[ $fail -eq 0 ]]; then echo "test-update-check: OK"; else echo "test-update-check: FALHOU"; fi
exit $fail
