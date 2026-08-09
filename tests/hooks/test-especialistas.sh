#!/usr/bin/env bash
# S-302: especialistas de linguagem vendorizados/adaptados.
# Verifica: tiering de modelo, atribuição de licença (ADR-004), integridade do vendor/,
# curadoria (enxugamento) e as descrições — o gate MoE, que é a AC da story.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
tmp=$(mktemp -d); export MAESTRO_HOME="$tmp"   # nunca tocar no ~/.maestro real
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
chk() { if [[ $1 -eq 0 ]]; then ok "$2"; else bad "$2"; fi; }

PIN_SHORT="c4b82b0"
PIN_FULL="c4b82b0ad771190355eb8e204b1329732a18449a"
VEN="$REPO/vendor/wshobson-agents"
AG="$REPO/agents"

# adaptado:original-no-vendor:token-da-linguagem
ESPECIALISTAS=(
  "golang-pro:golang-pro.md:Go"
  "python-pro:python-pro.md:Python"
  "typescript-pro:typescript-pro.md:TypeScript"
  "postgres-pro:sql-pro.md:Postgres"
)
# sha256 dos arquivos do upstream no commit pinado (registro independente do PINNED.md)
SHA_golang_pro_md=8e4dc761fb38caab96a1d898596ffee3b55fbf369b36ed9729290f48f13d8cf8
SHA_python_pro_md=5c764591a3d06efac4495c30f80f1d37f460d7d833498eeed8441cf6a1f32f50
SHA_typescript_pro_md=d7dd97fbc3fed73c8feb63ca5071b561660d150d94ecb2c1fa009c7cfba2d404
SHA_sql_pro_md=6eb2fdb139b7971ae98b604ad7d22f6710f904ca74cf00e8961dbe81159513d7
SHA_LICENSE=f89abb55d9f073f38f1703e4518f0613c788c6174be7f13b8dfe48a1c076c746

# extrai o frontmatter (entre a 1a e a 2a linha '---')
frontmatter() { awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$1"; }
# valor de uma chave do frontmatter
fm_val() { frontmatter "$1" | sed -n "s/^$2: *//p" | head -1; }

echo "-- 1. existência e tiering de modelo (sonnet, nunca opus)"
for e in "${ESPECIALISTAS[@]}"; do
  name="${e%%:*}"; f="$AG/$name.md"
  if [[ ! -f $f ]]; then bad "$name existe em agents/"; continue; fi
  ok "$name existe em agents/"
  [[ "$(fm_val "$f" name)" == "$name" ]]; chk $? "$name: frontmatter name confere"
  [[ "$(fm_val "$f" model)" == "sonnet" ]]
  chk $? "$name: model sonnet (rebaixado do upstream — tiering de custo, ADR-004)"
  ! frontmatter "$f" | grep -qi 'opus'; chk $? "$name: nenhum resquício de opus no frontmatter"
  # tools mínimas, só nomes que existem no Claude Code
  tools=$(fm_val "$f" tools)
  [[ -n "$tools" ]]; chk $? "$name: declara tools"
  bad_tool=""
  for t in ${tools//,/ }; do
    case "$t" in
      Read|Grep|Glob|Edit|Write|Bash|WebFetch|WebSearch|Task|NotebookEdit|TodoWrite) ;;
      *) bad_tool="$t" ;;
    esac
  done
  [[ -z "$bad_tool" ]]; chk $? "$name: tools só com nomes reais do Claude Code${bad_tool:+ (inválido: $bad_tool)}"
done

echo "-- 2. atribuição de licença no frontmatter (ADR-004: requisito, não cortesia)"
for e in "${ESPECIALISTAS[@]}"; do
  name="${e%%:*}"; orig="${e#*:}"; orig="${orig%%:*}"; f="$AG/$name.md"
  [[ -f $f ]] || continue
  hdr=$(frontmatter "$f" | grep '^# upstream:')
  [[ -n "$hdr" ]]; chk $? "$name: header '# upstream:' presente no frontmatter"
  grep -q "wshobson/agents@$PIN_SHORT" <<<"$hdr"; chk $? "$name: cita o commit pinado $PIN_SHORT"
  grep -q 'MIT, Seth Hobson' <<<"$hdr"; chk $? "$name: cita licença MIT e autor"
  grep -qF "$orig" <<<"$hdr"; chk $? "$name: cita o caminho de origem ($orig)"
done

echo "-- 3. vendor/ completo e byte-idêntico ao upstream"
for req in LICENSE PINNED.md golang-pro.md python-pro.md typescript-pro.md sql-pro.md; do
  [[ -f "$VEN/$req" ]]; chk $? "vendor/wshobson-agents/$req presente"
