#!/usr/bin/env bash
# maestro hooks/user-prompt-submit.sh — evento UserPromptSubmit (S-205 / ADR-008)
#
# PROPÓSITO: produzir a MÉTRICA PRINCIPAL do projeto. Prompt que começa com `/`
# é invocação manual de comando de workflow — o oposto do roteamento automático.
# Cada um vira uma linha `override_manual` no JSONL; `maestro log --summary`
# divide por sessão e sai o "% de override manual" (brief, Baseline & Measurement).
#
# REGRAS DURAS (API_SPEC §1 + ADR-008 + brief §7/§10):
#  1. SEMPRE exit 0. Nunca altera o prompt, nunca bloqueia.
#  2. NADA em stdout, jamais: no UserPromptSubmit o stdout do hook é INJETADO no
#     contexto do Claude. Garantido estruturalmente por `exec 1>&2` abaixo.
#  3. O prompt é o dado mais sensível do sistema (pode conter credencial, caminho
#     de cliente, texto privado). Tratado como radioativo: o `jq` extrai o NOME do
#     comando e já devolve só isso — o texto do prompt nunca chega a uma variável
#     do shell, nunca é interpolado, nunca vai ao log. Nada além de
#     `^[a-z0-9:_-]{1,48}$` (o tipo `cmd` do log_event) pode ser logado; token que
#     não casa é DESCARTADO (o par some), nunca truncado/normalizado à força.
#  4. Degrada com exit 0 em: kill-switch, `jq` ausente, stdin vazio/malformado,
#     falha do log.
#
# Bash puro. Sem Bun, sem src/, sem rede. Um único fork (`jq`) no caminho quente.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
if ! source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null; then
  exit 0 # sem a lib não há o que logar — degrada em silêncio
fi
maestro_killswitch

# Regra 2, aplicada de uma vez para todo o resto do script: qualquer escrita em
# stdout (inclusive de uma edição futura distraída) cai no stderr, que o Claude
# Code NÃO injeta no contexto.
exec 1>&2

# stdin é terminal → não há JSON de hook para ler; não trava esperando.
if [[ -t 0 ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Programa jq: lê o payload do hook e emite EXATAMENTE 3 linhas, todas já
# sanitizadas na origem (o prompt não sai daqui):
#   1. session_id, ou vazio se ausente/fora do tipo
#   2. "1" se o prompt começa com `/` (houve override manual), senão "0"
#   3. nome do comando, ou vazio se não casar com o tipo `cmd`
# `?` + `// ""` + `s` blindam contra payload que não é objeto, prompt que não é
# string (JSON aninhado) e campos ausentes.
# O token do comando vai da barra até o PRIMEIRO espaço em branco (nunca até a
# próxima `/`: `/home/rcosta00/x.py` tem de ser rejeitado inteiro, e não virar
# `cmd=home`). O delimitador final `(?:[[:space:]]|$)` é obrigatório de propósito:
# sem ele um token de 49+ chars seria TRUNCADO em 48 e viraria log — trecho de
# prompt vazando. Sem delimitador, sem match, par descartado.
_MAESTRO_JQ='def s: if type=="string" then . else "" end;
(.session_id? // "" | s | if test("^[A-Za-z0-9_-]{1,64}$") then . else "" end),
(.prompt? // "" | s | if startswith("/") then "1" else "0" end),
(.prompt? // "" | s
   | [capture("^/(?<c>[^[:space:]]{1,48})(?:[[:space:]]|$)")]
   | if length > 0 then .[0].c else "" end
   | if test("^[a-z0-9:_-]{1,48}$") then . else "" end)'

# jq lê o stdin direto (um fork só). Stdin vazio → saída vazia; JSON malformado
# → rc≠0 e stderr suprimido: em ambos os casos `out` fica vazio e o hook sai 0.
out=""
out=$(jq -r "$_MAESTRO_JQ" 2>/dev/null) || out=""
[[ -n "$out" ]] || exit 0

# Três `read` em vez de `mapfile`: bash 3.2 (macOS) não tem mapfile, e o restante
# do código já tem fallbacks BSD. O grupo é LHS de `||` → errexit não dispara.
sid=""; is_slash=""; cmd=""
{ IFS= read -r sid; IFS= read -r is_slash; IFS= read -r cmd; } <<<"$out" || :

# Não começa com `/` → prompt normal, roteamento automático: não é evento nosso.
if [[ "$is_slash" != "1" ]]; then
  exit 0
fi

# Cinto e suspensório: revalida no shell o que o jq já filtrou. Se qualquer coisa
# escapar (regex trocada numa edição futura, jq de outra versão), o par é
# descartado aqui — o evento ainda conta para a métrica, sem o nome do comando.
if [[ ! "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then sid=""; fi
if [[ ! "$cmd" =~ ^[a-z0-9:_-]{1,48}$ ]]; then cmd=""; fi

pairs=()
if [[ -n "$sid" ]]; then pairs+=("session_id=$sid"); fi
if [[ -n "$cmd" ]]; then pairs+=("cmd=$cmd"); fi

# log_event nunca aborta o chamador e sempre retorna 0 (CONTRATO §1).
log_event override_manual ${pairs[@]+"${pairs[@]}"}

exit 0
