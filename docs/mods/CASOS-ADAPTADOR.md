# maestro-guard — caso × adaptador (ordem 072, turno 1)

Os dois adaptadores: o hook bash (`hooks/pre-bash-guard.sh`, em modo autônomo) e o mod
(`mods/maestro-guard`, decisão pura em `hooks/policy.ts`). A fonte é o corpus
(`mods/maestro-guard/tests/corpus.ts`): cada caso que o hook bash cobre traz o veredito dele no campo `bash`.

## Contagens (só inteiros)

Corpus: 236 casos = 99 passam · 111 negam · 26 perguntam. Falso positivo 0 · falso negativo 0 (contra o esperado do corpus).

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
