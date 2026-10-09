#!/usr/bin/env bash
# tools/harness-minimo/lancar.sh — o LANÇADOR das duas configurações do experimento (ordem 077).
#
# Roda UM `claude -p` numa base sem futuro já montada (montar-base.sh), mesmo modelo, mesmo teto de
# turnos, mesma máquina. NÃO sobe o daemon de produção: reproduz o argv que o runner do ponte-daemon usa
# para gerente (headless/claudeArgv.ts, runFiles.ts, envelopeRender.ts — conferidos em 09/10 contra a main
# do daemon, claude 2.1.294) num diretório isolado.
#
#   --config 1  Maestro completo como hoje: plugin carregado (settings de usuário, como o daemon), hooks,
#               Ponte (MCP stdio + --permission-prompt-tool), envelope como --append-system-prompt-file,
#               o prompt posicional FIXO do runner. A ordem inteira (prompt-1.md) fica FORA da árvore da
#               base e o envelope aponta para ela (a base é byte a byte a do head:, sem o arquivo da ordem).
#   --config 2  claude -p puro: --safe-mode --strict-mcp-config, sem `maestro` no PATH, sem Ponte,
#               --permission-mode dontAsk com lista fechada; o prompt é o prompt-2.md.
#
# Nos DOIS: ambiente do filho montado do zero (HOME PATH TERM LANG XDG_RUNTIME_DIR + MAESTRO_HOME
# temporário e VAZIO — o ledger, os briefs e os papercuts de hoje trazem rastro desta ordem). HOME é o real
# (apontá-lo para outra pasta perderia o login). Sem --dangerously-skip-permissions, sem --bare.
#
# Uso: lancar.sh --config 1|2 --base DIR --saida DIR (--prompt ARQ | --texto "frase") [opções]
#   --model M              padrão: sonnet (o manager_model_policy do maestro)         [HM_MODEL]
#   --max-turns N          padrão: 150 (o max_turns do risk_policy do maestro)
#   --max-budget-usd D     teto em dólar do run (o aparelho converte do teto em R$)
#   --parede-s N           teto de parede em segundos (padrão 5400)
#   --politicas ARQ        padrão: docs/experimento/politicas.json (a allowlist REAL do gerente)
#   --politica-projeto P   padrão: maestro
#   --fixture-project P    config 1: project de fixture (padrão exp-harness-054)
#   --fixture-order-ref R  config 1: order_ref de fixture (padrão order/054-exp-harness)
#   --ponte-bridge CMD     config 1: o bridge stdio (padrão: ponte-daemon do PATH) — roda `CMD mcp`
#   --ponte-socket ARQ     config 1: o socket do MCP da Ponte (padrão $HOME/.ponte/mcp.sock)
#   --debug                grava o `claude --debug` em <saida>/debug.log (modo de carga)
#   --recibo "CMD"         depois do claude, roda CMD na árvore final, por fora; rc em <saida>/recibo.rc
#   --dry-run              só monta arquivos e argv (não executa o claude)
# Variáveis: HM_CLAUDE_BIN (o binário; padrão `command -v claude`; o teste usa um claude falso).
# Saída em <saida>: argv.txt, ambiente.txt, versao.txt, uptime.txt, base-tree.txt, stream.jsonl, stderr.log,
# tempos.txt (spawn_ms, fim_ms, parede_ms, rc), [debug.log], [recibo.log, recibo.rc], arquivos/.
set -u

config="" base="" saida="" prompt="" texto="" model="${HM_MODEL:-sonnet}" turnos=150 orcamento="" parede=5400
politicas="" pproj=maestro fproj=exp-harness-054 fref=order/054-exp-harness bridge="" socket=""
debug=0 recibo="" dry=0
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

