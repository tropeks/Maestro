#!/usr/bin/env bash
# ordem 041 — aceite por identidade (dívida de segurança, docs/ENCERRAMENTO-
# v1.md §5). Cobre a "Prova exigida" do desenho, incluindo o VETOR CANÔNICO
# (docs-ops/045/VETOR-CANONICO-prova-de-aceite.md, ponte-daemon — decisão do
# Diretor, Ponte 01M34JJYS7ZDHH2HWM877PPQS7): payload sem newline final, id
# sempre 3 dígitos, base64url sem padding, transporte "v1:<sujeito>:<sig>".
#
# Lição da 003/004A/013/017/021/022/036: o teste NÃO exige os patches já
# aplicados. Mecanismo ausente (_order_accept_require_proof) → PENDENTE
# (nunca reprova — lib/ está fora do alcance de edição comum); presente →
# cobra de verdade.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$REPO/bin/maestro"
CAP="$REPO/lib/core-order-accept-proof.sh"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
# shellcheck source=hooks/lib/project-state.sh
source "$REPO/hooks/lib/project-state.sh"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
pending() { printf 'PENDENTE  %s\n' "$1"; }

CORE_PATCHED=0
[[ -f "$CAP" ]] && grep -qF '_order_accept_proof_verify' "$CAP" 2>/dev/null && CORE_PATCHED=1
if (( CORE_PATCHED == 0 )); then
  pending "ordem 041: lib/core-order-accept-proof.sh ainda ausente/incompleto — aplicar os patches"
  exit 0
fi

git_id() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }
git_init_main() { local d="$1"; git -C "$d" init -q; git -C "$d" symbolic-ref HEAD refs/heads/main; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"

# openssl "ausente" sob demanda: PATH próprio, sem nenhum diretório que tenha
# `openssl` — construído com symlink de TODO o resto de /usr/bin /bin (não é
# um PATH vazio: o CLI precisa de bash/git/jq/awk/etc, só openssl falta).
FAKEBIN="$tmp/fakebin-sem-openssl"
mkdir -p "$FAKEBIN"
for d in /usr/bin /bin /usr/local/bin; do
  [[ -d "$d" ]] || continue
  for f in "$d"/*; do
    b="${f##*/}"
    case "$b" in openssl*) continue ;; esac
    [[ -x "$f" && ! -e "$FAKEBIN/$b" ]] && ln -s "$f" "$FAKEBIN/$b" 2>/dev/null
  done
done

# =============================================================================
# PARTE A — VETOR CANÔNICO: chamadas DIRETAS a _order_accept_proof_verify
# (sourcing o módulo), payload/chave/assinatura exatamente como o documento
# fixa. Testa o PRIMITIVO isolado do resto do CLI — é aqui que "id cru" e
# "LF final" são reproduzíveis: o CLI nunca monta esses bytes errados (o
# `%03d` e o `printf '%s\n%s\n%s\n%s'` sem newline final são estruturais),
# então a única forma honesta de provar que o verificador os REJEITA é
# chamando a função com os bytes errados de propósito.
# =============================================================================
echo "-- ordem 041: vetor canônico (docs-ops/045, ponte-daemon)"
export REPO_DIR="$REPO"
# shellcheck source=lib/core-order-accept-proof.sh
source "$CAP"
VEC_PUB="$REPO/config/accept-proof.pub"
VEC_SIG='JuDNEgEZFI0rC1kMNaVCkmdeqPgfayNeOWJScypUNx6SQCgj4VraPLNK8WRSrDqcy976Vlc1b5MGmdEbzPeTBw'
VEC_TREE='7b87b9612db81a54a2aa99d947cd35bf9c65f6a2'

if [[ ! -f "$VEC_PUB" ]]; then
  bad "(A0) config/accept-proof.pub ausente — o vetor não pode nem começar a ser testado"
