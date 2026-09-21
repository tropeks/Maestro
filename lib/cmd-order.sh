#!/usr/bin/env bash
# maestro lib/cmd-order.sh — E15/S-1501/S-1502, extraído de bin/maestro no E24
# (adaptador; núcleo em lib/core-order-state.sh — ver
# docs/designs/e24-nucleo-e-adaptadores.md).
#
# `maestro order`: as 4 ações do CLI (--create/--list/--status/--accept) e o
# despacho de flags. A derivação de estado, verificação por área e o gate de
# direção vivem em core-order-state.sh (sourced ANTES deste arquivo, mesmo
# processo, via _order_lib_load — I-2). Executor não fecha a própria ordem;
# o diretor assina.
#
# Convenção (E24): nenhuma função fecha sobre local de outra — `proj`/`of`/
# `oid`/`sid`/`odir` chegam SEMPRE por parâmetro posicional, nessa ordem;
# função pura não recebe `proj`. `_order_action_*` (as ações do CLI) é a
# exceção declarada ao teto de 5 parâmetros: cada uma espelha 1:1 as flags
# do comando — sacola genérica esconderia o contrato.
#
# ordem 036 (DATA_MODEL §9 v1.22): `wproj` (projeto do TRABALHO) entra como
# SEGUNDO parâmetro posicional, logo depois de `proj`/`dono`, em toda função
# que precisa dele — resolvido UMA VEZ na fronteira de despacho (`cmd_order`,
# depois de `_order_resolve_stamped`, antes de qualquer emissão) e passado
# às ações. `--list` resolve por ORDEM dentro do próprio loop (cada arquivo
# pode ter um `work_project` diferente) e NUNCA morre — marca `[?]`.
#
# `maestro_verif_load` (lib/cmd-verify.sh, ordem 011) NÃO é mais residente:
# cmd_order chama `_verif_lib_load` antes, fora de `$(...)` — mesma nota já
# registrada abaixo sobre subshell, mesma técnica de `_order_lib_load`.
#
# `_intent_valid`/`_intent_version`/`_intent_file`/`_intent_body_hash`
# (lib/core-intent.sh, ordem 015) e `cmd_docs` (lib/cmd-docs.sh, ordem 015)
# também NÃO são residentes: cada função que os usa chama `_intent_lib_load`/
# `_docs_lib_load` antes, mesma técnica — acoplamento mapeado na ordem 015.

# ------------------------------------------------------------- ação: --create
_order_slug() { # <título> → slug de arquivo/branch (minúsculo, [a-z0-9-], até 32)
  local slug; slug=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-' | head -c 32)
  slug="${slug%-}"; printf '%s' "${slug#-}"
}
# ordem 037 — lê o corpo do stdin sem pendurar e sem cortar calado. Casa
# própria porque `_order_create_write` passou do teto do `maestro habits` com
# o bloco dentro (a régua não sobe para acomodar o novo).
#
# `head` sob `timeout` PERDE o que já leu quando é morto (o buffer vai junto),
# e aí "corpo parcial" fica indistinguível de "sem corpo" — o silêncio que a
# ordem 032 matou no `brief --write`, de volta. `cat` para um temporário
# escreve enquanto lê: o que chegou SOBREVIVE ao kill, e os três desfechos
# ficam distinguíveis de verdade.
_order_body_from_stdin() { # <teto-em-bytes> → corpo em stdout; recusa em vez de cortar
  local body_cap="$1" rc=0 stdin_tmp body_bytes
  local stdin_to="${MAESTRO_ORDER_STDIN_TIMEOUT:-2}"
  [[ "$stdin_to" =~ ^[0-9]{1,3}$ ]] || stdin_to=2
  stdin_tmp=$(mktemp "${TMPDIR:-/tmp}/maestro-order-stdin.XXXXXX") || \
    die env "não consigo criar temporário para ler o stdin" "cheque TMPDIR e espaço em disco" 2
  timeout "$stdin_to" cat > "$stdin_tmp" || rc=$?
  body_bytes=$(wc -c < "$stdin_tmp" | tr -d ' ')
  if (( rc == 124 )) && (( body_bytes > 0 )); then
    rm -f "$stdin_tmp"
    die validation \
      "corpo do stdin veio pela metade: $body_bytes bytes lidos e nenhum EOF em $stdin_to s" \
      "feche o stdin (o produtor precisa terminar) ou passe o corpo já pronto; nada foi gravado" 1
  fi
  if (( body_bytes > body_cap )); then
    rm -f "$stdin_tmp"
    die validation \
      "corpo de $body_bytes bytes excede o teto de $body_cap bytes (excedeu por $(( body_bytes - body_cap )) bytes)" \
      "reduza o corpo para até $body_cap bytes ou divida a ordem; nada foi gravado" 1
  fi
  cat "$stdin_tmp"; rm -f "$stdin_tmp"
}

