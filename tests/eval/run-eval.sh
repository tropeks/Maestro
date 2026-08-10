#!/usr/bin/env bash
# tests/eval/run-eval.sh — S-402: driver dos três instrumentos de avaliação.
#
# NÃO é um teste da suíte. `tests/run-all.sh` varre tests/hooks e tests/cli; este
# diretório fica de fora de propósito: um score de roteamento abaixo de 100% é
# informação, não regressão, e não pode derrubar o CI do plugin. Quem quiser gate de
# CI usa `--prescribed --min N` explicitamente.
#
# Instrumentos (o porquê de serem três está em docs/ROUTING_EVAL.md § Método):
#   (A) --prescribed   determinístico. Mede se o TEXTO da tabela basta. Piso, não AC.
#   (B) --judge-*      julgamento cego de LLM. É o mecanismo real (ADR-002) e é dele
#                      que sai o número comparável à AC da S-402.
#   (C) --log FILE     métrica observada no dogfood real (~/.maestro/logs/routing.jsonl).
#
# Uso:
#   bash tests/eval/run-eval.sh                      # (A) veredito completo
#   bash tests/eval/run-eval.sh --prescribed --min 8 # (A) com gate de CI
#   bash tests/eval/run-eval.sh --what-if            # (A) variantes de calibração
#   bash tests/eval/run-eval.sh --judge-prompt [out] # (B) gera o prompt do juiz cego
#   bash tests/eval/run-eval.sh --judge-score FILE   # (B) pontua o TSV do juiz
#   bash tests/eval/run-eval.sh --judge-agree A B    # (B') concordância entre 2 juízes
#   bash tests/eval/run-eval.sh --log FILE           # (C) métrica do log real
#   bash tests/eval/run-eval.sh --selftest           # asserções do próprio harness
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PRESCRIBE="$HERE/prescribe.ts"

die() { printf 'run-eval: %s\n' "$1" >&2; exit 1; }
command -v bun >/dev/null 2>&1 || die "bun não encontrado (o harness vive em tests/, onde Bun é permitido)"

# ---------------------------------------------------------------------------
# (B) prompt do juiz cego.
# Contexto entregue = EXATAMENTE o que o Claude de uma sessão real recebe: a saída
# do hooks/session-start.sh. Nada de cases.yaml, nada de `expected`, nada de
# rationale — se o gabarito vazasse, o juiz estaria copiando, não roteando.
# O MAESTRO_HOME e o CLAUDE_PROJECT_DIR são temporários e vazios: os casos são de
# projetos diferentes, então nenhum .maestro.yaml único se aplica (e a ausência de
# profile é justamente a condição mais dura — ver a recomendação R3 do relatório).
# ---------------------------------------------------------------------------
judge_prompt() {
  local out="${1:-$HERE/judge-prompt.md}"
  # sem `trap ... RETURN`: o trap é herdado pelas funções chamadoras e dispararia
  # de novo no retorno delas, com $tmp fora de escopo. Limpeza explícita no fim.
  local tmp; tmp=$(mktemp -d) || die "mktemp falhou"
  local injection
  injection=$(MAESTRO_HOME="$tmp/home" CLAUDE_PROJECT_DIR="$tmp/proj" \
    bash "$REPO/hooks/session-start.sh" </dev/null 2>/dev/null) || injection=""
  [[ -n "$injection" ]] || die "session-start.sh não produziu injeção"

  {
    printf '# Instrumento (B) — julgamento cego de roteamento (S-402)\n\n'
    printf 'Gerado por `tests/eval/run-eval.sh --judge-prompt` em %s.\n' "$(date -Iseconds)"
    printf 'Tabela: sha256 %s\n\n' "$(sha256sum "$REPO/config/routing-table.yaml" | cut -c1-12)"
    printf -- '---\n\n'
    printf 'Você é o Claude de uma sessão do Claude Code com o plugin Maestro instalado.\n'
    printf 'O bloco abaixo é o que o hook SessionStart injetou no seu contexto:\n\n'
    printf '```\n%s\n```\n\n' "$injection"
    printf 'Além dele, você tem no contexto as descrições dos agentes do roster '
    printf '(carregadas always-on pelo harness — reproduzidas aqui porque este é um '
    printf 'ambiente offline):\n\n'
    local f nm ds
    for f in "$REPO"/agents/*.md; do
      [[ -e "$f" ]] || continue
      nm=$(awk -F': *' '/^name:/{print $2; exit}' "$f")
      ds=$(awk -F': *' '/^description:/{sub(/^description: */,""); print; exit}' "$f")
      printf -- '- **%s**: %s\n' "$nm" "$ds"
    done
