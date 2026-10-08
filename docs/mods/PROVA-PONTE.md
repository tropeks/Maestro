# Prova da Ponte sobre mods (ordem 076)

Prova de conceito medida: o gerente pede permissão e o Diretor responde por `$.session.send` / `session.receive`, sem `herdr pane run`. **Não muda o ponte-daemon de produção.** Estado: **turno 1 de 4** — só o verificador de peer e o impostor existem; o mod `maestro-prova` e as sessões vivas ainda não.

## Desenho: a identidade vem de fora da mensagem

A documentação do Claude Code 2.1.293 diz que o nome do remetente é o que o remetente escreveu. Por isso nada na mensagem decide quem fala. O verificador (`tools/prova-ponte-mods/peer-verifier`, socket unix próprio, nunca `~/.ponte/mcp.sock`):

1. pega o PID do peer por `SO_PEERCRED` (do kernel, não do cliente) e recusa uid diferente;
2. sobe `/proc/<pid>/stat` até o processo `claude`; cadeia quebrada (processo reparentado ao init) → `desconhecido`;
3. mapeia o PID do `claude` a um papel por `<map-dir>/<pid>`, gravado **pelo aparelho que lança as sessões**, nunca pela sessão.

Operações: `registrar-pedido` (só `gerente`), `verificar-pedido` e `registrar-decisao` (só `diretor`), `verificar-decisao` (só `gerente`). O `rid` tem 128 bits (32 hex), é de uso único e vence em 10 s (`--ttl-ms`). A decisão só vale para o `rid` cujo pedido o Diretor verificou. O `hash` é o sha256 da entrada da ferramenta, nunca o comando. O verificador não decide: só atesta quem registrou. O log guarda `rid` truncado, papel, op, veredito; nunca hash, comando nem caminho.

### Assinatura × parentesco

Escolhido: **parentesco**. Gerente e Diretor rodam com o mesmo usuário; uma chave assinadora é legível por qualquer processo dele (inclusive o Bash do agente). Sem custódia fora do alcance do agente, a assinatura autentica a mensagem, não o remetente. Se alguém propuser assinatura, a chave mora no verificador, nunca com o remetente.

## Ask-First: contrato de eventos (2.1.293, lido de `claude-code.d.ts` da build)

- **(a) `e.origin` em `session.receive`:** `{ kind }` com `bridge | task-notification | scheduled-trigger | peer-send-message | projects-relay | slack-ping | unclassified`; ou `{ kind: 'peer' | 'coordinator', plugin? }`; ou, via mailbox de time, `{ kind, plugin?, teammate, isVerified }`. `plugin` é **"AS THE SENDER SAYS"**: "nunca key a guard on it". Confirma o desenho: o nome não é identidade. Além de `origin`: `text`, `event?`, `agentId?`.
- **(b) `to` em `$.session.send`:** aceita `string` (nome, id de agente ou endereço `from` recebido), `{ sessionId }` (sessão do mesmo usuário nesta máquina, ou id remoto) ou `{ agentId }` (subagente/teammate da sessão). Sessão que não está rodando: `{ isDelivered: false, reason }`. `isDelivered: true` = enfileirada, não lida.
- **(c) acorda sessão ociosa? `claude -p` com entrada contínua?** **Não respondido por tipos.** Os tipos dizem só que entregue = enfileirado e que "o turno do receptor é dele". Depende de medir com sessões vivas (turno seguinte). Se `session.receive` não disparar na ociosa, o critério de acordar **falha, nomeado**, sem reintroduzir `herdr`.
- **(d) recusar mensagens de entrada:** **Não encontrado nos tipos** (nenhuma opção de configuração nomeada). Verificar com a sessão viva e a documentação de settings; relatar.

## Resultado do turno 1 (verificador + impostor, sem sessão do Claude Code)

`bash tests/cli/test-prova-ponte-verificador.sh`: 100 trocas válidas seguidas, intercaladas com 313 tentativas de impostor em 16 formas, **0 aceitas em todas**; o verificador aceitou exatamente 400 operações (4 por troca) e recusou exatamente as tentativas feitas. Formas: nome falso de gerente, nome falso de Diretor, `rid` copiado, pedido por peer errado, auto-aprovação (gerente decidindo), hash trocado, `claude` sem mapa, replay, veredito trocado, decisão para `rid` alheio, papel errado, texto malformado, gigante, processo reparentado, `rid` vencido. O aparelho de teste usa um `claude` falso (`claude-falso`, comm `claude`) como pai do cliente, com o papel gravado no mapa pelo lançador. O vencimento usa um verificador à parte com TTL de 800 ms (o padrão é 10 s).

## Limite que não se disfarça

Mesmo usuário e mod sem sandbox: quem controla o processo do `claude` do Diretor (`ptrace`, injeção) ou escreve em `<map-dir>` forja tudo. Isto é **tripwire e reconciliação** (como ST26), não fronteira, até o cutover para usuário sem `sudo`. O `comm` do `claude` real precisa ser conferido no lançador (`--comm`); o mapa por PID tem a janela de reuso de PID, que o lançador cobre removendo a entrada ao fim da sessão.
