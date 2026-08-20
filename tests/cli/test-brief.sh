#!/usr/bin/env bash
# E8 / S-801 — `maestro brief`: estado situacional por projeto, carimbado por
# conteúdo (ts/epoch/HEAD/wtree/session), em bash puro (sem Bun de propósito:
# o brief é a arma contra o cold start e não pode depender de runtime).
# Hermético: MAESTRO_HOME e projetos-fixture em mktemp -d.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

export MAESTRO_HOME="$tmp/home"

mkrepo() { # mkrepo <dir> → repo git com 1 commit
  mkdir -p "$1"; git -C "$1" init -q
  echo conteudo > "$1/a.txt"; git -C "$1" add -A
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm inicial
}
commit_more() { echo mais >> "$1/a.txt"; git -C "$1" add -A; git -C "$1" -c user.email=t@t -c user.name=t commit -qm outro; }

PROJ="$tmp/projeto"; mkrepo "$PROJ"

# ---------------------------------------------------------------------------
echo "-- --path: determinístico e sem colisão"
# ---------------------------------------------------------------------------
p1=$("$BIN" brief --path --project "$PROJ")
p2=$("$BIN" brief --path --project "$PROJ")
chk "duas chamadas dão o mesmo caminho" "$p1" "$p2"
[[ "$p1" == "$MAESTRO_HOME/briefs/"*.md ]] \
  && ok "caminho vive em \$MAESTRO_HOME/briefs/" || bad "caminho vive em \$MAESTRO_HOME/briefs/ ($p1)"
mkdir -p "$tmp/outro/projeto"
p3=$("$BIN" brief --path --project "$tmp/outro/projeto")
[[ "$p1" != "$p3" ]] && ok "mesmo basename em dirs distintos → chaves distintas" \
                     || bad "mesmo basename em dirs distintos → chaves distintas"

# ---------------------------------------------------------------------------
echo "-- leitura sem brief: informativo, nunca erro"
# ---------------------------------------------------------------------------
out=$("$BIN" brief --project "$PROJ" 2>&1); rc=$?
chk "sem brief → exit 0" "$rc" "0"
grep -q 'nenhum brief' <<<"$out" && ok "diz que não existe e como criar" \
                                 || bad "diz que não existe e como criar ($out)"

# ---------------------------------------------------------------------------
echo "-- --write: carimbos corretos, escrita atômica"
# ---------------------------------------------------------------------------
out=$(printf 'Em curso: E8.\nPróximo: docs.\n' | "$BIN" brief --write --session sessao-abc --project "$PROJ" 2>&1); rc=$?
chk "--write via stdin → exit 0" "$rc" "0"
BF=$("$BIN" brief --path --project "$PROJ")
[[ -f "$BF" ]] && ok "arquivo gravado" || bad "arquivo gravado"
chk "cabeçalho v1 na primeira linha" "$(head -1 "$BF")" "<!-- maestro-brief v1"
grep -q '^session: sessao-abc$' "$BF" && ok "session carimbada" || bad "session carimbada"
HEAD1=$(git -C "$PROJ" rev-parse HEAD)
grep -q "^head: $HEAD1\$" "$BF" && ok "HEAD carimbado é o real" || bad "HEAD carimbado é o real"
grep -Eq '^wtree: [0-9a-f]{40}$' "$BF" && ok "wtree carimbado (40 hex)" || bad "wtree carimbado (40 hex)"
grep -Eq '^epoch: [0-9]+$' "$BF" && ok "epoch é inteiro" || bad "epoch é inteiro"
grep -q 'Próximo: docs.' "$BF" && ok "narrativa preservada" || bad "narrativa preservada"
ls "$MAESTRO_HOME/briefs/"*.tmp.* >/dev/null 2>&1 \
  && bad "sem tmp órfão após o write" || ok "sem tmp órfão após o write"

# ---------------------------------------------------------------------------
echo "-- freshness: FRESCO → wtree mudou → STALE por commit"
# ---------------------------------------------------------------------------
out=$("$BIN" brief --project "$PROJ")
grep -q 'FRESCO' <<<"$out" && ok "nada mudou → FRESCO" || bad "nada mudou → FRESCO ($out)"
grep -q 'working tree idêntico' <<<"$out" \
  && ok "veredito por conteúdo (wtree) no CLI" || bad "veredito por conteúdo (wtree) no CLI"
echo suja > "$PROJ/novo.txt"
out=$("$BIN" brief --project "$PROJ")
grep -q 'working tree MUDOU' <<<"$out" \
  && ok "arquivo novo → wtree acusa mudança com HEAD igual" \
  || bad "arquivo novo → wtree acusa mudança com HEAD igual ($out)"
