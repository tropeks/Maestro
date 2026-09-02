#!/usr/bin/env bash
# E20 / S-2001 — metade CLI do barramento de telemetria: `maestro telemetry`,
# `maestro retro --all` e o check novo do doctor (check_telemetry).
#
# Por que existe: hooks/lib/telemetry-sync.sh (S-2001) já publica os logs no
# SessionEnd; este teste cobre o que o humano opera na mão — ligar/desligar por
# máquina, forçar push/pull, ler o estado, e agregar duas máquinas no retro sem
# contar o host local duas vezes.
#
# Hermético: remoto bare em file:// dentro do mktemp (nunca a rede real); um
# MAESTRO_HOME por host; MAESTRO_HOST_ID fixo por host (evita depender do
# hostname da máquina que roda a suíte); MAESTRO_TELEMETRY_INTERVAL=0 força
# toda checagem de push a ignorar o intervalo de 24h. O doctor roda com o
# mesmo isolamento de tests/cli/test-install-drift.sh (MAESTRO_SKILL_DIRS,
# MAESTRO_PLUGINS_DIR) — o ~/.claude/plugins real nunca é lido.
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
command -v jq  >/dev/null || { echo "FAIL jq ausente (dependência declarada)"; exit 1; }
G() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# ---------------------------------------------------------------------------
# Fixture: um remoto bare vazio — o barramento inteiro. `-b main` porque o
# clone da lib só recupera órfão em `main` quando o HEAD do bare já é ele.
# ---------------------------------------------------------------------------
REMOTE="$SANDBOX/remote.git"
G init -q --bare -b main "$REMOTE"

home_with_log() { # home_with_log <sid> → MAESTRO_HOME novo com uma decisão no log
  # mktemp, não um contador global: a função roda em subshell quando chamada
  # via `$(...)` — um `n=$((n+1))` se perderia ao sair do subshell e toda
  # chamada devolveria o MESMO diretório (achado real, não hipotético).
  local h; h=$(mktemp -d "$SANDBOX/home.XXXXXX")
  mkdir -p "$h/logs"
  printf '{"ts":"2026-09-01T00:00:00-03:00","event":"decision","session_id":"%s","workflow":"fix","mode":"direct"}\n' "$1" \
    > "$h/logs/routing.jsonl"
  printf '%s' "$h"
}

OUTF="$SANDBOX/out"; ERRF="$SANDBOX/err"
T() { # T <home> [VAR=VAL ...] -- <args de maestro telemetry|retro>
  local home="$1"; shift
  local extra=()
  while [[ "${1:-}" != "--" ]]; do extra+=("$1"); shift; done
  shift
  env MAESTRO_HOME="$home" "${extra[@]}" "$BIN" "$@" >"$OUTF" 2>"$ERRF"
  RC=$?
}
kv() { sed -n "s/^$2=\(.*\)\$/\1/p" "$1/telemetry-state" 2>/dev/null | head -1; }

# ---------------------------------------------------------------------------
echo "-- status desligada: sem telemetry_remote"
# ---------------------------------------------------------------------------
HOMEA=$(home_with_log a1)
T "$HOMEA" -- telemetry --status
chk "exit 0" "$RC" "0"
has "mensagem 'desligada'" "telemetria: desligada (sem telemetry_remote" "$OUTF"

echo "-- telemetry sem flag == --status"
T "$HOMEA" -- telemetry
chk "exit 0" "$RC" "0"
has "default é --status" "telemetria: desligada" "$OUTF"

# ---------------------------------------------------------------------------
echo "-- remote inválida: exit 1, nada gravado"
# ---------------------------------------------------------------------------
T "$HOMEA" -- telemetry --remote 'bad url; rm -rf /'
chk "exit 1" "$RC" "1"
[[ -f "$HOMEA/config.yaml" ]] && bad "config.yaml não deveria existir" || ok "config.yaml não foi gravado"

# ---------------------------------------------------------------------------
echo "-- remote válida: grava config.yaml, --status passa a 'nunca publicou'"
# ---------------------------------------------------------------------------
T "$HOMEA" -- telemetry --remote "$REMOTE"
chk "exit 0" "$RC" "0"
has "confirma a gravação" "config.yaml: telemetry_remote = $REMOTE" "$OUTF"
has "config.yaml tem a chave" "telemetry_remote: $REMOTE" "$HOMEA/config.yaml"

