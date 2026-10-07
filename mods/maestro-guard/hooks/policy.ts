// maestro-guard: a decisao de politica, como FUNCAO PURA (sem `$`, sem I/O).
// decide(tool, input, ctx) -> { verdict: deny | ask | pass, rule, reason }.
//
// Regra de desenho (ordem 072): NEGA so a classe estrutural clara; o ambiguo
// vira ASK; o resto passa (o hook devolve o que `next(e)` devolveu). Este
// modulo nunca emite "allow" e nunca devolve texto do comando em `reason`.
// A analise e lexica: ver "LIMITES" no fim do arquivo.
import { baseName, lex, SHELLS, stripHeredocs, Unparseable, type Seg } from './shell-lex'
import { normalize, protectedAbs, resolvePath, writeTarget } from './paths'
import { leafCommand } from './commands'
import { flagsOf, operands } from './args'
import { checkSecretTool, secretInput } from './secrets'
import { ask, deny, PASS, rank, type Cmd, type Ctx, type Decision, type State } from './types'

export type { Ctx, Decision, Verdict } from './types'

const MAX_CMD = 32768
const MAX_DEPTH = 6

const WRAPPERS = new Set([
  'env', 'nohup', 'time', 'command', 'builtin', 'exec', 'nice', 'ionice', 'setsid', 'stdbuf',
  'watch', 'flock', 'then', 'do', 'else', 'elif', 'fi', 'done', 'if', 'while', 'until', '!', '{', '}', '[', '[[',
])
const XARGS_ARG = new Set(['-I', '-n', '-P', '-L', '-d', '-E', '-s'])
const SUDO_ARG = new Set(['-u', '-g', '-h', '-p', '-C', '-T', '-U', '-r', '-t'])

type Envelope = { i: number; sudo: boolean; xargs: boolean }

// Descasca atribuicoes de ambiente e envelopes (sudo, timeout, xargs...) ate o verbo.
function stripEnvelope(seg: Seg): Envelope {
  const w = seg.w
  const env: Envelope = { i: 0, sudo: false, xargs: false }
  const skipFlags = (argTaking?: Set<string>): void => {
    while (w[env.i + 1]?.t.startsWith('-')) {
      env.i++
      if (argTaking?.has(w[env.i]?.t ?? '')) env.i++
    }
  }
  for (; env.i < w.length; env.i++) {
    const t = w[env.i]?.t ?? ''
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) continue
    if (t === 'sudo' || t === 'doas') {
      env.sudo = true
      skipFlags(SUDO_ARG)
    } else if (t === 'timeout') {
      skipFlags()
      if (/^[0-9.]+[smhd]?$/.test(w[env.i + 1]?.t ?? '')) env.i++
    } else if (t === 'xargs') {
      env.xargs = true
      skipFlags(XARGS_ARG)
    } else if (WRAPPERS.has(t)) skipFlags()
    else break
  }
  return env
}

function shellDash(c: Cmd, st: State, depth: number): void {
  const ci = c.args.findIndex(a => /^-[a-z]*c[a-z]*$/.test(a.t))
  if (ci < 0) return
  const script = c.args.slice(ci + 1).find(a => !a.t.startsWith('-'))
  if (!script) return
  if (script.dyn) st.findings.push(ask('dynamic_exec', 'shell -c com comando montado em tempo de execucao'))
  else scan(script.t, st, depth + 1)
}

function sshRemote(c: Cmd, st: State, depth: number): void {
  let k = 0
  while (k < c.args.length) {
    const a = c.args[k]?.t ?? ''
    if (/^-[bcDeEFIiJLlmOopQRSWw]$/.test(a)) k += 2
    else if (a.startsWith('-')) k++
    else break
  }
  const cmd = c.args.slice(k + 1)
  if (cmd.length) scan(cmd.map(a => a.t).join(' '), st, depth + 1)
}

function changeDir(c: Cmd, st: State): void {
  const d = c.ops[0]
  st.cwd = !d || d.t === '-' || d.dyn ? null : resolvePath(d.t, st.cwd, st.ctx.home)
}

function scanSeg(seg: Seg, st: State, depth: number): void {
  for (const o of seg.out) writeTarget(o, st, 'redirecionamento')
  secretInput(seg.inp, st)
  const env = stripEnvelope(seg)
  const headW = seg.w[env.i]
  if (!headW) return
  const args = seg.w.slice(env.i + 1)
  const c: Cmd = { head: baseName(headW.t), args, flags: flagsOf(args), ops: operands(args), xargs: env.xargs }
  if (env.sudo) st.findings.push(ask('privilege', 'sudo pede privilegio elevado'))

  if (SHELLS.has(c.head)) shellDash(c, st, depth)
  else if (c.head === 'eval') {
    if (args.some(a => a.dyn)) st.findings.push(ask('dynamic_exec', 'eval com comando montado em tempo de execucao'))
    else scan(args.map(a => a.t).join(' '), st, depth + 1)
  } else if (c.head === 'ssh') sshRemote(c, st, depth)
  else if (c.head === 'cd' || c.head === 'pushd') changeDir(c, st)
  else leafCommand(c, st)
}

function scan(text: string, st: State, depth: number): void {
  if (depth > MAX_DEPTH) throw new Unparseable('depth')
  const { text: body, docs } = stripHeredocs(text)
  for (const seg of lex(body)) scanSeg(seg, st, depth)
  for (const d of docs) {
    if (d.feeds === 'shell') scan(d.body, st, depth + 1)
    else if (d.feeds === 'sql') {
      st.db = true
      st.sql.push(d.body)
    }
  }
}

