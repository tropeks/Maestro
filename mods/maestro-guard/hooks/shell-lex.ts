// Lexer de shell da guarda: quebra o comando em segmentos de palavras, com as
// aspas ja removidas, sem executar nem expandir nada. `$(...)` e crases viram
// segmentos proprios (o conteudo tambem e comando) e a palavra que os contem
// fica marcada `dyn`. Texto que nao da para ler com seguranca lanca Unparseable.

export type Word = { t: string; dyn: boolean; glob: boolean }
// w: as palavras do comando; out: alvos de `>`; inp: alvos de `<` (arquivo lido por stdin)
export type Seg = { w: Word[]; out: Word[]; inp: Word[] }
export type Heredoc = { word: string; feeds: 'shell' | 'sql' | 'data'; body: string }

export class Unparseable extends Error {}

const MAX_SEGS = 256

export const DB_CLIENTS = new Set([
  'psql', 'mysql', 'mariadb', 'sqlite3', 'mongo', 'mongosh', 'sqlcmd', 'cockroach',
  'clickhouse-client', 'pg_restore', 'usql',
])
export const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh'])

export const baseName = (p: string): string => p.slice(p.lastIndexOf('/') + 1)

function feedKind(line: string, idx: number): Heredoc['feeds'] {
  const before = line.slice(0, idx).split(/[;&|(]/).pop() ?? ''
  const words = before.trim().split(/\s+/).filter(w => !/^[A-Za-z_]\w*=/.test(w) && w !== 'sudo')
  const head = baseName(words[0] ?? '')
  if (SHELLS.has(head) || head === 'eval') return 'shell'
  if (DB_CLIENTS.has(head)) return 'sql'
  const after = line.slice(idx)
  if (/\|\s*(sudo\s+)?(ba|z|da|k)?sh\b/.test(after)) return 'shell'
  if (/\|\s*(psql|mysql|mariadb|sqlite3|mongosh?)\b/.test(after)) return 'sql'
  return 'data'
}

// Remove o corpo dos heredocs (entre `<<WORD` e `WORD`); o corpo de um heredoc
// que alimenta shell ou cliente de banco volta como material a analisar.
export function stripHeredocs(src: string): { text: string; docs: Heredoc[] } {
  if (!src.includes('<<')) return { text: src, docs: [] }
  const lines = src.split('\n')
  const out: string[] = []
  const docs: Heredoc[] = []
  for (let li = 0; li < lines.length; li++) {
    const line = lines[li] ?? ''
    out.push(line)
    const re = /(^|[^<])<<(-?)\s*(['"\\]?)([A-Za-z_][A-Za-z0-9_]*)\3/g
    for (let m = re.exec(line); m; m = re.exec(line)) {
      const word = m[4] ?? ''
      const feeds = feedKind(line, m.index + (m[1]?.length ?? 0))
      const body: string[] = []
      let closed = false
      while (li + 1 < lines.length && !closed) {
        li++
        const next = lines[li] ?? ''
        if (next.trim() === word) closed = true
        else body.push(next)
      }
      if (!closed) throw new Unparseable('heredoc')
      docs.push({ word, feeds, body: body.join('\n') })
    }
  }
  return { text: out.join('\n'), docs }
}

// O estado de um nivel de aninhamento: o segmento e a palavra em construcao.
class Frame {
  cur: Seg = { w: [], out: [], inp: [] }
  word: Word | null = null
  redirOut = false
  redirIn = false
  skipNext = false
  paren = 0

  constructor(private segs: Seg[]) {}

  open(): Word {
    if (!this.word) this.word = { t: '', dyn: false, glob: false }
    return this.word
  }

  endWord(): void {
    if (!this.word) return
    if (this.redirOut) this.cur.out.push(this.word)
    else if (this.redirIn) this.cur.inp.push(this.word)
    else if (!this.skipNext) this.cur.w.push(this.word)
    this.redirOut = false
    this.redirIn = false
    this.skipNext = false
    this.word = null
  }

  endSeg(): void {
    this.endWord()
    if (this.cur.w.length || this.cur.out.length || this.cur.inp.length) {
      if (this.segs.length >= MAX_SEGS) throw new Unparseable('segs')
      this.segs.push(this.cur)
    }
    this.cur = { w: [], out: [], inp: [] }
    // redirecionamento sem alvo (`cat <;`) nao vaza para o proximo segmento
    this.redirOut = false
    this.redirIn = false
    this.skipNext = false
  }
}

class Lexer {
  i = 0
  segs: Seg[] = []

  constructor(private src: string) {}

  run(closer: ')' | '`' | null): void {
    const f = new Frame(this.segs)
    while (this.i < this.src.length) {
      if (this.step(f, closer)) return
    }
    if (closer !== null) throw new Unparseable('unclosed')
    f.endSeg()
  }

  // true = este nivel acabou (achou o fechamento)
  private step(f: Frame, closer: ')' | '`' | null): boolean {
    const c = this.src[this.i] as string
    if (c === ' ' || c === '\t' || c === '\r') {
      f.endWord()
      this.i++
    } else if (c === '\n' || c === ';' || c === '|' || c === '&') this.separator(f, c)
    else if (c === '>') this.redirectOut(f)
    else if (c === '<') this.redirectIn(f)
    else if (c === '(') {
      f.endSeg()
      f.paren++
      this.i++
    } else if (c === ')') return this.closeParen(f, closer)
    else if (c === '`') return this.backtick(f, closer)
    else if (c === "'") this.singleQuote(f)
    else if (c === '"') this.doubleQuote(f.open())
    else if (c === '\\') this.escape(f)
    else if (c === '$') this.dollar(f.open())
    else if (c === '#' && !f.word) this.comment()
    else this.plain(f, c)
    return false
  }

  private separator(f: Frame, c: string): void {
    const nx = this.src[this.i + 1]
    if (c === '&' && nx === '>') {
      f.endWord()
      this.i += this.src[this.i + 2] === '>' ? 3 : 2
      f.redirOut = true
      return
    }
    f.endSeg()
    this.i += (c === '&' && nx === '&') || (c === '|' && (nx === '|' || nx === '&')) ? 2 : 1
  }

  private redirectOut(f: Frame): void {
    const w = f.word
    if (w && /^[0-9]+$/.test(w.t) && !w.dyn) f.word = null
    else f.endWord()
    this.i++
    if (this.src[this.i] === '>' || this.src[this.i] === '|') this.i++
    if (this.src[this.i] === '&') {
      this.i++
      f.skipNext = true
    } else f.redirOut = true
  }

  // `< arquivo`: o alvo vira origem de LEITURA (seg.inp), para a guarda de segredo
  // ve-lo (`cat < .env`). Heredoc/here-string (`<<`, `<<<`), `<(...)` e `<&`/`<>`
  // nao nomeiam um arquivo lido por stdin e seguem descartando a palavra seguinte.
  private redirectIn(f: Frame): void {
    const w = f.word
    if (w && /^[0-9]+$/.test(w.t) && !w.dyn) f.word = null
    else f.endWord()
    this.i++
    const nx = this.src[this.i]
    if (nx === '<') {
      this.i++
      if (this.src[this.i] === '<') this.i++
      if (this.src[this.i] === '-') this.i++
      f.skipNext = true
    } else if (nx === '(' || nx === '&' || nx === '>') f.skipNext = true
    else f.redirIn = true
  }

  private closeParen(f: Frame, closer: ')' | '`' | null): boolean {
    f.endSeg()
    this.i++
    if (f.paren > 0) {
      f.paren--
      return false
    }
    return closer === ')'
  }

  private backtick(f: Frame, closer: ')' | '`' | null): boolean {
    this.i++
    if (closer === '`') {
      f.endSeg()
      return true
    }
    this.substitute(f.open(), '`')
    return false
  }

  private singleQuote(f: Frame): void {
    const end = this.src.indexOf("'", this.i + 1)
    if (end < 0) throw new Unparseable('quote')
    f.open().t += this.src.slice(this.i + 1, end)
    this.i = end + 1
  }

  private doubleQuote(w: Word): void {
    this.i++
    while (this.i < this.src.length) {
      const d = this.src[this.i] as string
      if (d === '"') {
        this.i++
        return
      }
      if (d === '\\') this.dqEscape(w)
      else if (d === '$') this.dollar(w)
      else if (d === '`') {
        this.i++
        this.substitute(w, '`')
      } else {
        w.t += d
        this.i++
      }
    }
    throw new Unparseable('dquote')
  }

  private dqEscape(w: Word): void {
    const e = this.src[this.i + 1]
    if (e === undefined) throw new Unparseable('escape')
    if ('$"\\`'.includes(e)) w.t += e
    else if (e !== '\n') w.t += '\\' + e
    this.i += 2
  }

  private escape(f: Frame): void {
    const e = this.src[this.i + 1]
    if (e === undefined) throw new Unparseable('escape')
    if (e !== '\n') f.open().t += e
    this.i += 2
  }

  private comment(): void {
    while (this.i < this.src.length && this.src[this.i] !== '\n') this.i++
  }

  private plain(f: Frame, c: string): void {
    const w = f.open()
    if (c === '*' || c === '?' || c === '[') w.glob = true
    w.t += c
    this.i++
  }

  // `$(...)` e crases: o conteudo vira segmentos proprios; a palavra guarda o texto
  private substitute(w: Word, c: ')' | '`'): void {
    const from = this.i
    this.run(c)
    w.dyn = true
    const inner = this.src.slice(from, this.i - 1)
    w.t += c === ')' ? `$(${inner})` : '`' + inner + '`'
  }

  private dollar(w: Word): void {
    const s = this.src
    const nx = s[this.i + 1]
    if (nx === '(') {
      this.i += 2
      this.substitute(w, ')')
    } else if (nx === '{') {
      const end = s.indexOf('}', this.i)
      if (end < 0) throw new Unparseable('brace')
      w.dyn = true
      w.t += s.slice(this.i, end + 1)
      this.i = end + 1
    } else if (nx !== undefined && /[A-Za-z_]/.test(nx)) {
      let j = this.i + 1
      while (j < s.length && /[A-Za-z0-9_]/.test(s[j] ?? '')) j++
      w.dyn = true
      w.t += s.slice(this.i, j)
      this.i = j
    } else if (nx !== undefined && /[0-9?$!@*#-]/.test(nx)) {
      w.dyn = true
      w.t += '$' + nx
      this.i += 2
    } else if (nx === "'") {
      const end = s.indexOf("'", this.i + 2)
      if (end < 0) throw new Unparseable('ansi-c')
      w.t += s.slice(this.i + 2, end)
      this.i = end + 1
    } else {
      w.t += '$'
      this.i++
    }
  }
}

export function lex(src: string): Seg[] {
  const lx = new Lexer(src)
  lx.run(null)
  return lx.segs
}
