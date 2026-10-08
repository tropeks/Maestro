#!/usr/bin/env bash
# Ordem 076 / turno 1: verificador de peer (SO_PEERCRED) + impostor, sem sessao do Claude Code.
# 100 trocas validas (gerente -> Diretor -> gerente) INTERCALADAS com tentativas de
# remetente falso; a identidade vem do kernel (PID do peer -> ancestral `claude` ->
# mapa gravado pelo aparelho), nunca da mensagem. Criterio: 100/100 trocas corretas e
# 0 aceitas em toda forma de impostor. Saida: so inteiros.
#
# Argumento 1 (opcional): outro diretorio do aparelho; inexistente reproduz o
# "vermelho antes" (verificador ausente).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${1:-$ROOT/tools/prova-ponte-mods}"
VERIF="$DIR/peer-verifier"
CLIENT="$DIR/peer-client"

RUN=$(mktemp -d)
mkdir -p "$RUN/map" "$RUN/bin"
chmod 700 "$RUN" "$RUN/map"
VPIDS=()
# shellcheck disable=SC2329  # chamada pelo trap EXIT
cleanup() {
  local p
  for p in "${VPIDS[@]}"; do kill "$p" 2>/dev/null; done
  rm -rf "$RUN"
}
trap cleanup EXIT

fail=0
FAIL() { echo "FAIL: $*"; fail=1; }

if [[ ! -x "$VERIF" || ! -x "$CLIENT" || ! -x "$DIR/claude-falso" || ! -x "$DIR/orfao" ]]; then
  FAIL "aparelho ausente em $(basename "$DIR") (verificador, cliente, claude-falso ou orfao)"
  echo "trocas_ok=0/100 tentativas=0 aceitas=0"
  exit 1
fi
ln -s "$DIR/claude-falso" "$RUN/bin/claude"

SOCK=""
start_verifier() { # nome ttl-ms
  SOCK="$RUN/$1.sock"
  python3 -I "$VERIF" --sock "$SOCK" --map-dir "$RUN/map" --ttl-ms "$2" --log "$RUN/$1.log" &
  VPIDS+=("$!")
  local i
  for i in $(seq 1 300); do
    [[ -S "$SOCK" ]] && return 0
    sleep 0.01
  done
  FAIL "verificador nao subiu"
  echo "trocas_ok=0/100 tentativas=0 aceitas=0"
  exit 1
}

sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
novo_rid() { tr -d '-' </proc/sys/kernel/random/uuid; }
J() { printf '{"op":"%s","rid":"%s","hash":"%s","veredito":"%s","de":"%s"}' "$1" "$2" "$3" "$4" "$5"; }

# Roda o cliente como FILHO de um `claude` falso cujo papel o APARELHO grava no mapa.
# papel: gerente | diretor | semmapa (claude que o aparelho nao mapeou).
como() { # papel json
  local papel=$1 json=$2 out pid
  out=$(mktemp "$RUN/out.XXXXXX")
  "$RUN/bin/claude" "$RUN/map" "$CLIENT" "$SOCK" "$json" >"$out" 2>&1 &
  pid=$!
  [[ $papel != semmapa ]] && printf '%s' "$papel" >"$RUN/map/$pid"
  : >"$RUN/map/.go.$pid"
  wait "$pid"
  cat "$out"
  rm -f "$out" "$RUN/map/$pid" "$RUN/map/.go.$pid"
}

# Cliente lancado e reparentado: o mapa continua la, a cadeia ate o `claude` nao.
orfao() { # papel json
  local papel=$1 json=$2 out pid
  out=$(mktemp "$RUN/orf.XXXXXX")
  "$RUN/bin/claude" "$RUN/map" "$DIR/orfao" "$out" "$CLIENT" "$SOCK" "$json" >/dev/null 2>&1 &
  pid=$!
  printf '%s' "$papel" >"$RUN/map/$pid"
  : >"$RUN/map/.go.$pid"
  wait "$pid"
  sleep 1.2
  cat "$out"
  rm -f "$out" "$RUN/map/$pid" "$RUN/map/.go.$pid"
}

