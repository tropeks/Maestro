#!/usr/bin/env bash
# ordem 014 (issue #18) — fonte única de estado da ordem para o supervisor.
#
# O supervisor mora em repo próprio e RECALCULAVA a derivação de estado por
# conta — a derivação vive aqui e evolui aqui, então as duas leituras
# divergiam, e a que interrompe humano é a que erra: catorze interrupções
# nesta sessão cobrando aceite de ordem que já tinha estado terminal
# (`absorvida`, ordem 004/issue #12; `adiada`, ordem 013), porque o
# consumidor externo não conhecia os dois estados novos. Zero ações
# possíveis em todas.
#
# `maestro order --status N --json` é a fonte única: lê os MESMOS predicados
# de core-order-state.sh que o modo texto lê — nunca uma segunda derivação
# (precedente hooks/lib/habit-sensors.awk, "sensor único, dois momentos";
# aqui são dois momentos de ESTADO, não de smell).
#
# Arquivo PRÓPRIO (não em test-order.sh) — mesmo motivo de
# tests/cli/test-order-issue6.sh/issue12.sh/issue13.sh/013-deferred.sh: não
# estourar o teto da catraca `oversized-file`.
#
# Lição da ordem 003/004A/013: o teste NÃO exige o patch já aplicado.
# Detecta o MECANISMO em lib/cmd-order.sh (lib/ está na denylist de
# autoproteção do gate desde a ordem 012 — quem aplica
# docs/patches/014-status-json-cmd-order.patch é o Capitão); ausente →
# PENDENTE (nunca reprova); presente → cobra de verdade nos SEIS estados do
# contrato, prova que texto e JSON nunca divergem, prova compatibilidade
# aditiva (campo novo não quebra leitor antigo) e sabota (numa CÓPIA) a
# MESMA asserção de paridade para provar que o teste tem dente.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
CMD="$REPO/lib/cmd-order.sh"
CMDJ="$REPO/lib/cmd-order-json.sh"   # emissão JSON em módulo próprio (catraca oversized-file)

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

