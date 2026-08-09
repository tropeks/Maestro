# vendor/wshobson-agents — upstream pinado

Referência **read-only, não instalada** (ENGINEERING_SPEC §Layout). Os arquivos aqui são cópias
**byte-idênticas** do upstream. A adaptação curada vive em `agents/`, com header `# upstream:`
no frontmatter (ADR-004: "prompts upstream adaptados carregam atribuição de licença no cabeçalho").

| Campo | Valor |
|---|---|
| Repositório | `wshobson/agents` — https://github.com/wshobson/agents |
| Commit pinado | `c4b82b0ad771190355eb8e204b1329732a18449a` |
| Data do commit | 2026-07-18 |
| Data da vendorização | 2026-08-09 |
| Licença | MIT — Copyright (c) 2024 Seth Hobson (ver `LICENSE`) |
| Story | S-302 (E3 — Roster v1) |

## Procedência de cada arquivo

| Arquivo aqui | Caminho de origem no upstream | Adaptado em | sha256 |
|---|---|---|---|
| `golang-pro.md` | `plugins/systems-programming/agents/golang-pro.md` | `agents/golang-pro.md` | `8e4dc761fb38caab96a1d898596ffee3b55fbf369b36ed9729290f48f13d8cf8` |
| `python-pro.md` | `plugins/python-development/agents/python-pro.md` | `agents/python-pro.md` | `5c764591a3d06efac4495c30f80f1d37f460d7d833498eeed8441cf6a1f32f50` |
| `typescript-pro.md` | `plugins/javascript-typescript/agents/typescript-pro.md` | `agents/typescript-pro.md` | `d7dd97fbc3fed73c8feb63ca5071b561660d150d94ecb2c1fa009c7cfba2d404` |
| `sql-pro.md` | `plugins/database-design/agents/sql-pro.md` | `agents/postgres-pro.md` | `6eb2fdb139b7971ae98b604ad7d22f6710f904ca74cf00e8961dbe81159513d7` |
| `LICENSE` | `LICENSE` | — | `f89abb55d9f073f38f1703e4518f0613c788c6174be7f13b8dfe48a1c076c746` |

Notas de adaptação:

- **`sql-pro` → `postgres-pro`**: o upstream não publica um `postgres-pro`. O portfólio é PostgreSQL
  (PROJECT_BRIEF §3.2), então o adaptado foi especializado em Postgres, não em SQL genérico —
  Snowflake/BigQuery/Redshift/Neo4j/HTAP e afins do original foram cortados.
- **Modelo**: `golang-pro`, `python-pro` e `typescript-pro` vêm com `model: opus`; `sql-pro` vem com
  `model: inherit`. Todos os adaptados são `model: sonnet` (tiering de custo, ADR-004 / brief §3.2).
- **Enxugamento**: os originais somam 22.489 bytes / 517 linhas de capacidades genéricas. Os
  adaptados cortam para o que serve ao portfólio e ao fluxo do Maestro — prompt grande é custo em
  toda invocação, e a NFR de injeção é ≤ ~2k tokens.
- Os demais ~200 agentes do upstream **não** foram vendorizados nem instalados (ADR-004 rejeitou
  explicitamente: "polui o gate — o problema que o Maestro resolve").

## Como atualizar o pin

1. `git clone https://github.com/wshobson/agents && git checkout <novo-commit>`
2. Recopiar os 4 arquivos + `LICENSE` **intocados** para cá; atualizar commit, data e sha256 acima.
3. Reavaliar `agents/*.md` manualmente (diff do upstream) — a adaptação nunca é regenerada automaticamente.
4. `bash tests/hooks/test-especialistas.sh`.