declare -A TENT ACC
TOTAL=0
conta() { # forma resposta
  TENT[$1]=$(( ${TENT[$1]:-0} + 1 ))
  TOTAL=$(( TOTAL + 1 ))
  if [[ $2 == *'"ok": true'* ]]; then ACC[$1]=$(( ${ACC[$1]:-0} + 1 )); fi
}
tentar() { # forma papel json   (papel direto = sem `claude` no caminho)
  local r
  if [[ $2 == direto ]]; then r=$("$CLIENT" "$SOCK" "$3"); else r=$(como "$2" "$3"); fi
  conta "$1" "$r"
}
legit() { # papel json
  local r
  r=$(como "$1" "$2")
  [[ $r == *'"ok": true'* ]] && return 0
  echo "recusado ($1): $r"
  return 1
}

RID="" H="" V="" OPOSTO=""
pre() { # pedido registrado, ainda nao verificado
  case $1 in
    0) tentar nome_falso_gerente direto "$(J registrar-pedido "$(novo_rid)" "$H" "$V" gerente)" ;;
    1) tentar nome_falso_diretor direto "$(J registrar-decisao "$RID" "$H" allow diretor)" ;;
    2) tentar rid_copiado direto "$(J verificar-pedido "$RID" "$H" "$V" diretor)" ;;
    3) tentar pedido_peer_errado diretor "$(J registrar-pedido "$(novo_rid)" "$H" "$V" gerente)" ;;
    4) tentar auto_aprovacao gerente "$(J registrar-decisao "$RID" "$H" allow diretor)" ;;
    5) tentar hash_trocado diretor "$(J verificar-pedido "$RID" "$(sha trocado)" "$V" diretor)" ;;
    6) tentar peer_sem_mapa semmapa "$(J registrar-pedido "$(novo_rid)" "$H" "$V" gerente)" ;;
  esac
}
pos() { # decisao registrada, ainda nao verificada pelo gerente
  case $1 in
    0) tentar replay diretor "$(J verificar-pedido "$RID" "$H" "$V" diretor)" ;;
    1) tentar decisao_nao_diretor gerente "$(J registrar-decisao "$RID" "$H" "$OPOSTO" diretor)" ;;
    2) tentar veredito_trocado gerente "$(J verificar-decisao "$RID" "$H" "$OPOSTO" gerente)" ;;
    3) tentar rid_copiado direto "$(J verificar-decisao "$RID" "$H" "$V" gerente)" ;;
    4) tentar decisao_rid_alheio diretor "$(J registrar-decisao "$(novo_rid)" "$H" "$V" diretor)" ;;
    5) tentar papel_errado diretor "$(J verificar-decisao "$RID" "$H" "$V" gerente)" ;;
  esac
}

# Uma troca valida + 3 tentativas de impostor intercaladas. Devolve o passo que falhou.
troca() { # n
  local n=$1
  RID=$(novo_rid)
  H=$(sha "entrada-$n")
  if (( n % 2 )); then V=allow OPOSTO=deny; else V=deny OPOSTO=allow; fi
  legit gerente "$(J registrar-pedido "$RID" "$H" "$V" gerente)" || return 1
  pre $(( n % 7 ))
  legit diretor "$(J verificar-pedido "$RID" "$H" "$V" diretor)" || return 2
  legit diretor "$(J registrar-decisao "$RID" "$H" "$V" diretor)" || return 3
  pos $(( n % 6 ))
  legit gerente "$(J verificar-decisao "$RID" "$H" "$V" gerente)" || return 4
  tentar replay gerente "$(J verificar-decisao "$RID" "$H" "$V" gerente)"
  return 0
}

start_verifier principal 10000

seguidas=0
for n in $(seq 1 100); do
  troca "$n"
  rc=$?
  if (( rc != 0 )); then
    FAIL "troca $n falhou no passo $rc; contagem de trocas seguidas zerada (era $seguidas)"
    seguidas=0
    break
  fi
  seguidas=$(( seguidas + 1 ))
done

