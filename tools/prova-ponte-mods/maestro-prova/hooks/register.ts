// Mod de prova da ordem 076 (NUNCA em mods/): gerente pede, Diretor responde por session.send.
// Dois papeis por variavel de ambiente (PROVA_PAPEL = diretor | gerente), lida na primeira
// necessidade apos o load. A identidade NAO vem da mensagem: cada operacao passa pelo
// cliente do verificador de peer (SO_PEERCRED), chamado por $.process.run, sem shell.
// Log so de metadados: rid truncado, papel, veredito, ms. Nunca comando, caminho nem prompt.
import type { EngineInterface, Register } from 'claude-code'

const TABELA_VERSAO = 1
const HEX32 = /^[0-9a-f]{32}$/
const HEX64 = /^[0-9a-f]{64}$/
const MAX_TEXTO = 2048
const ESPERA_MS = 8000
const SEGREDO = /(^|[/._"-])(env|id_rsa|id_ed25519|credentials|secret|token)([/._"-]|$)/i
const REDE = /\b(curl|wget|nc|ssh|scp|http|https)\b/i

type Veredito = 'allow' | 'deny'
type Cfg = { papel: string; sock: string; client: string; par: string; log: string }
type Resp = { ok: boolean; motivo: string }

let lida: Promise<Cfg> | undefined
const pendentes = new Map<string, (v: string) => void>()

// Funcao pura da tabela: so a leitura em pasta liberada passa; o resto e deny.
function decidir(classe: string): Veredito {
  return classe === 'leitura-liberada' ? 'allow' : 'deny'
}

// Funcao pura: a classe vem da ferramenta, nunca do texto digitado por outro processo.
function classificar(tool: string, input: unknown): string {
  const alvo = JSON.stringify(input ?? '')
  if (SEGREDO.test(alvo)) return 'segredo'
  if (tool === 'Read' || tool === 'Glob' || tool === 'Grep') return 'leitura-liberada'
  if (tool === 'Write' || tool === 'Edit' || tool === 'NotebookEdit') return 'escrita-protegida'
  if (tool === 'WebFetch' || tool === 'WebSearch' || REDE.test(alvo)) return 'rede'
  return 'outro'
}

function hex(b: Uint8Array): string {
  return Array.from(b, x => x.toString(16).padStart(2, '0')).join('')
}

async function sha256(texto: string): Promise<string> {
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto))))
}

function novoRid(): string {
  return hex(crypto.getRandomValues(new Uint8Array(16)))
}

// A 2.1.293 entrega o corpo embrulhado em <cross-session-message from=... from-name=... ...>.
// Os atributos sao do remetente (nao confiaveis): so o corpo interessa, e a identidade vem do verificador.
const ENVELOPE = /^<cross-session-message [^>]*>\n([\s\S]*)\n<\/cross-session-message>$/

function desembrulhar(texto: string): string {
  if (texto.length > MAX_TEXTO + 512) return ''
  const m = ENVELOPE.exec(texto)
  return m ? (m[1] ?? '') : texto
}

function parse(texto: string): Record<string, unknown> | null {
  if (texto.length > MAX_TEXTO) return null
  try {
    const m = JSON.parse(texto)
    return m !== null && typeof m === 'object' && !Array.isArray(m) ? (m as Record<string, unknown>) : null
  } catch {
    return null
  }
}

async function config($: EngineInterface): Promise<Cfg> {
  lida ??= (async () => ({
    papel: (await $.env.get('PROVA_PAPEL')) ?? '',
    sock: (await $.env.get('PROVA_SOCK')) ?? '',
    client: (await $.env.get('PROVA_CLIENT')) ?? '',
    par: (await $.env.get('PROVA_PAR')) ?? '',
    log: (await $.env.get('PROVA_LOG')) ?? '',
  }))()
  return lida
}

// Uma operacao do verificador. Qualquer falha (processo, saida, JSON) e recusa.
async function verificar($: EngineInterface, c: Cfg, req: Record<string, unknown>): Promise<Resp> {
  try {
    const r = await $.process.run(['python3', '-I', c.client, c.sock, JSON.stringify(req)], { timeoutMs: 3000 })
    const j = JSON.parse(r.stdout.trim()) as { ok?: unknown; motivo?: unknown }
    return { ok: j.ok === true, motivo: typeof j.motivo === 'string' ? j.motivo : 'sem_motivo' }
  } catch {
    return { ok: false, motivo: 'erro' }
  }
}

type Linha = { id: string; v: string; ms: number; motivo: string }

// Log so de metadados: rid truncado, papel, veredito, ms e o codigo fixo do motivo (nunca texto livre).
async function registrar($: EngineInterface, c: Cfg, l: Linha): Promise<void> {
  if (!c.log) return
  try {
    await $.fs.write(`${c.log}/${l.id.slice(0, 8)}-${c.papel}.log`, `rid=${l.id.slice(0, 8)} papel=${c.papel} veredito=${l.v} ms=${l.ms} motivo=${l.motivo}\n`)
  } catch {
    // log nunca derruba a troca
  }
}

