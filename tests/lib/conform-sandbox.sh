#!/usr/bin/env bash
# tests/lib/conform-sandbox.sh — sandbox de `maestro conform` (ordem 042).
#
# `bin/` está na denylist de autoproteção do gate (mesma classe de
# hooks/012) — o despacho do comando `conform` (`_conform_lib_load` +
# `conform) shift; ...`) só existe hoje em
# `docs/patches/042-conform-bin-maestro-despachante.patch`; quem aplica no
# repo real é o Capitão. Molde da ordem 027 (armadilha "sandbox some com o
# lib/ que o mecanismo sabotado precisa"): a sandbox aqui symlinka lib/,
# hooks/, agents/, src/, config/ do repo real (leitura, nunca escrita — os
# módulos de conform em si não são "sabotados", só o dispatch em bin/maestro
# precisa nascer de um jeito ou de outro) e SÓ copia bin/maestro, aplicando o
# patch quando o dispatch ainda não existe nele. Detecta pelo MECANISMO
# (grep por `_conform_lib_load`), nunca pelo número da ordem: se o Capitão já
# aplicou o patch no repo, a sandbox usa o bin/maestro real tal como está —
# sem reaplicar (git apply reprovaria num arquivo já mudado).
#
# Sourceável, não é enumerado como teste (nome sem `test-` — mesmo contrato
# de tests/lib/env-clean.sh).

# conform_sandbox_build <repo> <tmpdir> → grava CONFORM_BIN=<caminho do maestro pronto>
conform_sandbox_build() {
  local repo="$1" tmp="$2" patchfile
  patchfile="$repo/docs/patches/042-conform-bin-maestro-despachante.patch"
  mkdir -p "$tmp/sandbox/bin"
  cp "$repo/bin/maestro" "$tmp/sandbox/bin/maestro"
  if ! grep -q '_conform_lib_load' "$tmp/sandbox/bin/maestro" 2>/dev/null; then
    [[ -f "$patchfile" ]] || { echo "conform-sandbox: patch ausente: $patchfile" >&2; return 1; }
    ( cd "$tmp/sandbox" && patch -s -p1 < "$patchfile" ) \
      || { echo "conform-sandbox: falha ao aplicar $patchfile" >&2; return 1; }
  fi
  chmod +x "$tmp/sandbox/bin/maestro"
  local d
  for d in lib hooks agents src config; do
    [[ -e "$tmp/sandbox/$d" ]] || ln -s "$repo/$d" "$tmp/sandbox/$d"
  done
  CONFORM_BIN="$tmp/sandbox/bin/maestro"
  return 0
}

# conform_fixture_golden <dir> — projeto git conforme (todas as 6 famílias OK,
# exceto brief e cadastro no ponte, que quem chama resolve à parte).
conform_fixture_golden() {
  local p="$1"
  mkdir -p "$p/.maestro" "$p/docs"
  git -C "$p" init -q
  git -C "$p" config user.email t@conform.test
  git -C "$p" config user.name conform-test
  printf '# projeto de teste\n' > "$p/CLAUDE.md"
  printf '# projeto de teste\n' > "$p/README.md"
  printf '# guia\n' > "$p/docs/GUIA.md"
  cat > "$p/.maestro.yaml" <<'EOF'
docs: [docs/GUIA.md]
verifications:
  core:
    paths: [src/]
    labels: [suite]
commands:
  suite: "true"
EOF
  local body="$p/.maestro/.INTENT.body.$$"
  cat > "$body" <<'EOF'
# Direção — teste

## Problema

problema de teste

## Público

público de teste

## Resultado

resultado de teste

## Prioridades

prioridades de teste

## Limites

limites de teste

## Fora de escopo

fora de escopo de teste
EOF
  local hash; hash=$(sha256sum "$body" | head -c 8)
  {
    printf '<!-- maestro-intent v1\n'
    printf 'version: 1\nts: 2020-01-01T00:00:00-03:00\nhead: none\n'
    printf 'author_session: fixture\nhash: %s\n' "$hash"
    printf -- '-->\n'
    cat "$body"
  } > "$p/.maestro/INTENT.md"
  rm -f "$body"
  git -C "$p" add -A
  git -C "$p" commit -q -m "fixture golden"
  return 0
}