rm -f "$PROJ/novo.txt"
commit_more "$PROJ"
out=$("$BIN" brief --project "$PROJ")
grep -q 'STALE — 1 commit(s)' <<<"$out" && ok "1 commit depois → STALE contando" \
                                        || bad "1 commit depois → STALE contando ($out)"
grep -q "${HEAD1:0:7}" <<<"$out" && ok "STALE nomeia o SHA do carimbo" || bad "STALE nomeia o SHA do carimbo"

# ---------------------------------------------------------------------------
echo "-- fora de git: degrada com honestidade"
# ---------------------------------------------------------------------------
NOGIT="$tmp/semgit"; mkdir -p "$NOGIT"
printf 'nota\n' | "$BIN" brief --write --project "$NOGIT" >/dev/null 2>&1; rc=$?
chk "--write fora de git → exit 0" "$rc" "0"
grep -q '^head: none$' "$("$BIN" brief --path --project "$NOGIT")" \
  && ok "head: none fora de git" || bad "head: none fora de git"
out=$("$BIN" brief --project "$NOGIT")
grep -q 'sem veredito de conteúdo' <<<"$out" \
  && ok "leitura fora de git não finge freshness" || bad "leitura fora de git não finge freshness ($out)"

# ---------------------------------------------------------------------------
echo "-- --auto: esqueleto determinístico do git"
# ---------------------------------------------------------------------------
"$BIN" brief --auto --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "--auto → exit 0" "$rc" "0"
BF=$("$BIN" brief --path --project "$PROJ")
grep -q 'outro' "$BF" && ok "esqueleto traz commits recentes" || bad "esqueleto traz commits recentes"
grep -q 'arquivo(s) sujo(s)' "$BF" && ok "esqueleto conta dirty files" || bad "esqueleto conta dirty files"
grep -q 'próximo passo' "$BF" && ok "esqueleto pede a narrativa humana" || bad "esqueleto pede a narrativa humana"

# ---------------------------------------------------------------------------
echo "-- validação e limites"
# ---------------------------------------------------------------------------
: | "$BIN" brief --write --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "narrativa vazia → exit 1 (validação)" "$rc" "1"
"$BIN" brief --flag-inventada --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "flag desconhecida → exit 1" "$rc" "1"
"$BIN" brief --write --session 'id inválido!' --project "$PROJ" >/dev/null 2>&1 </dev/null; rc=$?
chk "session malformada → exit 1" "$rc" "1"
head -c 40000 /dev/zero | tr '\0' 'x' | "$BIN" brief --write --project "$PROJ" >/dev/null 2>&1
sz=$(wc -c < "$("$BIN" brief --path --project "$PROJ")")
(( sz < 17000 )) && ok "narrativa gigante é capada (~16KB; ficou ${sz}B)" \
                 || bad "narrativa gigante é capada (ficou ${sz}B)"

# ---------------------------------------------------------------------------
echo "-- sem Bun no PATH: brief continua inteiro"
# ---------------------------------------------------------------------------
SHIM="$tmp/shim"; mkdir -p "$SHIM"
for c in bash env readlink dirname basename date git awk grep sed head tr mkdir mv rm wc ls cksum; do
  q="$(command -v "$c" 2>/dev/null)" || continue; ln -sf "$q" "$SHIM/$c"
done
printf 'sem bun\n' | PATH="$SHIM" "$BIN" brief --write --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "--write sem Bun → exit 0" "$rc" "0"
PATH="$SHIM" "$BIN" brief --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "leitura sem Bun → exit 0" "$rc" "0"

# ---------------------------------------------------------------------------
echo "-- carimbo ilegível: aviso, nunca crash"
# ---------------------------------------------------------------------------
printf 'lixo sem cabeçalho\n' > "$("$BIN" brief --path --project "$PROJ")"
out=$("$BIN" brief --project "$PROJ" 2>&1); rc=$?
chk "brief corrompido → exit 0" "$rc" "0"
grep -q 'carimbo ilegível' <<<"$out" && ok "corrompido vira aviso de regravação" \
                                     || bad "corrompido vira aviso de regravação ($out)"

# ---------------------------------------------------------------------------
echo "-- nada vaza para o log (DATA_MODEL §4 intocado)"
# ---------------------------------------------------------------------------
if [[ -f "$MAESTRO_HOME/logs/routing.jsonl" ]]; then
  grep -q 'brief\|briefs/' "$MAESTRO_HOME/logs/routing.jsonl" \
    && bad "routing.jsonl não conhece o brief" || ok "routing.jsonl não conhece o brief"
else
  ok "brief não escreve no routing.jsonl"
fi

exit $fail
