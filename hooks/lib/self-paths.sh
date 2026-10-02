#!/usr/bin/env bash
# maestro hooks/lib/self-paths.sh — ordem 047 (INTENT v6 §Limites, ADR-003 v1.2).
#
# A autoproteção do gate só interceptava Write/Edit. Bash e interpretadores
# escreviam em `self_paths` sem barreira (reproduzido: `echo x > lib/a.sh`,
# `sed -i … bin/maestro`, `python3 -c "open('lib/x','w')…"` saíam rc 0).
# Este módulo é o critério LÉXICO que o pre-bash-guard usa para fechar o
# caminho: o comando tem uma FORMA DE ESCRITA e o alvo dela é um caminho de
# `self_paths`. Sem classificar intenção, sem executar nada.
#
# FONTE ÚNICA da lista: a MESMA política compilada que o pre-tool-gate lê
# ($MAESTRO_GATE_POLICY ou $MAESTRO_HOME/gate-policy.sh — MAESTRO_GATE_DENY_SELF
# e MAESTRO_PLUGIN_ROOT); ausente, o fallback embutido (o MESMO do session-start,
# com `lib/`). Âncora: raiz do plugin OU qualquer worktree do mesmo repo (a
# ordem 043: `.git` de worktree aponta o common-dir). Tudo em builtin — zero
# fork no caminho comum (NFR do guard, 50 ms).
#
# LIMITES DECLARADOS (honra, não trilho — ENGINEERING_SPEC): script gravado fora
# de self_paths e depois executado; `git apply` de patch que toca self_paths;
# `eval`; variável montando o caminho; `cd lib && echo x > a.sh`; symlink; escrita
# por ferramenta que a lista abaixo não conhece.
#
# Sourced por hooks/pre-bash-guard.sh só quando o comando menciona uma raiz.

SP_FALLBACK="agents/ bin/ src/ hooks/ lib/ config/routing-table.yaml config/accept-proof.pub .claude-plugin/"
SP_DENY=""; SP_ROOT=""; SP_CWD=""; SP_N=""; SP_R=""

_sp_load() { # <raiz-do-hook> → carrega SP_DENY/SP_ROOT da política compilada; fallback embutido
  local pol="${MAESTRO_GATE_POLICY:-${MAESTRO_HOME:-$HOME/.maestro}/gate-policy.sh}"
  local MAESTRO_GATE_DENY_SELF="" MAESTRO_PLUGIN_ROOT=""
  [[ -r "$pol" ]] && { source "$pol" 2>/dev/null || :; }
  SP_DENY="${MAESTRO_GATE_DENY_SELF:-$SP_FALLBACK}"
  SP_ROOT="${MAESTRO_PLUGIN_ROOT:-$1}"
  SP_ROOT="${SP_ROOT%/}"
}

_sp_norm() { # <caminho absoluto> → SP_N sem `.`/`..`/`//` (sem fork)
  local p="$1"
  while [[ "$p" == *"//"* ]]; do p="${p//\/\//\/}"; done
  while [[ "$p" == *"/./"* ]]; do p="${p//\/.\//\/}"; done
  while [[ "$p" =~ ^(.*)/[^/.][^/]*/\.\.(/.*)?$ ]]; do p="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; done
  SP_N="${p%/.}"
}

_sp_family_root() { # <abs> → rc 0 e SP_R = raiz do plugin ou do worktree dele que contém <abs>
  local abs="$1" d gl gd n=0
  SP_R=""
  [[ -n "$SP_ROOT" ]] || return 1
  if [[ "$abs" == "$SP_ROOT"/* ]]; then SP_R="$SP_ROOT"; return 0; fi
  d="${abs%/*}"
  while [[ -n "$d" && $n -lt 16 ]]; do
    if [[ -f "$d/.git" ]]; then
      read -r gl < "$d/.git" || return 1
      gd="${gl#gitdir: }"
      [[ "${gd%/.git/worktrees/*}" == "$SP_ROOT" ]] && { SP_R="$d"; return 0; }
      return 1
    fi
    [[ -d "$d/.git" ]] && return 1
    d="${d%/*}"; n=$((n + 1))
  done
  return 1
}

_sp_is_self() { # <palavra> → rc 0 se é caminho em self_paths (relativo ao cwd, absoluto ou ~)
  local w="${1#./}" abs rel e
  [[ -n "$w" ]] || return 1
  case "$w" in
    /*) abs="$w" ;;
    "~"/*) abs="$HOME/${w#"~"/}" ;;
    *) [[ -n "$SP_CWD" ]] || return 1; abs="$SP_CWD/$w" ;;
  esac
  _sp_norm "$abs"; abs="$SP_N"
  _sp_family_root "$abs" || return 1
  rel="${abs#"$SP_R"/}"
  for e in $SP_DENY; do
    if [[ "$e" == */ ]]; then [[ "$rel/" == "$e"* ]] && return 0
    else [[ "$rel" == "$e" ]] && return 0
    fi
  done
  return 1
}

