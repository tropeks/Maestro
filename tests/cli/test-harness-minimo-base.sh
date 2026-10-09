#!/usr/bin/env bash
# ordem 077 — tools/harness-minimo/montar-base.sh monta a BASE SEM FUTURO: `git log --all` tem 1 commit, sem
# remoto, sem outros refs, sem o objeto da solução; o hash da árvore é o do commit `head:`. Repo de fixture
# com um commit FUTURO (a "solução") em outro branch e com um remoto. Controles negativos: destino sujo e
# commit inexistente são recusados; o repo de origem não muda.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/harness-minimo/montar-base.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

[[ -x "$TOOL" ]] || { bad "montar-base.sh não existe ou não é executável"; exit 1; }

O="$tmp/origem"
git init -q -b main "$O"
git -C "$O" config user.email t@t; git -C "$O" config user.name t
echo antigo > "$O/antigo.txt"; git -C "$O" add -A; git -C "$O" commit -qm "passado"
echo "teste quebrado" > "$O/teste.sh"; git -C "$O" add -A; git -C "$O" commit -qm "head da ordem"
HEAD_ORDEM=$(git -C "$O" rev-parse HEAD)
TREE_ORDEM=$(git -C "$O" rev-parse 'HEAD^{tree}')
git -C "$O" checkout -q -b order/solucao
echo "teste consertado" > "$O/teste.sh"; git -C "$O" commit -qam "a solução (futuro)"
SOLUCAO=$(git -C "$O" rev-parse HEAD)
git -C "$O" checkout -q main
git -C "$O" remote add origin "https://exemplo.invalid/repo.git"
git -C "$O" tag v-futura "$SOLUCAO"
estado_antes=$(git -C "$O" for-each-ref --format='%(refname) %(objectname)' | sha256sum | cut -d' ' -f1)

B="$tmp/base"
out=$(bash "$TOOL" "$O" "$HEAD_ORDEM" "$B")
rc=$?
[[ $rc -eq 0 ]] && ok "montagem sai 0" || { bad "montagem saiu $rc: $out"; exit 1; }

n=$(git -C "$B" log --all --oneline | wc -l)
[[ "$n" -eq 1 ]] && ok "git log --all tem 1 commit" || bad "git log --all tem $n commits"
tree=$(git -C "$B" rev-parse 'HEAD^{tree}')
[[ "$tree" == "$TREE_ORDEM" ]] && ok "hash da árvore é o do head: da ordem" || bad "árvore $tree ≠ $TREE_ORDEM"
grep -q "^tree=$TREE_ORDEM\$" <<<"$out" && ok "o hash da árvore é impresso (registro do run)" || bad "tree= não impresso"
[[ -z "$(git -C "$B" remote)" ]] && ok "sem remoto" || bad "a base tem remoto"
refs=$(git -C "$B" for-each-ref | wc -l)
[[ "$refs" -eq 1 ]] && ok "um único ref (o branch da base), sem tags nem branches futuros" || bad "$refs refs na base"
git -C "$B" cat-file -e "$SOLUCAO" 2>/dev/null && bad "o objeto da solução EXISTE na base" || ok "o commit da solução não existe na base"
git -C "$B" cat-file -e "$HEAD_ORDEM" 2>/dev/null && bad "o commit original EXISTE na base" || ok "nem o commit original (só a árvore dele)"
[[ "$(cat "$B/teste.sh")" == "teste quebrado" ]] && ok "o conteúdo é o do head (teste ainda quebrado)" || bad "conteúdo diferente do head"
[[ -z "$(git -C "$B" status --porcelain)" ]] && ok "árvore limpa depois da montagem" || bad "árvore suja"

# determinismo: segunda montagem do mesmo commit → mesma árvore E mesmo commit (identidade e data fixas)
out2=$(bash "$TOOL" "$O" "$HEAD_ORDEM" "$tmp/base2")
[[ "$(grep '^commit=' <<<"$out")" == "$(grep '^commit=' <<<"$out2")" ]] && ok "duas montagens dão o mesmo commit (byte a byte)" || bad "montagens diferem"

# o repo de origem não muda
estado_depois=$(git -C "$O" for-each-ref --format='%(refname) %(objectname)' | sha256sum | cut -d' ' -f1)
[[ "$estado_antes" == "$estado_depois" ]] && ok "o repo de origem não mudou" || bad "o repo de origem mudou"

# negativos
bash "$TOOL" "$O" "$HEAD_ORDEM" "$B" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "destino não vazio é recusado (rc 2)" || bad "destino sujo aceito (rc $rc)"
bash "$TOOL" "$O" 0000000000000000000000000000000000000000 "$tmp/b3" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "commit inexistente é recusado (rc 2)" || bad "commit inexistente aceito (rc $rc)"
bash "$TOOL" "$O" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "uso inválido sai 2" || bad "uso inválido saiu $rc"

exit $fail
