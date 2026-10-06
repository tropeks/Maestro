# Fase 0, item 5 — bloco `permissions.deny`: o que foi testado (06/10/2026)

Bloco pronto: `docs/fase0/permissions-deny.json`. **Não foi aplicado** em `~/.claude/settings.json`: isso é do Capitão.

## Como foi testado

Sessões descartáveis do Claude Code `2.1.291`, modelo `claude-haiku-4-5-20251001`, num diretório de sandbox em
`/tmp` (arquivos e um repo git sem remote), com **as mesmas regras do bloco, trocando só o prefixo** (`//home/rcosta00/dev/Maestro`
→ `//tmp/…/denytest/Maestro`; `…/worktrees/maestro-*` → `//tmp/…/denytest/worktrees/maestro-*`). Cada sessão rodou
`claude -p` com `--permission-mode acceptEdits`, `--setting-sources local`, `--settings <só o bloco>`,
`--strict-mcp-config` com config vazia e `--disable-slash-commands`. O evento `init` de cada sessão confirma **zero MCP e só
os 3 plugins embutidos** (nem o Maestro): os resultados são das regras, não de hook.

**Desvio do pedido: a sessão NÃO usou `HOME` de sandbox.** O login do Claude Code é OAuth (`~/.claude/.credentials.json`).
Com `HOME` de sandbox a sessão não autentica; copiar a credencial para a sandbox arriscaria **rotacionar o refresh token
e deslogar a conta real**. O isolamento veio de `--setting-sources local` + `--settings` (o `settings.json` real não é lido
nem alterado) e de `cwd` dentro da sandbox.

A verdade vem de duas fontes: o `tool_result` de cada chamada e **o estado do disco depois** (arquivo criado ou não).

## Resultado (todos os casos casam com o disco)

| # | Operação | Esperado | Resultado |
|---|---|---|---|
| 1 | `Edit` em `Maestro/hooks/a.sh` | negado | **negado**, arquivo intacto |
| 2 | `Write` novo em `Maestro/hooks/new.sh` | negado se `Edit(...)` cobrir `Write` | **negado**, arquivo não criado |
| 3 | `Write` novo em `Maestro/lib/new.sh` | idem | **negado** |
| 4 | `Edit` em `Maestro/bin/a` | negado | **negado** |
| 5 | `Write` em `worktrees/maestro-049/hooks/new.sh` | negado se o glob `maestro-*` casar | **negado** |
| 6 | `Edit` em `worktrees/maestro-release-1.22.0/lib/a.sh` | negado (glob com pontos) | **negado** |
| 7 | `Write` em `home/.claude/plugins/new.json` | negado | **negado** |
| 8 | `Write` em `Maestro/docs/new.md` (controle) | passa | **passou**, arquivo criado |
| 9 | `Edit` em `worktrees/other-x/hooks/a.sh` (controle: nome fora do glob) | passa | **passou**, arquivo alterado |

**Respostas às duas perguntas do plano:**
1. **O glob `maestro-*` casa?** Sim, inclusive com ponto no nome (`maestro-release-1.22.0`).
2. **`Edit(...)` cobre `Write`?** Sim: o `Write` a caminho coberto por regra `Edit` foi negado. A sintaxe `//caminho/absoluto` funciona.
3. **`MultiEdit`:** a ferramenta **não existe** na versão instalada (a lista de ferramentas do `init` não a traz); não há o que cobrir.

## Bash: a regra do plano, como escrita, deixa passar variações — e o bloco foi corrigido

Com `Bash(git:*)` permitido (assim só o `deny` decide), as regras **do plano** negaram `git push --force`, `git push -f`,
`git push --delete` e `git reset --hard` **no início do comando**. Mas **não casaram** com:

- `git push origin main --force` e `git push origin main -f` (flag depois dos argumentos);
- `git -C . push --force origin main` (e `-f`, `--delete`, `reset --hard` com `-C`);
- `git push origin +main` (force por refspec);
- `git push origin --delete x` (flag depois do remoto);
- **`git push origin :x`** (o `Bash(git push origin :*)` do plano **nunca casa**: o `:*` final é o marcador de prefixo da sintaxe antiga).

O bloco em `permissions-deny.json` acrescenta curingas (`git push * --force`, `git push * -f`, `git push * --delete *`,
`git push * +*`, e as quatro formas com `git -C * …`). **Todos foram testados e negam.** `git push --force-with-lease`
**continua permitido** (como o guard do Maestro faz) e `git push origin main` e `git status` também.

## Limites declarados (não resolvidos pelo bloco)

- **`git push origin :x`** (apagar branch remoto por refspec vazio): **nenhum padrão testado o nega.** O `deny` por prefixo
  não cobre. Hoje quem cobre é o guard do Maestro; sem ele, fica descoberto.
- Regra de prefixo **não** vê o que está dentro de `bash -c '…'`, `eval`, scripts gravados antes ou variáveis montando o comando.
- **Worktrees chamados `maestro-*` ficam sem edição de `hooks/ lib/ bin/ src/` pela ferramenta Edit/Write**, inclusive o do próprio
  trabalho de patch (`maestro-fase0`, `maestro-0NN`). É o efeito desejado (patch humano); o fluxo atual (clone sandbox fora de
  `maestro-*`, patch em `docs/patches/`) segue funcionando.
- O bloco cobre `Edit`/`Write`. **Edição por shell** (`sed -i`, redirecionamento, `python -c`) é do Bash, não do `Edit(...)`:
  continua sendo só do guard do Maestro (ordem 047) até haver outra trava.
