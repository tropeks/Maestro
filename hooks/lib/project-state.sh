#!/usr/bin/env bash
# hooks/lib/project-state.sh — estado situacional por projeto (E8 + E11).
#
# Extraído do common.sh quando ele cruzou as 400 linhas (a própria catraca
# oversized-file do E9 cobrou — 2026-08-25). Coesão do grupo: os dois helpers
# respondem "onde este PROJETO está" — caminho do brief (E8/S-801) e frescor
# do grafo graphify (E11) — e nada aqui toca log, gate ou kill-switch.
# Carregado PELO common.sh: quem consome continua com um único source.

# ---------------------------------------------------------------------------
# E11 — estado do grafo graphify (graphify-out/graph.json) SEM carimbo próprio:
# freshness = mtime do graph.json vs data do último commit. Barato (2 forks) —
# roda dentro do session-start. Saída em uma linha:
#   absent | nogit <idade_min> | fresh <idade_min> | stale <commits_atras>
# Grafo velho é fato morto vestido de mapa: o veredito NUNCA finge frescor.
# ---------------------------------------------------------------------------
maestro_graph_state() { # <raiz-do-projeto>
  local root="${1:-$PWD}" gj mt now age last n
  gj="$root/graphify-out/graph.json"
  [[ -f "$gj" && -r "$gj" ]] || { printf 'absent\n'; return 0; }
  mt=$(stat -c %Y -- "$gj" 2>/dev/null) || mt=""
  now=$(maestro_now_epoch)
  [[ "$mt" =~ ^[0-9]+$ ]] || { printf 'nogit 0\n'; return 0; }
  age=$(( (now - mt) / 60 )); (( age < 0 )) && age=0
  last=$(git -C "$root" log -1 --format=%ct 2>/dev/null) || last=""
  [[ "$last" =~ ^[0-9]+$ ]] || { printf 'nogit %s\n' "$age"; return 0; }
  if (( mt >= last )); then
    printf 'fresh %s\n' "$age"
  else
    n=$(git -C "$root" rev-list --count HEAD --since="@$mt" 2>/dev/null) || n=""
    [[ "$n" =~ ^[0-9]+$ ]] || n="?"
    printf 'stale %s\n' "$n"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# E8/S-801 — caminho do brief de projeto (DATA_MODEL §7).
# Chave = basename saneado + 8 hex do sha256 do caminho absoluto: legível no ls
# e sem colisão entre projetos homônimos. ÚNICA definição — session-start e
# bin/maestro derivam por aqui; divergência quebraria o ponteiro da injeção.
# ---------------------------------------------------------------------------
maestro_brief_file() { # <raiz-do-projeto> → caminho do brief no stdout
  # Hash djb2 em bash puro: isto roda DENTRO do session-start (NFR <100ms) e
  # cada fork custa ~7ms nesta classe de máquina — sha256sum+tr+head eram 4.
  # Não é hash criptográfico e não precisa ser: é chave de arquivo, e a única
  # propriedade exigida é determinismo (CLI e hook derivam pela MESMA função).
  local root="${1:-$PWD}" real base slug="" i c h=5381
  real=$(cd -P -- "$root" 2>/dev/null && pwd) || real="$root"
  base="${real##*/}"
  slug="${base//[^a-zA-Z0-9._-]/-}"; slug="${slug:0:32}"
  for (( i = 0; i < ${#real}; i++ )); do
    printf -v c '%d' "'${real:i:1}" 2>/dev/null || c=63
    h=$(( ((h * 33) + c) & 0xFFFFFFFF ))
  done
  printf '%s/briefs/%s-%08x.md' "${MAESTRO_HOME:-$HOME/.maestro}" "${slug:-projeto}" "$h"
}


# ---------------------------------------------------------------------------
# E13/S-1301 — caminho do recibo de evidência (DATA_MODEL §8). Mesma chave
# djb2 do brief: evidência é estado DO PROJETO, por rótulo (suite, build…).
# ---------------------------------------------------------------------------
maestro_evidence_file() { # <raiz-do-projeto> <rótulo> → caminho no stdout
  local bf; bf=$(maestro_brief_file "$1")
  local base="${bf##*/}"; base="${base%.md}"
  printf '%s/evidence/%s-%s' "${MAESTRO_HOME:-$HOME/.maestro}" "$base" "${2:-suite}"
}
