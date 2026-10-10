#!/usr/bin/env bash
# ordem 067 item 1 — `maestro evidence --record` grava `regravacoes` no recibo: 0 na 1ª gravação, anterior+1
# nas seguintes (mesma label = mesmo arquivo <chave>-order-<n>); recibo velho SEM o campo conta como uma
# gravação anterior (grava 1); labels diferentes não se somam; o recibo cabe na janela de 20 linhas e
# _ev_read_vars / maestro_proof_verdict dão o mesmo veredito no recibo velho e no novo.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MAESTRO="$REPO/bin/maestro"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"
export CLAUDE_CODE_SESSION_ID="" MAESTRO_OFF=""
P="$tmp/proj"; mkdir -p "$P"
git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm base

# ordem 078: order-N só grava o comando declarado entre crases no fim: da ordem N (commit-base). As ordens 67
# e 68 são escritas à mão (o CLI numeraria 001, 002…) e declaram `true`, o comando que o teste grava.
BIN="$MAESTRO"
source "$REPO/tests/lib/declare-order.sh"
mkdir -p "$P/.maestro/orders"
for n in 067 068; do
  printf '<!-- maestro-order v1\nid: %s\nts: x\nepoch: 1790000000\n-->\n# ordem %s\n\n## Turno\n- fatia: t\n- fim: x\n- teto: 1\n- fora: nada\n- relatório: v54\n' "$n" "$n" > "$P/.maestro/orders/$n-x.md"
  declare_order "$P" "$n" true
done

rec() { (cd "$P" && "$MAESTRO" evidence --record --label "$1" -- true >/dev/null 2>&1); }
efile() { ls "$MAESTRO_HOME"/evidence/*-"$1" 2>/dev/null | head -1; }
field() { awk -F= -v k="$2" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$1"; }

rec order-67; f=$(efile order-67)
[[ -f "$f" && "$(field "$f" regravacoes)" == "0" ]] && ok "1ª gravação grava regravacoes=0" || bad "1ª gravação: '$(field "$f" regravacoes)'"
rec order-67
[[ "$(field "$f" regravacoes)" == "1" ]] && ok "2ª gravação da mesma label: 1" || bad "2ª: '$(field "$f" regravacoes)'"
rec order-67
[[ "$(field "$f" regravacoes)" == "2" ]] && ok "3ª gravação: 2" || bad "3ª: '$(field "$f" regravacoes)'"

rec order-68; g=$(efile order-68)
[[ "$(field "$g" regravacoes)" == "0" && "$(field "$f" regravacoes)" == "2" ]] \
  && ok "labels diferentes não se somam (order-68 nasce 0; order-67 segue 2)" || bad "labels: 68='$(field "$g" regravacoes)' 67='$(field "$f" regravacoes)'"

# recibo velho (15 campos, sem regravacoes) conta como uma gravação anterior
grep -v '^regravacoes=\|^tokens=\|^custo_centavos=\|^custo_fonte=' "$f" > "$tmp/velho"; cp "$tmp/velho" "$f"
rec order-67
[[ "$(field "$f" regravacoes)" == "1" ]] && ok "recibo velho sem o campo → regravacoes=1" || bad "velho: '$(field "$f" regravacoes)'"

# lixo no campo anterior (não inteiro) também conta como uma gravação anterior
{ cat "$tmp/velho"; printf 'regravacoes=muitas\n'; } > "$f"
rec order-67
[[ "$(field "$f" regravacoes)" == "1" ]] && ok "campo anterior inválido → 1 (nunca propaga lixo)" || bad "lixo: '$(field "$f" regravacoes)'"

# a janela de 20 linhas: os quatro campos novos ficam no fim, em ordem fixa, dentro da janela
total=$(wc -l < "$f")
(( total <= 20 )) && ok "recibo novo cabe nas 20 linhas ($total)" || bad "recibo com $total linhas (>20)"
[[ "$(grep -o '^[a-z_0-9]*=' "$f" | tail -5 | tr -d '=\n' )" == "probe_msregravacoestokenscusto_centavoscusto_fonte" ]] \
  && ok "campos novos no fim, em ordem fixa (regravacoes, tokens, custo_centavos, custo_fonte)" || bad "ordem dos campos: $(tail -5 "$f" | tr '\n' ' ')"
for k in regravacoes tokens custo_centavos custo_fonte; do
  awk -F= -v k="$k" 'NR<=20 && $1==k{f=1} END{exit !f}' "$f" || bad "campo $k fora da janela de 20 linhas"
done

# o leitor e o veredito dão o mesmo resultado no recibo velho e no novo
readvars() { ( REPO_DIR="$REPO"; source "$REPO/lib/core-evidence.sh" 2>/dev/null; _ev_read_vars "$1" ); }
# o mesmo recibo SEM os campos novos = o recibo velho (mesmo epoch, mesmas árvores)
grep -v '^regravacoes=\|^tokens=\|^custo_centavos=\|^custo_fonte=' "$f" > "$tmp/velho-igual"
[[ -n "$(readvars "$f")" ]] && ok "_ev_read_vars lê o recibo novo" || bad "_ev_read_vars vazio no recibo novo"
[[ "$(readvars "$f")" == "$(readvars "$tmp/velho-igual")" ]] \
  && ok "_ev_read_vars: variáveis idênticas no recibo velho e no novo" || bad "_ev_read_vars difere"
cp "$f" "$tmp/novo"
# maestro_proof_verdict (via evidence --check): mesmo veredito nos dois, no mesmo caminho do ledger
cp "$tmp/novo" "$f";        vn=$(cd "$P" && "$MAESTRO" evidence --label order-67 --check 2>&1); rn=$?
cp "$tmp/velho-igual" "$f"; vv=$(cd "$P" && "$MAESTRO" evidence --label order-67 --check 2>&1); rv=$?
[[ "$vn" == "$vv" && $rn -eq $rv ]] && ok "veredito (evidence --check) igual no recibo velho e no novo (rc=$rn)" || bad "veredito difere: novo='$vn'($rn) velho='$vv'($rv)"

exit $fail
