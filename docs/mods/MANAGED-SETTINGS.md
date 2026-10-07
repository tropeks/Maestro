# Settings gerenciados dos mods (decisão do Capitão, 07/10)

Fonte: `~/dev/spock/docs/pesquisa-claude-code-nativo-vs-metodo-2026-10-07.md` e a documentação oficial dos mods
(`plugins/mods/admin`), consultada em 07/10 contra o Claude Code **2.1.293**. Este branch **não** é uma ordem: entrega o arquivo e o passo a passo
para o Capitão aplicar.

## Etapa A — fechar os mods (patch `903`)

`docs/patches/903-managed-settings-mods-gerenciados.patch` cria **`/etc/claude-code/managed-settings.json`**:

```json
{
  "pluginConfigs": {
    "cc-plugin-sec-default@builtin": {
      "options": { "allowManagedModsOnly": true }
    }
  }
}
```

**A chave não é de topo.** A pesquisa de 07/10 escreve `allowManagedModsOnly: true` solto; a documentação a põe em
`pluginConfigs["cc-plugin-sec-default@builtin"].options`, e o guard **só lê esse caminho** (e só de settings gerenciados).

Efeito (documentação): nenhum mod "de usuário" carrega: nem de plugin instalado, nem de `--plugin-dir`, nem **escrito pelo Claude na sessão**.
Hooks de settings, status line e `/goal` seguem funcionando. Mods embutidos (`cc-plugin-*`) seguem. Ao existir um arquivo gerenciado na máquina, o
guard embutido `sec-default` **passa a carregar** em toda sessão.

### Aplicar (Capitão, é arquivo de root; o `git apply` do daemon **não serve**, o alvo é fora do repo)

1. `patch --dry-run -p1 -d / -i docs/patches/903-managed-settings-mods-gerenciados.patch` (já foi rodado: `checking file etc/claude-code/managed-settings.json`)
2. `sudo patch -p1 -d / -i docs/patches/903-managed-settings-mods-gerenciados.patch`
3. `sudo chown root:root /etc/claude-code /etc/claude-code/managed-settings.json` e `sudo chmod 755 /etc/claude-code` e `sudo chmod 644 /etc/claude-code/managed-settings.json`
4. Reiniciar as panes (settings gerenciados são lidos na partida).

sha256 do patch: `ae7450a51ad6c2704678ca9cb5c57be6ca1c900a2dd4a160504aff784b818ba1`

### Verificar (documentação, "confirm the option")

Num diretório vazio, com um mod qualquer (`first-mod/` com `plugin.json`, `hooks/hooks.json` e `hooks/register.js`):

`claude --plugin-dir ./first-mod --debug`

Esperado: os hooks do mod **não rodam** e o log traz a linha
`refused by cc-plugin-sec-default: mods are limited to your organization's by policy (allowManagedModsOnly)`. Se o mod carregar, a opção **não** está em vigor:
confira a chave aninhada e o dono do arquivo.

### Reverter

`sudo rm /etc/claude-code/managed-settings.json` e reiniciar as panes. (Se o diretório estava vazio antes, `sudo rmdir /etc/claude-code`.)

### O que NÃO está na etapa A, de propósito

- **`disableSideloadFlags`** fica de fora: ele rejeita `--plugin-dir`, `--plugin-url`, **`--agents` e `--mcp-config`**, e o lançador de agentes
  (ordem 066) e os runs headless usam `--agents`/`--mcp-config`. Ligá-lo pararia a fábrica inteira. `allowManagedModsOnly` já fecha `--plugin-dir` e o mod
  escrito pela sessão; `disableSideloadFlags` só se justifica se a fábrica deixar de usar essas flags.
- **`deny` de Edit nos caminhos protegidos** fica de fora (a pesquisa os lista como "deny mínimos"): é política que muda o comportamento de **toda**
  sessão do Capitão e pede decisão própria. Fica como fragmento opcional na etapa C abaixo.
- **`allowManagedHooksOnly` e `disableAllHooks`** ficam de fora: derrubariam os hooks bash do Maestro e o `PreToolUse` de usuário.

## Etapa B — instalar a guarda como mod da organização (só depois da ordem da guarda aceita)

Um mod só conta como "da organização" com **todas** as condições: `enabledPlugins` gerenciado = `true`; marketplace declarado por **caminho absoluto de
diretório**; plugin listado por **caminho relativo** (carregado "no lugar"); e o diretório e seus pais **graváveis só por root**. Um plugin que o Claude
Code copia para o cache (GitHub, git, URL, npm) conta como de usuário e **não carrega** sob a etapa A.

Arquivo da etapa B (`docs/mods/managed-settings.etapa-b.json`), no lugar do da etapa A; os plugins `maestro-reads` e `maestro-hold` entram na lista quando as
ordens 073 e 074 forem aceitas. **A ordem da lista é a ordem da cadeia: a guarda vem primeiro**, o que ela nega os outros nunca liberam.

Antes: `sudo tools/install-managed-mods.sh` (entregue pela ordem 072) copia `mods/` para `/opt/maestro/claude-plugins` com dono `root:root`.

## Limite que não se disfarça

O agente roda com o usuário que tem **`sudo` sem senha** (em 07/10, `sudo -n true` saiu sem erro nem pedido de senha). Com isso, quem controla o processo pode editar
`/etc/claude-code` e `/opt/maestro/claude-plugins`. Os settings gerenciados e o mod são **tripwire, não fronteira**, até o cutover dos agentes para um
usuário sem `sudo` (pré-requisito de tudo que se chama segurança aqui, pesquisa de 07/10, Riscos 1).

## Etapa C — opcional, decisão separada

Fragmento para somar ao arquivo, **não incluído no patch**: `permissions.deny` com `Edit(//home/rcosta00/dev/Maestro/{hooks,bin,src,lib,agents,.claude-plugin}/**)`
e o equivalente `Edit(//home/rcosta00/dev/worktrees/*/…)`. Bloqueia também as sessões do Capitão nesses caminhos; patches seguem por clone sandbox.
