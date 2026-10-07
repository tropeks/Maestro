// Fiacao do hook: tool.check (via $.tool.check, que roda a mesma cadeia) e a
// segunda trava em tool.call. O mod fica no tier 'prepend', o das orgs.
import type { On } from 'claude-code'
import { test, expect, tier } from 'claude-code/testing'

tier('prepend')

const WT = '/home/rcosta00/dev/worktrees/maestro-072'

// o "motor" por baixo do mod: cwd, ambiente, marcadores do Maestro e o veredito base
const engine = (on: On, env: Record<string, string> = {}, cwdBroken = false): void => {
  // chamadas em `$` voltam como { value }
  on('session.cwd', () => {
    if (cwdBroken) throw new Error('boom')
    return { value: WT }
  })
  on('env.get', (_$, e) => ({ value: e.name === 'HOME' ? '/home/rcosta00' : env[e.name] }))
  on('fs.exists', (_$, e) => ({ value: e.path.startsWith(WT) }))
  on('fs.read', () => ({ value: 'gitdir: /home/rcosta00/dev/Maestro/.git/worktrees/maestro-072\n' }))
  on('fs.write', () => ({ value: undefined }))
  on('tool.check', () => ({ decision: 'allow' as const, reason: 'motor' }))
}

test('destrutivo nega', async ($, on) => {
  engine(on)
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'rm -rf /' } })
  expect(r.decision).toBe('deny')
})

test('autoprotecao nega Edit em lib/', async ($, on) => {
  engine(on)
  const r = await $.tool.check({ tool: 'Edit', input: { file_path: 'lib/common.sh' } })
  expect(r.decision).toBe('deny')
})

test('autoprotecao alcanca o checkout lido do .git do worktree', async ($, on) => {
  engine(on)
  const r = await $.tool.check({ tool: 'Write', input: { file_path: '/home/rcosta00/dev/Maestro/hooks/x.sh' } })
  expect(r.decision).toBe('deny')
})

test('ambiguo vira ask', async ($, on) => {
  engine(on)
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'git push -f origin feature/x' } })
  expect(r.decision).toBe('ask')
})

test('o que passa devolve o que next(e) devolveu; o mod nao emite allow', async ($, on) => {
  engine(on)
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'echo $?' } })
  expect(r.reason).toBe('motor')
})

test('ferramenta fora da guarda segue direto', async ($, on) => {
  engine(on)
  const r = await $.tool.check({ tool: 'Read', input: { file_path: 'lib/common.sh' } })
  expect(r.reason).toBe('motor')
})

test('evento malformado nega', async ($, on) => {
  engine(on)
  const r = await $.tool.check({ tool: 'Bash', input: { command: 7 } })
  expect(r.decision).toBe('deny')
})

test(
  'outro mod no tier user que devolve allow nao vence o guard',
  {
    plugins: [
      {
        name: 'permissivo',
        tier: 'user',
        register(on) {
          on('tool.check', () => ({ decision: 'allow' as const, reason: 'permissivo' }))
        },
      },
    ],
  },
  async ($, on) => {
    engine(on)
    const r = await $.tool.check({ tool: 'Bash', input: { command: 'git push --force origin main' } })
    expect(r.decision).toBe('deny')
  },
)

test('queda segura: falha do motor por baixo nega, nao libera', async ($, on) => {
  engine(on, {}, true)
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'echo oi' } })
  expect(r.decision).toBe('deny')
})

test('kill-switch MAESTRO_OFF=1 desliga o mod', async ($, on) => {
  engine(on, { MAESTRO_OFF: '1' })
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'rm -rf /' } })
  expect(r.reason).toBe('motor')
})

test('segunda trava: tool.call com destrutivo e negado', async ($, on) => {
  engine(on)
  on('tool.call', () => ({ result: 'ran', text: 'ran', ref: 'x' }))
  const r = await $.tool.call({ tool: 'Bash', command: 'rm -rf /' })
  expect('deny' in r || ('isError' in r && r.isError === true)).toBe(true)
})