die() { echo "lancar: $*" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) debug=1; shift; continue ;;
    --dry-run) dry=1; shift; continue ;;
  esac
  [[ $# -ge 2 ]] || die "flag '$1' sem valor"
  case "$1" in
    --config) config="$2" ;;
    --base) base="$2" ;;
    --saida) saida="$2" ;;
    --prompt) prompt="$2" ;;
    --texto) texto="$2" ;;
    --model) model="$2" ;;
    --max-turns) turnos="$2" ;;
    --max-budget-usd) orcamento="$2" ;;
    --parede-s) parede="$2" ;;
    --politicas) politicas="$2" ;;
    --politica-projeto) pproj="$2" ;;
    --fixture-project) fproj="$2" ;;
    --fixture-order-ref) fref="$2" ;;
    --ponte-bridge) bridge="$2" ;;
    --ponte-socket) socket="$2" ;;
    --recibo) recibo="$2" ;;
    *) die "flag desconhecida '$1'" ;;
  esac
  shift 2
done

[[ "$config" == 1 || "$config" == 2 ]] || die "--config deve ser 1 ou 2"
[[ -d "$base/.git" ]] || die "--base '$base' não é uma base montada"
[[ -n "$saida" ]] || die "--saida obrigatório"
[[ -n "$prompt" || -n "$texto" ]] || die "informe --prompt ARQ ou --texto"
[[ -z "$prompt" || -f "$prompt" ]] || die "prompt '$prompt' não existe"
[[ "$turnos" =~ ^[0-9]+$ && "$parede" =~ ^[0-9]+$ ]] || die "--max-turns e --parede-s devem ser inteiros"
[[ -z "$orcamento" || "$orcamento" =~ ^[0-9]+([.][0-9]{1,2})?$ ]] || die "--max-budget-usd: dólar com até 2 casas"
[[ "$fproj" =~ ^[a-z0-9-]{1,40}$ ]] || die "--fixture-project fora do alfabeto"
[[ "$fref" =~ ^order/[0-9]{3}(-[a-z0-9-]{1,60})?$ ]] || die "--fixture-order-ref fora do alfabeto"
claude_bin="${HM_CLAUDE_BIN:-$(command -v claude)}"
[[ -x "$claude_bin" ]] || die "claude não encontrado"
command -v jq >/dev/null || die "jq ausente"
[[ -n "$politicas" ]] || politicas="$REPO/docs/experimento/politicas.json"

mkdir -p "$saida/arquivos" || die "não criou $saida"
saida="$(cd "$saida" && pwd)"; base="$(cd "$base" && pwd)"
[[ -z "$prompt" ]] || prompt="$(cd "$(dirname "$prompt")" && pwd)/$(basename "$prompt")"
arq="$saida/arquivos"

# ---- MAESTRO_HOME temporário e vazio (nos dois lados) ----
mhome="$saida/maestro-home"; mkdir -p "$mhome"
home_real="${HOME:?}"

# ---- a lista fechada de permissões: a do gerente REAL do maestro ----
allow_json=$(jq -c --arg p "$pproj" '.[] | select(.project==$p) | .tool_allowlist | fromjson' "$politicas" 2>/dev/null)
[[ -n "$allow_json" && "$allow_json" != null ]] || die "sem tool_allowlist para '$pproj' em $politicas"

claude_ver=$("$claude_bin" --version 2>/dev/null)
printf '%s\n' "$claude_ver" > "$saida/versao.txt"
uptime > "$saida/uptime.txt"
git -C "$base" rev-parse 'HEAD^{tree}' > "$saida/base-tree.txt"
[[ -z "$(git -C "$base" status --porcelain)" ]] || die "a base não está limpa (cada run começa do mesmo estado)"

uuid=$(cat /proc/sys/kernel/random/uuid)
argv=("$claude_bin" -p --output-format stream-json --verbose --model "$model" --max-turns "$turnos")
[[ -z "$orcamento" ]] || argv+=(--max-budget-usd "$orcamento")
[[ $debug -eq 0 ]] || argv+=(--debug-file "$saida/debug.log")