function sqlCheck(st: State): void {
  const text = (st.raw + '\n' + st.sql.join('\n')).toLowerCase()
  if (/\bdrop\s+(table|database|schema)\b/.test(text) || /\btruncate\s+(table\s+)?["`a-z_]/.test(text)) {
    st.findings.push(deny('sql_destructive', 'DROP ou TRUNCATE em cliente de banco'))
    return
  }
  for (const m of text.matchAll(/\bdelete\s+from\s+[^;]*/g)) {
    if (!/\bwhere\b/.test(m[0])) {
      st.findings.push(deny('sql_destructive', 'DELETE sem WHERE em cliente de banco'))
      return
    }
  }
}

function checkBash(input: unknown, ctx: Ctx): Decision {
  if (typeof input !== 'object' || input === null) return deny('malformed', 'entrada do Bash ilegivel')
  const command = (input as { command?: unknown }).command
  if (typeof command !== 'string') return deny('malformed', 'campo command ausente ou nao-texto')
  if (command.length > MAX_CMD) return deny('too_large', 'comando grande demais para analisar')
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F�]/.test(command)) return deny('bad_bytes', 'comando com bytes invalidos')
  const projectRoot = ctx.roots.find(r => ctx.cwd === r || ctx.cwd.startsWith(r + '/')) ?? ctx.cwd
  const st: State = { ctx, cwd: ctx.cwd || null, projectRoot, findings: [], db: false, sql: [], curlSeen: false, raw: command }
  try {
    scan(command, st, 0)
  } catch (err) {
    if (err instanceof Unparseable) return deny('unparseable', 'comando que nao da para ler com seguranca (aspas, heredoc ou aninhamento)')
    throw err
  }
  if (st.db) sqlCheck(st)
  if (st.curlSeen && /(curl|wget)[^;|]*\|\s*(sudo\s+)?(ba|z|da|k)?sh\b/i.test(command)) {
    st.findings.push(ask('remote_pipe_shell', 'baixa e executa script remoto'))
  }
  return st.findings.reduce<Decision>((best, f) => (rank(f) > rank(best) ? f : best), PASS)
}

const PATH_KEY: Record<string, string> = { Edit: 'file_path', Write: 'file_path', MultiEdit: 'file_path', NotebookEdit: 'notebook_path' }

function checkFileWrite(tool: string, input: unknown, ctx: Ctx): Decision {
  if (typeof input !== 'object' || input === null) return deny('malformed', 'entrada da ferramenta ilegivel')
  const rec = input as Record<string, unknown>
  const p = rec[PATH_KEY[tool] ?? 'file_path'] ?? (tool === 'NotebookEdit' ? rec.file_path : undefined)
  if (typeof p !== 'string' || p === '') return deny('malformed', 'caminho do arquivo ausente ou nao-texto')
  if (/[\u0000�]/.test(p)) return deny('bad_bytes', 'caminho com bytes invalidos')
  const abs = resolvePath(p, ctx.cwd || null, ctx.home)
  if (abs === null) return ctx.roots.length ? ask('unresolved_self_write', 'caminho nao resolvivel') : PASS
  if (protectedAbs(normalize(abs), ctx)) return deny('self_protect', 'caminho protegido do Maestro: use o patch protegido')
  return PASS
}

// Regras de destrutivo: com humano na sessao viram ask (decisao do Diretor, 07/10);
// sem humano (headless) seguem deny. Autoprotecao, segredo e queda segura nao entram.
const DESTRUCTIVE = new Set([
  'rm_recursive_wide', 'sql_destructive', 'chmod_wide', 'disk_format', 'device_write',
  'force_push_main', 'git_clean', 'reset_hard',
])

function judge(tool: string, input: unknown, ctx: Ctx): Decision {
  if (tool === 'Bash') return checkBash(input, ctx)
  if (tool in PATH_KEY) return checkFileWrite(tool, input, ctx)
  if (tool === 'Read' || tool === 'Grep' || tool === 'Glob') return checkSecretTool(tool, input) ?? PASS
  return PASS
}

export function decide(tool: string, input: unknown, ctx: Ctx): Decision {
  try {
    const d = judge(tool, input, ctx)
    return ctx.interactive === true && d.verdict === 'deny' && DESTRUCTIVE.has(d.rule) ? ask(d.rule, d.reason) : d
  } catch {
    return deny('guard_error', 'falha interna da guarda')
  }
}

// LIMITES (a analise e lexica, nao uma sandbox; ver ENGINEERING_SPEC):
//  - `bash script.sh`, `make`, `npm run x`: o perigo mora dentro do arquivo, que nao lemos;
//  - variavel montando o caminho (`D=/; rm -rf $D`): so o texto `$D` e visto -> ask, nunca allow;
//  - `eval`/`bash -c` com texto montado por variavel ou substituicao: ask (dynamic_exec);
//  - codificacao (`base64 -d | sh`), `find -delete`, `rsync --delete`;
//  - symlink para dentro de caminho protegido; mudanca de cwd por subshell `( cd x; ... )`;
//  - linguagem hospedeira: so `python/node/perl/ruby -c|-e` com literal de caminho protegido.
