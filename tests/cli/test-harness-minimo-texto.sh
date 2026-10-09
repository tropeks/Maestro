#!/usr/bin/env bash
# ordem 077 — tools/harness-minimo/texto-da-ordem: prompt-1 é a ordem INTEIRA; prompt-2 é a MESMA ordem
# sem os blocos do método; tudo o que sobra coincide byte a byte; e o corte NÃO remove o critério de
# pronto (o comando do recibo aparece em prompt-2, como instrução). Fixture sintética + a 054 real do git.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/harness-minimo/texto-da-ordem"
EXTRAI="$REPO/tools/harness-minimo/extrair-ordem.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

[[ -x "$TOOL" ]] || { bad "texto-da-ordem não existe ou não é executável"; exit 1; }

ORD="$tmp/ordem.md"
cat > "$ORD" <<'EOF'
<!-- maestro-order v1
id: 900
-->
# Ordem 900 — fixture

## Por quê

O teste X quebra. Conserte.

## O que entrega

1. Reproduzir o FAIL.
2. Prova com `maestro evidence --record --label order-900 -- suite`
   e o recibo gravado.
3. Corrigir o teste.

## Prova exigida

- A suíte sai 0 depois.
- Recibo `order-900`; `habits` dentro da catraca.
- Relato por `director_report` com o sha.

## Turno

- fatia: diagnosticar
- teto: 4

> **Execução headless:** cada turno é um `claude -p` novo.
> Segunda linha do mesmo bloco.

> **Log:** vai para a pasta temporária.

## Contrato de execução
- Trabalhe APENAS no branch `order/900-x`.
- O aceite é do diretor: `maestro order --accept 900`.
EOF

OUT="$tmp/saida"
bash "$TOOL" "$ORD" "$OUT" "bash tests/run-all.sh" > "$tmp/diff.out"
rc=$?
[[ $rc -eq 0 ]] && ok "gera os dois prompts (rc 0)" || { bad "texto-da-ordem saiu $rc"; exit 1; }

cmp -s "$ORD" "$OUT/prompt-1.md" && ok "prompt-1 é a ordem inteira, byte a byte" || bad "prompt-1 difere da ordem"

for cortado in '## Turno' 'Execução headless' 'Segunda linha do mesmo bloco' 'Log:' '## Contrato de execução' 'maestro order --accept' \
               'maestro evidence' 'e o recibo gravado' 'director_report' 'habits' 'fatia: diagnosticar'; do
  grep -qF -- "$cortado" "$OUT/prompt-2.md" && bad "prompt-2 ainda tem: $cortado" || ok "prompt-2 não tem: $cortado"
done
for mantido in '# Ordem 900' '## Por quê' 'O teste X quebra. Conserte.' '1. Reproduzir o FAIL.' '3. Corrigir o teste.' \
               '- A suíte sai 0 depois.' '<!-- maestro-order v1'; do
  grep -qF -- "$mantido" "$OUT/prompt-2.md" && ok "prompt-2 mantém: $mantido" || bad "prompt-2 perdeu: $mantido"
done

# o critério de pronto sobrevive ao corte e é INSTRUÇÃO
grep -qF 'Rode `bash tests/run-all.sh` na raiz do repositório e termine quando sair 0.' "$OUT/prompt-2.md" \
  && ok "o comando do recibo aparece em prompt-2, escrito como instrução" || bad "critério de pronto ausente de prompt-2"
grep -qF 'bash tests/run-all.sh' "$OUT/prompt-1.md" && bad "prompt-1 ganhou o critério (devia ser a ordem pura)" || ok "prompt-1 não recebe o critério extra"

# byte a byte fora dos blocos cortados: tirando a seção final, prompt-2 só PERDE linhas em relação ao prompt-1
total=$(wc -l < "$OUT/prompt-2.md")
corpo="$tmp/corpo2.md"
head -n "$((total - 4))" "$OUT/prompt-2.md" > "$corpo"
if diff "$corpo" "$OUT/prompt-1.md" | grep -q '^<'; then bad "prompt-2 tem linha que NÃO está no prompt-1 (fora do critério)"; else ok "fora dos blocos cortados, prompt-2 coincide byte a byte com prompt-1 (só perde linhas)"; fi
diff "$OUT/prompt-1.md" "$OUT/prompt-2.md" > "$tmp/diff.re"
cmp -s "$tmp/diff.re" "$OUT/prompt.diff" && ok "prompt.diff é o diff dos dois" || bad "prompt.diff difere do diff real"
cmp -s "$tmp/diff.out" "$OUT/prompt.diff" && ok "o diff também sai em stdout" || bad "stdout difere do prompt.diff"

# prefixo comum: idêntico no começo dos dois
bash "$TOOL" "$ORD" "$tmp/saida-p" "bash tests/run-all.sh" "Faça o reparo completo." >/dev/null
[[ "$(head -n 1 "$tmp/saida-p/prompt-1.md")" == "Faça o reparo completo." && "$(head -n 1 "$tmp/saida-p/prompt-2.md")" == "Faça o reparo completo." ]] \
  && ok "o prefixo comum abre os DOIS prompts" || bad "prefixo comum ausente de um dos prompts"

# negativos
bash "$TOOL" "$tmp/nao-existe.md" "$tmp/o2" "x" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "ordem inexistente é recusada (rc 2)" || bad "ordem inexistente aceita (rc $rc)"
bash "$TOOL" "$ORD" "$tmp/o3" "" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "recibo vazio é recusado (rc 2)" || bad "recibo vazio aceito (rc $rc)"

# a 054 REAL (commit da ordem no git): o corte tira o Turno e o Contrato, e o comando da suíte continua lá
if git -C "$REPO" cat-file -e 89be67f:.maestro/orders/054-reparo-dos-8-fail-preexistentes-da-main.md 2>/dev/null; then
  bash "$EXTRAI" "$REPO" 89be67f .maestro/orders/054-reparo-dos-8-fail-preexistentes-da-main.md "$tmp/054.md" || bad "extrair-ordem falhou"
  bash "$TOOL" "$tmp/054.md" "$tmp/o054" "bash tests/run-all.sh" >/dev/null
  grep -qF '## Turno' "$tmp/o054/prompt-2.md" && bad "054: prompt-2 ainda tem o Turno" || ok "054: prompt-2 sem o Turno"
  grep -qF 'Contrato de execução' "$tmp/o054/prompt-2.md" && bad "054: prompt-2 ainda tem o Contrato" || ok "054: prompt-2 sem o Contrato"
  grep -qF 'maestro evidence' "$tmp/o054/prompt-2.md" && bad "054: prompt-2 ainda cita maestro evidence" || ok "054: prompt-2 sem maestro evidence"
  grep -qF 'bash tests/run-all.sh' "$tmp/o054/prompt-2.md" && ok "054: o comando do recibo está em prompt-2" || bad "054: recibo ausente de prompt-2"
  grep -qF 'Saída colada dos 8 FAIL' "$tmp/o054/prompt-2.md" && ok "054: a prova exigida de conteúdo (8 FAIL antes/depois) fica" || bad "054: prova de conteúdo foi cortada"
else
  printf 'skip 054 real: commit 89be67f ausente neste clone\n'
fi

exit $fail
