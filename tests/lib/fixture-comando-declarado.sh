#!/usr/bin/env bash
# ordem 078 — fixture comum dos testes do comando declarado (evidence --record recusa antes de executar).
# Quem faz `source` já definiu: BIN, tmp, fail, ok(), bad(). Aqui só moram o projeto de teste e os ajudantes.
#
# Número da ordem: o CLI numera em sequência (001, 002…), então a ordem 1 faz o papel da "ordem 101" do
# contrato; `order-0001` e `order-1` valem a mesma ordem (10#).

# shellcheck disable=SC2154  # tmp, BIN, ok, bad vêm de quem faz source
G() { git -C "$P" -c user.email=t@t -c user.name=t "$@"; }

# mk_proj <nome> <fim-da-ordem-1> → projeto $P com .maestro.yaml (commands de área), tests/run-all.sh de
# brinquedo e a ordem 1 (com `## Turno`) COMMITADA. <fim> vazio = ordem sem o rótulo `fim:` de crases.
mk_proj() {
  P="$tmp/$1"; mkdir -p "$P/tests"
  MARK="$tmp/marcador-$1"
  git -C "$P" init -q -b main
  printf '#!/usr/bin/env bash\ntouch %s\n' "$MARK" > "$P/tests/run-all.sh"   # o comando declarado também deixa o marcador
  printf 'commands:\n  suite: bash tests/run-all.sh\n  tenant-isolation: bash tests/run-all.sh\n  billing: bash tests/run-all.sh\n  frontend: bash tests/run-all.sh\n' > "$P/.maestro.yaml"
  G add -A; G commit -qm base
  printf '%s\n' "## Objetivo
Comando declarado.

## Turno
- fatia: um turno
- fim: $2
- teto: 2
- fora: nada
- relatório: v54" | "$BIN" order --create --title "Declarada" --project "$P" --session dir-1 >/dev/null
  G add -A; G commit -qm "ordem 1"
  # o baseline do fim: (fim_commit) é gravado pelo CLI no commit da ordem; NOBASE=1 pula (teste do "sem baseline")
  [[ "${NOBASE:-0}" == 1 ]] || "$BIN" order --baseline 1 --project "$P" >/dev/null
  rm -f "$MARK"
  SCRIPT="$tmp/script-$1.sh"; printf '#!/usr/bin/env bash\ntouch %s\n' "$MARK" > "$SCRIPT"
}

# n_recibos → "<quantos>:<soma do conteúdo>" dos recibos em $MAESTRO_HOME/evidence (muda se criar OU regravar um)
n_recibos() {
  local n=0 f s=""
  for f in "$MAESTRO_HOME"/evidence/*; do [[ -e "$f" ]] && { n=$((n + 1)); s+=$(sha256sum < "$f"); }; done
  printf '%s:%s' "$n" "$(printf '%s' "$s" | sha256sum | head -c 12)"
}

# rec <rótulo> -- <comando...> → roda evidence --record em $P; REC_OUT = stdout+stderr, REC_RC = código
rec() {
  local label="$1"; shift
  REC_OUT=$("$BIN" evidence --record --label "$label" --project "$P" "$@" 2>&1); REC_RC=$?
}

# recusado <descrição> <rótulo> -- <comando...> → exige rc≠0, comando NÃO executou (sem marcador), nenhum recibo novo
recusado() {
  local desc="$1" before; shift
  before=$(n_recibos); rm -f "$MARK"
  rec "$@"
  local ok_rc=0 ok_mark=0 ok_rec=0
  (( REC_RC != 0 )) && ok_rc=1
  [[ ! -e "$MARK" ]] && ok_mark=1
  [[ "$(n_recibos)" == "$before" ]] && ok_rec=1   # n_recibos inclui o conteúdo: regravar o mesmo recibo também reprova
  if (( ok_rc && ok_mark && ok_rec )); then ok "$desc"
  else bad "$desc (rc=$REC_RC marcador=$([[ -e $MARK ]] && echo CRIADO || echo ausente) recibos $before→$(n_recibos))"; fi
}

# aceito <descrição> <rótulo> -- <comando...> → exige rc 0, o comando executou (marcador) e o recibo foi gravado
aceito() {
  local desc="$1"; shift
  rm -f "$MARK"
  rec "$@"
  if (( REC_RC == 0 )) && [[ -e "$MARK" ]] && grep -q 'evidência gravada' <<<"$REC_OUT"; then ok "$desc"
  else bad "$desc (rc=$REC_RC marcador=$([[ -e $MARK ]] && echo criado || echo AUSENTE): $REC_OUT)"; fi
}
