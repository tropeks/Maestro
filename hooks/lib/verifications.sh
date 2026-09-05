#!/usr/bin/env bash
# hooks/lib/verifications.sh — verificações obrigatórias por área (E23b/S-2302).
#
# Responde "que prova este changeset DEVE ter" a partir do `.maestro.yaml` do
# projeto. Quem consome: `maestro verify`, `maestro evidence` (recibo casa o
# comando), `order --accept` e `outcome accepted`. Bash+awk puros: nenhum yq,
# nenhum Bun, nenhum jq — a mesma fronteira dos hooks (esta lib é sourceável
# por hook, ainda que hoje só o CLI a use).
#
# ---------------------------------------------------------------------------
# Formato lido do `.maestro.yaml` (DATA_MODEL §2):
#
#   verifications:
#     auth:                                  # nome da área
#       paths: [src/auth/, migrations/]      # prefixos de caminho que a área governa
#       labels: [suite, tenant-isolation]    # rótulos de recibo exigidos ao tocá-la
#     billing:
#       paths: src/billing/                  # lista separada por espaço também vale
#       labels: suite
#   commands:                                # comando canônico por rótulo (opcional)
#     suite: bash tests/run-all.sh
#
# Regras do parser (deliberadamente rasas — é config, não YAML completo):
#   - `verifications:`/`commands:` só valem na coluna 0; qualquer outra chave na
#     coluna 0 FECHA o bloco (o parser nunca vaza para a chave seguinte);
#   - lista em flow (`[a, b]`) ou separada por espaço; uma linha só (flow
#     multi-linha e bloco `- item` NÃO são suportados e são ignorados);
#   - comentário ` #...` é removido do valor; aspas nas pontas são removidas;
#   - nome de área `^[a-z0-9][a-z0-9._-]{0,31}$`, path `^[A-Za-z0-9._/-]{1,80}$`,
#     rótulo com a MESMA regra do `--label` do evidence (`^[a-z][a-z0-9-]{0,23}$`);
#     item fora da regra é descartado em silêncio (config malformada nunca
#     derruba quem chama — degrada para "nada exigido");
#   - área SEM path válido é ignorada: prefixo nenhum casa nada, então ela não
#     governa área alguma. Aparecer na lista só induziria a erro.
#
# O comando declarado NUNCA é executado por esta lib — é comparado como string
# (e hasheado) para o recibo provar que rodou o comando que o projeto declara.
# ---------------------------------------------------------------------------

