import type { Engine, Register } from 'claude-code'
import { decide, type Ctx } from './policy'

// Ferramentas que a guarda julga; as demais seguem direto para next(e).
const GUARDED = ['Bash', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit']
const LOG_KEEP = 1000

let offOnce: Promise<boolean> | undefined
const rootsByCwd = new Map<string, string[]>()

async function logLine($: Engine, rule: string, tool: string, verdict: string): Promise<void> {
  try {
    const home = (await $.env.get('HOME')) || ''
    const base = (await $.env.get('MAESTRO_HOME')) || `${home}/.maestro`
    const file = `${base}/logs/guard-mod.jsonl`
    let old = ''
    try {
      const r = await $.fs.read(file)
      old = typeof r === 'string' ? r : ''
    } catch {
      old = ''
    }
    // so metadados: nunca comando, caminho ou prompt
    const line = JSON.stringify({ ts: new Date().toISOString(), event: 'guard_mod', rule, tool, verdict })
    const kept = old ? old.split('\n').filter(Boolean).slice(-(LOG_KEEP - 1)) : []
    await $.fs.write(file, kept.concat(line).join('\n') + '\n')
  } catch {
    // log nunca muda o veredito
  }
}

// MAESTRO_OFF lido uma vez no load, pelo ambiente do processo do Claude Code.
function killSwitch($: Engine): Promise<boolean> {
  if (!offOnce) {
    offOnce = (async () => {
      const off = (await $.env.get('MAESTRO_OFF')) === '1'
      if (off) await logLine($, 'killswitch_on', '-', 'off')
      return off
    })()
    offOnce.catch(() => {
      offOnce = undefined
    })
  }
  return offOnce
}

async function rootsFor($: Engine, cwd: string): Promise<string[]> {
  const hit = rootsByCwd.get(cwd)
  if (hit) return hit
  let dir = cwd
  let root: string | undefined
  for (let k = 0; k < 16 && dir; k++) {
    if ((await $.fs.exists(`${dir}/.maestro.yaml`)) && (await $.fs.exists(`${dir}/config/routing-table.yaml`))) {
      root = dir
      break
    }
    dir = dir.slice(0, dir.lastIndexOf('/'))
  }
  const roots: string[] = []
  if (root && !root.startsWith('/tmp/')) {
    roots.push(root)
    try {
      const git = await $.fs.read(`${root}/.git`)
      const m = typeof git === 'string' ? /^gitdir:\s*(.+?)\/\.git\/worktrees\/[^/\n]+\s*$/m.exec(git) : null
      if (m?.[1]) roots.push(m[1])
    } catch {
      // .git e diretorio: este e o checkout
    }
  }
  rootsByCwd.set(cwd, roots)
  return roots
}

async function context($: Engine): Promise<Ctx> {
  const cwd = await $.session.cwd()
  const home = (await $.env.get('HOME')) || ''
  return { cwd, home, roots: await rootsFor($, cwd) }
}

export const register: Register = on => {
  on('tool.check', async ($, e, next) => {
    if (!GUARDED.includes(e.tool) || (await killSwitch($))) return next(e)
    const d = decide(e.tool, e.input, await context($))
    if (d.verdict === 'pass') return next(e)
    await logLine($, d.rule, e.tool, d.verdict)
    return { decision: d.verdict, reason: `maestro-guard [${d.rule}]: ${d.reason}` }
  }).catch(async ($, e, next) => {
    await logLine($, `guard_failed_${next.error?.kind ?? 'unknown'}`, e.tool, 'deny')
    return { decision: 'deny' as const, reason: `maestro-guard: falha interna (${next.error?.kind ?? 'unknown'}); recusado por seguranca` }
  })

  // segunda trava: o mesmo julgamento no tool.call, que so sabe negar
  on('tool.call', async ($, e, next) => {
    const name: string = e.tool
    if (!GUARDED.includes(name) || (await killSwitch($))) return next(e)
    const { tool: _t, tool_use_id: _u, consent: _c, agentId: _a, ...input } = e as Record<string, unknown>
    const d = decide(name, input, await context($))
    if (d.verdict !== 'deny') return next(e)
    await logLine($, d.rule, name, 'deny')
    return { deny: `maestro-guard [${d.rule}]: ${d.reason}` }
  }).catch(($, e, next) => (next.called ? next(e) : { deny: 'maestro-guard: falha interna; recusado por seguranca' }))
}
