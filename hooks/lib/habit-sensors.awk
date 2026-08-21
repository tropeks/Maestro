# hooks/lib/habit-sensors.awk — motor ÚNICO dos habit sensors (E9/S-901).
#
# Uma passada de awk por arquivo; quem chama é o hook post-edit-habits.sh (no
# momento da edição) E o CLI `maestro habits` (sobre o diff) — mesmo sensor,
# dois momentos. Conceito: sensor determinístico + guia qualitativo (padrão
# habit-hooks, MIT — github.com/habit-hooks/habit-hooks), adaptado às
# fronteiras do Maestro: awk puro, zero dependência, latência de hook.
#
# Entrada:  o arquivo a analisar (um por invocação)
# Vars:     EXT      extensão sem ponto (py, ts, sh, …)
#           ENABLED  lista de smells ativos separada por vírgula ("all" = todos)
#           MAXFILE / MAXFN / MAXNEST / MAXPARAMS  thresholds (defaults abaixo)
#           ISTEST   1 = arquivo de teste (decidido pelo chamador, pelo nome)
# Saída:    uma linha por achado: smell \t linha \t detalhe-curto
#           (caminho NUNCA sai daqui — quem chama decide o que expor a quem)
#
# Vieses deliberados:
#  - CONSERVADOR: preferir falso negativo a falso positivo — um sensor que
#    grita errado ensina o agente a ignorar sensores (o anti-hábito).
#  - Idiomas do ambiente são respeitados: `|| true`/`2>/dev/null` em shell é
#    degradação-por-design (fronteira deste repo), então swallowed-error NÃO
#    olha shell; `shellcheck disable` justificado é idioma, não supressão.
#  - Heurística de função é POR EXTENSÃO e só conta o que reconhece com
#    segurança; assinatura multilinha escapa — aceito.

BEGIN {
  if (MAXFILE   == 0) MAXFILE   = 400
  if (MAXFN     == 0) MAXFN     = 60
  if (MAXNEST   == 0) MAXNEST   = 5
  if (MAXPARAMS == 0) MAXPARAMS = 5
  split("", on)
  if (ENABLED == "" || ENABLED == "all") all = 1
  else { n = split(ENABLED, a, ","); for (i = 1; i <= n; i++) on[a[i]] = 1 }
  fn_line = 0; fn_indent = -1
  comment_run = 0; comment_start = 0
  nest_hit = 0; pending_except = 0; pending_catch = 0
  pending_bare = 0; pending_pydef = 0; prev_abstract = 0
  brace = (EXT ~ /^(js|jsx|ts|tsx|go|rs|java|c|h|cpp|hpp|cs|php)$/)
  py    = (EXT == "py")
  sh    = (EXT ~ /^(sh|bash|zsh)$/)
}

function want(s) { return all || (s in on) }
function emit(s, l, d) { printf "%s\t%d\t%s\n", s, l, d }

# indentação em "níveis": tab = 1 nível, 4 espaços = 1 nível
function indent_of(line,   sp, i, c) {
  sp = 0
  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)
    if (c == "\t") sp += 4; else if (c == " ") sp += 1; else break
  }
  return int(sp / 4)
}

function close_fn(endline,   fn_len) {
  if (fn_line > 0 && want("oversized-function")) {
    fn_len = endline - fn_line
    if (fn_len > MAXFN) emit("oversized-function", fn_line, fn_len " linhas (max " MAXFN ")")
  }
  fn_line = 0; fn_indent = -1
}

