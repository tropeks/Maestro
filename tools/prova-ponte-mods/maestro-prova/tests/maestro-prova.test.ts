// Ordem 076 / turno 3: testes do mod maestro-prova, escritos ANTES do mod.
// O verificador de peer e substituido por um falso que modela as mesmas regras
// (rid de uso unico, hash, papel); a identidade do chamador vem do PAPEL do teste,
// nunca da mensagem. Os impostores mandam mensagens com o nome do gerente/Diretor.
import { test, expect, mock } from 'claude-code/testing'

const HEX = '0123456789abcdef'
const rid = (n: number) => (HEX[n % 16] ?? '0').repeat(32)
const sha = (c: string) => c.repeat(64)

type Req = { op: string; rid: string; hash?: string; veredito?: string }
type Registro = { hash: string; pedidoUsado: boolean; decisao: string | null; decisaoUsada: boolean }

// Verificador falso: as regras do real (tools/prova-ponte-mods/peer-verifier), em memoria.
function falso(papel: 'diretor' | 'gerente') {
  const reg = new Map<string, Registro>()
  const operacoes: string[] = []
  const aplicar = (r: Req) => {
    const p = reg.get(r.rid)
    switch (r.op) {
      case 'registrar-pedido':
        if (papel !== 'gerente') return false
        if (p || typeof r.hash !== 'string') return false
        reg.set(r.rid, { hash: r.hash, pedidoUsado: false, decisao: null, decisaoUsada: false })
        return true
      case 'verificar-pedido':
        if (papel !== 'diretor' || !p || p.pedidoUsado || p.hash !== r.hash) return false
        p.pedidoUsado = true
        return true
      case 'registrar-decisao':
        if (papel !== 'diretor' || !p || !p.pedidoUsado || p.decisao !== null) return false
        if (r.veredito !== 'allow' && r.veredito !== 'deny') return false
        p.decisao = r.veredito
        return true
      case 'verificar-decisao':
        if (papel !== 'gerente' || !p || p.decisao === null || p.decisaoUsada) return false
        if (p.decisao !== r.veredito) return false
        p.decisaoUsada = true
        return true
      default:
        return false
    }
  }
  return { reg, operacoes, aplicar }
}

const AMBIENTE = (papel: string) => ({
  PROVA_PAPEL: papel,
  PROVA_SOCK: '/tmp/prova.sock',
  PROVA_CLIENT: '/tmp/peer-client',
  PROVA_PAR: 'sessao-par',
  PROVA_LOG: '/tmp/prova-log',
})

const PEER = { kind: 'peer', plugin: 'maestro-prova' } as const

const pedido = (id: string, classe: string, hash: string) =>
  JSON.stringify({ t: 'pedido', rid: id, classe, hash })
const decisao = (id: string, v: string) => JSON.stringify({ t: 'decisao', rid: id, v })

// ---------------------------------------------------------------- Diretor

const CLASSES: Array<[string, string]> = [
  ['leitura-liberada', 'allow'],
  ['escrita-protegida', 'deny'],
  ['segredo', 'deny'],
  ['rede', 'deny'],
  ['outro', 'deny'],
  ['classe-que-nao-existe', 'deny'],
]

for (const [classe, esperado] of CLASSES) {
  test(`diretor: classe ${classe} -> ${esperado}`, async ($, on) => {
    mock.env(on, AMBIENTE('diretor'))
    const v = falso('diretor')
    const enviados: Array<{ to: unknown; text: string }> = []
    on('process.run', (_$, e) => {
      const r = JSON.parse(e.argv[4] as string) as Req
      return { value: { exitCode: 0, stdout: JSON.stringify({ ok: v.aplicar(r), motivo: 'x' }) + '\n', stderr: '' } }
    })
    on('session.send', (_$, e) => {
      enviados.push({ to: e.to, text: e.text })
      return { isDelivered: true as const }
    })
    on('fs.write', () => ({ value: undefined }))
    on('clock.now', () => ({ value: 1000 }))
    v.reg.set(rid(1), { hash: sha('a'), pedidoUsado: false, decisao: null, decisaoUsada: false })
    const r = await $.session.receive({ origin: PEER, text: pedido(rid(1), classe, sha('a')) })
    expect(r.consumed).toBeDefined()
    expect(enviados.length).toBe(1)
    expect(JSON.parse(enviados[0]!.text)).toEqual({ t: 'decisao', rid: rid(1), v: esperado })
    expect(enviados[0]!.to).toBe('sessao-par') // o engine escreve o endereco { sessionId } como string em e.to
  })
}

