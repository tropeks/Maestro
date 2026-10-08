#!/usr/bin/env bash
# Ordem 076: oraculo VIVO da prova da Ponte sobre mods (gerente pede, Diretor responde por session.send).
#   Par A (caminho real): 5 trocas, o MODELO do gerente executa 5 Reads e o tool.check cai no pedido.
#   Par B (as 100 trocas): `claude -p "/prova-ponte N"`, comando do mod, SEM turno de modelo, com o
#     impostor vivo injetando mensagens forjadas nas duas sessoes durante todas as trocas.
# O Diretor de cada par e uma `claude -p` ociosa (entrada continua); o `herdr` do PATH e falso
# (grava cada chamada e sai com erro); o verificador de peer (SO_PEERCRED) e o do aparelho.
# So sessoes lancadas aqui participam; nada de producao, nada em mods/, nenhum settings tocado.
# Uso: rodar.sh [N]   (N = trocas do par B, padrao 100). Saida: so inteiros; rc 0 = todos os criterios.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/../.." && pwd)"
MOD="$AQUI/maestro-prova"
N="${1:-100}"
LOTE=4     # trocas por comando: o hook de command.run vale 10 s (medido); LOTE*(PAUSA+700) <= 9500
PAUSA=1500 # ms entre trocas (fora do ms medido): o $.session.send tem limite de taxa (rajada ~50, depois ~0,5/s)
((N % LOTE == 0)) || {
  echo "N tem de ser multiplo de $LOTE"
  exit 2
}
UIDN=$(id -u)
BASE="/tmp/claude-$UIDN/${RAIZ//\//-}"
mkdir -p "$BASE"
RUN=$(mktemp -d "$BASE/rodar.XXXXXX")
mkdir -p "$RUN/map" "$RUN/log" "$RUN/work" "$RUN/bin"
chmod 700 "$RUN" "$RUN/map"
PIDS=()
# shellcheck disable=SC2329  # chamada pelo trap EXIT
limpa() {
  local p
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
  exec 3>&- 2>/dev/null
}
trap limpa EXIT

falha=0
FALHA() {
  echo "FALHA: $*"
  falha=1
}

# herdr falso: criterio = 0 chamadas.
# shellcheck disable=SC2016  # o $(...) deve rodar no herdr falso, nao aqui
printf '%s\n' '#!/usr/bin/env bash' 'echo "$(date +%s) chamada" >>"$HERDR_LOG"' 'exit 1' >"$RUN/bin/herdr"
chmod +x "$RUN/bin/herdr"
: >"$RUN/herdr.log"
: >"$RUN/olheiro.txt"

SOCK="$RUN/v.sock"
python3 -I "$AQUI/peer-verifier" --sock "$SOCK" --map-dir "$RUN/map" --log "$RUN/verificador.log" --olheiro "$RUN/olheiro.txt" &
PIDS+=("$!")
for _ in $(seq 1 300); do
  [[ -S $SOCK ]] && break
  sleep 0.01
done

uuid() { cat /proc/sys/kernel/random/uuid; }

# O APARELHO grava o mapa de papeis; a sessao nunca. `exec`: o pid lancado e o do claude.
lanca() { # papel par entrada saida erro [args...]  -> PID em $LANCADO
  local papel=$1 par=$2 ent=$3 sai=$4 err=$5
  shift 5
  (cd "$RUN/work" && exec env PATH="$RUN/bin:$PATH" HERDR_LOG="$RUN/herdr.log" \
    PROVA_PAPEL="$papel" PROVA_SOCK="$SOCK" PROVA_CLIENT="$AQUI/peer-client" \
    PROVA_PAR="$par" PROVA_LOG="$RUN/log" \
    claude --plugin-dir "$MOD" --model haiku --debug-file "$sai.debug" "$@" <"$ent" >"$sai" 2>"$err" 3>&- 4>&-) & # sem os fifos herdados: o EOF tem de chegar
  LANCADO=$!
  printf '%s' "$papel" >"$RUN/map/$LANCADO"
}

espera_arquivo() { # arquivo padrao tentativas
  for _ in $(seq 1 "$3"); do
    grep -q -E "$2" "$1" 2>/dev/null && return 0
    sleep 0.25
  done
  return 1
}

