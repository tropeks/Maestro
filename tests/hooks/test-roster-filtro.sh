#!/usr/bin/env bash
# S-303 — `.maestro.yaml` filtra o roster ativo.
#
# AC (EPICS.md): "em repo com `experts: [golang-pro]`, só ele aparece na injeção".
# Aqui isso é provado com rosters SINTÉTICOS (mktemp -d + MAESTRO_AGENTS_DIR):
# o roster real do repo é do E3 e pode estar sendo escrito neste exato momento —
# um teste que dependesse dele seria um teste de corrida, não de comportamento.
# O roster real ganha, no fim, uma verificação de ponta a ponta separada.
#
# Cobre também: `experts` ausente/vazio/inexistente, o orçamento de 8000 bytes
# com roster grande, degradação com exit 0 em profile corrompido, a validação de
# `--agents` no CLI (par válido × inválido) e as checagens de roster do doctor.
#
# Isolamento: MAESTRO_HOME, CLAUDE_PROJECT_DIR e agents/ sempre em mktemp -d.
# NUNCA toca o ~/.maestro real nem o agents/ do repo.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
CLI="$REPO/src/cli.ts"
TABLE="$REPO/config/routing-table.yaml"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$1" == "yes" ]]; then ok "$2"; else bad "$2${3:+ — $3}"; fi; }

ROSTER_HDR='## Roster — nome (modelo): função'

new_home() { local d; d=$(mktemp -d "$SANDBOX/home.XXXXXX"); printf '%s' "$d"; }

# mk_roster <dir> <nome>... — roster sintético com frontmatter do DATA_MODEL §5
mk_roster() {
  local dir="$1"; shift
  mkdir -p "$dir"
  local n
  for n in "$@"; do
    cat >"$dir/$n.md" <<EOF
---
name: $n
description: aciona $n quando a tarefa é do domínio de $n e de mais ninguém
model: sonnet
tools: Read, Grep, Glob, Edit, Write, Bash
---
corpo do prompt, irrelevante para o índice.
EOF
  done
}

# proj <conteúdo-do-.maestro.yaml|-> → caminho de um projeto novo
proj() {
  local d; d=$(mktemp -d "$SANDBOX/proj.XXXXXX")
  [[ "${1:--}" == "-" ]] || printf '%s\n' "$1" >"$d/.maestro.yaml"
  printf '%s' "$d"
}

IN="$SANDBOX/in.json"
printf '{"session_id":"ses_S303","hook_event_name":"SessionStart"}' >"$IN"

# run <projdir> <agents-dir> [VAR=VAL...] → OUT, ERR, RC, OUTBYTES
run() {
  local p="$1" a="$2"; shift 2
  local outf="$SANDBOX/out.$$" errf="$SANDBOX/err.$$"
  env MAESTRO_HOME="$(new_home)" CLAUDE_PROJECT_DIR="$p" MAESTRO_AGENTS_DIR="$a" "$@" \
    bash "$HOOK" <"$IN" >"$outf" 2>"$errf"
  RC=$?
  OUT=$(cat "$outf"); ERR=$(cat "$errf")
  OUTBYTES=$(wc -c <"$outf" | tr -d ' ')
  return 0
}

# roster de 9 nomes, igual ao do E3
ROSTER9="$SANDBOX/agents9"
mk_roster "$ROSTER9" dev-junior dev-pleno engenheiro revisor qa \
                     golang-pro python-pro typescript-pro postgres-pro

# lista os nomes que a injeção declarou no roster
listed() { printf '%s\n' "$OUT" | sed -n 's/^- \([a-z0-9-]*\) (.*/\1/p' | sort | tr '\n' ' '; }

# =============================================================================
echo "-- 1. AC da S-303: experts: [golang-pro] → só golang-pro na injeção"
# =============================================================================
run "$(proj 'version: 1
project: remedix
languages: [go]
experts: [golang-pro]')" "$ROSTER9"

