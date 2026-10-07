// Tipos e construtores compartilhados da politica da guarda.
import type { Word } from './shell-lex'

export type Verdict = 'deny' | 'ask' | 'pass'
export type Decision = { verdict: Verdict; rule: string; reason: string }
// roots: raizes do repo Maestro em que a sessao esta (checkout e/ou worktree);
// vazio = a sessao nao e do Maestro e a autoprotecao fica inativa.
export type Ctx = { cwd: string; roots: readonly string[]; home: string }

export const PASS: Decision = { verdict: 'pass', rule: 'none', reason: '' }
export const deny = (rule: string, reason: string): Decision => ({ verdict: 'deny', rule, reason })
export const ask = (rule: string, reason: string): Decision => ({ verdict: 'ask', rule, reason })

export const rank = (d: Decision): number => (d.verdict === 'deny' ? 2 : d.verdict === 'ask' ? 1 : 0)

// O estado de uma analise de Bash: cwd corrente (null = desconhecido), os
// achados e o que o comando inteiro mostrou (cliente de banco, curl/wget).
export type State = {
  ctx: Ctx
  cwd: string | null
  projectRoot: string
  findings: Decision[]
  db: boolean
  sql: string[]
  curlSeen: boolean
  raw: string
}

// Um comando ja sem os envelopes (sudo, env, timeout, xargs...).
export type Cmd = {
  head: string
  args: Word[]
  flags: string[]
  ops: Word[]
  xargs: boolean
}