socket_de() { # arquivo.debug -> caminho do socket de mensagens da sessao
  local l
  for _ in $(seq 1 120); do
    l=$(grep -o -m 1 -E 'Listening: /[^ ]+\.sock' "$1" 2>/dev/null)
    if [[ -n $l ]]; then
      echo "${l#Listening: }"
      return 0
    fi
    sleep 0.25
  done
  return 1
}

turnos() { grep -c '"type":"assistant"' "$1"; }

# Um par Diretor ocioso + gerente. Deixa em: DIR_TURNOS (turnos do Diretor nas trocas),
# GER_SAIDA (arquivo do gerente). Argumentos: nome espera-s impostor(0|1) [args do claude do gerente...]
par() {
  local nome=$1 espera=$2 impostor=$3 lotes=$4
  shift 4
  local did gid dpid gpid ipid base_ass
  did=$(uuid)
  gid=$(uuid)
  mkfifo "$RUN/$nome.in"
  exec 3<>"$RUN/$nome.in" # entrada do Diretor aberta: sessao ociosa, nao encerrada
  lanca diretor "$gid" "$RUN/$nome.in" "$RUN/$nome-diretor.out" "$RUN/$nome-diretor.err" \
    --session-id "$did" -p --input-format stream-json --output-format stream-json --verbose
  dpid=$LANCADO
  PIDS+=("$dpid")
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"Responda apenas: PRONTO"}}' >&3
  espera_arquivo "$RUN/$nome-diretor.out" '"type":"result"' 240 || FALHA "diretor $nome nao ficou ocioso"
  base_ass=$(turnos "$RUN/$nome-diretor.out")
  echo "$nome: diretor_vivo=$(kill -0 "$dpid" 2>/dev/null && echo 1 || echo 0)"
  local sd sg
  sd=$(socket_de "$RUN/$nome-diretor.out.debug") || sd=""
  ipid=""
  local gout="$RUN/$nome-gerente.out"
  if ((lotes > 0)); then
    # gerente por entrada continua: um `/prova-ponte LOTE` por mensagem (o hook de command.run vale 10 s)
    mkfifo "$RUN/$nome.gin"
    exec 4<>"$RUN/$nome.gin"
    lanca gerente "$did" "$RUN/$nome.gin" "$gout" "$RUN/$nome-gerente.err" --session-id "$gid" -p --input-format stream-json --output-format stream-json --verbose
  else
    lanca gerente "$did" /dev/null "$gout" "$RUN/$nome-gerente.err" --session-id "$gid" -p --output-format stream-json --verbose "$@"
  fi
  gpid=$LANCADO
  if ((impostor)); then
    sg=$(socket_de "$gout.debug") || sg=""
    python3 -I "$AQUI/impostor-vivo" --olheiro "$RUN/olheiro.txt" --diretor "$sd" --gerente "$sg" \
      --parar "$RUN/$nome.parar" --saida "$RUN/$nome-impostor.txt" 3>&- 4>&- & # sem os fifos herdados
    ipid=$!
    PIDS+=("$ipid")
  fi
  if ((lotes > 0)); then
    local k
    for k in $(seq 1 "$lotes"); do
      printf '%s\n' "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"/prova-ponte $LOTE $PAUSA\"}}" >&4
      for _ in $(seq 1 120); do
        (($(grep -c '"type":"result"' "$gout") >= k)) && break
        sleep 0.5
      done
      (($(grep -c '"type":"result"' "$gout") >= k)) || FALHA "lote $k sem resultado em 60 s"
    done
    exec 4>&-
  fi
  timeout "$espera" tail --pid="$gpid" -f /dev/null
  kill -0 "$gpid" 2>/dev/null && FALHA "gerente $nome excedeu ${espera}s"
  sleep 2
  if [[ -n $ipid ]]; then
    : >"$RUN/$nome.parar"
    wait "$ipid" 2>/dev/null
  fi
  DIR_TURNOS=$(($(turnos "$RUN/$nome-diretor.out") - base_ass))
  kill "$dpid" 2>/dev/null
  exec 3>&-
}

