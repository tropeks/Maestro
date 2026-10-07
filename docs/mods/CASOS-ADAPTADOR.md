# maestro-guard — caso × adaptador (ordem 072, turno 1)

Os dois adaptadores: o hook bash (`hooks/pre-bash-guard.sh`, em modo autônomo) e o mod
(`mods/maestro-guard`, decisão pura em `hooks/policy.ts`). A fonte é o corpus
(`mods/maestro-guard/tests/corpus.ts`): cada caso que o hook bash cobre traz o veredito dele no campo `bash`.

## Contagens (só inteiros)

Corpus (após a revisão de segurança de 07/10): 327 casos = 129 passam · 172 negam · 26 perguntam. Falso positivo 0 · falso negativo 0 (contra o esperado do corpus).
Item d (settings do usuário): 22 formas de escrita e 13 de leitura/vizinhos em `tests/settings-home.test.ts`, nos três modos (headless, sem flag, interativo), fora do corpus acima.
Antes da correção, os 24 casos novos de P2-1 (segredo por `<`) e P2-2 (`.claude/`, `.github/workflows/`) davam falso negativo 24; depois, 0
(`tests/corpus-revisao.ts`).
Os 59 casos novos do turno 2 são de segredo (`Read`, `Grep`, `Glob`, `cat`, `cp`); a tabela abaixo é a do turno 1 e **não mudou**: o hook bash
não cobre segredo. Decisão (b) do Diretor de 07/10: os 12 casos `block → ask` foram aceitos como estão. Decisão (a): os vereditos `deny` desta
tabela valem em **headless**; em sessão interativa os destrutivos viram `ask` (`tests/interativo.test.ts`).

| hook bash | mod | casos |
| --- | --- | --- |
| block | deny | 43 |
| block | ask | 12 |
| pass | pass | 37 |
| pass | deny | 1 |
| block | pass | 0 |

Nenhum caso que o hook bash bloqueia passa no mod. Os 13 que divergem:

| comando | bash | mod | por quê |
| --- | --- | --- | --- |
| `git push --force-with-lease origin main` | pass | deny | a ordem: lease só passa fora da main |
| `rm -rf ../../outro-projeto` | block | ask | fora do repo, não é diretório de sistema nem home: ambíguo |
| `git push -f` | block | ask | sem alvo explícito, pode ser branch de trabalho |
| `git checkout .` / `git restore .` | block | ask | descarta alterações; pergunta |
| `truncate -s 0 /var/log/app.log` | block | ask | fora de caminho protegido: ambíguo |
| `sudo apt-get install -y nginx` | block | ask | operação de infra |
| `kubectl delete pod …` | block | ask | operação de infra |
| `docker system prune -a` | block | ask | operação de infra |
| `terraform destroy -auto-approve` | block | ask | operação de infra |
| `curl … \| sh` / `wget … \| sudo bash` | block | ask | baixa e executa |
| `shutdown -h now` | block | ask | pode ser container descartável |

O hook bash só bloqueia em fluxo autônomo (decision record `subagent`/`multi`); o mod não vê o
decision record e julga sempre: a negativa vale também no modo direto.