T "$HOMEA" -- telemetry --status
chk "exit 0" "$RC" "0"
has "'configurada, nunca publicou'" "telemetria: configurada, nunca publicou" "$OUTF"

# ---------------------------------------------------------------------------
echo "-- push publica: exit 0, arquivos no remoto, host+routing"
# ---------------------------------------------------------------------------
T "$HOMEA" MAESTRO_HOST_ID=hostaaaa MAESTRO_TELEMETRY_INTERVAL=0 -- telemetry --push
chk "exit 0" "$RC" "0"
has "mensagem de publicação" "telemetria: publicada — host hostaaaa, 1 arquivo(s)" "$OUTF"
TREE=$(git --git-dir="$REMOTE" ls-tree -r --name-only main 2>/dev/null)
grep -qF "logs/hostaaaa/routing-current.jsonl" <<<"$TREE" && ok "publicou routing-current.jsonl" \
  || bad "publicou routing-current.jsonl (árvore: $TREE)"
grep -qF "logs/hostaaaa/HOST" <<<"$TREE" && ok "publicou HOST" || bad "publicou HOST (árvore: $TREE)"
chk "telemetry-state result=pushed" "$(kv "$HOMEA" result)" "pushed"

# ---------------------------------------------------------------------------
echo "-- push de novo sem mudança: 'sem novidade', exit 0"
# ---------------------------------------------------------------------------
T "$HOMEA" MAESTRO_HOST_ID=hostaaaa MAESTRO_TELEMETRY_INTERVAL=0 -- telemetry --push
chk "exit 0" "$RC" "0"
has "'sem novidade'" "telemetria: sem novidade" "$OUTF"
chk "telemetry-state result=nochange" "$(kv "$HOMEA" result)" "nochange"

T "$HOMEA" MAESTRO_HOST_ID=hostaaaa -- telemetry --status
has "status reflete 'sem novidade desde'" "telemetria: sem novidade desde o último push" "$OUTF"

# ---------------------------------------------------------------------------
echo "-- segundo host publica no MESMO remoto"
# ---------------------------------------------------------------------------
HOMEB=$(home_with_log b1)
T "$HOMEB" -- telemetry --remote "$REMOTE"
chk "exit 0" "$RC" "0"
T "$HOMEB" MAESTRO_HOST_ID=hostbbbb MAESTRO_TELEMETRY_INTERVAL=0 -- telemetry --push
chk "exit 0" "$RC" "0"
has "host B publicou" "telemetria: publicada — host hostbbbb" "$OUTF"
TREE=$(git --git-dir="$REMOTE" ls-tree -r --name-only main 2>/dev/null)
grep -qF "logs/hostbbbb/routing-current.jsonl" <<<"$TREE" && ok "dois hosts convivem no remoto (diretórios distintos)" \
  || bad "dois hosts convivem no remoto (árvore: $TREE)"

# ---------------------------------------------------------------------------
echo "-- pull no host A lista os dois hosts"
# ---------------------------------------------------------------------------
T "$HOMEA" MAESTRO_HOST_ID=hostaaaa -- telemetry --pull
chk "exit 0" "$RC" "0"
has "clone em dia, 2 hosts" "telemetria: clone em dia — 2 host(s)" "$OUTF"
has "lista hostaaaa" "hostaaaa (" "$OUTF"
has "lista hostbbbb" "hostbbbb (" "$OUTF"

# ---------------------------------------------------------------------------
echo "-- retro --all no host A: agrega os dois SEM dobrar o local"
# ---------------------------------------------------------------------------
T "$HOMEA" MAESTRO_HOST_ID=hostaaaa MAESTRO_TELEMETRY_INTERVAL=0 -- retro --all --days 999
chk "exit 0" "$RC" "0"
has "linha por máquina com os dois hosts" "-- por máquina: hostaaaa (local): 1 decisões" "$OUTF"
has "linha por máquina cita hostbbbb" "hostbbbb (" "$OUTF"
has "decisões: 2 (1 local + 1 remoto)" "-- decisões: 2" "$OUTF"

echo "-- retro SEM --all no host A: só o local (1 decisão)"
T "$HOMEA" MAESTRO_HOST_ID=hostaaaa -- retro --days 999
chk "exit 0" "$RC" "0"
has "decisões: 1 (só local)" "-- decisões: 1" "$OUTF"
hasnt "sem --all não imprime 'por máquina'" "-- por máquina:" "$OUTF"

