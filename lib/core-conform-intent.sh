#!/usr/bin/env bash
# maestro lib/core-conform-intent.sh — ordem 042, família (a) de `maestro conform --check`.
#
# NÃO reimplementa o formato do INTENT: chama `_intent_lib_load` (bin/maestro,
# I-2) e usa `_intent_file`/`_intent_version`/`_intent_missing`/
# `_intent_body_hash`/`_intent_stamp_field` de lib/core-intent.sh — a MESMA
# leitura que `maestro intent --check` faz. Este módulo só decide QUAIS
# lacunas essas leituras significam para o conform, nunca recalcula a forma
# do carimbo ou das seções.
#
# Sourced por lib/cmd-conform.sh (_conform_core_lib_load), dentro do mesmo
# processo — REPO_DIR, die() e _intent_lib_load já no escopo (bin/maestro).
#
# Saída de _conform_check_intent: uma linha "1<TAB>código<TAB>alvo<TAB>fix"
# por lacuna encontrada — a família (1) é o índice de ORDENAÇÃO estável que
# lib/cmd-conform.sh usa para intercalar as seis famílias; o nome amigável
# ("intent") só existe do lado de fora (_CONFORM_FAMILIA_NOME).

_conform_check_intent() { # <proj> → TSV de lacunas da família (a) INTENT
  local proj="$1" f ver stamped body_hash miss
  _intent_lib_load   # core-intent.sh: _intent_file/_intent_version/_intent_missing/_intent_body_hash/_intent_stamp_field
  f=$(_intent_file "$proj")

  if [[ ! -f "$f" || ! -r "$f" ]]; then
    printf '1\tintent-missing\t.maestro/INTENT.md\trode "maestro intent --init" e preencha as seis seções\n'
    return 0
  fi

  ver=$(_intent_version "$f")
  if [[ -z "$ver" ]]; then
    printf '1\tintent-missing\t.maestro/INTENT.md\tcarimbo ilegível — reconstrua o cabeçalho `<!-- maestro-intent v1` (maestro intent --check)\n'
    return 0
  fi

  miss=$(_intent_missing "$f")
  if [[ -n "$miss" ]]; then
    printf '1\tintent-sections\t.maestro/INTENT.md\tpreencha as seções vazias/ausentes: %s\n' "$miss"
  fi

  stamped=$(_intent_stamp_field "$f" hash)
  body_hash=$(_intent_body_hash "$f")
  if [[ -n "$stamped" && -n "$body_hash" && "$stamped" != "$body_hash" ]]; then
    printf '1\tintent-hash\t.maestro/INTENT.md\tconteúdo mudou desde o carimbo — rode "maestro intent --bump"\n'
  fi
  return 0
}
