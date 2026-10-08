# Emendas propostas à Ponte de produção (ordem 076) — decisão do Diretor

> **Proposta, não aplicada.** A ordem 076 não toca o ponte-daemon, o `~/.ponte/mcp.sock`, o `ponte.db` nem as tools `director.*`. Estas linhas são o que a
> prova sugere; adotar ou não é do Diretor. Evidência e números em `docs/mods/PROVA-PONTE.md` ("Resultado do turno 5").

## O que a prova sustenta

- O gerente pode pedir e o Diretor pode responder por `$.session.send` / `session.receive`, **sem `herdr pane run`** e **sem turno de modelo** no Diretor:
  100 trocas seguidas, 100 corretas, mediana 405 ms, p95 549 ms, máximo 2045 ms, 0 chamadas ao `herdr` falso, 0 turnos de modelo.
- A identidade **não** vem da mensagem. O mesmo desenho do daemon (`SO_PEERCRED` → PID → ancestral `claude` → papel gravado por quem lança a sessão), em miniatura,
  recusou 200 de 200 tentativas vivas de impostor em 13 formas, e 313 de 313 no teste do verificador; as mutações de controle ficam vermelhas (mutante do verificador:
  4 aceitos; mutante do Diretor por `e.origin.plugin`: 2 aceitos).

## O que ela NÃO sustenta (limites medidos)

1. **Sessão interativa:** `session.receive` foi medido só numa `claude -p` ociosa com entrada contínua. Numa sessão **interativa** a entrega não foi medida (o gerente não a achou:
   `no live session on this machine has id …`). O Diretor de produção é interativo: **isto precisa de medição própria antes de qualquer cutover**.
2. **Vazão:** o `$.session.send` tem limite de taxa no receptor (rajada ~50, depois da ordem de 0,5 mensagem/s). Acima disso o envio é recusado e o gerente faz `deny`.
   Uma Ponte por mensagens entre sessões serve para pedidos esparsos; rajadas precisam de fila ou lote, ou voltam ao canal atual.
3. **Hook de 10 s:** o gerente espera no máximo 8 s; qualquer coisa além é `deny`. Um Diretor humano (ou modelo) responde em segundos a minutos: **este canal só serve para decisão por tabela**
   (função pura), como na prova. Decisão que precisa de pessoa continua no canal atual.
4. **Tripwire, não fronteira:** mesmo usuário, mod sem sandbox. Quem controla o processo do `claude` do Diretor (`ptrace`, injeção) forja tudo. Vale como tripwire e reconciliação (como ST26)
   até o cutover para usuário sem `sudo`.
5. **Inundação = negação de serviço (segura):** um impostor de mesmo usuário que inunda o receptor derruba trocas legítimas para `deny`. Não aceita decisão falsa, mas degrada.

## Proposta de emenda (se o Diretor decidir seguir)

1. Manter o canal atual de produção. Usar `session.send` apenas para **pedidos de classe A resolvidos por tabela** (leitura em pasta liberada), atrás de um interruptor, com `deny` em qualquer queda.
2. Reaproveitar o verificador por `SO_PEERCRED` do daemon: nada de identidade na mensagem; **amarrar `rid`, `hash` e `classe`** (a prova achou a `classe` solta e a corrigiu).
3. Medir a entrega numa sessão interativa antes de qualquer decisão (item 1 acima): é a lacuna aberta desta ordem.
4. Não promover o mod de prova a `mods/`: só por patch protegido, decisão futura.
