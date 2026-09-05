#!/usr/bin/env bash
# E23b / S-2302 — hooks/lib/verifications.sh: o parser que diz QUAL prova este
# changeset deve. Invariantes: config malformada nunca derruba quem chama (degrada
# para "nada exigido"); área sem path não governa nada; casamento é por PREFIXO
# de caminho; `tip` vazio = working tree. Hermético (fixtures em mktemp).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=hooks/lib/verifications.sh
source "$REPO/hooks/lib/verifications.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

git_id() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

echo "-- parser: flow list, lista por espaço, área sem paths, nome inválido"
P="$tmp/p1"; mkdir -p "$P"
cat > "$P/.maestro.yaml" <<'Y'
version: 1
experts: [dev-pleno]
verifications:
  auth:
    paths: [src/auth/, migrations/]
    labels: [suite, tenant-isolation]
  billing:
    paths: src/billing/ src/pay/
    labels: suite
  sem-path:
    labels: [suite]
  RUIM!:
    paths: [roubado/]
  docs:
    paths: ["docs/"]
    labels: [suite]
commands:
  suite: bash tests/run-all.sh   # comentário no fim
  tenant-isolation: "bash tests/tenant.sh"
docs: [docs/architecture/ARCHITECTURE.md]
Y
A=$(maestro_verif_areas "$P")
chk "flow list vira lista por espaço" "$(grep -c '^auth	src/auth/ migrations/	suite tenant-isolation$' <<<"$A")" "1"
chk "lista separada por espaço também vale" "$(grep -c '^billing	src/billing/ src/pay/	suite$' <<<"$A")" "1"
grep -q '^sem-path' <<<"$A" && bad "área sem paths não governa nada" || ok "área sem paths é ignorada (não governa nada)"
grep -q 'roubado/' <<<"$A" \
  && bad "paths de área com nome inválido vazaram para a área anterior" \
  || ok "área de nome inválido é descartada SEM contaminar a anterior"
chk "aspas nas pontas do item somem" "$(awk -F'\t' '$1=="docs"{print $2}' <<<"$A")" "docs/"
chk "chave de topo seguinte (docs:) não vira área" "$(wc -l <<<"$A")" "3"

echo "-- parser: commands"
chk "comando declarado" "$(maestro_verif_cmd "$P" suite)" "bash tests/run-all.sh"
chk "aspas removidas do comando" "$(maestro_verif_cmd "$P" tenant-isolation)" "bash tests/tenant.sh"
chk "rótulo sem comando declarado → vazio" "$(maestro_verif_cmd "$P" build)" ""
chk "rótulo inválido → vazio (nunca erro)" "$(maestro_verif_cmd "$P" 'Ruim!')" ""

echo "-- parser: degradações (arquivo sem bloco, sem arquivo, lixo)"
P2="$tmp/p2"; mkdir -p "$P2"; printf 'version: 1\nexperts: [qa]\n' > "$P2/.maestro.yaml"
chk "arquivo sem bloco verifications → vazio" "$(maestro_verif_areas "$P2")" ""
chk "sem .maestro.yaml → vazio" "$(maestro_verif_areas "$tmp/nao-existe")" ""
P3="$tmp/p3"; mkdir -p "$P3"; head -c 2048 /dev/urandom > "$P3/.maestro.yaml"
maestro_verif_areas "$P3" >/dev/null 2>&1; chk "arquivo binário → rc 0 (degrada, não quebra)" "$?" "0"
P4="$tmp/p4"; mkdir -p "$P4"
printf 'verifications:\n  a:\n    paths: [ok/, ../fuga, "com espaço", "aspas-ok"]\n    labels: [suite, RUIM, x!]\n' > "$P4/.maestro.yaml"
chk "item fora da regra é descartado, o válido fica" "$(maestro_verif_areas "$P4")" \
  "$(printf 'a\tok/ ../fuga aspas-ok\tsuite')"