# Áreas declaradas → uma linha TSV por área: `nome\tpaths\tlabels`
# (paths e labels separados por espaço, na ordem em que foram declarados).
maestro_verif_areas() { # <raiz-do-projeto>
  local f="${1:-$PWD}/.maestro.yaml"
  [[ -f "$f" && -r "$f" ]] || return 0
  awk '
    function clean(s) {
      sub(/[ \t]+#.*$/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
      sub(/^["\047]/, "", s); sub(/["\047]$/, "", s)
      return s
    }
    function list(s, re,   n, i, t, out, a) {
      s = clean(s); sub(/^\[/, "", s); sub(/\]$/, "", s); gsub(/,/, " ", s)
      n = split(s, a, /[ \t]+/); out = ""
      for (i = 1; i <= n; i++) {
        t = a[i]
        # Aspas só saem em PAR. Item com aspa solta veio de um valor com espaço
        # ("com espaço"), que este parser não suporta: descartar os dois pedaços
        # é mais honesto que aceitar meio caminho como se fosse um path.
        if (t ~ /^"[^"]*"$/ || t ~ /^\047[^\047]*\047$/) t = substr(t, 2, length(t) - 2)
        else if (t ~ /["\047]/) continue
        if (t != "" && t ~ re) out = out (out == "" ? "" : " ") t
      }
      return out
    }
    { line = $0; sub(/\r$/, "", line) }
    line ~ /^verifications:[ \t]*(#.*)?$/ { blk = "v"; area = ""; next }
    line ~ /^[^ \t]/                      { blk = "";  area = ""; next }
    blk != "v" { next }
    # `paths:`/`labels:` pertencem à área corrente; qualquer outra chave de
    # valor vazio ABRE uma área nova.
    area != "" && line ~ /^[ \t]+paths:/ {
      p[area] = list(substr(line, index(line, ":") + 1), "^[A-Za-z0-9._/-]{1,80}$"); next
    }
    area != "" && line ~ /^[ \t]+labels:/ {
      l[area] = list(substr(line, index(line, ":") + 1), "^[a-z][a-z0-9-]{0,23}$"); next
    }
    line ~ /^[ \t]+[A-Za-z0-9][A-Za-z0-9._-]*:[ \t]*(#.*)?$/ {
      a = line; sub(/:[ \t]*(#.*)?$/, "", a); a = clean(a)
      if (a !~ /^[a-z0-9][a-z0-9._-]{0,31}$/) { area = ""; next }
      area = a
      if (!(area in seen)) { seen[area] = 1; ord[++n] = area }
      next
    }
    # Cabeçalho de área com nome fora da regra (ex.: `RUIM!:`): a área é
    # descartada E o cursor é zerado — sem isto o `paths:` DELA seria creditado
    # à área anterior, que passaria a governar caminho que ninguém lhe deu.
    line ~ /^[ \t]+[^ \t#][^:]*:[ \t]*(#.*)?$/ { area = ""; next }
    END {
      for (i = 1; i <= n; i++) {
        a = ord[i]
        if (p[a] == "") continue            # área sem path não governa nada
        printf "%s\t%s\t%s\n", a, p[a], l[a]
      }
    }
  ' "$f" 2>/dev/null || return 0
  return 0
}

# Comando canônico declarado para um rótulo (vazio quando não há).
maestro_verif_cmd() { # <raiz-do-projeto> <rótulo>
  local f="${1:-$PWD}/.maestro.yaml" label="${2:-}"
  [[ -f "$f" && -r "$f" ]] || return 0
  [[ "$label" =~ ^[a-z][a-z0-9-]{0,23}$ ]] || return 0
  awk -v want="$label" '
    { line = $0; sub(/\r$/, "", line) }
    line ~ /^commands:[ \t]*(#.*)?$/ { blk = "c"; next }
    line ~ /^[^ \t]/                 { blk = "";  next }
    blk != "c" { next }
    line ~ /^[ \t]+[a-z][a-z0-9-]*:/ {
      k = line; sub(/^[ \t]+/, "", k); v = substr(k, index(k, ":") + 1)
      k = substr(k, 1, index(k, ":") - 1)
      if (k != want) next
      sub(/[ \t]+#.*$/, "", v); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      sub(/^["\047]/, "", v); sub(/["\047]$/, "", v)
      if (v != "" && length(v) <= 240 && v !~ /[[:cntrl:]]/) { print v; exit }
    }
  ' "$f" 2>/dev/null || return 0
  return 0
}

# 16 hex do sha256 de uma string — MESMA fórmula do `cmd_hash` do recibo
# (DATA_MODEL §8). Existe aqui para que o leitor do recibo e o declarante do
# comando derivem o hash pelo mesmo lugar; divergência viraria falso "VENCIDA".
maestro_verif_hash() { # <string>
  local h
  h=$(printf '%s' "${1:-}" | sha256sum 2>/dev/null | head -c 16) || h=""
  printf '%s' "${h:-none}"
  return 0
}

# Áreas TOCADAS por um changeset — uma por linha, na ordem de declaração.
# `tip` vazio = working tree + index (+ arquivos novos não-ignorados) contra a
# base; `base` vazia nesse modo = HEAD. Casamento por PREFIXO de caminho.
# Sem git, sem base resolvível ou sem áreas declaradas → nada tocado (silêncio:
# projeto sem declaração não passa a dever prova nenhuma).
maestro_verif_touched() { # <raiz-do-projeto> <base> [tip]
  local proj="${1:-$PWD}" base="${2:-}" tip="${3:-}"
  local areas files name paths labels p f hit
  areas=$(maestro_verif_areas "$proj") || return 0
  [[ -n "$areas" ]] || return 0
  git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || return 0
  if [[ -n "$tip" ]]; then
    [[ -n "$base" ]] || return 0
    files=$(git -C "$proj" diff --name-only "$base" "$tip" 2>/dev/null) || files=""
  else
    files=$( { git -C "$proj" diff --name-only "${base:-HEAD}" 2>/dev/null
               git -C "$proj" ls-files --others --exclude-standard 2>/dev/null; } | sort -u) || files=""
  fi
  [[ -n "$files" ]] || return 0
  while IFS=$'\t' read -r name paths labels; do
    [[ -n "$name" ]] || continue
    : "$labels"
    hit=0
    for p in $paths; do
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        if [[ "$f" == "$p"* ]]; then hit=1; break; fi
      done <<<"$files"
      (( hit == 1 )) && break
    done
    (( hit == 1 )) && printf '%s\n' "$name"
  done <<<"$areas"
  return 0
}

# União dos rótulos exigidos pelas áreas dadas — um por linha, sem repetição,
# na ordem de declaração das áreas. Área desconhecida é ignorada.
maestro_verif_labels() { # <raiz-do-projeto> <área>...
  local proj="${1:-$PWD}"; shift || true
  local want=" $* " name paths labels lb seen=" "
  want="${want//$'\n'/ }"
  [[ -n "${want// /}" ]] || return 0
  while IFS=$'\t' read -r name paths labels; do
    [[ -n "$name" ]] || continue
    : "$paths"
    [[ "$want" == *" $name "* ]] || continue
    for lb in $labels; do
      [[ "$seen" == *" $lb "* ]] && continue
      seen+="$lb "
      printf '%s\n' "$lb"
    done
  done < <(maestro_verif_areas "$proj")
  return 0
}
