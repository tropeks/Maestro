#!/usr/bin/env bash
# S-301/S-302: contrato do roster em agents/*.md (DATA_MODEL §5, ADR-004,
# ARCHITECTURE §Security Touchpoints).
#
# Varre o diretório INTEIRO, não uma lista fixa: quando os especialistas de
# linguagem chegarem (S-302), eles caem sob as mesmas asserções sem editar
# este arquivo. Só leitura — nenhum estado é escrito fora do tmpdir.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
AGENTS_DIR="$REPO/agents"
tmp=$(mktemp -d); export MAESTRO_HOME="$tmp"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

# Ferramentas que existem no Claude Code. O contrato proíbe inventar nome:
# `tools:` com nome fora daqui é erro de digitação ou invenção.
KNOWN_TOOLS=" Read Grep Glob Edit Write MultiEdit Bash BashOutput KillShell \
NotebookEdit WebFetch WebSearch Task TodoWrite Skill SlashCommand \
ExitPlanMode AskUserQuestion "

# Lê uma chave do frontmatter (só a primeira ocorrência), já sem aspas/espaços.
fm() { # fm <chave> <arquivo>
  awk -v k="$1" '
    FNR == 1 && /^---[ \t]*$/ { st = 1; next }
    st == 1 && /^---[ \t]*$/  { exit }
    st == 1 && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      sub(/^"/, "", v); sub(/"$/, "", v)
      sub(/^'\''/, "", v); sub(/'\''$/, "", v)
      print v; exit
    }
  ' "$2"
}

# ---------------------------------------------------------------------------
# 1. Higiene do diretório: só markdown, sem código executável (CLAUDE.md).
# ---------------------------------------------------------------------------
if [[ ! -d "$AGENTS_DIR" ]]; then
  bad "agents/ não existe"; exit 1
fi