{
  line = $0
  ind = indent_of(line)
  stripped = line; sub(/^[ \t]+/, "", stripped)
  is_blank   = (stripped == "")
  is_comment = (stripped ~ /^(#|\/\/|\/\*|\*|--)/)

  # ---- função: início/fim (heurística conservadora por família) -------------
  fn_start = 0
  if (py     && stripped ~ /^(async )?def [A-Za-z_]/)                        fn_start = 1
  if (EXT == "go" && line ~ /^func /)                                        fn_start = 1
  if (EXT == "rs" && stripped ~ /^(pub +)?(async +)?fn [A-Za-z_]/)           fn_start = 1
  if (sh     && line ~ /^[A-Za-z_][A-Za-z0-9_]* *\(\) *\{/)                  fn_start = 1
  if (brace && !fn_start && stripped ~ /(^|[^A-Za-z0-9_])function [A-Za-z_$]/) fn_start = 1

  if (fn_start) {
    close_fn(NR)
    fn_line = NR; fn_indent = ind

    # ---- too-many-params: só na linha de assinatura, só se fecha parêntese --
    if (want("too-many-params") && line ~ /\(/ && line ~ /\)/) {
      sig = line
      sub(/^[^(]*\(/, "", sig); sub(/\).*$/, "", sig)
      if (sig !~ /^ *$/) {
        depth = 0; params = 1
        for (i = 1; i <= length(sig); i++) {
          c = substr(sig, i, 1)
          if (c == "(" || c == "[" || c == "{" || c == "<") depth++
          else if (c == ")" || c == "]" || c == "}" || c == ">") depth--
          else if (c == "," && depth == 0) params++
        }
        if (params > MAXPARAMS) emit("too-many-params", NR, params " parâmetros (max " MAXPARAMS ")")
      }
    }
  } else if (fn_line > 0 && !is_blank) {
    if (py && ind <= fn_indent && NR > fn_line)            close_fn(NR)
    else if ((brace || sh) && stripped ~ /^\}/ && ind <= fn_indent) close_fn(NR + 1)
  }

  # ---- deep-nesting: primeiro estouro do arquivo (código, não comentário) ---
  if (want("deep-nesting") && !nest_hit && !is_blank && !is_comment && ind > MAXNEST) {
    nest_hit = 1
    emit("deep-nesting", NR, "indentação nível " ind " (max " MAXNEST ")")
  }

  # ---- swallowed-error (nunca em shell — degradação é design lá) ------------
  if (want("swallowed-error") && !sh) {
    if (pending_except && !is_blank) {
      if (stripped ~ /^(pass|\.\.\.)[ \t]*(#.*)?$/)
        emit("swallowed-error", NR, "except sem tratamento")
      else if (pending_bare)
        emit("swallowed-error", NR - 1, "except: sem tipo (pega até SystemExit)")
      pending_except = 0; pending_bare = 0
    }
    if (pending_catch && !is_blank) {
      if (stripped ~ /^\}/) emit("swallowed-error", NR - 1, "catch vazio")
      pending_catch = 0
    }
    if (py && stripped ~ /^except([^:]*)?:[ \t]*(#.*)?$/) {
      pending_except = 1
      pending_bare = (stripped ~ /^except[ \t]*:/) ? 1 : 0
    }
    else if (py && stripped ~ /^except([^:]*)?:[ \t]*(pass|\.\.\.)[ \t]*(#.*)?$/)
      emit("swallowed-error", NR, "except inline sem tratamento")
    if (brace && stripped ~ /catch[ \t]*(\([^)]*\))?[ \t]*\{[ \t]*\}/)
      emit("swallowed-error", NR, "catch {} vazio")
    else if (brace && stripped ~ /catch[ \t]*(\([^)]*\))?[ \t]*\{[ \t]*$/)
      pending_catch = 1
  }

  # ---- debug-leftover (fora de arquivo de teste) ----------------------------
  if (want("debug-leftover") && !ISTEST && !is_comment) {
    if (py && stripped ~ /^print\(/)                      emit("debug-leftover", NR, "print()")
    if (EXT ~ /^(js|jsx|ts|tsx)$/ && stripped ~ /console\.(log|debug)\(/)
                                                          emit("debug-leftover", NR, "console.log/debug")
    if (EXT == "rs" && line ~ /(^|[^A-Za-z0-9_])dbg!\(/)  emit("debug-leftover", NR, "dbg!()")
  }

  # ---- lint-suppression: burlar a métrica é o anti-hábito nº 1 --------------
  if (want("lint-suppression")) {
    if (line ~ /@ts-ignore/)                              emit("lint-suppression", NR, "@ts-ignore")
    if (line ~ /# *noqa *$/)                              emit("lint-suppression", NR, "# noqa sem código de regra")
    if (line ~ /# *type: *ignore *$/)                     emit("lint-suppression", NR, "type: ignore genérico")
    if (line ~ /eslint-disable([^-]|$)/ && line !~ /eslint-disable-(next-)?line/)
                                                          emit("lint-suppression", NR, "eslint-disable de arquivo inteiro")
  }

  # ---- type-escape (TS) -----------------------------------------------------
  if (want("type-escape") && EXT ~ /^(ts|tsx)$/ && !is_comment) {
    if (line ~ /(^|[^A-Za-z0-9_])as +any([^A-Za-z0-9_]|$)/)  emit("type-escape", NR, "as any")
    if (line ~ /as +unknown +as +/)                          emit("type-escape", NR, "as unknown as")
  }

  # ---- slop-comment: frases-assinatura de código gerado sem terminar --------
  if (want("slop-comment")) {
    low = tolower(line)
    if (low ~ /in a real (implementation|application|app|system)/ ||
        low ~ /in production,? (you|we|this) would/ ||
        low ~ /for (simplicity|brevity|demonstration purposes)/ ||
        low ~ /this is a simplified/ ||
        low ~ /(implementation|logic|code) goes here/ ||
        low ~ /your (logic|code|implementation) here/ ||
        low ~ /rest of (the|your) (code|file|function)/ ||
        low ~ /\.\.\. *existing code *\.\.\./ ||
        low ~ /todo:? implement/ ||
        low ~ /should work( now)?( hopefully)?[.!]? *$/ ||
        low ~ /hopefully (this|that|it)/ ||
        low ~ /not (100%|entirely|totally) sure/ ||
        low ~ /(this|it) might (work|break|fail)/ ||
        low ~ /por simplicidade/ || low ~ /numa implementa..o real/)
      emit("slop-comment", NR, "frase-assinatura de slop")
  }

  # ---- empty-impl: esqueleto entregue como produto --------------------------
  # def com corpo imediato `pass` (fora de @abstractmethod/@overload, que são
  # legítimos): função declaradamente vazia — catálogo do AI-SLOP-Detector.
  if (want("empty-impl") && py) {
    if (pending_pydef && !is_blank) {
      if (stripped ~ /^pass[ \t]*(#.*)?$/ && !prev_abstract)
        emit("empty-impl", NR, "corpo é só pass")
      pending_pydef = 0; prev_abstract = 0
    }
    if (stripped ~ /^@.*(abstractmethod|overload)/) prev_abstract = 1
    if (fn_start) pending_pydef = 1
  }
  if (want("empty-impl") && !is_comment) {
    if (line ~ /raise NotImplementedError/ ||
        line ~ /throw new Error\((["'])[Nn]ot implemented/ ||
        line ~ /(^|[^A-Za-z0-9_])(todo|unimplemented)!\(\)/)
      emit("empty-impl", NR, "implementação declaradamente vazia")
  }

  # ---- dead-code: bloco de CÓDIGO comentado (≥3 linhas), não prosa ----------
  if (want("dead-code")) {
    codeish = 0
    if (is_comment) {
      body = stripped
      sub(/^(#+|\/\/+|\/\*+|\*+|--+)[ \t]?/, "", body)
      if (body ~ /[;{}]$/ ||
          body ~ /^(if|for|while|return|const|let|var|def|func|fn|import|from|class) / ||
          body ~ /^[A-Za-z_][A-Za-z0-9_]* *=[^=]/)
        codeish = 1
    }
    if (codeish) {
      if (comment_run == 0) comment_start = NR
      comment_run++
    } else {
      if (comment_run >= 3) emit("dead-code", comment_start, comment_run " linhas de código comentado")
      comment_run = 0
    }
  }

  # ---- skipped-test / asserção que não afirma nada (só em teste) ------------
  if (want("skipped-test") && ISTEST) {
    if (stripped ~ /^(it|test|describe)\.skip\(/ || stripped ~ /^x(it|describe|test)\(/)
      emit("skipped-test", NR, "teste pulado")
    if (line ~ /@pytest\.mark\.skip/ || stripped ~ /(^|[^A-Za-z0-9_])t\.Skip\(/)
      emit("skipped-test", NR, "teste pulado")
    if (stripped ~ /^assert True[ \t]*(#.*)?$/ || line ~ /expect\(true\)\.toBe\(true\)/)
      emit("skipped-test", NR, "asserção que não afirma nada")
  }

  # ---- risky-shortcut: atalho de linguagem que vira bug ---------------------
  if (want("risky-shortcut") && !is_comment) {
    if (py && stripped ~ /^(async )?def [A-Za-z_][A-Za-z0-9_]*\([^)]*=[ \t]*(\[\]|\{\})/)
      emit("risky-shortcut", NR, "default mutável em parâmetro")
    if (py && stripped ~ /^from [A-Za-z0-9_.]+ import \*/)
      emit("risky-shortcut", NR, "import * esconde a superfície do módulo")
    if (EXT == "rs" && !ISTEST && line ~ /\.unwrap\(\)/)
      emit("risky-shortcut", NR, ".unwrap() fora de teste")
  }
}

END {
  close_fn(NR + 1)
  if (comment_run >= 3 && want("dead-code"))
    emit("dead-code", comment_start, comment_run " linhas de código comentado")
  if (want("oversized-file") && NR > MAXFILE)
    emit("oversized-file", 1, NR " linhas (max " MAXFILE ")")
}