echo "== par A: caminho real (modelo executa 5 Reads; tool.check cai no pedido)"
par A 180 0 0 "Use a ferramenta Read, uma de cada vez, nos arquivos /etc/hostname, /etc/hosts, /etc/os-release, /etc/shells e /etc/issue, e depois responda apenas FIM."
TURNOS_A=$DIR_TURNOS
REAIS=$(find "$RUN/log" -name '*-gerente.log' | grep -c .)
REAIS_ALLOW=$(grep -l -h 'veredito=allow' "$RUN"/log/*-gerente.log 2>/dev/null | grep -c .)
mkdir -p "$RUN/log-reais"
mv "$RUN"/log/*-gerente.log "$RUN/log-reais/" 2>/dev/null
mv "$RUN"/log/*-diretor.log "$RUN/log-reais/" 2>/dev/null

: >"$RUN/olheiro.txt" # o impostor so forja sobre os pedidos do par B
echo "== par B: $N trocas em lotes de $LOTE (/prova-ponte $LOTE $PAUSA) com o impostor vivo"
par B 900 1 $((N / LOTE))
TURNOS_B=$DIR_TURNOS

# Soma dos lotes (um arquivo por comando) e estatistica em inteiros sobre os ms brutos.
TROCAS=0 CORRETAS=0 ERRADOS=0 TIMEOUTS=0 PRIMEIRA=0
MS=""
POS=0
for f in "$RUN"/log/lote-*.txt; do
  [[ -f $f ]] || continue
  linha=$(cat "$f")
  [[ $linha =~ trocas=([0-9]+)\ corretas=([0-9]+)\ errados=([0-9]+)\ timeouts=([0-9]+)\ primeira_falha=([0-9]+)\ ms=(.*)$ ]] || continue
  TROCAS=$((TROCAS + BASH_REMATCH[1]))
  CORRETAS=$((CORRETAS + BASH_REMATCH[2]))
  ERRADOS=$((ERRADOS + BASH_REMATCH[3]))
  TIMEOUTS=$((TIMEOUTS + BASH_REMATCH[4]))
  ((PRIMEIRA == 0 && BASH_REMATCH[5] > 0)) && PRIMEIRA=$((POS + BASH_REMATCH[5]))
  POS=$((POS + BASH_REMATCH[1]))
  MS="$MS ${BASH_REMATCH[6]}"
done
MEDIANA=0 P95=0 MAX=0 SOMA_MS=0
if [[ -n ${MS// /} ]]; then
  # shellcheck disable=SC2086  # a lista de inteiros e separada por espacos de proposito
  mapfile -t ORD < <(printf '%s\n' $MS | sort -n)
  NT=${#ORD[@]}
  if ((NT % 2)); then MEDIANA=${ORD[$(((NT - 1) / 2))]}; else MEDIANA=$(((ORD[NT / 2 - 1] + ORD[NT / 2]) / 2)); fi
  P95=${ORD[$(((95 * NT + 99) / 100 - 1))]}
  MAX=${ORD[$((NT - 1))]}
  for v in "${ORD[@]}"; do SOMA_MS=$((SOMA_MS + v)); done
fi
TOTAL_MS=$SOMA_MS

ACEITAS_V=$(grep -c 'ok=1' "$RUN/verificador.log")
RECUSADAS_V=$(grep -c 'ok=0' "$RUN/verificador.log")
# "Aceita" = efeito de impostor: decisao aplicada com veredito errado (ERRADOS), ou o Diretor atendendo mais
# vezes do que ha pedidos reais, ou o gerente aplicando mais decisoes do que trocas decididas. Os ok=1 do
# verificador sozinhos nao servem: etapas de trocas legitimas interrompidas (fail-closed) tambem os geram.
PEDIDOS_B=$(grep -c . "$RUN/olheiro.txt")
ATENDIDOS=$(grep -c 'consumed by a hook (atendido' "$RUN/B-diretor.out.debug")
APLICADAS=$(grep -c 'consumed by a hook (decisao_aplicada' "$RUN/B-gerente.out.debug")
DECIDIDOS=$(grep -l -h 'motivo=decidido$' "$RUN"/log/*-gerente.log 2>/dev/null | grep -c .)
SOBRA_D=$((ATENDIDOS > PEDIDOS_B ? ATENDIDOS - PEDIDOS_B : 0))
SOBRA_G=$((APLICADAS > DECIDIDOS ? APLICADAS - DECIDIDOS : 0))
EXTRAS=$((ERRADOS + SOBRA_D + SOBRA_G))

echo
echo "-- trocas (par B, comando do mod, sem turno de modelo)"
echo "trocas=$TROCAS corretas=$CORRETAS falhas=$((TROCAS - CORRETAS)) timeouts=$TIMEOUTS primeira_falha=$PRIMEIRA"
echo "mediana_ms=$MEDIANA p95_ms=$P95 max_ms=$MAX total_ms=$TOTAL_MS"
echo "-- caminho real (par A): trocas_reais=$REAIS allow=$REAIS_ALLOW"
echo "-- motivos do gerente no par B (fail-closed visivel):"
for m in decidido timeout entrega_falhou registro_recusado excecao erro; do
  echo "motivo_$m=$(grep -l -h "motivo=$m\$" "$RUN"/log/*-gerente.log 2>/dev/null | grep -c .)"
done
echo "-- impostor vivo (forma, tentativas, aceitas)"
printf '%-30s %10s %8s\n' forma tentativas aceitas
TENT_TOT=0
FORMAS=0
if [[ -f $RUN/B-impostor.txt ]]; then
  while read -r forma n; do
    [[ $forma == _falhas_de_envio ]] && {
      ENVIO_FALHO=$n
      continue
    }
    printf '%-30s %10d %8s\n' "$forma" "$n" "$((EXTRAS > 0 ? -1 : 0))"
    # -1 = ha aceita no total e nao ha como atribuir a forma
    TENT_TOT=$((TENT_TOT + n))
    FORMAS=$((FORMAS + 1))
  done <"$RUN/B-impostor.txt"
fi
echo "-- (aceitas = 0 em toda forma quando aceitas_impostor=0; a atestacao e do TOTAL, -1 = ha aceita e nao ha como atribuir a forma)"
echo "tentativas=$TENT_TOT formas=$FORMAS envio_falho=${ENVIO_FALHO:-0} aceitas_impostor=$EXTRAS (veredito_errado=$ERRADOS diretor_a_mais=$SOBRA_D gerente_a_mais=$SOBRA_G)"
echo "pedidos_reais=$PEDIDOS_B atendidos_pelo_diretor=$ATENDIDOS decisoes_aplicadas=$APLICADAS verificador_ok=$ACEITAS_V verificador_recusadas=$RECUSADAS_V"
HERDR=$(grep -c . "$RUN/herdr.log")
echo "herdr_chamadas=$HERDR turnos_do_diretor_par_A=$TURNOS_A turnos_do_diretor_par_B=$TURNOS_B"
for papel in diretor gerente; do
  grep -q -h -E 'refused by [a-z-]+: mods are limited' "$RUN"/*-"$papel".out.debug 2>/dev/null && FALHA "mod recusado pela politica no $papel (FALHA NOMEADA, sem contornar)"
done
echo "-- run em $RUN"

((TROCAS == N)) || FALHA "trocas feitas $TROCAS de $N"
((CORRETAS == N && PRIMEIRA == 0)) || FALHA "trocas corretas $CORRETAS de $N (primeira falha: troca $PRIMEIRA)"
((TIMEOUTS == 0)) || FALHA "$TIMEOUTS timeout(s)"
((MEDIANA <= 5000)) || FALHA "mediana $MEDIANA ms acima de 5000"
((EXTRAS == 0)) || FALHA "$EXTRAS efeito(s) de impostor aceito(s)"
((TENT_TOT >= 100)) || FALHA "so $TENT_TOT tentativas de impostor (minimo 100)"
((FORMAS >= 8)) || FALHA "so $FORMAS formas de impostor (minimo 8)"
((HERDR == 0)) || FALHA "$HERDR chamada(s) ao herdr falso"
((TURNOS_A == 0 && TURNOS_B == 0)) || FALHA "turnos de modelo no Diretor: A=$TURNOS_A B=$TURNOS_B"
((REAIS == 5 && REAIS_ALLOW == 5)) || FALHA "caminho real: $REAIS trocas, $REAIS_ALLOW allow (esperado 5 e 5)"

((falha == 0)) && echo "PASS: prova da Ponte sobre mods (vivo)"
exit "$falha"
