#!/usr/bin/env bash
# maestro lib/core-order-state.sh — E15/S-1501/S-1502/E22/E23b, extraído de
# bin/maestro no E24 (núcleo, ver docs/designs/e24-nucleo-e-adaptadores.md).
#
# NÚCLEO de `maestro order`: leitura de campos/carimbo, estado DERIVADO
# (aberta→em_execucao→provada→aceita|absorvida — issue #12), verificação
# obrigatória por área (E23b) e o gate de direção (E22). Zero I/O de CLI —
# só predicados e leituras sobre o arquivo da ordem e o repo/ledger.
#
# Sourced por bin/maestro (_order_lib_load, I-2) ANTES de lib/cmd-order.sh, no
# MESMO processo — REPO_DIR, die(), maestro_evidence_file já no escopo.
# `maestro_verif_*`/`verif_base_ref`/`verif_record_hint` (lib/cmd-verify.sh,
# ordem 011) NÃO são mais residentes: _order_verif_areas chama
# `_verif_lib_load` antes de usá-las (mesma técnica de `_ev_lib_load`),
# acoplamento mapeado pela ordem A e resolvido aqui. `_intent_version`/
# `_intent_file` (lib/core-intent.sh, ordem 015) também NÃO são residentes:
# `_order_stamp_intent`/`_order_intent_gate` chamam `_intent_lib_load` antes
# de usá-las, mesma técnica.
#
# Convenção (firmada em _order_field antes de custar caro, E24): nenhuma
# função fecha sobre local de outra — `proj`/`of`/`oid` chegam SEMPRE por
# parâmetro posicional, nessa ordem; função pura não recebe `proj`.
#
# ordem 036 (DATA_MODEL §9 v1.22) — três papéis que, até a 033, sempre
# coincidiram num único `proj`:
#   R1 — repo do GIT (branch/tip/merge-base/áreas tocadas)
#   R2 — chave do LEDGER (maestro_evidence_file)
#   R3 — dono da ORDEM (arquivo, carimbo, ~/.maestro/order-state/, INTENT, doc)
# Quando `work_project:` está no cabeçalho, R1/R2 passam a ser o projeto do
# TRABALHO (`wproj`, resolvido por `_order_work_project`); R3 continua SEMPRE
# o projeto DONO (`proj`/`dono`, o mesmo parâmetro de sempre). Convenção
# estendida: funções que precisam dos dois papéis recebem `dono` e `wproj`
# como os DOIS PRIMEIROS parâmetros posicionais, nessa ordem; funções só-R1/R2
# (verificação por área) recebem `wproj` no lugar onde recebiam `proj` — sem
# mudança de forma, só de QUEM o chamador passa. `work_project` AUSENTE →
# `wproj` resolvido é o PRÓPRIO `dono` → literalmente os mesmos argumentos de
# antes desta ordem (I3 do desenho — prova é o golden T1, não este comentário).

