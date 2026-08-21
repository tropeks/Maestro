**too-many-params** — parâmetros demais significam que a função conhece detalhes
demais de quem a chama. Agrupe o que viaja junto num objeto/struct com nome de
domínio, ou divida a função. Não faça: esconder tudo num dict/kwargs genérico —
isso remove o aviso e piora o contrato.
