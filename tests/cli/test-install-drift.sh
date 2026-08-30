#!/usr/bin/env bash
# E7 / S-710 — drift de INSTALAÇÃO: a cópia do plugin registrada no Claude Code
# divergindo deste repo (achado da migração do mount de 2026-08-18).
#
# Por que existe: `hooks.json` chama tudo por `${CLAUDE_PLUGIN_ROOT}`. Quem
# resolve esse root é o Claude Code, a partir de ~/.claude/plugins — e o
# `installPath` registrado costuma ser uma CÓPIA em cache, congelada no instante
# da instalação. Copia velha viva = rollback silencioso (tabela e injeção
# antigas, sem sinal nenhum). Mesma classe do incidente do --prefix (S-706),
# um andar acima. É AVISO: o repo é a verdade e nada aqui derruba o doctor.
#
# Hermético: MAESTRO_PLUGINS_DIR e MAESTRO_HOME em mktemp -d; skills via
# MAESTRO_SKILL_DIRS (nunca as reais). O ~/.claude/plugins real NUNCA é lido.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

command -v jq  >/dev/null || { echo "FAIL jq ausente (dependência declarada)"; exit 1; }
command -v cmp >/dev/null || { echo "FAIL cmp ausente (diffutils)"; exit 1; }

FX="$tmp/skills"; mkdir -p "$FX"
for s in systematic-debugging requesting-code-review gstack-qa gstack-ship gstack-cso gstack-office-hours; do
  mkdir -p "$FX/$s"; echo 'v1' > "$FX/$s/SKILL.md"
done

n=0
doc() { # doc <dir-de-plugins> → OUT/rc do doctor com plugins e home isolados
  n=$((n + 1))
  MAESTRO_HOME="$tmp/home$n" MAESTRO_SKILL_DIRS="$FX" MAESTRO_PLUGINS_DIR="$1" \
    "$BIN" doctor >"$tmp/out" 2>&1
  rc=$?
  HOME_USED="$tmp/home$n"
}

reg() { # reg <dir-de-plugins> <installPath> [chave] → escreve installed_plugins.json
  mkdir -p "$1"
  jq -n --arg p "$2" --arg k "${3:-maestro@maestro}" \
    '{version:2, plugins:{($k):[{scope:"user", installPath:$p, version:"1.0.4"}]}}' \
    > "$1/installed_plugins.json"
}

line() { grep -E '^(ok|warn|skip|FAIL).*instalação do plugin' "$tmp/out" | head -1; }

mkt() { # mkt <dir-de-plugins> <installLocation> [source] → known_marketplaces.json
  jq -n --arg l "$2" --arg s "${3:-directory}" \
    '{maestro:{source:{source:$s, path:$l}, installLocation:$l}}' \
    > "$1/known_marketplaces.json"
}

# ---------------------------------------------------------------------------
echo "-- sem registro: o doctor não inventa problema"
# ---------------------------------------------------------------------------
doc "$tmp/vazio"
chk "sem installed_plugins.json → exit 0" "$rc" "0"
grep -q 'ok   instalação do plugin: sem registro' "$tmp/out" \
  && ok "reporta 'repo usado direto' em vez de falhar" \
  || bad "reporta 'repo usado direto' em vez de falhar ($(line))"

reg "$tmp/outro" "/nao/importa" "superpowers@claude-plugins-official"
doc "$tmp/outro"
grep -q "ok   instalação do plugin: 'maestro' não registrado" "$tmp/out" \
  && ok "registro só de OUTRO plugin não é drift deste" \
  || bad "registro só de OUTRO plugin não é drift deste ($(line))"

# ---------------------------------------------------------------------------
echo "-- registro apontando para o próprio repo"
# ---------------------------------------------------------------------------
reg "$tmp/p-repo" "$REPO"
doc "$tmp/p-repo"
chk "installPath = repo → exit 0" "$rc" "0"
grep -q 'ok   instalação do plugin: 1 registro(s) sem cópia divergente' "$tmp/out" \
  && ok "installPath = repo → sem aviso" || bad "installPath = repo → sem aviso ($(line))"

# symlink para o repo é o MESMO repo (ADR-001 instala por symlink)
ln -s "$REPO" "$tmp/link-repo"
reg "$tmp/p-link" "$tmp/link-repo"
doc "$tmp/p-link"
grep -q 'ok   instalação do plugin' "$tmp/out" \
  && ok "symlink para o repo não é drift" || bad "symlink para o repo não é drift ($(line))"

# ---------------------------------------------------------------------------
echo "-- cópia idêntica × cópia divergente"
# ---------------------------------------------------------------------------
COPY="$tmp/cache/1.0.4"; mkdir -p "$tmp/cache"
cp -a "$REPO" "$COPY"; rm -rf "$COPY/.git"
reg "$tmp/p-copy" "$COPY"
doc "$tmp/p-copy"
chk "cópia idêntica → exit 0" "$rc" "0"
grep -q 'ok   instalação do plugin' "$tmp/out" \
  && ok "cópia byte a byte idêntica não vira ruído" \
  || bad "cópia byte a byte idêntica não vira ruído ($(line))"