_order_create_write() { # <proj> <oid> <título> <branch> <frozen> <extra> <doc> <sid> <work_project> — grava, loga, imprime confirmação
  local proj="$1" oid="$2" title="$3" branch="$4" frozen="$5" extra="$6" odoc="$7" sid="$8" wp="${9:-}"
  local of="$proj/.maestro/orders/$oid-$(_order_slug "$title").md" head_sha
  head_sha=$(git -C "$proj" rev-parse HEAD 2>/dev/null) || head_sha="none"
  local i_ver="" i_hash=""   # E22: ordem nasce citando a direção vigente; sem carimbo, sai avisando
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
  if _intent_valid "$proj"; then
    i_ver=$(_intent_version "$(_intent_file "$proj")")
    i_hash=$(_intent_body_hash "$(_intent_file "$proj")")
  fi
  # ordem 037: gêmeo da issue #43 (ordem 032 truncava o `brief --write` em
  # silêncio; aqui, o MESMO `head -c 16384` incondicional TRAVAVA em silêncio
  # — stdin pipe/socket aberto e vazio nunca fecha e nunca manda byte, e sem
  # timeout o processo espera para sempre, medido: 147s em pipe_read). Ler
  # corpo de stdin continua implícito (`cat corpo.md | maestro order
  # --create ...` não muda), mas a espera passa a ser LIMITADA — ausência de
  # corpo dentro da janela é caminho normal (ordem nasce só com título e
  # contrato), nunca erro. `MAESTRO_ORDER_STDIN_TIMEOUT` (segundos) por trás
  # do default, mesma técnica de MAESTRO_UPDATE_TIMEOUT (E19).
  local stdin_to="${MAESTRO_ORDER_STDIN_TIMEOUT:-2}"
  [[ "$stdin_to" =~ ^[0-9]{1,3}$ ]] || stdin_to=2
  # Os TRÊS desfechos, separados — limitar a espera sem separá-los traria de
  # volta o corte silencioso que a ordem 032 matou no `brief --write`:
  #   leitura completa          → corpo inteiro, caminho normal;
  #   timeout com ZERO byte     → sem corpo, caminho normal (é o hang);
  #   timeout COM byte lido     → corpo veio pela metade ⇒ RECUSA, nunca grava.
  # `head -c $((cap+1))` deixa o excesso VISÍVEL: passou do teto, recusa com os
  # três números (mesma doutrina da 032), em vez de cortar calado.
  local body; body=$(_order_body_from_stdin 16384)
  {
    printf '<!-- maestro-order v1\n'
    printf 'id: %s\nts: %s\nepoch: %s\nhead: %s\n' "$oid" "$(date -Iseconds)" "$(maestro_now_epoch)" "$head_sha"
    printf 'branch: %s\n' "$branch"
    printf '%s' "$extra"
    [[ -n "$i_ver" ]]  && printf 'intent_version: %s\n' "$i_ver"
    [[ -n "$i_hash" ]] && printf 'intent_hash: %s\n' "$i_hash"
    printf 'author_session: %s\n' "${sid:-desconhecido}"
    printf -- '-->\n# Ordem %s — %s\n\n%s\n' "$oid" "$title" "$body"
    printf '\n## Contrato de execução\n'
    printf -- '- Trabalhe APENAS no branch `%s`; NUNCA no main/master.\n' "$branch"
    [[ -n "$frozen" ]] && printf -- '- Zonas CONGELADAS (não toque): %s\n' "$frozen"
    printf -- '- Prove com o ledger: `maestro evidence --record --label order-%s -- <suíte>` no tip do branch.\n' "$((10#$oid))"
    if [[ -n "$wp" ]]; then
      # ordem 036 (§7.6): camada 3 fecha por DOCUMENTAÇÃO — o contrato traz os
      # comandos exatos que o EXECUTOR roda de dentro do repo do trabalho.
      local dono8; dono8=$(_order_dono8 "$proj")
      printf -- '- Trabalho vive em `%s` (fora deste repo): de lá, `maestro order --status %s --project %s` mostra o estado; prove com `maestro evidence --record --label order-%s-%s -- <suíte>`.\n' \
        "$wp" "$((10#$oid))" "$proj" "$((10#$oid))" "$dono8"
    fi
    [[ -n "$i_ver" ]] && printf -- '- Direção vigente na criação: INTENT v%s (`.maestro/INTENT.md`) — o plano cita a seção da direção que autoriza esta ordem.\n' "$i_ver"
    [[ -n "$odoc" ]] && printf -- '- Esta ordem é autorizada por `%s` — siga-o; se a entrega mudar o contrato, EMENDE o doc no mesmo changeset (o aceite confere o frescor).\n' "$odoc"
    printf -- '- Estourou Ask-First ou orçamento? PARE e reporte ao humano — não improvise.\n'
    printf -- '- O aceite é do diretor: `maestro order --accept %s` (você não fecha a própria ordem).\n' "$oid"
  } > "$of.tmp.$$" && mv -f "$of.tmp.$$" "$of" \
    || { rm -f "$of.tmp.$$" 2>/dev/null; die env "falha ao gravar $of" "" 2; }
  log_event order_create ${sid:+session_id="$sid"} n="$((10#$oid))"
  printf 'ordem %s criada: %s\n  branch: %s\n  status: aberta (derivado — nada executado ainda)\n' "$oid" "$of" "$branch"
  if [[ -n "$i_ver" ]]; then
    printf '  direção: INTENT v%s carimbada na ordem\n' "$i_ver"
  else
    printf '  AVISO: ordem sem direção — %s\n' \
      "$([[ -f "$(_intent_file "$proj")" ]] && echo 'INTENT incompleto ou sem carimbo (maestro intent --check)' || echo 'não há .maestro/INTENT.md (maestro intent --init)')"
  fi
}
_order_action_create() { # <proj> <sid> <título> <branch> <frozen> <budget "steps:min:cents"> <doc> <work_project>
  local proj="$1" sid="$2" title="$3" branch="$4" frozen="$5" odoc="$7" wp="${8:-}"
  local b_steps="" b_min="" b_cents="" v extra="" odir="$proj/.maestro/orders" n next=1 f oid
  IFS=: read -r b_steps b_min b_cents <<<"$6"
  [[ -n "$title" ]] || die validation "--title obrigatório" "o título é o contrato em uma linha" 1
  [[ -t 0 ]] && die validation "corpo ausente" "passe objetivo/critérios/Ask-First via stdin (heredoc)" 1
  for v in "$b_steps" "$b_min" "$b_cents"; do
    [[ -z "$v" || "$v" =~ ^[0-9]{1,6}$ ]] || die validation "orçamento exige inteiros" "E14: passos/min/centavos" 1
  done
  # ordem 036 (DATA_MODEL §9 v1.22, tabela 5.2): --create valida ANTES de
  # gravar nada — forma inválida, não-resolve ou o típo "aponta pro próprio
  # dono" recusam (rc 1), nunca criam ordem com campo quebrado.
  if [[ -n "$wp" ]]; then
    local wpprobe wptag wprest
    wpprobe=$(_order_work_project_probe_value "$proj" "$wp")
    wptag="${wpprobe%% *}"; wprest="${wpprobe#* }"
    case "$wptag" in
      FORMA)     die validation "--work-project \"$wp\" tem forma inválida (esperado ${_order_work_project_re}, sem '/')" "" 1 ;;
      NORESOLVE) die validation "--work-project \"$wp\" não resolve para um repositório git (root ${wprest#* })" \
                   "confira MAESTRO_WORK_ROOT ou o layout de diretórios irmãos" 1 ;;
      PROPRIO)   die validation "--work-project \"$wp\" resolve para o próprio projeto dono — não é cross-repo (typo?)" "" 1 ;;
    esac
    extra+="work_project: $wp"$'\n'
  fi
  mkdir -p "$odir" 2>/dev/null || die env "não consigo criar $odir" "cheque permissões" 2
  shopt -s nullglob
  for f in "$odir"/[0-9][0-9][0-9]-*.md "$odir"/[0-9][0-9][0-9].md; do
    n="${f##*/}"; n="${n%%[-.]*}"; n=$((10#$n))
    (( n >= next )) && next=$(( n + 1 ))
  done
  shopt -u nullglob
  oid=$(printf '%03d' "$next")
  [[ -n "$branch" ]] || branch="order/$oid-$(_order_slug "$title")"
  [[ "$branch" =~ ^[A-Za-z0-9/_-]{1,80}$ ]] || die validation "branch inválido" "" 1
  [[ -n "$frozen" ]]  && extra+="frozen: $frozen"$'\n'
  [[ -n "$b_steps" ]] && extra+="budget_steps: $b_steps"$'\n'
  [[ -n "$b_min" ]]   && extra+="budget_min: $b_min"$'\n'
  [[ -n "$b_cents" ]] && extra+="budget_cents: $b_cents"$'\n'
  [[ -n "$odoc" ]]    && extra+="doc: $odoc"$'\n'
  _order_create_write "$proj" "$oid" "$title" "$branch" "$frozen" "$extra" "$odoc" "$sid" "$wp"
}

# --------------------------------------------------------------- ação: --list
_order_action_list() { # <proj> <odir> — lista ordens com estado derivado
  [[ -d "$2" ]] || { echo "nenhuma ordem em $2 (crie: maestro order --create)"; return 0; }
  local proj="$1" odir="$2" f any=0 iv_now mark id _skip="" _seen=" " _dupe=""
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
  iv_now=$(_intent_version "$(_intent_file "$proj")")
  shopt -s nullglob
  for f in "$odir"/*.md; do
    if ! _order_valid_stamp "$f"; then   # issue #13: sem carimbo válido não é ordem
      _skip+="${_skip:+ }${f##*/}"
      continue
    fi
    any=1
    mark=""
    _order_intent_stale "$f" "$iv_now" && mark="  [direção mudou]"
    id=$(_order_field "$f" id)
    if [[ -n "$id" ]]; then
      [[ "$_seen" == *" $id "* ]] && _dupe+="${_dupe:+ }$id"
      _seen+="$id "
    fi
    # ordem 036: cada ordem pode ter o SEU work_project — resolve POR
    # ARQUIVO, dentro do loop, e NUNCA morre (I5/tabela 5.2: --list marca
    # `[?]`, não derruba a listagem das outras).
    local wproj_f wp_mark
    wproj_f=$(_order_work_project_list_wproj "$proj" "$f")
    wp_mark=$(_order_work_project_list_mark "$proj" "$f")
    printf '%s  [%s]%s%s  %s\n' "$id" "$(_order_status "$proj" "$wproj_f" "$f")" "$mark" "${wp_mark:+ $wp_mark}" \
      "$(grep -m1 '^# ' "$f" | sed 's/^# //')"
  done
  shopt -u nullglob
  (( any == 0 )) && echo "nenhuma ordem em $odir"
  [[ -n "$_dupe" ]] && printf 'ATENÇÃO: id de ordem duplicado — %s (dois arquivos com o mesmo id; renomeie/ajuste um)\n' "$_dupe"
  [[ -n "$_skip" ]] && printf '(ignorado(s) em %s sem carimbo de ordem: %s)\n' "$odir" "$_skip"
  return 0
}

