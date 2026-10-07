# Instalação dos mods gerenciados (`maestro-guard`)

Ordem 072. O Capitão roda este passo a passo; a fábrica (agente, gerente headless) **não** roda o instalador nem toca os settings gerenciados.

## O que é "da organização"

Um mod só conta como da organização quando duas coisas valem juntas:

1. os arquivos estão em um diretório **de root** (`/opt/maestro/claude-plugins`, dono `root:root`, 755/644, nenhum pai gravável por não-root);
2. os **settings gerenciados** registram esse diretório como marketplace e habilitam o plugin (patch `903`, ramo `mods/managed-settings`, fora da ordem 072).

Só o item 1 sem o 2 deixa os arquivos no lugar, mas nada os carrega. Só o 2 sem o 1 aponta para um diretório que o usuário da sessão reescreve.

## Comando único (passos 2 e 3 juntos)

```
tools/armar-mods.sh --so-diff     # só mostra o diff; sem root, não escreve nada
sudo tools/armar-mods.sh          # mostra o diff, pergunta "Aplicar? [s/N]", aplica
sudo tools/armar-mods.sh --desfazer   # volta ao arquivo gerenciado anterior
```

Rode do checkout da `main` depois do merge (o que o instalador copia é o `mods/` de onde o script está). O comando:

1. confere o Claude Code instalado: versão >= 2.1.287, as seis chaves (`allowManagedModsOnly`, `prependPlugins`, `cc-plugin-sec-default`, `extraKnownMarketplaces`, `enabledPlugins`, `pluginConfigs`) presentes **no executável**, e `claude plugin validate mods/maestro-guard`; qualquer falha recusa antes de escrever;
2. mostra o **diff** do `/etc/claude-code/managed-settings.json` (o arquivo atual é preservado: só as chaves abaixo são somadas) e o destino dos mods, e **pergunta**;
3. instala `mods/` em `/opt/maestro/claude-plugins` pelo `tools/install-managed-mods.sh` (root:root, recusa pai gravável por não-root);
4. faz **backup** do arquivo gerenciado anterior (`managed-settings.json.bak-<data>`) e grava o novo: `pluginConfigs["cc-plugin-sec-default@builtin"].options.allowManagedModsOnly = true` (aninhado), o marketplace `maestro-managed` em `/opt/maestro/claude-plugins`, `enabledPlugins["maestro-guard@maestro-managed"] = true` e `prependPlugins` com o `maestro-guard` **primeiro** e o `sec-default@builtin` na lista (etapas A e B do 903 juntas; o patch 903 fica dispensado);
5. roda `tools/verificar-mod-armado.sh` e imprime o que falta.

`--desfazer` restaura o backup (ou remove o arquivo, se não existia) e remove `/opt/maestro/claude-plugins` se foi criado pelo arme. Depois de armar ou desfazer, **reinicie as panes**. Armar fecha todos os mods de usuário, inclusive `--plugin-dir` (as provas da ordem 076 deixam de rodar assim). `disableSideloadFlags` **não** é escrito: quebraria `--agents` e `--mcp-config`. Teste, com raiz falsa e `claude` falso: `tests/cli/test-armar-mods.sh`.

## Passo a passo (o que o comando único faz, em partes)

1. Confira o que será recusado, sem criar nada:

   ```
   tools/install-managed-mods.sh --check
   ```

   Sai 0 se `/opt/maestro/claude-plugins` e todo pai existente são de root e não graváveis por grupo ou outros. Sai 2, com o diretório culpado, se não.

2. Instale (o Capitão, com `sudo`):

   ```
   sudo tools/install-managed-mods.sh
   ```

   O script copia `mods/` por inteiro para uma pasta de preparo ao lado do destino, entrega a `root:root`, aplica 755 nas pastas e 644 nos arquivos, e troca o destino de uma vez (o anterior sai junto). Sem `node_modules`.

3. Registre o marketplace e habilite o plugin nos **settings gerenciados** (patch `903`). O marketplace é o diretório instalado (nome `maestro-managed`, plugin `maestro-guard` por caminho relativo). Confira os nomes das chaves contra a versão do Claude Code instalada antes de escrever o patch.

4. Abra sessão nova. `claude plugin list` mostra `maestro-guard@maestro-managed`; o log `~/.maestro/logs/guard-mod.jsonl` ganha uma linha por veredito. Confirme em `claude --debug` a linha `hooks module maestro-guard@maestro-managed loaded` com `tier prepend`.

5. **Só agora o patch 072 pode ser aplicado** (ver a seção abaixo): confirme que o mod está armado e grave o gate.

6. Para atualizar o mod: repita o passo 2 depois de cada merge que mexa em `mods/`.

## O patch 072 só se aplica com o mod armado (revisão de segurança, P2-3)