// Gerente: o pedido que cairia em `ask` vai ao Diretor; so allow valido libera.
async function pedir($: EngineInterface, c: Cfg, tool: string, input: unknown): Promise<{ v: Veredito; motivo: string; ms: number }> {
  const t0 = await $.clock.now()
  let id = ''
  let v: Veredito = 'deny'
  let motivo = 'erro'
  try {
    const hash = await sha256(JSON.stringify([tool, input]))
    const classe = classificar(tool, input)
    id = novoRid()
    const reg = await verificar($, c, { op: 'registrar-pedido', rid: id, hash, classe })
    if (!reg.ok) {
      motivo = 'registro_recusado'
    } else {
      const espera = new Promise<string>(resolve => pendentes.set(id, resolve))
      const env = await $.session.send({
        to: { sessionId: c.par },
        text: JSON.stringify({ t: 'pedido', rid: id, classe, hash }),
      })
      if (!env.isDelivered) {
        motivo = 'entrega_falhou'
      } else {
        const r = await Promise.race([espera, $.clock.sleep(ESPERA_MS).then(() => 'timeout')])
        v = r === 'allow' ? 'allow' : 'deny'
        motivo = r === 'timeout' ? 'timeout' : 'decidido'
      }
    }
  } catch {
    v = 'deny'
    motivo = 'excecao'
  }
  pendentes.delete(id)
  const ms = (await $.clock.now()) - t0
  await registrar($, c, { id: id || '00000000', v, ms, motivo })
  return { v, motivo, ms }
}

// Diretor: verifica FORA da mensagem, decide pela tabela, responde por session.send.
async function atender($: EngineInterface, c: Cfg, m: Record<string, unknown>, id: string): Promise<{ consumed: string }> {
  const hash = m.hash
  if (m.t !== 'pedido' || typeof hash !== 'string' || !HEX64.test(hash) || typeof m.classe !== 'string') {
    return { consumed: 'malformado' }
  }
  const ver = await verificar($, c, { op: 'verificar-pedido', rid: id, hash, classe: m.classe })
  if (!ver.ok) return { consumed: `pedido_recusado:${ver.motivo}` }
  const v = decidir(m.classe)
  const reg = await verificar($, c, { op: 'registrar-decisao', rid: id, veredito: v })
  if (!reg.ok) return { consumed: `decisao_recusada:${reg.motivo}` }
  const env = await $.session.send({ to: { sessionId: c.par }, text: JSON.stringify({ t: 'decisao', rid: id, v }) })
  await registrar($, c, { id, v, ms: 0, motivo: 'atendido' })
  return { consumed: env.isDelivered ? `atendido:v${TABELA_VERSAO}` : 'resposta_nao_entregue' }
}

// Gerente recebendo: a decisao so vale se o verificador atesta que o Diretor a registrou.
async function aplicar($: EngineInterface, c: Cfg, m: Record<string, unknown>, id: string): Promise<{ consumed: string }> {
  const v = m.v
  if (m.t !== 'decisao' || (v !== 'allow' && v !== 'deny')) return { consumed: 'malformado' }
  const ver = await verificar($, c, { op: 'verificar-decisao', rid: id, veredito: v })
  if (!ver.ok) return { consumed: `decisao_recusada:${ver.motivo}` }
  const entrega = pendentes.get(id)
  if (!entrega) return { consumed: 'sem_pedido_pendente' }
  entrega(v)
  return { consumed: 'decisao_aplicada' }
}

// Rotacao das trocas do comando: cada classe da tabela aparece, a decisao esperada vem da funcao pura.
const ROTACAO: Array<[string, Record<string, unknown>]> = [
  ['Read', { file_path: '/etc/hostname' }],
  ['Write', { file_path: '/etc/prova-alvo' }],
  ['Read', { file_path: '/home/prova/.env' }],
  ['WebFetch', { url: 'https://exemplo.invalido' }],
  ['Bash', { command: 'ls' }],
]

// Inteiros: percentil por posicao (nearest-rank), sem float no resultado.
function pct(ordenado: number[], p: number): number {
  return ordenado[Math.max(0, Math.trunc((p * ordenado.length + 99) / 100) - 1)] ?? 0
}

// O hook de command.run vale 10 s (medido: 100 trocas num comando falham fechado aos 13,8 s):
// cada comando faz um LOTE de ate MAX_LOTE trocas; o aparelho emite um comando por lote.
const MAX_LOTE = 12
let lote = 0
let serial = 0