# ------------------------------------------------------------- ação: --status
#
# A renderização em TEXTO mora em MÓDULO PRÓPRIO (lib/cmd-order-status.sh,
# ordem 036) — ver o cabeçalho de lá para o motivo medido (mesmo corte que já
# separa texto de JSON, agora separando texto de tudo mais neste arquivo).
_order_status_lib_load() { # carrega lib/cmd-order-status.sh — uma vez, degradando por comando (I-2)
  declare -f _order_action_status >/dev/null 2>&1 && return 0
  if [[ -f "$REPO_DIR/lib/cmd-order-status.sh" ]]; then
    # shellcheck source=lib/cmd-order-status.sh
    source "$REPO_DIR/lib/cmd-order-status.sh" && return 0
  fi
  die env "lib/cmd-order-status.sh não encontrado em $REPO_DIR" \
    "reinstale o plugin (maestro doctor)" 2
}

# ------------------------------------------ ação: --accept (ordem 022, módulo próprio)
#
# `_order_accept_absorb`/`_order_accept_own` moram em MÓDULO PRÓPRIO
# (lib/cmd-order-accept.sh), MESMO molde de lib/cmd-order-json.sh (ordem 014,
# issue #18): responsabilidade distinta o bastante pra ter nome — aceite/
# absorção é um ADAPTADOR de ESCRITA sobre o mesmo núcleo
# (core-order-state.sh) que --status/--status --json já leem. Motivo medido,
# não estético: este arquivo estava EXATAMENTE em 400 linhas — o teto do
# sensor `oversized-file` — margem zero, e a ordem 022 (curar o carimbo
# terminal só-por-arquivo, DATA_MODEL §9 emenda v1.18) precisava tocar as
# duas ações. Carregado SOB DEMANDA — só quando a ação é `--accept` — no
# molde de `_order_json_lib_load` logo abaixo: módulo ausente derruba SÓ este
# comando (I-2, `die env`), nunca o CLI inteiro; `--create`/`--list`/
# `--status` nunca pagam o custo de sourcing de um módulo que não usam.
_order_accept_lib_load() { # carrega lib/cmd-order-accept.sh — uma vez, degradando por comando (I-2)
  declare -f _order_accept_own >/dev/null 2>&1 && return 0
  if [[ -f "$REPO_DIR/lib/cmd-order-accept.sh" ]]; then
    # shellcheck source=lib/cmd-order-accept.sh
    source "$REPO_DIR/lib/cmd-order-accept.sh" && return 0
  fi
  die env "lib/cmd-order-accept.sh não encontrado em $REPO_DIR" \
    "reinstale o plugin (maestro doctor)" 2
}

