#!/usr/bin/env bash
# ordem 047 — a autoproteção do gate também vale para o BASH: redirecionamento,
# tee, sed -i, cp, mv, install, dd of=, ln, truncate, perl -i e python/node com
# alvo em self_paths saem rc 2 no pre-bash-guard. Cada forma × cada raiz da
# denylist × caminho relativo/absoluto/worktree/`./`/`../`. Controles negativos
# (leitura, docs/, tests/, /tmp, projeto de fora), fail-open (kill-switch,
# política ausente/truncada cai no fallback, nunca em "libera tudo") e latência.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO/hooks/pre-bash-guard.sh"

source "$REPO/tests/lib/env-clean.sh"
maestro_env_clean_inherit
source "$REPO/tests/lib/latency.sh"
command -v jq >/dev/null || { echo "PENDENTE  jq ausente — teste da ordem 047 pulado"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MAESTRO_HOME="$tmp/home"; mkdir -p "$MAESTRO_HOME"

fail=0; nok=0
ok()  { nok=$((nok + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# --- um "plugin" de mentira: repo + worktree + política compilada --------------
PL="$tmp/plugin"; WT="$tmp/wt"; OUT="$tmp/outro"
git init -q -b main "$PL"; echo a > "$PL/f"; git -C "$PL" add -A
git -C "$PL" -c user.email=t@t -c user.name=t commit -qm base
git -C "$PL" worktree add -q "$WT" -b wt 2>/dev/null
git init -q -b main "$OUT"
for d in agents bin src hooks lib config .claude-plugin tests docs .maestro; do mkdir -p "$PL/$d" "$WT/$d" "$OUT/$d"; done
SELF="agents/ bin/ src/ hooks/ lib/ config/routing-table.yaml config/accept-proof.pub .claude-plugin/"
cat > "$tmp/policy.sh" <<EOF
MAESTRO_GATE_MODE="block"
MAESTRO_GATE_DENY_SELF="$SELF"
MAESTRO_PLUGIN_ROOT="$PL"
EOF
export MAESTRO_GATE_POLICY="$tmp/policy.sh"

payload() { jq -n --arg c "$1" --arg d "$2" '{session_id:"s047",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
run() { payload "$1" "$2" | bash "$GUARD" >/dev/null 2>&1; echo $?; }       # <comando> <cwd> → rc
expect() { # <rc esperado> <rótulo> <comando> <cwd>
  local got; got=$(run "$3" "$4")
  if [[ "$got" == "$1" ]]; then ok; else bad "$2: rc=$got (esperado $1) — $3"; fi
}

ROOTS="agents/a.md bin/maestro src/cli.ts hooks/h.sh lib/l.sh config/routing-table.yaml config/accept-proof.pub .claude-plugin/plugin.json"

# --- (1) toda forma × toda raiz, caminho relativo, cwd na raiz do plugin --------
forms=(
  'echo x > %P' 'echo x >> %P' 'echo x &> %P' 'echo x >| %P'
  $'cat > %P <<EOF\nbody\nEOF'
  'printf x | tee %P' 'printf x | tee -a %P'
  'sed -i s/a/b/ %P' 'sed -i.bak s/a/b/ %P' 'sed --in-place s/a/b/ %P' 'sed -ni p %P'
  'cp /tmp/a %P' 'cp -r /tmp/a %P' 'cp -t %P /tmp/a'
  'mv /tmp/a %P' 'install -m 755 /tmp/a %P'
  'dd if=/dev/zero of=%P bs=1 count=1' 'ln -sf /tmp/a %P' 'truncate -s 0 %P'
  'perl -pi -e s/a/b/ %P'
  "python3 -c \"open('%P','w').write('y')\"" "node -e \"require('fs').writeFileSync('%P','y')\""
  'cd /tmp && echo x > %P' 'true && echo x > %P' 'echo ok; echo x > %P'
)
for f in "${forms[@]}"; do
  for p in $ROOTS; do expect 2 "forma × raiz" "${f//%P/$p}" "$PL"; done
done
printf 'ok   %s formas × %s raízes (relativo, cwd no plugin) → rc 2\n' "${#forms[@]}" "$(wc -w <<<"$ROOTS")"

# --- (2) estilos de caminho: absoluto, worktree, ./, ../, cwd no worktree -------
styles=3
for p in $ROOTS; do
  for f in 'echo x > %P' 'cp /tmp/a %P' "python3 -c \"open('%P','w')\"" 'sed -i s/a/b/ %P'; do
    expect 2 "absoluto no plugin"   "${f//%P/$PL/$p}" "$OUT"
    expect 2 "absoluto no worktree" "${f//%P/$WT/$p}" "$OUT"
    expect 2 "cwd no worktree"      "${f//%P/$p}"     "$WT"
    expect 2 "com ./"               "${f//%P/.\/$p}"  "$PL"
    expect 2 "com ../ (cwd tests/)" "${f//%P/..\/$p}" "$PL/tests"
    expect 2 "com tests/../"        "${f//%P/tests\/..\/$p}" "$PL"
  done
done
echo "ok   caminhos absoluto/worktree/./../ → rc 2"

# --- (3) controles negativos: nada disto pode bloquear ---------------------------
neg=(
  'cat lib/l.sh' 'grep x lib/l.sh' 'sed -n 1,5p lib/l.sh' 'sed s/a/b/ lib/l.sh' 'cp lib/l.sh /tmp/b' 'ls -la bin/' 'bash tests/x.sh > /tmp/log'
  'echo x > docs/a.md' 'echo x > tests/t.sh' 'echo x > .maestro/o.md' 'echo x > /tmp/x' 'sed -i s/a/b/ docs/a.md'
  'cp /tmp/a docs/b' 'mv /tmp/a tests/c' 'printf x | tee tests/t' 'git commit -qm msg' 'git status' 'ls' 'echo 2>&1 | cat'
  "python3 -c \"open('/tmp/x','w').write('y')\"" 'python3 /tmp/script.py' 'bin/maestro order --status 1'
  'dd if=lib/l.sh of=/tmp/d' 'ln -s lib/l.sh /tmp/link'
)
for c in "${neg[@]}"; do expect 0 "controle negativo" "$c" "$PL"; done
expect 0 "projeto de FORA do plugin: lib/ dele não é do Maestro" 'echo x > lib/a.sh' "$OUT"
expect 0 "projeto de fora: sed -i em bin/" 'sed -i s/a/b/ bin/maestro' "$OUT"
echo "ok   controles negativos (leitura, docs/, tests/, /tmp, projeto de fora) → rc 0"

# --- (4) fail-open e fallback ---------------------------------------------------
c='echo x > lib/a.sh'
got=$(payload "$c" "$PL" | MAESTRO_OFF=1 bash "$GUARD" >/dev/null 2>&1; echo $?)
[[ "$got" == 0 ]] && ok || bad "kill-switch não liberou (rc=$got)"
# política ausente: fallback embutido + raiz do próprio hook (REPO) — NUNCA "libera tudo"
got=$(payload "echo x > $REPO/lib/zz.sh" "$REPO" | MAESTRO_GATE_POLICY=/nao/existe bash "$GUARD" >/dev/null 2>&1; echo $?)
[[ "$got" == 2 ]] && ok || bad "política ausente liberou escrita em lib/ do plugin (rc=$got)"
printf 'MAESTRO_PLUGIN_ROOT="%s"\n' "$PL" > "$tmp/trunc.sh"
got=$(payload "$c" "$PL" | MAESTRO_GATE_POLICY="$tmp/trunc.sh" bash "$GUARD" >/dev/null 2>&1; echo $?)
[[ "$got" == 2 ]] && ok || bad "política truncada (sem DENY_SELF) desarmou a autoproteção (rc=$got)"
# o MESMO buraco no Write: política parcial usava um default SEM lib/ (session-start já o incluía)
wj=$(jq -n --arg d "$PL" --arg f "$PL/lib/zz.sh" '{session_id:"s047",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f,content:"x"}}')
got=$(printf '%s' "$wj" | MAESTRO_GATE_POLICY="$tmp/trunc.sh" bash "$REPO/hooks/pre-tool-gate.sh" >/dev/null 2>&1; echo $?)
[[ "$got" == 2 ]] && ok || bad "Write em lib/ com política parcial passou (default do gate sem lib/, rc=$got)"
printf 'isto nao e shell valido ((\n' > "$tmp/lixo.sh"
got=$(payload "$c" "$PL" | MAESTRO_GATE_POLICY="$tmp/lixo.sh" bash "$GUARD" >/dev/null 2>&1; echo $?)
[[ "$got" =~ ^[02]$ ]] && ok || bad "política corrompida deu rc inesperado ($got)"
echo "ok   kill-switch libera; política ausente/truncada cai no fallback (rc 2), não em 'libera tudo'"

# --- (5) mensagem e log -----------------------------------------------------------
msg=$(payload "$c" "$PL" | bash "$GUARD" 2>&1 >/dev/null)
grep -q "protegido" <<<"$msg" && grep -q "git apply" <<<"$msg" && ok || bad "mensagem não explica o caminho do patch ($msg)"
grep -qiE "kill|MAESTRO_OFF" <<<"$msg" && bad "a mensagem ensina o kill-switch" || ok
grep -rqs 'self_path_write' "$MAESTRO_HOME/logs" && ok || bad "gate_block cmd=self_path_write não foi logado"
echo "ok   mensagem aponta o molde do patch, sem kill-switch; gate_block registrado (só metadado)"

# --- (6) latência: comando comum sem fork de git; candidato barato ------------------
mkdir -p "$tmp/fb"
printf '#!/bin/sh\necho git >> "%s/forks.log"\nexec %s "$@"\n' "$tmp" "$(command -v git)" > "$tmp/fb/git"; chmod +x "$tmp/fb/git"
: > "$tmp/forks.log"
payload 'ls -la docs/ && cat README.md' "$PL" | PATH="$tmp/fb:$PATH" bash "$GUARD" >/dev/null 2>&1
payload 'cat lib/l.sh' "$PL" | PATH="$tmp/fb:$PATH" bash "$GUARD" >/dev/null 2>&1
payload 'cp /tmp/a docs/b' "$OUT" | PATH="$tmp/fb:$PATH" bash "$GUARD" >/dev/null 2>&1
[[ ! -s "$tmp/forks.log" ]] && ok || bad "o guard forkou git ($(wc -l < "$tmp/forks.log")x) em comando que não escreve em self_paths"
maestro_latency_read_load
payload 'git status && ls -la' "$PL" > "$tmp/c1.json"
payload 'cat lib/l.sh | head -5' "$PL" > "$tmp/c2.json"
payload 'echo x > docs/note.md' "$PL" > "$tmp/c3.json"
printf '#!/usr/bin/env bash\nexec bash "%s"\n' "$GUARD" > "$tmp/g.sh"; chmod +x "$tmp/g.sh"
for n in c1 c2 c3; do
  maestro_latency_measure "$tmp/g.sh" "$tmp/$n.json"
  maestro_latency_report "guard $n" "$MIN" "$MED" "$MAX" 50
  case "$MAESTRO_LATENCY_VERDICT" in
    ok) ok ;;
    inconclusivo) printf 'INCONCLUSIVO sob carga: guard %s (mediana %sms)\n' "$n" "$MED" ;;
    *) bad "guard $n estourou 50 ms (mediana ${MED}ms)" ;;
  esac
done

(( fail == 0 )) && printf 'ok   %s asserções, todas verdes\n' "$nok"
exit "$fail"
