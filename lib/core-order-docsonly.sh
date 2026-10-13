#!/usr/bin/env bash
# maestro lib/core-order-docsonly.sh — ordem 081: o accept (e o status, que usa o mesmo _order_verif_report) dispensa os
# recibos de CÓDIGO quando o diff do branch contra o merge-base com o branch padrão REMOTO (origin/HEAD) só toca
# `docs_only_paths` do `.maestro.yaml`. O recibo `order-NN` continua exigido (nada aqui o toca).
#
# Sourced por lib/core-order-state.sh. Sem a chave, sem origin/HEAD, sem merge-base, com padrão inválido ou com diff
# vazio: NÃO dispensa (fecha para negado) e o fluxo é byte a byte o de antes.
#   - a lista vem do `.maestro.yaml` do MERGE-BASE, nunca do tip: o run edita o tip, e uma lista lida dali deixaria
#     um run declarar `src/**` como "docs" e se dispensar (mesmo princípio do fim_commit da ordem 078);
#   - `git diff --no-renames`: com detecção de rename o caminho ANTIGO (código) some do diff e um arquivo movido para
#     docs/ dispensaria; sem ela a remoção do caminho de código aparece e impede a dispensa;
#   - o casamento é o glob do próprio git (pathspec `:(exclude,glob)`): sobra no diff o que NÃO casa com padrão algum.
# Nenhum padrão é embutido: o projeto mantém a lista igual ao `paths-ignore` do CI dele.