# doc/teste divergindo NÃO é comportamento: não pode virar aviso
echo 'nota irrelevante' >> "$COPY/README.md"
: > "$COPY/tests/run-all.sh"
doc "$tmp/p-copy"
grep -q 'ok   instalação do plugin' "$tmp/out" \
  && ok "divergência só em doc/teste não vira aviso" \
  || bad "divergência só em doc/teste não vira aviso ($(line))"

# comportamento divergindo É aviso, e o aviso NOMEIA o arquivo
printf '\n# copia velha\n' >> "$COPY/hooks/session-start.sh"
doc "$tmp/p-copy"
chk "cópia divergente NÃO derruba o doctor" "$rc" "0"
grep -q 'warn instalação do plugin' "$tmp/out" \
  && ok "cópia divergente vira aviso" || bad "cópia divergente vira aviso ($(line))"
grep -q 'hooks/session-start.sh' "$tmp/out" \
  && ok "o aviso nomeia o arquivo que mudou" || bad "o aviso nomeia o arquivo que mudou ($(line))"
grep -q "$COPY" "$tmp/out" \
  && ok "o aviso nomeia o caminho da cópia" || bad "o aviso nomeia o caminho da cópia"
grep -q 'reinstale o plugin' "$tmp/out" \
  && ok "o aviso traz o fix" || bad "o aviso traz o fix ($(line))"

# a routing table velha é o caso que mais dói — e é detectada
COPY2="$tmp/cache2/1.0.4"; mkdir -p "$tmp/cache2"
cp -a "$REPO" "$COPY2"; rm -rf "$COPY2/.git"
printf '\n# rota fantasma\n' >> "$COPY2/config/routing-table.yaml"
reg "$tmp/p-copy2" "$COPY2"
doc "$tmp/p-copy2"
grep -q 'warn instalação do plugin.*routing-table.yaml' "$tmp/out" \
  && ok "routing-table.yaml divergente é detectado" \
  || bad "routing-table.yaml divergente é detectado ($(line))"

# versão igual não absolve: o E7 inteiro entrou sem bump de plugin.json
chk "plugin.json idêntico não impede a detecção" \
  "$(cmp -s "$REPO/.claude-plugin/plugin.json" "$COPY2/.claude-plugin/plugin.json" && echo igual)" "igual"

# ---------------------------------------------------------------------------
echo "-- quem EXECUTA decide a severidade (marketplace de diretório)"
# ---------------------------------------------------------------------------
# Medido em 2026-08-18: marketplace `source: directory` apontando para o repo faz
# do REPO o CLAUDE_PLUGIN_ROOT vivo (o plugin declara `"source": "./"`). A cópia
# em cache não executa — avisar seria ruído a cada commit de quem dogfooda.
reg "$tmp/p-live" "$COPY"; mkt "$tmp/p-live" "$REPO"
doc "$tmp/p-live"
chk "repo é a raiz viva → exit 0" "$rc" "0"
grep -q 'ok   instalação do plugin: o repo é a raiz viva' "$tmp/out" \
  && ok "cópia divergente INERTE não vira aviso" \
  || bad "cópia divergente INERTE não vira aviso ($(line))"
grep -q 'não executa' "$tmp/out" \
  && ok "a linha diz por que a cópia é inerte" || bad "a linha diz por que a cópia é inerte"

# marketplace de diretório apontando para OUTRO lugar não absolve nada
reg "$tmp/p-outro-dir" "$COPY"; mkt "$tmp/p-outro-dir" "$tmp/cache"
doc "$tmp/p-outro-dir"
grep -q 'warn instalação do plugin' "$tmp/out" \
  && ok "marketplace de diretório apontando para outro lugar → aviso" \
  || bad "marketplace de diretório apontando para outro lugar → aviso ($(line))"

# marketplace de github (a cópia em cache É a que executa) → aviso
reg "$tmp/p-github" "$COPY"; mkt "$tmp/p-github" "$REPO" "github"
doc "$tmp/p-github"
grep -q 'warn instalação do plugin' "$tmp/out" \
  && ok "marketplace github não faz do repo a raiz viva" \
  || bad "marketplace github não faz do repo a raiz viva ($(line))"

# known_marketplaces.json corrompido degrada para o lado seguro (avisa)
reg "$tmp/p-mkt-lixo" "$COPY"; printf 'lixo{' > "$tmp/p-mkt-lixo/known_marketplaces.json"
doc "$tmp/p-mkt-lixo"
chk "known_marketplaces.json corrompido → exit 0" "$rc" "0"
grep -q 'warn instalação do plugin' "$tmp/out" \
  && ok "marketplace ilegível não vira álibi (degrada avisando)" \
  || bad "marketplace ilegível não vira álibi ($(line))"

