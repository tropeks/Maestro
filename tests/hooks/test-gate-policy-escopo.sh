#!/usr/bin/env bash
# E26 / S-2601 — a política do gate deixa de ser um arquivo global.
#
# O buraco: `pre-tool-gate.sh` SEMPRE leu `${MAESTRO_GATE_POLICY:-$MAESTRO_HOME/
# gate-policy.sh}`, mas o `session-start.sh` gravava sempre no caminho fixo. Com duas
# sessões vivas na mesma máquina — que é o desenho de N gerentes —, abrir a sessão do
# projeto B sobrescrevia a política da sessão do projeto A: modo do gate, zonas
# congeladas da ordem em execução e a raiz do plugin. A partir dali A era policiada
# pelas regras de B, em silêncio.
#
# O que este teste protege:
#  1. sem a variável, o caminho e o conteúdo são EXATAMENTE os de antes (nenhuma
#     instalação existente muda de comportamento por atualizar);
#  2. com a variável, cada sessão tem o seu arquivo e uma não toca no da outra;
#  3. valor torto degrada para o padrão em vez de espalhar arquivo pelo disco;
#  4. o temporário é irmão do destino (mv atômico exige o mesmo sistema de arquivos)
#     e não sobra lixo.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

H="$SANDBOX/home"
PA="$SANDBOX/alpha"; PB="$SANDBOX/beta"
mkdir -p "$H" "$PA" "$PB"
printf 'project: alpha\nexperts: [qa]\n'      >"$PA/.maestro.yaml"
printf 'project: beta\nexperts: [revisor]\n'  >"$PB/.maestro.yaml"

# run <session_id> <projeto> [VAR=VAL ...]
run() {
  local sid="$1" proj="$2"; shift 2
  printf '{"session_id":"%s"}' "$sid" \
    | env MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$proj" MAESTRO_NO_UPDATE_CHECK=1 "$@" \
      bash "$HOOK" >/dev/null 2>"$SANDBOX/err"
  return 0
}

echo "-- 1. sem a variável: nada muda"
run s1 "$PA"
[[ -f "$H/gate-policy.sh" ]] \
  && ok "grava no caminho de sempre" || bad "grava no caminho de sempre"
grep -q '^MAESTRO_GATE_MODE=' "$H/gate-policy.sh" \
  && ok "com o conteúdo de sempre" || bad "com o conteúdo de sempre"

echo "-- 2. com a variável: uma sessão não escreve na política da outra"
PAF="$H/gate-policy-alpha.sh"; PBF="$H/gate-policy-beta.sh"
run s2 "$PA" MAESTRO_GATE_POLICY="$PAF"
before=$(cat "$PAF" 2>/dev/null)
run s3 "$PB" MAESTRO_GATE_POLICY="$PBF"
[[ -f "$PAF" && -f "$PBF" ]] \
  && ok "cada sessão tem o seu arquivo" || bad "cada sessão tem o seu arquivo"
[[ "$(cat "$PAF")" == "$before" ]] \
  && ok "a sessão de beta NÃO tocou na política de alpha (o bug que motivou o teste)" \
  || bad "a política de alpha mudou quando beta abriu"
# O default continua existindo e intocado por quem declarou caminho próprio.
[[ -f "$H/gate-policy.sh" ]] \
  && ok "o arquivo padrão sobrevive ao lado dos escopados" || bad "arquivo padrão sumiu"

echo "-- 3. o gate LÊ o arquivo escopado (o contrato é entre os dois hooks)"
GATE="$REPO/hooks/pre-tool-gate.sh"
sed -i 's/^MAESTRO_GATE_MODE=.*/MAESTRO_GATE_MODE="block"/' "$PAF"
sed -i 's/^MAESTRO_GATE_MODE=.*/MAESTRO_GATE_MODE="warn"/'  "$PBF"
gate_rc() { # gate_rc <arquivo de política> → rc do hook sem decision record
  printf '{"session_id":"nao-existe","tool_name":"Edit","tool_input":{"file_path":"%s/x.go"}}' "$PA" \
    | env MAESTRO_HOME="$H" CLAUDE_PROJECT_DIR="$PA" MAESTRO_GATE_POLICY="$1" \
      bash "$GATE" >/dev/null 2>&1
  printf '%s' "$?"
}
rc_block=$(gate_rc "$PAF"); rc_warn=$(gate_rc "$PBF")
[[ "$rc_block" != "$rc_warn" ]] \
  && ok "políticas diferentes produzem gates diferentes (block=$rc_block warn=$rc_warn)" \
  || bad "o gate ignorou o arquivo escopado (ambos rc=$rc_block)"

echo "-- 4. valor torto degrada para o padrão, sem espalhar arquivo"
for bad_val in "relativo.sh" "/com espaco/p.sh" "/" "" ; do
  run s4 "$PA" MAESTRO_GATE_POLICY="$bad_val"
done
[[ ! -e "$SANDBOX/relativo.sh" && ! -e "$REPO/relativo.sh" && ! -e "$H/relativo.sh" ]] \
  && ok "caminho relativo recusado (nada escrito fora do esperado)" \
  || bad "caminho relativo virou arquivo"
n=$(find "$SANDBOX" -maxdepth 3 -name 'gate-policy*.sh' | wc -l | tr -d ' ')
[[ "$n" -eq 3 ]] \
  && ok "seguem exatamente 3 políticas (padrão + alpha + beta)" \
  || bad "número de políticas inesperado: $n"

echo "-- 5. diretório novo é criado; temporário não vaza"
run s5 "$PB" MAESTRO_GATE_POLICY="$H/sub/dir/politica.sh"
[[ -f "$H/sub/dir/politica.sh" ]] \
  && ok "cria o diretório do caminho declarado" || bad "não criou o diretório"
t=$(find "$SANDBOX" -name '*.tmp' | wc -l | tr -d ' ')
[[ "$t" -eq 0 ]] && ok "nenhum temporário sobrou" || bad "sobraram $t temporário(s)"

echo
[[ $fail -eq 0 ]] && echo "test-gate-policy-escopo: OK" || echo "test-gate-policy-escopo: FALHAS" >&2
exit $fail