# ----------------------------------------- ação: --status --json (ordem 014, issue #18)
#
# A emissão JSON mora em MÓDULO PRÓPRIO (lib/cmd-order-json.sh, vocabulário
# cmd- do E24: responsabilidade distinta o bastante pra ter nome — texto e
# JSON são dois ADAPTADORES do mesmo núcleo, não a mesma peça): puxar
# _order_action_status_json para cá engordaria este arquivo acima do teto de
# `oversized-file` (400 linhas) sem nenhum motivo além de conveniência de
# edição. Carregado SOB DEMANDA — só quando `--status` vem com `--json` — no
# molde de `_order_lib_load`/`_verif_lib_load`: módulo ausente derruba SÓ
# este comando (I-2, `die env`), nunca o CLI; `--status` SEM `--json` nunca
# paga o custo de sourcing de um módulo que não usa.
_order_json_lib_load() { # carrega lib/cmd-order-json.sh — uma vez, degradando por comando (I-2)
  declare -f _order_action_status_json >/dev/null 2>&1 && return 0
  if [[ -f "$REPO_DIR/lib/cmd-order-json.sh" ]]; then
    # shellcheck source=lib/cmd-order-json.sh
    source "$REPO_DIR/lib/cmd-order-json.sh" && return 0
  fi
  die env "lib/cmd-order-json.sh não encontrado em $REPO_DIR" \
    "reinstale o plugin (maestro doctor)" 2
}