O patch protegido `docs/patches/072-guard-remocao-e-mods-self-paths.patch` **tira o registro do `pre-bash-guard` do `hooks/hooks.json`**. Se for aplicado antes de o mod estar armado, a máquina fica sem guarda de destrutivos e de autoproteção. A dependência é **imposta pelo próprio patch**, não só por esta nota:

- o patch tem um trecho em `docs/mods/GATE-PATCH-072.md` que exige a linha `estado: 903-CONFIRMADO` como contexto. Com `903-PENDENTE`, `git apply --check` **recusa** (e a ação `aplicar_patch_maestro` do daemon, que é um `git apply`, também);
- a linha só vira `903-CONFIRMADO` por `tools/verificar-mod-armado.sh --gravar --vi-tier-prepend`, que confere: settings gerenciados de root com `allowManagedModsOnly` **na chave aninhada** `pluginConfigs["cc-plugin-sec-default@builtin"].options`, `maestro-guard@maestro-managed` habilitado e **primeiro** em `prependPlugins` (com `sec-default@builtin` na lista), o marketplace instalado em diretório de root e `claude plugin list` mostrando o plugin habilitado. A flag `--vi-tier-prepend` é a atestação de que você viu `tier prepend` no `claude --debug`;
- depois de gravar, commite o gate; o patch 072 passa a aplicar e troca a linha para `PATCH-072-APLICADO` (não reaplica).

O patch 903 **da etapa A** (`allowManagedModsOnly` sozinho) **não arma o mod**: sem a etapa B (marketplace de root, `enabledPlugins` e `prependPlugins`), nada carrega. É a etapa B que o verificador exige. Teste: `tests/cli/test-order-072-gate-patch.sh`. Limite honesto: o gate é um arquivo de texto no repo; vale contra erro e pressa, não contra quem decide contorná-lo.

## Recusas do instalador

| Situação | Resposta |
| --- | --- |
| destino ou pai com dono que não é root | recusa (exit 2), nomeia o diretório |
| destino ou pai com modo gravável por grupo ou outros (`/tmp`, `1777`) | recusa |
| destino relativo, `/` ou de primeiro nível (`/opt`) | recusa |
| sem root e sem `--check` | recusa, pede `sudo` |
| `mods/` sem `marketplace.json` ou `plugin.json` | recusa |

`tests/cli/test-order-072-install-managed-mods.sh` cobre as recusas. A cópia em si, que exige root, **não** é testada pela suíte.

## Kill-switch

`MAESTRO_OFF=1` no **ambiente do processo do Claude Code** desliga o mod: ele lê a variável uma vez no load, por `$.env.get`, e registra uma linha `rule=kill-switch` (só metadados) no log. O `Bash` do agente não altera o ambiente do processo pai; **mas o Claude Code também lê `env` dos arquivos de settings**, e então o agente poderia gravar `"env": {"MAESTRO_OFF": "1"}` num settings e armar o kill-switch na sessão seguinte. Por isso (revisão de segurança, P2-2) `.claude/` e `.github/workflows/` entraram na autoproteção do mod: a escrita ali é `deny`, no checkout e em todo worktree. Os settings do **usuário** (`~/.claude/settings.json`, `settings.local.json` e qualquer `~/.claude/settings*.json`) também são cobertos (item d, decisão do Spock de 07/10): o mod **nega a escrita** por `Edit`, `Write`, `MultiEdit`, `NotebookEdit` ou shell (`>`, `tee`, `sed -i`, `cp`, `mv`, `rm`, `dd of=`…), **inclusive em sessão interativa** e fora de qualquer raiz do Maestro (`rule=settings_self_write`). A **leitura fica livre**: só o Capitão edita esses arquivos, e à mão. Limite que segue valendo: caminho montado por variável que o mod não resolve (`$X/settings.json`) e `bash script.sh` passam. Quem exporta a variável antes de abrir o Claude Code consegue: é uma porta de propósito, a que o `CLAUDE.md` do projeto manda ter em todo hook. Se o Capitão preferir um mod sem essa porta, é remover uma linha em `hooks/register.ts`.

## Limite que não se enfeita: sem sudo na fábrica

Com `sudo` sem senha, o dono do processo desfaz o diretório de root (`sudo rm`, `sudo cp`, edição dos settings gerenciados). Enquanto a fábrica roda com um usuário que tem sudo sem senha, o mod é **tripwire, não fronteira**: ele pega o erro e o descuido, não um agente que decida contornar. A fronteira de verdade chega com o cutover para o usuário sem sudo; até lá, trate o veredito `deny` como alarme e o diretório de root como cerca baixa.

Outros limites da guarda, que valem mesmo depois do cutover: `docs/architecture/ENGINEERING_SPEC.md`, seção "Limites da guarda léxica do mod".

## Desinstalação

```
sudo rm -rf /opt/maestro/claude-plugins
```

e remover o registro dos settings gerenciados. Sem o registro, o Claude Code segue sem o mod; os hooks bash do plugin `maestro` continuam valendo (a ordem 072 não os remove).
