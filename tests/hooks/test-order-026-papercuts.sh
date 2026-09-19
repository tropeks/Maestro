#!/usr/bin/env bash
# ordem 026 — papercuts compartilhados: o que quebrou de forma estranha.
#
# Cobre as quatro decisões da ordem, nesta ordem:
#   1. ONDE MORA   — $MAESTRO_HOME/papercuts.md, arquivo único da MÁQUINA (sem
#                    chave `<slug>-<hash8>`): dois projetos diferentes veem o
#                    MESMO registro. É o ponto todo — papercut descoberto num
#                    repo tem de poupar a investigação no outro.
#   2. ORÇAMENTO   — a injeção leva CONTAGEM + ponteiro, nunca o conteúdo; o
#                    custo é O(1) em dígitos (5 e 60 papercuts custam o mesmo);
#                    e o cenário COM papercuts cabe no ratchet que valia ANTES
#                    da ordem. Este é o teste que o ratchet compartilhado e o
#                    doctor NÃO conseguem fazer: os dois medem com MAESTRO_HOME
#                    em mktemp, onde papercuts.md nunca existe.
#   3. QUEM ESCREVE — escritor único (`maestro papercut --add`), com dedup e
#                    append sob lock; concorrência de VERDADE, com escritas
#                    simultâneas, tanto de sintomas distintos quanto do MESMO.
#   4. O QUE NÃO ENTRA — o critério é executado, não só documentado: sintoma sem
#                    conserto, caminho absoluto, separador no campo e campo
#                    quilométrico são RECUSADOS (e a recusa ensina o critério).
#
# Prioridade 1 do INTENT v3 ("nunca bloquear trabalho por estar quebrado") é o
# primeiro bloco: arquivo ausente, vazio ou ilegível → sessão inteira, exit 0,
# nenhuma linha e nenhum byte gasto.
# Hermético: MAESTRO_HOME, HOME e projeto em mktemp -d; nada toca o ~ real.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
BIN="$REPO/bin/maestro"

SANDBOX=$(mktemp -d)
trap 'chmod -R u+rwX "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

PROJ=$(mktemp -d "$SANDBOX/proj.XXXXXX")

OUT=''; RC=0
run_hook() { # run_hook <maestro_home> [home_para_o_til] → OUT/RC
  # O HOME default NÃO é prefixo dos MAESTRO_HOME de fixture: o encurtamento
  # em `~/` é testado à parte, no cenário de produção, e aqui atrapalharia a
  # asserção de que o ponteiro é o caminho inteiro derivado pelo CLI.
  local home="$1" fakehome="${2:-$SANDBOX/nao-e-home}" outf="$SANDBOX/out"
  printf '{"session_id":"pc-test"}' \
    | env MAESTRO_HOME="$home" HOME="$fakehome" CLAUDE_PROJECT_DIR="$PROJ" \
          MAESTRO_NO_UPDATE_CHECK=1 bash "$HOOK" >"$outf" 2>/dev/null
  RC=$?; OUT=$(cat "$outf")
  return 0
}

seed() { # seed <arquivo> <n> — n papercuts sintéticos, sem passar pelo CLI
  local f="$1" n="$2" i
  mkdir -p "${f%/*}"
  printf '# papercuts — cabeçalho sintético\n' > "$f"
  for (( i = 1; i <= n; i++ )); do
    printf '2026-09-18 · sintoma sintetico %s · conserto sintetico %s · fixture\n' "$i" "$i" >> "$f"
  done
}

# ---------------------------------------------------------------------------
echo "-- Prioridade 1: ausente, vazio, só-cabeçalho e ilegível NÃO quebram nada"
# ---------------------------------------------------------------------------
# BOOTSTRAP (decisão do diretor, 2026-09-18): registro vazio não fica mudo — a
# máquina nova é onde o gerente mais precisa saber que o mecanismo existe. A
# linha vazia leva SÓ nome + gatilho + verbo; sem ponteiro e sem "leia ANTES",
# que é o que não serve a quem não tem o que ler.
H_VAZIO=$(mktemp -d "$SANDBOX/hA.XXXXXX")
run_hook "$H_VAZIO"
chk "sem papercuts.md: hook sai 0" "$RC" "0"
grep -q '</maestro-routing>' <<<"$OUT" && ok "sem papercuts.md: bloco íntegro" \
  || bad "sem papercuts.md: bloco íntegro"
