// A decisao como funcao pura (hooks/policy.ts) contra o corpus inteiro.
// `claude plugin test` nao dispara tool.check por este arquivo: a fiacao do hook
// esta em wiring.test.ts; aqui o que se mede e a decisao e as contagens FP/FN.
import { test, expect } from 'claude-code/testing'
import { decide } from '../hooks/policy'
import { CORPUS, CTX, DENY, PASS, ASK, MALFORMED } from './corpus'

const label = (c: { tool: string; input: unknown }) =>
  `${c.tool} ${JSON.stringify(c.input).slice(0, 90)}`

test('corpus: tamanho minimo da ordem (>=150, >=60 passam, >=60 negam)', () => {
  expect(CORPUS.length >= 150).toBe(true)
  expect(PASS.filter(c => c.want === 'pass').length >= 60).toBe(true)
  expect(DENY.filter(c => c.want === 'deny').length >= 60).toBe(true)
  expect(ASK.length >= 20).toBe(true)
})

test('corpus: todo caso tem o veredito esperado', () => {
  const wrong: string[] = []
  let fp = 0
  let fn = 0
  for (const c of CORPUS) {
    const got = decide(c.tool, c.input, { ...CTX, cwd: c.cwd ?? CTX.cwd })
    if (got.verdict !== c.want) {
      wrong.push(`${label(c)} => ${got.verdict}/${got.rule}, esperado ${c.want}`)
      if (c.want === 'pass') fp++
      if (c.want === 'deny') fn++
    }
  }
  console.log(
    `corpus=${CORPUS.length} pass=${PASS.length} deny=${DENY.length} ask=${ASK.length} falso_positivo=${fp} falso_negativo=${fn} divergentes=${wrong.length}`,
  )
  expect(wrong).toEqual([])
})

test('controles negativos: nada que DEVE passar vira deny ou ask', () => {
  const blocked = PASS.filter(c => c.want === 'pass')
    .map(c => ({ c, got: decide(c.tool, c.input, { ...CTX, cwd: c.cwd ?? CTX.cwd }) }))
    .filter(x => x.got.verdict !== 'pass')
    .map(x => `${label(x.c)} => ${x.got.verdict}/${x.got.rule}`)
  expect(blocked).toEqual([])
})

test('ambiguo vira ask, nunca deny', () => {
  const wrong = ASK.map(c => ({ c, got: decide(c.tool, c.input, { ...CTX, cwd: c.cwd ?? CTX.cwd }) }))
    .filter(x => x.got.verdict !== 'ask')
    .map(x => `${label(x.c)} => ${x.got.verdict}/${x.got.rule}`)
  expect(wrong).toEqual([])
})

test('queda segura: entrada malformada, gigante ou ilegivel NEGA', () => {
  const wrong = MALFORMED.map(m => ({ m, got: decide(m.tool, m.input, CTX) }))
    .filter(x => x.got.verdict !== 'deny')
    .map(x => `${x.m.name} => ${x.got.verdict}/${x.got.rule}`)
  expect(wrong).toEqual([])
})

test('a decisao nunca emite allow e nunca devolve texto do comando', () => {
  for (const c of CORPUS) {
    const got = decide(c.tool, c.input, { ...CTX, cwd: c.cwd ?? CTX.cwd }) as Record<string, unknown>
    expect(['deny', 'ask', 'pass'].includes(got.verdict as string)).toBe(true)
    expect(/^[a-z0-9_]{1,40}$/.test(got.rule as string)).toBe(true)
    const cmd = (c.input as { command?: unknown }).command
    if (typeof cmd === 'string' && cmd.length > 8) {
      expect(String(got.reason).includes(cmd)).toBe(false)
    }
  }
})
