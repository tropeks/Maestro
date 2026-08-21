**risky-shortcut** — atalho idiomático que vira bug: default mutável em Python
compartilha estado entre chamadas; `.unwrap()` fora de teste é panic em produção
com input real. Use `None` + inicialização interna; propague `Result`/`Option`
com `?` ou trate o caso. O atalho economiza uma linha e cobra uma madrugada.