grep -q '^papercuts: 0 → consertou falha estranha de FERRAMENTA? maestro papercut --add$' <<<"$OUT" \
  && ok "sem papercuts.md: linha de BOOTSTRAP (o mecanismo se anuncia na máquina vazia)" \
  || bad "sem papercuts.md: linha de bootstrap"
grep -q 'papercuts.md)' <<<"$OUT" \
  && bad "bootstrap NÃO carrega ponteiro (não há o que ler)" \
  || ok  "bootstrap NÃO carrega ponteiro (não há o que ler)"
grep -q 'leia ANTES de investigar' <<<"$OUT" \
  && bad "bootstrap NÃO manda consultar registro vazio" \
  || ok  "bootstrap NÃO manda consultar registro vazio"

: > "$H_VAZIO/papercuts.md"
run_hook "$H_VAZIO"
chk "arquivo VAZIO: hook sai 0" "$RC" "0"
grep -q '^papercuts: 0 ' <<<"$OUT" && ok "arquivo vazio: bootstrap (mesmo estado)" \
  || bad "arquivo vazio: bootstrap"

printf '# papercuts — só cabeçalho, nenhum registro\n# data · sintoma · conserto · projeto\n' \
  > "$H_VAZIO/papercuts.md"
run_hook "$H_VAZIO"
grep -q '^papercuts: 0 ' <<<"$OUT" \
  && ok "só cabeçalho (0 registros): bootstrap — cabeçalho não é papercut" \
  || bad "só cabeçalho (0 registros): bootstrap — cabeçalho não é papercut"
BYTES_BOOT=$(printf '%s' "$OUT" | wc -c | tr -d ' ')

# ILEGÍVEL é o único estado MUDO: dizer "0" para um arquivo que existe e não se
# consegue ler seria mentir a contagem, e o Maestro não finge estado.
BYTES_MUDO=""
seed "$H_VAZIO/papercuts.md" 3
chmod 000 "$H_VAZIO/papercuts.md" 2>/dev/null
if [[ -r "$H_VAZIO/papercuts.md" ]]; then
  ok "ilegível: pulado (rodando como root?)"
else
  run_hook "$H_VAZIO"
  chk "arquivo ILEGÍVEL: hook sai 0" "$RC" "0"
  grep -q 'INSTRUÇÃO CANÔNICA' <<<"$OUT" && ok "ilegível: núcleo da injeção intacto" \
  || bad "ilegível: núcleo da injeção intacto"
  grep -q '^papercuts:' <<<"$OUT" \
    && bad "ilegível: MUDO — nem bootstrap (não se afirma contagem que não se leu)" \
    || ok  "ilegível: MUDO — nem bootstrap (não se afirma contagem que não se leu)"
  BYTES_MUDO=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
fi
chmod u+rw "$H_VAZIO/papercuts.md" 2>/dev/null

# ---------------------------------------------------------------------------
echo "-- presente: contagem + ponteiro + gatilho, e NADA do conteúdo"
# ---------------------------------------------------------------------------
H5=$(mktemp -d "$SANDBOX/hB.XXXXXX")
seed "$H5/papercuts.md" 5
run_hook "$H5"
chk "com papercuts: hook sai 0" "$RC" "0"
grep -q '^papercuts: 5 ' <<<"$OUT" && ok "a contagem é a real (5)" || bad "a contagem é a real (5)"
grep -qF "$H5/papercuts.md" <<<"$OUT" && ok "ponteiro = caminho do CLI (derivação única)" \
  || bad "ponteiro = caminho do CLI"
grep -q 'leia ANTES de investigar' <<<"$OUT" \
  && ok "o gatilho está na linha (consulta ANTES de investigar)" \
  || bad "o gatilho está na linha"
grep -q 'maestro papercut --add' <<<"$OUT" \
  && ok "a linha também diz como REGISTRAR (arquivo que ninguém alimenta morre)" \
  || bad "a linha diz como registrar"