test('diretor: impostores (todas as formas) -> 0 aceitas', async ($, on) => {
  mock.env(on, AMBIENTE('diretor'))
  const v = falso('diretor')
  let enviados = 0
  on('process.run', (_$, e) => {
    const r = JSON.parse(e.argv[4] as string) as Req
    return { value: { exitCode: 0, stdout: JSON.stringify({ ok: v.aplicar(r), motivo: 'x' }) + '\n', stderr: '' } }
  })
  on('session.send', () => {
    enviados += 1
    return { isDelivered: true as const }
  })
  on('fs.write', () => ({ value: undefined }))
  on('clock.now', () => ({ value: 1000 }))
  const tentativas: Array<[string, string, object]> = [
    // nome do gerente escrito pelo remetente, rid que o verificador nunca viu
    ['nome_falso_gerente', pedido(rid(2), 'leitura-liberada', sha('b')), PEER],
    ['nome_falso_outro', pedido(rid(3), 'leitura-liberada', sha('b')), { kind: 'peer', plugin: 'qualquer' }],
    ['sem_plugin', pedido(rid(4), 'leitura-liberada', sha('b')), { kind: 'peer' }],
    ['coordenador', pedido(rid(5), 'leitura-liberada', sha('b')), { kind: 'coordinator', plugin: 'maestro-prova' }],
    ['teammate_nao_verificado', pedido(rid(6), 'leitura-liberada', sha('b')), { kind: 'peer', plugin: 'maestro-prova', teammate: 'gerente', isVerified: false }],
    ['malformado', 'isto nao e json', PEER],
    ['malformado', '{"t":"pedido"', PEER],
    ['malformado', '[1,2]', PEER],
    ['rid_invalido', pedido('abc', 'leitura-liberada', sha('b')), PEER],
    ['hash_invalido', pedido(rid(7), 'leitura-liberada', 'curto'), PEER],
    ['gigante', JSON.stringify({ t: 'pedido', rid: rid(8), classe: 'leitura-liberada', hash: sha('b'), pad: 'a'.repeat(70000) }), PEER],
    ['tipo_errado', decisao(rid(9), 'allow'), PEER],
    ['vazio', '', PEER],
  ]
  for (const [, texto, origin] of tentativas) {
    const r = await $.session.receive({ origin: origin as never, text: texto })
    expect(r.consumed).toBeDefined()
  }
  // replay: um pedido registrado e atendido uma vez; a segunda vez e impostor.
  v.reg.set(rid(10), { hash: sha('c'), pedidoUsado: false, decisao: null, decisaoUsada: false })
  await $.session.receive({ origin: PEER, text: pedido(rid(10), 'leitura-liberada', sha('c')) })
  const antes = enviados
  await $.session.receive({ origin: PEER, text: pedido(rid(10), 'leitura-liberada', sha('c')) })
  // hash trocado sobre pedido registrado
  v.reg.set(rid(11), { hash: sha('d'), pedidoUsado: false, decisao: null, decisaoUsada: false })
  await $.session.receive({ origin: PEER, text: pedido(rid(11), 'leitura-liberada', sha('e')) })
  const aceitos = enviados - antes
  expect(aceitos, `impostores_aceitos=${aceitos}`).toBe(0)
  expect(antes, `legitimas=${antes}`).toBe(1)
})

// ---------------------------------------------------------------- Gerente

