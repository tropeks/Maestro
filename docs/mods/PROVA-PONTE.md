# Prova da Ponte sobre mods (ordem 076)

Prova de conceito medida: o gerente pede permissão e o Diretor responde por `$.session.send` / `session.receive`, sem `herdr pane run`. **Não muda o ponte-daemon de produção.** Estado: **turno 5 de 5** — verificador, mod, impostor e as 100 trocas em sessão viva existem e passaram; **(c) numa sessão interativa e (d) para a interativa não foram medidos** (ver "Resultado do turno 5").

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
- **(c) acorda sessão ociosa? `claude -p` com entrada contínua?** Os tipos não respondem (entregue = enfileirado; "o turno do receptor é dele"). **Medido no turno 5:** ver abaixo. `claude -p` com entrada contínua: **sim**; interativa: **não medida**.
- **(d) recusar mensagens de entrada:** nenhuma opção nos tipos. **Medido no turno 5:** na `claude -p` ociosa a mensagem entrou **sem desligar configuração nenhuma** (o run não toca settings). Para a interativa: não medido.

## Resultado do turno 1 (verificador + impostor, sem sessão do Claude Code)

`bash tests/cli/test-prova-ponte-verificador.sh`: 100 trocas válidas seguidas, intercaladas com 313 tentativas de impostor em 16 formas, **0 aceitas em todas**; o verificador aceitou exatamente 400 operações (4 por troca) e recusou exatamente as tentativas feitas. Formas: nome falso de gerente, nome falso de Diretor, `rid` copiado, pedido por peer errado, auto-aprovação (gerente decidindo), hash trocado, `claude` sem mapa, replay, veredito trocado, decisão para `rid` alheio, papel errado, texto malformado, gigante, processo reparentado, `rid` vencido. O aparelho de teste usa um `claude` falso (`claude-falso`, comm `claude`) como pai do cliente, com o papel gravado no mapa pelo lançador. O vencimento usa um verificador à parte com TTL de 800 ms (o padrão é 10 s).

## Resultado do turno 3 (mod `maestro-prova`, mutante do Diretor, sessão viva)

- **Mod** em `tools/prova-ponte-mods/maestro-prova/` (nunca em `mods/`): papéis `diretor` e `gerente` por `PROVA_PAPEL` (lido por `$.env.get` na primeira necessidade após o load, pois `register` não recebe `$`). Gerente: `tool.check` devolve a base e, se for `ask`, registra o pedido no verificador, envia por `$.session.send` e espera no máximo 8 s; qualquer queda (`throw`, timeout, resposta inválida, entrega falha) é `deny`. Diretor: `session.receive` verifica o pedido **no verificador**, decide pela função pura (`leitura-liberada` → `allow`, o resto → `deny`, tabela v1), registra a decisão e responde por `$.session.send`; mensagem sem pedido válido vira `{ consumed }`. O endereço da resposta vem de `PROVA_PAR` (ambiente do aparelho), nunca da mensagem.
- **Vermelho antes:** `claude plugin test` sem o mod falhou com `no hooks module to load; there is no hooks/hooks.json naming one in "modules"` (rc 1). **Verde depois:** 16 testes, 0 falhas. `claude plugin validate`: sai 0; `hooks: tool.check, session.receive`; `calls: $.clock.now, $.clock.sleep, $.env.get, $.fs.write, $.process.run, $.session.send` (sem `http.fetch`).
- **Mutação do Diretor** (`bash tests/cli/test-prova-ponte-mutacao-diretor.sh`): o mutante, derivado do mod real por `tools/prova-ponte-mods/mutar-diretor`, decide por `e.origin.plugin` (o nome que o remetente escreve). O mesmo teste do impostor: **mutante → VERMELHO, 2 impostores aceitos; Diretor real → VERDE, 0**.
- **(c) e (d) em sessão viva: FALHA NOMEADA.** Ambiente: política `allowManagedModsOnly` **armada** (`maestro-guard@maestro-managed`). Com `--plugin-dir`, o log de debug de cada sessão (Diretor e gerente) traz: `plugin.register: maestro-prova (user, maestro-prova@inline), judged by cc-plugin-sec-default: refused by cc-plugin-sec-default: mods are limited to your organization's by policy (allowManagedModsOnly); maestro-prova was not loaded`. Nada foi contornado (sem settings gerenciados, sem `--safe-mode`, sem instalar em diretório de root). `session.receive` numa sessão ociosa **não foi medido**; (d) idem. O aparelho `tools/prova-ponte-mods/medir-acordar` reproduz e imprime essa linha. Observação: `claude plugin test` carrega o mod (o kit não passa pelo `plugin.register` da política), então as tabelas acima valem para a lógica, não para a sessão viva.