n=$(grep -c 'sintoma sintetico' <<<"$OUT" || true)
chk "o CONTEÚDO do arquivo NUNCA é injetado (ponteiro, não despejo)" "$n" "0"
n=$(grep -c 'conserto sintetico' <<<"$OUT" || true)
chk "nenhum conserto vaza para a injeção" "$n" "0"

# o mesmo registro visto de OUTRO projeto: é da máquina, não do projeto
PROJ2=$(mktemp -d "$SANDBOX/proj2.XXXXXX")
OUT2=$(printf '{"session_id":"pc-test"}' \
  | env MAESTRO_HOME="$H5" HOME="$SANDBOX/nao-e-home" CLAUDE_PROJECT_DIR="$PROJ2" \
        MAESTRO_NO_UPDATE_CHECK=1 bash "$HOOK" 2>/dev/null)
grep -q '^papercuts: 5 ' <<<"$OUT2" \
  && ok "decisão 1: outro PROJETO, mesmo registro (chave é a máquina, não o repo)" \
  || bad "decisão 1: outro projeto vê o mesmo registro"

# ---------------------------------------------------------------------------
echo "-- decisão 2: o custo da linha é O(1) em dígitos, não O(n) em papercuts"
# ---------------------------------------------------------------------------
H60=$(mktemp -d "$SANDBOX/hC.XXXXXX")   # nome do MESMO tamanho: o caminho entra na linha
seed "$H60/papercuts.md" 60
run_hook "$H5";  B5=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
run_hook "$H60"; B60=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
grep -q '^papercuts: 60 ' <<<"$OUT" && ok "60 papercuts: contagem certa" || bad "60 papercuts: contagem certa"
d=$(( B60 - B5 ))
if (( d >= 0 && d <= 2 )); then
  ok "5 → 60 papercuts custa +${d}B na injeção (só o dígito a mais)"
else
  bad "5 → 60 papercuts custou ${d}B — a injeção está crescendo com o arquivo"
fi
# Custo das DUAS linhas, contra o único estado que não emite nada (o mudo).
if [[ -n "$BYTES_MUDO" ]]; then
  d2=$(( B5 - BYTES_MUDO ))
  if (( d2 > 0 && d2 <= 160 )); then
    ok "linha CHEIA custa ${d2}B (teto declarado: 160B)"
  else
    bad "custo da linha cheia fora do teto declarado: ${d2}B"
  fi
  d3=$(( BYTES_BOOT - BYTES_MUDO ))
  if (( d3 > 0 && d3 <= 90 )); then
    ok "linha de BOOTSTRAP custa ${d3}B (teto declarado: 90B) — o que a máquina vazia paga"
  else
    bad "custo do bootstrap fora do teto declarado: ${d3}B"
  fi
  if (( d3 < d2 )); then
    ok "bootstrap é mais barato que a linha cheia (${d3}B < ${d2}B): paga só o que serve a quem não tem o que ler"
  else
    bad "bootstrap não é mais barato que a linha cheia (${d3}B vs ${d2}B)"
  fi
else
  ok "custo por linha: pulado (o estado mudo não pôde ser medido)"
fi

# Cenário de PRODUÇÃO (MAESTRO_HOME sob o HOME, ponteiro encurtado em `~/`):
# tem de caber no ratchet que valia ANTES desta ordem. É a asserção que o
# ratchet compartilhado e o doctor não podem fazer — os dois medem em mktemp.
RATCHET_PRE_026=7400
FAKEHOME=$(mktemp -d "$SANDBOX/home.XXXXXX")
seed "$FAKEHOME/.maestro/papercuts.md" 5
run_hook "$FAKEHOME/.maestro" "$FAKEHOME"
BPROD=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
grep -q 'papercuts: 5 (~/.maestro/papercuts.md)' <<<"$OUT" \
  && ok "ponteiro sai como ~/ (mais curto E sem imprimir a topologia da máquina)" \
  || bad "ponteiro encurtado em ~/"
if (( BPROD <= RATCHET_PRE_026 )); then
  ok "injeção de produção com papercuts: ${BPROD}B ≤ ${RATCHET_PRE_026}B (ratchet pré-026)"