else
  if _order_accept_proof_verify "$VEC_PUB" "ponte-daemon" "042" "$VEC_TREE" "spock" "$VEC_SIG"; then
    ok "(A1) vetor EXATO (projeto=ponte-daemon id=042 sujeito=spock) → verifica (rc=0)"
  else
    bad "(A1) vetor EXATO deveria verificar (rc=0), obtido rc=$?"
  fi
  if _order_accept_proof_verify "$VEC_PUB" "ponte-daemon" "42" "$VEC_TREE" "spock" "$VEC_SIG"; then
    bad "(A2) ponto (a) do vetor: id CRU '42' (sem repadronizar) deveria FALHAR e passou"
  else
    ok "(A2) ponto (a): id cru '42' em vez de '042' → recusa (payload muda, assinatura não bate)"
  fi
  if _order_accept_proof_verify "$VEC_PUB" "ponte-daemon" "042" "$VEC_TREE" "captain" "$VEC_SIG"; then
    bad "(A3) sujeito trocado (captain em vez de spock) deveria FALHAR e passou"
  else
    ok "(A3) sujeito trocado (captain) → recusa"
  fi
  if _order_accept_proof_verify "$VEC_PUB" "outro-projeto" "042" "$VEC_TREE" "spock" "$VEC_SIG"; then
    bad "(A4) projeto trocado deveria FALHAR e passou"
  else
    ok "(A4) RECUSA: prova de OUTRO projeto (payload muda) → recusa"
  fi
  if _order_accept_proof_verify "$VEC_PUB" "ponte-daemon" "041" "$VEC_TREE" "spock" "$VEC_SIG"; then
    bad "(A5) id trocado (041 em vez de 042) deveria FALHAR e passou"
  else
    ok "(A5) RECUSA: prova de OUTRA ordem (id muda) → recusa"
  fi
  if _order_accept_proof_verify "$VEC_PUB" "ponte-daemon" "042" "0000000000000000000000000000000000000000" "spock" "$VEC_SIG"; then
    bad "(A6) árvore trocada deveria FALHAR e passou"
  else
    ok "(A6) RECUSA: prova de OUTRA árvore → recusa"
  fi
  # ponto (c): payload SEM newline final — verificação estrutural (o código
  # nunca adiciona a LF; provamos que o formato SEM ela é o que o vetor exige,
  # comparando contra o openssl bruto com e sem a LF extra).
  PAYLOAD_SEM_LF=$(mktemp); PAYLOAD_COM_LF=$(mktemp); SIGFILE=$(mktemp)
  printf 'ponte-daemon\n042\n%s\nspock' "$VEC_TREE" > "$PAYLOAD_SEM_LF"
  printf 'ponte-daemon\n042\n%s\nspock\n' "$VEC_TREE" > "$PAYLOAD_COM_LF"
  printf '%s' "$VEC_SIG" | tr -- '-_' '+/' | sed 's/$/==/' | base64 -d > "$SIGFILE" 2>/dev/null
  if openssl pkeyutl -verify -pubin -inkey "$VEC_PUB" -rawin -in "$PAYLOAD_SEM_LF" -sigfile "$SIGFILE" >/dev/null 2>&1; then
    ok "(A7) ponto (c): payload SEM newline final → verifica"
  else
    bad "(A7) payload sem LF final deveria verificar"
  fi
  if openssl pkeyutl -verify -pubin -inkey "$VEC_PUB" -rawin -in "$PAYLOAD_COM_LF" -sigfile "$SIGFILE" >/dev/null 2>&1; then
    bad "(A8) ponto (c): payload COM newline final deveria FALHAR e passou"
  else
    ok "(A8) ponto (c): payload COM newline final → recusa (é por isto que o código nunca a adiciona)"
  fi
  rm -f "$PAYLOAD_SEM_LF" "$PAYLOAD_COM_LF" "$SIGFILE"
fi

