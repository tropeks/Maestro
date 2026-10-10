#!/usr/bin/env bash
# ordem 067 itens 1 e 2 — `maestro evidence --record` grava tokens, custo_centavos e custo_fonte no recibo, lendo
# SÓ inteiros do transcrito da sessão (fixture sintética, nunca real). Sem fonte → a palavra `ausente`, nunca 0,
# nunca estimativa, nunca soma parcial. Custo não altera o exit do comando provado nem imprime texto do transcrito.
#   tokens         = Σ input+output+cache_creation+cache_read das mensagens do assistente (id único), todas com usage inteiro
#   custo_centavos = Σ costUSD (por mensagem) arredondado meio-para-cima a centavos inteiros, só se TODAS trazem costUSD
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MAESTRO="$REPO/bin/maestro"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"
export MAESTRO_CLAUDE_PROJECTS="$tmp/claude-projects"
P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm base
TD="$MAESTRO_CLAUDE_PROJECTS/$(printf '%s' "$P" | sed 's/[^A-Za-z0-9]/-/g')"
SID=11111111-1111-4111-8111-111111111111
SEGREDO="SEGREDO-DO-TRANSCRITO-XYZ"

# msg <id> <in> <out> <cc> <cr> [costUSD|-]  → uma linha de assistente (cc/cr "-" = campo ausente)
msg() {
  local u="\"input_tokens\":$2,\"output_tokens\":$3"
  [[ "$4" == - ]] || u+=",\"cache_creation_input_tokens\":$4"
  [[ "$5" == - ]] || u+=",\"cache_read_input_tokens\":$5"
  local c=""; [[ "${6:--}" == - ]] || c=",\"costUSD\":$6"
  printf '{"type":"assistant","sessionId":"%s","message":{"id":"%s","content":[{"type":"text","text":"%s"}],"usage":{%s}}%s}\n' "$SID" "$1" "$SEGREDO" "$u" "$c"
}
fresh() { rm -rf "$TD" "$MAESTRO_HOME"/evidence; mkdir -p "$TD"; export CLAUDE_CODE_SESSION_ID="$SID"; unset MAESTRO_EVIDENCE_TRANSCRIPT_MAX_BYTES; }
rec() { # <label> [comando...] → grava; guarda stdout+stderr em $out e o rc em $rc
  local l="$1"; shift; [[ $# -gt 0 ]] || set -- true
  out=$(cd "$P" && "$MAESTRO" evidence --record --label "$l" -- "$@" 2>&1); rc=$?
}
efile() { ls "$MAESTRO_HOME"/evidence/*-"$1" 2>/dev/null | head -1; }
field() { awk -F= -v k="$2" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$1"; }
expect() { # <rótulo> <tokens> <centavos> <fonte>
  local f; f=$(efile "$L")
  if [[ "$(field "$f" tokens)" == "$2" && "$(field "$f" custo_centavos)" == "$3" && "$(field "$f" custo_fonte)" == "$4" ]]; then ok "$1"
  else bad "$1: tokens='$(field "$f" tokens)' custo_centavos='$(field "$f" custo_centavos)' custo_fonte='$(field "$f" custo_fonte)' (esperado $2/$3/$4)"; fi
}
L=custo-67   # ordem 078: rótulo livre (order-N só executa o fim: do baseline; aqui o rótulo é irrelevante ao custo)

# 1. usage e costUSD completos; a mesma mensagem em duas linhas (stream) conta UMA vez; 0,0025+0,0025 = meio centavo → 1
fresh; { msg m1 10 20 30 40 0.0025; msg m1 10 20 30 40 0.0025; msg m2 1 2 3 4 0.0025; } > "$TD/$SID.jsonl"
rec $L; expect "usage e costUSD completos: tokens 110 (dedupe por id), 0,005 USD → 1 centavo (meio para cima), fonte transcrito" 110 1 transcrito
f=$(efile $L); [[ "$(wc -l < "$f")" -le 20 ]] && ok "recibo com a fonte cabe nas 20 linhas ($(wc -l < "$f"))" || bad "recibo >20 linhas"
# arredondamento declarado: 0,0049 → 0 centavo (é inteiro 0 por conta, não ausência); 0,145 → 15 (armadilha de float binário)
fresh; msg m1 1 1 1 1 0.0049 > "$TD/$SID.jsonl"; rec $L; expect "0,0049 USD → 0 centavo (afirmação: custou < meio centavo)" 4 0 transcrito
fresh; msg m1 1 1 1 1 0.145 > "$TD/$SID.jsonl"; rec $L; expect "0,145 USD → 15 centavos (meio para cima, sem erro de float)" 4 15 transcrito
fresh; { msg m1 1 1 1 1 0.10; msg m2 1 1 1 1 0.20; } > "$TD/$SID.jsonl"; rec $L; expect "soma de duas mensagens: 0,30 USD → 30 centavos" 8 30 transcrito

# 2. sem costUSD (o caso real): tokens inteiro, centavos ausente, fonte transcrito (a fonte dos tokens)
fresh; msg m1 5 6 7 8 > "$TD/$SID.jsonl"; rec $L; expect "sem costUSD: tokens 26, custo_centavos ausente, fonte transcrito" 26 ausente transcrito

# 3. sem fonte: ausente em tudo, nunca 0
fresh; rm -rf "$TD"; rec $L; expect "sem transcrito: tudo ausente, nunca 0" ausente ausente ausente
fresh; printf 'isto não é json {{{\n' > "$TD/$SID.jsonl"; rec $L; expect "transcrito ilegível: tudo ausente" ausente ausente ausente
fresh; : > "$TD/$SID.jsonl"; rec $L; expect "transcrito vazio (sem usage): tudo ausente" ausente ausente ausente
fresh; msg m1 1 1 1 1 0.01 > "$TD/$SID.jsonl"; chmod 000 "$TD/$SID.jsonl"; rec $L
[[ "$(id -u)" == 0 ]] || expect "transcrito sem permissão de leitura: tudo ausente" ausente ausente ausente
chmod 644 "$TD/$SID.jsonl"
# duas sessões candidatas: sem a chave da sessão e com mais de um transcrito no diretório → ausente
fresh; unset CLAUDE_CODE_SESSION_ID; msg m1 1 1 1 1 0.01 > "$TD/aaaa.jsonl"; msg m2 1 1 1 1 0.01 > "$TD/bbbb.jsonl"; rec $L
expect "duas sessões candidatas (sem chave de sessão): tudo ausente" ausente ausente ausente
# sem chave de sessão e UM só transcrito: não há ambiguidade
fresh; unset CLAUDE_CODE_SESSION_ID; msg m1 1 1 1 1 0.01 > "$TD/aaaa.jsonl"; rec $L
expect "sem chave de sessão, um único transcrito: lê esse (4 tokens, 1 centavo)" 4 1 transcrito

# 4. parcial nunca entra
fresh; { msg m1 10 20 30 40 0.01; msg m2 1 2 3 - 0.01; } > "$TD/$SID.jsonl"; rec $L
expect "usage parcial (mensagem sem cache_read): tokens ausente, não soma parcial; costUSD completo segue 2 centavos" ausente 2 transcrito
fresh; { msg m1 10 20 30 40 0.01; msg m2 1 2 3 4; } > "$TD/$SID.jsonl"; rec $L
expect "costUSD parcial (uma mensagem sem): custo_centavos ausente, tokens 110 seguem" 110 ausente transcrito
fresh; { msg m1 10 20 30 40 0.01; msg m2 1 2.5 3 4 0.01; } > "$TD/$SID.jsonl"; rec $L
expect "usage não inteiro (2.5): tokens ausente" ausente 2 transcrito

# 5. piso de leitura: transcrito acima do piso não é lido (o --record não fica mais lento por custo)
fresh; msg m1 1 1 1 1 0.01 > "$TD/$SID.jsonl"; export MAESTRO_EVIDENCE_TRANSCRIPT_MAX_BYTES=10; rec $L
expect "transcrito acima do piso de bytes: tudo ausente, sem ler" ausente ausente ausente

# 6. custo não altera o exit nem imprime texto do transcrito; o campo `exit` do recibo é o do comando provado
fresh; msg m1 1 1 1 1 0.01 > "$TD/$SID.jsonl"; rec $L false
f=$(efile $L)
[[ $rc -eq 1 && "$(field "$f" exit)" == "1" ]] && ok "o --record sai com o exit do comando provado (1), custo não o altera" || bad "rc=$rc exit no recibo='$(field "$f" exit)'"
fresh; msg m1 1 1 1 1 0.01 > "$TD/$SID.jsonl"; rec $L bash -c 'exit 7'; [[ $rc -eq 7 ]] && ok "exit 7 do comando preservado" || bad "exit 7 → rc=$rc"
fresh; msg m1 1 1 1 1 0.01 > "$TD/$SID.jsonl"; rec $L
grep -q "$SEGREDO" <<<"$out" && bad "texto do transcrito apareceu na saída do --record" || ok "nenhum texto do transcrito na saída (stdout+stderr)"
f=$(efile $L)
grep -q "$SEGREDO" "$f" && bad "texto do transcrito no recibo" || ok "nenhum texto do transcrito no recibo"
if grep -rq "$SEGREDO" "$MAESTRO_HOME" 2>/dev/null; then bad "texto do transcrito em algum arquivo do MAESTRO_HOME (logs)"; else ok "nenhum texto do transcrito no MAESTRO_HOME (recibo e logs)"; fi
grep -qE '^(tokens|custo_centavos)=[0-9]+\.[0-9]' "$f" && bad "float no recibo" || ok "nenhum float no recibo"

exit $fail