if [[ "$config" == 1 ]]; then
  [[ -n "$bridge" ]] || bridge="$(command -v ponte-daemon)"
  [[ -n "$bridge" ]] || die "config 1 precisa do bridge da Ponte (--ponte-bridge)"
  [[ -n "$socket" ]] || socket="$home_real/.ponte/mcp.sock"
  # mcp.json e settings.json: o conteúdo de runFiles.ts#montarArquivosDoRun. Sem o hook de audit
  # (PostToolUse → ponte-hook.sh): ele só fala com um run que o daemon conhece, e o run de fixture não é um.
  jq -n --arg cmd "$bridge" --arg sock "$socket" \
    '{mcpServers:{ponte:{type:"stdio",command:$cmd,args:["mcp"],env:{PONTE_MCP_SOCKET:$sock}}}}' > "$arq/mcp.json"
  jq -n --argjson allow "$allow_json" \
    '{permissions:{allow:$allow, deny:["Read(~/.ponte/**)","Edit(~/.ponte/**)","Bash(ponte-daemon:*)","mcp__plugin_*"]},
      allowedMcpServers:[{serverName:"ponte"}]}' > "$arq/settings.json"
  # envelope: as dez fontes do envelopeRender.ts, com ponteiros para arquivos (sem o bloco de fingerprint,
  # que é prova do daemon). A ordem ativa aponta para o prompt-1.md, fora da árvore da base.
  fonte() { # $1=chave $2=rótulo $3=arquivo-ou-vazio $4=motivo
    if [[ -n "$3" && -f "$3" ]]; then
      printf '### %s — %s\nPRESENTE\n> %s, %s bytes, sha256 %s\n\n' "$1" "$2" "$3" "$(wc -c < "$3")" "$(sha256sum "$3" | cut -d' ' -f1)"
    else
      printf '### %s — %s\nAUSENTE — motivo:\n> %s\n\n' "$1" "$2" "$4"
    fi
  }
  ordem_ativa="$prompt"
  {
    printf '# Contexto do gerente headless — Ponte Vulcan\n\nProjeto: %s\nVersão do envelope: 1\n\n' "$fproj"
    printf 'Você é o gerente headless deste projeto, lançado pelo daemon sob supervisão do Diretor.\n'
    printf -- '- O seu relato vai ao Diretor pela Ponte, por MCP. Não há outro canal.\n'
    printf -- '- Você nunca aceita a própria ordem: o aceite é ato do Diretor.\n'
    printf -- '- As fontes abaixo são referências a arquivos do seu worktree; leia-os lá.\n'
    printf -- '- Fonte AUSENTE é ausência registrada, com motivo; não suponha o conteúdo.\n'
    printf -- '- Rode `maestro` e `git` sozinhos, um comando por chamada: nada de encadear com `;`, `&&` ou `|`,\n  nem redirecionar para `echo`. Comando composto vira pergunta ao Diretor.\n\n'
    printf '## Instrução do Diretor\n\n(nenhuma instrução do Diretor nesta ativação)\n\n## Fontes (dez, na ordem canônica)\n\n'
    fonte "1. intent" "direção do projeto (INTENT)" "$base/.maestro/INTENT.md" "sem INTENT"
    fonte "2. brief" "brief atual" "" "sem nome de arquivo único de brief"
    fonte "3. roadmap" "roadmap / gap canônico" "" "sem nome de arquivo único de roadmap/gap"
    fonte "4. local_rules" "regras locais" "$base/CLAUDE.md" "sem CLAUDE.md"
    fonte "5. limits" "orçamento, timeout e limites" "$base/.maestro.yaml" "sem .maestro.yaml"
    fonte "6. active_order" "ordem ativa" "$ordem_ativa" "sem ordem ativa"
    printf '### 7. git — branch e HEAD do Git\nPRESENTE\n> refs/heads/main em %s\n\n' "$(git -C "$base" rev-parse HEAD)"
    fonte "8. verifications" "verificações exigidas" "" "o daemon só lê disco"
    fonte "9. evidence" "evidências" "" "recibo sem convenção de nome por projeto; não lido"
    fonte "10. director_decision" "última decisão do Diretor" "" "sem amarração unívoca ao projeto; não lida"
  } > "$arq/envelope.md"
  posicional="Gerente headless do projeto $fproj, ordem $fref. O contexto da ordem está no system prompt. Relate pelo MCP da Ponte (director.report). Você nunca aceita a própria ordem."
  argv+=(--session-id "$uuid" --mcp-config "$arq/mcp.json" --strict-mcp-config --settings "$arq/settings.json"
         --permission-mode default --permission-prompt-tool mcp__ponte__permission_prompt --permission-prompts host
         --append-system-prompt-file "$arq/envelope.md")
  # Config 1: o filho vê o PATH normal (com `maestro`), como o gerente de produção.
  path_filho="$PATH"
