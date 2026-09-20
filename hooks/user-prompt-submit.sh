#!/usr/bin/env bash
# maestro hooks/user-prompt-submit.sh — evento UserPromptSubmit (S-205 / ADR-008)
#
# PROPÓSITO: produzir a MÉTRICA PRINCIPAL do projeto. Prompt que começa com `/`
# é invocação manual de comando de workflow — o oposto do roteamento automático.
# Cada um vira uma linha `override_manual` no JSONL; `maestro log --summary`
# divide por sessão e sai o "% de override manual" (brief, Baseline & Measurement).
#
# ordem 030 — SENSOR DE CORREÇÃO DE ROTA (`route_fix`, INTENT v3 "zero correção
# manual do modo/modelo escolhido"). Mecânico, não classificador: só conta se
# (a) já existe decision record válido NESTA sessão (âncora — mata de graça a
# maior fonte de falso positivo) e (b) o prompt cita, em vocabulário FECHADO
# (o MESMO enum de mode/workflow/agents do log_event), um valor que DIFERE do
# gravado no record. Menção sem contradição não emite nada. Ver bloco
# "route_fix" mais abaixo.
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
#     não casa é DESCARTADO (o par some), nunca truncado/normalizado à força. A
#     detecção de `route_fix` segue a MESMA regra: o jq só devolve o TOKEN do
#     enum que casou (ex.: "subagent"), nunca um trecho do prompt — jamais a
#     frase, jamais hash que permita reconstruir.
#  4. Degrada com exit 0 em: kill-switch, `jq` ausente, stdin vazio/malformado,
#     falha do log, roster ilegível, record ilegível/corrompido.
#
# Bash puro. Sem Bun, sem src/, sem rede.

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

# E21/S-2101 — o humano respondeu: o gate deste pane deixa de estar pendente.
# Apaga o arquivo que o Stop hook deixou para o forwarder e libera a autoridade
# de estado no herdr (best-effort, 2s). Um teste de arquivo por prompt; fora do
# herdr, nada.
if [[ "${HERDR_ENV:-}" == "1" && "${HERDR_PANE_ID:-}" =~ ^[A-Za-z0-9:_-]{1,32}$ ]]; then
  _gate_file="$MAESTRO_HOME/herdr/gates/${HERDR_PANE_ID//:/_}"
  if [[ -f "$_gate_file" ]]; then
    rm -f -- "$_gate_file" 2>/dev/null || :
    _hb="${HERDR_BIN_PATH:-herdr}"
    if command -v "$_hb" >/dev/null 2>&1 || [[ -x "$_hb" ]]; then
      if command -v timeout >/dev/null 2>&1; then
        timeout 2 "$_hb" pane release-agent "$HERDR_PANE_ID" --source custom:maestro --agent claude \
          --seq "$(date +%s%N 2>/dev/null || date +%s)" >/dev/null 2>&1 || :
      else
        "$_hb" pane release-agent "$HERDR_PANE_ID" --source custom:maestro --agent claude \
          --seq "$(date +%s%N 2>/dev/null || date +%s)" >/dev/null 2>&1 || :
      fi
    fi
  fi
fi

