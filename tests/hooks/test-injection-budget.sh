#!/usr/bin/env bash
# E7 / S-703 + S-704 — ratchet da injeção do SessionStart + checks de ambiente
# do doctor (agent teams, MCP fora-do-envelope, conta da injeção no envelope).
#
# PROTOCOLO DO RATCHET (padrão gstack-context-bill, RAD_PATTERNS §5.9): o teto
# consciente abaixo dos 8000B duros. Toda adição de seção à injeção DEVE vir com
# o bump deliberado deste número no MESMO commit — é o que impede "só mais uma
# seção" de comer o orçamento em silêncio. Nunca suba o ratchet sem dizer no
# commit POR QUÊ.
set -u

RATCHET=6930   # bump deliberado 6800→6930 em 2026-08-31 (E17/S-1703): cenário medido
               # = baseline do plugin com projeto vazio (CLAUDE_PROJECT_DIR sem .maestro.yaml;
               # roster inteiro, sem filtro experts; sem seções de projeto). Sessão real neste
               # repo mede mais (~6940B com .maestro.yaml vivo, medida pelo doctor) e é
               # governada pelo warn 7200/teto 8000 do doctor, não por este ratchet.
               # Histórico: 5895B (08-18) → 6266B (E8+) → 6516B (E16) → 6930B (E17).
               # Teto duro segue 8000B.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/session-start.sh"
BIN="$REPO/bin/maestro"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v jq >/dev/null || { echo "FAIL jq ausente (dependência declarada)"; exit 1; }

echo "-- S-703: ratchet da injeção"
h=$(mktemp -d "$tmp/h.XXXXXX"); p=$(mktemp -d "$tmp/p.XXXXXX")
bytes=$(printf '{"session_id":"ratchet"}' \
  | MAESTRO_HOME="$h" CLAUDE_PROJECT_DIR="$p" bash "$HOOK" 2>/dev/null | wc -c | tr -d ' ')
[[ "$bytes" =~ ^[0-9]+$ && "$bytes" -gt 0 ]] \
  && ok "injeção medida: ${bytes}B" || bad "injeção medida (obtido '$bytes')"
[[ "$bytes" -le 8000 ]] && ok "dentro do teto duro de 8000B" \
                        || bad "dentro do teto duro de 8000B (${bytes}B)"
if [[ "$bytes" -le $RATCHET ]]; then
  ok "dentro do RATCHET de ${RATCHET}B"
else
  bad "RATCHET estourado: ${bytes}B > ${RATCHET}B — seção nova? bump consciente no mesmo commit"
fi

echo "-- S-703: doctor reporta a conta e grava no envelope"
h2=$(mktemp -d "$tmp/h2.XXXXXX")
MAESTRO_HOME="$h2" "$BIN" doctor >"$tmp/doc" 2>&1
grep -qE 'ok   injeção SessionStart: [0-9]+B de 8000B' "$tmp/doc" \
  && ok "linha da conta no doctor" || bad "linha da conta no doctor"
inj=$(jq -r '.injection.bytes' "$h2/capabilities.json" 2>/dev/null)
[[ "$inj" =~ ^[0-9]+$ && "$inj" -gt 0 ]] \
  && ok "envelope carrega injection.bytes=${inj} (inteiro)" \
  || bad "envelope carrega injection.bytes (obtido '$inj')"
[[ "$(jq -r '.injection.budget' "$h2/capabilities.json" 2>/dev/null)" == "8000" ]] \
  && ok "envelope carrega injection.budget=8000" || bad "envelope carrega injection.budget=8000"

echo "-- S-704: agent teams experimental"
grep -q 'ok   agent teams experimental inativo' "$tmp/doc" \
  && ok "sem a env: reporta inativo" || bad "sem a env: reporta inativo"
h3=$(mktemp -d "$tmp/h3.XXXXXX")
MAESTRO_HOME="$h3" CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 "$BIN" doctor >"$tmp/doc2" 2>&1
grep -q 'warn agent teams experimental ATIVO' "$tmp/doc2" \
  && ok "com a env: warn (teams podem se formar sem pedido)" \
  || bad "com a env: warn"
grep -q 'doctor: instalação saudável' "$tmp/doc2" \
  && ok "warn não derruba o doctor" || bad "warn não derruba o doctor"

echo "-- S-704: MCP fora-do-envelope (só nomes, nunca config)"
fakehome=$(mktemp -d "$tmp/home.XXXXXX")
printf '{"mcpServers":{"supermemory":{"url":"https://SECRET.example"},"outro":{}}}' \
  > "$fakehome/.claude.json"
h4=$(mktemp -d "$tmp/h4.XXXXXX")
HOME="$fakehome" MAESTRO_HOME="$h4" "$BIN" doctor >"$tmp/doc3" 2>&1
grep -qE 'MCP fora-do-envelope: 2 server\(s\) — .*outro supermemory' "$tmp/doc3" \
  && ok "nomeia os servers do ~/.claude.json (ordenados)" \
  || bad "nomeia os servers do ~/.claude.json"
grep -q 'SECRET' "$tmp/doc3" \
  && bad "config/URL de MCP NÃO vaza no doctor" \
  || ok  "config/URL de MCP NÃO vaza no doctor"
fakehome2=$(mktemp -d "$tmp/home2.XXXXXX")
h5=$(mktemp -d "$tmp/h5.XXXXXX")
HOME="$fakehome2" CLAUDE_PROJECT_DIR="$fakehome2" MAESTRO_HOME="$h5" "$BIN" doctor >"$tmp/doc4" 2>&1
grep -q 'MCP fora-do-envelope: nenhum configurado' "$tmp/doc4" \
  && ok "sem config: reporta nenhum" || bad "sem config: reporta nenhum"

exit $fail
