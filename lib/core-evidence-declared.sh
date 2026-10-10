#!/usr/bin/env bash
# maestro lib/core-evidence-declared.sh — ordem 078 (fase S0 de segurança).
#
# `evidence --record` executava QUALQUER comando depois do `--`. Aqui a recusa vem ANTES de executar:
#   - `order-N`  : só o comando entre crases no `fim:` do bloco `## Turno` da ordem N, lido do COMMIT-BASE
#                  (`fim_commit`, gravado por `maestro order --baseline N`), nunca da árvore de trabalho;
#   - área       : `suite`, `tenant-isolation`, `billing`, `frontend` (e `<área>-N`) só o `commands.<área>`
#                  do .maestro.yaml; rótulo de área sem declaração é recusado;
#   - rótulo livre: como sempre (nenhum gate lê esse recibo).
# Comparação: palavra por palavra sobre os argumentos recebidos, depois de normalizar espaços/tabs do
# DECLARADO; nada de expandir variável, tirar aspas ou tratar `;` `&&` `|` — argumento com espaço é recusado.
# Fecha para negado: ordem inexistente, sem `## Turno`, `fim:` sem crases, sem `fim_commit`, `fim:` que
# mudou depois do baseline ou está editado sem commit. Nenhuma flag, variável de ambiente ou MAESTRO_HOME
# liga a recusa para "livre". O leitor do veredito (maestro_proof_verdict) NÃO muda.
# O que isto não cobre (ENGINEERING_SPEC): o comando declarado roda o que o repo contém, e o ledger em
# ~/.maestro (recibo, baseline) é forjável pelo run enquanto ele roda com o usuário do Capitão.
#
# Sourced por lib/cmd-evidence.sh e lib/cmd-order.sh (--baseline), mesmo processo: die() já no escopo.