# =============================================================================
# PARTE B — end-to-end via --status --json: registro forjado com os bytes
# EXATOS do vetor (projeto cujo basename é 'ponte-daemon', ordem 042, árvore
# do vetor) — é o caminho real que a DERIVAÇÃO usa (fecha a porta dos fundos).
# =============================================================================
echo "-- ordem 041: PASSA — vetor canônico via --status --json (derivação real)"
VP="$tmp/vecproj/ponte-daemon"; mkdir -p "$VP"
git_init_main "$VP"; echo a > "$VP/f.txt"; git_id "$VP" add f.txt; git_id "$VP" commit -qm base
"$BIN" order --create --title "vetor" --project "$VP" --session criador <<'BODY' >/dev/null
## Objetivo
vetor
BODY
VOF="$VP/.maestro/orders/001-vetor.md"
sed -i 's/^id: 001$/id: 042/' "$VOF"
mv "$VOF" "$VP/.maestro/orders/042-vetor.md"
VSF=$(maestro_order_state_file "$VP" 42)
mkdir -p "$(dirname "$VSF")"
{
  echo 'schema=maestro-order-state-v1'
  echo 'id=42'
  echo 'outcome=aceita'
  echo 'accepted_at=2026-09-22T12:00:00-03:00'
  echo "accepted_tree=$VEC_TREE"
  echo 'accept_proof_subject=spock'
  echo "accept_proof_sig=$VEC_SIG"
  echo 'accept_proof_version=v1'
} > "$VSF"
VST=$(MAESTRO_ACCEPT_REQUIRE_PROOF=1 "$BIN" order --status 042 --project "$VP" --json 2>&1 | jq -r '.estado // "?"' 2>/dev/null)
if [[ "$VST" == "aceita" ]]; then
  ok "(B1) PASSA: vetor canônico completo (registro real, REQUIRE ligado) → --status deriva 'aceita'"
else
  bad "(B1) PASSA: esperava 'aceita' com o vetor canônico, obtido '$VST'"
fi
# variação: sujeito trocado no MESMO registro → deixa de derivar 'aceita'
sed -i 's/^accept_proof_subject=spock$/accept_proof_subject=captain/' "$VSF"
VST2=$(MAESTRO_ACCEPT_REQUIRE_PROOF=1 "$BIN" order --status 042 --project "$VP" --json 2>&1 | jq -r '.estado // "?"' 2>/dev/null)
[[ "$VST2" != "aceita" ]] \
  && ok "(B2) sujeito trocado no registro (captain) → deixa de derivar 'aceita' (estado=$VST2)" \
  || bad "(B2) sujeito trocado deveria invalidar a derivação"
sed -i 's/^accept_proof_subject=captain$/accept_proof_subject=spock/' "$VSF"

# =============================================================================
# PARTE C — write path (--accept) com par de chaves PRÓPRIO, gerado aqui no
# tmp — NUNCA o vetor do daemon, NUNCA a chave de produção. Prova que --accept
# (a porta do COMANDO) aceita uma assinatura genuinamente válida, e que
# accepted_session vira o SUJEITO PROVADO, não o --session autodeclarado.
# =============================================================================
echo "-- ordem 041: PASSA — --accept com par de chaves autogerado (write path)"
if ! command -v openssl >/dev/null 2>&1; then
  pending "(C) openssl ausente nesta máquina — não dá para gerar par de teste"
else
  KEYDIR="$tmp/mykeys"; mkdir -p "$KEYDIR"
  openssl genpkey -algorithm ed25519 -out "$KEYDIR/priv.pem" >/dev/null 2>&1
  openssl pkey -in "$KEYDIR/priv.pem" -pubout -out "$KEYDIR/pub.pem" >/dev/null 2>&1

  P="$tmp/proj"; mkdir -p "$P"
  git_init_main "$P"
  echo a > "$P/f.txt"; git_id "$P" add f.txt; git_id "$P" commit -qm base
  "$BIN" order --create --title "Aceite por identidade" --project "$P" --session criador <<'BODY' >/dev/null
## Objetivo
Fixture da ordem 041 — cobre as recusas testáveis e o PASSA com par próprio.
BODY
OF="$P/.maestro/orders/001-aceite-por-identidade.md"
BR=$(grep '^branch:' "$OF" | awk '{print $2}')
git_id "$P" checkout -qb "$BR"
echo b >> "$P/f.txt"; git_id "$P" add f.txt; git_id "$P" commit -qm entrega
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null

