**type-escape** — `as any` / `as unknown as` desliga o type checker exatamente
onde você mais precisa dele. O erro de tipo está apontando um contrato mal
declarado: modele o tipo certo (union, generic, type guard). Cada `any` é uma
promessa de runtime error futuro.
