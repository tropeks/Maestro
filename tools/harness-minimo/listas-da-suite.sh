#!/usr/bin/env bash
# tools/harness-minimo/listas-da-suite.sh — as LISTAS passam/falham da suíte completa (ordem 077, seção 4).
#
# Roda `bash tests/run-all.sh` numa árvore e grava, em <saida-dir>:
#   passam.txt  os testes que PASSAM (linhas `ok   <nome>` da suíte), um por linha
#   falham.txt  os testes que FALHAM (linhas `FAIL <nome>`), um por linha
#   suite.log   a saída completa da suíte      suite.rc   o rc da suíte
# Nome = `<arquivo de teste relativo>::<nome do teste>` (o cabeçalho `== <arquivo>` da suíte dá o arquivo),
# ordenado e sem repetição. As regressões de um run são `passam.txt` da BASE ∩ `falham.txt` do FIM
# (coletar-metricas.sh --passavam-base / --falham-fim). O script mede, não julga: sai 0 com a suíte vermelha.
#
# O ambiente da suíte é montado do zero (`env -i` + HOME PATH TERM LANG + MAESTRO_HOME temporário e vazio):
# os 8 FAIL da base da 054 vêm de HERDR_ENV/HERDR_PANE_ID herdados do shell — a medição não pode herdá-los.
#
# Uso: listas-da-suite.sh <arvore> <saida-dir>
# Variável: HM_SUITE_CMD (o comando da suíte; padrão `bash tests/run-all.sh`; o teste usa uma suíte falsa).
set -u

[[ $# -eq 2 ]] || { echo "uso: listas-da-suite.sh <arvore> <saida-dir>" >&2; exit 2; }
arvore="$1" saida="$2"
[[ -d "$arvore" && -f "$arvore/tests/run-all.sh" ]] || { echo "listas-da-suite: '$arvore' não tem tests/run-all.sh" >&2; exit 2; }
mkdir -p "$saida" || exit 2
arvore="$(cd "$arvore" && pwd)"; saida="$(cd "$saida" && pwd)"
mhome="$(mktemp -d)"; trap 'rm -rf "$mhome"' EXIT

(cd "$arvore" && env -i HOME="${HOME:?}" PATH="$PATH" TERM="${TERM:-dumb}" LANG="${LANG:-C.UTF-8}" MAESTRO_HOME="$mhome" \
  bash -c "${HM_SUITE_CMD:-bash tests/run-all.sh}" < /dev/null > "$saida/suite.log" 2>&1)
echo $? > "$saida/suite.rc"

# `== <arquivo>` abre o arquivo corrente; o caminho vira relativo (do `tests/` em diante).
awk '
  /^== / { f = substr($0, 4); sub(/^.*\/tests\//, "tests/", f); next }
  /^ok[ ]+/   { n = $0; sub(/^ok[ ]+/, "", n);  print "P\t" f "::" n; next }
  /^FAIL[ ]+/ { n = $0; sub(/^FAIL[ ]+/, "", n); print "F\t" f "::" n; next }
' "$saida/suite.log" > "$mhome/marcados" || exit 1

while IFS=$'\t' read -r tipo nome; do
  if [[ "$tipo" == P ]]; then printf '%s\n' "$nome" >> "$mhome/p"; else printf '%s\n' "$nome" >> "$mhome/f"; fi
done < "$mhome/marcados"
: >> "$mhome/p"; : >> "$mhome/f"
LC_ALL=C sort -u "$mhome/p" > "$saida/passam.txt"
LC_ALL=C sort -u "$mhome/f" > "$saida/falham.txt"

echo "passam=$(wc -l < "$saida/passam.txt")"
echo "falham=$(wc -l < "$saida/falham.txt")"
echo "suite_rc=$(cat "$saida/suite.rc")"
exit 0
