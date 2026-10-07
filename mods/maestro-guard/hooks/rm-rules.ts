// Alvo de rm/chmod/chown recursivo: largo (deny), nao provado (ask) ou rotina (ok).
import { baseName, type Word } from './shell-lex'
import { resolvePath } from './paths'
import type { State } from './types'

const ARTIFACTS = new Set([
  'node_modules', 'dist', 'build', 'out', 'target', 'coverage', 'obj', 'Pods', 'DerivedData',
  '.next', '.nuxt', '.svelte-kit', '.output', '.turbo', '.parcel-cache', '.cache', '.angular',
  '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.venv', 'venv', '.tox',
  '.gradle', '.dart_tool', 'tmp', '.tmp', '.terraform',
])
const SYSTEM_TOP = new Set([
  'etc', 'usr', 'var', 'bin', 'sbin', 'lib', 'lib64', 'boot', 'dev', 'proc', 'sys', 'root',
  'opt', 'srv', 'run', 'mnt', 'media', 'snap',
])

type Wide = 'deny' | 'ask' | 'ok'

function dynTarget(t: string): Wide {
  if (/^(\$\(pwd\)|\$\{?PWD\}?)\/?\*?$/.test(t)) return 'deny'
  if (/^(\$\{?HOME\}?|~)(\/[^/]*)?\/?$/.test(t)) return 'deny'
  return 'ask'
}

function homeAndSystem(abs: string, comps: string[], home: string): Wide | null {
  if (comps.length === 0) return 'deny'
  if (home && (abs === home || home.startsWith(abs + '/'))) return 'deny'
  if (home && abs.startsWith(home + '/') && !abs.slice(home.length + 1).includes('/')) return 'deny'
  if (comps[0] === 'tmp') return comps.length >= 2 ? 'ok' : 'deny'
  if (comps[0] === 'var' && comps[1] === 'tmp') return comps.length >= 3 ? 'ok' : 'deny'
  if (comps.length === 1 || SYSTEM_TOP.has(comps[0] ?? '')) return 'deny'
  if (comps[0] === 'home' && comps.length <= 2) return 'deny'
  return null
}

export function rmTarget(w: Word, st: State): Wide {
  if (w.dyn) return dynTarget(w.t)
  let t = w.t
  while (t.length > 1 && (t.endsWith('/') || t.endsWith('/*'))) t = t.endsWith('/*') ? t.slice(0, -2) : t.slice(0, -1)
  if (['', '/', '.', '..', '*', '~'].includes(t)) return 'deny'
  if (/[*?[]/.test(baseName(t))) return 'ask'
  const abs = resolvePath(t, st.cwd, st.ctx.home)
  if (abs === null) return 'ask'
  const early = homeAndSystem(abs, abs.split('/').filter(Boolean), st.ctx.home)
  if (early) return early
  const root = st.projectRoot
  if (root && abs.startsWith(root + '/')) return ARTIFACTS.has(baseName(abs)) ? 'ok' : 'ask'
  return root && abs === root ? 'deny' : 'ask'
}