## Resultado do turno 5 (sessão viva, política `allowManagedModsOnly` desarmada pelo Capitão)

**Ambiente:** `--plugin-dir`, política desarmada pelo Capitão fora do run (o run não tocou settings, nem `--safe-mode`). O log de cada sessão traz `hooks module maestro-prova@inline loaded` e `plugin.register: … admitted` (sem a recusa do turno 3). Modelo das sessões de teste: haiku. Cada sessão é lançada pelo aparelho; o mapa de papéis é gravado por ele; o verificador reconheceu o `claude` real (`claude=1` em todas as linhas do log: o `comm` do processo real é `claude`).

**As 100 trocas** (`tools/prova-ponte-mods/rodar.sh`, rc 0, `PASS`): `trocas=100 corretas=100 falhas=0 timeouts=0 primeira_falha=0`; **mediana 405 ms, p95 549 ms, máximo 2045 ms** (inteiros, do início do pedido à decisão aplicada, medidos por `$.clock.now()` no gerente). Elas passam pelo comando `/prova-ponte` do mod (**sem turno de modelo**), em lotes de 4 com pausa de 1500 ms entre trocas (a pausa fica fora do ms medido). Mais **5 trocas pelo caminho real** (o modelo executa 5 `Read`; o `tool.check` cai em `ask` e vira pedido): 5 de 5, `allow`. Os dois números: 100 pelo comando, 5 pelo modelo.

**Impostor vivo** (durante as 100, nos dois sentidos; o atacante forte: lê `rid`/`hash`/`classe` do pedido real num arquivo do olheiro): 200 tentativas, 13 formas, **0 aceitas**.

| forma | tentativas | aceitas |
|---|---:|---:|
| decisao_oposta_rid_copiado | 12 | 0 |
| decisao_replay | 12 | 0 |
| decisao_rid_aleatorio | 12 | 0 |
| envelope_falso_aninhado | 24 | 0 |
| gigante | 22 | 0 |
| malformado | 24 | 0 |
| pedido_classe_trocada | 12 | 0 |
| pedido_hash_trocado | 12 | 0 |
| pedido_replay | 12 | 0 |
| pedido_rid_aleatorio | 12 | 0 |
| sem_rid | 11 | 0 |
| tipo_trocado | 24 | 0 |
| vazio | 11 | 0 |

"Aceita" = efeito de impostor: decisão aplicada com veredito errado (0), Diretor atendendo mais vezes que os pedidos reais (100 atendidos para 100 pedidos), gerente aplicando mais decisões que trocas decididas (100 para 100). A atestação é do total, não por forma (se fosse > 0, a tabela mostraria `-1`). Os pedidos forjados chegam ao hook e são recusados pelos motivos certos (`replay`, `classe_trocada`, `hash_trocado`, `rid_desconhecido`, `malformado`). O verificador ainda recusou 84 operações.

**Acordar sem `herdr`:** `herdr` falso no PATH: **0 chamadas**. Turnos de modelo no Diretor durante as trocas: **0** (contados pelas saídas `assistant` da sessão), nos dois pares. O `session.receive` do Diretor ocioso responde em ~10 ms.