# ---------------------------------------------- carimbo e campos (puro; janela = cabeçalho, 20 linhas)
_order_field() { # <arquivo> <chave> → valor do campo, ou vazio
  awk -F': ' -v k="$2" 'NR>20 { exit } $1 == k { print substr($0, length(k)+3); exit }' "$1" 2>/dev/null
}
_order_valid_stamp() { # <arquivo> → rc 0 se carimbo de ordem válido (issue #13: nem todo .md é ordem)
  awk -F': ' '
    NR>20 { exit }
    $0 ~ /^<!-- maestro-order v1/ { hdr=1 }
    $1 == "id" && $2 ~ /^[0-9]{1,3}$/ { idok=1 }
    END { exit !(hdr && idok) }
  ' "$1" 2>/dev/null
}
_order_num() { # <string> → "$((10#string))" em decimal, ou vazio (rc 1) se não for 1-9 dígitos
  # ordem 037: causa-raiz do bug reproduzido pelo Capitão — arquivo sem
  # carimbo faz `_order_field ... id` devolver VAZIO, e todo `$((10#$id))`
  # cru virava `$((10#))`, erro de bash vazando pro usuário e estado
  # inventado ("aberta") no lugar. Defesa em profundidade: NENHUM `10#`
  # deste arquivo roda mais sobre string vazia — quem precisa do valor
  # numérico passa por aqui primeiro.
  [[ "${1:-}" =~ ^[0-9]{1,9}$ ]] || return 1
  printf '%s' "$((10#$1))"
}
_order_intent_stale() { # <arquivo> <versão atual> → rc 0 se a direção andou depois da ordem (E22)
  local ov; ov=$(_order_field "$1" intent_version)
  [[ "$ov" =~ ^[0-9]{1,9}$ && "${2:-}" =~ ^[0-9]{1,9}$ ]] || return 1
  (( 10#$2 > 10#$ov ))
}
_order_branch_number() { # <branch> → número de ordem embutido no branch, ou vazio se não extraível com confiança (ordem 018)
  # Três identificadores (id do cabeçalho, branch declarado, rótulo do
  # recibo) e nada os reconciliava — _order_evidence_candidates (abaixo)
  # deriva o rótulo SÓ do id; o branch nunca entrava na conta. O padrão de
  # prefixo varia por projeto e não é contrato (Maestro: refactor/015-…,
  # fix/016-…; vulcan: order/001-…; ponte-daemon: order/NNN-slug) — o que É
  # verificável é o NÚMERO: a corrida de dígitos que abre o ÚLTIMO segmento
  # do path (depois da última '/', ou o branch inteiro se não houver '/').
  # Cap de 3 dígitos — MESMO teto de `_order_valid_stamp` (`^[0-9]{1,3}$`) —
  # de propósito: exclui ano/hash (ex.: "2026-09-17-fix" não vira id 2026).
  # Fora do cap ou sem dígito líder: devolve vazio — "não sei dizer", NUNCA
  # "incoerente" (falso positivo aqui é ruído que ninguém lê, issue #9).
  local br="${1:-}" tail num
  [[ -n "$br" ]] || return 0
  tail="${br##*/}"
  [[ "$tail" =~ ^([0-9]+) ]] || return 0
  num="${BASH_REMATCH[1]}"
  (( ${#num} <= 3 )) || return 0
  printf '%s' "$((10#$num))"
}
_order_identifier_mismatch() { # <arquivo> → detalhe do aviso se branch:/id: DIVERGEM; vazio se coerentes OU se "não sei dizer" (ordem 018, DATA_MODEL §9 v1.20)
  # FAZ tornar a incoerência VISÍVEL; NÃO FAZ escolher qual dos três
  # identificadores está certo — id, branch e recibo são escritos por mãos
  # diferentes em momentos diferentes, e um vencedor automático inventaria
  # verdade. Puro: só os DOIS campos DECLARADOS no cabeçalho, nunca git nem
  # ledger — não é sobre o branch EXISTIR (isso é _order_status), é sobre o
  # NÚMERO que ele embute bater com o id do arquivo que o declara.
  local f="$1" id br bn idn
  id=$(_order_field "$f" id); [[ -n "$id" ]] || return 0
  br=$(_order_field "$f" branch); [[ -n "$br" ]] || return 0
  bn=$(_order_branch_number "$br"); [[ -n "$bn" ]] || return 0
  idn=$(_order_num "$id") || return 0   # ordem 037: id não numérico é "não sei dizer", não estouro de 10#
  (( idn == 10#$bn )) && return 0
  printf 'branch declarado "%s" embute o número %s — id desta ordem é %s; id, branch e recibo podem apontar para ordens diferentes, nenhum foi corrigido automaticamente' \
    "$br" "$bn" "$idn"
  return 0
}
_order_evidence_candidates() { # <id> [dono8] [strict:0|1] → variantes de rótulo, uma por linha; vazio se id vazio/não numérico
  # ordem 036 (DATA_MODEL §9 v1.22): com `dono8` (work_project presente), o
  # candidato CANÔNICO NOVO `order-<n>-<dono8>` entra na FRENTE da lista.
  # `strict=1` (chamado só quando NÃO HÁ tip pra ancorar — v1.16 endurecida)
  # corta os dois legados: sem árvore do branch pra desambiguar, um recibo
  # `order-<n>` do repo do OUTRO dono seria falso positivo de aceite (M4).
  # `dono8` vazio (work_project ausente) → EXATAMENTE as 2 variantes de
  # sempre (S-1802), na mesma ordem — I3 do desenho da ordem 036.
  local n; n=$(_order_num "$1") || return 0   # ordem 037: era aqui que `10#` estourava sobre id vazio (arquivo sem carimbo)
  local dono8="${2:-}" strict="${3:-0}"
  if [[ -n "$dono8" ]]; then
    printf 'order-%s-%s\n' "$n" "$dono8"
    (( strict == 1 )) && return 0
  fi
  printf 'order-%s\n' "$n"
  printf 'order-%03d\n' "$n"
}
_order_default_branch() { # <proj> → branch padrão do repo, resolvido — SEM rede (NetForge: 'main' fixo recusava master)
  # Ordem de resolução: origin/HEAD (mais confiável quando existe) → config
  # LOCAL init.defaultBranch (só se o branch existir de verdade — config
  # desatualizada não vira sinal) → existência direta de main/master →
  # fallback literal 'main' (preserva a mensagem de hoje quando não há sinal
  # nenhum). `git remote show` fica de fora de propósito: chamaria a rede.
  local proj="$1" ref db
  ref=$(git -C "$proj" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    && [[ -n "$ref" ]] && { printf '%s' "${ref#origin/}"; return 0; }
  db=$(git -C "$proj" config --get init.defaultBranch 2>/dev/null)
  [[ -n "$db" ]] && git -C "$proj" rev-parse --verify --quiet "$db" >/dev/null 2>&1 \
    && { printf '%s' "$db"; return 0; }
  git -C "$proj" rev-parse --verify --quiet main   >/dev/null 2>&1 && { printf 'main';   return 0; }
  git -C "$proj" rev-parse --verify --quiet master >/dev/null 2>&1 && { printf 'master'; return 0; }
  printf 'main'
}


# lib/core-order-workproject.sh, lib/core-order-terminal.sh e lib/core-order-
# accept-proof.sh (ordem 041) são sourced por ESTE arquivo — não por
# bin/maestro (congelado nesta ordem). Mesmo molde de _order_json_lib_load
# (I-2), mas carregado NA HORA (não sob demanda de uma flag do CLI): as
# funções dos três módulos são usadas por quase todo predicado deste núcleo
# (_order_status confere a prova de identidade em TODA leitura, não só em
# --accept).
_order_workproject_lib_load() {
  declare -f _order_work_project >/dev/null 2>&1 && declare -f _order_state_write >/dev/null 2>&1 \
    && declare -f _order_accept_proof_gate >/dev/null 2>&1 && return 0
  if [[ -f "$REPO_DIR/lib/core-order-workproject.sh" && -f "$REPO_DIR/lib/core-order-terminal.sh" \
        && -f "$REPO_DIR/lib/core-order-accept-proof.sh" ]]; then
    # shellcheck source=lib/core-order-workproject.sh
    source "$REPO_DIR/lib/core-order-workproject.sh"
    # shellcheck source=lib/core-order-terminal.sh
    source "$REPO_DIR/lib/core-order-terminal.sh"
    # shellcheck source=lib/core-order-accept-proof.sh
    source "$REPO_DIR/lib/core-order-accept-proof.sh" && return 0
  fi
  die env "lib/core-order-workproject.sh (ou core-order-terminal.sh/core-order-accept-proof.sh) não encontrado em $REPO_DIR" \
    "reinstale o plugin (maestro doctor)" 2
}
_order_workproject_lib_load
# --------------------------------------------------------- estado derivado (dono, wproj)
_order_evidence_match() { # <dono> <wproj> <arquivo> → "rótulo árvore" do 1º candidato provado (S-1802), vazio se nenhum
  local dono="$1" wproj="$2" f="$3" br cand ev_f ev_w tip_tree dono8=""
  br=$(_order_field "$f" branch); [[ -n "$br" ]] || return 0
  tip_tree=$(git -C "$wproj" rev-parse --verify --quiet "$br^{tree}" 2>/dev/null) || return 0
  [[ -n "$(_order_field "$f" work_project)" ]] && dono8=$(_order_dono8 "$dono")
  # branch VIVO ancora a árvore — candidato legado é seguro mesmo com
  # work_project presente (M2/§5.3: recibo alheio tem OUTRA árvore, nunca
  # casa por acidente), então strict=0 aqui sempre.
  for cand in $(_order_evidence_candidates "$(_order_field "$f" id)" "$dono8" 0); do
    ev_f=$(maestro_evidence_file "$wproj" "$cand" 2>/dev/null)
    [[ -f "$ev_f" ]] && grep -q '^exit=0$' "$ev_f" 2>/dev/null || continue
    ev_w=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$ev_f" 2>/dev/null)
    [[ -n "$ev_w" && "$ev_w" == "$tip_tree" ]] && { printf '%s %s' "$cand" "$ev_w"; return 0; }
  done
  return 0
}
_order_evidence_frozen_tree() { # <dono> <wproj> <arquivo> → wtree_after do recibo VÁLIDO (exit=0), sem comparar com tip
  # ordem 017: branch AUSENTE (nunca criado OU mergeado-e-apagado) não tem
  # tip vivo pra comparar — mesma situação de _order_deferred_tree (ordem
  # 013), por outro motivo (lá é "adiada não anda", aqui é "o branch sumiu").
  # Reusa a VARREDURA de _order_deferred_tree (candidatos + wtree_after),
  # mas não pode reusar a função: _order_deferred_tree não exige exit=0 (ali
  # o gate já é o campo deferred_by, a árvore é só para exibição) e aqui o
  # exit=0 É o gate — é o que decide 'provada' em vez de 'aberta', tem de
  # ser tão rígido quanto _order_evidence_match exige quando o branch existe.
  #
  # ordem 036 (DATA_MODEL §9 v1.22, endurecimento da v1.16): SEM tip pra
  # ancorar, um recibo legado `order-<n>` pode ser de ORDEM HOMÔNIMA em OUTRO
  # projeto (M4) — falso positivo de aceite. Com `work_project` presente,
  # `strict=1`: SÓ o candidato namespeado (`order-<n>-<dono8>`) vale.
  local dono="$1" wproj="$2" f="$3" cand ev_f ev_w dono8="" strict=0
  if [[ -n "$(_order_field "$f" work_project)" ]]; then dono8=$(_order_dono8 "$dono"); strict=1; fi
  for cand in $(_order_evidence_candidates "$(_order_field "$f" id)" "$dono8" "$strict"); do
    ev_f=$(maestro_evidence_file "$wproj" "$cand" 2>/dev/null)
    [[ -f "$ev_f" ]] && grep -q '^exit=0$' "$ev_f" 2>/dev/null || continue
    ev_w=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$ev_f" 2>/dev/null)
    [[ -n "$ev_w" ]] && { printf '%s' "$ev_w"; return 0; }
  done
  return 0
}
_order_status() { # <dono> <wproj> <arquivo> → status derivado no stdout
  local dono="$1" wproj="$2" f="$3" br sf so oid id3
  # ordem 021: o registro fora da árvore é a FONTE do estado terminal.
  # Presente → DECIDE, mesmo que o arquivo tenha sido restaurado por um
  # checkout (é exatamente o defeito que esta ordem fecha). Ausente → o
  # carimbo do ARQUIVO ainda conta (migração: ordens carimbadas antes desta
  # ordem entrar, em qualquer projeto desta máquina, não podem "reabrir").
  # ordem 036: registro terminal é SEMPRE do DONO (R3) — nunca do wproj.
  oid=$(_order_field "$f" id)
  sf=$(maestro_order_state_file "$dono" "$oid" 2>/dev/null)
  if [[ -n "$sf" && -f "$sf" ]]; then
    so=$(_order_state_field "$sf" outcome)
    case "$so" in
      aceita)
        # ordem 041: com MAESTRO_ACCEPT_REQUIRE_PROOF ligado, 'aceita' só se
        # deriva se a assinatura gravada no REGISTRO bater — é isto que fecha
        # a porta dos fundos (carimbo escrito à mão no arquivo E/OU no
        # registro, sem os campos accept_proof_*, nunca deriva). REQUIRE
        # desligado: _order_accept_proof_derived_ok devolve rc 0 sem olhar
        # nada — comportamento de hoje, byte a byte.
        id3=$(printf '%03d' "$(_order_num "$oid" 2>/dev/null || echo 0)")
        if _order_accept_proof_derived_ok "$dono" "$id3" "$(_order_state_field "$sf" accepted_tree)" "$sf"; then
          printf 'aceita'; return 0
        fi
        ;;
      absorvida) printf 'absorvida'; return 0 ;;
    esac
  fi
  if grep -q '^accepted_at: ' "$f" 2>/dev/null; then
    # ordem 041: carimbo SÓ-POR-ARQUIVO (sem registro, ou registro sem
    # outcome=aceita) nunca prova identidade — com REQUIRE ligado, cai para
    # os sinais normais abaixo (branch/recibo), nunca 'aceita' sem prova.
    if ! _order_accept_require_proof "$dono"; then printf 'aceita'; return 0; fi
  fi
  [[ -n "$(_order_field "$f" absorbed_by)" ]] && { printf 'absorvida'; return 0; }   # issue #12
  [[ -n "$(_order_field "$f" deferred_by)" ]] && { printf 'adiada'; return 0; }   # ordem 013: suspensa, NÃO terminal — distinta de absorvida
  br=$(_order_field "$f" branch)
  # ordem 036: existência do branch e recibo passam a ser conferidos no
  # WPROJ (R1/R2) — quando work_project está ausente, wproj == dono e nada
  # muda (I3).
  if [[ -z "$br" ]] || ! git -C "$wproj" rev-parse --verify --quiet "$br" >/dev/null 2>&1; then
    # ordem 017: branch ausente tem dois sentidos opostos — nunca criado
    # (nada começou) vs mergeado-e-apagado (tudo terminou). O recibo no
    # ledger é o que sobrevive aos dois e distingue: sem recibo, 'aberta'
    # continua certo; com recibo válido, é 'provada' (árvore CONGELADA do
    # recibo, decisão do diretor — não abre estado novo no enum).
    [[ -n "$(_order_evidence_frozen_tree "$dono" "$wproj" "$f")" ]] && { printf 'provada'; return 0; }
    printf 'aberta'; return 0
  fi
  [[ -n "$(_order_evidence_match "$dono" "$wproj" "$f")" ]] && { printf 'provada'; return 0; }
  printf 'em_execucao'
  return 0
}
_order_proof_tree() { # <dono> <wproj> <arquivo> → árvore PROVADA (sha), vazio se não há prova
  local dono="$1" wproj="$2" f="$3" m br
  m=$(_order_evidence_match "$dono" "$wproj" "$f")
  if [[ -n "$m" ]]; then printf '%s' "${m#* }"; return 0; fi
  # ordem 017: branch ausente não tem tip pra _order_evidence_match comparar
  # (ela devolve vazio de propósito, cedo, na linha 1) — cai para a árvore
  # CONGELADA do recibo, a MESMA que decidiu 'provada' em _order_status.
  br=$(_order_field "$f" branch)
  if [[ -z "$br" ]] || ! git -C "$wproj" rev-parse --verify --quiet "$br" >/dev/null 2>&1; then
    printf '%s' "$(_order_evidence_frozen_tree "$dono" "$wproj" "$f")"
  fi
  return 0
}
_order_deferred_tree() { # <dono> <wproj> <arquivo> → wtree_after do recibo já gravado p/ esta ordem, vazio se nenhum
  # ordem 013: a árvore que a prova CONGELOU — nunca comparada ao tip atual
  # (isso é o que faria o recibo "vencer por mudança de árvore"; adiada não
  # anda, então não há comparação a fazer, só a árvore que ficou registrada).
  # ordem 036: mesmo endurecimento de _order_evidence_frozen_tree — sem tip
  # pra ancorar, work_project presente restringe ao candidato namespeado.
  local dono="$1" wproj="$2" f="$3" cand ev_f ew dono8="" strict=0
  if [[ -n "$(_order_field "$f" work_project)" ]]; then dono8=$(_order_dono8 "$dono"); strict=1; fi
  for cand in $(_order_evidence_candidates "$(_order_field "$f" id)" "$dono8" "$strict"); do
    ev_f=$(maestro_evidence_file "$wproj" "$cand" 2>/dev/null)
    [[ -f "$ev_f" ]] || continue
    ew=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$ev_f" 2>/dev/null)
    [[ -n "$ew" ]] && { printf '%s' "$ew"; return 0; }
  done
  return 0
}
_order_moved_since_accept() { # <dono> <wproj> <arquivo> → caminhos mudados desde o aceite (S-1806; vazio = não andou)
  local dono="$1" wproj="$2" f="$3" at tip br
  br=$(_order_field "$f" branch)
  # ordem 021: accepted_tree pode só existir no registro fora da árvore, se
  # um checkout restaurou o arquivo depois do --accept — mesma precedência de
  # _order_status. accepted_tree é R3 (dono); o tip comparado é R1 (wproj).
  at=$(_order_terminal_field_appended "$dono" "$f" accepted_tree) || true
  [[ -n "$at" && "$at" != "desconhecida" ]] || return 0
  tip=$(git -C "$wproj" rev-parse --verify --quiet "$br^{tree}" 2>/dev/null || true)
  [[ -n "$tip" && "$at" != "$tip" ]] || return 0
  git -C "$wproj" diff --name-only "$at" "$tip" 2>/dev/null \
    | grep -v '^\.maestro/orders/' | head -3 | tr '\n' ' ' || true
}
_order_evidence_label() { # <dono> <wproj> <arquivo> → rótulo do recibo a EXIBIR (S-1804: mesma tolerância do status)
  local dono="$1" wproj="$2" f="$3" m cand ev_f dono8="" strict=0 br
  br=$(_order_field "$f" branch)
  # achado P3 da revisão da 036: o `dono8` vale para a LISTA de candidatos em
  # QUALQUER caminho. Sem ele, a linha de diagnóstico de uma ordem cross-repo
  # ainda NÃO provada mostrava só o rótulo legado e escondia o namespeaceado —
  # justamente o que o operador precisa procurar. O `strict` é que continua
  # exclusivo do caminho sem tip: com branch vivo a árvore ancora e o legado
  # segue legível de propósito (S-1804).
  [[ -n "$(_order_field "$f" work_project)" ]] && dono8=$(_order_dono8 "$dono")
  if [[ -n "$br" ]] && git -C "$wproj" rev-parse --verify --quiet "$br" >/dev/null 2>&1; then
    m=$(_order_evidence_match "$dono" "$wproj" "$f"); [[ -n "$m" ]] && { printf '%s' "${m%% *}"; return 0; }
    # branch VIVO ancora — nunca estrito (mesma razão de _order_evidence_match)
  else
    [[ -n "$dono8" ]] && strict=1
  fi
  for cand in $(_order_evidence_candidates "$(_order_field "$f" id)" "$dono8" "$strict"); do
    ev_f=$(maestro_evidence_file "$wproj" "$cand" 2>/dev/null)
    [[ -f "$ev_f" ]] && { printf '%s' "$cand"; return 0; }
  done
  # ordem 037: era EXATAMENTE aqui (era a linha 267 antes desta ordem) que o
  # bug reproduzido pelo Capitão vazava "10#: invalid integer constant" —
  # arquivo sem carimbo, id vazio, `10#` cru sobre string vazia.
  local n; n=$(_order_num "$(_order_field "$f" id)") && printf 'order-%s' "$n" || printf 'order-?'
}

# ------------------ verificação obrigatória por área (E23b): julga o TIP via recibo em arquivo, nunca ao vivo
# ordem 036: R1/R2 — chamador passa `wproj` (repo do TRABALHO) no lugar onde
# antes só existia `proj`; sem `work_project`, `wproj == dono`, sem mudança.
_order_verif_areas() { # <wproj> <arquivo> → áreas tocadas pelo branch (uma por linha)
  local proj="$1" f="$2" br base
  br=$(_order_field "$f" branch); [[ -n "$br" ]] || return 0
  git -C "$proj" rev-parse --verify --quiet "$br" >/dev/null 2>&1 || return 0
  _verif_lib_load   # ordem 011: maestro_verif_load não é mais residente
  maestro_verif_load
  base=$(verif_base_ref "$proj" "" "$br"); [[ -n "$base" ]] || return 0
  maestro_verif_touched "$proj" "$base" "$br"
  return 0
}
_order_verif_report() { # <wproj> <arquivo> [áreas] → uma linha "rótulo: estado" por rótulo exigido
  local proj="$1" f="$2" areas="${3-}" labels lb tip br ef ev_w ev_m st
  [[ -n "$areas" || $# -ge 3 ]] || areas=$(_order_verif_areas "$proj" "$f")
  [[ -n "$areas" ]] || return 0
  # shellcheck disable=SC2086
  labels=$(maestro_verif_labels "$proj" $areas); [[ -n "$labels" ]] || return 0
  br=$(_order_field "$f" branch)
  tip=$(git -C "$proj" rev-parse --verify --quiet "$br^{tree}" 2>/dev/null) || tip=""
  for lb in $labels; do
    ef=$(maestro_evidence_file "$proj" "$lb" 2>/dev/null) || ef=""
    if [[ -z "$ef" || ! -f "$ef" || ! -r "$ef" ]]; then st='NENHUMA'
    elif ! grep -q '^exit=0$' "$ef" 2>/dev/null; then st='VENCIDA (a execução falhou)'
    else
      ev_w=$(awk -F= '/^wtree_after=/ { print $2; exit }' "$ef" 2>/dev/null) || ev_w=""
      if [[ -z "$tip" || "$ev_w" != "$tip" ]]; then st='VENCIDA (não é o conteúdo do tip)'
      else
        ev_m=$(awk -F= '/^cmd_match=/ { print $2; exit }' "$ef" 2>/dev/null) || ev_m=""
        [[ "$ev_m" == "no" ]] && st='VENCIDA (comando ≠ o declarado)' || st='VÁLIDA'
      fi
    fi
    printf '%s: %s\n' "$lb" "$st"
  done
  return 0
}
_order_verif_gate() { # <wproj> <arquivo> <id> — recusa (exit 1) o aceite sem o conjunto exigido
  local proj="$1" f="$2" id="$3" rep falta="" lb st
  rep=$(_order_verif_report "$proj" "$f"); [[ -n "$rep" ]] || return 0
  while IFS= read -r st; do
    [[ -n "$st" ]] || continue
    [[ "$st" == *": VÁLIDA" ]] && continue
    lb="${st%%:*}"
    falta+="  ${st} — $(verif_record_hint "$proj" "$lb")"$'\n'
  done <<<"$rep"
  [[ -n "$falta" ]] || return 0
  printf 'ordem %s toca área com verificação obrigatória e falta prova:\n%s' "$id" "$falta" >&2
  die validation "ordem $id sem o conjunto de verificações exigido pelo .maestro.yaml" \
    "rode os comandos acima NO TIP DO BRANCH e aceite de novo" 1
}

# --------------------------------------------------------------- direção (E22) — SEMPRE do DONO (R3, ordem 036/§4-B)
_order_stamp_intent() { # <proj> <arquivo> — grava sob QUAL direção o aceite foi dado
  local proj="$1" nv
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
  nv=$(_intent_version "$(_intent_file "$proj")")
  [[ -n "$nv" ]] && printf 'accepted_intent: %s\n' "$nv" >> "$2"
  return 0
}
_order_intent_gate() { # <proj> <arquivo> <id> <intent_reviewed> — aceite sob direção velha é decisão nova
  local proj="$1" f="$2" id="$3" reviewed="$4" nv ov
  _intent_lib_load   # ordem 015: _intent_* não é mais residente
  nv=$(_intent_version "$(_intent_file "$proj")")
  _order_intent_stale "$f" "$nv" || return 0
  ov=$(_order_field "$f" intent_version)
  if (( reviewed == 1 )); then
    printf 'direção revisada pelo diretor: a ordem nasceu sob v%s, a direção está em v%s\n' "$ov" "$nv"
    return 0
  fi
  die validation "a direção mudou (v$ov → v$nv) depois da ordem $id" \
    "releia o plano contra .maestro/INTENT.md; se ele continua de pé, aceite com --intent-reviewed" 1
}