_sp_any_self() { # <palavras…> → rc 0 se alguma é caminho em self_paths
  local w
  for w in "$@"; do _sp_is_self "$w" && return 0; done
  return 1
}

_sp_redirect_hit() { # <segmento> → rc 0 se algum alvo de `>` `>>` `&>` `>|` é self_path
  local rest="$1"
  local tgt
  while [[ "$rest" =~ (\>\>?|\&\>)[[:space:]]*([^[:space:]\<\>\|\&\;]+)(.*) ]]; do
    tgt="${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"   # antes: _sp_is_self reescreve BASH_REMATCH
    _sp_is_self "$tgt" && return 0
  done
  return 1
}

_sp_dest_hit() { # cp/install/ln: só o DESTINO conta (último não-opção, ou -t/--target-directory)
  local dest="" tdir="" w next=0
  for w in "$@"; do
    if (( next )); then tdir="$w"; next=0; continue; fi
    case "$w" in
      -t) next=1 ;;
      --target-directory=*) tdir="${w#*=}" ;;
      -*) ;;
      *) dest="$w" ;;
    esac
  done
  dest="${tdir:-$dest}"
  [[ -n "$dest" ]] && _sp_is_self "$dest"
}

_sp_interp_hit() { # interpretador: qualquer caminho de self_paths em qualquer posição
  local t="$1" w
  t="${t//[^A-Za-z0-9_.\/~+-]/ }"
  for w in $t; do _sp_is_self "$w" && return 0; done
  return 1
}

_sp_inplace() { # sed: alguma palavra é -i, -i.bak, -ni, -Ei ou --in-place (palavra inteira, nunca o script)
  local w
  for w in "$@"; do
    [[ "$w" == --in-place* || "$w" =~ ^-[a-zA-Z]*i ]] && return 0
  done
  return 1
}

_sp_seg_hit() { # <segmento> → rc 0 se o segmento escreve em self_paths
  local seg="$1" w=() i first="" base args=()
  _sp_redirect_hit "$seg" && return 0
  read -ra w <<<"$seg"
  for i in "${!w[@]}"; do
    case "${w[i]}" in
      *=*|sudo|env|nohup|command|time|exec) ;;
      *) first="${w[i]}"; args=("${w[@]:i+1}"); break ;;
    esac
  done
  base="${first##*/}"
  case "$base" in
    tee|mv|truncate) _sp_any_self "${args[@]}" ;;
    cp|install|ln) _sp_dest_hit "${args[@]}" ;;
    dd) for i in "${args[@]}"; do [[ "$i" == of=* ]] && _sp_is_self "${i#of=}" && return 0; done; return 1 ;;
    sed|gsed) _sp_inplace "${args[@]}" && _sp_any_self "${args[@]}" ;;
    python|python[0-9]*|node|nodejs|ruby|perl) _sp_interp_hit "$seg" ;;
    *) return 1 ;;
  esac
}

maestro_bash_self_write() { # <comando achatado> <cwd> <raiz-do-hook> → rc 0 se ESCREVE em self_paths (publica SP_N)
  local flat="$1" seg segs=()
  SP_CWD="${2%/}"
  _sp_load "$3"
  flat="${flat//>|/>}"   # `>|` é redirecionamento (força sobrescrita), não pipe
  flat="${flat//&&/;}"; flat="${flat//||/;}"; flat="${flat//|/;}"
  local IFS=';'
  read -ra segs <<<"$flat"
  IFS=$' \t\n'
  for seg in "${segs[@]}"; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [[ -n "$seg" ]] && _sp_seg_hit "$seg" && return 0
  done
  return 1
}

maestro_bash_self_message() { # <sid> — mensagem instrutiva do bloqueio (printf builtin, sem kill-switch na mensagem)
  printf '%s\n' >&2 \
    "maestro: comando bloqueado — escreve em caminho protegido pela autoproteção do Maestro (ADR-003, ordem 047)." \
    "Roteador, roster, gate, CLI, lib/ e configs executáveis não são reescritos por agente — nem por" \
    "Bash, tee, sed -i, cp, mv ou python/node. A regra vale com decisão registrada e em qualquer modo." \
    "Faça assim: edite num CLONE fora do repo do plugin (git clone --no-hardlinks), gere o diff" \
    "como docs/patches/NNN-*.patch e peça ao humano responsável que o aplique com um git apply."
}