# ---------------------------------------------------------------------------
echo "-- retro --all com telemetria desligada: aviso, segue local"
# ---------------------------------------------------------------------------
HOMEE=$(home_with_log e1)
T "$HOMEE" -- retro --all --days 999
chk "exit 0" "$RC" "0"
has "avisa telemetria desligada" "-- telemetria: desligada nesta máquina (retro só local)" "$OUTF"
has "decisões: 1 (só o local, sem telemetria)" "-- decisões: 1" "$OUTF"

# ---------------------------------------------------------------------------
echo "-- push com remoto quebrado: exit 2, estado failed"
# ---------------------------------------------------------------------------
HOMEC=$(home_with_log c1)
T "$HOMEC" -- telemetry --remote "$SANDBOX/nao-existe.git"
chk "exit 0 (só configura)" "$RC" "0"
T "$HOMEC" MAESTRO_HOST_ID=hostcccc MAESTRO_TELEMETRY_TIMEOUT=3 MAESTRO_TELEMETRY_INTERVAL=0 -- telemetry --push
chk "exit 2" "$RC" "2"
has "mensagem de falha" "telemetria: falhou" "$OUTF"
chk "telemetry-state result=failed" "$(kv "$HOMEC" result)" "failed"

# ---------------------------------------------------------------------------
echo "-- off remove a linha, status volta a 'desligada'"
# ---------------------------------------------------------------------------
T "$HOMEA" -- telemetry --off
chk "exit 0" "$RC" "0"
has "confirma desligamento" "telemetria: desligada nesta máquina" "$OUTF"
hasnt "config.yaml sem telemetry_remote" "telemetry_remote:" "$HOMEA/config.yaml"

T "$HOMEA" -- telemetry --status
chk "exit 0" "$RC" "0"
has "status volta a 'desligada'" "telemetria: desligada (sem telemetry_remote" "$OUTF"

# off num MAESTRO_HOME sem config.yaml não deve falhar
HOMEF=$(home_with_log f1)
T "$HOMEF" -- telemetry --off
chk "off sem config.yaml: exit 0" "$RC" "0"

# ---------------------------------------------------------------------------
echo "-- doctor: estado failed escrito à mão → warn"
# ---------------------------------------------------------------------------
FX="$SANDBOX/skills"; mkdir -p "$FX"
for s in systematic-debugging requesting-code-review gstack-qa gstack-ship gstack-cso gstack-office-hours; do
  mkdir -p "$FX/$s"; echo 'v1' > "$FX/$s/SKILL.md"
done
PLUGDIR="$SANDBOX/plugins-empty"

HOMEG=$(home_with_log g1)
printf 'telemetry_remote: %s\n' "$REMOTE" > "$HOMEG/config.yaml"
cat > "$HOMEG/telemetry-state" <<EOF
schema=maestro-telemetry-state-v1
checked=1
pushed=0
result=failed
reason=clone
host=hostgggg
files=0
EOF
env MAESTRO_HOME="$HOMEG" MAESTRO_SKILL_DIRS="$FX" MAESTRO_PLUGINS_DIR="$PLUGDIR" \
  "$BIN" doctor >"$OUTF" 2>&1
grep -qE '^warn telemetria: último push falhou \(clone\)' "$OUTF" \
  && ok "doctor avisa 'último push falhou'" || bad "doctor avisa 'último push falhou' (não achou em: $(grep -i telemetr "$OUTF"))"
has "capabilities.json com o resultado" '"result": "failed"' "$HOMEG/capabilities.json"

# ---------------------------------------------------------------------------
echo "-- doctor: sem telemetry_remote → ok 'local'"
# ---------------------------------------------------------------------------
HOMEH=$(home_with_log h1)
env MAESTRO_HOME="$HOMEH" MAESTRO_SKILL_DIRS="$FX" MAESTRO_PLUGINS_DIR="$PLUGDIR" \
  "$BIN" doctor >"$OUTF" 2>&1
grep -qE '^ok   telemetria: local \(sem telemetry_remote' "$OUTF" \
  && ok "doctor reporta 'local' sem config" || bad "doctor reporta 'local' sem config (não achou em: $(grep -i telemetr "$OUTF"))"

# ---------------------------------------------------------------------------
if [[ $fail -eq 0 ]]; then echo "TELEMETRY OK"; else echo "TELEMETRY COM FALHAS"; fi
exit $fail
