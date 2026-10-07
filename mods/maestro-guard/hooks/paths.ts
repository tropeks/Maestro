// Caminhos: normalizacao lexica, resolucao contra o cwd e o que e protegido.
import type { Word } from './shell-lex'
import { ask, deny, type Ctx, type State } from './types'

export function normalize(p: string): string {
  const out: string[] = []
  for (const part of p.split('/')) {
    if (part === '' || part === '.') continue
    if (part === '..') out.pop()
    else out.push(part)
  }
  return '/' + out.join('/')
}

// null = nao da para saber (cwd ou variavel desconhecida)
export function resolvePath(t: string, cwd: string | null, home: string): string | null {
  if (t === '~' || t.startsWith('~/')) return home ? normalize(home + t.slice(1)) : null
  if (t.startsWith('/')) return normalize(t)
  if (cwd === null) return null
  return normalize(cwd + '/' + t)
}

// `.claude/` (settings do projeto: `env`, hooks, permissoes) e `.github/workflows/` (CI)
// entram aqui por causa da revisao de seguranca da 072 (P2-2): com `.claude/` gravavel o
// agente armaria o kill-switch (`env.MAESTRO_OFF`) na proxima sessao. Entrada pode ter 2 niveis.
const SELF_DIRS = ['agents', 'bin', 'src', 'hooks', 'lib', 'mods', '.claude-plugin', '.claude', '.github/workflows']
const SELF_FILES = ['config/routing-table.yaml', 'config/accept-proof.pub']

const relProtected = (rel: string): boolean =>
  SELF_DIRS.some(d => rel === d || rel.startsWith(d + '/')) || SELF_FILES.includes(rel)

export function protectedAbs(abs: string, ctx: Ctx): boolean {
  if (ctx.roots.length === 0) return false
  // o clone sandbox fora do repo (pasta do run, /tmp/claude-<uid>/...) sempre passou
  if (abs === '/tmp' || abs.startsWith('/tmp/')) return false
  for (const root of ctx.roots) {
    if (abs.startsWith(root + '/') && relProtected(abs.slice(root.length + 1))) return true
  }
  const m = /^\/(?:[^/]+\/)*worktrees\/[^/]+\/(.+)$/.exec(abs)
  return m !== null && relProtected(m[1] ?? '')
}

const PROTECTED_LOOK = /(^|\/)(agents|bin|src|hooks|lib|mods|\.claude-plugin|\.claude|\.github\/workflows|config)\//

// Escrita (por redirecionamento, tee, cp...) num alvo: nega caminho protegido,
// nega dispositivo de bloco, pergunta quando o alvo nao resolve perto de um.
export function writeTarget(w: Word, st: State, via: string): void {
  const { ctx } = st
  if (/^\/dev\/(null|zero|stdout|stderr|tty|fd\/\d+)$/.test(w.t)) return
  if (/^\/dev\/(sd|hd|nvme|vd|mmcblk|disk)/.test(w.t)) {
    st.findings.push(deny('device_write', 'escrita direta em dispositivo de bloco'))
    return
  }
  if (ctx.roots.length === 0) return
  const abs = w.dyn ? null : resolvePath(w.t, st.cwd, ctx.home)
  if (abs === null) {
    if (PROTECTED_LOOK.test(w.t)) st.findings.push(ask('unresolved_self_write', `destino de ${via} nao resolvivel perto de caminho protegido`))
    return
  }
  if (protectedAbs(abs, ctx)) st.findings.push(deny('self_protect', `escrita (${via}) em caminho protegido do Maestro: use o patch protegido`))
}

const WRITE_CODE = /(write|open\s*\([^)]*['"][wax+]|rmtree|unlink|remove|rename|replace|copy|move|truncate|symlink|appendfile|createwritestream|mkdir)/i

// Codigo inline (python -c, node -e...) que escreve num literal de caminho protegido.
export function codeTouchesProtected(code: string, st: State): boolean {
  if (st.ctx.roots.length === 0 || !WRITE_CODE.test(code)) return false
  for (const m of code.matchAll(/['"]([^'"\s]+)['"]/g)) {
    const abs = resolvePath(m[1] ?? '', st.cwd, st.ctx.home)
    if (abs !== null && protectedAbs(abs, st.ctx)) return true
  }
  return false
}