[[ $RC -eq 0 ]] && chk yes "exit 0 com filtro ativo" || chk no "exit 0 com filtro ativo" "rc=$RC"
got=$(listed)
[[ "$got" == "golang-pro " ]] \
  && chk yes "AC: só golang-pro aparece no roster injetado" \
  || chk no "AC: só golang-pro aparece no roster injetado" "veio: '$got'"
[[ "$OUT" != *"- python-pro ("* && "$OUT" != *"- typescript-pro ("* && "$OUT" != *"- postgres-pro ("* ]] \
  && chk yes "nenhum outro especialista de linguagem vaza" || chk no "nenhum outro especialista de linguagem vaza"
[[ "$OUT" != *"- dev-junior ("* && "$OUT" != *"- dev-pleno ("* \
   && "$OUT" != *"- engenheiro ("* && "$OUT" != *"- revisor ("* && "$OUT" != *"- qa ("* ]] \
  && chk yes "nenhum perfil de senioridade vaza" || chk no "nenhum perfil de senioridade vaza"
[[ "$OUT" == *"$ROSTER_HDR"* ]] \
  && chk yes "seção de roster continua existindo (filtro não some com a seção)" \
  || chk no "seção de roster continua existindo"
[[ "$OUT" == *"experts ativos: golang-pro"* ]] \
  && chk yes "profile anuncia o expert ativo" || chk no "profile anuncia o expert ativo"
[[ "$OUT" == *"1 de 9"* ]] \
  && chk yes "injeção diz quantos agentes o filtro omitiu" || chk no "injeção diz quantos agentes o filtro omitiu"
[[ -z "$ERR" ]] && chk yes "filtro válido não polui o stderr" || chk no "filtro válido não polui o stderr" "$ERR"

# =============================================================================
echo "-- 2. vários experts: exatamente o subconjunto declarado"
# =============================================================================
run "$(proj 'experts: [golang-pro, python-pro, revisor]')" "$ROSTER9"
got=$(listed)
[[ "$got" == "golang-pro python-pro revisor " ]] \
  && chk yes "3 experts declarados → 3 agentes injetados" \
  || chk no "3 experts declarados → 3 agentes injetados" "veio: '$got'"
[[ "$OUT" == *"3 de 9"* ]] && chk yes "contagem do filtro correta (3 de 9)" || chk no "contagem do filtro correta (3 de 9)"

# ordem do YAML não importa, duplicata não duplica linha
run "$(proj 'experts: [revisor, golang-pro, revisor]')" "$ROSTER9"
got=$(listed)
[[ "$got" == "golang-pro revisor " ]] \
  && chk yes "expert repetido no YAML não duplica a linha do roster" \
  || chk no "expert repetido no YAML não duplica a linha do roster" "veio: '$got'"

# =============================================================================
echo "-- 3. experts ausente → roster INTEIRO (sem opinião do projeto)"
# =============================================================================
run "$(proj 'version: 1
project: remedix
languages: [go, python]')" "$ROSTER9"
got=$(listed)
[[ "$got" == "dev-junior dev-pleno engenheiro golang-pro postgres-pro python-pro qa revisor typescript-pro " ]] \
  && chk yes "sem experts: os 9 agentes aparecem" || chk no "sem experts: os 9 agentes aparecem" "veio: '$got'"
[[ "$OUT" != *"de 9)"* ]] \
  && chk yes "sem experts: nenhuma nota de filtro na injeção" || chk no "sem experts: nenhuma nota de filtro na injeção"

# sem .maestro.yaml nenhum → idem
run "$(proj -)" "$ROSTER9"
got=$(listed)
[[ "$got" == *"dev-junior"* && "$got" == *"typescript-pro"* ]] \
  && chk yes "sem .maestro.yaml: roster inteiro" || chk no "sem .maestro.yaml: roster inteiro" "veio: '$got'"

