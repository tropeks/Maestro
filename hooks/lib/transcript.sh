# hooks/lib/transcript.sh — ler a RODADA CORRENTE de um transcrito, e só ela.
#
# Ordem 038. O Stop precisa saber se a rodada que ACABOU pediu decisão ao
# Diretor. O caminho antigo lia uma janela de BYTES (`tail -c 8192`) e casava
# os regexes nela — só que 8 KB cobrem muitas rodadas, e qualquer ocorrência
# antiga da linha canônica servia: rodada velha, citação do humano, relato que
# descrevesse o mecanismo. Falso positivo medido: canônica na 2ª de 14
# mensagens, rodada corrente limpa, e o Stop bloqueou.
#
# A rodada corrente é a ÚLTIMA mensagem do ASSISTENTE: o transcrito é JSONL,
# uma mensagem por linha, e depois dela só vêm linhas de metadado
# (`last-prompt`, `ai-title`, …). Vem de graça: mensagem de USUÁRIO deixa de
# ser examinada, então citar a linha não dispara mais nada.
#
# POR QUE `awk`, e não bash puro (medido nesta forge, transcrito de 16 KB, NFR
# do hook = 50ms):
#   `${x##*"$mk"}`          ~65ms — o `*` inicial tenta todos os pontos de corte
#   `while read` + regex    ~80ms — compila o regex por linha
#   `grep … | tail -n 1`    ~51ms — dois forks
#   `awk` numa passada      ~41ms — um fork, guarda a última que casa
# O caminho anterior (sem separar rodada) custava 17–21ms: o preço da correção
# é ~20ms, dentro do orçamento e com menos folga. Está dito para quem for
# mexer aqui de novo.
#
# Bash puro, sem jq, sem rede — a fronteira de `hooks/` vale aqui igual.

# maestro_last_assistant_line <caminho-do-transcrito> → a última linha de
# assistente da janela, ou VAZIO. Vazio significa "não sei": quem chama não
# pode afirmar que há pergunta pendente (Prioridade 1 — degradar, nunca
# inventar).
maestro_last_assistant_line() {
  local tpath="$1"
  [[ -n "$tpath" && -f "$tpath" && -r "$tpath" ]] || return 0
  tail -c 8192 -- "$tpath" 2>/dev/null \
    | awk '/"(type|role)"[ \t]*:[ \t]*"assistant"/ { l = $0 } END { if (l != "") print l }' 2>/dev/null \
    || true
}