_dz_items() { # stdin: .maestro.yaml → "K" se a chave `docs_only_paths:` existe + "P<TAB>item" por item (lista em flow, uma linha)
  awk '
    { line = $0; sub(/\r$/, "", line) }
    line ~ /^docs_only_paths:/ {
      print "K"
      s = substr(line, index(line, ":") + 1)
      sub(/[ \t]+#.*$/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
      if (s !~ /^\[.*\]$/) { print "P\t" s; exit }   # não é lista em flow: o item cru cai na validação
      s = substr(s, 2, length(s) - 2)
      n = split(s, a, ",")
      for (i = 1; i <= n; i++) {
        t = a[i]; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        if (t ~ /^"[^"]*"$/ || t ~ /^\047[^\047]*\047$/) t = substr(t, 2, length(t) - 2)
        if (n == 1 && t == "") break              # `[]`: lista vazia, sem itens
        print "P\t" t
      }
      exit
    }
  '
}
_dz_pat_ok() { # <padrão> → rc 0 se o padrão é aceitável (allowlist: nada de vazio, raiz, absoluto, ../, magia de pathspec, só-curingas)
  local p="$1"
  [[ -n "$p" && "$p" != . && "$p" != ./* ]] || return 1
  [[ "$p" != *[[:space:][:cntrl:]\"\'\\]* ]] || return 1
  [[ "$p" != /* && "$p" != :* && "$p" != *..* ]] || return 1
  [[ "$p" == *[!*/]* ]]   # só `*` e `/` (`*`, `**`, `**/*`...) casa o repo inteiro
}
_dz_tip_has_key() { # <wproj> <branch> → rc 0 se o .maestro.yaml do TIP cita a chave (só para explicar a recusa; nunca dispensa)
  git -C "$1" show "$2:.maestro.yaml" 2>/dev/null | grep -q '^docs_only_paths:'
}
_order_docsonly() { # <wproj> <arquivo> → SIM + "ARQ <caminho>"..., ou "NAO <razão>" / "AVISO <texto>"; vazio = sem a chave ou nada a dispensar
  local proj="$1" f="$2" br areas labels dref mb yml items tag it pats=() bad="" all hit l
  br=$(_order_field "$f" branch); [[ -n "$br" ]] || return 0
  git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1 || return 0
  _verif_lib_load; maestro_verif_load   # ordem 011: não residentes; aqui, no próprio subshell
  areas=$(_order_verif_areas "$proj" "$f"); [[ -n "$areas" ]] || return 0
  # shellcheck disable=SC2086
  labels=$(maestro_verif_labels "$proj" $areas); [[ -n "$labels" ]] || return 0   # sem recibo de código exigido, nada a dispensar
  dref=$(git -C "$proj" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || dref=""
  if [[ -z "$dref" ]] || ! git -C "$proj" rev-parse --verify --quiet "$dref^{commit}" >/dev/null 2>&1; then
    _dz_tip_has_key "$proj" "$br" && echo "NAO sem origin/HEAD resolvível — recibos de código cobrados"
    return 0
  fi
  mb=$(git -C "$proj" merge-base "$dref" "$br" 2>/dev/null) || mb=""
  if [[ -z "$mb" ]]; then
    _dz_tip_has_key "$proj" "$br" && echo "NAO sem merge-base entre o branch e origin/HEAD — recibos de código cobrados"
    return 0
  fi
  yml=$(git -C "$proj" show "$mb:.maestro.yaml" 2>/dev/null) || yml=""
  items=$(_dz_items <<<"$yml")
  if [[ "$items" != K* ]]; then
    _dz_tip_has_key "$proj" "$br" && echo "NAO docs_only_paths não está no .maestro.yaml do merge-base (a lista vale a de lá, não a do branch) — recibos de código cobrados"
    return 0
  fi
  while IFS=$'\t' read -r tag it; do
    [[ "$tag" == P ]] || continue
    _dz_pat_ok "$it" || bad+="'${it:-<vazio>}' "
    pats+=(":(glob)$it")
  done <<<"$items"
  [[ ${#pats[@]} -gt 0 ]] || return 0
  [[ -z "$bad" ]] || { echo "AVISO docs_only_paths tem padrão inválido (${bad% }): a lista é ignorada, nada é dispensado"; return 0; }
  all=$(git -C "$proj" diff --name-only --no-renames "$mb" "$br" -- 2>/dev/null) || all=""
  [[ -n "$all" ]] || { echo "NAO diff contra o merge-base vazio — recibos de código cobrados"; return 0; }
  while IFS= read -r l; do
    [[ "$l" != *[[:space:]\"\\]* ]] || { echo "NAO caminho com espaço ou aspas no diff — recibos de código cobrados"; return 0; }
  done <<<"$all"
  hit=$(git -C "$proj" diff --name-only --no-renames "$mb" "$br" -- "${pats[@]}" 2>/dev/null) || hit="?"
  [[ "$hit" == "$all" ]] || { echo "NAO o diff contra o merge-base toca fora de docs_only_paths — recibos de código cobrados"; return 0; }
  echo SIM
  while IFS= read -r l; do echo "ARQ $l"; done <<<"$all"
  return 0
}
_order_docsonly_say() { # <wproj> <arquivo> → o que a dispensa decidiu, no mesmo formato para o status e o accept (nada sem a chave)
  local ds l files=()
  ds=$(_order_docsonly "$1" "$2")
  while IFS= read -r l; do
    case "$l" in
      ARQ\ *) files+=("${l#ARQ }") ;;
      NAO\ *|AVISO\ *) printf '  docs    : %s\n' "${l#* }" ;;
    esac
  done <<<"$ds"
  (( ${#files[@]} > 0 )) || return 0
  printf '  docs    : recibos de código DISPENSADOS: diff contra o merge-base só em docs_only_paths (o recibo da ordem continua exigido)\n'
  printf '            %s\n' "${files[@]}"
}
_order_docsonly_kv() { # <wproj> <arquivo> → " docs_only_dispensa=1 docs_only_files=a,b" para o registro do aceite (vazio sem dispensa)
  local ds l files=""
  ds=$(_order_docsonly "$1" "$2")
  [[ "$ds" == SIM* ]] || return 0
  while IFS= read -r l; do
    [[ "$l" == "ARQ "* ]] && files+="${files:+,}${l#ARQ }"
  done <<<"$ds"
  printf ' docs_only_dispensa=1 docs_only_files=%s' "$files"
}
