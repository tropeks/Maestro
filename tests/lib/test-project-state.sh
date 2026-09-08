#!/usr/bin/env bash
# hooks/lib/project-state.sh — a chave do projeto (slug + hash) que amarra brief,
# recibo e ordem. Invariante que este teste trava: WORKTREE e REPO PRINCIPAL são o
# MESMO projeto. Sem isso, uma ordem provada dentro de uma worktree ficava invisível
# do repo principal e `order --status` respondia 'em_execucao / prova NENHUMA' para
# uma ordem já aceita — o relatório mentia conforme o diretório corrente.
# Hermético: MAESTRO_HOME e repositórios em mktemp.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
# shellcheck source=hooks/lib/project-state.sh
source "$REPO/hooks/lib/project-state.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
git_id() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

command -v git >/dev/null || { echo "FAIL git ausente"; exit 1; }

# ── fixture: repo principal + uma worktree ─────────────────────────────────
P="$tmp/projeto"; mkdir -p "$P"
git -C "$P" init -q -b main
echo conteudo > "$P/a.txt"; git_id "$P" add -A; git_id "$P" commit -qm base
W="$tmp/wt-1"; git_id "$P" worktree add -q "$W" -b trabalho

chk "worktree criada (.git é ARQUIVO, não diretório)" "$( [[ -f "$W/.git" ]] && echo file || echo dir )" "file"

# ── a invariante ───────────────────────────────────────────────────────────
chk "brief da worktree == brief do repo principal" "$(maestro_brief_file "$W")" "$(maestro_brief_file "$P")"
chk "recibo da worktree == recibo do repo principal" \
    "$(maestro_evidence_file "$W" suite)" "$(maestro_evidence_file "$P" suite)"

# ── e projetos diferentes continuam diferentes ─────────────────────────────
O="$tmp/outro"; mkdir -p "$O"; git -C "$O" init -q -b main
echo x > "$O/a.txt"; git_id "$O" add -A; git_id "$O" commit -qm base
if [[ "$(maestro_brief_file "$O")" == "$(maestro_brief_file "$P")" ]]; then
  bad "dois repos distintos colidiram na mesma chave"
else ok "repos distintos continuam com chaves distintas"; fi

# ── diretório sem git não é tocado pelo desvio ─────────────────────────────
D="$tmp/sem-git"; mkdir -p "$D"
b=$(maestro_brief_file "$D")
[[ "$b" == *"/briefs/sem-git-"* ]] && ok "diretório sem git usa o próprio nome" || bad "sem git: $b"

# ── submódulo também tem .git ARQUIVO, e NÃO deve virar o superprojeto ─────
SUP="$tmp/super"; mkdir -p "$SUP"; git -C "$SUP" init -q -b main
echo s > "$SUP/s.txt"; git_id "$SUP" add -A; git_id "$SUP" commit -qm base
if git_id "$SUP" -c protocol.file.allow=always submodule add -q "$P" sub 2>/dev/null; then
  git_id "$SUP" commit -qm "add sub" >/dev/null 2>&1
  if [[ "$(maestro_brief_file "$SUP/sub")" == "$(maestro_brief_file "$SUP")" ]]; then
    bad "submódulo foi confundido com o superprojeto"
  else ok "submódulo NÃO vira o superprojeto (git-common-dir não termina em /.git)"; fi
else
  ok "submódulo: fixture indisponível nesta máquina (pulado)"
fi

# ── determinismo: mesma entrada, mesma saída ───────────────────────────────
chk "determinístico" "$(maestro_brief_file "$W")" "$(maestro_brief_file "$W")"

exit $fail
