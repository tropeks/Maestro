#!/usr/bin/env bash
# ordem 063 item 3 — `gh` também no --all: roda POR REPO (cd na raiz), só leitura
# (gh pr list e gh run list). Cada chave do ledger tem de resolver para um repo.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/baseline.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"/{order-state,evidence,logs} "$tmp/bin" "$tmp/repos"
: > "$MAESTRO_HOME/logs/routing.jsonl"
export MAESTRO_BASELINE_REPOS="$tmp/repos"
# dois repos de fixture sob a raiz de busca
for n in alfa beta; do
  git -C "$tmp/repos" init -q -b main "$n"; git -C "$tmp/repos/$n" config user.email t@t; git -C "$tmp/repos/$n" config user.name t
  echo a > "$tmp/repos/$n/a"; git -C "$tmp/repos/$n" add -A; git -C "$tmp/repos/$n" commit -qm base
  k=$(source "$REPO/hooks/lib/project-state.sh"; b=$(maestro_brief_file "$tmp/repos/$n"); b="${b##*/}"; echo "${b%.md}")
  printf 'schema=maestro-order-state-v1\nid=1\noutcome=aceita\naccepted_at=2026-10-05T10:00:00-03:00\n' > "$MAESTRO_HOME/order-state/$k-001"
  printf 'schema=maestro-evidence-v1\nlabel=order-1\nepoch=1791200000\nexit=0\n' > "$MAESTRO_HOME/evidence/$k-order-1"
done
# gh simulado: registra cwd e argumentos; só aceita pr list e run list
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "$(basename "$PWD")" "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list")  echo '[{"number":1,"mergedAt":"2026-10-05T10:10:00Z","headRefOid":"abc"}]' ;;
  "run list") echo '[{"headSha":"abc","updatedAt":"2026-10-05T10:00:00Z"}]' ;;
  *) exit 9 ;;
esac
STUB
printf '#!/usr/bin/env bash\nprintf " 10:00:00 up 1 day, load average: 0,50, 0,40, 0,30\\n8\\n"\nprintf "total used free shared buff avail\\nMem.: 16000 4000 8000 100 4000 8000\\n"\nprintf "actions.runner.x.service loaded active running Runner\\n---\\n1\\n"\n' > "$tmp/bin/ssh"
chmod +x "$tmp/bin/gh" "$tmp/bin/ssh"
export GH_LOG="$tmp/gh.log"; : > "$GH_LOG"
export PATH="$tmp/bin:$PATH" MAESTRO_BASELINE_LAB_SSH=lab-fake
export MAESTRO_PONTE_DB="$tmp/ponte.db"
sqlite3 "$MAESTRO_PONTE_DB" "CREATE TABLE manager_run(run_id TEXT, project TEXT, order_ref TEXT, created_at TEXT);
  CREATE TABLE decision(kind TEXT, project TEXT, order_ref TEXT, tool_name TEXT, created_at TEXT);"

j=$(bash "$TOOL" --all --format json 2>"$tmp/err"); rc=$?
[[ $rc -eq 0 ]] && ok "--all com dois repos resolvidos: exit 0" || bad "rc=$rc err=$(cat "$tmp/err")"
for n in alfa beta; do
  [[ "$(grep -c "^$n|pr list " "$GH_LOG")" -eq 1 && "$(grep -c "^$n|run list " "$GH_LOG")" -eq 1 ]] \
    && ok "gh rodou uma vez por tipo no repo $n (cwd = raiz do repo)" || bad "gh no repo $n: $(cat "$GH_LOG")"
done
[[ -s "$GH_LOG" ]] && ! grep -Evq '^[a-z]+\|(pr list|run list) ' "$GH_LOG" && ok "gh só com pr list e run list" || bad "gh fora da lista: $(cat "$GH_LOG")"
[[ "$(wc -l < "$GH_LOG")" -eq 4 ]] && ok "exatamente 4 chamadas (2 repos × 2 comandos)" || bad "chamadas: $(wc -l < "$GH_LOG")"
jq -e '.metricas[1].status=="ok" and .metricas[1].prs==2 and .metricas[1].mediana_s==600' <<<"$j" >/dev/null \
  && ok "métrica 2 no --all: 2 PRs somados, mediana 600 s" || bad "métrica 2: $(jq -c '.metricas[1]' <<<"$j")"

exit $fail