# =============================================================================
echo "-- 4. experts: [] → decisão explícita de roster vazio"
# =============================================================================
run "$(proj 'version: 1
project: sem-agentes
experts: []')" "$ROSTER9"
[[ $RC -eq 0 ]] && chk yes "exit 0 com experts: []" || chk no "exit 0 com experts: []" "rc=$RC"
got=$(listed)
[[ -z "${got// /}" ]] \
  && chk yes "experts: [] omite todos os agentes" || chk no "experts: [] omite todos os agentes" "veio: '$got'"
[[ "$OUT" == *"$ROSTER_HDR"* && "$OUT" == *"nenhum agente ativo"* ]] \
  && chk yes "experts: [] explica o vazio (não finge que o roster não existe)" \
  || chk no "experts: [] explica o vazio"
[[ "$OUT" == *"experts ativos: nenhum"* ]] \
  && chk yes "profile registra a escolha explícita" || chk no "profile registra a escolha explícita"

# =============================================================================
echo "-- 5. expert inexistente: avisa, ignora, NUNCA quebra a sessão"
# =============================================================================
run "$(proj 'experts: [golang-pro, agente-que-nao-existe]')" "$ROSTER9"
[[ $RC -eq 0 ]] && chk yes "exit 0 com expert inexistente" || chk no "exit 0 com expert inexistente" "rc=$RC"
got=$(listed)
[[ "$got" == "golang-pro " ]] \
  && chk yes "nome inexistente é ignorado; o válido continua valendo" \
  || chk no "nome inexistente é ignorado; o válido continua valendo" "veio: '$got'"
[[ "$ERR" == *"não existem no roster"* && "$ERR" == *"agente-que-nao-existe"* ]] \
  && chk yes "aviso no stderr nomeia o expert inexistente" || chk no "aviso no stderr nomeia o expert inexistente" "$ERR"
[[ "$OUT" == *"experts ignorados (fora do roster): agente-que-nao-existe"* ]] \
  && chk yes "injeção também mostra o que foi ignorado" || chk no "injeção também mostra o que foi ignorado"

# todos inexistentes = erro de config, não intenção: volta ao roster inteiro
run "$(proj 'experts: [nao-existe-um, nao-existe-dois]')" "$ROSTER9"
[[ $RC -eq 0 ]] && chk yes "exit 0 com todos os experts inexistentes" || chk no "exit 0 com todos os experts inexistentes" "rc=$RC"
got=$(listed)
[[ "$got" == "dev-junior dev-pleno engenheiro golang-pro postgres-pro python-pro qa revisor typescript-pro " ]] \
  && chk yes "filtro 100% inválido cai para o roster inteiro (typo não apaga o roster)" \
  || chk no "filtro 100% inválido cai para o roster inteiro" "veio: '$got'"
[[ "$ERR" == *"injetando o roster inteiro"* ]] \
  && chk yes "stderr explica o fallback" || chk no "stderr explica o fallback" "$ERR"

# nome hostil não vira token nem vaza para a injeção
run "$(proj 'experts: [../../etc/passwd, "a;id", golang-pro]')" "$ROSTER9"
[[ $RC -eq 0 && "$OUT" != *"passwd"* && "$OUT" != *";id"* ]] \
  && chk yes "expert com metacaractere é descartado antes de virar valor" \
  || chk no "expert com metacaractere é descartado antes de virar valor" "rc=$RC"
[[ "$(listed)" == "golang-pro " ]] \
  && chk yes "expert hostil descartado não impede o filtro válido" || chk no "expert hostil descartado não impede o filtro válido"

# =============================================================================
echo "-- 6. orçamento de 8000 bytes com roster grande"
# =============================================================================
BIG_ROSTER="$SANDBOX/agents-big"
names=()
for i in $(seq -w 1 120); do names+=("agente-de-teste-numero-$i"); done
names+=(zz-alvo-do-filtro)   # último na ordem alfabética: é o primeiro a ser cortado
mk_roster "$BIG_ROSTER" "${names[@]}"