# conform_fixture_ponte_db <db> <slug> <policy:0|1> — cria o banco fixture;
# policy=1 grava as três colunas de política preenchidas, policy=0 deixa
# risk_policy NULL (ponte-no-policy). slug ausente do banco = ponte-unregistered.
conform_fixture_ponte_db() {
  local db="$1" slug="$2" policy="${3:-1}" risk="'low'"
  [[ -f "$db" ]] || sqlite3 "$db" \
    "CREATE TABLE manager_definition (project_slug TEXT PRIMARY KEY, manager_model_policy TEXT, tool_allowlist TEXT, risk_policy TEXT);"
  [[ "$policy" == "1" ]] || risk="NULL"
  sqlite3 "$db" "INSERT OR REPLACE INTO manager_definition (project_slug, manager_model_policy, tool_allowlist, risk_policy) VALUES ('$slug','p','[\"Read\"]',$risk);"
  return 0
}

# conform_write_brief <bin> <home> <proj> — brief real via `maestro brief --write --auto`
conform_write_brief() {
  local bin="$1" home="$2" proj="$3"
  MAESTRO_HOME="$home" "$bin" brief --write --auto --project "$proj" --session fixture0001 >/dev/null 2>&1
  return 0
}

# conform_check_json_parity <bin> <dir> <home> <db> <texto-já-capturado> → rc
# 0 se --json é JSON válido (jq) e lista os MESMOS códigos, na MESMA ordem,
# do texto dado; rc 1 se inválido ou diverge; rc 2 se `jq` ausente (quem
# chama decide: PENDENTE, nunca FALHA por dependência faltando).
conform_check_json_parity() {
  local bin="$1" dir="$2" home="$3" db="$4" text="$5" json codes_txt codes_json
  command -v jq >/dev/null 2>&1 || return 2
  json=$(env MAESTRO_HOME="$home" MAESTRO_PONTE_DB="$db" "$bin" conform --check --json "$dir" 2>/dev/null)
  echo "$json" | jq -e . >/dev/null 2>&1 || return 1
  codes_txt=$(printf '%s\n' "$text" | awk -F'\t' 'NF{print $1}')
  codes_json=$(echo "$json" | jq -r '.lacunas[].codigo')
  [[ "$codes_txt" == "$codes_json" ]]
}

# conform_sandbox_agents <repo> <tmpdir> → grava AGENTS_SANDBOX=<dir com o
# roster REAL + agents/conformador.md aplicado do patch (Parte B, ordem 042).
# `agents/` está na denylist do gate (mesma classe de bin/) — o arquivo só
# existe hoje em docs/patches/042-conform-agents-conformador.patch, aplicado
# pelo Capitão. Mesmo mecanismo de detecção de conform_sandbox_build: se o
# arquivo já existir no roster real, não reaplica.
conform_sandbox_agents() {
  local repo="$1" tmp="$2" patchfile
  patchfile="$repo/docs/patches/042-conform-agents-conformador.patch"
  mkdir -p "$tmp/agentsrepo/agents"
  cp "$repo"/agents/*.md "$tmp/agentsrepo/agents/" 2>/dev/null
  if [[ ! -f "$tmp/agentsrepo/agents/conformador.md" ]]; then
    [[ -f "$patchfile" ]] || { echo "conform-sandbox: patch de agents ausente: $patchfile" >&2; return 1; }
    ( cd "$tmp/agentsrepo" && patch -s -p1 < "$patchfile" ) \
      || { echo "conform-sandbox: falha ao aplicar patch de agents" >&2; return 1; }
  fi
  AGENTS_SANDBOX="$tmp/agentsrepo/agents"
  return 0
}
