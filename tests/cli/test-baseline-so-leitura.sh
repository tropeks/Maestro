#!/usr/bin/env bash
# ordem 058 — tools/baseline.sh é SOMENTE LEITURA: sobre um repo de fixture, um ledger
# de fixture e um "runner" (ssh falso) nada muda — hash antes e depois iguais — e o
# único comando que chega ao runner é de leitura. Controle negativo: o detector de hash
# de fato enxerga uma escrita.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/tools/baseline.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"
P="$tmp/proj"
mkdir -p "$P/.maestro/orders" "$MAESTRO_HOME"/{order-state,evidence,logs} "$tmp/bin"
git -C "$P" init -q -b main
git -C "$P" config user.email t@t; git -C "$P" config user.name t
printf '<!-- maestro-order v1\nid: 001\nts: x\nepoch: 1700000000\n-->\n# o\n' > "$P/.maestro/orders/001-x.md"
git -C "$P" add -A; git -C "$P" commit -qm "ordem 001"
git -C "$P" checkout -q -b order/001-x
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm "feat"
git -C "$P" checkout -q main

KEY=$(source "$REPO/hooks/lib/project-state.sh"; b=$(maestro_brief_file "$P"); b="${b##*/}"; echo "${b%.md}")
printf 'schema=maestro-order-state-v1\nid=1\noutcome=aceita\naccepted_at=2023-11-14T20:00:00-03:00\n' > "$MAESTRO_HOME/order-state/$KEY-001"
printf 'schema=maestro-evidence-v1\nlabel=order-1\nepoch=1700001800\nexit=0\n' > "$MAESTRO_HOME/evidence/$KEY-order-1"
{ echo '{"ts":"2026-01-01T10:00:00-03:00","event":"decision","session_id":"s1","project":"proj"}'
  echo '{"ts":"2026-01-01T10:01:00-03:00","event":"gate_warn","tool":"Edit","session_id":"s1"}'
  echo '{"ts":"2026-01-01T10:02:00-03:00","event":"turno_teto","session_id":"s1","n":"1"}'
} > "$MAESTRO_HOME/logs/routing.jsonl"

# ssh falso: registra o comando e responde como um lab-ci; qualquer coisa fora da lista de leitura = veneno
cat > "$tmp/bin/ssh" <<'STUB'
#!/usr/bin/env bash
cmd="${*: -1}"
printf '%s\n' "$cmd" >> "$STUB_LOG"
printf '0.50 0.40 0.30 1/200 999\n8\nMemTotal: 16384000 kB\nMemAvailable: 8192000 kB\n1\n0\n'
STUB
chmod +x "$tmp/bin/ssh"
export STUB_LOG="$tmp/ssh.log"; : > "$STUB_LOG"
export PATH="$tmp/bin:$PATH" MAESTRO_BASELINE_LAB_SSH="lab-fake"

snap() { # hash de tudo que não pode mudar: repo (com .git), ledger, runner
  ( cd "$tmp" && find proj home bin -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64 )
}

before=$(snap)
j=$(bash "$TOOL" --project "$P" --format json 2>/dev/null); rc1=$?
m=$(bash "$TOOL" --project "$P" --format md 2>/dev/null);   rc2=$?
a=$(bash "$TOOL" --all --format json 2>/dev/null);          rc3=$?
w=$(bash "$TOOL" --project "$P" --format json --since 1 --next 10 2>/dev/null); rc4=$?
after=$(snap)

[[ $rc1 -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 && $rc4 -eq 0 ]] && ok "as quatro execuções saem 0" || bad "rc: $rc1 $rc2 $rc3 $rc4"
[[ "$before" == "$after" ]] && ok "hash do repo, do ledger e do runner igual antes e depois" || bad "algo mudou (hash difere)"
jq -e '.metricas|length==6' <<<"$j" >/dev/null && ok "seis métricas" || bad "esperava 6 métricas"
jq -e '.metricas[0].ordens[0].parada_em_pronta_s==1000' <<<"$j" >/dev/null \
  && ok "métrica 1 calculada do ledger (aceita - provada = 1000)" || bad "métrica 1 errada: $(jq -c '.metricas[0]' <<<"$j")"
jq -e '.metricas[4].load1m_x100==50 and .metricas[4].ncpu==8' <<<"$j" >/dev/null && ok "métrica 5 lida do runner" || bad "métrica 5 errada"
jq -e '.metricas[3].turnos==1 and .metricas[3].permissoes==1' <<<"$j" >/dev/null && ok "métrica 4 do routing.jsonl" || bad "métrica 4 errada"
[[ -n "$m" ]] && grep -q '^## 6\.' <<<"$m" && ok "saída markdown tem as seis seções" || bad "markdown sem a seção 6"
jq -e '.selecao|test("1 encontrado")' <<<"$w" >/dev/null && ok "--since/--next seleciona os aceites" || bad "janela de aceites errada"

# o runner só recebe comandos de leitura
if [[ -s "$STUB_LOG" ]] && ! grep -Eq '(^|[ ;|&])(rm|mv|cp|kill|systemctl|tee|dd|chmod|chown|sed -i|>)' "$STUB_LOG" \
   && ! grep -q '>' "$STUB_LOG"; then ok "ssh só com comandos de leitura"; else bad "comando não-leitura no runner: $(cat "$STUB_LOG")"; fi

# controle negativo: o detector enxerga uma escrita
echo x >> "$P/a"
[[ "$(snap)" != "$before" ]] && ok "controle negativo: o hash detecta escrita" || bad "o detector de hash é cego"

exit $fail