command -v jq >/dev/null 2>&1 || { echo "PENDENTE  jq ausente — teste exige jq para validar JSON"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

git_init_main() { local d="$1"; git -C "$d" init -q; git -C "$d" symbolic-ref HEAD refs/heads/main; }
# `git add -A` DENTRO de branch de ordem de teste come o arquivo da ordem
# (ele vira tracked só nesse branch, e o `git checkout` seguinte o apaga do
# disco ao voltar pra main — armadilha paga na ordem 013). Nominal sempre.
commit_f() { local d="$1" m="$2"; git -C "$d" add f.txt; git -C "$d" -c user.email=t@t -c user.name=t commit -qm "$m"; }

# mecanismo em DOIS arquivos (lib/cmd-order.sh carrega sob demanda, lib/
# cmd-order-json.sh define): os dois patches precisam estar aplicados.
LOADER_PATCHED=0; grep -qF '_order_json_lib_load' "$CMD" 2>/dev/null && LOADER_PATCHED=1
MODULE_PATCHED=0; [[ -f "$CMDJ" ]] && grep -qF '_order_action_status_json' "$CMDJ" 2>/dev/null && MODULE_PATCHED=1

if (( LOADER_PATCHED == 0 || MODULE_PATCHED == 0 )); then
  pending "ordem 014: '--status --json' ainda ausente; aplicar docs/patches/014-status-json-cmd-order.patch e docs/patches/014-status-json-cmd-order-json-novo-modulo.patch"
  exit 0
fi
ok "mecanismo presente: lib/cmd-order.sh carrega lib/cmd-order-json.sh sob demanda (_order_json_lib_load)"

# ---------------------------------------------------------------------------
# fixture: um projeto com uma ordem em CADA um dos seis estados do contrato.
# ---------------------------------------------------------------------------
P="$tmp/proj"; mkdir -p "$P"; git_init_main "$P"
echo base > "$P/f.txt"; commit_f "$P" base

new_order() { # <título> → cria e devolve <arquivo> <branch> por stdout, uma linha "arquivo branch"
  local title="$1" of br
  "$BIN" order --create --title "$title" --project "$P" --session v14 >/dev/null <<BODY
## Objetivo
fixture ordem 014: $title
BODY
of=$(ls -t "$P"/.maestro/orders/*.md | head -1)
br=$(grep '^branch:' "$of" | awk '{print $2}')
printf '%s %s\n' "$of" "$br"
}

# 1: aberta
read -r OF1 _ <<<"$(new_order "aberta")"

# 2: em_execucao
read -r OF2 BR2 <<<"$(new_order "em execucao")"
git -C "$P" checkout -qb "$BR2"; echo e2 >> "$P/f.txt"; commit_f "$P" e2; git -C "$P" checkout -q main

# 3: provada
read -r OF3 BR3 <<<"$(new_order "provada")"
git -C "$P" checkout -qb "$BR3"; echo e3 >> "$P/f.txt"; commit_f "$P" e3
"$BIN" evidence --record --label "order-$(grep '^id:' "$OF3" | awk '{print $2}' | sed 's/^0*//')" --project "$P" -- true >/dev/null
git -C "$P" checkout -q main

# 4: aceita
read -r OF4 BR4 <<<"$(new_order "aceita")"
ID4=$(grep '^id:' "$OF4" | awk '{print $2}' | sed 's/^0*//')
git -C "$P" checkout -qb "$BR4"; echo e4 >> "$P/f.txt"; commit_f "$P" e4
"$BIN" evidence --record --label "order-$ID4" --project "$P" -- true >/dev/null
git -C "$P" checkout -q main
"$BIN" order --accept "$ID4" --project "$P" --session v14 >/dev/null

# 5: absorvida (pela 4, já aceita/provada)
read -r OF5 _ <<<"$(new_order "absorvida")"
ID5=$(grep '^id:' "$OF5" | awk '{print $2}' | sed 's/^0*//')
"$BIN" order --accept "$ID5" --project "$P" --session v14 --absorbed-by "$ID4" >/dev/null

# 6: adiada (deferred_by escrito à mão, recibo prévio congelado)
read -r OF6 BR6 <<<"$(new_order "adiada")"
ID6=$(grep '^id:' "$OF6" | awk '{print $2}' | sed 's/^0*//')
git -C "$P" checkout -qb "$BR6"; echo e6 >> "$P/f.txt"; commit_f "$P" e6
"$BIN" evidence --record --label "order-$ID6" --project "$P" -- true >/dev/null
git -C "$P" checkout -q main
awk -v ins='deferred_by: Capitao' '!done && $0 == "-->" { print ins; done=1 } { print }' "$OF6" > "$OF6.tmp.$$" \
  && mv -f "$OF6.tmp.$$" "$OF6"

declare -A EXPECT=( [1]=aberta [2]=em_execucao [3]=provada [4]=aceita [5]=absorvida [6]=adiada )

# ---------------------------------------------------------------------------
# (a) para cada um dos seis estados: JSON é válido (jq parseia) e o campo
# "estado" é IDÊNTICO ao que o modo texto imprime — mesma fonte.
# ---------------------------------------------------------------------------
LAST_JSON=""
for n in 1 2 3 4 5 6; do
  id=$(printf '%03d' "$n")
  TXT=$("$BIN" order --status "$n" --project "$P" 2>&1)
  JSON=$("$BIN" order --status "$n" --project "$P" --json 2>&1)
  if jq -e . >/dev/null 2>&1 <<<"$JSON"; then ok "(a) ordem $id: --json é JSON válido (jq parseia)"
  else bad "(a) ordem $id: --json não é JSON válido: $JSON"; fi
  txt_st=$(head -1 <<<"$TXT" | awk -F': ' '{print $2}')
  json_st=$(jq -r '.estado // "?"' <<<"$JSON")
  [[ "$txt_st" == "${EXPECT[$n]}" ]] && ok "(a) ordem $id: texto deriva '${EXPECT[$n]}'" \
    || bad "(a) ordem $id: texto deriva '$txt_st', esperado '${EXPECT[$n]}'"
  [[ "$txt_st" == "$json_st" ]] && ok "(a) ordem $id: estado no JSON ($json_st) == estado no texto ($txt_st)" \
    || bad "(a) ordem $id: DIVERGÊNCIA texto='$txt_st' json='$json_st' — dois vocabulários de estado"
  [[ "$(jq -r .id <<<"$JSON")" == "$id" ]] && ok "(a) ordem $id: campo id bate" || bad "(a) ordem $id: campo id não bate"
  [[ -n "$(jq -r '.branch // empty' <<<"$JSON")$(jq -r 'if .branch==null then "n" else "" end' <<<"$JSON")" ]] \
    && ok "(a) ordem $id: campo branch presente (valor ou null)" || bad "(a) ordem $id: campo branch ausente"
  [[ "$(jq 'has("prova") and (.prova|has("estado")) and (.prova|has("detalhe")) and (.prova|has("arvore"))' <<<"$JSON")" == "true" ]] \
    && ok "(a) ordem $id: objeto prova{estado,detalhe,arvore} presente" \
    || bad "(a) ordem $id: objeto prova incompleto: $JSON"
  [[ "$(jq 'has("direcao")' <<<"$JSON")" == "true" ]] && ok "(a) ordem $id: campo direcao presente (objeto ou null)" \
    || bad "(a) ordem $id: campo direcao ausente"
  [[ -n "$(jq -r '.motivo // empty' <<<"$JSON")" ]] && ok "(a) ordem $id: campo motivo não vazio" \
    || bad "(a) ordem $id: campo motivo vazio"
  [[ "$n" == 3 ]] && LAST_JSON="$JSON"
done

# ---------------------------------------------------------------------------
# (b) semântica que resolve a issue: terminal/suspensa/pede_aceite batem com
# o que a issue mediu — absorvida e adiada NUNCA pedem aceite, aberta/
# em_execucao também não (nada para aceitar ainda), só provada pede.
# ---------------------------------------------------------------------------
declare -A EXP_PEDE=( [1]=false [2]=false [3]=true [4]=false [5]=false [6]=false )
declare -A EXP_TERM=( [1]=false [2]=false [3]=false [4]=true [5]=true [6]=false )
declare -A EXP_SUSP=( [1]=false [2]=false [3]=false [4]=false [5]=false [6]=true )
for n in 1 2 3 4 5 6; do
  JSON=$("$BIN" order --status "$n" --project "$P" --json 2>&1)
  pede=$(jq -r .pede_aceite <<<"$JSON"); term=$(jq -r .terminal <<<"$JSON"); susp=$(jq -r .suspensa <<<"$JSON")
  [[ "$pede" == "${EXP_PEDE[$n]}" ]] && ok "(b) ordem $(printf '%03d' "$n"): pede_aceite=$pede" \
    || bad "(b) ordem $(printf '%03d' "$n"): pede_aceite=$pede, esperado ${EXP_PEDE[$n]}"
  [[ "$term" == "${EXP_TERM[$n]}" ]] && ok "(b) ordem $(printf '%03d' "$n"): terminal=$term" \
    || bad "(b) ordem $(printf '%03d' "$n"): terminal=$term, esperado ${EXP_TERM[$n]}"
  [[ "$susp" == "${EXP_SUSP[$n]}" ]] && ok "(b) ordem $(printf '%03d' "$n"): suspensa=$susp" \
    || bad "(b) ordem $(printf '%03d' "$n"): suspensa=$susp, esperado ${EXP_SUSP[$n]}"
done
# a asserção CENTRAL da issue: nem absorvida (5) nem adiada (6) pedem aceite.
J5=$("$BIN" order --status 5 --project "$P" --json); J6=$("$BIN" order --status 6 --project "$P" --json)
[[ "$(jq -r .pede_aceite <<<"$J5")" == "false" ]] && ok "(b) issue #18: ordem absorvida NÃO pede aceite no JSON" \
  || bad "(b) issue #18: ordem absorvida pede aceite — regressão do defeito medido"
[[ "$(jq -r .pede_aceite <<<"$J6")" == "false" ]] && ok "(b) issue #18: ordem adiada NÃO pede aceite no JSON" \
  || bad "(b) issue #18: ordem adiada pede aceite — regressão do defeito medido"

# ---------------------------------------------------------------------------
# (c) campo novo não quebra leitor que só conhece os campos de hoje (mesmo
# método de tests/cli/test-order-issue11.sh, item 4): injeta chave TOP-LEVEL
# desconhecida no objeto e prova que um leitor que só lê id/estado/branch
# continua lendo os mesmos valores.
# ---------------------------------------------------------------------------
if [[ -n "$LAST_JSON" ]]; then
  OLD_READ=$(jq -r '.id + " " + .estado + " " + (.branch // "null")' <<<"$LAST_JSON")
  FUTURO=$(jq -c '. + {"estado_futuro_hipotetico": "recusada", "campo_novo": 7}' <<<"$LAST_JSON")
  OLD_READ2=$(jq -r '.id + " " + .estado + " " + (.branch // "null")' <<<"$FUTURO")
  jq -e . >/dev/null 2>&1 <<<"$FUTURO" && ok "(c) objeto com campo top-level desconhecido continua JSON válido" \
    || bad "(c) objeto com campo desconhecido deixou de parsear"
  [[ "$OLD_READ" == "$OLD_READ2" ]] && ok "(c) leitor que só conhece id/estado/branch não muda de resposta com campo novo" \
    || bad "(c) leitor antigo quebrou com campo novo: '$OLD_READ' != '$OLD_READ2'"
fi

# ---------------------------------------------------------------------------
# (d) sabotagem: injeta uma SEGUNDA derivação de estado só no caminho JSON
# (o defeito que esta ordem existe para não repetir — dois vocabulários) e
# prova que a MESMA asserção de paridade de (a) reprova. Cópia (git clone),
# nunca git archive.
# ---------------------------------------------------------------------------
SABROOT="$tmp/sabotado"; mkdir -p "$SABROOT/bin" "$SABROOT/lib"
cp "$BIN" "$SABROOT/bin/maestro"; chmod +x "$SABROOT/bin/maestro"
ln -s "$REPO/hooks" "$SABROOT/hooks"
ln -s "$REPO/agents" "$SABROOT/agents" 2>/dev/null || :
ln -s "$REPO/bin/maestro-wtree" "$SABROOT/bin/maestro-wtree"
cp "$REPO"/lib/*.sh "$SABROOT/lib/"
# a emissão JSON mora em módulo PRÓPRIO (lib/cmd-order-json.sh, ordem 014
# pós-catraca: lib/cmd-order.sh só carrega sob demanda) — é lá que o sed
# sabota, não em lib/cmd-order.sh.
SABCMD="$SABROOT/lib/cmd-order-json.sh"
# no handler JSON, "aceita" passa a sair como "aceito" — uma segunda leitura
# de estado que diverge do texto (_order_status continua dizendo "aceita").
sed -i 's/out+=",\$(_order_json_field estado "\$st")"/out+=",\$(_order_json_field estado "\$([[ "\$st" == aceita ]] \&\& echo aceito || echo "\$st")")"/' "$SABCMD"
if ! grep -q 'aceito' "$SABCMD"; then
  bad "(d) sabotagem não pegou (padrão do sed não bateu — mecanismo mudou de forma?)"
else
  SAB="$SABROOT/bin/maestro"
  TXT_SAB=$("$SAB" order --status 4 --project "$P" 2>&1 | head -1 | awk -F': ' '{print $2}')
  JSON_SAB=$("$SAB" order --status 4 --project "$P" --json 2>&1)
  JST_SAB=$(jq -r '.estado // "?"' <<<"$JSON_SAB")
  if [[ "$TXT_SAB" == "$JST_SAB" ]]; then
    bad "(d) sabotagem não quebrou nada — a asserção de paridade passaria mesmo com dois vocabulários de estado"
  else
    ok "(d) sabotado: a MESMA asserção de (a) REPROVA (texto='$TXT_SAB' json='$JST_SAB') — o teste tem dente"
  fi
fi

exit $fail