done
for req in LICENSE golang-pro.md python-pro.md typescript-pro.md sql-pro.md; do
  [[ -f "$VEN/$req" ]] || continue
  var="SHA_${req//[.-]/_}"; want="${!var}"
  got=$(sha256sum "$VEN/$req" | cut -d' ' -f1)
  [[ "$got" == "$want" ]]; chk $? "vendor/$req byte-idêntico ao upstream (sha256)"
done
# nenhum header de adaptação vazou para o vendor (prova de que não foi editado no lugar)
! grep -rqi 'maestro\|# upstream:' "$VEN"/*.md --include='*.md' --exclude=PINNED.md
chk $? "vendor/: originais sem marca de adaptação"
# PINNED.md registra o essencial
if [[ -f "$VEN/PINNED.md" ]]; then
  grep -q "$PIN_FULL" "$VEN/PINNED.md"; chk $? "PINNED.md registra o commit completo"
  grep -q 'wshobson/agents' "$VEN/PINNED.md"; chk $? "PINNED.md registra o repositório"
  grep -q '2026-08-09' "$VEN/PINNED.md"; chk $? "PINNED.md registra a data da vendorização"
  grep -qi 'MIT' "$VEN/PINNED.md"; chk $? "PINNED.md registra a licença"
  for e in "${ESPECIALISTAS[@]}"; do
    orig="${e#*:}"; orig="${orig%%:*}"; base="${orig%.md}"
    grep -q "agents/$base.md" "$VEN/PINNED.md"; chk $? "PINNED.md registra o caminho de origem de $orig"
  done
fi
# o upstream inteiro NÃO foi vendorizado (ADR-004: não poluir o gate)
n_md=$(find "$VEN" -maxdepth 1 -name '*.md' | wc -l)
[[ $n_md -eq 5 ]]; chk $? "vendor/ tem só os 4 originais + PINNED.md (não os ~200 do upstream)"
n_ag=$(find "$AG" -maxdepth 1 -name '*-pro.md' | wc -l)
[[ $n_ag -eq 4 ]]; chk $? "agents/ tem só os 4 especialistas"

echo "-- 4. curadoria: enxugamento e budget de contexto"
# Regra uniforme: nenhum adaptado passa do budget (80 linhas / 3500 bytes) e todo original
# acima do budget encolhe pelo menos 50%. Original que já cabia no budget só precisa continuar
# cabendo — não há gordura para cortar nele.
BUDGET_BYTES=3500; BUDGET_LINES=80
tot_o=0; tot_a=0
for e in "${ESPECIALISTAS[@]}"; do
  name="${e%%:*}"; orig="${e#*:}"; orig="${orig%%:*}"
  a="$AG/$name.md"; o="$VEN/$orig"
  [[ -f $a && -f $o ]] || { bad "$name: par adaptado/original ausente"; continue; }
  ab=$(wc -c <"$a"); al=$(wc -l <"$a"); ob=$(wc -c <"$o")
  tot_o=$((tot_o+ob)); tot_a=$((tot_a+ab))
  [[ $ab -le $BUDGET_BYTES && $al -le $BUDGET_LINES ]]
  chk $? "$name: dentro do budget de contexto (${ab}B/${al}l <= ${BUDGET_BYTES}B/${BUDGET_LINES}l)"
  if [[ $ob -gt $BUDGET_BYTES ]]; then
    [[ $((ab*100/ob)) -le 50 ]]
    chk $? "$name: original inchado (${ob}B) cortado para $((ab*100/ob))% (<=50%)"
  else
    ok "$name: original já cabia no budget (${ob}B) — curadoria é especialização, não corte"
  fi
done
[[ $((tot_a*100/tot_o)) -le 55 ]]
chk $? "corpus dos especialistas: ${tot_o}B -> ${tot_a}B ($((tot_a*100/tot_o))% <= 55%)"

echo "-- 5. descrições: uma linha, pt-BR, sem herança do upstream"
declare -A DESC=()
for e in "${ESPECIALISTAS[@]}"; do
  name="${e%%:*}"; f="$AG/$name.md"
  [[ -f $f ]] || continue
  d=$(fm_val "$f" description); DESC[$name]="$d"
  [[ -n "$d" ]]; chk $? "$name: tem description"
  # uma linha só: a linha seguinte à description tem de ser outra chave ou o fim do frontmatter
  nxt=$(frontmatter "$f" | grep -n '^description:' | cut -d: -f1)
  nxt=$(frontmatter "$f" | sed -n "$((nxt+1))p")
  [[ "$nxt" =~ ^([A-Za-z_-]+:|#) ]]; chk $? "$name: description ocupa uma única linha"
  [[ ! "$d" =~ ^[\>\|] ]]; chk $? "$name: description não usa bloco YAML multilinha"
  [[ ${#d} -le 240 ]]; chk $? "$name: description com ${#d} chars (<=240)"
  ! grep -qi 'PROACTIVELY' <<<"$d"; chk $? "$name: description sem 'PROACTIVELY'"
  ! grep -qiwE 'master|expert|the|with|and|for|handles|advanced|patterns' <<<"$d"
  chk $? "$name: description sem sobra de inglês do upstream"
  grep -q 'Especialista em' <<<"$d"; chk $? "$name: description em pt-BR"
done

echo "-- 6. gate MoE: sem colisão entre os 4 e desempate explícito"
for e in "${ESPECIALISTAS[@]}"; do
  name="${e%%:*}"; lang="${e##*:}"; d="${DESC[$name]:-}"
  [[ -n "$d" ]] || continue
  grep -qw "$lang" <<<"$d"; chk $? "$name: description nomeia sua linguagem ($lang)"
  # não pode disputar a linguagem de outro especialista
  clash=""
  for o in "${ESPECIALISTAS[@]}"; do
    olang="${o##*:}"; [[ "$olang" == "$lang" ]] && continue
    grep -qw "$olang" <<<"$d" && clash="$olang"
  done
  [[ -z "$clash" ]]; chk $? "$name: não menciona linguagem de outro especialista${clash:+ (colide com $clash)}"
  # desempate contra os perfis de senioridade (S-301) declarado na própria descrição
  grep -qE 'dev-pleno|dev-junior|engenheiro' <<<"$d"
  chk $? "$name: declara o desempate com os perfis de senioridade"
done
# descrições mutuamente distintas
dups=$(printf '%s\n' "${DESC[@]}" | sort | uniq -d | wc -l)
[[ $dups -eq 0 ]]; chk $? "as 4 descrições são mutuamente distintas"
# e distintas já nas primeiras palavras (o gate lê o começo)
heads=$(for d in "${DESC[@]}"; do cut -c1-40 <<<"$d"; done | sort -u | wc -l)
[[ $heads -eq ${#DESC[@]} ]]; chk $? "as 4 descrições divergem já nos primeiros 40 chars"

echo "-- 7. agents/ é só markdown (CLAUDE.md: sem lógica)"
for e in "${ESPECIALISTAS[@]}"; do
  name="${e%%:*}"; f="$AG/$name.md"
  [[ -f $f ]] || continue
  [[ ! -x $f ]]; chk $? "$name: não é executável"
  ! grep -qE '^#!' "$f"; chk $? "$name: sem shebang"
done

# Se o clone do upstream estiver disponível, confere byte a byte contra ele (não só contra o sha).
UPS="${MAESTRO_UPSTREAM_CLONE:-/tmp/claude-1000/-home-rcosta00-dev-orquestrador-maestro-e1/aa0d254c-7981-4383-bbeb-08756ee3257f/scratchpad/ups}"
if [[ -d "$UPS/.git" ]]; then
  echo "-- 8. diff direto contra o clone do upstream (opcional)"
  head=$(git -C "$UPS" rev-parse HEAD 2>/dev/null || echo '?')
  [[ "$head" == "$PIN_FULL" ]]; chk $? "clone local está no commit pinado"
  cmp -s "$UPS/plugins/systems-programming/agents/golang-pro.md"     "$VEN/golang-pro.md";     chk $? "golang-pro.md idêntico ao clone"
  cmp -s "$UPS/plugins/python-development/agents/python-pro.md"      "$VEN/python-pro.md";     chk $? "python-pro.md idêntico ao clone"
  cmp -s "$UPS/plugins/javascript-typescript/agents/typescript-pro.md" "$VEN/typescript-pro.md"; chk $? "typescript-pro.md idêntico ao clone"
  cmp -s "$UPS/plugins/database-design/agents/sql-pro.md"            "$VEN/sql-pro.md";        chk $? "sql-pro.md idêntico ao clone"
  cmp -s "$UPS/LICENSE"                                              "$VEN/LICENSE";           chk $? "LICENSE idêntico ao clone"
fi

[[ ! -e "$tmp/logs" && ! -e "$tmp/sessions" ]]; chk $? "teste não escreveu estado do Maestro"
exit $fail
