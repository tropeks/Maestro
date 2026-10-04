#!/usr/bin/env bash
# ordem 055 — carga só qualifica o recibo; nunca invalida o veredito.
#
# Recibo `exit 0` com conteúdo byte-idêntico ao tip é prova com QUALQUER load.
# O recibo é gravado com load1m_x100 acima do limiar (200) e medições
# inconclusivas; `order --status`, `--status --json` e `--accept` têm de ler
# `provada` e liberar o aceite, com o qualificador impresso pelo evidence.
# Controles negativos: exit ≠ 0, árvore mudada e tip diferente do provado
# continuam recusando. Idade não invalida (ordem 060): controle positivo.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

# fixture <nome> → cria $tmp/<nome> com a ordem 001 num branch com entrega; define P, BR
fixture() {
  P="$tmp/$1"; mkdir -p "$P"
  git -C "$P" init -q -b main
  echo a > "$P/f.txt"
  G add -A; G commit -qm base
  "$BIN" order --create --title "Carga" --project "$P" --session dir-1 >/dev/null <<'BODY'
## Objetivo
Carga não invalida.
BODY
  G add -A; G commit -qm "ordem 1"
  BR=$(grep '^branch:' "$P"/.maestro/orders/001-*.md | awk '{print $2}')
  G checkout -qb "$BR"; echo b >> "$P/f.txt"; G add -A; G commit -qm entrega
}

# grava o recibo e força o qualificador: load 9,10 (> limiar 2,00) e 3 medições inconclusivas
record_loaded() { # <comando...>
  "$BIN" evidence --record --label order-1 --project "$P" -- "$@" >/dev/null 2>&1
  EF=$(ls -t "$MAESTRO_HOME"/evidence/*-order-1 2>/dev/null | head -1)
  [[ -f "$EF" ]] || { bad "fixture: recibo order-1 não gravado"; return 1; }
  sed -i 's/^load1m_x100=.*/load1m_x100=910/; s/^inconclusive=.*/inconclusive=3/' "$EF"
  grep -q '^load1m_x100=910$' "$EF" && grep -q '^inconclusive=3$' "$EF" \
    || { bad "fixture: qualificador de carga não aplicado ao recibo"; return 1; }
}

# --- positivo: exit 0 + árvore idêntica + carga alta ⇒ provada, evidence imprime o qualificador, aceite libera
fixture pos
record_loaded true || exit 1
out=$("$BIN" evidence --check --label order-1 --project "$P" 2>&1); rc=$?
(( rc == 0 )) && grep -q 'VÁLIDA, mas fora do limiar de medição (load 9.10)' <<<"$out" \
  && grep -q '3 medição' <<<"$out" \
  && ok "evidence --check: rc 0, VÁLIDA com qualificador de carga e inconclusivas impresso" \
  || bad "evidence --check (rc=$rc): $out"
out=$("$BIN" order --status 1 --project "$P" 2>&1)
grep -q 'provada' <<<"$out" && ok "order --status: provada com load acima do limiar" \
  || bad "order --status não é provada sob carga (obtido: $(head -5 <<<"$out" | tr '\n' '|'))"
js=$("$BIN" order --status 1 --json --project "$P" 2>&1)
grep -q '"estado":"provada"' <<<"$js" && grep -q '"pede_aceite":true' <<<"$js" \
  && grep -q '"prova":{"estado":"valida"' <<<"$js" \
  && ok "order --status --json: provada, pede_aceite, prova valida" \
  || bad "order --status --json sob carga: $js"
G checkout -q main
out=$("$BIN" order --accept 1 --project "$P" --session dir-1 2>&1); rc=$?
(( rc == 0 )) && grep -q 'ACEITA' <<<"$out" && ok "order --accept: libera com load acima do limiar" \
  || bad "order --accept recusou sob carga (rc=$rc): $out"

# --- negativo 1: exit ≠ 0 continua recusando, mesmo com carga
fixture neg1
"$BIN" evidence --record --label order-1 --project "$P" -- false >/dev/null 2>&1
G checkout -q main
out=$("$BIN" order --accept 1 --project "$P" --session dir-1 2>&1); rc=$?
(( rc != 0 )) && ok "controle: exit ≠ 0 recusa o aceite" || bad "exit ≠ 0 aceitou (rc=$rc): $out"
"$BIN" order --status 1 --project "$P" 2>&1 | grep -q 'em_execucao' \
  && ok "controle: exit ≠ 0 segue em_execucao" || bad "exit ≠ 0 não ficou em_execucao"

# --- negativo 2: árvore mudou na corrida (comando edita o arquivo) ⇒ recibo inválido
fixture neg2
record_loaded bash -c "echo mudou >> '$P/f.txt'" || exit 1
out=$("$BIN" evidence --check --label order-1 --project "$P" 2>&1); rc=$?
(( rc != 0 )) && grep -q 'VENCIDA' <<<"$out" && ok "controle: árvore mudada na corrida ⇒ VENCIDA (rc ≠ 0)" \
  || bad "árvore mudada na corrida não venceu (rc=$rc): $out"

# --- negativo 3: tip diferente do provado ⇒ em_execucao, aceite recusado
fixture neg3
record_loaded true || exit 1
echo c >> "$P/f.txt"; G add -A; G commit -qm "depois da prova"
"$BIN" order --status 1 --project "$P" 2>&1 | grep -q 'em_execucao' \
  && ok "controle: tip ≠ provado ⇒ em_execucao" || bad "tip ≠ provado não ficou em_execucao"
G checkout -q main
out=$("$BIN" order --accept 1 --project "$P" --session dir-1 2>&1); rc=$?
(( rc != 0 )) && ok "controle: tip ≠ provado recusa o aceite" || bad "tip ≠ provado aceitou: $out"

# --- controle 4 (ordem 060): idade enorme + carga ⇒ evidence VÁLIDA (idade só informa)
fixture neg4
record_loaded true || exit 1
sed -i 's/^epoch=.*/epoch=1/' "$EF"
out=$("$BIN" evidence --check --label order-1 --project "$P" 2>&1); rc=$?
(( rc == 0 )) && grep -q 'VÁLIDA' <<<"$out" && ! grep -q 'idade' <<<"$out" \
  && ok "idade é informação (ordem 060): recibo velho e idêntico ao tip segue VÁLIDO (rc 0)" || bad "idade invalidou o recibo (rc=$rc): $out"

exit $fail
