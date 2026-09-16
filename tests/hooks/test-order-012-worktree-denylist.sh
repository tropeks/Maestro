#!/usr/bin/env bash
# ordem 012 — autoproteção reconhece worktree como o mesmo plugin.
#
# Achado: PLUGIN_ROOT (MAESTRO_PLUGIN_ROOT, gravado como REPO_DIR pelo
# session-start.sh) é ancorado numa árvore de trabalho FÍSICA. Um `git
# worktree` do MESMO repositório tem raiz de arquivos diferente — o mesmo
# `bin/maestro`, MESMO record válido, editado de dentro do worktree escapava
# da denylist de autoproteção (ADR-003 v1.2) só por mudança de endereço, a
# mesma classe que a decisão A do Lote 0 recusou para lib/.
#
# Mecanismo do conserto (docs/patches/012-autoprotecao-worktree-pre-tool-gate.patch):
# `git rev-parse --path-format=absolute --git-common-dir` do projeto e do
# plugin — iguais → mesma árvore Git, endereço novo, denylist se aplica.
# Degradação NEUTRA (correção pós-suíte): só bloqueia com evidência POSITIVA
# (os dois `git rev-parse` tiveram sucesso, valores não-vazios, e iguais).
# git ausente, projeto que não é repositório, comando falhando ou
# `--path-format` indisponível caem no comportamento PRÉ-EXISTENTE (não
# bloqueiam por aqui) — worktree não existe sem git, então não há cenário de
# risco a proteger quando a evidência falta. A versão anterior tratava "não
# deu para saber" como "é a mesma árvore" (nega), o que virava bloqueio
# universal de qualquer diretório NÃO-GIT cujo caminho batesse a denylist —
# achado real da própria `tests/hooks/test-gate.sh` (projeto sintético via
# `mktemp -d`, sem `git init`). A asserção 2b abaixo cobre exatamente esse
# caso para a regressão não voltar.
#
# Lição das ordens 003/004/006: o teste NÃO exige o patch já aplicado.
# hooks/ está na denylist de autoproteção do próprio gate, então quem aplica
# o patch é o Capitão. Ausente → PENDENTE. Presente → cobra de verdade.
#
# AJUSTE DO SUPERVISOR (ordem 012): as três asserções rodam com decision
# record VÁLIDO DE VERDADE (gravado no próprio teste via `maestro decide`
# num MAESTRO_HOME de sandbox) — nunca mock, e nunca o record da sessão que
# roda a suíte (fuga de ambiente das ordens 001/002). Sem record válido, o
# portão genérico (mode=block) bloqueia TUDO, e as três passariam pelo
# motivo errado, sem nunca exercitar a denylist.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO/hooks/pre-tool-gate.sh"
SS="$REPO/hooks/session-start.sh"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()       { printf 'ok   %s\n' "$1"; }
bad()      { printf 'FAIL %s\n' "$1"; fail=1; }
pending()  { printf 'PENDENTE  %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Mecanismo presente? (marcador único do patch em hooks/pre-tool-gate.sh)
# ---------------------------------------------------------------------------
MARKER='worktree do PRÓPRIO plugin (ordem 012'
PATCHED=0
grep -qF "$MARKER" "$GATE" 2>/dev/null && PATCHED=1
if (( PATCHED == 0 )); then
  pending "ordem 012: hooks/pre-tool-gate.sh ainda sem reconhecimento de worktree — aplicar docs/patches/012-autoprotecao-worktree-pre-tool-gate.patch"
  exit 0
fi

command -v git >/dev/null 2>&1 || { pending "git ausente no ambiente de teste — mecanismo não é exercitável aqui"; exit 0; }
if ! git rev-parse --path-format=absolute --git-common-dir >/dev/null 2>&1; then
  pending "git sem --path-format=absolute (versão antiga) — mecanismo não é exercitável aqui"
  exit 0
fi

T=$(mktemp -d)
cleanup() {
  git -C "$REPO" worktree remove --force "$T/worktree" >/dev/null 2>&1 || true
  git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  rm -rf "$T"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Sandbox: política REAL compilada pelo session-start (não mock) + record
# REAL gravado por `maestro decide` (não mock) — CONTRATO do supervisor.
# ---------------------------------------------------------------------------
IHOME="$T/home"; mkdir -p "$IHOME"
MAESTRO_HOME="$IHOME" CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_ROOT="$REPO" \
  bash "$SS" >/dev/null 2>&1 || true
if [[ ! -s "$IHOME/gate-policy.sh" ]]; then
  pending "session-start.sh não compilou política neste ambiente — não exercitável"
  exit 0
fi

SID="ord12-record"
if ! MAESTRO_HOME="$IHOME" bash "$REPO/bin/maestro" decide --session "$SID" \
      --workflow fix --mode direct >/dev/null 2>&1; then
  pending "\`maestro decide\` falhou neste ambiente (Bun ausente?) — não exercitável"
  exit 0
fi
[[ -s "$IHOME/sessions/$SID.json" ]] || { pending "decision record não foi gravado"; exit 0; }

# ---------------------------------------------------------------------------
# Dois fixtures de árvore: um WORKTREE de verdade do próprio REPO (git
# worktree add), e um repositório git INDEPENDENTE (git init) — as duas
# pontas da asserção 2, que prova que o conserto não virou bloqueio
# universal de bin/.
# ---------------------------------------------------------------------------
WT="$T/worktree"
if ! git -C "$REPO" worktree add --detach "$WT" HEAD >/dev/null 2>&1; then
  pending "git worktree add falhou neste ambiente — não exercitável"
  exit 0
fi
OTHER="$T/otherrepo"; mkdir -p "$OTHER/bin"
git init -q "$OTHER" >/dev/null 2>&1

# Terceiro fixture — o que a versão anterior do patch quebrou de verdade
# (achado do supervisor, não hipotético): um diretório que NÃO é repositório
# git NENHUM, com caminho relativo batendo a denylist. `git -C` aqui falha e
# devolve vazio — é exatamente o "não deu para saber" que a degradação NEUTRA
# tem que devolver ao comportamento pré-existente (não bloquear), porque
# worktree não existe sem git.
NOGIT="$T/naogit"; mkdir -p "$NOGIT/bin" "$NOGIT/src"

run_gate() { # $1=CLAUDE_PROJECT_DIR $2=file_path (absoluto) -> RC, OUT
  local proj="$1" fp="$2"
  RC=0
  OUT=$(jq -n --arg p "$fp" \
      '{session_id:"'"$SID"'",tool_name:"Edit",tool_input:{file_path:$p}}' \
    | MAESTRO_HOME="$IHOME" CLAUDE_PROJECT_DIR="$proj" bash "$GATE" 2>&1 >/dev/null) || RC=$?
}

echo "-- as três asserções (record válido de verdade, gravado no sandbox) --"

run_gate "$WT" "$WT/bin/maestro"
if [[ $RC -eq 2 ]]; then
  ok "asserção 1: bin/maestro dentro de WORKTREE do plugin → BLOQUEADO (rc=2)"
else
  bad "asserção 1: worktree deveria bloquear como a árvore principal (rc=$RC, saída: '$OUT')"
fi

run_gate "$OTHER" "$OTHER/bin/maestro"
if [[ $RC -eq 0 ]]; then
  ok "asserção 2: bin/ de OUTRO repositório qualquer → continua LIVRE (rc=0)"
else
  bad "asserção 2: outro repo não pode ser pego pela autoproteção (rc=$RC, saída: '$OUT') — bloqueio universal de bin/, modo de falha oposto"
fi

run_gate "$NOGIT" "$NOGIT/bin/x.go"
if [[ $RC -eq 0 ]]; then
  ok "asserção 2b: diretório NÃO-GIT com caminho batendo a denylist → continua LIVRE (rc=0)"
else
  bad "asserção 2b: diretório não-git não pode ser pego pela autoproteção (rc=$RC, saída: '$OUT') — a regressão real (git ausente vira 'nega') voltou"
fi

run_gate "$REPO" "$REPO/bin/maestro"
if [[ $RC -eq 2 ]]; then
  ok "asserção 3: árvore PRINCIPAL inalterada → continua BLOQUEADA (rc=2)"
else
  bad "asserção 3: árvore principal não pode destravar (rc=$RC, saída: '$OUT') — regressão"
fi

# ---------------------------------------------------------------------------
# terceiro estado: sabota a checagem de worktree numa CÓPIA do gate JÁ
# PATCHADO (remove só o bloco novo) e mostra que a MESMA edição no worktree
# deixa de ser bloqueada — o teste tem dente.
# ---------------------------------------------------------------------------
SAB="$T/gate-sabotado.sh"
mkdir -p "$T/hookscopy-lib"
awk -v m="$MARKER" '
  index($0, m) { skip=1 }
  /^# ── 3b\. consentimento/ { skip=0 }
  !skip { print }
' "$GATE" > "$SAB"
if grep -qF "$MARKER" "$SAB"; then
  bad "sabotagem não pegou (marcador ainda presente na cópia)"
else
  ln -sf "$REPO/hooks/lib" "$T/hookscopy-lib/lib"
  cp "$SAB" "$T/hookscopy-lib/gate.sh"
  RC=0
  OUT=$(jq -n --arg p "$WT/bin/maestro" \
      '{session_id:"'"$SID"'",tool_name:"Edit",tool_input:{file_path:$p}}' \
    | MAESTRO_HOME="$IHOME" CLAUDE_PROJECT_DIR="$WT" bash "$T/hookscopy-lib/gate.sh" 2>&1 >/dev/null) || RC=$?
  if [[ $RC -eq 2 ]]; then
    bad "sabotagem não quebrou nada — worktree ainda seria bloqueado sem o bloco novo"
  else
    ok "sabotado: sem o bloco de reconhecimento de worktree, a mesma edição passa (rc=$RC) — o teste tem dente"
  fi
fi

exit $fail