# Formas que nao cabem no giro: texto malformado, gigante, processo reparentado.
tentar malformado diretor 'isto nao e json'
tentar malformado gerente '{"op":'
tentar malformado gerente '[1,2]'
tentar malformado gerente "$(J registrar-pedido abc "$(sha x)" allow gerente)"
PAD=$(head -c 70000 /dev/zero | tr '\0' a)
tentar gigante gerente "{\"op\":\"registrar-pedido\",\"rid\":\"$(novo_rid)\",\"hash\":\"$(sha g)\",\"pad\":\"$PAD\"}"
tentar gigante diretor "{\"op\":\"registrar-decisao\",\"rid\":\"$(novo_rid)\",\"veredito\":\"allow\",\"pad\":\"$PAD\"}"
for k in 1 2 3; do
  conta reparentado "$(orfao gerente "$(J registrar-pedido "$(novo_rid)" "$(sha "orfao-$k")" allow gerente)")"
done

# O verificador conta o mesmo que o aparelho: 4 ops aceitas por troca e nenhuma outra.
stats=$("$CLIENT" "$SOCK" '{"op":"stats"}')
ACEITAS_V=-1 RECUSADAS_V=-1
[[ $stats =~ \"aceitas\":\ ([0-9]+) ]] && ACEITAS_V=${BASH_REMATCH[1]}
[[ $stats =~ \"recusadas\":\ ([0-9]+) ]] && RECUSADAS_V=${BASH_REMATCH[1]}
(( ACEITAS_V == seguidas * 4 )) || FAIL "verificador aceitou $ACEITAS_V ops; esperado $(( seguidas * 4 ))"
(( RECUSADAS_V == TOTAL )) || FAIL "verificador recusou $RECUSADAS_V; tentativas feitas $TOTAL"

# rid vencido: verificador a parte com TTL curto (o padrao de 10 s e o do mod).
start_verifier curto 800
for i in 1 2; do
  RID=$(novo_rid) H=$(sha "v-$i")
  legit gerente "$(J registrar-pedido "$RID" "$H" allow gerente)" || FAIL "registro valido recusado (ttl curto)"
  sleep 1
  tentar vencido diretor "$(J verificar-pedido "$RID" "$H" allow diretor)"
  RID=$(novo_rid)
  legit gerente "$(J registrar-pedido "$RID" "$H" allow gerente)" || FAIL "registro valido recusado (ttl curto)"
  legit diretor "$(J verificar-pedido "$RID" "$H" allow diretor)" || FAIL "verificacao valida recusada (ttl curto)"
  legit diretor "$(J registrar-decisao "$RID" "$H" allow diretor)" || FAIL "decisao valida recusada (ttl curto)"
  sleep 1
  tentar vencido gerente "$(J verificar-decisao "$RID" "$H" allow gerente)"
done

# Log so de metadados: nem hash nem json nem comando.
if grep -q -E '[0-9a-f]{64}|"op"|entrada-' "$RUN/principal.log"; then
  FAIL "log do verificador vazou conteudo alem de metadados"
fi

if (( fail != 0 )); then
  echo "-- primeiras linhas do log do verificador (metadados):"
  head -n 5 "$RUN/principal.log"
fi

echo
printf '%-26s %10s %8s\n' forma tentativas aceitas
ACEITAS_TOT=0
for f in $(printf '%s\n' "${!TENT[@]}" | sort); do
  printf '%-26s %10d %8d\n' "$f" "${TENT[$f]}" "${ACC[$f]:-0}"
  ACEITAS_TOT=$(( ACEITAS_TOT + ${ACC[$f]:-0} ))
done
FORMAS=${#TENT[@]}
echo
echo "trocas_ok=$seguidas/100 formas=$FORMAS tentativas=$TOTAL aceitas=$ACEITAS_TOT verificador_aceitas=$ACEITAS_V verificador_recusadas=$RECUSADAS_V"

(( seguidas == 100 )) || FAIL "trocas validas seguidas: $seguidas de 100"
(( ACEITAS_TOT == 0 )) || FAIL "$ACEITAS_TOT tentativa(s) de impostor aceita(s)"
(( TOTAL >= 100 )) || FAIL "so $TOTAL tentativas (minimo 100)"
(( FORMAS >= 8 )) || FAIL "so $FORMAS formas (minimo 8)"

if (( fail == 0 )); then echo "PASS: prova do verificador de peer"; fi
exit $fail
