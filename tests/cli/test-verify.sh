#!/usr/bin/env bash
# E23b / S-2302 — `maestro verify`: que prova ESTE changeset exige, e quanto
# dela existe. Invariantes: projeto sem `verifications:` não deve nada (o Maestro
# não inventa dever); a exigência sai do diff contra a base, não da memória de
# quem entrega; --check é o gate de rotina. Hermético.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }
gitc() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

echo "-- projeto sem verifications: nada é exigido"
P0="$tmp/p0"; mkdir -p "$P0"; git -C "$P0" init -qb main
echo a > "$P0/f"; gitc "$P0" add -A; gitc "$P0" commit -qm base
out=$("$BIN" verify --project "$P0"); rc=$?
chk "sem declaração → exit 0" "$rc" "0"
grep -q 'nenhuma declarada' <<<"$out" && ok "diz que não há declaração (não inventa dever)" || bad "sem declaração ($out)"
"$BIN" verify --check --project "$P0" >/dev/null; chk "--check sem declaração → 0" "$?" "0"

echo "-- áreas tocadas saem do diff contra a base"
P="$tmp/proj"; mkdir -p "$P/src/auth" "$P/docs"
git -C "$P" init -qb main
cat > "$P/.maestro.yaml" <<'Y'
verifications:
  auth:
    paths: [src/auth/]
    labels: [suite, tenant]
commands:
  suite: true
Y
echo a > "$P/src/auth/jwt.py"; echo d > "$P/docs/d.md"
gitc "$P" add -A; gitc "$P" commit -qm base
out=$("$BIN" verify --project "$P")
grep -q 'áreas tocadas: nenhuma' <<<"$out" && ok "árvore limpa → nenhuma área, nada exigido" || bad "árvore limpa ($out)"
"$BIN" verify --check --project "$P" >/dev/null; chk "--check com árvore limpa → 0" "$?" "0"
echo mudou >> "$P/docs/d.md"
grep -q 'áreas tocadas: nenhuma' <<<"$("$BIN" verify --project "$P")" \
  && ok "mexer FORA das paths declaradas não exige nada" || bad "área fora do escopo exigiu prova"
echo mudou >> "$P/src/auth/jwt.py"
out=$("$BIN" verify --project "$P"); rc=$?
chk "faltando prova → exit 0 (relatório, não gate)" "$rc" "0"
grep -q 'áreas tocadas: auth' <<<"$out" && ok "a área tocada é nomeada" || bad "área tocada ($out)"
grep -q 'evidência (suite): NENHUMA' <<<"$out" && ok "rótulo exigido sem recibo → NENHUMA" || bad "NENHUMA ($out)"
grep -q 'registre com: maestro evidence --record --label suite -- true' <<<"$out" \
  && ok "a sugestão cita o COMANDO DECLARADO em commands.suite" || bad "sugestão sem o comando declarado ($out)"
grep -q 'registre com: maestro evidence --record --label tenant -- <comando>' <<<"$out" \
  && ok "rótulo sem comando declarado cai no placeholder honesto" || bad "placeholder ($out)"
grep -q 'faltam 2' <<<"$out" && ok "conta as faltantes" || bad "contagem ($out)"
"$BIN" verify --check --project "$P" >/dev/null 2>&1; chk "--check com faltante → exit 1" "$?" "1"

echo "-- recibo válido fecha a exigência"
"$BIN" evidence --record --label suite --project "$P" -- true >/dev/null
"$BIN" evidence --record --label tenant --project "$P" -- true >/dev/null
out=$("$BIN" verify --project "$P")
grep -q 'todas as verificações obrigatórias estão VÁLIDAS' <<<"$out" \
  && ok "com os dois recibos, tudo VÁLIDA" || bad "tudo válido ($out)"
"$BIN" verify --check --project "$P" >/dev/null; chk "--check com tudo provado → 0" "$?" "0"
echo "sujou depois da prova" >> "$P/src/auth/jwt.py"
"$BIN" verify --check --project "$P" >/dev/null 2>&1; chk "conteúdo andou depois da prova → --check 1" "$?" "1"
grep -q 'conteúdo mudou desde a prova' <<<"$("$BIN" verify --project "$P")" \
  && ok "e o motivo é nomeado (recibo é amarrado a conteúdo)" || bad "motivo do vencimento"

echo "-- recibo com o comando ERRADO não fecha a exigência (E23b)"
"$BIN" evidence --record --label suite --project "$P" -- echo nao-e-o-declarado >/dev/null
out=$("$BIN" verify --project "$P")
grep -q 'evidência (suite): VENCIDA — comando diferente do declarado' <<<"$out" \
  && ok "comando fora do declarado → VENCIDA, mesmo com exit 0" || bad "cmd_match no verify ($out)"

echo "-- base: default merge-base, --base explícita, ref inválida"
gitc "$P" add -A; gitc "$P" commit -qm entrega
git -C "$P" checkout -qb trabalho
echo maisum >> "$P/src/auth/jwt.py"; gitc "$P" add -A; gitc "$P" commit -qm mais
grep -q 'áreas tocadas: auth' <<<"$("$BIN" verify --project "$P")" \
  && ok "no branch, a base default é o merge-base com main" || bad "merge-base default"
grep -q 'áreas tocadas: nenhuma' <<<"$("$BIN" verify --base HEAD --project "$P")" \
  && ok "--base HEAD compara com o commit atual (nada tocado)" || bad "--base explícita"
"$BIN" verify --base nao-existe --project "$P" >/dev/null 2>&1
chk "--base inexistente → exit 1 (validação)" "$?" "1"
"$BIN" verify --flag-que-nao-existe --project "$P" >/dev/null 2>&1
chk "flag desconhecida → exit 1" "$?" "1"

echo "-- sem git degrada, nunca quebra"
P2="$tmp/semgit"; mkdir -p "$P2"; cp "$P/.maestro.yaml" "$P2/.maestro.yaml"
out=$("$BIN" verify --project "$P2"); rc=$?
chk "sem repositório → exit 0" "$rc" "0"
grep -q 'base: nenhuma' <<<"$out" && ok "diz que não há base para comparar" || bad "base nenhuma ($out)"

echo "-- log: evento verify com o nº de faltantes (e só isso)"
LOG="$MAESTRO_HOME/logs/routing.jsonl"
grep -q '"event":"verify"' "$LOG" && ok "evento verify registrado" || bad "evento verify"
grep -q '"event":"verify".*"n":"2"' "$LOG" && ok "n = faltantes" || bad "n de faltantes"
grep -q 'auth\|suite\|maestro.yaml\|/' <(grep '"event":"verify"' "$LOG") \
  && bad "o log de verify vazou rótulo/área/caminho" || ok "nada de rótulo, área ou caminho no log"

exit $fail
