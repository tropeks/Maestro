# Instalação dos mods gerenciados (`maestro-guard`)

Ordem 072. O Capitão roda este passo a passo; a fábrica (agente, gerente headless) **não** roda o instalador nem toca os settings gerenciados.

## O que é "da organização"

Um mod só conta como da organização quando duas coisas valem juntas:

1. os arquivos estão em um diretório **de root** (`/opt/maestro/claude-plugins`, dono `root:root`, 755/644, nenhum pai gravável por não-root);
2. os **settings gerenciados** registram esse diretório como marketplace e habilitam o plugin (patch `903`, ramo `mods/managed-settings`, fora da ordem 072).

Só o item 1 sem o 2 deixa os arquivos no lugar, mas nada os carrega. Só o 2 sem o 1 aponta para um diretório que o usuário da sessão reescreve.

## Passo a passo

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

4. Abra sessão nova. `claude plugin list` mostra `maestro-guard@maestro-managed`; o log `~/.maestro/logs/guard-mod.jsonl` ganha uma linha por veredito.

5. Para atualizar o mod: repita o passo 2 depois de cada merge que mexa em `mods/`.

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

`MAESTRO_OFF=1` no **ambiente do processo do Claude Code** desliga o mod: ele lê a variável uma vez no load, por `$.env.get`, e registra uma linha `rule=kill-switch` (só metadados) no log. O `Bash` do agente não altera o ambiente do processo pai, então o agente não consegue ligar o kill-switch por conta própria. Quem exporta a variável antes de abrir o Claude Code consegue: é uma porta de propósito, a que o `CLAUDE.md` do projeto manda ter em todo hook. Se o Capitão preferir um mod sem essa porta, é remover uma linha em `hooks/register.ts`.

## Limite que não se enfeita: sem sudo na fábrica

Com `sudo` sem senha, o dono do processo desfaz o diretório de root (`sudo rm`, `sudo cp`, edição dos settings gerenciados). Enquanto a fábrica roda com um usuário que tem sudo sem senha, o mod é **tripwire, não fronteira**: ele pega o erro e o descuido, não um agente que decida contornar. A fronteira de verdade chega com o cutover para o usuário sem sudo; até lá, trate o veredito `deny` como alarme e o diretório de root como cerca baixa.

Outros limites da guarda, que valem mesmo depois do cutover: `docs/architecture/ENGINEERING_SPEC.md`, seção "Limites da guarda léxica do mod".

## Desinstalação

```
sudo rm -rf /opt/maestro/claude-plugins
```

e remover o registro dos settings gerenciados. Sem o registro, o Claude Code segue sem o mod; os hooks bash do plugin `maestro` continuam valendo (a ordem 072 não os remove).
