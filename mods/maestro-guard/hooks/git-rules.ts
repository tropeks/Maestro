// git: so os subcomandos que perdem trabalho ou reescrevem historia compartilhada.
import type { Word } from './shell-lex'
import { resolvePath } from './paths'
import { ask, deny, type State } from './types'
import { flagsOf, hasShort, operands } from './args'

const MAIN = new Set(['main', 'master', 'trunk', 'refs/heads/main', 'refs/heads/master'])

// Pula as opcoes globais (-C dir, -c k=v...) e devolve o subcomando e onde ele esta.
function subcommand(args: Word[], st: State): { sub: string; rest: Word[]; gcwd: string | null } {
  let j = 0
  let gcwd = st.cwd
  while (j < args.length) {
    const a = args[j]?.t ?? ''
    if (a === '-C') {
      const d = args[j + 1]
      gcwd = d && !d.dyn ? resolvePath(d.t, gcwd, st.ctx.home) : null
      j += 2
    } else if (a === '-c' || a === '--git-dir' || a === '--work-tree' || a === '--namespace') j += 2
    else if (a.startsWith('-')) j++
    else break
  }
  return { sub: args[j]?.t ?? '', rest: args.slice(j + 1), gcwd }
}

function pushCheck(rest: Word[], st: State): void {
  const flags = flagsOf(rest)
  const refs = operands(rest).slice(1).map(w => w.t)
  const dsts = refs.map(r => {
    const x = r.replace(/^\+/, '')
    return x.includes(':') ? x.slice(x.lastIndexOf(':') + 1) : x
  })
  if (flags.includes('--mirror')) {
    st.findings.push(deny('force_push_main', 'push --mirror sobrescreve todas as refs do remoto'))
    return
  }
  const plain = flags.includes('--force') || hasShort(flags, /f/) || refs.some(r => r.startsWith('+'))
  const lease = flags.some(f => f.startsWith('--force-with-lease') || f === '--force-if-includes')
  if ((plain || lease) && dsts.some(d => MAIN.has(d))) {
    st.findings.push(deny('force_push_main', 'force push na main reescreve a historia compartilhada'))
  } else if (plain) {
    st.findings.push(ask('force_push', 'force push reescreve a historia do remoto'))
  }
}

function cleanCheck(flags: string[], st: State): void {
  const dry = flags.includes('--dry-run') || hasShort(flags, /n/)
  const force = flags.includes('--force') || hasShort(flags, /f/)
  if (dry || !force) return
  if (hasShort(flags, /x/)) st.findings.push(deny('git_clean', 'clean -x apaga ate o que o .gitignore protege'))
  else st.findings.push(ask('git_clean', 'clean -f apaga arquivos nao rastreados'))
}

function resetCheck(flags: string[], gcwd: string | null, st: State): void {
  if (!flags.includes('--hard')) return
  if (gcwd === null) st.findings.push(ask('reset_hard', 'reset --hard em diretorio nao resolvivel'))
  else if (!/(^|\/)worktrees\//.test(gcwd)) st.findings.push(deny('reset_hard', 'reset --hard fora de worktree descartavel perde trabalho'))
}

export function gitCheck(args: Word[], st: State): void {
  const { sub, rest, gcwd } = subcommand(args, st)
  const flags = flagsOf(rest)
  if (sub === 'push') pushCheck(rest, st)
  else if (sub === 'reset') resetCheck(flags, gcwd, st)
  else if (sub === 'clean') cleanCheck(flags, st)
  else if ((sub === 'checkout' || sub === 'restore') && operands(rest).some(w => w.t === '.')) {
    st.findings.push(ask('discard_changes', 'descarta todas as alteracoes do diretorio'))
  } else if (sub === 'filter-branch') st.findings.push(ask('force_push', 'filter-branch reescreve a historia'))
}