_evd_words_equal() { # <declarado> <arg>... → rc 0 se os argumentos são, palavra a palavra, o declarado
  local decl="$1" w=() a i=0
  shift
  read -ra w <<<"$decl"
  (( ${#w[@]} > 0 && ${#w[@]} == $# )) || return 1
  for a in "$@"; do
    [[ "$a" =~ [[:space:]] ]] && return 1
    [[ "$a" == "${w[i]}" ]] || return 1
    i=$((i + 1))
  done
  return 0
}

_evd_bashc_equal() { # <declarado> <arg>... → rc 0 só se for `bash` `-c` <um argumento = o declarado, espaços normalizados>
  local decl="$1" w=()
  shift
  (( $# == 3 )) && [[ "$1" == bash && "$2" == -c ]] || return 1
  [[ "$3" == *$'\n'* ]] && return 1
  read -ra w <<<"$3"
  (( ${#w[@]} > 0 )) && [[ "${w[*]}" == "$decl" ]]
}

_evd_fim_cmds() { # <valor do fim:> → um comando declarado por linha (só o que está entre crases)
  local s="$1" re='`([^`]+)`' c
  while [[ "$s" =~ $re ]]; do
    c="${BASH_REMATCH[1]}"
    printf '%s\n' "$(read -ra w <<<"$c"; printf '%s' "${w[*]}")"
    s="${s#*"${BASH_REMATCH[0]}"}"
  done
  return 0
}

_evd_refuse() { # <rótulo> <recebido> <declarados> <motivo> <como declarar> — recusa ANTES de executar, rc 1
  printf 'maestro: recusado antes de executar (nada rodou, nenhum recibo gravado)\n  rótulo: %s\n  comando recebido: %s\n  comandos declarados: %s\n' \
    "$1" "$2" "${3:-(nenhum)}" >&2
  die validation "$4" "$5" 1
}

_evd_order_file() { # <proj> <n> → arquivo da ordem N, vazio se não existe
  local n3 f
  n3=$(printf '%03d' "$2")
  for f in "$1/.maestro/orders/$n3"-*.md "$1/.maestro/orders/$n3.md"; do
    [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  return 0
}

_evd_baseline_file() { # <proj> <n> → arquivo do baseline (irmão do registro order-state, ordem 050 fez igual com .validate)
  printf '%s.baseline' "$(maestro_order_state_file "$1" "$2")"
}

_evd_turno_fim() { # <arquivo.md> → valor do fim: do bloco ## Turno
  declare -f _turno_value >/dev/null 2>&1 || source "$REPO_DIR/lib/core-order-turno.sh"
  _turno_value "$1" fim
}

_evd_gate_order() { # <proj> <rótulo> <n> <comando...>
  local proj="$1" label="$2" n="$3" of bf sha rel bfim wfim decl why
  shift 3
  local hint="o fim: da ordem é decisão do Diretor — ele edita o fim:, commita e roda: maestro order --baseline $n"
  of=$(_evd_order_file "$proj" "$n")
  [[ -n "$of" ]] || _evd_refuse "$label" "$*" "" "a ordem $n não existe neste projeto (inexistente)" "$hint"
  bf=$(_evd_baseline_file "$proj" "$n")
  sha=$(awk -F= '$1 == "fim_commit" { print $2; exit }' "$bf" 2>/dev/null) || sha=""
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || _evd_refuse "$label" "$*" "" \
    "a ordem $n não tem fim_commit (baseline do fim:) — fecha para negado" "$hint"
  rel="${of#"$proj"/}"
  bfim=$(_evd_turno_fim <(git -C "$proj" show "$sha:$rel" 2>/dev/null))
  [[ -n "$bfim" ]] || _evd_refuse "$label" "$*" "" \
    "o commit-base da ordem $n não tem fim: no bloco ## Turno" "$hint"
  wfim=$(_evd_turno_fim "$of")
  if [[ "$(printf '%s' "$bfim" | tr -s ' \t' ' ')" != "$(printf '%s' "$wfim" | tr -s ' \t' ' ')" ]]; then
    if [[ -n "$(git -C "$proj" status --porcelain -- "$rel" 2>/dev/null)" ]]; then
      why="o fim: da ordem $n está editado na árvore e NÃO commitado — só vale o fim: do commit-base"
    else
      why="o fim: da ordem $n mudou em commit depois do baseline — só vale o fim: do commit-base"
    fi
    _evd_refuse "$label" "$*" "$(_evd_fim_cmds "$bfim")" "$why" "$hint"
  fi
  decl=$(_evd_fim_cmds "$bfim")
  [[ -n "$decl" ]] || _evd_refuse "$label" "$*" "" \
    "o fim: da ordem $n não declara comando entre crases (\`…\`) — o texto fora das crases é prosa" "$hint"
  while IFS= read -r why; do
    _evd_words_equal "$why" "$@" && return 0
    _evd_bashc_equal "$why" "$@" && return 0
  done <<<"$decl"
  _evd_refuse "$label" "$*" "$decl" "comando diferente dos declarados no fim: da ordem $n" \
    "$hint; o declarado composto (&&, ;, |) vale como bash -c '<texto>' com o texto exato"
}

_evd_area_decl() { # <proj> <rótulo> → commands.<rótulo> do .maestro.yaml COMMITADO (fim_commit da ordem N em `área-N`, senão HEAD)
  # O run edita a árvore de trabalho: o que vale é o commit. Sem repo/commit, lê a árvore (degrada para hoje).
  local proj="$1" label="$2" ref="" bf d td
  if [[ "$label" =~ ^.+-([0-9]{1,3})$ ]]; then
    bf=$(_evd_baseline_file "$proj" "$((10#${BASH_REMATCH[1]}))")
    ref=$(awk -F= '$1 == "fim_commit" { print $2; exit }' "$bf" 2>/dev/null) || ref=""
    [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || ref=""
  fi
  [[ -n "$ref" ]] || ref=$(git -C "$proj" rev-parse --verify --quiet HEAD 2>/dev/null) || ref=""
  if [[ -z "$ref" ]]; then _ev_decl "$proj" "$label"; return 0; fi
  td=$(mktemp -d "${TMPDIR:-/tmp}/maestro-evd.XXXXXX" 2>/dev/null) || return 0
  if git -C "$proj" show "$ref:.maestro.yaml" >"$td/.maestro.yaml" 2>/dev/null; then
    d=$(_ev_decl "$td" "$label")
    # edição não commitada no .maestro.yaml (árvore ≠ commit): o declarado da árvore não vale
    [[ "$ref" == "$(git -C "$proj" rev-parse --verify --quiet HEAD 2>/dev/null)" ]] \
      && ! git -C "$proj" diff --quiet HEAD -- .maestro.yaml 2>/dev/null && d=""
    printf '%s' "$d"
  fi
  rm -rf "$td" 2>/dev/null
  return 0
}

_evd_yaml_gate() { # <proj> <oid> — --accept: recusa se o .maestro.yaml mudou entre o fim_commit da ordem e o tip
  # Rótulo de área sem sufixo (`suite`) lê o yaml do HEAD: o run poderia commitar um yaml próprio e provar com ele.
  # Ordem sem fim_commit (criada antes do baseline): nada a comparar, passa — o recibo order-N dela já é recusado.
  local proj="$1" oid="$2" n bf sha
  n=$((10#$oid)); bf=$(_evd_baseline_file "$proj" "$n")
  sha=$(awk -F= '$1 == "fim_commit" { print $2; exit }' "$bf" 2>/dev/null) || sha=""
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 0
  git -C "$proj" cat-file -e "$sha^{commit}" 2>/dev/null \
    || die validation "ordem $oid: o fim_commit (${sha:0:12}) não existe neste repositório — não dá para comparar o .maestro.yaml" \
         "o Diretor re-despacha a ordem (regrava o baseline)" 1
  git -C "$proj" diff --quiet "$sha" HEAD -- .maestro.yaml 2>/dev/null && return 0
  die validation "ordem $oid: o .maestro.yaml mudou entre o fim_commit (${sha:0:12}) e o tip — o comando de área da prova pode ser do run" \
    "o Diretor confere o diff (git diff ${sha:0:12} HEAD -- .maestro.yaml) e re-despacha para regravar o baseline" 1
}

_evd_gate_area() { # <proj> <rótulo> <comando...>
  local proj="$1" label="$2" decl base is_area=0
  shift 2
  [[ "$label" =~ ^(suite|tenant-isolation|billing|frontend)(-[0-9]{1,3})?$ ]] && is_area=1
  _verif_lib_load   # ordem 011: maestro_verif_load não é mais residente
  maestro_verif_load
  decl=$(_evd_area_decl "$proj" "$label")
  (( is_area == 0 )) && [[ -z "$decl" ]] && return 0   # rótulo livre: como hoje
  base="$label"; [[ "$label" =~ ^(.+)-[0-9]{1,3}$ ]] && base="${BASH_REMATCH[1]}"
  local hint="a declaração é decisão do Diretor — commands.$base no .maestro.yaml"
  [[ -n "$decl" ]] || _evd_refuse "$label" "$*" "" \
    "o rótulo de área $label não tem commands.$base no .maestro.yaml — fecha para negado" "$hint"
  _evd_words_equal "$decl" "$@" && return 0
  _evd_refuse "$label" "$*" "commands.$base: $decl" "comando diferente do declarado em commands.$base" "$hint"
}

_evd_gate() { # <proj> <rótulo> <comando...> → rc 0 libera a execução; recusa morre (rc 1) antes de executar
  local proj="$1" label="$2"
  shift 2
  if [[ "$label" =~ ^order-([0-9]{1,9})(-[0-9a-f]{8})?$ ]]; then
    _evd_gate_order "$proj" "$label" "$((10#${BASH_REMATCH[1]}))" "$@"
    return 0
  fi
  _evd_gate_area "$proj" "$label" "$@"
}

# ------------------------------------------------ maestro order --baseline N (grava o fim_commit)
_order_baseline() { # <proj> <arquivo da ordem> <oid NNN> — baseline = HEAD, com o arquivo da ordem commitado e limpo
  local proj="$1" of="$2" oid="$3" n bf sha rel prev tmp
  n=$((10#$oid)); rel="${of#"$proj"/}"
  git -C "$proj" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 \
    || die validation "o arquivo da ordem $oid não está commitado" "commite a ordem (chore(order)) e rode de novo" 1
  [[ -z "$(git -C "$proj" status --porcelain -- "$rel" 2>/dev/null)" ]] \
    || die validation "o arquivo da ordem $oid tem edição não commitada" "commite o fim: que vale e rode de novo" 1
  sha=$(git -C "$proj" rev-parse --verify --quiet HEAD 2>/dev/null) \
    || die validation "sem commit para ser o baseline" "commite a ordem primeiro" 1
  bf=$(_evd_baseline_file "$proj" "$n")
  prev=$(awk -F= '$1 == "fim_commit" { print $2; exit }' "$bf" 2>/dev/null) || prev=""
  [[ -z "$prev" ]] || die validation "a ordem $oid já tem baseline (fim_commit=${prev:0:12}) — não se sobrescreve" \
    "re-despache a ordem (o Diretor apaga o registro $bf e roda --baseline de novo)" 1
  mkdir -p "${bf%/*}" 2>/dev/null || die env "não consigo criar ${bf%/*}" "cheque permissões/MAESTRO_HOME" 2
  tmp="$bf.tmp.$$"
  { printf 'schema=maestro-order-baseline-v1\nid=%s\nfim_commit=%s\n' "$n" "$sha"; } > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$bf" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; die env "falha ao gravar o baseline da ordem $oid" "cheque permissões/MAESTRO_HOME" 2; }
  printf 'baseline da ordem %s gravado: fim_commit=%s%s\n' "$oid" "${sha:0:12}" "${prev:+ (antes: ${prev:0:12})}"
  [[ -n "$(_evd_fim_cmds "$(_evd_turno_fim "$of")")" ]] \
    || printf '  AVISO: o fim: não declara comando entre crases — order-%s seguirá recusado até declarar\n' "$n"
  return 0
}
_order_baseline_cmd() { # --baseline N [--project p] [--session s] — a ordem N precisa estar commitada e limpa
  local oid="" proj="${CLAUDE_PROJECT_DIR:-$PWD}" of
  while (( $# )); do
    case "$1" in
      --baseline) oid="${2:-}"; shift ;;
      --project)  proj="${2:-}"; shift ;;
      --session)  shift ;;
      *) die validation "flag desconhecida '$1'" "maestro order --baseline N [--project p]" 1 ;;
    esac
    shift
  done
  [[ "$oid" =~ ^[0-9]{1,3}$ ]] || die validation "id de ordem inválido" "use o NNN do maestro order --list" 1
  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  oid=$(printf '%03d' "$((10#$oid))")
  of=$(_evd_order_file "$proj" "$((10#$oid))")
  [[ -n "$of" ]] || die validation "ordem $oid não existe" "maestro order --list" 1
  _order_baseline "$proj" "$of" "$oid"
}