# árvore que _order_proof_tree vai gravar = a tree do commit da entrega
PTREE=$(git -C "$P" rev-parse HEAD^{tree})
PNAME=$(cd -P -- "$P" && basename -- "$PWD")   # mesma técnica de _order_accept_proof_project_name

sign() { # <projeto> <id3> <arvore> <sujeito> → base64url sem padding no stdout
  local pf; pf=$(mktemp)
  printf '%s\n%s\n%s\n%s' "$1" "$2" "$3" "$4" > "$pf"
  openssl pkeyutl -sign -inkey "$KEYDIR/priv.pem" -rawin -in "$pf" 2>/dev/null \
    | base64 -w0 | tr -- '+/' '-_' | tr -d '='
  rm -f "$pf"
}
SIG_OK=$(sign "$PNAME" "001" "$PTREE" "captain")

# troca a âncora de confiança pela MINHA chave de teste, e restaura no fim
REAL_PUB="$REPO/config/accept-proof.pub"
HAD_REAL=0; [[ -f "$REAL_PUB" ]] && { HAD_REAL=1; cp "$REAL_PUB" "$tmp/real-pub-backup.pem"; }
mkdir -p "$REPO/config"
cp "$KEYDIR/pub.pem" "$REAL_PUB"
restore_pub() { if (( HAD_REAL == 1 )); then cp "$tmp/real-pub-backup.pem" "$REAL_PUB"; else rm -f "$REAL_PUB"; fi; }
trap 'restore_pub; rm -rf "$tmp"' EXIT

OUT=$(MAESTRO_ACCEPT_REQUIRE_PROOF=1 MAESTRO_ACCEPT_PROOF="v1:captain:$SIG_OK" \
  "$BIN" order --accept 1 --project "$P" --session sessao-autodeclarada 2>&1)
RC=$?
if [[ "$RC" == "0" ]]; then
  ok "(C1) PASSA: --accept com assinatura válida (par próprio) → aceita (rc=0)"
else
  bad "(C1) PASSA: --accept deveria aceitar a assinatura válida, obtido rc=$RC: $OUT"
fi
SESS=$(grep '^accepted_session:' "$OF" | tail -1 | awk '{print $2}')
if [[ "$SESS" == "captain" ]]; then
  ok "(C2) accepted_session = 'captain' (sujeito PROVADO) — NÃO 'sessao-autodeclarada' (--session ignorado)"
else
  bad "(C2) accepted_session deveria ser 'captain' (sujeito provado), obtido '$SESS'"
fi

# RECUSA: mesma assinatura, id de OUTRA ordem
"$BIN" order --create --title "Outra ordem" --project "$P" --session criador <<'BODY' >/dev/null
## Objetivo
outra ordem, mesma árvore não importa — o id já muda o payload.
BODY
OF3="$P/.maestro/orders/002-outra-ordem.md"
BR3=$(grep '^branch:' "$OF3" | awk '{print $2}')
git_id "$P" checkout -qb "$BR3"
git_id "$P" merge -q --no-edit "$BR" >/dev/null 2>&1 || true
"$BIN" evidence --record --label order-2 --project "$P" -- true >/dev/null
OUT=$(MAESTRO_ACCEPT_REQUIRE_PROOF=1 MAESTRO_ACCEPT_PROOF="v1:captain:$SIG_OK" \
  "$BIN" order --accept 2 --project "$P" --session x 2>&1)
RC=$?
[[ "$RC" != "0" ]] \
  && ok "(C3) RECUSA: prova assinada para a ordem 001 usada em --accept 2 → recusa" \
  || bad "(C3) prova de OUTRA ordem deveria recusar, aceitou (rc=$RC): $OUT"

restore_pub
fi

