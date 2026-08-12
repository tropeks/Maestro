#!/usr/bin/env bash
# S-401 (bindings) + S-501 (gates humanos) — teste de MUTAÇÃO da routing table.
#
# A AC da S-401 é literal: "cada step referencia comando existente no ambiente".
# Um doctor que aprova binding apontando para skill desinstalada é pior que
# doctor nenhum: a injeção manda o Claude rodar algo que não existe e ele
# improvisa em silêncio. Por isso o teste não se contenta em ver o doctor passar
# no repo íntegro — ele quebra o binding de UM jeito por vez e exige FAIL com o
# exit code certo (API_SPEC §3: 1 = conteúdo · 2 = ambiente/dependência).
#
# A parte S-501 prova que o gate humano é DERIVADO do YAML (mudou `gate:` no
# workflow, mudou a instrução injetada) e não texto decorativo fixo no hook.
#
# NUNCA escreve no ~/.maestro real nem depende de rede.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session-start.sh"
TMPROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"' EXIT

fail=0
MATRIX=()
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

fresh() { # cópia íntegra do repo (sem .git) — mutações não tocam o repo real
  local d="$TMPROOT/$1"
  cp -a "$ROOT" "$d"
  rm -rf "$d/.git"
  mkdir -p "$d/.state"
  printf '%s\n' "$d"
}

OUT=''
doctor_run() { # doctor_run <dir> [env...] → OUT = stdout+stderr; retorna o rc
  local d="$1"; shift
  OUT="$(env MAESTRO_HOME="$d/.state" NO_COLOR=1 "$@" "$d/bin/maestro" doctor 2>&1)"
  return $?
}