# ---------------------------------------------------------------------------
echo "-- caminho registrado que sumiu"
# ---------------------------------------------------------------------------
reg "$tmp/p-gone" "$tmp/nao-existe/1.0.4"
doc "$tmp/p-gone"
chk "installPath inexistente → exit 0" "$rc" "0"
grep -q 'warn instalação do plugin.*ausente' "$tmp/out" \
  && ok "installPath inexistente vira aviso 'ausente'" \
  || bad "installPath inexistente vira aviso 'ausente' ($(line))"

# ---------------------------------------------------------------------------
echo "-- registro malformado degrada sem erro"
# ---------------------------------------------------------------------------
mkdir -p "$tmp/p-lixo"; printf 'nao é json {' > "$tmp/p-lixo/installed_plugins.json"
doc "$tmp/p-lixo"
chk "installed_plugins.json corrompido → exit 0" "$rc" "0"
grep -qE '^(ok|skip) +instalação do plugin' "$tmp/out" \
  && ok "JSON corrompido degrada sem inventar drift" \
  || bad "JSON corrompido degrada sem inventar drift ($(line))"

mkdir -p "$tmp/p-vazio"; printf '{"version":2,"plugins":{}}' > "$tmp/p-vazio/installed_plugins.json"
doc "$tmp/p-vazio"
grep -q "ok   instalação do plugin: 'maestro' não registrado" "$tmp/out" \
  && ok "registro vazio não é drift" || bad "registro vazio não é drift ($(line))"

# entrada sem installPath (schema futuro) não pode explodir
mkdir -p "$tmp/p-sempath"
printf '{"version":2,"plugins":{"maestro@maestro":[{"scope":"user"}]}}' \
  > "$tmp/p-sempath/installed_plugins.json"
doc "$tmp/p-sempath"
chk "entrada sem installPath → exit 0" "$rc" "0"
grep -qE '^ok +instalação do plugin' "$tmp/out" \
  && ok "entrada sem installPath não vira drift" \
  || bad "entrada sem installPath não vira drift ($(line))"

# ---------------------------------------------------------------------------
echo "-- envelope (DATA_MODEL §6): fatos inteiros, nunca pass/fail"
# ---------------------------------------------------------------------------
doc "$tmp/p-copy"; CAP="$HOME_USED/capabilities.json"
chk "install.registered é inteiro" "$(jq -r '.install.registered | type' "$CAP")" "number"
chk "install.divergent é inteiro"  "$(jq -r '.install.divergent  | type' "$CAP")" "number"
chk "install.registered = 1"       "$(jq -r '.install.registered' "$CAP")" "1"
chk "install.divergent = 1 (cópia adulterada)" "$(jq -r '.install.divergent' "$CAP")" "1"
doc "$tmp/p-repo"; CAP="$HOME_USED/capabilities.json"
chk "install.divergent = 0 quando o registro é o repo" "$(jq -r '.install.divergent' "$CAP")" "0"
chk "install.repo_is_live é bool" "$(jq -r '.install.repo_is_live | type' "$CAP")" "boolean"
chk "repo_is_live=false sem marketplace de diretório" \
    "$(jq -r '.install.repo_is_live' "$CAP")" "false"
doc "$tmp/p-live"; CAP="$HOME_USED/capabilities.json"
chk "repo_is_live=true com marketplace de diretório para cá" \
    "$(jq -r '.install.repo_is_live' "$CAP")" "true"
chk "install.divergent conta a cópia inerte (fato, não veredito)" \
    "$(jq -r '.install.divergent' "$CAP")" "1"
chk "envelope não carrega caminho (§6: paths só no snapshot)" \
    "$(jq -r '.install | tostring | test("/") | tostring' "$CAP")" "false"

# ---------------------------------------------------------------------------
echo "-- nada disso vaza para o log (DATA_MODEL §4 intocado)"
# ---------------------------------------------------------------------------
doc "$tmp/p-copy"
if [[ -f "$HOME_USED/logs/routing.jsonl" ]]; then
  grep -q 'installPath\|plugins/cache' "$HOME_USED/logs/routing.jsonl" \
    && bad "caminho de instalação vazou para o routing.jsonl" \
    || ok "routing.jsonl não conhece a instalação"
else
  ok "doctor não escreve no routing.jsonl"
fi

# ---------------------------------------------------------------------------
echo "-- sem jq: skip honesto (o doctor não adivinha)"
# ---------------------------------------------------------------------------
SHIM="$tmp/shim"; mkdir -p "$SHIM"
for c in bash env readlink dirname basename date stat grep sed awk tr mkdir touch rm cmp find sort cut wc printf; do
  p="$(command -v "$c" 2>/dev/null)" || continue; ln -sf "$p" "$SHIM/$c"
done
MAESTRO_HOME="$tmp/home-nojq" MAESTRO_SKILL_DIRS="$FX" MAESTRO_PLUGINS_DIR="$tmp/p-copy" \
  PATH="$SHIM" "$BIN" doctor >"$tmp/out" 2>&1 || true
grep -q 'skip.*instalação do plugin' "$tmp/out" \
  && ok "sem jq → skip nomeando a dependência" \
  || bad "sem jq → skip nomeando a dependência ($(line))"

exit $fail