# =============================================================================
# PARTE D — camadas de recusa que NÃO dependem de payload correto (formato,
# ambiente). Projeto e ordem PRÓPRIOS (a ordem 001 do $P da Parte C já foi
# consumida — está genuinamente 'aceita' — reusá-la aqui mentiria um FAIL).
# =============================================================================
P="$tmp/projD"; mkdir -p "$P"
git_init_main "$P"; echo a > "$P/f.txt"; git_id "$P" add f.txt; git_id "$P" commit -qm base
"$BIN" order --create --title "D" --project "$P" --session c <<'BODY' >/dev/null
## Objetivo
D
BODY
OF="$P/.maestro/orders/001-d.md"
BR=$(grep '^branch:' "$OF" | awk '{print $2}')
git_id "$P" checkout -qb "$BR"
echo b >> "$P/f.txt"; git_id "$P" add f.txt; git_id "$P" commit -qm entrega
"$BIN" evidence --record --label order-1 --project "$P" -- true >/dev/null

accept() { # <MAESTRO_ACCEPT_PROOF ou vazio> [PATH extra] → roda --accept 1 com REQUIRE ligado
  local proof="${1:-}" path="${2:-$PATH}"
  MAESTRO_ACCEPT_REQUIRE_PROOF=1 MAESTRO_ACCEPT_PROOF="$proof" PATH="$path" \
    "$BIN" order --accept 1 --project "$P" --session dir-1
}
status_json() { "$BIN" order --status 1 --project "$P" --json 2>/dev/null; }

echo "-- ordem 041: recusas de formato/ambiente"
OUT=$(accept "" 2>&1); RC=$?
if [[ "$RC" != "0" && "$OUT" == *"prova ausente"* ]]; then
  ok "(D1) prova ausente + REQUIRE ligado → recusa (rc=$RC)"
else
  bad "(D1) prova ausente + REQUIRE ligado → esperava recusa citando 'prova ausente', obtido rc=$RC: $OUT"
fi
ST=$(status_json | jq -r '.estado // "?"' 2>/dev/null)
[[ "$ST" != "aceita" ]] && ok "(D1b) --status confirma: NÃO derivou 'aceita' (estado=$ST)" \
  || bad "(D1b) --status derivou 'aceita' sem prova nenhuma"

OUT=$(accept "v1:hacker:AAAAAAAAAAAAAAAA" 2>&1); RC=$?
if [[ "$RC" != "0" && "$OUT" == *"fora do conjunto"* ]]; then
  ok "(D2) sujeito 'hacker' → recusa (fora do conjunto)"
else
  bad "(D2) sujeito 'hacker' → esperava recusa 'fora do conjunto', obtido rc=$RC: $OUT"
fi

OUT=$(accept "v1:captain:not-valid-b64!!" 2>&1); RC=$?
if [[ "$RC" != "0" && "$OUT" == *"corrompida"* ]]; then
  ok "(D3) assinatura corrompida → recusa"
else
  bad "(D3) assinatura corrompida → esperava recusa 'corrompida', obtido rc=$RC: $OUT"
fi

for bad_env in 'captain:AAAA' 'v1:captain' 'v2:captain:AAAA'; do
  OUT=$(accept "$bad_env" 2>&1); RC=$?
  if [[ "$RC" != "0" ]]; then ok "(D4) envelope malformado '$bad_env' → recusa"
  else bad "(D4) envelope malformado '$bad_env' → deveria recusar, obtido rc=$RC: $OUT"; fi
done

# chave pública ausente: esconde a de verdade (config/accept-proof.pub agora
# EXISTE por padrão — a de teste do vetor) e restaura no fim.
REAL_PUB="$REPO/config/accept-proof.pub"
HAD_REAL2=0
if [[ -f "$REAL_PUB" ]]; then
  HAD_REAL2=1
  mv "$REAL_PUB" "$tmp/real-pub-backup2.pem"
fi
OUT=$(accept "v1:captain:AAAAAAAAAAAAAAAA" 2>&1); RC=$?
if [[ "$RC" != "0" && "$OUT" == *"chave pública ausente"* ]]; then
  ok "(D5) chave pública ausente → recusa"
else
  bad "(D5) chave pública ausente → esperava recusa 'chave pública ausente', obtido rc=$RC: $OUT"
