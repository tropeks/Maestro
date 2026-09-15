#!/usr/bin/env bash
# ordem 009 (E24) — O TESTE QUE PROVA A POSSE do formato do recibo.
#
# lib/core-evidence.sh virou o DONO do formato maestro-evidence-v1; lib/
# cmd-retro.sh deixou de reimplementar `grep -q '^exit=0$'` por conta própria
# e passou a chamar _ev_ledger_summary (que chama _ev_is_ok, que chama o
# leitor genérico _ev_field). Reorganizar arquivo com discurso de arquitetura
# NÃO é posse — só é posse de verdade se um campo NOVO no recibo (ou uma
# mudança na REGRA do que conta como "OK") chega ao retro SEM QUE O RETRO
# SEJA TOCADO. Duas provas, nessa ordem:
#
#   1) GENERICIDADE do leitor: um campo que NUNCA existiu no schema
#      (`retries_x100`) é lido por _ev_field sem nenhuma linha de código
#      saber o nome dele de antemão — não é lista de campos conhecidos.
#   2) POSSE DE VERDADE: redefinimos _ev_is_ok (o predicado de "recibo OK",
#      que mora em lib/core-evidence.sh, NUNCA em lib/cmd-retro.sh) para usar
#      esse campo novo. O número que _retro_evidence_signal imprime muda de
#      acordo — sem UMA LINHA de lib/cmd-retro.sh mudar. Se o retro tivesse
#      reimplementado a leitura (o defeito que abriu esta ordem), redefinir
#      _ev_is_ok não teria efeito nenhum sobre o que ele imprime.
#
# Teste NÃO exige os módulos já aplicados (lib/ está na denylist do gate de
# quem escreve o patch — bin/, hooks/, src/, lib/ só mudam por patch
# revisado). Ausente → PENDENTE, exit 0; presente → cobra as duas provas.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

if [[ ! -f "$REPO/lib/core-evidence.sh" || ! -f "$REPO/lib/cmd-retro.sh" ]]; then
  pending "ordem 009: lib/core-evidence.sh e/ou lib/cmd-retro.sh ainda não aplicados — aplicar docs/patches/009-*.patch"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
mkdir -p "$MAESTRO_HOME/evidence"

REPO_DIR="$REPO"
# shellcheck source=hooks/lib/common.sh
source "$REPO/hooks/lib/common.sh"
# shellcheck source=lib/core-evidence.sh
source "$REPO/lib/core-evidence.sh"
# shellcheck source=lib/cmd-retro.sh
source "$REPO/lib/cmd-retro.sh"

# ── fixture: um recibo comum + um recibo com campo que NUNCA existiu no schema ──
_ev_write "$MAESTRO_HOME/evidence/comum" suite hash1 0 abc abc free 150 4 0
_ev_write "$MAESTRO_HOME/evidence/com-campo-novo" suite hash2 0 abc abc free 150 4 0
# aditivo, no FIM (DATA_MODEL §8) — exatamente como load1m_x100/ncpu/inconclusive
# entraram na ordem 005: ninguém que já lia o recibo sabia deste campo.
printf 'retries_x100=250\n' >> "$MAESTRO_HOME/evidence/com-campo-novo"

echo "-- prova 1: o leitor é GENÉRICO, não uma lista de campos conhecidos"
v=$(_ev_field "$MAESTRO_HOME/evidence/com-campo-novo" retries_x100)
chk "_ev_field lê um campo que NUNCA existiu no schema, sem tocar o leitor" "$v" "250"
v2=$(_ev_field "$MAESTRO_HOME/evidence/comum" retries_x100)
chk "recibo sem o campo → vazio, sem crash" "$v2" ""

echo "-- baseline: o retro conta certo mesmo com o campo desconhecido presente"
out=$(_retro_evidence_signal)
grep -q '2 recibo(s) no ledger, 2 de exit 0' <<<"$out" \
  && ok "cobertura correta com um recibo carregando campo que o retro nunca viu" \
  || bad "cobertura errada ($out)"

echo "-- prova 2 (A POSSE): redefine a REGRA em core-evidence, NUNCA em cmd-retro"
# _ev_is_ok é o ÚNICO lugar que decide "o que conta como recibo OK" (é para
# isto que o dono do formato existe). Simulamos aqui o que a ordem 005 fez de
# verdade com `inconclusive`: o schema ganha um campo, e o schema PASSA A
# EXIGIR dele algo que os recibos antigos não tinham como cumprir.
_ev_is_ok() {
  local r; r=$(_ev_field "$1" retries_x100)
  [[ "$(_ev_field "$1" exit)" == "0" ]] && [[ -n "$r" ]] && (( r < 200 ))
}
out2=$(_retro_evidence_signal)
grep -q '2 recibo(s) no ledger, 0 de exit 0' <<<"$out2" \
  && ok "POSSE PROVADA: redefinir _ev_is_ok (dono: core-evidence) muda o número do retro SEM TOCAR lib/cmd-retro.sh" \
  || bad "retro não reagiu à regra nova — a leitura está reimplementada em algum lugar (posse nominal, não real) ($out2)"

# controle: se cmd-retro.sh tivesse sua própria cópia da regra (o defeito
# original desta ordem), o `sed` abaixo teria achado `grep`/`exit=0` no
# arquivo do retro; ele não deve ter NENHUMA menção crua ao formato do recibo.
if grep -v '^[[:space:]]*#' "$REPO/lib/cmd-retro.sh" | grep -qE "grep .*exit=0|'\\^exit=0"; then
  bad "lib/cmd-retro.sh ainda reimplementa a leitura do recibo (duplicação de conhecimento)"
else
  ok "lib/cmd-retro.sh não conhece o FORMATO do recibo — só chama o dono"
fi

exit $fail