// /prova-ponte N: N (<= MAX_LOTE) trocas gerente -> Diretor -> gerente, SEM turno de modelo
// (nao passa por tool.check). Grava lote-NNN.txt com os ms brutos (inteiros) para o aparelho somar.
async function trocas($: EngineInterface, c: Cfg, args: string): Promise<{ text: string; exitCode: number }> {
  // /prova-ponte N [pausa_ms]: a pausa fica ENTRE as trocas (fora do ms medido) e mantem o ritmo
  // abaixo do limite de taxa do receptor; N * (pausa + ~700 ms) tem de caber nos 10 s do hook.
  const m = /^\s*(\d{1,3})(?:\s+(\d{1,4}))?\s*$/.exec(args)
  const n = m ? Number.parseInt(m[1] ?? '0', 10) : 0
  const pausa = m?.[2] ? Number.parseInt(m[2], 10) : 0
  if (c.papel !== 'gerente' || n < 1 || n > MAX_LOTE || n * (pausa + 700) > 9500) {
    return { text: `prova-ponte: uso /prova-ponte N [pausa_ms] (N de 1 a ${MAX_LOTE}; N*(pausa+700) <= 9500: limite de 10 s do hook), so no gerente`, exitCode: 2 }
  }
  const t0 = await $.clock.now()
  const ms: number[] = []
  let corretas = 0
  let errados = 0 // decisao aplicada com veredito diferente do esperado: o unico jeito de um impostor "ganhar"
  let timeouts = 0
  let primeira = 0
  for (let i = 0; i < n; i++) {
    const [tool, base] = ROTACAO[serial % ROTACAO.length]!
    const input = { ...base, n: serial }
    serial += 1
    const r = await pedir($, c, tool, input)
    ms.push(r.ms)
    if (r.motivo === 'timeout') timeouts += 1
    if (r.motivo === 'decidido' && r.v !== decidir(classificar(tool, input))) errados += 1
    if (r.motivo === 'decidido' && r.v === decidir(classificar(tool, input))) corretas += 1
    else if (primeira === 0) primeira = i + 1
    if (pausa > 0 && i < n - 1) await $.clock.sleep(pausa)
  }
  const ordenado = [...ms].sort((a, b) => a - b)
  const mediana = ordenado.length % 2 ? (ordenado[(ordenado.length - 1) / 2] ?? 0) : Math.trunc(((ordenado[ordenado.length / 2 - 1] ?? 0) + (ordenado[ordenado.length / 2] ?? 0)) / 2)
  const total = (await $.clock.now()) - t0
  const text =
    `prova-ponte trocas=${n} corretas=${corretas} falhas=${n - corretas} timeouts=${timeouts} primeira_falha=${primeira} ` +
    `mediana_ms=${mediana} p95_ms=${pct(ordenado, 95)} max_ms=${ordenado[ordenado.length - 1] ?? 0} total_ms=${total}`
  if (c.log) {
    lote += 1
    try {
      await $.fs.write(
        `${c.log}/lote-${String(lote).padStart(3, '0')}.txt`,
        `trocas=${n} corretas=${corretas} errados=${errados} timeouts=${timeouts} primeira_falha=${primeira} ms=${ms.join(' ')}\n`,
      )
    } catch {
      // log nunca derruba a prova
    }
  }
  return { text, exitCode: corretas === n ? 0 : 1 }
}

export const register: Register = on => {
  lida = undefined
  lote = 0
  serial = 0
  pendentes.clear()

  on('session.start', async ($, e, next) => {
    try {
      await $.command.register({ name: 'prova-ponte', description: 'Prova da Ponte: N trocas gerente-Diretor sem turno de modelo.', argumentHint: '[N]' })
    } catch {
      // sem o comando a prova segue pelo caminho real (tool.check)
    }
    return next(e)
  }).catch(() => ({}))

  on('command.run', { command: 'prova-ponte' }, async ($, e) => trocas($, await config($), e.args)).catch(() => ({
    text: 'prova-ponte: erro',
    exitCode: 1,
  }))

  on('tool.check', async ($, e, next) => {
    const c = await config($)
    const base = await next(e)
    if (c.papel !== 'gerente' || base.decision !== 'ask') return base
    const r = await pedir($, c, e.tool, e.input)
    return { decision: r.v, reason: `maestro-prova: ${r.motivo}` }
  }).catch(() => ({ decision: 'deny' as const, reason: 'maestro-prova: falha do gerente de teste' }))

  on('session.receive', async ($, e, next) => {
    const c = await config($)
    if (c.papel !== 'diretor' && c.papel !== 'gerente') return next(e)
    const m = parse(desembrulhar(e.text))
    const id = m?.rid
    if (m === null || typeof id !== 'string' || !HEX32.test(id)) return { consumed: 'malformado' }
    return c.papel === 'diretor' ? atender($, c, m, id) : aplicar($, c, m, id)
  }).catch(() => ({ consumed: 'erro' }))
}
