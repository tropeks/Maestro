#!/usr/bin/env bash
# ordem 061 — docs/INVENTARIO-CONTROLES.md: uma linha por controle, com custo e ganho medidos.
# Confere: (1) o documento existe e a tabela cobre o universo declarado na ordem (hooks de
# hooks/hooks.json, guardas, sensores de config/habit-guides, verificações); (2) as seis colunas
# estão preenchidas e célula sem fonte é exatamente `sem fonte`; (3) só inteiros; (4) a lista
# proposta aponta para linhas da tabela, usa sai | vira opcional | fica e traz os três candidatos
# de partida; (5) SÓ LEITURA: o hash de hooks/ lib/ bin/ src/ config/ .claude-plugin/ não muda.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DOC="$REPO/docs/INVENTARIO-CONTROLES.md"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tree_hash() {
  ( cd "$REPO" && find hooks lib bin src config .claude-plugin -type f 2>/dev/null | LC_ALL=C sort \
      | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1 )
}
HASH_ANTES=$(tree_hash)

[[ -f "$DOC" ]] || { bad "docs/INVENTARIO-CONTROLES.md não existe"; exit 1; }
ok "docs/INVENTARIO-CONTROLES.md existe"

# --- tabela: linhas de dados entre o cabeçalho `| controle |` e a primeira linha não-tabela
mapfile -t ROWS < <(awk '
  /^\| controle \|/ { on = 1; next }
  on && /^\|[-| ]+\|$/ { next }
  on && /^\|/ { print; next }
  on { exit }' "$DOC")
(( ${#ROWS[@]} > 0 )) && ok "tabela encontrada (${#ROWS[@]} linhas)" || { bad "tabela sem linhas de dados"; exit 1; }

col() { # <linha> <n> → célula n (1-based) sem espaços nas pontas
  awk -F'|' -v n="$2" '{ c = $(n + 1); gsub(/^ +| +$/, "", c); print c }' <<<"$1"
}
NAMES=()
for r in "${ROWS[@]}"; do NAMES+=("$(col "$r" 1)"); done
has_name() { local n; for n in "${NAMES[@]}"; do [[ "$n" == "$1" ]] && return 0; done; return 1; }

# --- seis colunas, nenhuma vazia
nbad=0
for r in "${ROWS[@]}"; do
  ncol=$(awk -F'|' '{ print NF - 2 }' <<<"$r")
  [[ "$ncol" -eq 6 ]] || { bad "linha com $ncol colunas (esperado 6): ${r:0:60}"; nbad=1; continue; }
  for i in 1 2 3 4 5 6; do
    [[ -n "$(col "$r" "$i")" ]] || { bad "célula vazia (col $i): $(col "$r" 1)"; nbad=1; }
  done
done
(( nbad == 0 )) && ok "seis colunas preenchidas em todas as linhas"

# --- gramática das células
SF='sem fonte'
nbad=0
for r in "${ROWS[@]}"; do
  n=$(col "$r" 1); ef=$(col "$r" 2); di=$(col "$r" 3); cu=$(col "$r" 4); ga=$(col "$r" 5); pr=$(col "$r" 6)
  [[ "$ef" =~ ^(bloqueia|avisa|registra)\  ]] || { bad "$n: efeito deve começar com bloqueia|avisa|registra"; nbad=1; }
  # disparos: `sem fonte` ou  L=<int|sem fonte> T=<int|sem fonte> [<data>..<data>]
  if [[ "$di" != "$SF" && ! "$di" =~ ^L=([0-9]+|sem\ fonte)\ T=([0-9]+|sem\ fonte)(\ [0-9]{4}-[0-9]{2}-[0-9]{2}\.\.[0-9]{4}-[0-9]{2}-[0-9]{2})?$ ]]; then
    bad "$n: disparos fora da gramática ($di)"; nbad=1; fi
  # custo: `sem fonte` ou  t=<int>ms|sem fonte m=<int>p/<int>c|sem fonte
  if [[ "$cu" != "$SF" && ! "$cu" =~ ^t=([0-9]+ms|sem\ fonte)\ m=([0-9]+p/[0-9]+c|sem\ fonte)$ ]]; then
    bad "$n: custo fora da gramática ($cu)"; nbad=1; fi
  [[ "$ga" =~ ^(sim\ —\ .+|sem\ evidência)$ ]] || { bad "$n: ganho deve ser 'sim — <evidência>' ou 'sem evidência'"; nbad=1; }
  [[ "$pr" =~ ^(sai|vira\ opcional|fica)\ —\ .+ ]] || { bad "$n: proposta deve ser sai|vira opcional|fica — <motivo>"; nbad=1; }
  # só inteiros: nenhum decimal em nenhuma célula
  if grep -qE '[0-9][.,][0-9]' <<<"$r"; then bad "$n: número não inteiro na linha"; nbad=1; fi
  # logs só metadados: sem caminho absoluto
  if grep -qE '(^|[ (])/(home|tmp|root|Users)/' <<<"$r"; then bad "$n: caminho completo na linha"; nbad=1; fi
done
(( nbad == 0 )) && ok "gramática: efeito, disparos, custo, ganho, proposta; só inteiros; sem caminho completo"

# --- universo 1: hooks de hooks/hooks.json (a contagem bate)
mapfile -t HOOKS < <(jq -r '.hooks[][].hooks[].command' "$REPO/hooks/hooks.json" | sed 's#.*/##; s#\.sh$##' | sort -u)
nrow_hooks=0; for n in "${NAMES[@]}"; do [[ "$n" == hook:* ]] && nrow_hooks=$((nrow_hooks + 1)); done
[[ "${#HOOKS[@]}" -eq "$nrow_hooks" ]] \
  && ok "hooks: ${#HOOKS[@]} em hooks.json = $nrow_hooks linhas hook:" \
  || bad "hooks: hooks.json tem ${#HOOKS[@]}, a tabela tem $nrow_hooks linhas hook:"
for h in "${HOOKS[@]}"; do has_name "hook:$h" || bad "falta a linha hook:$h"; done

# --- universo 2: guardas
for g in guarda:self_paths-write-edit guarda:self_paths-bash guarda:destrutiva guarda:gate-de-decisao \
         guarda:politica-compilada guarda:consent guarda:gate-plan guarda:gate-ship guarda:kill-switch; do
  has_name "$g" && ok "linha $g" || bad "falta a linha $g"
done

# --- universo 3: sensores (um por guia em config/habit-guides) e a catraca
for f in "$REPO"/config/habit-guides/*.md; do
  s=$(basename "$f" .md)
  has_name "sensor:$s" && ok "linha sensor:$s" || bad "falta a linha sensor:$s"
done
has_name "sensor:catraca-baseline" && ok "linha sensor:catraca-baseline" || bad "falta a linha sensor:catraca-baseline"

# --- universo 4: verificações
for v in verificacao:por-area-E23b verificacao:recibos-de-evidencia verificacao:aceite-direcao-E22 \
         verificacao:aceite-prova-ed25519 verificacao:aceite-validacao-050 verificacao:conform-check \
         verificacao:doctor verificacao:evals; do
  has_name "$v" && ok "linha $v" || bad "falta a linha $v"
done

# --- os três candidatos de partida têm linha na tabela
for c in legado:teto-de-idade legado:deferred_by verificacao:por-area-E23b sensor:catraca-baseline; do
  has_name "$c" && ok "candidato com linha: $c" || bad "candidato sem linha: $c"
done

# --- lista proposta: `- \`<controle>\` — sai|vira opcional|fica — <motivo>`
mapfile -t PROP < <(awk '/^## Lista proposta/ { on = 1; next } on && /^## / { exit } on && /^- `/' "$DOC")
(( ${#PROP[@]} > 0 )) && ok "lista proposta (${#PROP[@]} itens)" || bad "lista proposta vazia"
nbad=0
for p in "${PROP[@]}"; do
  if [[ ! "$p" =~ ^-\ \`([^\`]+)\`\ —\ (sai|vira\ opcional|fica)\ —\ .+ ]]; then bad "item da lista fora do formato: ${p:0:70}"; nbad=1; continue; fi
  n="${BASH_REMATCH[1]}"; pv="${BASH_REMATCH[2]}"
  has_name "$n" || { bad "lista aponta para controle fora da tabela: $n"; nbad=1; continue; }
  # a proposta da lista é a mesma da coluna proposta da tabela
  for r in "${ROWS[@]}"; do
    [[ "$(col "$r" 1)" == "$n" ]] || continue
    [[ "$(col "$r" 6)" == "$pv"\ —* ]] || { bad "$n: lista diz '$pv', tabela diz '$(col "$r" 6)'"; nbad=1; }
  done
done
(( nbad == 0 )) && ok "cada item da lista aponta para uma linha da tabela, com a mesma proposta"
# toda linha da tabela entra na lista
for n in "${NAMES[@]}"; do
  grep -qF -- "- \`$n\` —" <<<"$(printf '%s\n' "${PROP[@]}")" || bad "controle fora da lista proposta: $n"
done
for c in legado:teto-de-idade legado:deferred_by verificacao:por-area-E23b sensor:catraca-baseline; do
  grep -qF -- "- \`$c\` —" <<<"$(printf '%s\n' "${PROP[@]}")" && ok "candidato com proposta: $c" || bad "candidato sem proposta: $c"
done

# --- achados e regra de honestidade presentes
grep -q '^## Achados' "$DOC" && ok "seção Achados" || bad "falta a seção Achados"
grep -q '^## Método' "$DOC" && ok "seção Método" || bad "falta a seção Método"

# --- só leitura
HASH_DEPOIS=$(tree_hash)
[[ "$HASH_ANTES" == "$HASH_DEPOIS" ]] && ok "só leitura: hash de hooks/ lib/ bin/ src/ config/ .claude-plugin/ igual antes e depois" \
  || bad "só leitura violada: hash de hooks/ lib/ bin/ src/ config/ .claude-plugin/ mudou"

exit "$fail"
