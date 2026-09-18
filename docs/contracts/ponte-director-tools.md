# O que o daemon da Ponte precisa expor para o gerente perguntar

Pedido do Maestro ao `ponte-daemon`. Escrito em 2026-09-17, durante a ordem 020
do Maestro (`gerente pergunta por MCP`). Destinatário: quem mantém
`ponte-daemon-003`.

## O problema, em uma frase

O lado Maestro está pronto, mas hoje a chamada falharia com **"tool
desconhecida"**: `director.ask` e `director.wait` **não estão registrados no
servidor MCP stdio**, que é o único caminho pelo qual o Claude Code enxerga
ferramentas.

## Onde está a lacuna (achado, não suposição)

`src/mcp/stdioBridge.ts`, na lista `TOOL_REGISTRATIONS` — a que o servidor MCP
stdio realmente publica ao Claude Code. Ela contém hoje:

```
captain.ask · captain.inform · gates.list · gates.resolve   (+ os demais ponte.*)
```

E **nenhum `director.*`**.

O resto da cadeia existe e está certo:

| camada | estado |
|---|---|
| domínio — `src/domain/directorAsk.ts` | existe |
| services — `src/services/mcp/DirectorAsk.ts`, `DirectorWait.ts` | existem |
| fiação — `handlers["director.ask"]`, `["director.wait"]` em `main.ts` | existe |
| **publicação MCP — `TOOL_REGISTRATIONS`** | **ausente** |

A story S-233 da ordem 006 de vocês ("fiação + catraca nos `mcpHandlers`")
cobriu a fiação interna; a publicação no bridge stdio ficou de fora.

## O que precisa ser exposto

Nada de novo em comportamento — só publicar o que já existe. O contrato abaixo é
o que a ordem 006 de vocês já especifica (S-229/S-230 e o "Critério de saída"),
transcrito para conferência:

### `director.ask`

| item | valor |
|---|---|
| parâmetros | o estado corrente do gerente e a pergunta |
| retorno | `{ decision_id, status: "open" }`, **na hora** — não bloqueia |
| autorização | pane de **gerente** basta (`requireManagerPane` no `AuthorizeMcpPeer`) |
| efeito | cria decisão `kind: question`, que **não entra** na amostra do GATE do Diretor |

### `director.wait`

| item | valor |
|---|---|
| parâmetros | `id` (o `decision_id` do `ask`) e `max_s` — o teto de 5 min é **parâmetro**, não fixo |
| retorno com resposta | a `note` do Diretor, texto livre, ≤ 2000 |
| retorno sem resposta | **"continua aberta"** — retorno NORMAL, nunca erro |
| persistência | a decisão **sobrevive a restart do daemon**; `wait` volta a funcionar depois dele |
| expiração | sem resposta aos **30 min** a decisão vira `expirada` e o Diretor é avisado |
| autorização | idêntica ao `ask` |

### Identificação do chamador

Por **SO_PEERCRED + cadeia `/proc`** (`src/adapters/peercred/adapter.ts`), do
lado do daemon. Isto é importante para nós: **o hook do Maestro é bash puro e não
inventa identidade** — quem identifica é o daemon, pelo peer do socket. Pane que
não é de gerente tem de ser **recusada**.

### Concorrência

O pareamento é por `decision_id`, então duas perguntas do mesmo gerente são duas
decisões distintas. O lado Maestro **não depende de estado implícito de pane** —
guarde essa propriedade, ela é o que permite mais de um gerente perguntando na
mesma máquina (há 9 sessões aqui hoje).

## Como o Maestro chama

- Servidor declarado em `.mcp.json` na raiz do plugin, com
  `command: "ponte-daemon"`, `args: ["mcp"]` — **nome nu resolvido por PATH**, de
  propósito: não assumimos nenhuma estrutura de instalação.
- Socket por `env.PONTE_MCP_SOCKET`, default `${HOME}/.ponte/mcp.sock`.
- Binário ou socket ausente → o servidor não sobe e **a sessão do gerente segue
  normal**. Essa degradação é a Prioridade 1 da nossa direção e não é
  negociável: nada na Ponte pode impedir uma sessão do Maestro de terminar.

## O que NÃO estamos pedindo

- Nenhuma capacidade de o gerente **mandar** — só perguntar e esperar. Está
  vedado por texto expresso na nossa direção (INTENT v3).
- `gates.resolve` continua exclusivo do Diretor. Não queremos acesso.
- Nenhuma mudança no que o GATE do Diretor mede.