_wf_enum() { # nomes de workflow, na ordem do YAML
  awk '/^workflows:/{f=1;next} f&&/^[a-z]/{exit} f&&/^  [a-z_]+:/{gsub(/^  /,"");sub(/:.*/,"");printf "%s%s", sep, $0; sep=", "}' "$REPO/config/routing-table.yaml"
}

    printf '\n## Tarefa\n\n'
    printf 'Para CADA enunciado abaixo (pt-BR, escritos pelo usuário no telefone), decida o\n'
    printf 'roteamento como decidiria numa sessão real: workflow, mode e agente(s) do roster.\n'
    printf 'Não peça esclarecimento e não pesquise o repositório — decida com o que está aqui,\n'
    printf 'que é o que você teria no primeiro turno de uma sessão real.\n\n'
    printf 'Responda SOMENTE com TSV, uma linha por caso, sem cabeçalho e sem comentário:\n\n'
    printf '```\n<id>\t<workflow>\t<mode>\t<agentes separados por vírgula, ou - se nenhum>\n```\n\n'
    # Derivado da tabela, não hardcoded: na r3 os dois juízes flagraram que o enum
    # contradizia as rotas (faltavam verify/codereview) e tiveram que decidir qual
    # obedecer — o instrumento não pode contradizer o que ele mede.
    printf 'workflow ∈ {%s} · ' "$(_wf_enum)"
    printf 'mode ∈ {direct, subagent, multi}\n\n'
    # Desambiguação da coluna `agentes` (rodada 2 — ver ROUTING_EVAL.md § R10).
    # Na rodada 1 os dois juízes leram "agente(s)" como "todo o elenco do workflow" e
    # listaram revisor/qa porque `review` e `qa` são STEPS. É leitura legítima do texto
    # injetado — e o mesmo texto está em produção. Aqui a coluna é fixada na semântica
    # do decision record (DATA_MODEL §3: workflow fix, steps [investigate, implement,
    # review], agents ["golang-pro"]) para que a rodada 2 meça roteamento, e não uma
    # divergência de vocabulário.
    printf 'A coluna `agentes` é o campo `--agents` do decision record: **quem executa o\n'
    printf 'trabalho principal** (investigação/implementação). NÃO liste os agentes que já\n'
    printf 'vêm de graça dos steps do workflow (o `revisor` do step `review`, o `qa` do step\n'
    printf '`qa`) — eles são implícitos no workflow escolhido. Exemplo do DATA_MODEL: workflow\n'
    printf '`fix` (steps investigate/implement/review) com agents `["golang-pro"]`, só.\n'
    printf 'Use `-` quando o trabalho não for de nenhum agente do roster\n'
    printf '(ex.: o passo é uma skill pesada como `ship`/`cso`, ou fica no contexto principal).\n\n'
    printf '## Enunciados\n\n```\n'
    bun "$PRESCRIBE" --cases
    printf '```\n'
  } >"$out" || { rm -rf "$tmp"; die "falha ao escrever $out"; }
  rm -rf "$tmp"
  printf 'prompt do juiz cego escrito em %s (%s bytes)\n' "$out" "$(wc -c <"$out")"
}