else
  # Config 2: lista fechada = a do gerente real SEM o que é do método (maestro, ponte), igual em todos os runs.
  allow2=$(jq -c '[.[] | select(startswith("mcp__ponte__") or . == "Bash(maestro *)" or . == "Bash(./bin/maestro *)" | not)]' <<<"$allow_json")
  printf '%s\n' "$allow2" > "$arq/allowlist.json"
  printf '{"mcpServers":{}}\n' > "$arq/mcp-vazio.json"
  posicional="$texto"
  [[ -z "$prompt" ]] || posicional="$(cat "$prompt")"
  argv+=(--safe-mode --strict-mcp-config --mcp-config "$arq/mcp-vazio.json" --permission-mode dontAsk
         "--allowedTools=$(jq -r 'join(",")' <<<"$allow2")")   # forma com "=": a flag é variadica e engoliria o prompt
  # PATH sem `maestro` nem `ponte-daemon`: um diretório de atalhos só com o necessário.
  shim="$saida/bin"; mkdir -p "$shim"
  ln -sf "$claude_bin" "$shim/claude"
  if command -v shellcheck >/dev/null; then ln -sf "$(command -v shellcheck)" "$shim/shellcheck"; fi
  path_filho="$shim:/usr/local/bin:/usr/bin:/bin"
fi
# Config 1 com --prompt: o posicional é o do runner e a ordem vai pelo envelope; com --texto (modo de carga) vale o texto.
[[ "$config" == 1 && -n "$texto" ]] && posicional="$texto"
argv+=("$posicional")

env_filho=(HOME="$home_real" PATH="$path_filho" TERM="${TERM:-dumb}" LANG="${LANG:-C.UTF-8}" MAESTRO_HOME="$mhome")
[[ -z "${XDG_RUNTIME_DIR:-}" ]] || env_filho+=(XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR")
printf '%s\n' "${argv[@]}" > "$saida/argv.txt"
printf '%s\n' "${env_filho[@]}" | sed "s#^HOME=.*#HOME=<real>#" > "$saida/ambiente.txt"
[[ $dry -eq 0 ]] || exit 0

# ---- roda: em sequência (quem chama nunca paraleliza), spawn → saída em ms ----
t0=$(date +%s%3N)
(cd "$base" && exec timeout --signal=TERM "${parede}s" env -i "${env_filho[@]}" "${argv[@]}" < /dev/null > "$saida/stream.jsonl" 2> "$saida/stderr.log")
rc=$?
t1=$(date +%s%3N)
printf 'spawn_ms=%s\nfim_ms=%s\nparede_ms=%s\nrc=%s\n' "$t0" "$t1" "$((t1 - t0))" "$rc" > "$saida/tempos.txt"

# ---- o recibo da ordem ORIGINAL, por fora (o agente não se avalia), no mesmo ambiente neutro ----
if [[ -n "$recibo" ]]; then
  (cd "$base" && env -i HOME="$home_real" PATH="$PATH" TERM="${TERM:-dumb}" LANG="${LANG:-C.UTF-8}" MAESTRO_HOME="$(mktemp -d)" bash -c "$recibo" < /dev/null > "$saida/recibo.log" 2>&1)
  echo $? > "$saida/recibo.rc"
fi
exit 0
