// Base do corpus da ordem 072: o tipo do caso, o contexto de teste e os
// construtores B (Bash) e F (ferramenta de arquivo). So dado, sem logica.

export type Want = 'deny' | 'ask' | 'pass'

export type Case = {
  tool: string
  input: Record<string, unknown>
  want: Want
  // veredito do hook bash para o mesmo comando; ausente = o hook bash nao cobre
  bash?: 'block' | 'pass'
  // cwd da sessao; padrao: o worktree da ordem
  cwd?: string
}

export const WT = '/home/rcosta00/dev/worktrees/maestro-072'
export const CK = '/home/rcosta00/dev/Maestro'
export const HOME = '/home/rcosta00'
export const CTX = { cwd: WT, roots: [WT, CK], home: HOME }

export const B = (command: string, want: Want, bash?: 'block' | 'pass', cwd?: string): Case => ({
  tool: 'Bash',
  input: { command },
  want,
  ...(bash ? { bash } : {}),
  ...(cwd ? { cwd } : {}),
})
export const F = (tool: string, key: string, path: string, want: Want, cwd?: string): Case => ({
  tool,
  input: { [key]: path },
  want,
  ...(cwd ? { cwd } : {}),
})