# ---------------------------------------------------------------------------
# (C) métrica observada no log real. Definição operacional (documentada e
# discutível — ver ROUTING_EVAL.md § Instrumento C):
#   universo  = sessões com ≥1 evento `decision`
#   suja      = sessão com QUALQUER um de:
#                 - `override_manual`            (ADR-008: o humano digitou comando)
#                 - 2+ `decision` divergentes    (re-decisão = correção de rumo)
#                 - `gate_warn`/`gate_block` antes do primeiro `decision`
#                                                (editou antes de rotear)
#   métrica   = (universo − sujas) / universo
# Sessões sem nenhum `decision` NÃO entram: podem ser sessões sem trabalho de código.
# ---------------------------------------------------------------------------
log_metric() {
  local log="${1:-$HOME/.maestro/logs/routing.jsonl}"
  command -v jq >/dev/null 2>&1 || die "jq necessário para --log"
  if [[ ! -f "$log" ]]; then
    printf 'log inexistente: %s\n' "$log"
    printf 'SEM DADO — o instrumento (C) só produz número depois do dogfood.\n'
    return 0
  fi
  local lines; lines=$(wc -l <"$log" | tr -d ' ')
  if [[ "$lines" == "0" ]]; then
    printf 'log vazio (%s): 0 eventos.\n' "$log"
    printf 'SEM DADO — o instrumento (C) só produz número depois do dogfood.\n'
    return 0
  fi
  # `fromjson? // empty` descarta linha malformada em silêncio: JSONL append-only
  # escrito por hooks concorrentes pode ter linha truncada, e perder a métrica
  # inteira por causa de uma linha é pior do que ignorá-la.
  jq -R 'fromjson? // empty' "$log" 2>/dev/null | jq -rs '
    map(select(type=="object" and has("event") and has("session_id")))
    | group_by(.session_id)
    | map({
        sid: .[0].session_id,
        decisions: [ .[] | select(.event=="decision")
                     | {w:.workflow, m:.mode, a:((.agents//[])|sort|join(","))} ],
        overrides: [ .[] | select(.event=="override_manual") ] | length,
        pre_gate: ( [ .[] | .event ] as $e
                    | ($e | index("decision")) as $d
                    | if $d == null then 0
                      else [ $e[0:$d][] | select(. == "gate_warn" or . == "gate_block") ] | length
                      end )
      })
    | map(select((.decisions|length) > 0))
    | map(. + {redecided: ((.decisions|unique|length) > 1)})
    | map(. + {clean: ((.overrides == 0) and (.redecided|not) and (.pre_gate == 0))})
    | { universo: length,
        limpas: ([ .[] | select(.clean) ] | length),
        sujas_override: ([ .[] | select(.overrides > 0) ] | length),
        sujas_redecisao: ([ .[] | select(.redecided) ] | length),
        sujas_pre_gate: ([ .[] | select(.pre_gate > 0) ] | length) }
    | if .universo == 0
      then "SEM DADO — nenhum evento `decision` no log."
      else "OBSERVADO NO LOG: \(.limpas)/\(.universo) sessões roteadas sem correção manual"
           + "  (override \(.sujas_override) · re-decisão \(.sujas_redecisao) · edição antes de rotear \(.sujas_pre_gate))"
      end
  ' || die "log ilegível: $log"
}

# ---------------------------------------------------------------------------
# selftest do harness: o instrumento (C) é a parte que ninguém consegue exercitar
# hoje (log vazio), então é a que mais precisa de asserção — com log sintético.
# ---------------------------------------------------------------------------
selftest() {
  local fail=0 tmp out
  tmp=$(mktemp -d) || die "mktemp falhou"
  t() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; echo "       esperado: $2"; echo "       obtido:   $3"; fail=1; fi; }
  has() { if [[ "$2" == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1 (obtido: $2)"; fail=1; fi; }

  bun "$PRESCRIBE" --selftest >/dev/null 2>&1 && echo "ok   prescribe.ts --selftest" \
    || { echo "FAIL prescribe.ts --selftest"; fail=1; }

  : >"$tmp/vazio.jsonl"
  has "(C) log vazio → SEM DADO" "$(log_metric "$tmp/vazio.jsonl")" "SEM DADO"
  has "(C) log inexistente → SEM DADO" "$(log_metric "$tmp/nao-existe.jsonl")" "SEM DADO"

  # sessão limpa: uma decisão, nenhum override, gate depois da decisão
  cat >"$tmp/limpa.jsonl" <<'EOF'
{"ts":"t","event":"decision","session_id":"s1","workflow":"fix","mode":"direct","agents":["golang-pro"]}
{"ts":"t","event":"gate_pass","session_id":"s1","tool":"Edit","file_ext":".go"}
EOF
  has "(C) sessão limpa conta como limpa" "$(log_metric "$tmp/limpa.jsonl")" "1/1"

  # override manual suja a sessão
  cp "$tmp/limpa.jsonl" "$tmp/override.jsonl"
  echo '{"ts":"t","event":"override_manual","session_id":"s1","cmd":"review"}' >>"$tmp/override.jsonl"
  has "(C) override_manual suja" "$(log_metric "$tmp/override.jsonl")" "0/1"

  # re-decisão divergente suja; re-decisão idêntica NÃO suja (re-registro do mesmo)
  cp "$tmp/limpa.jsonl" "$tmp/redecide.jsonl"
  echo '{"ts":"t","event":"decision","session_id":"s1","workflow":"feature","mode":"multi","agents":["golang-pro"]}' >>"$tmp/redecide.jsonl"
  has "(C) re-decisão divergente suja" "$(log_metric "$tmp/redecide.jsonl")" "0/1"
  cp "$tmp/limpa.jsonl" "$tmp/mesma.jsonl"
  head -1 "$tmp/limpa.jsonl" >>"$tmp/mesma.jsonl"
  has "(C) re-registro idêntico não suja" "$(log_metric "$tmp/mesma.jsonl")" "1/1"

  # gate antes da decisão suja
  cat >"$tmp/pregate.jsonl" <<'EOF'
{"ts":"t","event":"gate_warn","session_id":"s2","tool":"Edit","file_ext":".ts"}
{"ts":"t","event":"decision","session_id":"s2","workflow":"fix","mode":"direct"}
EOF
  has "(C) edição antes de rotear suja" "$(log_metric "$tmp/pregate.jsonl")" "0/1"

  # sessão sem decision fica fora do universo
  cat >"$tmp/fora.jsonl" <<'EOF'
{"ts":"t","event":"killswitch","session_id":"s3"}
{"ts":"t","event":"decision","session_id":"s1","workflow":"fix","mode":"direct","agents":["golang-pro"]}
EOF
  has "(C) sessão sem decision sai do universo" "$(log_metric "$tmp/fora.jsonl")" "1/1"

  # linha corrompida no meio não derruba a métrica (JSONL append-only real)
  cp "$tmp/limpa.jsonl" "$tmp/sujo.jsonl"
  echo 'nao é json' >>"$tmp/sujo.jsonl"
  out=$(log_metric "$tmp/sujo.jsonl" 2>&1) || true
  has "(C) linha corrompida é descartada, métrica sobrevive" "$out" "1/1"

  # (B) o prompt do juiz não pode vazar o gabarito
  judge_prompt "$tmp/jp.md" >/dev/null
  local leaked=0
  grep -q "expected" "$tmp/jp.md" && leaked=1
  grep -q "rationale" "$tmp/jp.md" && leaked=1
  grep -q "golang-pro, typescript-pro" "$tmp/jp.md" && leaked=1
  t "(B) prompt do juiz não vaza expected/rationale" "0" "$leaked"
  t "(B) prompt do juiz traz os 15 enunciados" \
    "$(bun "$PRESCRIBE" --cases | wc -l)" "$(awk '/^## Enunciados/{f=1} f&&/^[a-z0-9-]+\t/{n++} END{print n+0}' "$tmp/jp.md")"
  has "(B) prompt do juiz contém a injeção real" "$(cat "$tmp/jp.md")" "<maestro-routing>"

  # (B) o scorer casa o TSV do juiz com o expected
  bun "$PRESCRIBE" --json | \
    jq -r '.verdicts[] | [.id, .expected.workflow, .expected.mode, (if (.expected.agents|length)==0 then "-" else (.expected.agents|join(",")) end)] | @tsv' \
    >"$tmp/perfeito.tsv"
  has "(B) TSV idêntico ao gabarito pontua 15/15" \
    "$(bun "$PRESCRIBE" --score "$tmp/perfeito.tsv" | tail -1)" "15/15"

  # (B') concordância: um arquivo consigo mesmo é 15/15 por construção; com um
  # arquivo alterado numa linha, cai exatamente 1.
  has "(B') arquivo × ele mesmo = concordância total" \
    "$(bun "$PRESCRIBE" --agree "$tmp/perfeito.tsv" "$tmp/perfeito.tsv" | tail -1)" "15/15 exatos"
  # Troca o mode da 1a linha por um valor garantidamente diferente, seja ele qual for.
  # Antes era `sed s/direct/multi/`, que virou no-op quando o gabarito do caso 1 deixou
  # de ser `direct` — fixture frágil que passava por não mexer em nada.
  awk -F'\t' 'BEGIN{OFS="\t"} NR==1{$3=($3=="multi"?"direct":"multi")} {print}' \
    "$tmp/perfeito.tsv" >"$tmp/mexido.tsv"
  has "(B') uma divergência derruba exatamente 1" \
    "$(bun "$PRESCRIBE" --agree "$tmp/perfeito.tsv" "$tmp/mexido.tsv" | tail -1)" "14/15 exatos"

  rm -rf "$tmp"
  return $fail
}

# ---------------------------------------------------------------------------
main() {
  case "${1:---prescribed}" in
    --prescribed|--tsv|"")
      local min=""
      [[ "${2:-}" == "--min" ]] && min="${3:-}"
      local out; out=$(bun "$PRESCRIBE" --tsv) || die "prescribe.ts falhou"
      printf '%s\n' "$out"
      if [[ -n "$min" ]]; then
        local got; got=$(printf '%s' "$out" | grep -oE 'DETERMINÍSTICA[^:]*: [0-9]+' | grep -oE '[0-9]+$')
        [[ -n "$got" ]] || die "não consegui extrair o score"
        if (( got < min )); then printf 'ABAIXO DO MÍNIMO (%s < %s)\n' "$got" "$min" >&2; return 1; fi
      fi
      ;;
    --what-if)
      printf '## What-if de calibração (mesma matriz, tabela hipotética)\n\n'
      printf 'baseline .......... '; bun "$PRESCRIBE" --summary | tail -1
      printf 'intents por radical  '; bun "$PRESCRIBE" --stem --summary | tail -1
      printf 'linguagem do profile '; bun "$PRESCRIBE" --profile --summary | tail -1
      printf 'os dois ............ '; bun "$PRESCRIBE" --stem --profile --summary | tail -1
      ;;
    --judge-prompt) judge_prompt "${2:-}" ;;
    --judge-score)  [[ -n "${2:-}" ]] || die "--judge-score exige o TSV do juiz"
                    bun "$PRESCRIBE" --score "$2" ;;
    --judge-agree)  [[ -n "${3:-}" ]] || die "--judge-agree exige dois TSV"
                    bun "$PRESCRIBE" --agree "$2" "$3" ;;
    --log)          log_metric "${2:-}" ;;
    --selftest)     selftest ;;
    -h|--help)      sed -n '2,25p' "${BASH_SOURCE[0]}" ;;
    *) die "opção desconhecida: $1 (use --help)" ;;
  esac
}
main "$@"