# ------------------------------------------------ resolução por id (--status/--accept)
_order_resolve_stamped() { # <odir> <oid:NNN> → caminho da ordem CARIMBADA; die se ausente ou sem carimbo
  # ordem 037: --list (linha ~106, issue #13) já recusa .md sem carimbo antes
  # de tratá-lo como ordem; a resolução por glob de id que serve --status/
  # --accept NÃO aplicava a mesma guarda — duas portas para o mesmo dado, uma
  # com tranca e a outra sem. Sem isso, id vazio (_order_field devolve "" pra
  # arquivo sem carimbo) chegava cru a `10#` em core-order-state.sh e vazava
  # erro de bash, com o estado saindo inventado ("aberta"). Degrada com a
  # MESMA linguagem do --list, citando o caminho, rc previsível, nunca stderr
  # de implementação.
  local odir="$1" oid="$2" of
  of=$(ls "$odir/$oid"-*.md "$odir/$oid.md" 2>/dev/null | head -1 || true)   # pipefail: glob vazio sai 2
  [[ -n "$of" && -f "$of" ]] || die validation "ordem $oid não existe" "maestro order --list" 1
  _order_valid_stamp "$of" || die validation "$of sem carimbo de ordem" \
    "não é uma ordem válida (maestro order --list mostra o que é ordem de verdade)" 1
  printf '%s' "$of"
}

