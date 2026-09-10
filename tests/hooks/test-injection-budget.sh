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

RATCHET=7400   # bump deliberado 7230→7430 em 2026-09-10 (E26/S-2602): o Capitão pediu a
               # regra de RELATÓRIO no estilo — relatório é estado, não jornada; obstáculo
               # vencido não é notícia; erro pego antes de entregar não se relata. +186B
               # medidos, e já DEPOIS de pagar parte: quatro linhas de tipografia viraram
               # uma só no mesmo arquivo (-172B). Regra de comportamento vale mais que
               # regra de formatação, e o corte foi a forma de dizer isso com o byte.
               #
               # ATENÇÃO — segundo bump em dois dias (7080→7230→7430). O ratchet não existe
               # para impedir crescimento, existe para que ele seja dito em voz alta; dois
               # seguidos é a hora de dizer: a PRÓXIMA adição vem com uma subtração do mesmo
               # tamanho, ou não vem. Folga até o warn do doctor (7500) é de 100B.
               #
               # (bump anterior: 7080→7230 em 2026-09-09, E25/S-2502): a INSTRUÇÃO
               # CANÔNICA ganhou a linha do desfecho `killed` — "decidir NÃO fazer
               # também é desfecho", com o comando pronto. +150B medidos no cenário
               # abaixo (7064B → 7214B). Verbo que não aparece no preâmbulo ninguém
               # digita, e descarte sem registro volta como ideia nova daqui a três
               # semanas sem o porquê que já tinha sido pago: o byte se paga na
               # primeira repetição evitada. O mesmo commit traz o preâmbulo
               # graduado (`preamble: standard|lean` no .maestro.yaml), que DEVOLVE
               # 914B/3043B a quem opta — mas o ratchet segue medindo o default
               # `full`, que é o que todo projeto recebe sem escolher nada.
               # (bump anterior: 6930→7080 em 2026-09-05, E22/S-2203: linha da
               # DIREÇÃO na seção "## Projeto".) Cenário medido
               # = baseline do plugin com projeto vazio (CLAUDE_PROJECT_DIR sem .maestro.yaml;
               # roster inteiro, sem filtro experts; sem seções de projeto). Sessão real neste
               # repo mede mais (com .maestro.yaml vivo, medida pelo doctor) e é
               # governada pelo warn 7500/teto 8000 do doctor, não por este ratchet.
               # A ordem que vale é ratchet < warn < teto: 7230 < 7500 < 8000 — mover
               # um exige olhar o outro (o warn subiu de 7200 no mesmo commit, senão
               # instalação saudável nasceria com aviso que ninguém podia limpar).
               # Histórico: 5895B (08-18) → 6266B (E8+) → 6516B (E16) → 6930B (E17)
               # → 7080B (E22) → 7230B (E25). Teto duro segue 8000B.

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
# MAESTRO_NO_UPDATE_CHECK=1 alinha esta medição à do doctor (bin/maestro, mesmo
# flag): sem ele, máquina atrás do origin ou com árvore suja ganha a linha
# `atualização: …` no cabeçalho (~120B) e o ratchet reprovaria por ambiente, não
# por conteúdo. Os dois números têm de medir a MESMA coisa.
bytes=$(printf '{"session_id":"ratchet"}' \
  | MAESTRO_HOME="$h" CLAUDE_PROJECT_DIR="$p" MAESTRO_NO_UPDATE_CHECK=1 bash "$HOOK" 2>/dev/null | wc -c | tr -d ' ')
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
# Volta a exigir `ok` (E25, integração): o limiar do warn foi para 7500B no
# mesmo changeset, restaurando a ordem ratchet(7230) < warn(7500) < teto(8000).
# Aceitar `(ok|warn)` aqui deixaria passar em silêncio o dia em que o default
# cruzar a folga — que é exatamente o que esta asserção existe para pegar.
grep -qE 'ok   injeção SessionStart: [0-9]+B de 8000B' "$tmp/doc" \
  && ok "linha da conta no doctor (faixa ok: default abaixo do warn)" \
  || bad "linha da conta no doctor (faixa ok: default abaixo do warn)"
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