**(c) medido.** `session.receive` **dispara numa `claude -p` ociosa com entrada contínua** (stream-json) e a mensagem não gera turno de modelo (o hook responde sem `next()`). **Numa sessão interativa: NÃO MEDIDO.** O Diretor interativo, numa pty (`pty-diretor`), carregou o mod e ficou vivo, mas o gerente não o achou: `$.session.send: not sent: no live session on this machine has id <uuid>`. A sessão `-p` de teste aparece no registro de sessões vivas (`~/.claude/sessions/<pid>.json`); a interativa lançada pelo aparelho **não** apareceu, e a causa não foi isolada (o turno terminou por ordem do Diretor). O diálogo de confiança na pasta tem "No, exit" como padrão e aceitá-lo gravaria estado do usuário: por isso o Diretor interativo rodou no próprio worktree e o aparelho não responde a diálogo algum.

**(d) medido para a `claude -p`:** nenhuma configuração de "recusar mensagens de entrada" foi preciso desligar. Para a interativa: não medido.

**Achados que mudam a Ponte de produção** (medidos no turno 5):

1. **O corpo chega embrulhado.** O `e.text` do receptor é `<cross-session-message from="uds:…" from-name="…" from-mode="…">\n<corpo>\n</cross-session-message>`; os atributos são do remetente. O mod desembrulha por regex estrita e só confia no corpo; a identidade segue vindo do verificador. `e.origin` chega como `{ kind: 'peer', plugin: 'maestro-prova' }` (o nome que o remetente escreveu).
2. **O `$.session.send` tem limite de taxa.** `Too many messages to this session just now: N were sent recently and more would be dropped by its rate limit`: o envio é recusado (`isDelivered: false`), o gerente faz `deny` (fail-closed, nunca `allow`). Rajada em torno de 50 mensagens e depois uma vazão de ordem de 0,5 mensagem por segundo (lido do log de debug, não de uma sondagem dedicada). A 1 troca por ~1 s o limite foi atingido na troca 50 (31 de 100 falhas, todas `deny`); com pausa de 1,5 s entre trocas, 0 recusas. **Consequência: uma Ponte por `session.send` não sustenta mais que ~0,5 pedido por segundo por par de sessões**; o resto vira `deny` (seguro, mas lento) ou precisa de fila/lote.
3. **O hook de `command.run` vale 10 s** (como os demais): 100 trocas num só comando falharam fechado aos 13,8 s (`hook failed closed`). Por isso o comando faz lotes (≤ 12, e `N × (pausa + 700 ms) ≤ 9500`).
4. **A `classe` não estava amarrada ao pedido.** O desenho do turno 3 amarrava só o `hash`; quem copiasse `rid` + `hash` podia trocar a `classe` e mudar a decisão. Corrigido: o verificador registra a `classe` e o Diretor tem de repeti-la (`classe_trocada`). Também achado e corrigido: `.env` dentro do JSON não casava com o padrão de segredo (`env"`), então ler `.env` virava `leitura-liberada`.
5. **Um impostor que inunda é negação de serviço, não falsificação.** A inundação (~700 mensagens/min) esgotou o limite do receptor e derrubou trocas legítimas para `deny`; nenhuma decisão falsa foi aceita. Segue a regra da casa: queda → `deny`.

**Harness.** Quatro rodadas vivas do `rodar.sh` até a final: 1) comando de 100 trocas estourou o hook de 10 s; 2) o fifo herdado segurava o EOF do gerente e o impostor inundou o receptor; 3) ritmo ainda acima do limite do `session.send`; 4) a que passou. Cada falha foi do aparelho ou do limite medido, nunca uma decisão falsa aceita.

## Limite que não se disfarça

Mesmo usuário e mod sem sandbox: quem controla o processo do `claude` do Diretor (`ptrace`, injeção) ou escreve em `<map-dir>` forja tudo. Isto é **tripwire e reconciliação** (como ST26), não fronteira, até o cutover para usuário sem `sudo`. O `comm` do `claude` real foi conferido em sessão viva (o verificador achou o ancestral `claude` em todas as chamadas, `claude=1`); o mapa por PID tem a janela de reuso de PID, que o lançador cobre removendo a entrada ao fim da sessão. A mensagem forjada que chega pelo socket de mensagens da sessão é indistinguível, na camada do Claude Code, de uma legítima: só o verificador, fora da mensagem, separa uma da outra. **A prova mostra que o caminho funciona e se defende contra impostor de mesmo usuário que não controla o processo do `claude`; ela não é uma fronteira.**
