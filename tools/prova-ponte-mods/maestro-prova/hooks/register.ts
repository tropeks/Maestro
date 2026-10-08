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
const SEGREDO = /(^|[/._-])(env|id_rsa|id_ed25519|credentials|secret|token)([/._-]|$)/i
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

async function registrar($: EngineInterface, c: Cfg, id: string, v: string, ms: number): Promise<void> {
  if (!c.log) return
  try {
    await $.fs.write(`${c.log}/${id.slice(0, 8)}-${c.papel}.log`, `rid=${id.slice(0, 8)} papel=${c.papel} veredito=${v} ms=${ms}\n`)
  } catch {
    // log nunca derruba a troca
  }
}

// Gerente: o pedido que cairia em `ask` vai ao Diretor; so allow valido libera.
async function pedir($: EngineInterface, c: Cfg, tool: string, input: unknown): Promise<{ v: Veredito; motivo: string }> {
  const t0 = await $.clock.now()
  let id = ''
  let v: Veredito = 'deny'
  let motivo = 'erro'
  try {
    const hash = await sha256(JSON.stringify([tool, input]))
    id = novoRid()
    const reg = await verificar($, c, { op: 'registrar-pedido', rid: id, hash })
    if (!reg.ok) {
      motivo = 'registro_recusado'
    } else {
      const espera = new Promise<string>(resolve => pendentes.set(id, resolve))
      const env = await $.session.send({
        to: { sessionId: c.par },
        text: JSON.stringify({ t: 'pedido', rid: id, classe: classificar(tool, input), hash }),
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
  await registrar($, c, id || '00000000', v, (await $.clock.now()) - t0)
  return { v, motivo }
}

// Diretor: verifica FORA da mensagem, decide pela tabela, responde por session.send.
async function atender($: EngineInterface, c: Cfg, m: Record<string, unknown>, id: string): Promise<{ consumed: string }> {
  const hash = m.hash
  if (m.t !== 'pedido' || typeof hash !== 'string' || !HEX64.test(hash) || typeof m.classe !== 'string') {
    return { consumed: 'malformado' }
  }
  const ver = await verificar($, c, { op: 'verificar-pedido', rid: id, hash })
  if (!ver.ok) return { consumed: `pedido_recusado:${ver.motivo}` }
  const v = decidir(m.classe)
  const reg = await verificar($, c, { op: 'registrar-decisao', rid: id, veredito: v })
  if (!reg.ok) return { consumed: `decisao_recusada:${reg.motivo}` }
  const env = await $.session.send({ to: { sessionId: c.par }, text: JSON.stringify({ t: 'decisao', rid: id, v }) })
  await registrar($, c, id, v, 0)
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

export const register: Register = on => {
  lida = undefined
  pendentes.clear()

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
    const m = parse(e.text)
    const id = m?.rid
    if (m === null || typeof id !== 'string' || !HEX32.test(id)) return { consumed: 'malformado' }
    return c.papel === 'diretor' ? atender($, c, m, id) : aplicar($, c, m, id)
  }).catch(() => ({ consumed: 'erro' }))
}
