// Segredo: leitura de .env*, ~/.ssh, ~/.ponte, ~/.claude/.credentials*, certificados.
// So texto de caminho e de comando, nunca o conteudo do arquivo: o mod nao le segredo.
import type { Word } from './shell-lex'
import { deny, type Cmd, type Decision, type State } from './types'

const TEMPLATE = /\.(example|sample|template|dist|defaults?)$/i
// .env, .env.local, .env.* e o glob .env*; nao pega .environment.md nem .envrc
const ENV_FILE = /^\.env($|[.*?[{])/
const CERT_EXT = /\.(pem|pfx|p12)($|[^a-z0-9])/i
const CERT_BRACE = /\.\{[^}]*\b(pem|pfx|p12)\b/i
const ECPF = /e-?cpf/i

// texto de caminho (ou de glob) que nomeia um segredo
export function isSecretPath(p: string): boolean {
  const parts = p.split('/').filter(Boolean)
  const base = parts[parts.length - 1] ?? ''
  if (ENV_FILE.test(base) && !TEMPLATE.test(base)) return true
  if (parts.includes('.ssh') || parts.includes('.ponte')) return true
  const i = parts.indexOf('.claude')
  if (i >= 0 && (parts[i + 1] ?? '').startsWith('.credentials')) return true
  if (CERT_EXT.test(base) || CERT_BRACE.test(base)) return true
  return ECPF.test(base) && /\.(pfx|p12|pem|cer|crt)$/i.test(base)
}

const SECRET_REASON = 'leitura de segredo (.env, chave, credencial ou certificado) nao e permitida'
const secretDeny = (): Decision => deny('secret_read', SECRET_REASON)

const READERS = new Set([
  'cat', 'less', 'more', 'head', 'tail', 'tac', 'nl', 'od', 'xxd', 'strings', 'bat', 'batcat',
  'grep', 'egrep', 'fgrep', 'rg', 'ag', 'awk', 'sed', 'cut', 'sort', 'uniq', 'base64', 'zcat', 'jq', 'yq',
  'cp', 'scp', 'rsync',
])

// cp/scp/rsync: so a ORIGEM e leitura (o destino .env de `cp .env.example .env` e legitimo)
const COPIERS = new Set(['cp', 'scp', 'rsync'])

export function secretReader(c: Cmd, st: State): void {
  if (!READERS.has(c.head)) return
  const hasTarget = c.args.some(a => a.t === '-t' || a.t.startsWith('--target-directory'))
  const sources: Word[] = COPIERS.has(c.head) && !hasTarget ? c.ops.slice(0, -1) : c.ops
  if (sources.some(w => isSecretPath(w.t))) st.findings.push(secretDeny())
}

// `cmd < arquivo`: qualquer comando que recebe um segredo por stdin o le (a revisao de
// seguranca da 072, P2-1). Vale para o comando todo, nao so para a lista de leitores.
export function secretInput(inputs: readonly Word[], st: State): void {
  if (inputs.some(w => isSecretPath(w.t))) st.findings.push(secretDeny())
}

const FIELDS: Record<string, string[]> = {
  Read: ['file_path'],
  Grep: ['path', 'glob'],
  Glob: ['path', 'pattern'],
}

// Read, Grep e Glob: o caminho, o glob e o padrao de arquivo
export function checkSecretTool(tool: string, input: unknown): Decision | null {
  if (typeof input !== 'object' || input === null) return deny('malformed', 'entrada da ferramenta ilegivel')
  const rec = input as Record<string, unknown>
  for (const key of FIELDS[tool] ?? []) {
    const v = rec[key]
    if (v === undefined) {
      if (tool === 'Read') return deny('malformed', 'caminho do arquivo ausente')
      continue
    }
    if (typeof v !== 'string') return deny('malformed', 'campo de caminho nao-texto')
    if (/[\u0000�]/.test(v)) return deny('bad_bytes', 'caminho com bytes invalidos')
    if (isSecretPath(v)) return secretDeny()
  }
  return null
}