echo "-- touched: casamento por PREFIXO, no diff de duas pontas"
G="$tmp/git"; mkdir -p "$G/src/auth" "$G/src/billing" "$G/docs"
git -C "$G" init -qb main
cp "$P/.maestro.yaml" "$G/.maestro.yaml"
echo a > "$G/src/auth/jwt.py"; echo b > "$G/src/billing/inv.py"; echo c > "$G/docs/d.md"
git_id "$G" add -A; git_id "$G" commit -qm base
BASE=$(git -C "$G" rev-parse HEAD)
echo x >> "$G/docs/d.md"; git_id "$G" add -A; git_id "$G" commit -qm docs
chk "diff que só toca docs/ acende a área docs" "$(maestro_verif_touched "$G" "$BASE" HEAD)" "docs"
echo x >> "$G/src/auth/jwt.py"; git_id "$G" add -A; git_id "$G" commit -qm auth
chk "áreas saem na ordem de declaração" "$(maestro_verif_touched "$G" "$BASE" HEAD | tr '\n' ' ')" "auth docs "
chk "base == tip → nada tocado" "$(maestro_verif_touched "$G" HEAD HEAD)" ""

echo "-- touched: tip vazio = working tree + index (+ arquivo novo)"
chk "árvore limpa contra HEAD → nada tocado" "$(maestro_verif_touched "$G" "" "")" ""
echo sujo >> "$G/src/billing/inv.py"
chk "arquivo sujo não-commitado acende a área" "$(maestro_verif_touched "$G" "" "")" "billing"
git_id "$G" add -A
chk "arquivo no INDEX acende igual (staged conta)" "$(maestro_verif_touched "$G" "" "")" "billing"
git_id "$G" commit -qm billing
chk "commitado, o working tree volta a limpo" "$(maestro_verif_touched "$G" "" "")" ""
echo novo > "$G/src/auth/novo.py"
chk "arquivo NOVO não-rastreado acende a área (slop novo chega em arquivo novo)" \
  "$(maestro_verif_touched "$G" "" "")" "auth"
rm -f "$G/src/auth/novo.py"

echo "-- touched: prefixo é prefixo (e as bordas do contrato)"
mkdir -p "$G/src/authorization"; echo z > "$G/src/authorization/z.py"
chk "src/authorization/ casa o prefixo src/auth/? NÃO (o path declarado tem barra)" \
  "$(maestro_verif_touched "$G" "" "")" ""
rm -rf "$G/src/authorization"
chk "sem áreas declaradas → nada tocado" "$(maestro_verif_touched "$P2" "" "")" ""
chk "sem git → nada tocado" "$(maestro_verif_touched "$P" "" "")" ""
chk "tip sem base → nada tocado (não inventa base)" "$(maestro_verif_touched "$G" "" HEAD)" ""

echo "-- labels: união sem repetição, na ordem de declaração"
chk "duas áreas, suite aparece uma vez" "$(maestro_verif_labels "$G" auth billing | tr '\n' ' ')" \
  "suite tenant-isolation "
chk "área desconhecida é ignorada" "$(maestro_verif_labels "$G" inexistente)" ""
chk "sem área → vazio" "$(maestro_verif_labels "$G")" ""
chk "aceita as áreas em uma string só (saída do touched)" \
  "$(maestro_verif_labels "$G" "$(printf 'auth\nbilling')" | tr '\n' ' ')" "suite tenant-isolation "

echo "-- hash: MESMA fórmula do cmd_hash do recibo (DATA_MODEL §8)"
H=$(maestro_verif_hash 'bash tests/run-all.sh')
chk "16 hex" "$(printf '%s' "$H" | grep -cE '^[0-9a-f]{16}$')" "1"
chk "igual ao sha256sum truncado que o evidence grava" "$H" \
  "$(printf '%s' 'bash tests/run-all.sh' | sha256sum | head -c 16)"

exit $fail
