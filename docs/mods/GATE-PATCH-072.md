# Gate do patch protegido 072 (revisão de segurança, P2-3)

O patch `docs/patches/072-guard-remocao-e-mods-self-paths.patch` **remove o registro do `pre-bash-guard` no `hooks/hooks.json`**. Aplicado antes de
o mod estar armado, a máquina fica **sem** guarda de destrutivos e de autoproteção. Por isso o patch **só se aplica** depois que o mod estiver armado.

estado: 903-CONFIRMADO

O patch troca a linha acima de `903-CONFIRMADO` para `PATCH-072-APLICADO`. Com qualquer outro valor, `git apply` (e a ação `aplicar_patch_maestro`
do daemon, que é um `git apply`) **recusa**: a linha faz parte do contexto exigido pelo patch.

Como a linha vira `903-CONFIRMADO`: o Capitão aplica os settings gerenciados (patch `903`, etapas A e B) e roda, no checkout:

    tools/verificar-mod-armado.sh --gravar --vi-tier-prepend

O script confere a máquina (settings gerenciados, diretório de root, `claude plugin list`) e só então grava `903-CONFIRMADO` e a data abaixo.
`--vi-tier-prepend` é a atestação do Capitão de que viu, em `claude --debug`, a linha `hooks module maestro-guard@maestro-managed loaded` com `tier prepend`.

Limite honesto: a trava vale contra o erro e a pressa, não contra quem decide contorná-la. O arquivo é texto em `docs/` e quem tem o checkout o edita à mão.
Mesmo uso do mod: tripwire, não fronteira, até o cutover para o usuário sem sudo (`docs/mods/INSTALACAO.md`).

confirmado-em: 2026-10-07T19:07:30-03:00