run "$(proj -)" "$BIG_ROSTER"
[[ $RC -eq 0 ]] && chk yes "exit 0 com roster de 121 agentes" || chk no "exit 0 com roster de 121 agentes" "rc=$RC"
[[ $OUTBYTES -le 8000 ]] \
  && chk yes "roster grande sem filtro respeita 8000 B (saiu $OUTBYTES B)" \
  || chk no "roster grande sem filtro respeita 8000 B" "saiu $OUTBYTES B"
[[ "$OUT" == *"session_id: ses_S303"* && "$OUT" == *"maestro decide --session ses_S303"* ]] \
  && chk yes "núcleo (session_id + instrução canônica) sobrevive" || chk no "núcleo sobrevive"
[[ "$OUT" == *"</maestro-routing>"* ]] && chk yes "bloco fecha com roster grande" || chk no "bloco fecha com roster grande"
[[ "$OUT" != *"zz-alvo-do-filtro"* ]] \
  && chk yes "sem filtro, o último agente cai no truncamento" || chk no "sem filtro, o último agente cai no truncamento"

# o filtro roda ANTES do orçamento: o mesmo agente que era truncado agora cabe
run "$(proj 'experts: [zz-alvo-do-filtro]')" "$BIG_ROSTER"
[[ $OUTBYTES -le 8000 ]] \
  && chk yes "roster grande com filtro respeita 8000 B (saiu $OUTBYTES B)" \
  || chk no "roster grande com filtro respeita 8000 B" "saiu $OUTBYTES B"
[[ "$(listed)" == "zz-alvo-do-filtro " ]] \
  && chk yes "filtro aplicado antes do truncamento (agente antes cortado agora aparece)" \
  || chk no "filtro aplicado antes do truncamento" "veio: '$(listed)'"

# =============================================================================
echo "-- 7. degradação: profile corrompido → exit 0, sessão intacta"
# =============================================================================
degrade() { # degrade <descrição>
  if [[ $RC -ne 0 ]]; then bad "$1 (rc=$RC)"; return; fi
  if [[ "$OUT" != *"<maestro-routing>"* || "$OUT" != *"maestro decide --session"* \
        || "$OUT" != *"</maestro-routing>"* ]]; then
    bad "$1 — bloco/instrução ausentes"; return
  fi
  ok "$1"
}

PB=$(mktemp -d "$SANDBOX/proj.XXXXXX")
printf '\x00\x01experts: [[[ nao\t: yaml\n  - - -\n' >"$PB/.maestro.yaml"
run "$PB" "$ROSTER9"
degrade ".maestro.yaml corrompido degrada com exit 0"
[[ "$OUT" == *"$ROSTER_HDR"* ]] \
  && chk yes "profile corrompido não derruba o roster" || chk no "profile corrompido não derruba o roster"

PB2=$(mktemp -d "$SANDBOX/proj.XXXXXX")
head -c 4096 /dev/urandom >"$PB2/.maestro.yaml"
run "$PB2" "$ROSTER9"
degrade ".maestro.yaml binário degrada com exit 0"

PB3=$(mktemp -d "$SANDBOX/proj.XXXXXX")
printf 'experts: [golang-pro]\n' >"$PB3/.maestro.yaml"; chmod 0000 "$PB3/.maestro.yaml"
run "$PB3" "$ROSTER9"
degrade ".maestro.yaml ilegível degrada com exit 0"
chmod 0644 "$PB3/.maestro.yaml"

# roster ausente/vazio com experts declarado: nada de erro, só aviso na injeção
run "$(proj 'experts: [golang-pro]')" "$SANDBOX/nao-existe-agents"
degrade "agents/ inexistente degrada com exit 0"
[[ "$OUT" == *"nenhum agents/*.md instalado"* ]] \
  && chk yes "roster ausente é explicado na injeção" || chk no "roster ausente é explicado na injeção"

