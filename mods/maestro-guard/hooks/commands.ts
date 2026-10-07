// Regras por comando (o verbo na cabeca do segmento). Sem recursao: shells,
// eval, ssh e cd ficam em policy.ts, que cuida do aninhamento e do cwd.
import { DB_CLIENTS, type Word } from './shell-lex'
import { codeTouchesProtected, writeTarget } from './paths'
import { rmTarget } from './rm-rules'
import { gitCheck } from './git-rules'
import { hasShort } from './args'
import { secretReader } from './secrets'
import { ask, deny, type Cmd, type State } from './types'

type Handler = (c: Cmd, st: State) => void

const rmHandler: Handler = (c, st) => {
  if (c.flags.includes('--no-preserve-root')) {
    st.findings.push(deny('rm_recursive_wide', 'rm --no-preserve-root'))
    return
  }
  const recursive = c.flags.includes('--recursive') || hasShort(c.flags, /[rR]/)
  for (const t of c.ops) writeTarget(t, st, 'rm')
  if (!recursive) return
  if (c.xargs && c.ops.length === 0) {
    st.findings.push(deny('rm_recursive_wide', 'rm recursivo com alvo vindo de pipe'))
    return
  }
  for (const t of c.ops) {
    const r = rmTarget(t, st)
    if (r === 'deny') st.findings.push(deny('rm_recursive_wide', 'rm recursivo de alvo largo (raiz, home, sistema ou diretorio atual)'))
    else if (r === 'ask') st.findings.push(ask('rm_recursive', 'rm recursivo de alvo que nao e artefato de build'))
  }
}

const tee: Handler = (c, st) => c.ops.forEach(t => writeTarget(t, st, 'tee'))

const sed: Handler = (c, st) => {
  if (c.flags.some(f => f.startsWith('--in-place')) || hasShort(c.flags, /i/)) c.ops.forEach(t => writeTarget(t, st, 'sed -i'))
}

// interpretadores com codigo inline: o literal de caminho protegido + verbo de escrita
const inlineCode: Handler = (c, st) => {
  if (c.head === 'perl' && hasShort(c.flags, /i/)) c.ops.forEach(t => writeTarget(t, st, 'perl -i'))
  const ci = c.args.findIndex(a => /^-[a-z]*[ce]$/.test(a.t) || a.t === '--eval' || a.t === '--print')
  const code = ci >= 0 ? c.args[ci + 1] : undefined
  if (!code) return
  if (codeTouchesProtected(code.t, st)) st.findings.push(deny('self_protect', 'codigo inline escreve em caminho protegido do Maestro: use o patch protegido'))
  else if (code.dyn && st.ctx.roots.length) st.findings.push(ask('dynamic_exec', 'codigo inline montado em tempo de execucao'))
}

const copyLike: Handler = (c, st) => {
  const ti = c.args.findIndex(a => a.t === '-t' || a.t.startsWith('--target-directory'))
  if (ti >= 0) {
    const tw = c.args[ti] as Word
    const dir: Word | undefined = tw.t.includes('=') ? { ...tw, t: tw.t.slice(tw.t.indexOf('=') + 1) } : c.args[ti + 1]
    if (dir) writeTarget(dir, st, c.head)
    return
  }
  const dest = c.ops[c.ops.length - 1]
  if (dest) writeTarget(dest, st, c.head)
  if (c.head === 'mv') c.ops.slice(0, -1).forEach(f => writeTarget(f, st, 'mv'))
}

const dd: Handler = (c, st) => {
  for (const a of c.args) if (a.t.startsWith('of=')) writeTarget({ ...a, t: a.t.slice(3) }, st, 'dd')
}

const truncate: Handler = (c, st) => {
  const sized = c.flags.some(f => f === '-s' || f.startsWith('--size') || (f.startsWith('-s') && f.length > 2))
  const before = st.findings.length
  for (const t of c.ops) if (!/^[0-9+-]/.test(t.t)) writeTarget(t, st, 'truncate')
  if (sized && st.findings.length === before) st.findings.push(ask('truncate_file', 'truncate zera ou corta arquivo'))
}

const chmodLike: Handler = (c, st) => {
  if (!(c.flags.includes('--recursive') || hasShort(c.flags, /R/))) return
  const worldWritable = c.head === 'chmod' && c.ops.some(o => /^(0?777|a\+rwx|a=rwx|ugo\+w|o\+w)$/.test(o.t))
  if (worldWritable || c.ops.slice(1).some(t => rmTarget(t, st) === 'deny')) {
    st.findings.push(deny('chmod_wide', `${c.head} -R de alvo largo ou permissao aberta a todos`))
  }
}

const dbClient: Handler = (_c, st) => {
  st.db = true
}

const redis: Handler = (c, st) => {
  if (/flush(all|db)/.test(c.args.map(a => a.t).join(' ').toLowerCase())) st.findings.push(deny('sql_destructive', 'redis FLUSH apaga todos os dados'))
}

const kube: Handler = (c, st) => {
  if (/^(delete|drain)\b/.test(c.ops.map(o => o.t).join(' '))) st.findings.push(ask('infra_destructive', 'apaga recursos do cluster'))
}

const container: Handler = (c, st) => {
  const joined = c.ops.map(o => o.t).join(' ')
  const downV = /\bdown\b/.test(joined) && (c.flags.includes('-v') || c.flags.includes('--volumes'))
  if (/system prune|volume (rm|prune)|^rm |^rmi |\bprune\b/.test(joined) || downV) {
    st.findings.push(ask('infra_destructive', 'apaga containers, imagens ou volumes'))
  }
}

const iac: Handler = (c, st) => {
  if (c.ops.some(o => o.t === 'destroy') || c.flags.includes('-auto-approve')) st.findings.push(ask('infra_destructive', 'destroi infraestrutura'))
}

const diskFormat: Handler = (_c, st) => {
  st.findings.push(deny('disk_format', 'formata ou reparticiona disco'))
}
const diskRisky: Handler = (_c, st) => {
  st.findings.push(ask('disk_format', 'operacao destrutiva de disco'))
}
const power: Handler = (_c, st) => {
  st.findings.push(ask('system_power', 'desliga ou reinicia a maquina'))
}
const git: Handler = (c, st) => gitCheck(c.args, st)
const net: Handler = (_c, st) => {
  st.curlSeen = true
}

const TABLE: Record<string, Handler> = {
  rm: rmHandler, rmdir: rmHandler, unlink: rmHandler,
  git, tee, sed, truncate, dd,
  perl: inlineCode, ruby: inlineCode, python: inlineCode, python3: inlineCode, node: inlineCode, bun: inlineCode, deno: inlineCode,
  cp: copyLike, install: copyLike, ln: copyLike, rsync: copyLike, mv: copyLike,
  chmod: chmodLike, chown: chmodLike, chgrp: chmodLike,
  'redis-cli': redis,
  mkfs: diskFormat, wipefs: diskFormat, fdisk: diskFormat, sfdisk: diskFormat, parted: diskFormat,
  shred: diskRisky, zpool: diskRisky,
  kubectl: kube, oc: kube,
  docker: container, podman: container,
  terraform: iac, tofu: iac, pulumi: iac,
  shutdown: power, reboot: power, halt: power, poweroff: power,
  curl: net, wget: net,
}
for (const db of DB_CLIENTS) TABLE[db] = dbClient

export function leafCommand(c: Cmd, st: State): void {
  secretReader(c, st)
  const h = TABLE[c.head]
  if (h) h(c, st)
  else if (c.head.startsWith('mkfs.')) diskFormat(c, st)
}