else
  bad "injeção de produção com papercuts: ${BPROD}B > ${RATCHET_PRE_026}B — o corte compensatório não pagou"
fi
# O bootstrap também é cenário de produção: máquina nova, registro vazio.
HVAZIA=$(mktemp -d "$SANDBOX/home2.XXXXXX")
mkdir -p "$HVAZIA/.maestro"
run_hook "$HVAZIA/.maestro" "$HVAZIA"
BBOOTPROD=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
grep -q '^papercuts: 0 ' <<<"$OUT" && ok "máquina nova em produção: bootstrap presente" \
  || bad "máquina nova em produção: bootstrap presente"
if (( BBOOTPROD <= RATCHET_PRE_026 )); then
  ok "injeção de produção com bootstrap: ${BBOOTPROD}B ≤ ${RATCHET_PRE_026}B (ratchet pré-026)"
else
  bad "injeção de produção com bootstrap: ${BBOOTPROD}B > ${RATCHET_PRE_026}B — bootstrap sem corte que o pague"
fi
if (( BPROD <= 8000 )); then ok "dentro do teto duro de 8000B (INTENT v3)"
else bad "teto duro de 8000B estourado (${BPROD}B)"; fi

# ---------------------------------------------------------------------------
echo "-- CLI: path, count e list"
# ---------------------------------------------------------------------------
HC=$(mktemp -d "$SANDBOX/hD.XXXXXX")
p=$(MAESTRO_HOME="$HC" "$BIN" papercut --path)
chk "--path é a MESMA derivação que o hook usa" "$p" "$HC/papercuts.md"
out=$(MAESTRO_HOME="$HC" "$BIN" papercut 2>&1); rc=$?
chk "lista sem arquivo: rc 0 (nada quebra)" "$rc" "0"
grep -q 'nenhum papercut registrado' <<<"$out" && ok "lista vazia diz como registrar o primeiro" \
  || bad "lista vazia diz como registrar o primeiro"
chk "--count sem arquivo" "$(MAESTRO_HOME="$HC" "$BIN" papercut --count)" "0"

# ---------------------------------------------------------------------------
echo "-- decisão 4: o critério é EXECUTADO, não só documentado"
# ---------------------------------------------------------------------------
recusa() { # recusa <descrição> <args...>
  local desc="$1"; shift
  local o rc
  o=$(MAESTRO_HOME="$HC" "$BIN" papercut "$@" 2>&1); rc=$?
  if (( rc == 1 )); then ok "recusa: $desc (rc 1)"; else bad "recusa: $desc (rc=$rc, saída: $o)"; fi
}
recusa "sintoma sem conserto não é papercut, é investigação em aberto" \
  --add "algo esquisito aconteceu"
recusa "caminho absoluto (metadado de outra máquina)" \
  --add "x falha" --fix "edite /home/alguem/dev/x.sh" --project maestro
recusa "campo com o separador '·'" \
  --add "a · b" --fix "conserto" --project maestro
recusa "campo quilométrico (papercut é UMA linha lida de relance)" \
  --add "$(printf 'x%.0s' $(seq 1 200))" --fix "conserto" --project maestro
recusa "slug de projeto fora do formato" \
  --add "y falha" --fix "conserto" --project "Projeto Com Espaço"
o=$(MAESTRO_HOME="$HC" "$BIN" papercut --add "algo esquisito" 2>&1 || true)
grep -q 'issue' <<<"$o" && ok "a recusa ENSINA o critério (aponta a issue)" \
  || bad "a recusa ensina o critério"
chk "nenhuma recusa criou arquivo" "$(MAESTRO_HOME="$HC" "$BIN" papercut --count)" "0"

# aceita o caso legítimo, inclusive com caminho RELATIVO no conserto
MAESTRO_HOME="$HC" "$BIN" papercut --add "pkill sai 144" \
  --fix "128+sinal, não código do pkill (0/1/2/3): confira com pgrep antes de investigar" \
  --project maestro >/dev/null
chk "papercut legítimo entra" "$(MAESTRO_HOME="$HC" "$BIN" papercut --count)" "1"
grep -q '^# papercuts' "$HC/papercuts.md" && ok "o CRITÉRIO é escrito no topo do arquivo, onde se lê" \
  || bad "cabeçalho com o critério"
