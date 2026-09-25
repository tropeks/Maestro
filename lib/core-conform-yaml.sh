#!/usr/bin/env bash
# maestro lib/core-conform-yaml.sh — ordem 042, família (b) de `maestro conform --check`.
#
# Reusa o parser de `.maestro.yaml` que já existe — `maestro_verif_areas`/
# `maestro_verif_cmd` (hooks/lib/verifications.sh, via `_verif_lib_load` +
# `maestro_verif_load`) — nunca um segundo parser de `verifications:`/
# `commands:`. A única leitura NOVA é a chave `lab:` (DATA_MODEL, emenda
# desta ordem), no MESMO estilo raso de `_docs_declared_list`
# (lib/cmd-docs.sh): lista em flow, uma linha, sem suporte a bloco `- item`.
#
# Sourced por lib/cmd-conform.sh — REPO_DIR/die() já no escopo (bin/maestro).
# `_cf_area`/`_cf_labels`/`_cf_cmd`/`_cf_lab` são globais do MÓDULO (molde
# EV_RUN_*/RETRO_*): _conform_check_yaml as zera a cada chamada, e as duas
# funções internas só se falam por elas — nunca por parâmetro extra.

# `-g`: este módulo é sourceado DE DENTRO de uma função (_conform_core_lib_load,
# lib/cmd-conform.sh) — sem `-g`, `declare -A/-a` no topo do arquivo vira LOCAL
# do CARREGADOR, não global do módulo (armadilha registrada na ordem 015,
# lib/core-order-state.sh). `_conform_check_yaml` zera os cinco a cada chamada.
declare -ga _cf_area_name=() _cf_area_labels=() _cf_label_order=()
declare -gA _cf_cmd=() _cf_lab=()

# `lab: [rótulo, …]` — mesmo padrão raso de `docs:` (lib/cmd-docs.sh,
# `_docs_declared_list`): flow numa linha só, vírgula ou espaço, aspas e
# comentário removidos. Bloco `- item` não é suportado (config, não YAML completo).
_conform_yaml_lab_list() { # <proj> → rótulos marcados como lab, um por linha
  local proj="$1" yaml
  yaml="$proj/.maestro.yaml"
  [[ -f "$yaml" ]] || return 0
  awk '/^lab:/ { sub(/^lab:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit }' "$yaml" 2>/dev/null \
    | tr -d '[]"'"'" | tr ',' ' ' | tr ' ' '\n' | grep -v '^[ \t]*$'
  return 0
}

# comando "parece lab" — casa docker, compose ou --context lab, ignorando o
# resto do texto do comando (o comando pode ter mais partes além disso).
_conform_yaml_cmd_is_lab() { # <comando>
  [[ "$1" == *docker* || "$1" == *compose* || "$1" == *"--context lab"* ]]
}

# Popula _cf_area_name/_cf_area_labels/_cf_label_order/_cf_cmd/_cf_lab a
# partir de `maestro_verif_areas` + `maestro_verif_cmd` + `lab:` — sem
# imprimir nada (a impressão é de quem chama, por responsabilidade própria).
_conform_yaml_index() { # <proj> <areas-tsv>
  local proj="$1" areas="$2" name paths labels lb cmd lab_list
  lab_list=" $(_conform_yaml_lab_list "$proj" | tr '\n' ' ') "
  declare -A seen=()
  while IFS=$'\t' read -r name paths labels; do
    [[ -n "$name" ]] || continue
    : "$paths"
    _cf_area_name+=("$name"); _cf_area_labels+=("$labels")
    for lb in $labels; do
      [[ -n "${seen[$lb]:-}" ]] && continue
      seen[$lb]=1; _cf_label_order+=("$lb")
    done
  done <<<"$areas"

  for lb in "${_cf_label_order[@]}"; do
    cmd=$(maestro_verif_cmd "$proj" "$lb") || cmd=""
    _cf_cmd[$lb]="$cmd"
    [[ -z "$cmd" ]] && continue
    if _conform_yaml_cmd_is_lab "$cmd"; then
      _cf_lab[$lb]=1
    elif [[ "$lab_list" == *" $lb "* ]]; then
      _cf_lab[$lb]=1
    fi
  done
  return 0
}

_conform_check_yaml() { # <proj> → TSV de lacunas da família (b) .maestro.yaml
  local proj="$1" yaml
  yaml="$proj/.maestro.yaml"
  if [[ ! -f "$yaml" ]]; then
    printf '2\tyaml-missing\t.maestro.yaml\tcrie .maestro.yaml com verifications:/commands: (docs/architecture/DATA_MODEL.md §2)\n'
    return 0
  fi

  _verif_lib_load; maestro_verif_load
  local areas; areas=$(maestro_verif_areas "$proj") || areas=""
  if [[ -z "$areas" ]]; then
    printf '2\tyaml-no-verifications\t.maestro.yaml\tdeclare pelo menos uma área em verifications: com paths: e labels:\n'
    return 0
  fi

  _cf_area_name=(); _cf_area_labels=(); _cf_label_order=(); _cf_cmd=(); _cf_lab=()
  _conform_yaml_index "$proj" "$areas"

  local lab_list; lab_list=" $(_conform_yaml_lab_list "$proj" | tr '\n' ' ') "
  local lb
  for lb in "${_cf_label_order[@]}"; do
    if [[ -z "${_cf_cmd[$lb]}" ]]; then
      printf '2\tyaml-label-no-command\t%s\tdeclare commands.%s: <comando> no .maestro.yaml\n' "$lb" "$lb"
      continue
    fi
    if _conform_yaml_cmd_is_lab "${_cf_cmd[$lb]}" && [[ "$lab_list" != *" $lb "* ]]; then
      printf '2\tyaml-lab-unmarked\t%s\tadicione "%s" à chave lab: do .maestro.yaml (o comando roda em docker/compose/--context lab)\n' "$lb" "$lb"
    fi
  done

  local i area labels all_lab
  for i in "${!_cf_area_name[@]}"; do
    area="${_cf_area_name[$i]}"; labels="${_cf_area_labels[$i]}"
    [[ -n "$labels" ]] || continue
    all_lab=1
    for lb in $labels; do
      [[ -n "${_cf_lab[$lb]:-}" ]] || { all_lab=0; break; }
    done
    if (( all_lab == 1 )); then
      printf '2\tyaml-lab-only-area\t%s\tárea "%s" só tem prova em lab — adicione um rótulo headless (sem docker/compose/--context lab) ou mova a prova para fora da lab\n' "$area" "$area"
    fi
  done
  return 0
}