# stdin é terminal → não há JSON de hook para ler; não trava esperando.
if [[ -t 0 ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Roster (nomes de agents/*.md) para a detecção do eixo `agents` do route_fix.
# Só nomes de ARQUIVO (nunca conteúdo) e só o que já casa `^[a-z0-9-]+$` — o
# mesmo tipo `agents` do log_event. Ausência/diretório ilegível → lista vazia,
# que apenas desliga essa parte da detecção (degrada mudo, nunca quebra).
# `${SCRIPT_DIR%/*}` em vez de `$(cd .. && pwd)`: SCRIPT_DIR já é absoluto e
# canônico (fork pago uma vez lá em cima); um segundo fork só para subir um
# nível seria pagar de novo por algo que manipulação de string resolve de
# graça — medido: ~5ms/chamada no caminho quente (ver relato da ordem 030).
REPO_DIR="${SCRIPT_DIR%/*}"
AGENTS_DIR="${MAESTRO_AGENTS_DIR:-$REPO_DIR/agents}"
_maestro_roster_json='[]'
if [[ -d "$AGENTS_DIR" ]]; then
  shopt -s nullglob
  _roster_files=("$AGENTS_DIR"/*.md)
  shopt -u nullglob
  _roster_csv=""
  for _rf in "${_roster_files[@]}"; do
    _rn="${_rf##*/}"; _rn="${_rn%.md}"
    [[ "$_rn" =~ ^[a-z0-9-]+$ ]] || continue
    _roster_csv+="\"$_rn\","
  done
  [[ -n "$_roster_csv" ]] && _maestro_roster_json="[${_roster_csv%,}]"
fi

# Programa jq: lê o payload do hook e emite EXATAMENTE 7 linhas, todas já
# sanitizadas na origem (o prompt não sai daqui):
#   1. session_id, ou vazio se ausente/fora do tipo
#   2. "1" se o prompt começa com `/` (houve override manual), senão "0"
#   3. nome do comando, ou vazio se não casar com o tipo `cmd`
#   4. token de `mode` citado no prompt (direct/subagent/multi), ou vazio
#   5. token de `workflow` citado, ou vazio
#   6. nome de agente do roster citado, ou vazio
#   7. token de modelo citado (haiku/sonnet/opus), ou vazio
# `?` + `// ""` + `s` blindam contra payload que não é objeto, prompt que não é
# string (JSON aninhado) e campos ausentes.
# O token do comando vai da barra até o PRIMEIRO espaço em branco (nunca até a
# próxima `/`: `/home/rcosta00/x.py` tem de ser rejeitado inteiro, e não virar
# `cmd=home`). O delimitador final `(?:[[:space:]]|$)` é obrigatório de propósito:
# sem ele um token de 49+ chars seria TRUNCADO em 48 e viraria log — trecho de
# prompt vazando. Sem delimitador, sem match, par descartado.
# `onehit`: teste de PERTENCIMENTO por palavra inteira (`\b`), NUNCA
# classificador — os únicos alfabetos aceitos são os mesmos enums fechados do
# log_event. Alternação de literais curtos e `\b`, sem quantificador limitado
# (issue #42): medido, ver relato da ordem. Ambíguo (≥2 tokens distintos no
# mesmo prompt) → "" — "emita o que tiver certeza, ou não emita".
_MAESTRO_JQ='def s: if type=="string" then . else "" end;
def onehit(pl; lst): ([lst[] as $t | select(pl | test("\\b" + $t + "\\b")) | $t] | unique) as $m
  | if ($m | length) == 1 then $m[0] else "" end;
(.session_id? // "" | s) as $sid0 |
(.prompt? // "" | s) as $p |
($p | ascii_downcase) as $pl |
($sid0 | if test("^[A-Za-z0-9_-]{1,64}$") then . else "" end),
(if $p | startswith("/") then "1" else "0" end),
($p
   | [capture("^/(?<c>[^[:space:]]{1,48})(?:[[:space:]]|$)")]
   | if length > 0 then .[0].c else "" end
   | if test("^[a-z0-9:_-]{1,48}$") then . else "" end),
onehit($pl; ["direct","subagent","multi"]),
onehit($pl; ["fix","feature","refactor","ship","audit","verify","codereview","custom"]),
onehit($pl; $roster),
onehit($pl; ["haiku","sonnet","opus"])'

# jq lê o stdin direto (um fork só). Stdin vazio → saída vazia; JSON malformado
# → rc≠0 e stderr suprimido: em ambos os casos `out` fica vazio e o hook sai 0.
out=""
out=$(jq -r --argjson roster "$_maestro_roster_json" "$_MAESTRO_JQ" 2>/dev/null) || out=""
[[ -n "$out" ]] || exit 0

# Sete `read` em vez de `mapfile`: bash 3.2 (macOS) não tem mapfile, e o
# restante do código já tem fallbacks BSD. O grupo é LHS de `||` → errexit não
# dispara.
sid=""; is_slash=""; cmd=""; hit_mode=""; hit_wf=""; hit_agent=""; hit_model=""
{ IFS= read -r sid; IFS= read -r is_slash; IFS= read -r cmd
  IFS= read -r hit_mode; IFS= read -r hit_wf
  IFS= read -r hit_agent; IFS= read -r hit_model; } <<<"$out" || :

# Cinto e suspensório: revalida no shell o que o jq já filtrou. Se qualquer
# coisa escapar (regex trocada numa edição futura, jq de outra versão), o par
# é descartado aqui.
if [[ ! "$sid" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then sid=""; fi
if [[ ! "$hit_mode"  =~ ^(direct|subagent|multi)$ ]]; then hit_mode=""; fi
if [[ ! "$hit_wf"    =~ ^(fix|feature|refactor|ship|audit|verify|codereview|custom)$ ]]; then hit_wf=""; fi
if [[ ! "$hit_agent" =~ ^[a-z0-9-]+$ ]]; then hit_agent=""; fi
if [[ ! "$hit_model" =~ ^(haiku|sonnet|opus)$ ]]; then hit_model=""; fi

# Começa com `/` → invocação manual de comando: métrica de override existente.
if [[ "$is_slash" == "1" ]]; then
  if [[ ! "$cmd" =~ ^[a-z0-9:_-]{1,48}$ ]]; then cmd=""; fi
  pairs=()
  if [[ -n "$sid" ]]; then pairs+=("session_id=$sid"); fi
  if [[ -n "$cmd" ]]; then pairs+=("cmd=$cmd"); fi
  # log_event nunca aborta o chamador e sempre retorna 0 (CONTRATO §1).
  log_event override_manual ${pairs[@]+"${pairs[@]}"}
fi

# ---------------------------------------------------------------------------
# route_fix (ordem 030) — roda em TODO prompt, com `/` ou sem (a correção em
# linguagem natural, o próprio caso que motivou a ordem, nunca começa com `/`).
# ---------------------------------------------------------------------------
_maestro_route_fix_agent_model() { # <nome> → model do agents/<nome>.md, ou "" (≤10 linhas, sem fork)
  local name="$1" f line="" model="" n=0
  [[ "$name" =~ ^[a-z0-9-]+$ ]] || { printf ''; return 0; }
  f="$AGENTS_DIR/$name.md"
  [[ -f "$f" && -r "$f" ]] || { printf ''; return 0; }
  while IFS= read -r line && (( n < 10 )); do
    n=$(( n + 1 ))
    if [[ "$line" =~ ^model:[[:space:]]*(haiku|sonnet|opus)[[:space:]]*$ ]]; then
      model="${BASH_REMATCH[1]}"
      break
    fi
  done < "$f"
  printf '%s' "$model"
  return 0
}

# <agents do record, csv> <agente citado|""> <modelo citado|""> → rc=0 se
# eixo `agents` contradiz. Sem agents no record (mode direct) → sem âncora,
# rc=1 (mudo). "aceite a lista do record": a comparação é sempre contra os
# agentes JÁ decididos, nunca contra um vocabulário adivinhado.
_maestro_route_fix_agents_axis() {
  local csv="$1" ag="$2" mdl="$3" a am matched known
  [[ -n "$csv" ]] || return 1
  local -a arr=()
  local IFS=','
  for a in $csv; do arr+=("$a"); done
  unset IFS
  if [[ -n "$ag" ]]; then
    matched=0
    for a in "${arr[@]}"; do [[ "$a" == "$ag" ]] && matched=1; done
    (( matched == 1 )) || return 0
  fi
  if [[ -n "$mdl" ]]; then
    matched=0; known=0
    for a in "${arr[@]}"; do
      am=$(_maestro_route_fix_agent_model "$a")
      [[ -n "$am" ]] || continue
      known=1
      [[ "$am" == "$mdl" ]] && matched=1
    done
    # Roster ilegível para TODOS os agentes do record → nada se sabe do
    # modelo real: mudo, não inventa contradição.
    (( known == 1 )) && (( matched == 0 )) && return 0
  fi
  return 1
}

# <arquivo> → grava rec_workflow/rec_mode/rec_agents (globais, por convenção
# desta casa: NUNCA via $(...), que perderia as globais num subshell).
# O record é escrito via `JSON.stringify(record)` SEM indentação (src/cli.ts)
# — compacto, uma linha só — então dá para extrair por regex builtin, sem
# fork nenhum. NÃO decide validade (TTL): só LÊ. A validade continua sendo
# pré-condição do EVENTO (ver bloco abaixo, que só confirma com
# `maestro_record_valid` DEPOIS de já saber que há contradição) — deixou de
# ser pré-condição da LEITURA, que é o que barateia o caminho comum.
# Formato inesperado (record multi-linha, campo ausente, arquivo ausente) →
# campos vazios, que é o mesmo "mudo" de qualquer outra degradação deste hook.
_maestro_route_fix_record_fields() {
  rec_workflow=""; rec_mode=""; rec_agents=""
  local line=""
  IFS= read -r line < "$1" 2>/dev/null || return 0
  if [[ "$line" =~ \"workflow\"[[:space:]]*:[[:space:]]*\"([a-z]+)\" ]]; then
    rec_workflow="${BASH_REMATCH[1]}"
  fi
  if [[ "$line" =~ \"mode\"[[:space:]]*:[[:space:]]*\"([a-z]+)\" ]]; then
    rec_mode="${BASH_REMATCH[1]}"
  fi
  if [[ "$line" =~ \"agents\"[[:space:]]*:[[:space:]]*\[([^]]*)\] ]]; then
    local raw="${BASH_REMATCH[1]}" n=0
    while [[ "$raw" =~ \"([a-z0-9-]+)\" ]] && (( n < 10 )); do
      rec_agents+="${rec_agents:+,}${BASH_REMATCH[1]}"
      raw="${raw#*"${BASH_REMATCH[0]}"}"
      n=$(( n + 1 ))
    done
  fi
  return 0
}

# Ordem deliberada (medida — ver relato da ordem 030): o caro
# (`maestro_record_valid`, ~38ms nesta bancada: 1 fork de `jq` + 1 de
# `date -d`) só roda DEPOIS de já saber que há contradição a emitir. Antes
# disso só o forkless (leitura do record + comparação). Assim "mencionou sem
# contradizer" — o caso comum quando o record existe — custa o mesmo que o
# caminho sem hit nenhum, e o caro só é pago no caso raro que realmente vai
# ao log.
if [[ -n "$sid" && ( -n "$hit_mode" || -n "$hit_wf" || -n "$hit_agent" || -n "$hit_model" ) ]]; then
  rec_file="$MAESTRO_SESSIONS_DIR/$sid.json"
  _maestro_route_fix_record_fields "$rec_file"
  if [[ ! "$rec_workflow" =~ ^(fix|feature|refactor|ship|audit|verify|codereview|custom)$ ]]; then rec_workflow=""; fi
  if [[ ! "$rec_mode"     =~ ^(direct|subagent|multi)$ ]]; then rec_mode=""; fi
  if [[ ! "$rec_agents"   =~ ^[a-z0-9-]+(,[a-z0-9-]+)*$ ]]; then rec_agents=""; fi

  fix_mode=0; fix_wf=0; fix_agents=0
  if [[ -n "$hit_mode" && -n "$rec_mode" && "$hit_mode" != "$rec_mode" ]]; then fix_mode=1; fi
  if [[ -n "$hit_wf" && -n "$rec_workflow" && "$hit_wf" != "$rec_workflow" ]]; then fix_wf=1; fi
  if _maestro_route_fix_agents_axis "$rec_agents" "$hit_agent" "$hit_model"; then fix_agents=1; fi

  # Ressalva de correção: os campos acima podem vir de um record JÁ VENCIDO
  # (leitura não checa TTL). A validade continua sendo pré-condição do
  # EVENTO — só que agora confirmada aqui, e só quando já há algo a emitir.
  # Vencido → `maestro_record_valid` nega, o `&&` barra tudo, nada é logado.
  if [[ $fix_mode == 1 || $fix_wf == 1 || $fix_agents == 1 ]] \
     && maestro_record_valid "$sid" 2>/dev/null; then
    (( fix_mode   == 1 )) && log_event route_fix session_id="$sid" axis=mode
    (( fix_wf     == 1 )) && log_event route_fix session_id="$sid" axis=workflow
    (( fix_agents == 1 )) && log_event route_fix session_id="$sid" axis=agents
  fi
fi

exit 0