# ------------------------------------------------------------------ despacho
cmd_order() { # S-1501/S-1502 — parseia flags e despacha para a ação (única fronteira que fala com o CLI)
  local action="" proj="${CLAUDE_PROJECT_DIR:-$PWD}" title="" branch="" frozen="" oid="" sid="" odoc=""
  local b_steps="" b_min="" b_cents="" intent_reviewed=0 absorbed_by="" json_out=0 wp=""
  while (( $# )); do
    case "$1" in
      --create)  action="create" ;;
      --list)    action="list" ;;
      --status)  action="status"; oid="${2:-}"; shift ;;
      --accept)  action="accept"; oid="${2:-}"; shift ;;
      --title)   title="${2:-}"; shift ;;
      --branch)  branch="${2:-}"; shift ;;
      --frozen)  frozen="${2:-}"; shift ;;
      --budget-steps) b_steps="${2:-}"; shift ;;
      --budget-min)   b_min="${2:-}"; shift ;;
      --budget-cents) b_cents="${2:-}"; shift ;;
      --doc)     odoc="${2:-}"; shift ;;
      --work-project) wp="${2:-}"; shift ;;   # ordem 036 (DATA_MODEL §9 v1.22), só com --create
      --intent-reviewed) intent_reviewed=1 ;;   # E22
      --absorbed-by) absorbed_by="${2:-}"; shift ;;   # issue #12, usa-se COM --accept
      --json) json_out=1 ;;   # ordem 014/issue #18, só com --status: fonte única p/ o supervisor ler
      --session) sid="${2:-}"; shift ;;
      --project) proj="${2:-}"; shift ;;
      *) die validation "flag desconhecida '$1'" \
           "maestro order --create --title t [--branch b] [--frozen \"a/ b/\"] [--work-project p] | --list | --status N [--json] | --accept N [--absorbed-by M|main] [--intent-reviewed]" 1 ;;
    esac
    shift
  done
  [[ -n "$action" ]] || action="list"
  local odir="$proj/.maestro/orders"

  # shellcheck source=hooks/lib/common.sh
  source "$REPO_DIR/hooks/lib/common.sh"
  _verif_lib_load   # ordem 011: maestro_verif_load não é mais residente
  maestro_verif_load   # E23b: AQUI — dentro de $(...) a lib morreria no subshell

  case "$action" in
    create) _order_action_create "$proj" "$sid" "$title" "$branch" "$frozen" "$b_steps:$b_min:$b_cents" "$odoc" "$wp"; return 0 ;;
    list)   _order_action_list "$proj" "$odir"; return 0 ;;
  esac

  [[ "$oid" =~ ^[0-9]{1,3}$ ]] || die validation "id de ordem inválido" "use o NNN do --list" 1
  oid=$(printf '%03d' "$((10#$oid))")
  local of; of=$(_order_resolve_stamped "$odir" "$oid")
  # ordem 036: a resolução de `wproj` acontece AQUI — depois de
  # _order_resolve_stamped, antes de QUALQUER emissão (--status --json não
  # pode sair com stdout meio escrito). `die validation` (forma inválida /
  # não resolve) sai daqui direto; ausente/próprio-dono resolvem pro `proj`.
  local wproj; wproj=$(_order_work_project "$proj" "$of")

  case "$action" in
    status)
      if (( json_out == 1 )); then _order_json_lib_load; _order_action_status_json "$proj" "$wproj" "$of" "$oid"
      else _order_status_lib_load; _order_action_status "$proj" "$wproj" "$of" "$oid"; fi ;;
    accept)
      _order_accept_lib_load
      if [[ -n "$absorbed_by" ]]; then _order_accept_absorb "$proj" "$wproj" "$odir" "$of" "$oid" "$sid" "$absorbed_by"
      else _order_accept_own "$proj" "$wproj" "$of" "$oid" "$sid" "$intent_reviewed"; fi ;;
  esac
}
