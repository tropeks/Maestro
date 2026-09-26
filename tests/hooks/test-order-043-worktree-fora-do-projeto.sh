#!/usr/bin/env bash
# ordem 043 — autoproteção vencida por worktree FORA do projeto da sessão.
#
# Incidente da 042: com a sessão no main (CLAUDE_PROJECT_DIR = raiz do
# plugin), um subagente escreveu agents/conformador.md num `git worktree` do
# plugin em OUTRO diretório, e o gate deixou passar. O ramo da ordem 012
# (3a-bis) só pergunta se o PROJETO da sessão é worktree do plugin: o caminho
# do worktree não fica sob o projeto, REL sai vazio e o ramo nem roda. O
# conserto (docs/patches/043-gate-worktree-fora-do-projeto.patch) pergunta
# pelo worktree do PRÓPRIO caminho editado.
#
# Cobre: todo alvo da denylist, cwd no main e no worktree, política com e
# sem MAESTRO_PLUGIN_ROOT (sem ela, a raiz vem da localização do hook);
# falha FECHADA quando o git não resolve o worktree; edição comum sem fork de
# git; a exceção da 039 e o consent roster iguais na raiz e no worktree;
# outro repo e diretório não-git continuam livres; e o teste tem dente.
#
# "Política ausente" não é cenário: sem arquivo de política o gate INTEIRO
# degrada com exit 0 antes da denylist, também na raiz (ADR-003 v1.1).
#
# Lição das ordens 003/012: o teste NÃO exige o patch aplicado — hooks/ está
# na autoproteção e quem aplica é o Capitão. Sem o marcador, as asserções do
# conserto viram PENDENTE e o teste mostra, em linhas `vermelho`, o furo.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO/hooks/pre-tool-gate.sh"
SS="$REPO/hooks/session-start.sh"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()      { printf 'ok   %s\n' "$1"; }
bad()     { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

MARKER='worktree do plugin FORA do projeto (ordem 043'
PATCHED=0
grep -qF "$MARKER" "$GATE" 2>/dev/null && PATCHED=1

command -v git >/dev/null 2>&1 || { pending "git ausente — não exercitável"; exit 0; }
command -v jq  >/dev/null 2>&1 || { pending "jq ausente — não exercitável"; exit 0; }
git -C "$REPO" rev-parse --path-format=absolute --git-common-dir >/dev/null 2>&1 \
  || { pending "git sem --path-format=absolute — não exercitável"; exit 0; }

T=$(mktemp -d)
cleanup() {
  git -C "$REPO" worktree remove --force "$T/wt" >/dev/null 2>&1 || true
  git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  rm -rf "$T"
}
trap cleanup EXIT

# --- política REAL (session-start) + record REAL (maestro decide) ----------
IHOME="$T/home"; mkdir -p "$IHOME"
MAESTRO_HOME="$IHOME" CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_ROOT="$REPO" \
  bash "$SS" >/dev/null 2>&1 || true
[[ -s "$IHOME/gate-policy.sh" ]] || { pending "session-start não compilou política — não exercitável"; exit 0; }
POL_ROOT="$T/policy-com-root.sh"; cp "$IHOME/gate-policy.sh" "$POL_ROOT"
grep -q '^MAESTRO_PLUGIN_ROOT=' "$POL_ROOT" || { bad "política compilada sem MAESTRO_PLUGIN_ROOT"; exit 1; }
POL_DERIV="$T/policy-sem-root.sh"; grep -v '^MAESTRO_PLUGIN_ROOT=' "$POL_ROOT" >"$POL_DERIV"

SID="ord43-record"
MAESTRO_HOME="$IHOME" bash "$REPO/bin/maestro" decide --session "$SID" \
  --workflow fix --mode direct >/dev/null 2>&1 || { pending "maestro decide falhou — não exercitável"; exit 0; }

WT="$T/wt"
git -C "$REPO" worktree add --detach "$WT" HEAD >/dev/null 2>&1 \
  || { pending "git worktree add falhou — não exercitável"; exit 0; }
OTHER="$T/outro"; mkdir -p "$OTHER/bin"; git init -q "$OTHER"
NOGIT="$T/naogit"; mkdir -p "$NOGIT/bin"

# git que conta forks: cada chamada deixa uma linha em $FORKS
FAKEBIN="$T/fakebin"; mkdir -p "$FAKEBIN"; FORKS="$T/forks"; : >"$FORKS"
REALGIT=$(command -v git)
printf '#!/usr/bin/env bash\necho x >>"%s"\nexec "%s" "$@"\n' "$FORKS" "$REALGIT" >"$FAKEBIN/git"
chmod +x "$FAKEBIN/git"
# git quebrado: existe e falha em tudo
BROKEN="$T/brokenbin"; mkdir -p "$BROKEN"
printf '#!/usr/bin/env bash\nexit 128\n' >"$BROKEN/git"; chmod +x "$BROKEN/git"
# PATH sem git nenhum: só o que o gate usa
NOGITBIN="$T/nogitbin"; mkdir -p "$NOGITBIN"
for c in bash jq awk sed grep cat date mkdir mv rm tr head tail wc cut sort env printf flock; do
  p=$(type -P "$c" 2>/dev/null) && ln -sf "$p" "$NOGITBIN/$c"
done

# run_gate <proj> <file_path> <política> [PATH] [tool] [old] [new] → RC, OUT
run_gate() {
  local proj="$1" fp="$2" pol="$3" path="${4:-$PATH}" tool="${5:-Write}"
  local payload
  if [[ "$tool" == "Edit" ]]; then
    payload=$(jq -n --arg p "$fp" --arg s "$SID" --arg o "$6" --arg n "$7" \
      '{session_id:$s,tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}')
  else
    payload=$(jq -n --arg p "$fp" --arg s "$SID" \
      '{session_id:$s,tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')
  fi
  RC=0
  OUT=$(printf '%s' "$payload" | env PATH="$path" MAESTRO_HOME="$IHOME" \
        MAESTRO_GATE_POLICY="$pol" CLAUDE_PROJECT_DIR="$proj" bash "$GATE" 2>&1 >/dev/null) || RC=$?
}

# expect <rc-esperado> <descrição> — com o patch ausente, só REGISTRA o furo
expect_block() {
  if (( PATCHED == 0 )); then
    printf 'vermelho  %s → rc=%s\n' "$1" "$RC"; return 0
  fi
  [[ $RC -eq 2 ]] && ok "$1 → BLOQUEADO" || bad "$1 → deveria bloquear (rc=$RC) ${OUT:0:160}"
}
expect_pass() { [[ $RC -eq 0 ]] && ok "$1 → livre" || bad "$1 → deveria passar (rc=$RC) ${OUT:0:160}"; }

# Alvos = a denylist que VALE (a compilada do routing-table, não o default do
# hook) + a âncora do aceite (ordem 041), que o default do hook protege.
TARGETS=""
for e in $(. "$POL_ROOT"; printf '%s %s' "$MAESTRO_GATE_DENY_SELF" "$MAESTRO_GATE_DENY_PATHS") config/accept-proof.pub; do
  [[ "$e" == */ ]] && e="${e}x.sh"
  [[ " $TARGETS " == *" $e "* ]] || TARGETS+=" $e"
done

echo "-- 1. todo alvo da denylist, pelo caminho do worktree: cwd × política --"
for cwd in main wt; do
  [[ $cwd == main ]] && P="$REPO" || P="$WT"
  for pol in com-root sem-root; do
    [[ $pol == com-root ]] && POL="$POL_ROOT" || POL="$POL_DERIV"
    for t in $TARGETS; do
      run_gate "$P" "$WT/$t" "$POL"
      if [[ "$t" == config/accept-proof.pub && $RC -ne 2 ]] && ! grep -q 'accept-proof' "$REPO/config/routing-table.yaml"; then
        printf 'vermelho  cwd=%s política=%s %s → rc=%s (routing-table sem a âncora)\n' "$cwd" "$pol" "$t" "$RC"; continue
      fi
      expect_block "cwd=$cwd política=$pol $t"
    done
  done
done

echo "-- 2. a raiz do plugin: todo alvo bloqueado --"
for pol in "$POL_ROOT" "$POL_DERIV"; do
  for t in $TARGETS; do
    run_gate "$REPO" "$REPO/$t" "$pol"
    if [[ $RC -eq 2 ]]; then ok "raiz: $t bloqueado (${pol##*/})"
    elif [[ "$t" == config/accept-proof.pub ]] && ! grep -q 'accept-proof' "$REPO/config/routing-table.yaml"; then
      printf 'vermelho  raiz: %s → rc=%s (routing-table sem a âncora: docs/patches/043-routing-table-accept-proof.patch)\n' "$t" "$RC"
    else bad "raiz: $t destravou (rc=$RC, ${pol##*/})"; fi
  done
done

echo "-- 3. falha FECHADA: worktree reconhecido, git não resolve --"
run_gate "$REPO" "$WT/bin/maestro" "$POL_ROOT" "$BROKEN:$PATH"
expect_block "git quebrado (exit 128) bin/maestro no worktree"
run_gate "$REPO" "$WT/agents/x.md" "$POL_ROOT" "$NOGITBIN"
expect_block "git ausente do PATH agents/x.md no worktree"

echo "-- 4. sem regressão: edição comum e outros repositórios --"
for f in tests/x.sh docs/x.md README.md; do
  : >"$FORKS"
  run_gate "$REPO" "$WT/$f" "$POL_ROOT" "$FAKEBIN:$PATH"
  expect_pass "worktree $f"
  n=$(wc -l <"$FORKS" | tr -d ' ')
  [[ "$n" -eq 0 ]] && ok "worktree $f: zero fork de git" || bad "worktree $f: $n fork(s) de git no caminho comum"
done
run_gate "$REPO" "$OTHER/bin/maestro" "$POL_ROOT"; expect_pass "outro repositório bin/maestro"
run_gate "$REPO" "$NOGIT/bin/x.go" "$POL_ROOT"; expect_pass "diretório não-git bin/x.go"
run_gate "$REPO" "$NOGIT/bin/x.go" "$POL_ROOT" "$NOGITBIN"; expect_pass "diretório não-git sem git no PATH"

echo "-- 5. exceção da 039 e consent roster: iguais na raiz e no worktree --"
for root in "$REPO" "$WT"; do
  where=$([[ $root == "$REPO" ]] && echo raiz || echo worktree)
  run_gate "$REPO" "$root/agents/conformador.md" "$POL_ROOT" "$PATH" Edit 'effort: alto' 'effort: baixo'
  expect_pass "$where: Edit effort alto→baixo (exceção 039)"
  run_gate "$REPO" "$root/agents/conformador.md" "$POL_ROOT" "$PATH" Edit 'model: sonnet' 'model: opus'
  if [[ $where == worktree ]]; then expect_block "$where: Edit model (fora da exceção 039)"
  else [[ $RC -eq 2 ]] && ok "raiz: Edit model bloqueado" || bad "raiz: Edit model passou (rc=$RC)"; fi
done
mkdir -p "$IHOME/consents"
printf 'expires=%s\ngranted=teste\nsession=%s\n' "$(( $(date +%s) + 600 ))" "$SID" >"$IHOME/consents/roster"
for root in "$REPO" "$WT"; do
  where=$([[ $root == "$REPO" ]] && echo raiz || echo worktree)
  run_gate "$REPO" "$root/agents/x.md" "$POL_ROOT"; expect_pass "$where: consent roster libera agents/"
  run_gate "$REPO" "$root/bin/maestro" "$POL_ROOT"
  if [[ $where == worktree ]]; then expect_block "$where: consent roster NÃO libera bin/"
  else [[ $RC -eq 2 ]] && ok "raiz: consent roster não libera bin/" || bad "raiz: bin/ liberado por consent (rc=$RC)"; fi
done
rm -f "$IHOME/consents/roster"

echo "-- 6. dente: sem o bloco novo, o worktree volta a passar --"
if (( PATCHED == 1 )); then
  mkdir -p "$T/sab/hooks"; ln -s "$REPO/hooks/lib" "$T/sab/hooks/lib"
  awk -v m="$MARKER" 'index($0, m) { skip=1 } /^# ── 3a-quater/ { skip=0 } !skip { print }' "$GATE" >"$T/sab/hooks/pre-tool-gate.sh"
  RC=0
  printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$SID" "$WT/agents/x.md" \
    | MAESTRO_HOME="$IHOME" MAESTRO_GATE_POLICY="$POL_ROOT" CLAUDE_PROJECT_DIR="$REPO" \
      bash "$T/sab/hooks/pre-tool-gate.sh" >/dev/null 2>&1 || RC=$?
  [[ $RC -eq 0 ]] && ok "sabotado: sem o bloco, agents/ no worktree passa — o teste tem dente" \
    || bad "sabotagem não quebrou nada (rc=$RC)"
else
  pending "ordem 043: conserto ausente em hooks/pre-tool-gate.sh — aplicar docs/patches/043-gate-worktree-fora-do-projeto.patch"
fi

exit $fail
