#!/usr/bin/env bash
# issue #11 (ordem 005) — o recibo não guardava a CARGA. `ARCHITECTURE.md §NFRs`
# exige load de 1min ABSOLUTO ≤ 2,0 para uma medição de latência valer, mas o
# recibo (schema=maestro-evidence-v1) gravava só schema/label/ts/epoch/cmd_hash/
# exit/wtree_before/wtree_after/cmd_match — nenhuma carga.
#
# Caso real: recibo gravado a load 12,12 foi lido como `VÁLIDA — exit 0,
# conteúdo byte-idêntico ao provado`, sem ressalva. O diretor recusou; o CLI
# não tinha como saber.
#
# Arquivo PRÓPRIO (não em test-evidence.sh) — mesmo motivo de
# tests/cli/test-order-issue6.sh: não estourar o teto da catraca `oversized-file`.
#
# Lição das ordens 003/004: o teste NÃO exige o patch já aplicado. Ele detecta
# o MECANISMO em bin/maestro: ausente → PENDENTE, sem reprovar (bin/ está na
# denylist de autoproteção do gate, ADR-003 v1.2; quem aplica
# docs/patches/005-issue11-recibo-com-carga.patch é o Capitão); presente →
# cobra de verdade e prova o TERCEIRO ESTADO — sabota o mecanismo (aplicado
# numa CÓPIA) e mostra que a MESMA asserção reprova.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
PATCH="$REPO/docs/patches/005-issue11-recibo-com-carga.patch"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

P="$tmp/proj"; mkdir -p "$P"; git -C "$P" init -q
echo base > "$P/f"; git -C "$P" add -A; git -C "$P" -c user.email=t@t -c user.name=t commit -qm x

# ---------------------------------------------------------------------------
# Mecanismo: os 3 campos novos no `--record` + a qualificação na leitura.
# ---------------------------------------------------------------------------
PATCHED=0
grep -qF 'load1m_x100=%s\nncpu=%s\ninconclusive=%s' "$BIN" 2>/dev/null && PATCHED=1

if (( PATCHED == 0 )); then
  pending "issue #11: bin/maestro ainda sem load1m_x100/ncpu/inconclusive — aplicar $PATCH"
