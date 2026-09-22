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

RATCHET=7308   # DESCIDA deliberada 7310→7308 em 2026-09-22 (ordem 039): H9 nasce
               # (config/routing-table.yaml, execution_heuristics) — a régua de
               # QUAL effort/omitClaudeMd cada agente recebe quando essa mudança
               # de frontmatter acontecer (H9 não muda nenhum agente por si; só
               # diz a regra). +150B medidos (H9 compacta, citando H8 por
               # referência em vez de repetir a lista de perfis). Pago no MESMO
               # changeset com cortes de prosa redundante em H1/H2/H4/H5/H7 (a
               # DECISÃO de cada heurística sobrevive inteira; o que saiu foi
               # reafirmação que já estava implícita ou dita em outro lugar —
               # mesma moeda do corte que pagou H8 em 2026-09-19):
               #   H1  -58B  "delegar um bugfix de uma linha a um especialista
               #              sonnet custa menos que fazê-lo no contexto
               #              principal" → "ainda é mais barato que o contexto
               #              principal" (a comparação already é o ponto; o
               #              exemplo "bugfix de uma linha" não muda a decisão)
               #   H2  -17B  "ou que cita duas ou mais áreas" → "ou cita duas+
               #              áreas" (mesma regra, prosa mais curta)
               #   H4  -15B  "componha com H5 (ou dev-pleno)" → "componha com
               #              H5" (H5 JÁ é "a linguagem do alvo escolhe o
               #              especialista"; dev-pleno é o residual que H5 usa
               #              quando nenhum especialista cobre — dizer os dois
               #              nomes aqui repetia o que H5 já cobre)
               #   H5  -37B  "(do .maestro.yaml do projeto ou do arquivo citado,
               #              não da palavra usada no pedido)" → "(do
               #              projeto/arquivo, não da palavra do pedido)"
               #   H7  -33B  removida a cauda "quando um projeto está nascendo"
               #              — redundante com o próprio nome "day-zero" que a
               #              frase anterior já usa
               #   =-160B líquido nos cortes contra +152B líquido de H9 (a régua
               #          decai porque os cortes correram um pouco à frente do
               #          necessário — sobrou 2B, não é intervalo generoso).
               #
               # (bump anterior: 7317→7310 em 2026-09-19, ordem 024 fatia 1): a
               # heurística H8 (coluna model, config/routing-table.yaml) sobe na
               # injeção — mapeia PERFIL da tarefa → haiku|sonnet|opus (ADR-004),
               # o eixo que faltava para o `decide` escolher modelo sem depender só
               # do agente do roster. Conta, em bytes medidos nesta forge (cenário
               # HERMÉTICO, igual ao do doctor):
               #   +188B  H8 inteira (nova)
               #    -77B  H1: cortada a cláusula final ("em direct não existe
               #          agente — o campo agents não vai no record") e a citação
               #          "(ADR-004)" que a acompanhava — FATO mecânico que o
               #          `decide` já recusa sozinho (--agents não se aplica a
               #          mode=direct); repetir na heurística era pagar byte por
               #          algo que o CLI garante sem depender do texto
               #    -34B  H4: "→ quem planeja é o arquiteto (opus): tier caro,
               #          raro; plano comum segue no engenheiro" virou "→
               #          arquiteto (opus) planeja; comum fica no engenheiro" —
               #          mesma decisão, sem a reafirmação de que opus é caro/raro
               #          (já dito por "opus" ser exceção em todo o resto do arquivo)
               #    -65B  H3: "VENCE H5: o tiering de custo é a razão de existir
               #          do roster, e mecânico em haiku é mais barato que
               #          mecânico em especialista sonnet (ADR-004)" virou "VENCE
               #          H5 (ADR-004): mecânico em haiku é mais barato que em
               #          especialista sonnet" — a heurística guarda a DECISÃO,
               #          o argumento completo mora no ADR-004 citado
               #    -19B  H7: removido o parêntese "(cite doc+seção)" — instrução
               #          de formato, não de roteamento; a AC de brief/depth
               #          (DATA_MODEL §3 v1.7) já cobre o que "deep" exige citar
               #     =-7B líquido no cenário HERMÉTICO (o que este ratchet mede):
               #          7317B → 7310B. Quatro cortes pagam um H8 inteiro e ainda
               #          sobra — mesma moeda do bump de ordem 026 (regra de
               #          COMPORTAMENTO/decisão vale mais que reafirmação do que
               #          já é mecânico ou já está citado em outro lugar).
               #
               # (bump anterior: 7400→7317 em 2026-09-18, ordem 026): o session-start
               # ganhou a linha de papercuts (contagem + ponteiro para
               # $MAESTRO_HOME/papercuts.md), e ela foi paga ANTES de nascer. A conta,
               # em bytes medidos nesta forge:
               #   +135B  linha de papercuts — SÓ em máquina que tem papercuts; o
               #          tamanho é O(1) em dígitos, então o papercut nº 50 custa o
               #          mesmo que o nº 5 (é por isso que vai CONTAGEM e não conteúdo)
               #   -163B  regra de TIPOGRAFIA do config/communication-style.md ("Formato
               #          serve ao conteúdo: lista numerada… `código`… negrito…"). O corte
               #          não perde a regra: a linha que ficou já diz "Base: Google
               #          developer documentation style guide", e é lá que a tipografia
               #          mora inteira — a injeção estava pagando bytes para repetir, por
               #          extenso, o que a referência nomeada já entrega. Mesma moeda com
               #          que o bump anterior se pagou ("quatro linhas de tipografia
               #          viraram uma só, -172B"): regra de COMPORTAMENTO vale mais que
               #          regra de FORMATAÇÃO, e o corte é a forma de dizer isso com o byte.
               #    +80B  linha de BOOTSTRAP na máquina de registro VAZIO (segunda rodada,
               #          decisão do diretor revendo a recusa por preço): registro vazio não
               #          fica mudo, porque máquina nova é onde o gerente mais precisa saber
               #          que o mecanismo existe e é onde ele não descobre por caminho
               #          nenhum — o único anúncio seria a linha que só nasce DEPOIS do
               #          primeiro registro. Leva só nome + gatilho + verbo: sem ponteiro e
               #          sem "leia ANTES", que não servem a quem não tem o que ler.
               #          É ESTE o cenário que o ratchet mede — daí 7237→7317.
               #   =-28B  líquido na máquina COM papercuts (7400→7372) e -83B na máquina de
               #          registro vazio (7400→7317, que é o que este ratchet mede). Os dois
               #          cenários ficam ABAIXO do baseline: o corte de 163B paga a linha
               #          cheia e o bootstrap, e ainda sobra.
               #
               # ATENÇÃO — este ratchet mede o cenário HERMÉTICO (MAESTRO_HOME em mktemp,
               # sem papercuts), igual ao do doctor. A linha de papercuts é a PRIMEIRA
               # coisa da injeção que depende do estado de $MAESTRO_HOME, e por isso nem
               # este número nem o do doctor a enxergam. O teto do cenário COM papercuts
               # é cobrado em tests/hooks/test-order-026-papercuts.sh, com fixture — sem
               # ele, 135B reais entrariam em produção invisíveis para os dois medidores.
               #
               # (bump anterior: 7230→7430/7400 em 2026-09-10, E26/S-2602): o Capitão pediu a
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
# Ordem 029: PONTE_MCP_SOCKET para um caminho inexistente pelo MESMO motivo do
# MAESTRO_NO_UPDATE_CHECK acima — a linha "Perguntar ao Diretor" é condicional ao
# socket da Ponte, e numa forge que TEM a Ponte o ratchet mediria +130B de ambiente
# em vez de conteúdo. O cenário COM Ponte é cobrado em test-order-029-gatilho.sh,
# com fixture, contra o warn do doctor (7500) e o teto duro (8000).
bytes=$(printf '{"session_id":"ratchet"}' \
  | MAESTRO_HOME="$h" CLAUDE_PROJECT_DIR="$p" MAESTRO_NO_UPDATE_CHECK=1 \
    PONTE_MCP_SOCKET="$tmp/sem-ponte.sock" bash "$HOOK" 2>/dev/null | wc -c | tr -d ' ')
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
# CLAUDE_PROJECT_DIR isolado (ordem 020): sem isto, check_session_env também olha
# "$PWD/.mcp.json" — quando a suíte roda de dentro do repo do plugin (o caso normal
# de tests/run-all.sh), um .mcp.json legítimo na raiz do plugin vazaria para dentro
# desta asserção de match exato, que quer só os dois nomes do ~/.claude.json FALSO.
HOME="$fakehome" MAESTRO_HOME="$h4" CLAUDE_PROJECT_DIR="$fakehome" "$BIN" doctor >"$tmp/doc3" 2>&1
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
