// Auxiliares de argumentos de comando.
import type { Word } from './shell-lex'

export const flagsOf = (args: Word[]): string[] => args.filter(a => a.t.startsWith('-') && a.t !== '-').map(a => a.t)
export const operands = (args: Word[]): Word[] => args.filter(a => !a.t.startsWith('-') || a.t === '-')
// flag curta combinada (-rf, -fdx): alguma letra do conjunto, fora das longas (--x)
export const hasShort = (flags: string[], re: RegExp): boolean =>
  flags.some(f => f.startsWith('-') && !f.startsWith('--') && re.test(f.slice(1)))