grep -q '^#   bug do PROJETO' "$HC/papercuts.md" && ok "o cabeçalho diz o que NÃO entra" \
  || bad "o cabeçalho diz o que NÃO entra"
MAESTRO_HOME="$HC" "$BIN" papercut --add "pkill sai 144" --fix "outro conserto" --project maestro >/dev/null
chk "mesmo sintoma de novo: idempotente (dedup por sintoma)" \
  "$(MAESTRO_HOME="$HC" "$BIN" papercut --count)" "1"

# ---------------------------------------------------------------------------
echo "-- decisão 3: escrita CONCORRENTE de verdade (12 processos simultâneos)"
# ---------------------------------------------------------------------------
HK=$(mktemp -d "$SANDBOX/hE.XXXXXX")
N=12
for (( i = 1; i <= N; i++ )); do
  MAESTRO_HOME="$HK" "$BIN" papercut --add "sintoma concorrente $i" \
    --fix "conserto concorrente $i" --project fixture >/dev/null 2>&1 &
done
wait
got=$(MAESTRO_HOME="$HK" "$BIN" papercut --count)
chk "as $N escritas simultâneas entraram, nenhuma perdida" "$got" "$N"
malformadas=$(grep -c '^2[0-9][0-9][0-9]-' "$HK/papercuts.md" || true)
chk "toda linha de papercut começa por data (nenhuma escrita partida ao meio)" "$malformadas" "$N"
n=$(awk -F ' · ' '/^2[0-9][0-9][0-9]-/ && NF != 4 { c++ } END { print c+0 }' "$HK/papercuts.md")
chk "toda linha tem exatamente 4 campos (nenhuma entrelaçada)" "$n" "0"
n=$(grep -c '^# papercuts —' "$HK/papercuts.md" || true)
chk "o cabeçalho foi escrito UMA vez só, mesmo com $N criadores simultâneos" "$n" "1"
n=$(sort "$HK/papercuts.md" | grep '^2[0-9][0-9][0-9]-' | uniq -d | wc -l | tr -d ' ')
chk "nenhuma linha duplicada" "$n" "0"

echo "-- decisão 3: 8 processos com o MESMO sintoma → uma linha só"
HM=$(mktemp -d "$SANDBOX/hF.XXXXXX")
for (( i = 1; i <= 8; i++ )); do
  MAESTRO_HOME="$HM" "$BIN" papercut --add "o mesmo papercut visto por nove gerentes" \
    --fix "conserto $i" --project fixture >/dev/null 2>&1 &
done
wait
if command -v flock >/dev/null 2>&1; then
  chk "dedup sob corrida: 8 simultâneos, 1 linha (a seção crítica cobre leitura+escrita)" \
    "$(MAESTRO_HOME="$HM" "$BIN" papercut --count)" "1"
else
  got=$(MAESTRO_HOME="$HM" "$BIN" papercut --count)
  (( got >= 1 && got <= 8 )) \
    && ok "sem flock: dedup degrada (obtido $got), mas nenhuma linha se perde ou corrompe" \
    || bad "sem flock: contagem fora da faixa (obtido $got)"
fi

# ---------------------------------------------------------------------------
echo "-- kill-switch e higiene de metadados"
# ---------------------------------------------------------------------------
o=$(printf '{"session_id":"pc-test"}' \
  | env MAESTRO_OFF=1 MAESTRO_HOME="$H5" HOME="$SANDBOX/nao-e-home" CLAUDE_PROJECT_DIR="$PROJ" \
        bash "$HOOK" 2>/dev/null); rc=$?
chk "MAESTRO_OFF=1: exit 0" "$rc" "0"
chk "MAESTRO_OFF=1: nenhuma saída, nem a linha de papercuts" "$(printf '%s' "$o" | wc -c | tr -d ' ')" "0"

log="$HK/logs/routing.jsonl"
if [[ -f "$log" ]]; then
  grep -q 'sintoma concorrente' "$log" && bad "conteúdo de papercut vazou para o log" \
  || ok  "nada de papercut vai para o log (só metadado)"
else
  ok "escrever papercut não gera evento de log (nada a vazar)"
fi

exit $fail
