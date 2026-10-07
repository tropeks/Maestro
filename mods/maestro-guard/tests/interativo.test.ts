// Decisao (a) do Diretor: destrutivo vira ask em sessao interativa e segue deny
// em headless; autoprotecao, segredo e queda segura seguem deny nos dois.
// Decisao (c): o mod nao casa `maestro order --accept`.
import type { On } from 'claude-code'
import { test, expect, tier } from 'claude-code/testing'
import { decide } from '../hooks/policy'
import { CORPUS, CTX, MALFORMED, WT } from './corpus'

tier('prepend')

const DESTRUTIVOS = [
  'rm -rf /',
  'rm -rf ~/Documents',
  'git push --force origin main',
  'git -C /home/rcosta00/dev/Maestro reset --hard HEAD',
  'git clean -fdx',
  'chmod -R 777 /',
  'psql -c "DROP TABLE users"',
  'psql -c "DELETE FROM users"',
  'mkfs.ext4 /dev/sdb1',
  'cat imagem.img > /dev/sdb',
]

test('puro: o mesmo destrutivo e ask interativo e deny headless', () => {
  const wrong: string[] = []
  for (const command of DESTRUTIVOS) {
    const head = decide('Bash', { command }, { ...CTX, interactive: false })
    const inter = decide('Bash', { command }, { ...CTX, interactive: true })
    const omitido = decide('Bash', { command }, CTX)
    if (head.verdict !== 'deny') wrong.push(`${command}: headless ${head.verdict}`)
    if (omitido.verdict !== 'deny') wrong.push(`${command}: sem flag ${omitido.verdict}`)
    if (inter.verdict !== 'ask') wrong.push(`${command}: interativo ${inter.verdict}`)
    if (inter.rule !== head.rule) wrong.push(`${command}: regra mudou ${head.rule} -> ${inter.rule}`)
  }
  expect(wrong).toEqual([])
})

test('puro: autoprotecao, segredo e queda segura seguem deny em sessao interativa', () => {
  const ctx = { ...CTX, interactive: true }
  const wrong: string[] = []
  const must: [string, unknown][] = [
    ['Edit', { file_path: 'lib/common.sh' }],
    ['Bash', { command: 'echo x > lib/a.sh' }],
    ['Read', { file_path: '.env' }],
    ['Bash', { command: 'cat ~/.ssh/id_rsa' }],
    ...MALFORMED.map((m): [string, unknown] => [m.tool, m.input]),
  ]
  for (const [tool, input] of must) {
    const got = decide(tool, input, ctx)
    if (got.verdict !== 'deny') wrong.push(`${tool} ${JSON.stringify(input).slice(0, 50)} => ${got.verdict}`)
  }
  expect(wrong).toEqual([])
})

test('puro: em sessao interativa nenhum caso do corpus vira deny onde era ask, nem deixa passar', () => {
  const wrong: string[] = []
  for (const c of CORPUS) {
    const head = decide(c.tool, c.input, { ...CTX, cwd: c.cwd ?? CTX.cwd })
    const inter = decide(c.tool, c.input, { ...CTX, cwd: c.cwd ?? CTX.cwd, interactive: true })
    if (head.verdict === 'pass' && inter.verdict !== 'pass') wrong.push(`${c.tool} passou a ${inter.verdict}`)
    if (head.verdict === 'ask' && inter.verdict !== 'ask') wrong.push(`${c.tool} ask virou ${inter.verdict}`)
    if (head.verdict === 'deny' && inter.verdict === 'pass') wrong.push(`${c.tool} deny virou pass`)
  }
  expect(wrong).toEqual([])
})

test('puro: maestro order --accept nao e casado, negado nem perguntado (decisao c)', () => {
  for (const command of ['maestro order --accept 072', 'maestro order --accept 072 --reason "ok"']) {
    expect(decide('Bash', { command }, CTX).verdict).toBe('pass')
    expect(decide('Bash', { command }, { ...CTX, interactive: true }).verdict).toBe('pass')
  }
})

