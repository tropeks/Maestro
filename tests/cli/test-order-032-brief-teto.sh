#!/usr/bin/env bash
# Ordem 032 — `maestro brief --write` nunca corta em silêncio: teto de 64 KiB
# (65536 bytes) nos dois caminhos (--file e stdin), erro explícito acima
# disso, nada gravado quando recusa. Issue #43.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

export MAESTRO_HOME="$tmp/home"

mkrepo() { # mkrepo <dir> → repo git com 1 commit
  mkdir -p "$1"; git -C "$1" init -q
  echo conteudo > "$1/a.txt"; git -C "$1" add -A
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm inicial
}

PROJ="$tmp/projeto"; mkrepo "$PROJ"

# gen_narrative <bytes-alvo> <marcador-final> <arquivo-saida>
# Gera um corpo de linhas de enchimento sem newline final, terminando
# exatamente no marcador — permite comparar "última linha da entrada" com
# precisão de byte, sem ambiguidade de \n final.
gen_narrative() {
  local target="$1" marker="$2" out="$3"
  local line="filler-0123456789-abcdefghijklmnopqrstuvwxyz-ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local linelen=$(( ${#line} + 1 ))
  : > "$out"
  local cur=0
  local budget=$(( target - ${#marker} ))
  while (( cur + linelen <= budget )); do
    printf '%s\n' "$line" >> "$out"
    cur=$(( cur + linelen ))
  done
  printf '%s' "$marker" >> "$out"
}

# narrativa_escrita <brief> → só a narrativa (pula o cabeçalho <!-- ... -->)
narrativa_escrita() {
  awk 'skip==1 { print; next } /^-->$/ { skip=1 }' "$1"
}

# ---------------------------------------------------------------------------
echo "-- 34 KB grava INTEIRO via --file (Prova 1)"
# ---------------------------------------------------------------------------
MARK34F="MARCA-FINAL-34K-FILE-$$"
IN34F="$tmp/in-34k-file.txt"
gen_narrative $((34*1024)) "$MARK34F" "$IN34F"
in_bytes=$(wc -c < "$IN34F" | tr -d ' ')

out=$("$BIN" brief --write --file "$IN34F" --session s34f --project "$PROJ" 2>&1); rc=$?
chk "--file 34KB → exit 0" "$rc" "0"
BF=$("$BIN" brief --path --project "$PROJ")
written=$(narrativa_escrita "$BF")
input=$(cat "$IN34F")
out_bytes=$(printf '%s' "$written" | wc -c | tr -d ' ')
printf 'PROVA-1: entrada=%sB gravado=%sB (--file)\n' "$in_bytes" "$out_bytes"
[[ "$input" == "$written" ]] && ok "--file: narrativa gravada é byte-idêntica à entrada" \
  || bad "--file: narrativa gravada é byte-idêntica à entrada"
last_line=$(tail -1 "$BF")
chk "--file: última linha do arquivo é a última linha da entrada" "$last_line" "$MARK34F"

# ---------------------------------------------------------------------------
echo "-- 34 KB grava INTEIRO via stdin (Prova 1)"
# ---------------------------------------------------------------------------
MARK34S="MARCA-FINAL-34K-STDIN-$$"
IN34S="$tmp/in-34k-stdin.txt"
gen_narrative $((34*1024)) "$MARK34S" "$IN34S"
in_bytes=$(wc -c < "$IN34S" | tr -d ' ')

out=$("$BIN" brief --write --session s34s --project "$PROJ" < "$IN34S" 2>&1); rc=$?
chk "stdin 34KB → exit 0" "$rc" "0"
BF=$("$BIN" brief --path --project "$PROJ")
written=$(narrativa_escrita "$BF")
input=$(cat "$IN34S")
out_bytes=$(printf '%s' "$written" | wc -c | tr -d ' ')
printf 'PROVA-1: entrada=%sB gravado=%sB (stdin)\n' "$in_bytes" "$out_bytes"
[[ "$input" == "$written" ]] && ok "stdin: narrativa gravada é byte-idêntica à entrada" \
  || bad "stdin: narrativa gravada é byte-idêntica à entrada"
last_line=$(tail -1 "$BF")
chk "stdin: última linha do arquivo é a última linha da entrada" "$last_line" "$MARK34S"

# ---------------------------------------------------------------------------
echo "-- leitura (maestro brief) devolve o brief de 34KB inteiro, última seção incluída (Prova 4)"
# ---------------------------------------------------------------------------
read_out=$("$BIN" brief --project "$PROJ" 2>&1)
grep -q "$MARK34S" <<<"$read_out" \
  && ok "leitura devolve a última linha do brief de 34KB" \
  || bad "leitura devolve a última linha do brief de 34KB"

# ---------------------------------------------------------------------------
echo "-- acima de 64 KiB → recusa explícita, NADA gravado (Prova 2)"
# ---------------------------------------------------------------------------
# brief anterior de referência: o de 34KB via stdin, ainda em disco
BF=$("$BIN" brief --path --project "$PROJ")
sha_antes=$(sha256sum "$BF" | awk '{print $1}')

OVER_BYTES=$((70000))
MARKOVER="MARCA-NUNCA-DEVE-APARECER-$$"
INOVER="$tmp/in-over.txt"
gen_narrative "$OVER_BYTES" "$MARKOVER" "$INOVER"
over_in_bytes=$(wc -c < "$INOVER" | tr -d ' ')

# --file
out=$("$BIN" brief --write --file "$INOVER" --session sover --project "$PROJ" 2>&1); rc_file=$?
printf 'PROVA-2 (--file): entrou=%sB teto=65536B excedeu=%sB rc=%s msg=%q\n' \
  "$over_in_bytes" "$((over_in_bytes - 65536))" "$rc_file" "$out"
[[ "$rc_file" -ne 0 ]] && ok "--file acima de 64KiB → rc != 0" || bad "--file acima de 64KiB → rc != 0 (rc=$rc_file)"
grep -q "$over_in_bytes" <<<"$out" && ok "--file: mensagem cita bytes de entrada ($over_in_bytes)" \
  || bad "--file: mensagem cita bytes de entrada ($over_in_bytes) ($out)"
grep -q '65536' <<<"$out" && ok "--file: mensagem cita o teto (65536)" \
  || bad "--file: mensagem cita o teto (65536) ($out)"
grep -q "$((over_in_bytes - 65536))" <<<"$out" && ok "--file: mensagem cita quanto excedeu" \
  || bad "--file: mensagem cita quanto excedeu ($out)"
sha_depois_file=$(sha256sum "$BF" | awk '{print $1}')
chk "--file acima de 64KiB: brief anterior INALTERADO (sha256)" "$sha_depois_file" "$sha_antes"
grep -q "$MARKOVER" "$BF" 2>/dev/null && bad "--file: marcador da recusa não deveria estar no brief" \
  || ok "--file: marcador da recusa não está no brief (nada gravado)"

# stdin
out=$("$BIN" brief --write --session sover2 --project "$PROJ" < "$INOVER" 2>&1); rc_stdin=$?
printf 'PROVA-2 (stdin): entrou=%sB teto=65536B excedeu=%sB rc=%s msg=%q\n' \
  "$over_in_bytes" "$((over_in_bytes - 65536))" "$rc_stdin" "$out"
[[ "$rc_stdin" -ne 0 ]] && ok "stdin acima de 64KiB → rc != 0" || bad "stdin acima de 64KiB → rc != 0 (rc=$rc_stdin)"
grep -q "$over_in_bytes" <<<"$out" && ok "stdin: mensagem cita bytes de entrada ($over_in_bytes)" \
  || bad "stdin: mensagem cita bytes de entrada ($over_in_bytes) ($out)"
grep -q '65536' <<<"$out" && ok "stdin: mensagem cita o teto (65536)" \
  || bad "stdin: mensagem cita o teto (65536) ($out)"
grep -q "$((over_in_bytes - 65536))" <<<"$out" && ok "stdin: mensagem cita quanto excedeu" \
  || bad "stdin: mensagem cita quanto excedeu ($out)"
sha_depois_stdin=$(sha256sum "$BF" | awk '{print $1}')
chk "stdin acima de 64KiB: brief anterior INALTERADO (sha256)" "$sha_depois_stdin" "$sha_antes"

# ---------------------------------------------------------------------------
echo "-- 16 KB (abaixo do teto antigo) continua gravando igual — sem regressão (Prova 3)"
# ---------------------------------------------------------------------------
MARK16="MARCA-FINAL-16K-$$"
IN16="$tmp/in-16k.txt"
gen_narrative $((16*1024)) "$MARK16" "$IN16"
in16_bytes=$(wc -c < "$IN16" | tr -d ' ')

out=$("$BIN" brief --write --file "$IN16" --session s16 --project "$PROJ" 2>&1); rc=$?
chk "--file 16KB → exit 0" "$rc" "0"
BF=$("$BIN" brief --path --project "$PROJ")
written=$(narrativa_escrita "$BF")
input=$(cat "$IN16")
[[ "$input" == "$written" ]] && ok "16KB via --file: gravado igual, sem regressão" \
  || bad "16KB via --file: gravado igual, sem regressão"
last_line=$(tail -1 "$BF")
chk "16KB: última linha preservada" "$last_line" "$MARK16"

out=$("$BIN" brief --write --session s16b --project "$PROJ" < "$IN16" 2>&1); rc=$?
chk "stdin 16KB → exit 0" "$rc" "0"
BF=$("$BIN" brief --path --project "$PROJ")
written=$(narrativa_escrita "$BF")
[[ "$input" == "$written" ]] && ok "16KB via stdin: gravado igual, sem regressão" \
  || bad "16KB via stdin: gravado igual, sem regressão"

# ---------------------------------------------------------------------------
echo "-- fronteira EXATA: 65536B grava, 65537B recusa (os dois canais)"
# ---------------------------------------------------------------------------
# gen_narrative preenche por LINHA inteira e não acerta o byte exato; a
# fronteira precisa de tamanho exato, senão o teste passa sem provar o limite.
mk_exact() { # mk_exact <bytes> <arquivo> — arquivo com exatamente N bytes
  local n="$1" out="$2"
  yes 'filler-0123456789-abcdefghijklmnopqrstuvwxyz' 2>/dev/null | head -c "$n" > "$out"
  local got; got=$(wc -c < "$out" | tr -d ' ')
  [[ "$got" == "$n" ]] || { bad "fixture de $n bytes saiu com $got"; return 1; }
}

IN_EQ="$tmp/in-eq-65536.txt"
mk_exact 65536 "$IN_EQ"
out=$("$BIN" brief --write --file "$IN_EQ" --session seq --project "$PROJ" 2>&1); rc=$?
chk "65536B (o teto) via --file grava" "$rc" "0"
out=$("$BIN" brief --write --session seqs --project "$PROJ" < "$IN_EQ" 2>&1); rc=$?
chk "65536B (o teto) via stdin grava" "$rc" "0"

# o brief válido de 65536B é o estado que a recusa NÃO pode danificar
BF=$("$BIN" brief --path --project "$PROJ")
sha_antes=$(sha256sum "$BF" | cut -d' ' -f1)

IN_OVER="$tmp/in-eq-65537.txt"
mk_exact 65537 "$IN_OVER"
out=$("$BIN" brief --write --file "$IN_OVER" --session sov --project "$PROJ" 2>&1); rc=$?
chk "65537B (teto+1) via --file recusa" "$([[ $rc -ne 0 ]] && echo sim || echo nao)" "sim"
grep -q '65537' <<<"$out" && ok "teto+1: mensagem cita a entrada (65537)" \
  || bad "teto+1: mensagem cita a entrada (65537) ($out)"
grep -q '65536' <<<"$out" && ok "teto+1: mensagem cita o teto (65536)" \
  || bad "teto+1: mensagem cita o teto (65536) ($out)"
grep -qE '(por|excedeu)[^0-9]*1 byte' <<<"$out" && ok "teto+1: mensagem cita o excesso de 1 byte" \
  || bad "teto+1: mensagem cita o excesso de 1 byte ($out)"
out=$("$BIN" brief --write --session sovs --project "$PROJ" < "$IN_OVER" 2>&1); rc=$?
chk "65537B (teto+1) via stdin recusa" "$([[ $rc -ne 0 ]] && echo sim || echo nao)" "sim"

sha_depois=$(sha256sum "$BF" | cut -d' ' -f1)
chk "as duas recusas na fronteira não tocam o brief de 65536B" "$sha_depois" "$sha_antes"

exit $fail