else
  ok "mecanismo presente: bin/maestro grava load1m_x100/ncpu/inconclusive"

  "$BIN" evidence --record --label carga --project "$P" -- true >/dev/null
  EF=$(ls "$MAESTRO_HOME/evidence"/*-carga 2>/dev/null | head -1)
  [[ -n "$EF" ]] && ok "recibo com os campos novos foi gravado" || bad "recibo não gravado"

  for campo in load1m_x100 ncpu inconclusive; do
    grep -q "^${campo}=" "$EF" 2>/dev/null && ok "recibo tem a linha $campo=" || bad "recibo sem $campo="
  done

  # --- qualificação por carga: força os dois lados via override do limiar,
  # sem depender do load REAL desta máquina (não determinístico em CI).
  sed -i 's/^load1m_x100=.*/load1m_x100=180/' "$EF"
  OUT=$(MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100=200 "$BIN" evidence --label carga --project "$P")
  grep -q 'VÁLIDA (load 1.80)' <<<"$OUT" && ok "load dentro do limiar → VÁLIDA (load X)" \
    || bad "qualificação de load dentro do limiar ($OUT)"

  sed -i 's/^load1m_x100=.*/load1m_x100=1212/' "$EF"
  OUT=$(MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100=200 "$BIN" evidence --label carga --project "$P")
  grep -q 'VÁLIDA, mas fora do limiar de medição (load 12.12)' <<<"$OUT" \
    && ok "load 12,12 (caso real) → VÁLIDA, mas fora do limiar de medição" \
    || bad "qualificação de load acima do limiar ($OUT)"

  # --- 3º item: contagem de INCONCLUSIVO sob carga, sem acoplar ao formato
  # de um teste específico — só ao vocabulário do protocolo compartilhado.
  "$BIN" evidence --record --label incon --project "$P" -- bash -c \
    'echo "== caso A"; echo "INCONCLUSIVO sob carga — foo (mediana 90ms >= teto 80ms; load 7.2/8 CPUs — não conta como falha)"; echo "== caso B"; echo "INCONCLUSIVO sob carga — bar"' \
    >/dev/null
  EF2=$(ls "$MAESTRO_HOME/evidence"/*-incon 2>/dev/null | head -1)
  chk_inc=$(awk -F= '/^inconclusive=/{print $2}' "$EF2" 2>/dev/null)
  [[ "$chk_inc" == "2" ]] && ok "2 linhas INCONCLUSIVO sob carga → inconclusive=2 no recibo" \
    || bad "contagem de inconclusivo (obtido '$chk_inc')"
  OUT=$("$BIN" evidence --label incon --project "$P")
  grep -q '2 medição(ões) INCONCLUSIVA(S) sob carga' <<<"$OUT" \
    && ok "leitura distingue exit 0 limpo de exit 0 com 2 dispensadas" \
    || bad "leitura não cita a contagem de inconclusivo ($OUT)"

  # exit != 0 continua sendo gravado (falha é dado) mesmo com `tee` no meio —
  # é a garantia que o `|| rc=\$?` original dava; o `tee` não pode perdê-la.
  "$BIN" evidence --record --label failexit --project "$P" -- bash -c 'echo x; exit 7' >/dev/null
  rc=$?
  chk_exit() { [[ "$1" == "$2" ]] && ok "$3" || bad "$3 (esperado '$2', obtido '$1')"; }
  chk_exit "$rc" "7" "record com tee ainda espelha o exit code do comando (7)"
  EF3=$(ls "$MAESTRO_HOME/evidence"/*-failexit 2>/dev/null | head -1)
  chk_exit "$(awk -F= '/^exit=/{print $2}' "$EF3" 2>/dev/null)" "7" "recibo grava exit=7, não 0 (pipefail sobrevive ao tee)"

  # ---------------------------------------------------------------------------
  # terceiro estado: sabota a QUALIFICAÇÃO numa cópia com o patch aplicado, e
  # mostra que a MESMA asserção de cima reprova.
  # ---------------------------------------------------------------------------
  # bin/maestro resolve REPO_DIR a partir do PRÓPRIO caminho (dirname/..) —
  # a cópia sabotada precisa morar em bin/ com um hooks/ irmão (symlink),
  # senão "quebra" por motivo errado (source de hooks/lib/common.sh falhando)
  # em vez do motivo que este teste quer provar.
  SABROOT="$tmp/sabotado"; mkdir -p "$SABROOT/bin"
  ln -s "$REPO/hooks" "$SABROOT/hooks"
  ln -s "$REPO/agents" "$SABROOT/agents" 2>/dev/null || :
  ln -s "$REPO/bin/maestro-wtree" "$SABROOT/bin/maestro-wtree"
  SAB="$SABROOT/bin/maestro"
  cp "$BIN" "$SAB"
  # inverte o sentido do limiar: "acima do limiar" passa a imprimir como se
  # estivesse dentro — a mensagem de qualificação mente.
  sed -i 's/if (( e_load > load_limiar )); then/if (( e_load <= load_limiar )); then/' "$SAB"
  if ! grep -q 'if (( e_load <= load_limiar )); then' "$SAB"; then
    bad "sabotagem não pegou (padrão do sed não bateu — mecanismo mudou de forma?)"
  else
    chmod +x "$SAB"
    OUT_SAB=$(MAESTRO_EVIDENCE_LOAD1M_LIMIAR_X100=200 "$SAB" evidence --label carga --project "$P" 2>&1)
    if grep -q 'VÁLIDA, mas fora do limiar de medição (load 12.12)' <<<"$OUT_SAB"; then
      bad "sabotagem não quebrou nada — a asserção passaria mesmo com o mecanismo invertido"
    else
      ok "sabotado: a mesma asserção REPROVA (obtido: '$OUT_SAB') — o teste tem dente"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# item 4 da ordem 005 — v1 ou v2, decidido por MEDIÇÃO. Regressão FROZEN: o
# leitor de bin/maestro do main em 3b300bc (ANTES desta ordem) — awk que casa
# só por NOME de campo, janela NR>12 — recebe um recibo NOVO (com os 3
# campos aditivos no fim) e continua lendo os campos que já conhecia sem
# erro. Prova que campo aditivo/opcional NÃO precisa de bump de schema — o
# leitor velho ignora em silêncio o que não reconhece. Congelado aqui como
# documentação executável do experimento (DATA_MODEL.md §8); não depende do
# estado atual de bin/maestro (roda sempre, patch aplicado ou não).
# ---------------------------------------------------------------------------
echo "-- item 4: recibo v1+campos novos, lido pelo leitor de ANTES da ordem 005 --"
V1FILE="$tmp/recibo-v1-com-campos-novos"
cat > "$V1FILE" <<'EOF'
schema=maestro-evidence-v1
label=order-5
ts=2026-09-14T10:00:00-03:00
epoch=1789403224
cmd_hash=none
exit=0
wtree_before=4b825dc642cb6eb9a060e54bf8d69288fbee4904
wtree_after=4b825dc642cb6eb9a060e54bf8d69288fbee4904
cmd_match=free
load1m_x100=180
ncpu=8
inconclusive=0
EOF
# Cópia LITERAL do trecho de extração do leitor pré-005 (bin/maestro,
# main@3b300bc, linha ~2677): mesma janela NR>12, mesmos padrões. Só o
# suficiente para provar tolerância a campo desconhecido — não é o CLI
# inteiro.
OLD_READ_OUT=$(eval "$(awk -F= 'NR>12 { exit }
  /^epoch=/        { if ($2 ~ /^[0-9]+$/)          print "e_epoch=" $2 }
  /^exit=/         { if ($2 ~ /^[0-9]+$/)          print "e_exit="  $2 }
  /^cmd_hash=/     { if ($2 ~ /^([0-9a-f]{16}|none)$/) print "e_hash=\047" $2 "\047" }
  /^cmd_match=/    { if ($2 ~ /^(yes|no|free)$/)   print "e_match=\047" $2 "\047" }
  /^wtree_before=/ { if ($2 ~ /^([0-9a-f]{40}|none)$/) print "e_wb=\047" $2 "\047" }
  /^wtree_after=/  { if ($2 ~ /^([0-9a-f]{40}|none)$/) print "e_wa=\047" $2 "\047" }' \
  "$V1FILE" 2>/dev/null)" 2>/dev/null; \
  printf 'epoch=%s exit=%s match=%s wb=%s wa=%s\n' "$e_epoch" "$e_exit" "$e_match" "$e_wb" "$e_wa")
EXPECT="epoch=1789403224 exit=0 match=free wb=4b825dc642cb6eb9a060e54bf8d69288fbee4904 wa=4b825dc642cb6eb9a060e54bf8d69288fbee4904"
if [[ "$OLD_READ_OUT" == "$EXPECT" ]]; then
  ok "item 4: leitor PRÉ-005 ignora load1m_x100/ncpu/inconclusive e lê tudo o resto certo → decisão = v1, sem migração"
else
  bad "item 4: leitor pré-005 NÃO tolerou os campos novos (obtido: '$OLD_READ_OUT') — reabrir item 4 (talvez precise ser v2)"
fi

exit $fail
