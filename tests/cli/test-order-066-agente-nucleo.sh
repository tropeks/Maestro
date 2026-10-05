#!/usr/bin/env bash
# ordem 066 (1) — o núcleo do `maestro agente`, SEM provedor real.
#   - os quatro perfis resolvem para as capacidades da tabela (adaptador FALSO as expõe);
#   - sem --perfil, perfil desconhecido e perfil vazio FALHAM FECHADO: erro lista os
#     perfis válidos e NADA é lançado (não existe perfil padrão);
#   - --dry-run imprime comando/ambiente/arquivos e NÃO executa;
#   - o núcleo (lib/cmd-agente.sh) e a declaração não contêm palavra do Claude Code;
#   - lançamento real (adaptador falso): args do provedor chegam, rc propaga, o log só
#     leva metadados (nunca argumento do provedor).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (esperado '$3', obtido '$2')"; fi; }

# provedor falso: registra que foi lançado e com que argumentos
mkdir -p "$tmp/bin"
ln -s "$REPO/tests/lib/provedor-falso.sh" "$tmp/bin/provedor-falso"
export PATH="$tmp/bin:$PATH"
export MAESTRO_AGENTE_ADAPTADOR_DIR="$REPO/tests/lib"
LANCOU="$tmp/lancou.args"
export FALSO_REGISTRO="$LANCOU"

A() { "$BIN" agente "$@"; }

# ---- o comando existe (vermelho antes: 'comando desconhecido')
out=$(A --help 2>&1); rc=$?
grep -q 'comando desconhecido' <<<"$out" && bad "o comando 'agente' não existe ($out)" || ok "comando 'agente' existe"

# ---- os quatro perfis → capacidades da tabela (via adaptador falso, --dry-run)
caps_de() { A --perfil "$1" --adaptador falso --dry-run 2>&1; }
expect_caps() { # perfil maestro ponte mcp plugins guardas segredos
  local p="$1" out
  out=$(caps_de "$p"); rc=$?
  chk "$p: dry-run rc 0" "$rc" "0"
  local want="maestro=$2 ponte=$3 mcp=$4 plugins=$5 guardas=$6 segredos=$7"
  grep -qF "capacidades: $want" <<<"$out" && ok "$p → $want" || bad "$p sem 'capacidades: $want' ($out)"
  grep -qF -- "--cap-maestro=$2" <<<"$out" && grep -qF -- "--cap-segredos=$7" <<<"$out" \
    && ok "$p: o adaptador recebeu as capacidades" || bad "$p: adaptador não recebeu as capacidades ($out)"
}
expect_caps dev      sim  envelope envelope envelope metodo   herda
expect_caps gerente  sim  sim      herdados herdados metodo   herda
expect_caps diretor  nao  sim      nenhum   nenhum   nenhuma  herda
expect_caps pesquisa nao  nao      nenhum   nenhum   nenhuma  nega
[[ -e "$LANCOU" ]] && bad "dry-run lançou o provedor" || ok "dry-run não executou nada (os quatro perfis)"

# ---- falha fechada: sem perfil, perfil desconhecido, perfil vazio — nada lança
for caso in "sem --perfil|--adaptador falso -- x" "perfil desconhecido|--perfil xyz --adaptador falso -- x" "perfil vazio|--perfil '' --adaptador falso -- x" "perfil sem valor|--perfil"; do
  nome="${caso%%|*}"; args="${caso#*|}"
  rm -f "$LANCOU"
  out=$(eval "A $args" 2>&1); rc=$?
  [[ $rc -ne 0 ]] && ok "$nome: rc != 0 ($rc)" || bad "$nome: saiu 0"
  for v in dev gerente diretor pesquisa; do
    grep -qw "$v" <<<"$out" || { bad "$nome: erro não lista o perfil '$v' ($out)"; break; }
  done
  [[ -e "$LANCOU" ]] && bad "$nome: LANÇOU o provedor" || ok "$nome: nada lançado"
done
# nenhum padrão que caia em "carrega tudo": --dry-run sem perfil também falha
out=$(A --dry-run --adaptador falso 2>&1); rc=$?
[[ $rc -ne 0 ]] && ok "dry-run sem perfil também falha fechado" || bad "dry-run sem perfil saiu 0 ($out)"

# ---- adaptador desconhecido: falha fechada
rm -f "$LANCOU"
out=$(A --perfil pesquisa --adaptador inexistente -- x 2>&1); rc=$?
[[ $rc -ne 0 && ! -e "$LANCOU" ]] && ok "adaptador desconhecido: falha e não lança" || bad "adaptador desconhecido não falhou fechado ($out)"

# ---- o núcleo não contém palavra do Claude Code
CORE="$REPO/lib/cmd-agente.sh"
if [[ -f "$CORE" ]]; then
  if grep -inE 'claude|anthropic|--settings|--bare|safe-mode|mcp-config|setting-sources|strict-mcp|CLAUDE_' "$CORE" >/dev/null; then
    bad "o núcleo contém palavra do Claude Code: $(grep -inE 'claude|anthropic|--settings|--bare|safe-mode|mcp-config|setting-sources|strict-mcp|CLAUDE_' "$CORE" | head -3 | tr '\n' '|')"
  else
    ok "o núcleo (lib/cmd-agente.sh) não contém palavra do Claude Code"
  fi
else
  bad "lib/cmd-agente.sh não existe"
fi
# a declaração fala em capacidades: nada de flag nem de palavra de provedor
# (a única menção é o NOME do adaptador padrão, que não é flag)
decl=$(grep -v '^#' "$REPO/config/perfis-agente.yaml" | grep -v '^adaptador_padrao:')
if grep -inE 'claude|anthropic|--[a-z]|settings|mcp-config' <<<"$decl" >/dev/null; then
  bad "a declaração tem flag/palavra de provedor"
else
  ok "a declaração só fala em capacidades"
fi

# ---- lançamento real (adaptador falso): args chegam, rc propaga, log só metadados
rm -f "$LANCOU"
FALSO_RC=7 A --perfil pesquisa --adaptador falso -- ARG-SENSIVEL-066 segundo >/dev/null 2>&1; rc=$?
chk "rc do provedor propaga" "$rc" "7"
grep -qx 'ARG-SENSIVEL-066' "$LANCOU" 2>/dev/null && grep -qx 'segundo' "$LANCOU" && ok "args depois de -- chegam ao provedor" || bad "args não chegaram ($(cat "$LANCOU" 2>/dev/null))"
logs=$(cat "$MAESTRO_HOME"/logs/agente* 2>/dev/null || true)
grep -q 'perfil=pesquisa' <<<"$logs" && grep -q 'adaptador=falso' <<<"$logs" && grep -q 'rc=7' <<<"$logs" && ok "log leva perfil, adaptador e rc" || bad "log sem metadados ($logs)"
grep -q 'ARG-SENSIVEL-066' <<<"$logs" && bad "log vazou argumento do provedor" || ok "log não leva argumento do provedor"

exit $fail