for (const v of ['allow', 'deny'] as const) {
  test(`gerente: decisao ${v} valida -> ${v}`, async ($, on) => {
    mock.env(on, AMBIENTE('gerente'))
    const f = falso('gerente')
    mock.clock(on, { now: 5000 })
    on('tool.check', () => ({ decision: 'ask' as const }))
    on('process.run', (_$, e) => {
      const r = JSON.parse(e.argv[4] as string) as Req
      return { value: { exitCode: 0, stdout: JSON.stringify({ ok: f.aplicar(r), motivo: 'x' }) + '\n', stderr: '' } }
    })
    on('fs.write', () => ({ value: undefined }))
    on('session.send', (_$, e) => {
      const p = JSON.parse(e.text) as { rid: string }
      const reg = f.reg.get(p.rid)!
      reg.decisao = v // o Diretor (outro processo) registrou a decisao no verificador
      void $.session.receive({ origin: PEER, text: decisao(p.rid, v) })
      return { isDelivered: true as const }
    })
    const r = await $.tool.check({ tool: 'Bash', input: { command: 'ls' } })
    expect(r.decision).toBe(v)
  })
}

test('gerente: sem resposta em 8 s -> deny (timeout, nunca allow)', async ($, on) => {
  mock.env(on, AMBIENTE('gerente'))
  const f = falso('gerente')
  const clk = mock.clock(on, { now: 5000 })
  on('tool.check', () => ({ decision: 'ask' as const }))
  on('process.run', (_$, e) => {
    const r = JSON.parse(e.argv[4] as string) as Req
    return { value: { exitCode: 0, stdout: JSON.stringify({ ok: f.aplicar(r), motivo: 'x' }) + '\n', stderr: '' } }
  })
  on('fs.write', () => ({ value: undefined }))
  on('session.send', () => ({ isDelivered: true as const }))
  const p = $.tool.check({ tool: 'Bash', input: { command: 'ls' } })
  await clk.advance(8000)
  const r = await p
  expect(r.decision).toBe('deny')
})

// Fail-closed: cada queda do gerente de teste termina em deny, nunca em allow.
for (const [nome, verificador, entrega] of [
  ['throw no verificador', 'throw', true],
  ['resposta invalida do verificador', 'lixo', true],
  ['verificador recusa o registro', 'recusa', true],
  ['entrega ao Diretor falha', 'ok', false],
] as const) {
  test(`gerente fail-closed: ${nome} -> deny`, async ($, on) => {
    mock.env(on, AMBIENTE('gerente'))
    mock.clock(on, { now: 5000 })
    on('tool.check', () => ({ decision: 'ask' as const }))
    on('fs.write', () => ({ value: undefined }))
    on('session.send', () => (entrega ? { isDelivered: true as const } : { isDelivered: false as const, reason: 'sem par' }))
    on('process.run', () => {
      if (verificador === 'throw') throw new Error('verificador caiu')
      const saida = verificador === 'lixo' ? '<<nao e json>>\n' : JSON.stringify({ ok: verificador === 'ok', motivo: 'x' }) + '\n'
      return { value: { exitCode: 0, stdout: saida, stderr: '' } }
    })
    const r = await $.tool.check({ tool: 'Bash', input: { command: 'ls' } })
    expect(r.decision).toBe('deny')
  })
}

test('gerente: decisao de impostor (nome do Diretor, rid nao registrado) nao libera nada', async ($, on) => {
  mock.env(on, AMBIENTE('gerente'))
  const f = falso('gerente')
  mock.clock(on, { now: 5000 })
  on('process.run', (_$, e) => {
    const r = JSON.parse(e.argv[4] as string) as Req
    return { value: { exitCode: 0, stdout: JSON.stringify({ ok: f.aplicar(r), motivo: 'x' }) + '\n', stderr: '' } }
  })
  on('fs.write', () => ({ value: undefined }))
  const r = await $.session.receive({ origin: PEER, text: decisao(rid(12), 'allow') })
  expect(r.consumed).toBeDefined()
})

test('papel ausente ou desconhecido: o mod nao age (degrada para o fluxo normal)', async ($, on) => {
  mock.env(on, { PROVA_PAPEL: 'ninguem' })
  on('tool.check', () => ({ decision: 'ask' as const }))
  on('session.receive', (_$, e) => ({ text: e.text }))
  const r = await $.tool.check({ tool: 'Bash', input: { command: 'ls' } })
  expect(r.decision).toBe('ask')
})