fi
if (( HAD_REAL2 == 1 )); then mv "$tmp/real-pub-backup2.pem" "$REAL_PUB"; fi

OUT=$(accept "v1:captain:AAAAAAAAAAAAAAAA" "$FAKEBIN" 2>&1); RC=$?
if [[ "$RC" != "0" && "$OUT" == *"openssl ausente"* ]]; then
  ok "(D6) openssl ausente + REQUIRE ligado → recusa"
else
  bad "(D6) openssl ausente + REQUIRE ligado → esperava recusa 'openssl ausente', obtido rc=$RC: $OUT"
fi

OUT=$(accept "v1:captain:AAAAAAAAAAAAAAAA" 2>&1); RC=$?
if [[ "$RC" != "0" && "$OUT" == *"inválida"* ]]; then
  ok "(D7) assinatura sintaticamente válida mas matematicamente errada → recusa"
else
  bad "(D7) esperava recusa de assinatura inválida, obtido rc=$RC: $OUT"
fi

# =============================================================================
# PORTA DOS FUNDOS: carimbo accepted_* escrito À MÃO no arquivo E no
# registro, com REQUIRE ligado → NÃO deriva 'aceita'.
# =============================================================================
echo "-- ordem 041: porta dos fundos"
"$BIN" order --create --title "Porta dos fundos" --project "$P" --session criador <<'BODY' >/dev/null
## Objetivo
Carimbo manual, sem passar pela CLI — o teste que prova que a ordem fechou a
janela, não só a porta.
BODY
OF2=$(ls "$P"/.maestro/orders/*porta-dos-fundos*.md 2>/dev/null | head -1)
BR2=$(grep '^branch:' "$OF2" | awk '{print $2}')
git_id "$P" checkout -qb "$BR2" 2>/dev/null || git_id "$P" checkout -q "$BR2"
echo c >> "$P/f.txt"; git_id "$P" add f.txt; git_id "$P" commit -qm entrega-pf 2>/dev/null || true
PF_ID=$(grep '^id:' "$OF2" | head -1 | awk '{print $2}')
"$BIN" evidence --record --label "order-$((10#$PF_ID))" --project "$P" -- true >/dev/null

printf 'accepted_at: %s\naccepted_session: captain\naccepted_tree: forjada\n' "$(date -Iseconds)" >> "$OF2"
SF2=$(maestro_order_state_file "$P" "$PF_ID")
mkdir -p "$(dirname "$SF2")"
{
  echo 'schema=maestro-order-state-v1'
  echo "id=$((10#$PF_ID))"
  echo 'outcome=aceita'
  echo "accepted_at=$(date -Iseconds)"
  echo 'accepted_session=captain'
  echo 'accepted_tree=forjada'
} > "$SF2"

ST2=$(MAESTRO_ACCEPT_REQUIRE_PROOF=1 "$BIN" order --status "$((10#$PF_ID))" --project "$P" --json 2>/dev/null | jq -r '.estado // "?"')
if [[ "$ST2" != "aceita" ]]; then
  ok "(PORTA DOS FUNDOS) carimbo à mão (arquivo E registro) com REQUIRE ligado → NÃO deriva 'aceita' (estado=$ST2)"
else
  bad "(PORTA DOS FUNDOS) carimbo à mão derivou 'aceita' com REQUIRE ligado — a porta dos fundos continua aberta"
fi

ST2B=$(MAESTRO_ACCEPT_REQUIRE_PROOF=0 "$BIN" order --status "$((10#$PF_ID))" --project "$P" --json 2>/dev/null | jq -r '.estado // "?"')
[[ "$ST2B" == "aceita" ]] \
  && ok "(controle) mesmo carimbo, REQUIRE desligado → 'aceita' (migração preservada)" \
  || bad "(controle) REQUIRE desligado deveria continuar derivando 'aceita' (obtido '$ST2B')"

if (( fail )); then
  echo "FALHOU: tests/cli/test-order-041-accept-proof.sh"
  exit 1
fi
echo "OK: tests/cli/test-order-041-accept-proof.sh"