shopt -s nullglob dotglob
all=("$AGENTS_DIR"/*)
shopt -u dotglob
files=("$AGENTS_DIR"/*.md)
shopt -u nullglob

intruso=0
for f in "${all[@]}"; do
  b="$(basename "$f")"
  # `.gitkeep` é placeholder do versionamento, não conteúdo do roster.
  [[ "$b" == ".gitkeep" && ! -s "$f" ]] && continue
  [[ -f "$f" && "$f" == *.md ]] || { bad "agents/ contém não-markdown: $b"; intruso=1; }
done
(( intruso == 0 )) && ok "agents/ só contém arquivos .md"

exec_bit=0; shebang=0
for f in "${all[@]}"; do
  [[ -f "$f" ]] || continue
  [[ -x "$f" ]] && { bad "$(basename "$f") tem bit de execução"; exec_bit=1; }
  IFS= read -r first < "$f" || first=""
  [[ "$first" == '#!'* ]] && { bad "$(basename "$f") começa com shebang"; shebang=1; }
done
(( exec_bit == 0 && shebang == 0 )) && ok "nenhum agente é executável (sem bit +x, sem shebang)"

if (( ${#files[@]} == 0 )); then
  bad "agents/ está vazio — o roster é o E3"; exit 1
fi
ok "roster com ${#files[@]} agente(s)"

# ---------------------------------------------------------------------------
# 2. Frontmatter obrigatório, por agente (DATA_MODEL §5).
# ---------------------------------------------------------------------------
names=(); descs=(); desc_owner=()

for f in "${files[@]}"; do
  base="$(basename "$f" .md)"

  # 2a. abertura e fechamento do bloco YAML
  IFS= read -r first < "$f" || first=""
  if [[ "$first" != "---" ]]; then
    bad "$base: frontmatter não abre com --- na linha 1"; continue
  fi
  if ! awk 'FNR==1{next} /^---[ \t]*$/{found=1; exit} END{exit !found}' "$f"; then
    bad "$base: frontmatter não fecha com ---"; continue
  fi

  # 2b. dentro do bloco só pode haver `chave: valor` ou comentário.
  # Qualquer outra linha é continuação/lista/bloco — e mataria a `description`
  # de uma linha, que é o gate MoE.
  malformada=$(awk '
    FNR == 1 && /^---[ \t]*$/ { st = 1; next }
    st == 1 && /^---[ \t]*$/  { exit }
    st == 1 && /^[ \t]*$/     { next }
    st == 1 && /^#/           { next }
    st == 1 && /^[A-Za-z_][A-Za-z0-9_-]*:/ { next }
    st == 1 { print FNR; exit }
  ' "$f")
  if [[ -n "$malformada" ]]; then
    bad "$base: linha $malformada do frontmatter não é 'chave: valor' (YAML malformado)"
    continue
  fi
  ok "$base: frontmatter YAML bem formado"

  # 2c. name casa com o nome do arquivo
  nm="$(fm name "$f")"
  if [[ "$nm" == "$base" ]]; then
    ok "$base: name casa com o nome do arquivo"
  else
    bad "$base: name='$nm' não casa com o arquivo"
  fi
  [[ "$nm" =~ ^[a-z0-9-]{1,40}$ ]] \
    || bad "$base: name fora do formato [a-z0-9-] (o parser do session-start descarta)"

  # 2d. description — uma linha, não vazia, sem bloco escalar, sem tab
  ds="$(fm description "$f")"
  if [[ -z "$ds" ]]; then
    bad "$base: description vazia — sem gate MoE o agente nunca é escolhido"
  elif [[ "$ds" == "|"* || "$ds" == ">"* ]]; then
    bad "$base: description usa bloco escalar YAML; precisa ser UMA linha"
  elif [[ "$ds" == *$'\t'* ]]; then
    bad "$base: description contém tab (quebra o índice do roster do session-start)"
  else
    ok "$base: description de uma linha, não vazia"
  fi

  # 2e. model no vocabulário fechado
  md="$(fm model "$f")"
  case "$md" in
    haiku|sonnet|opus) ok "$base: model=$md" ;;
    *) bad "$base: model='$md' fora de {haiku,sonnet,opus}" ;;
  esac

  # 2f. tools não vazio e com nomes que existem
  tl="$(fm tools "$f")"
  if [[ -z "$tl" ]]; then
    bad "$base: tools vazio — ferramentas mínimas por papel são obrigatórias"
  else
    inventada=""
    IFS=',' read -ra arr <<< "$tl"
    for t in "${arr[@]}"; do
      t="${t//[[:space:]]/}"
      [[ -z "$t" ]] && continue
      [[ "$KNOWN_TOOLS" == *" $t "* ]] || inventada+=" $t"
    done
    if [[ -n "$inventada" ]]; then
      bad "$base: tools com nome inexistente no Claude Code:$inventada"
    else
      ok "$base: tools declarado e válido ($tl)"
    fi
  fi

  names+=("$nm")
  descs+=("$ds")
  desc_owner+=("$base")
done

# ---------------------------------------------------------------------------
# 3. revisor é READ-ONLY (ARCHITECTURE §Security Touchpoints: "revisores
# read-only; só dev-* têm Write/Bash"). Requisito de segurança, não estilo:
# se alguém afrouxar, este teste quebra.
# ---------------------------------------------------------------------------
rev="$AGENTS_DIR/revisor.md"
if [[ -f "$rev" ]]; then
  rtools=",$(fm tools "$rev" | tr -d '[:space:]'),"
  proibida=""
  for t in Write Edit MultiEdit Bash; do
    [[ "$rtools" == *",$t,"* ]] && proibida+=" $t"
  done
  if [[ -n "$proibida" ]]; then
    bad "revisor NÃO pode ter:$proibida (read-only é requisito de segurança)"
  else
    ok "revisor é read-only (sem Write/Edit/Bash)"
  fi
else
  bad "revisor.md ausente do roster"
fi

# ---------------------------------------------------------------------------
# 4. Tiering de custo (ADR-004): dev-junior roda em haiku.
# ---------------------------------------------------------------------------
dj="$AGENTS_DIR/dev-junior.md"
if [[ -f "$dj" ]]; then
  if [[ "$(fm model "$dj")" == "haiku" ]]; then
    ok "dev-junior é haiku (tiering de custo do ADR-004)"
  else
    bad "dev-junior precisa ser haiku — o tiering de custo é a razão do roster"
  fi
else
  bad "dev-junior.md ausente do roster"
fi

# ---------------------------------------------------------------------------
# 5. Nenhum nome duplicado.
# ---------------------------------------------------------------------------
dup="$(printf '%s\n' "${names[@]}" | sort | uniq -d)"
if [[ -n "$dup" ]]; then
  bad "nome de agente duplicado: $(echo "$dup" | tr '\n' ' ')"
else
  ok "nenhum nome de agente duplicado"
fi

# ---------------------------------------------------------------------------
# 6. Colisão de gatilho (AC da S-302). Duas descrições iguais — ou uma contida
# na outra — deixam o Claude sem critério para escolher o expert.
# Extra: os primeiros 40 caracteres precisam diferir, porque o índice do roster
# injetado pelo session-start trunca a descrição em 100 chars.
# ---------------------------------------------------------------------------
norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' '; }

colisao=0
n=${#descs[@]}
for ((i = 0; i < n; i++)); do
  a="$(norm "${descs[i]}")"
  [[ -z "$a" ]] && continue
  for ((j = i + 1; j < n; j++)); do
    b="$(norm "${descs[j]}")"
    [[ -z "$b" ]] && continue
    if [[ "$a" == "$b" ]]; then
      bad "description idêntica: ${desc_owner[i]} e ${desc_owner[j]}"; colisao=1
    elif [[ "$b" == *"$a"* || "$a" == *"$b"* ]]; then
      bad "description contida em outra: ${desc_owner[i]} vs ${desc_owner[j]}"; colisao=1
    elif [[ "${a:0:40}" == "${b:0:40}" ]]; then
      bad "descriptions começam iguais nos 40 primeiros chars: ${desc_owner[i]} vs ${desc_owner[j]}"
      colisao=1
    fi
  done
done
(( colisao == 0 )) && ok "nenhuma colisão de gatilho entre as descriptions"

# ---------------------------------------------------------------------------
# 7. Nada foi escrito fora do tmpdir.
# ---------------------------------------------------------------------------
if [[ -e "$tmp/logs" || -e "$tmp/sessions" ]]; then
  bad "o teste escreveu estado em MAESTRO_HOME — deveria ser só leitura"
else
  ok "teste read-only (nenhum estado criado em MAESTRO_HOME)"
fi

exit $fail