EMPTY_ROSTER="$SANDBOX/agents-vazio"; mkdir -p "$EMPTY_ROSTER"
run "$(proj 'experts: [golang-pro]')" "$EMPTY_ROSTER"
degrade "agents/ vazio degrada com exit 0"

# kill-switch continua soberano com filtro declarado
H=$(new_home)
out=$(env MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$(proj 'experts: [golang-pro]')" \
      MAESTRO_AGENTS_DIR="$ROSTER9" MAESTRO_OFF=1 bash "$HOOK" <"$IN" 2>&1); rc=$?
[[ $rc -eq 0 && -z "$out" ]] \
  && chk yes "MAESTRO_OFF=1 continua silencioso com filtro declarado" \
  || chk no "MAESTRO_OFF=1 continua silencioso com filtro declarado" "rc=$rc out='$out'"

# =============================================================================
echo "-- 8. CLI: --agents validado contra o roster (API_SPEC §2/§3)"
# =============================================================================
if ! command -v bun >/dev/null 2>&1; then
  echo "skip CLI: bun ausente"
else
  FAKE_ROOT="$SANDBOX/plugin"
  mk_roster "$FAKE_ROOT/agents" golang-pro revisor
  CLI_HOME="$SANDBOX/cli-home"
  cout="$SANDBOX/cli.out"; cerr="$SANDBOX/cli.err"
  cli() {
    env MAESTRO_HOME="$CLI_HOME" MAESTRO_PLUGIN_ROOT="$FAKE_ROOT" MAESTRO_ROUTING_TABLE="$TABLE" \
      bun "$CLI" "$@" >"$cout" 2>"$cerr"
    CRC=$?
  }

  cli decide --session ses-ok --workflow fix --mode subagent --agents golang-pro
  [[ $CRC -eq 0 ]] && chk yes "agente do roster: decide sai 0" || chk no "agente do roster: decide sai 0" "rc=$CRC $(cat "$cerr")"
  [[ -f "$CLI_HOME/sessions/ses-ok.json" ]] \
    && chk yes "agente do roster: decision record gravado" || chk no "agente do roster: decision record gravado"
  grep -q 'roster vazio' "$cerr" \
    && chk no "roster populado não avisa 'roster vazio'" || chk yes "roster populado não avisa 'roster vazio'"

  cli decide --session ses-bad --workflow fix --mode subagent --agents nao-existe
  [[ $CRC -eq 1 ]] && chk yes "agente fora do roster: exit 1" || chk no "agente fora do roster: exit 1" "rc=$CRC"
  grep -qE '^maestro: validation: .+ \(fix: .+\)$' "$cerr" \
    && chk yes "envelope do API_SPEC §3 na categoria validation" \
    || chk no "envelope do API_SPEC §3 na categoria validation" "$(head -1 "$cerr")"
  grep -q 'golang-pro, revisor' "$cerr" \
    && chk yes "erro lista os nomes válidos (acionável do telefone)" \
    || chk no "erro lista os nomes válidos" "$(head -1 "$cerr")"
  [[ ! -f "$CLI_HOME/sessions/ses-bad.json" ]] \
    && chk yes "agente inválido não grava record" || chk no "agente inválido não grava record"

  # um válido + um inválido em multi: falha e nomeia só o inválido
  cli decide --session ses-mix --workflow fix --mode multi --agents golang-pro,fantasma
  [[ $CRC -eq 1 ]] && chk yes "multi com um agente fora do roster: exit 1" || chk no "multi com um agente fora do roster: exit 1" "rc=$CRC"
  grep -q 'fora do roster: fantasma' "$cerr" \
    && chk yes "erro cita apenas o agente inválido" || chk no "erro cita apenas o agente inválido" "$(head -1 "$cerr")"

  # transição automática: sem agents/*.md o CLI só avisa (instalação incompleta é assunto do doctor)
  ROOT_VAZIO="$SANDBOX/plugin-vazio"; mkdir -p "$ROOT_VAZIO/agents"
  env MAESTRO_HOME="$CLI_HOME" MAESTRO_PLUGIN_ROOT="$ROOT_VAZIO" MAESTRO_ROUTING_TABLE="$TABLE" \
    bun "$CLI" decide --session ses-vazio --workflow fix --mode subagent --agents nome-qualquer \
    >"$cout" 2>"$cerr"; CRC=$?
  [[ $CRC -eq 0 ]] && chk yes "roster vazio: decide não falha (só avisa)" || chk no "roster vazio: decide não falha" "rc=$CRC"
  grep -q 'roster vazio' "$cerr" \
    && chk yes "roster vazio: aviso no stderr" || chk no "roster vazio: aviso no stderr"
fi

# =============================================================================
echo "-- 9. doctor valida o roster (frontmatter, colisão, experts do projeto)"
# =============================================================================
DOC="$REPO/bin/maestro"
doc() { # doc <agents-dir> [projdir]
  env MAESTRO_HOME="$(new_home)" MAESTRO_AGENTS_DIR="$1" CLAUDE_PROJECT_DIR="${2:-$SANDBOX}" \
    "$DOC" doctor --ci >"$SANDBOX/doc.out" 2>"$SANDBOX/doc.err"
  DRC=$?
  DOUT=$(cat "$SANDBOX/doc.out" "$SANDBOX/doc.err")
}

doc "$ROSTER9"
[[ $DRC -eq 0 ]] && chk yes "doctor: roster sintético válido passa" || chk no "doctor: roster sintético válido passa" "rc=$DRC $DOUT"
# --ci esconde as linhas ok (ENGINEERING_SPEC §CI/CD): a contagem se confere no modo normal
env MAESTRO_HOME="$(new_home)" MAESTRO_AGENTS_DIR="$ROSTER9" CLAUDE_PROJECT_DIR="$SANDBOX" \
  NO_COLOR=1 "$DOC" doctor >"$SANDBOX/doc.out" 2>&1
[[ "$(cat "$SANDBOX/doc.out")" == *"9 agente(s) com frontmatter válido"* ]] \
  && chk yes "doctor: conta os agentes válidos" || chk no "doctor: conta os agentes válidos"

BADR="$SANDBOX/agents-bad"; mkdir -p "$BADR"
printf -- '---\nname: outro\ndescription: ok\nmodel: sonnet\ntools: Read\n---\n' >"$BADR/nome-errado.md"
doc "$BADR"
[[ $DRC -eq 1 ]] && chk yes "doctor: name != nome do arquivo → exit 1 (validação)" || chk no "doctor: name != nome do arquivo → exit 1" "rc=$DRC"
[[ "$DOUT" == *"não casa com o nome do arquivo"* ]] \
  && chk yes "doctor: aponta o arquivo com name divergente" || chk no "doctor: aponta o arquivo com name divergente"

BADR2="$SANDBOX/agents-bad2"; mkdir -p "$BADR2"
printf -- '---\nname: sem-desc\ndescription:\nmodel: sonnet\ntools: Read\n---\n' >"$BADR2/sem-desc.md"
doc "$BADR2"
[[ $DRC -eq 1 && "$DOUT" == *"'description:' vazia"* ]] \
  && chk yes "doctor: description vazia → exit 1" || chk no "doctor: description vazia → exit 1" "rc=$DRC"

BADR3="$SANDBOX/agents-bad3"; mkdir -p "$BADR3"
printf -- '---\nname: turbo-agent\ndescription: uma linha\nmodel: turbo\ntools: Read\n---\n' >"$BADR3/turbo-agent.md"
doc "$BADR3"
[[ $DRC -eq 1 && "$DOUT" == *"fora de haiku|sonnet|opus"* ]] \
  && chk yes "doctor: model fora do vocabulário → exit 1" || chk no "doctor: model fora do vocabulário → exit 1" "rc=$DRC"

BADR4="$SANDBOX/agents-bad4"; mkdir -p "$BADR4"
printf -- '---\nname: sem-tools\ndescription: uma linha\nmodel: sonnet\ntools:\n---\n' >"$BADR4/sem-tools.md"
doc "$BADR4"
[[ $DRC -eq 1 && "$DOUT" == *"'tools:' ausente ou vazio"* ]] \
  && chk yes "doctor: tools vazio → exit 1" || chk no "doctor: tools vazio → exit 1" "rc=$DRC"

BADR4b="$SANDBOX/agents-bad4b"; mkdir -p "$BADR4b"
printf -- '---\nname: Golang_Pro\ndescription: uma linha\nmodel: sonnet\ntools: Read\n---\n' >"$BADR4b/Golang_Pro.md"
doc "$BADR4b"
[[ $DRC -eq 1 && "$DOUT" == *"fora de kebab-case"* ]] \
  && chk yes "doctor: name fora de kebab-case → exit 1 (hook e CLI o ignorariam)" \
  || chk no "doctor: name fora de kebab-case → exit 1" "rc=$DRC $DOUT"

BADR5="$SANDBOX/agents-bad5"; mkdir -p "$BADR5"
printf 'sem frontmatter nenhum\n' >"$BADR5/solto.md"
doc "$BADR5"
[[ $DRC -eq 1 && "$DOUT" == *"frontmatter ausente"* ]] \
  && chk yes "doctor: arquivo sem frontmatter → exit 1" || chk no "doctor: arquivo sem frontmatter → exit 1" "rc=$DRC"

# colisão de nomes: dois arquivos declarando o mesmo `name`
BADR6="$SANDBOX/agents-bad6"; mk_roster "$BADR6" golang-pro
printf -- '---\nname: golang-pro\ndescription: clone que disputa o mesmo gate\nmodel: sonnet\ntools: Read\n---\n' \
  >"$BADR6/go-pro.md"
doc "$BADR6"
[[ $DRC -eq 1 && "$DOUT" == *"duplicado(s): golang-pro"* ]] \
  && chk yes "doctor: colisão de name → exit 1" || chk no "doctor: colisão de name → exit 1" "rc=$DRC $DOUT"

# .maestro.yaml do projeto referenciando expert inexistente → AVISO, não falha
PROJ_BAD=$(mktemp -d "$SANDBOX/proj.XXXXXX")
printf 'version: 1\nexperts: [golang-pro, agente-fantasma]\n' >"$PROJ_BAD/.maestro.yaml"
doc "$ROSTER9" "$PROJ_BAD"
[[ $DRC -eq 0 ]] \
  && chk yes "doctor: expert inexistente no .maestro.yaml não reprova a instalação" \
  || chk no "doctor: expert inexistente no .maestro.yaml não reprova a instalação" "rc=$DRC"
[[ "$DOUT" == *"agente-fantasma"* && "$DOUT" == *"warn"* ]] \
  && chk yes "doctor: avisa qual expert está fora do roster" || chk no "doctor: avisa qual expert está fora do roster" "$DOUT"

PROJ_BIN=$(mktemp -d "$SANDBOX/proj.XXXXXX")
head -c 3000 /dev/urandom >"$PROJ_BIN/.maestro.yaml"
doc "$ROSTER9" "$PROJ_BIN"
[[ $DRC -eq 0 ]] \
  && chk yes "doctor: .maestro.yaml binário não derruba o diagnóstico" \
  || chk no "doctor: .maestro.yaml binário não derruba o diagnóstico" "rc=$DRC"

PROJ_OK=$(mktemp -d "$SANDBOX/proj.XXXXXX")
printf 'version: 1\nexperts: [golang-pro, revisor]\n' >"$PROJ_OK/.maestro.yaml"
doc "$ROSTER9" "$PROJ_OK"
[[ $DRC -eq 0 && "$DOUT" != *"fora do roster"* ]] \
  && chk yes "doctor: .maestro.yaml coerente passa sem aviso" || chk no "doctor: .maestro.yaml coerente passa sem aviso" "$DOUT"

# modo degradado: sem jq e sem bun o doctor ainda valida o roster
NOBIN="$SANDBOX/nobin"; mkdir -p "$NOBIN"
for t in bash sh awk gawk mawk sed grep egrep cat cut tr head tail wc stat date mkdir rm mv cp ln \
         chmod touch dirname basename flock sort ls find env sleep seq id printf readlink; do
  p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NOBIN/$t"
done
if PATH="$NOBIN" command -v jq >/dev/null 2>&1 || PATH="$NOBIN" command -v bun >/dev/null 2>&1; then
  bad "sandbox sem jq/bun (ainda visíveis)"
else
  nojq() { # nojq <agents-dir> → saída em $o, rc em $rc
    env MAESTRO_HOME="$(new_home)" MAESTRO_AGENTS_DIR="$1" CLAUDE_PROJECT_DIR="$SANDBOX" \
      PATH="$NOBIN" bash "$DOC" doctor --ci >"$SANDBOX/doc.out" 2>"$SANDBOX/doc.err"; rc=$?
    o=$(cat "$SANDBOX/doc.out" "$SANDBOX/doc.err")
  }

  nojq "$BADR"
  [[ "$o" == *"não casa com o nome do arquivo"* ]] \
    && chk yes "doctor sem jq/bun: ainda detecta frontmatter inválido" \
    || chk no "doctor sem jq/bun: ainda detecta frontmatter inválido" "$o"
  # jq é dependência declarada (API_SPEC §1): a ausência dele é FAIL de AMBIENTE
  # e prevalece sobre o FAIL de conteúdo — por isso 2, não 1.
  [[ $rc -eq 2 ]] && chk yes "doctor sem jq/bun: FAIL de ambiente prevalece (exit 2)" \
                  || chk no "doctor sem jq/bun: FAIL de ambiente prevalece (exit 2)" "rc=$rc"

  nojq "$ROSTER9"
  [[ "$o" != *"roster:"*"FAIL"* && "$o" != *"frontmatter ausente"* ]] \
    && chk yes "doctor sem jq/bun: roster válido não gera FAIL falso" \
    || chk no "doctor sem jq/bun: roster válido não gera FAIL falso" "$o"
fi

# =============================================================================
echo "-- 10. ponta a ponta com o roster real do repo (se já estiver populado)"
# =============================================================================
shopt -s nullglob
real=("$REPO"/agents/*.md)
shopt -u nullglob
if [[ ${#real[@]} -eq 0 ]]; then
  echo "skip roster real ainda vazio (E3 em voo)"
else
  run "$(proj 'version: 1
project: maestro-e1
languages: [go]
experts: [golang-pro]')" "$REPO/agents"
  [[ $RC -eq 0 ]] && chk yes "E2E: exit 0 com o roster real" || chk no "E2E: exit 0 com o roster real" "rc=$RC"
  [[ "$(listed)" == "golang-pro " ]] \
    && chk yes "E2E: AC da S-303 vale no roster real (${#real[@]} agentes instalados)" \
    || chk no "E2E: AC da S-303 vale no roster real" "veio: '$(listed)'"

  run "$(proj -)" "$REPO/agents"
  [[ $OUTBYTES -le 8000 ]] \
    && chk yes "E2E: injeção com o roster real inteiro cabe em 8000 B ($OUTBYTES B)" \
    || chk no "E2E: injeção com o roster real inteiro cabe em 8000 B" "$OUTBYTES B"
  n=$(listed | wc -w)
  [[ "$n" -eq ${#real[@]} ]] \
    && chk yes "E2E: os $n agentes reais aparecem sem filtro" \
    || chk no "E2E: todos os agentes reais aparecem sem filtro" "injetados=$n, arquivos=${#real[@]}"
fi

# =============================================================================
[[ $fail -eq 0 ]] && echo "test-roster-filtro: OK" || echo "test-roster-filtro: FALHAS" >&2
exit $fail