matrix_add() {
  local c="$1" pad='' n=$(( 42 - ${#1} ))
  [[ $n -gt 0 ]] && pad="$(printf '%*s' "$n" '')"
  MATRIX+=("${c}${pad}$(printf '%-5s %-5s %s' "$2" "$3" "$4")")
}

expect_break() { # expect_break <caso> <dir> <rc esperado> <regex> [env...]
  local caso="$1" d="$2" want="$3" re="$4"; shift 4
  local rc
  doctor_run "$d" "$@"; rc=$?
  if [[ $rc -eq $want ]] && printf '%s\n' "$OUT" | grep -qE "$re"; then
    ok "mutação reprovada: $caso (rc=$rc)"
    matrix_add "$caso" "$want" "$rc" "REPROVOU"
  else
    bad "mutação NÃO reprovada: $caso (rc=$rc, esperado=$want, regex='$re')"
    matrix_add "$caso" "$want" "$rc" "ESCAPOU <<<"
    printf '%s\n' "$OUT" | sed 's/^/       | /'
  fi
}

# `sed -i` no bloco bindings da cópia
bind_set() { sed -i "s|^  $2:.*|  $2:        $3|" "$1/config/routing-table.yaml"; }

# raiz de skills FIXTURE — hermética: cada skill: citada em config/routing-table.yaml
# ganha um diretório com SKILL.md dentro de $TMPROOT. Sem isto o teste depende de
# quais skills estão instaladas na máquina de quem roda (ok no dev-box, skip/FAIL
# no runner do CI, que não tem superpowers/gstack). MAESTRO_SKILL_DIRS substitui as
# raízes reais (ver bin/maestro skill_roots()) então nem o $HOME real importa aqui.
# Cópia do parser de yaml_bindings() (bin/maestro:423-424) — se o parser real mudar, sincronizar aqui.
yaml_binding_pairs() { # → "<step>\t<alvo1> <alvo2>..." por linha
  awk '/^[^ \t#]/ { inb = ($0 ~ /^bindings:[ \t]*(#.*)?$/) ? 1 : 0; next }
       inb && /^[ \t]+[a-z][A-Za-z0-9_-]*:/ { v=$0; sub(/[ \t]*#.*$/,"",v); i=index(v,":");
         k=substr(v,1,i-1); r=substr(v,i+1); gsub(/^[ \t]+|[ \t]+$/,"",k);
         gsub(/[][,"]/," ",r); gsub(/[ \t]+/," ",r); gsub(/^ | $/,"",r);
         if (k != "" && r != "") print k "\t" r }' "$1"
}

SKILL_FIXTURE="$TMPROOT/skills-fixture"
mkdir -p "$SKILL_FIXTURE"
while IFS=$'\t' read -r step targets; do
  for t in $targets; do
    case "$t" in
      skill:*)
        n="${t#skill:}"
        mkdir -p "$SKILL_FIXTURE/$n"
        : >"$SKILL_FIXTURE/$n/SKILL.md"
        ;;
    esac
  done
done < <(yaml_binding_pairs "$ROOT/config/routing-table.yaml")

# =========================================================== 1. controle: repo íntegro
BASE="$(fresh base)"
doctor_run "$BASE" MAESTRO_SKILL_DIRS="$SKILL_FIXTURE"; rc=$?
if [[ $rc -eq 0 ]] \
   && printf '%s\n' "$OUT" | grep -q 'ok   bindings: todo step de workflow tem binding' \
   && printf '%s\n' "$OUT" | grep -qE 'ok   bindings: [0-9]+ alvo\(s\) resolvem no ambiente'; then
  ok "repo íntegro: doctor aprova os bindings (rc=0)"
  matrix_add "(controle) bindings do repo" "0" "$rc" "APROVOU"
else
  bad "repo íntegro: bindings deveriam passar (rc=$rc)"
  matrix_add "(controle) bindings do repo" "0" "$rc" "REPROVOU <<<"
  printf '%s\n' "$OUT" | sed 's/^/       | /'
fi

# Caso de controle adicional (ambiente real): valida a coerência interna do parser vs. YAML
if [[ -d "$HOME/.claude/skills" ]]; then
  BASE_REAL="$(fresh base-env-real)"
  doctor_run "$BASE_REAL"; rc=$?
  if [[ $rc -eq 0 ]] \
     && printf '%s\n' "$OUT" | grep -q 'ok   bindings: todo step de workflow tem binding' \
     && printf '%s\n' "$OUT" | grep -qE 'ok   bindings: [0-9]+ alvo\(s\) resolvem no ambiente'; then
    ok "repo íntegro contra ambiente real (dev-box): doctor aprova os bindings (rc=0)"
    matrix_add "repo íntegro contra ambiente real" "0" "$rc" "APROVOU"
  else
    bad "repo íntegro contra ambiente real: bindings deveriam passar (rc=$rc)"
    matrix_add "repo íntegro contra ambiente real" "0" "$rc" "REPROVOU <<<"
    printf '%s\n' "$OUT" | sed 's/^/       | /'
  fi
else
  matrix_add "repo íntegro contra ambiente real" "skip" "skip" "SKIP (sem skills reais)"
fi

# AC da S-401, prova positiva: cada alvo do YAML existe MESMO no disco. agent:/native:
# são conferidos contra o repo real; skill: contra a raiz FIXTURE (montada acima a
# partir do próprio YAML) — hermético, não depende do que está instalado na máquina
# (este bloco abaixo é FIXTURE, validação interna do parser).
echo "-- alvos do routing-table.yaml conferidos um a um no ambiente"
yaml_binding_pairs "$ROOT/config/routing-table.yaml" \
| while IFS=$'\t' read -r step targets; do
    for t in $targets; do
      case "$t" in
        agent:*)
          if [[ -f "$ROOT/agents/${t#agent:}.md" ]]; then echo "ok   $step → $t (agents/${t#agent:}.md)"
          else echo "FAIL $step → $t não existe no roster"; fi ;;
        native:*)
          if [[ "${t#native:}" == "plan-mode" ]]; then echo "ok   $step → $t (vocabulário fechado do DATA_MODEL §1)"
          else echo "FAIL $step → $t fora do vocabulário native"; fi ;;
        skill:*)
          n="${t#skill:}"
          if [[ -f "$SKILL_FIXTURE/$n/SKILL.md" ]]; then echo "ok   $step → $t ($SKILL_FIXTURE/$n/SKILL.md)"
          else echo "FAIL $step → $t sem fixture (bug no gerador da raiz fake acima)"; fi ;;
        *) echo "FAIL $step → '$t' fora de skill:|agent:|native:" ;;
      esac
    done
  done | tee "$TMPROOT/alvos.txt"
grep -q '^FAIL' "$TMPROOT/alvos.txt" && { bad "algum alvo do YAML não existe no ambiente"; }

# =========================================================== 2. matriz de mutação
# --- conteúdo (rc 1) ---------------------------------------------------------
d="$(fresh sem-binding)"
sed -i '/^  investigate: /d' "$d/config/routing-table.yaml"
expect_break "step de workflow sem binding" "$d" 1 'sem binding: fix → investigate' \
  MAESTRO_SKILL_DIRS="$SKILL_FIXTURE"

d="$(fresh alvo-sem-prefixo)"
bind_set "$d" qa 'gstack-qa'
expect_break "alvo sem prefixo skill:|agent:|native:" "$d" 1 "alvos no formato skill:" \
  MAESTRO_SKILL_DIRS="$SKILL_FIXTURE"

d="$(fresh native-inventado)"
bind_set "$d" plan 'native:telepatia'
expect_break "native: fora do vocabulário fechado" "$d" 1 'fora do vocabulário native' \
  MAESTRO_SKILL_DIRS="$SKILL_FIXTURE"

d="$(fresh v2-sem-bindings)"
sed -i '/^bindings:/,/^routes:/{/^routes:/!d}' "$d/config/routing-table.yaml"
expect_break "version 2 sem bloco bindings (com Bun)" "$d" 1 'version >= 2 exige o bloco bindings' \
  MAESTRO_SKILL_DIRS="$SKILL_FIXTURE"

# --- ambiente/dependência (rc 2) --------------------------------------------
d="$(fresh skill-fantasma)"
bind_set "$d" audit 'skill:gstack-nao-existe'
# MAESTRO_SKILL_DIRS=SKILL_FIXTURE: sem isto, num ambiente sem NENHUMA raiz de skill
# (CI limpo) o checker faz o skip honesto (rc=0) em vez de reprovar — comportamento
# correto (coberto no bloco 3), mas indeterminístico para ESTE caso. Com uma raiz
# fixture presente (que não tem "gstack-nao-existe"), o rc=2 fica garantido nos dois
# ambientes.
expect_break "binding aponta p/ skill desinstalada" "$d" 2 'skill:gstack-nao-existe \(skill não instalada\)' \
  MAESTRO_SKILL_DIRS="$SKILL_FIXTURE"

# agent: é conteúdo (rc 1), não ambiente: o roster é versionado dentro do plugin,
# então binding e agents/ em desacordo é incoerência entre dois arquivos do repo.
d="$(fresh agente-fantasma)"
bind_set "$d" implement 'agent:dev-fantasma'
expect_break "binding aponta p/ agente fora do roster" "$d" 1 'agent:dev-fantasma \(não há dev-fantasma.md' \
  MAESTRO_SKILL_DIRS="$SKILL_FIXTURE"

# o agente existir no roster de OUTRA instalação não vale: é o roster desta cópia
d="$(fresh agente-removido)"
rm -f "$d/agents/revisor.md"
expect_break "agente do binding removido do roster" "$d" 1 'agent:revisor' \
  MAESTRO_SKILL_DIRS="$SKILL_FIXTURE"

# =========================================================== 3. degradação honesta
# Ambiente sem NENHUMA raiz de skill (CI limpo) não é instalação quebrada.
d="$(fresh sem-raiz-de-skill)"
doctor_run "$d" MAESTRO_SKILL_DIRS="$TMPROOT/nao-existe-nenhum-dir"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$OUT" | grep -q 'skip bindings: alvos resolvem no ambiente'; then
  ok "ambiente sem diretório de skills: skip honesto, não FAIL (rc=0)"
  matrix_add "ambiente sem raiz de skill (CI)" "0" "$rc" "SKIP (ok)"
else
  bad "ambiente sem diretório de skills deveria dar skip (rc=$rc)"
  matrix_add "ambiente sem raiz de skill (CI)" "0" "$rc" "ERRADO <<<"
  printf '%s\n' "$OUT" | sed 's/^/       | /'
fi

# ...mas com raiz existente e skill ausente, volta a reprovar (o skip não é desculpa)
mkdir -p "$TMPROOT/skills-parciais/gstack-qa" && : >"$TMPROOT/skills-parciais/gstack-qa/SKILL.md"
d="$(fresh raiz-parcial)"
expect_break "raiz de skill existe mas a skill não" "$d" 2 'skill não instalada' \
  MAESTRO_SKILL_DIRS="$TMPROOT/skills-parciais"

# binding declarado que nenhum workflow usa: aviso, nunca falha
d="$(fresh binding-orfao)"
sed -i 's|^  audit:       skill:gstack-cso|  audit:       skill:gstack-cso\n  orfao:       skill:gstack-cso|' \
  "$d/config/routing-table.yaml"
doctor_run "$d"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$OUT" | grep -q 'warn bindings: todo binding é usado'; then
  ok "binding órfão vira aviso, não falha (rc=0)"
else
  bad "binding órfão deveria virar aviso (rc=$rc)"
  printf '%s\n' "$OUT" | sed 's/^/       | /'
fi

# --- sem Bun: a validação de conteúdo NÃO pode evaporar ----------------------
NOBUN="$TMPROOT/path-sem-bun"; mkdir -p "$NOBUN"
for c in bash env readlink dirname basename date stat grep sed awk tr mkdir touch rm flock jq cp ls find wc sort id chmod; do
  p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$NOBUN/$c"
done
d="$(fresh sem-bun-sem-binding)"
OUT="$(PATH="$NOBUN" MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$OUT" | grep -q 'ok   bindings: todo step de workflow tem binding'; then
  ok "sem Bun: check_bindings continua rodando (bash puro)"
else
  bad "sem Bun: check_bindings não rodou (rc=$rc)"
  printf '%s\n' "$OUT" | sed 's/^/       | /'
fi

d="$(fresh sem-bun-v2-sem-bindings)"
sed -i '/^bindings:/,/^routes:/{/^routes:/!d}' "$d/config/routing-table.yaml"
OUT="$(PATH="$NOBUN" MAESTRO_HOME="$d/.state" NO_COLOR=1 "$d/bin/maestro" doctor 2>&1)"; rc=$?
if [[ $rc -eq 1 ]] && printf '%s\n' "$OUT" | grep -q 'version >= 2 exige o bloco bindings'; then
  ok "sem Bun: version 2 sem bindings continua reprovando (rc=1)"
  matrix_add "version 2 sem bindings (sem Bun)" "1" "$rc" "REPROVOU"
else
  bad "sem Bun: version 2 sem bindings escapou (rc=$rc)"
  matrix_add "version 2 sem bindings (sem Bun)" "1" "$rc" "ESCAPOU <<<"
  printf '%s\n' "$OUT" | sed 's/^/       | /'
fi

# =========================================================== 4. injeção (S-401 + S-501)
SB="$TMPROOT/inj"; mkdir -p "$SB"
IN="$SB/in.json"; printf '%s' '{"session_id":"ses_S401"}' >"$IN"
run_hook() { # run_hook <yaml|-> [env...] → OUT/RC/OUTBYTES
  local yaml="$1"; shift
  local h; h=$(mktemp -d "$SB/home.XXXXXX")
  local p; p=$(mktemp -d "$SB/proj.XXXXXX")
  local e=()
  [[ "$yaml" != "-" ]] && e+=(MAESTRO_ROUTING_TABLE="$yaml")
  env MAESTRO_HOME="$h" CLAUDE_PROJECT_DIR="$p" "${e[@]}" "$@" \
    bash "$HOOK" <"$IN" >"$SB/out.txt" 2>"$SB/err.txt"
  RC=$?; OUT=$(cat "$SB/out.txt"); ERR=$(cat "$SB/err.txt")
  OUTBYTES=$(wc -c <"$SB/out.txt" | tr -d ' ')
  return 0
}

run_hook -
[[ $RC -eq 0 ]] && ok "injeção: exit 0 com a routing table real" || bad "injeção: exit 0 (rc=$RC)"
[[ "$OUT" == *"## Bindings (step → o que roda"* ]] \
  && ok "injeção: seção de bindings presente" || bad "injeção: seção de bindings presente"
for pair in "investigate → skill:systematic-debugging" "plan → native:plan-mode" \
            "implement → agent:dev-pleno" "review → skill:requesting-code-review + agent:revisor" \
            "qa → skill:gstack-qa + agent:qa" "ship → skill:gstack-ship" "audit → skill:gstack-cso"; do
  [[ "$OUT" == *"- $pair"* ]] && ok "injeção: binding '$pair'" || bad "injeção: binding '$pair'"
done
[[ "$OUT" == *"## Gates humanos"* && "$OUT" == *"gate plan (feature, refactor)"* \
   && "$OUT" == *"gate ship (ship)"* ]] \
  && ok "injeção: gates humanos derivados do YAML (plan: feature+refactor · ship: ship)" \
  || bad "injeção: gates humanos derivados do YAML"
[[ "$OUT" == *"plan mode"* && "$OUT" == *"Aprovo o plano?"* && "$OUT" == *"Shipo agora?"* ]] \
  && ok "injeção: pergunta objetiva de aprovação (plan mode + shipo)" \
  || bad "injeção: pergunta objetiva de aprovação"
[[ $OUTBYTES -le 8000 ]] && ok "injeção: $OUTBYTES B dentro do teto de 8000" \
  || bad "injeção: estourou o teto ($OUTBYTES B)"
echo "     (orçamento: $OUTBYTES B de 8000 — folga de $(( 8000 - OUTBYTES )) B)"

# o gate é DERIVADO: sem `gate: plan`/`gate: ship` no YAML, a seção some
Y1="$SB/sem-gate.yaml"
cat >"$Y1" <<'YAML'
version: 2
gate:
  mode: warn
  allowlist:
    extensions: [.md]
    paths: [docs/]
  denylist:
    paths: [.claude/]
    self_paths: [bin/]
workflows:
  fix: {steps: [investigate], gate: none}
bindings:
  investigate: skill:systematic-debugging
routes:
  - {intent: "x", workflow: fix}
execution_heuristics:
  - "h"
YAML
run_hook "$Y1"
[[ $RC -eq 0 && "$OUT" != *"## Gates humanos"* ]] \
  && ok "sem gate plan/ship no YAML, a seção de gates não é injetada" \
  || bad "seção de gates apareceu sem gate declarado (rc=$RC)"

# ...e um gate novo declarado aparece sozinho
Y2="$SB/so-ship.yaml"; sed 's/gate: none/gate: ship/' "$Y1" >"$Y2"
run_hook "$Y2"
[[ "$OUT" == *"gate ship (fix)"* && "$OUT" != *"gate plan"* ]] \
  && ok "gate ship declarado em outro workflow é derivado corretamente" \
  || bad "gate ship declarado em outro workflow não foi derivado"

# binding malformado no YAML: descartado com aviso, jamais injetado
Y3="$SB/binding-lixo.yaml"
sed 's|  investigate: skill:systematic-debugging|  investigate: [skill:systematic-debugging, rm -rf /]|' "$Y1" >"$Y3"
run_hook "$Y3"
[[ $RC -eq 0 && "$OUT" == *"investigate → skill:systematic-debugging"* \
   && "$OUT" != *"rm"* && "$ERR" == *"descartado"* ]] \
  && ok "alvo malformado é descartado com aviso, sem vazar para a injeção" \
  || bad "alvo malformado vazou ou derrubou o hook (rc=$RC)"

# YAML sem bloco bindings: injeção segue sem a seção, nunca quebra
Y4="$SB/sem-bindings.yaml"; grep -v '^  investigate: skill' "$Y1" | grep -v '^bindings:' >"$Y4"
run_hook "$Y4"
[[ $RC -eq 0 && "$OUT" == *"<maestro-routing>"* && "$OUT" != *"## Bindings"* ]] \
  && ok "YAML sem bindings degrada: injeção sai sem a seção, exit 0" \
  || bad "YAML sem bindings quebrou a injeção (rc=$RC)"

# kill-switch continua mudo com o schema novo
H=$(mktemp -d "$SB/ks.XXXXXX")
out=$(env MAESTRO_HOME="$H" MAESTRO_OFF=1 bash "$HOOK" <"$IN" 2>&1); rc=$?
[[ $rc -eq 0 && -z "$out" ]] && ok "MAESTRO_OFF=1: silencioso mesmo com bindings/gates" \
  || bad "MAESTRO_OFF=1 falhou (rc=$rc)"

# =========================================================== matriz final
echo
echo "matriz de mutação dos bindings (rc 1 = conteúdo · rc 2 = ambiente):"
printf '     %-42s%-5s %-5s %s\n' "caso" "esp" "obt" "veredito"
for l in "${MATRIX[@]}"; do printf '     %s\n' "$l"; done
echo

[[ $fail -eq 0 ]] && echo "test-routing-table: OK" || echo "test-routing-table: FALHAS" >&2
exit $fail
