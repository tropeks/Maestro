#!/usr/bin/env bash
# ordem 066 (3) — o perfil `pesquisa` nunca lê .env, chave nem ~/.ponte, e essa proteção
# vem da CONFIGURAÇÃO DO PRÓPRIO PERFIL — o plugin Maestro não carrega nesse perfil.
#   offline: o que o teste prova é a CONFIGURAÇÃO gerada (regras de negação cobrem os
#   arquivos da fixture, nenhum plugin é carregado) — não o enforcement do provedor.
#   O que não se prova offline vira LIMITE DECLARADO (impresso pelo adaptador e aqui).
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; export MAESTRO_HOME="$HOME/.maestro-home"
mkdir -p "$HOME/.ponte" "$tmp/proj/.maestro/credenciais" "$tmp/proj/sub"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# fixture: arquivos de segredo FALSOS (nada real)
printf 'TOKEN=falso\n' > "$tmp/proj/.env"
printf 'TOKEN=falso\n' > "$tmp/proj/sub/.env.local"
printf 'falso\n' > "$tmp/proj/chave.pem"
printf 'falso\n' > "$tmp/proj/sub/servidor.key"
printf 'falso\n' > "$tmp/proj/id_ed25519"
printf 'falso\n' > "$HOME/.ponte/mcp.sock"
printf 'falso\n' > "$tmp/proj/.maestro/credenciais/token"
printf 'ola\n' > "$tmp/proj/README.md"

out=$("$BIN" agente --perfil pesquisa --dry-run -- -p x 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "dry-run de pesquisa rc 0" || { bad "dry-run de pesquisa rc $rc ($out)"; exit 1; }

# 1) a negação vem por configuração do perfil (--settings inline), não pelo plugin
grep -q -- '--settings' <<<"$out" && ok "a negação viaja na configuração do perfil (--settings)" || bad "sem --settings no comando ($out)"
grep -qE -- '--plugin-dir|--plugin-url' <<<"$out" && bad "o perfil carrega plugin por flag" || ok "nenhum plugin carregado pelo perfil"
grep -qi 'maestro@' <<<"$out" && bad "o perfil referencia o plugin Maestro" || ok "a proteção não referencia o plugin Maestro"

# 2) extrai as regras de negação (uma por linha: 'deny: Read(...)') e confere a cobertura
mapfile -t regras < <(grep -E '^deny: ' <<<"$out" | sed 's/^deny: //')
[[ ${#regras[@]} -ge 7 ]] && ok "regras de negação presentes (${#regras[@]})" || bad "poucas regras de negação (${#regras[@]}): $out"

# casamento estilo gitignore/glob, só para a prova offline: Read(<padrão>) contra um caminho
casa() { # <regra> <caminho absoluto>
  local pad="${1#Read(}"; pad="${pad%)}" caminho="$2"
  if [[ "$pad" == '~/'* ]]; then pad="$HOME/${pad#\~/}"; fi
  if [[ "$pad" == '**/'* ]]; then
    local sufixo="${pad#\*\*/}"
    shopt -s extglob globstar
    # o padrão '**/x' casa x em qualquer profundidade: testa o caminho e cada sufixo dele
    local c="$caminho"
    while [[ -n "$c" ]]; do
      # shellcheck disable=SC2053
      [[ "$c" == $sufixo ]] && return 0
      [[ "$c" == */* ]] || break
      c="${c#*/}"
    done
    return 1
  fi
  shopt -s globstar
  # shellcheck disable=SC2053
  [[ "$caminho" == $pad ]]
}
coberto() { local r; for r in "${regras[@]}"; do [[ "$r" == Read\(* ]] && casa "$r" "$1" && return 0; done; return 1; }
for f in "$tmp/proj/.env" "$tmp/proj/sub/.env.local" "$tmp/proj/chave.pem" "$tmp/proj/sub/servidor.key" \
         "$tmp/proj/id_ed25519" "$HOME/.ponte/mcp.sock" "$tmp/proj/.maestro/credenciais/token"; do
  coberto "$f" && ok "negado: ${f#"$tmp"/}" || bad "NÃO coberto pelas regras: ${f#"$tmp"/}"
done
coberto "$tmp/proj/README.md" && bad "README.md coberto — regra larga demais" || ok "arquivo comum não é negado (README.md)"

# 3) o que só vale no perfil pesquisa: gerente/dev/diretor não ganham a negação
for p in gerente dev diretor; do
  o=$("$BIN" agente --perfil "$p" --dry-run -- -p x 2>&1)
  grep -q '^deny: ' <<<"$o" && bad "$p traz regras de negação (herda, não nega)" || ok "$p não traz a negação (segredos: herda)"
done

# 4) limites DECLARADOS (o que não cobre fica escrito, não fingido)
grep -q '^limite: .*Bash' <<<"$out" && ok "limite declarado: leitura por Bash/python/node" || bad "sem limite sobre leitura por Bash ($out)"
grep -q '^limite: .*enforcement' <<<"$out" && ok "limite declarado: enforcement do provedor não provado offline" || bad "sem limite sobre o enforcement ($out)"
printf 'LIMITES DECLARADOS:\n'; grep '^limite: ' <<<"$out" | sed 's/^/  /'

exit $fail