// motor por baixo: cwd, ambiente e marcadores do Maestro; o log vai para `escritas`
const engine = (on: On, env: Record<string, string> = {}, escritas: string[] = []): void => {
  on('session.cwd', () => ({ value: WT }))
  on('env.get', (_$, e) => ({ value: e.name === 'HOME' ? '/home/rcosta00' : env[e.name] }))
  on('fs.exists', (_$, e) => ({ value: e.path.startsWith(WT) }))
  on('fs.read', () => ({ value: 'gitdir: /home/rcosta00/dev/Maestro/.git/worktrees/maestro-072\n' }))
  on('fs.write', (_$, e) => {
    escritas.push(String(e.text))
    return { value: undefined }
  })
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('tool.check', () => ({ decision: 'allow' as const, reason: 'motor' }))
}

test('fiacao: com isInteractive:true o destrutivo e ask', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: WT, isInteractive: true })
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'git push --force origin main' } })
  expect(r.decision).toBe('ask')
})

test('fiacao: com isInteractive:false o mesmo destrutivo e deny', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: WT, isInteractive: false })
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'git push --force origin main' } })
  expect(r.decision).toBe('deny')
})

test('fiacao: sem session.start a sessao conta como headless (deny)', async ($, on) => {
  engine(on)
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'git push --force origin main' } })
  expect(r.decision).toBe('deny')
})

test('fiacao: sessao interativa nao afrouxa autoprotecao nem segredo', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: WT, isInteractive: true })
  const a = await $.tool.check({ tool: 'Edit', input: { file_path: 'lib/common.sh' } })
  const b = await $.tool.check({ tool: 'Read', input: { file_path: '.env' } })
  expect(a.decision).toBe('deny')
  expect(b.decision).toBe('deny')
})

test('fiacao: queda segura segue deny em sessao interativa', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: WT, isInteractive: true })
  const r = await $.tool.check({ tool: 'Bash', input: { command: 7 } })
  expect(r.decision).toBe('deny')
})

test('fiacao: segundo no tool.call, destrutivo interativo nao e negado pelo mod (a pergunta e do tool.check)', async ($, on) => {
  engine(on)
  on('tool.call', () => ({ result: 'ran', text: 'ran', ref: 'x' }))
  await $.session.start({ cwd: WT, isInteractive: true })
  const r = await $.tool.call({ tool: 'Bash', command: 'git push --force origin main' })
  expect('deny' in r).toBe(false)
})

test('kill-switch (d): MAESTRO_OFF=1 desliga e loga rule=kill-switch, sem comando', async ($, on) => {
  const escritas: string[] = []
  engine(on, { MAESTRO_OFF: '1' }, escritas)
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'rm -rf /' } })
  expect(r.reason).toBe('motor')
  const log = escritas.join('\n')
  expect(log.includes('"rule":"kill-switch"')).toBe(true)
  expect(log.includes('rm -rf')).toBe(false)
})

test('kill-switch (d): sem MAESTRO_OFF o mod julga e nao loga kill-switch', async ($, on) => {
  const escritas: string[] = []
  engine(on, {}, escritas)
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'rm -rf /' } })
  expect(r.decision).toBe('deny')
  const log = escritas.join('\n')
  expect(log.includes('kill-switch')).toBe(false)
  expect(log.includes('"rule":"rm_recursive_wide"')).toBe(true)
})

test('segredo na fiacao: Read, Grep, Glob e cat negam; .env.example passa', async ($, on) => {
  engine(on)
  const nega: [string, Record<string, unknown>][] = [
    ['Read', { file_path: '.env' }],
    ['Grep', { pattern: 'KEY', path: '/home/rcosta00/.ssh' }],
    ['Glob', { pattern: '**/*.pem' }],
    ['Bash', { command: 'cat .env' }],
  ]
  for (const [tool, input] of nega) {
    const r = await $.tool.check({ tool, input })
    expect(r.decision).toBe('deny')
  }
  const ok = await $.tool.check({ tool: 'Read', input: { file_path: '.env.example' } })
  expect(ok.reason).toBe('motor')
})
