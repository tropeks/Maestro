#!/usr/bin/env bash
# maestro lib/core-conform-ponte.sh — ordem 042, família (e) de `maestro conform --check`.
#
# Lê `~/.ponte/ponte.db` (SQLite) SOMENTE em modo read-only (`sqlite3
# -readonly`) — nunca escreve, nunca abre para escrita mesmo que o arquivo
# permita. Override por `MAESTRO_PONTE_DB` (testes: fixture, nunca o banco
# real). Sem `sqlite3` no PATH, sem o arquivo, ou consulta que falha (banco
# corrompido/travado) → `ponte-unreadable`: é LACUNA, nunca crash e nunca
# aprovação silenciosa. `chmod 0444` no banco não quebra nada — `-readonly`
# só precisa de permissão de leitura.
#
# Slug = basename do toplevel git, minúsculas, `_`→`-` (a mesma regra de
# `slugifyProjectName` no daemon, DATA_MODEL do ponte — texto da ordem 042).
#
# Sourced por lib/cmd-conform.sh — REPO_DIR/die()/has() já no escopo (bin/maestro).

_conform_project_slug() { # <proj> → slug (basename do toplevel git, minúsculas, _→-)
  local proj="$1" top base
  top=$(git -C "$proj" rev-parse --show-toplevel 2>/dev/null) || top="$proj"
  base=$(basename -- "$top")
  base="${base,,}"; base="${base//_/-}"
  printf '%s' "$base"
  return 0
}

_conform_check_ponte() { # <proj> → TSV de lacunas da família (e) daemon
  local proj="$1" db="${MAESTRO_PONTE_DB:-$HOME/.ponte/ponte.db}" slug row rc p1 p2 p3

  if ! has sqlite3 || [[ ! -f "$db" || ! -r "$db" ]]; then
    printf '5\tponte-unreadable\tponte.db\tinstale sqlite3 e garanta leitura de ~/.ponte/ponte.db (ou exporte MAESTRO_PONTE_DB nos testes)\n'
    return 0
  fi

  slug=$(_conform_project_slug "$proj")
  slug="${slug//\'/\'\'}"   # aspas simples do slug (improvável, mas nunca confie em basename de diretório alheio)
  row=$(sqlite3 -batch -readonly -separator $'\t' -- "$db" \
    "SELECT manager_model_policy IS NOT NULL, tool_allowlist IS NOT NULL, risk_policy IS NOT NULL
     FROM manager_definition WHERE project_slug = '$slug' LIMIT 1;" 2>/dev/null)
  rc=$?
  if (( rc != 0 )); then
    printf '5\tponte-unreadable\tponte.db\tbanco ilegível (consulta falhou — locked ou corrompido)\n'
    return 0
  fi
  if [[ -z "$row" ]]; then
    printf '5\tponte-unregistered\tponte.db\tcadastre "%s" em manager_definition — é o Diretor quem cadastra\n' "$slug"
    return 0
  fi
  IFS=$'\t' read -r p1 p2 p3 <<<"$row"
  if [[ "$p1" != "1" || "$p2" != "1" || "$p3" != "1" ]]; then
    printf '5\tponte-no-policy\tponte.db\tpreencha manager_model_policy/tool_allowlist/risk_policy de "%s" no ponte.db — é o Diretor quem decide a política\n' "$slug"
  fi
  return 0
}
