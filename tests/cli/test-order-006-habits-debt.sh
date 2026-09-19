#!/usr/bin/env bash
# ordem 006 (E24 Lote 0, passo 0.3) — dívida DECLARADA com prazo em
# .maestro-habits.tsv (colunas 3/4, OPCIONAIS): sensor  contagem  vence_epoch
# alvo. `maestro habits --all` passa a reprovar quando o prazo vence E a
# contagem segue acima do alvo, MESMO dentro do baseline (coluna 2) — é a
# única forma de o prazo ser mecânico. `maestro doctor` avisa a partir de
# D-14. Epoch é INTEIRO (CLAUDE.md proíbe float em métrica de custo).
#
# Teste NÃO exige o patch já aplicado (bin/ e lib/ estão na denylist do gate).
# Ausente → PENDENTE; presente → cobra os 5 casos do plano + prova o TERCEIRO
# ESTADO (sabota a comparação de prazo e mostra que a MESMA asserção reprova).
#
# Guard por MECANISMO, nunca por ENDEREÇO (lição da ordem 019, paga aqui): o
# E24 moveu as colunas 3/4 de bin/maestro para lib/cmd-habits.sh — um guard
# que só olhasse bin/maestro diria PENDENTE para sempre, com o patch já
# aplicado. Pergunta se o mecanismo existe em ALGUM módulo do plugin — nunca
# em tests/, que casaria com este próprio arquivo e tornaria o guard
# sempre-verdadeiro.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

PATCHED=0
if grep -rqF 'base_vence' "$REPO/lib" "$REPO/bin" "$REPO/hooks" 2>/dev/null; then
  PATCHED=1
fi
if (( PATCHED == 0 )); then
  pending "ordem 006/0.3: bin/maestro ainda sem colunas 3/4 (vence_epoch/alvo) — aplicar docs/patches/006-lote0-shebang-cli.patch e 006-lote0-debt-tsv-cli.patch (nessa ordem)"
  exit 0
fi

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export MAESTRO_HOME="$T/home"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q
echo x=1 > "$P/a.sh"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm base
{ for i in $(seq 1 450); do echo "echo l$i"; done; } > "$P/big.sh"
git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm big

run_habits() { MAESTRO_HOME="$MAESTRO_HOME" "$BIN" habits --all --project "$P" >/dev/null 2>&1; }
run_doctor() { MAESTRO_HOME="$MAESTRO_HOME" CLAUDE_PROJECT_DIR="$P" "$BIN" doctor 2>&1; }

NOW=$(date +%s); PAST=$(( NOW - 30*86400 )); FUT=$(( NOW + 30*86400 )); SOON=$(( NOW + 7*86400 ))

printf '# c\noversized-file\t1\n' > "$P/.maestro-habits.tsv"
run_habits; [[ $? -eq 0 ]] && ok "linha de 2 colunas lê como hoje (bl=1 cobre o achado de big.sh, sem prazo)" \
  || bad "linha de 2 colunas mudou de comportamento"

printf '# c\noversized-file\t5\t%d\t0\n' "$PAST" > "$P/.maestro-habits.tsv"
run_habits; [[ $? -eq 1 ]] && ok "vencida + acima do alvo (mesmo dentro do baseline 5) → exit 1" \
  || bad "deveria reprovar vencida+acima do alvo"

printf '# c\noversized-file\t5\t%d\t1\n' "$PAST" > "$P/.maestro-habits.tsv"
run_habits; [[ $? -eq 0 ]] && ok "vencida + NO alvo (cur == alvo) → exit 0" \
  || bad "não deveria reprovar quando cur está exatamente no alvo"

printf '# c\noversized-file\t5\t%d\t0\n' "$FUT" > "$P/.maestro-habits.tsv"
run_habits; [[ $? -eq 0 ]] && ok "não vencida (prazo no futuro) → exit 0 mesmo acima do alvo" \
  || bad "não deveria reprovar antes do prazo"

printf '# c\noversized-file\t5\t1789408490.5\t0\n' > "$P/.maestro-habits.tsv"
run_habits; [[ $? -eq 0 ]] && ok "epoch não-inteiro é RECUSADO (vira sem-prazo, não aborta)" \
  || bad "epoch não-inteiro deveria ser recusado, não travar o exit"

DOC=$(printf 'oversized-file\t5\t%d\t0\n' "$SOON" > "$P/.maestro-habits.tsv"; run_doctor)
[[ "$DOC" == *"D-14"* ]] && ok "doctor avisa a partir de D-14 do vencimento" \
  || bad "doctor deveria avisar D-14 (saída: '$(grep -i divida <<<"$DOC" || echo vazio)')"

DOC2=$(printf 'oversized-file\t5\t%d\t0\n' "$PAST" > "$P/.maestro-habits.tsv"; run_doctor)
[[ "$DOC2" == *"VENCIDA"* ]] && ok "doctor avisa dívida VENCIDA" \
  || bad "doctor deveria avisar vencida"

# ---------------------------------------------------------------------------
# terceiro estado: sabota a comparação (now > vence) numa CÓPIA e mostra que
# a mesma asserção (caso 2 acima) reprova a sabotagem.
# ---------------------------------------------------------------------------
# Ordem 027: a ordem 016 (36419c6, E24) moveu a comparação de bin/maestro
# para lib/cmd-habits.sh (cmd_habits) — sabotar $SAB não pega mais nada,
# porque o trecho não mora mais lá. _habits_lib_load exige só
# lib/cmd-habits.sh; a sandbox agora COPIA (nunca symlinka) esse arquivo — o
# mínimo pra rodar — e sabota a CÓPIA, não o binário. Symlink em lib/
# sabotaria o repo real.
SABROOT="$T/sabotado"; mkdir -p "$SABROOT/bin" "$SABROOT/lib"
ln -s "$REPO/hooks" "$SABROOT/hooks"
ln -s "$REPO/agents" "$SABROOT/agents" 2>/dev/null || :
ln -s "$REPO/config" "$SABROOT/config" 2>/dev/null || :
ln -s "$REPO/bin/maestro-wtree" "$SABROOT/bin/maestro-wtree"
cp "$REPO/lib/cmd-habits.sh" "$SABROOT/lib/cmd-habits.sh"
SAB="$SABROOT/bin/maestro"; cp "$BIN" "$SAB"; chmod +x "$SAB"
SABLIB="$SABROOT/lib/cmd-habits.sh"
sed -i 's/now_epoch > vence \&\& cur > alvo/now_epoch < vence \&\& cur > alvo/' "$SABLIB"
if ! grep -q 'now_epoch < vence && cur > alvo' "$SABLIB"; then
  bad "sabotagem não pegou (padrão do sed não bateu — mecanismo mudou de forma?)"
else
  printf '# c\noversized-file\t5\t%d\t0\n' "$PAST" > "$P/.maestro-habits.tsv"
  MAESTRO_HOME="$T/home-sab" "$SAB" habits --all --project "$P" >/dev/null 2>&1
  RC_SAB=$?
  [[ $RC_SAB -eq 1 ]] && bad "sabotagem não quebrou nada — vencida+acima do alvo ainda reprovaria" \
    || ok "sabotado: vencida+acima do alvo deixa de reprovar (rc=$RC_SAB) — o teste tem dente"
fi

exit $fail
