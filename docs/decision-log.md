# Decision log

## 2026-08-08 — Sessão E1 (vibe-code via chat)
- Story: S-101, S-102, S-103
- Implementado: estrutura de plugin (plugin.json, hooks.json, marketplace.json), common.sh (kill-switch, log_event com vocabulário fechado + sanitização + flock -n), 3 hooks como stubs seguros (degradam com exit 0), CLI bash com doctor completo, routing-table.yaml inicial, testes (killswitch, log-vocab) + run-all.
- Decisões: doctor em bash (Bun só entra no E2, checado como warn); sanitização de valores de log por whitelist de caracteres (defesa contra injeção de JSONL, review Opus achado 9); stubs dos hooks E2 já registrados no hooks.json para o wiring ser testado desde já.
- Descartado: implementar decide/status/log adiantado — guarda de escopo do EPICS.
- Flags: nenhum.

## 2026-08-09 — Review Opus do E1 + Sessão E1.1/E2 (vibe-code via subagentes)

**Review** (`docs/OPUS_E1_REVIEW.md`): 2 P0, 5 P1, 13 P2. Núcleo do E1 correto
(kill-switch, degradação, sanitização, fronteiras); os P0 eram ferramental de
suporte — repo sem git e doctor com falso-verde.

**Execução:** 6 subagentes em 2 ondas, com contrato compartilhado escrito antes e
propriedade estrita de arquivo (nenhum conflito de escrita). Onda 1: common.sh,
CLI. Onda 2: session-start, gate, doctor, user-prompt-submit. Integração,
verificação independente e commits pelo orquestrador.

- **Stories:** S-201, S-202, S-203, S-204, S-205 (E2 completo) + P0-1, P0-2,
  P1-1..P1-5, P2-1, P2-2, P2-6, P2-7, P2-8 da review.

### Decisões

1. **`bin/maestro` continua em bash e delega `decide|status|log` para
   `bun src/cli.ts`.** O ENGINEERING_SPEC prevê o CLI inteiro em Bun/TS, mas o
   doctor precisa diagnosticar ambiente quebrado — inclusive Bun ausente. Um
   doctor que não roda sem Bun é inútil justamente quando é necessário.
2. **`Bun.YAML.parse` em vez de dependência de YAML.** Bun 1.3.14 traz parser
   nativo; mantém a regra "zero dependências além do stdlib do Bun".
3. **Denylist do gate em duas classes** (`paths` universais x `self_paths`
   ancorados no plugin root). Uma lista só forçava escolher entre deixar
   `.claude/settings.json` aberto ou bloquear o `src/` de todo projeto. Descoberto
   na integração, não no projeto — o teste de cenário duplo é que expôs.
4. **A autoproteção cobre o caminho de enforcement, não a árvore do repo.**
   Proteger tudo sob o plugin root fechava README e docs do próprio Maestro,
   inviabilizando dogfood. Consequência aceita: agente não edita `hooks/`, `bin/`,
   `src/`, `agents/` nem a routing table no repo do Maestro — quem faz é o humano
   (ou `MAESTRO_OFF=1` para uma sessão deliberada de meta-trabalho).
5. **`custom` adicionado à routing table.** Estava no enum do API_SPEC §2 mas não
   no YAML, e o CLI valida contra o YAML. Sem ele, o roteador seria forçado a
   rotular errado uma tarefa fora do catálogo — envenenando a métrica de baseline.
6. **Chaves do log tipadas, par inválido rejeitado em vez de sanitizado.** A
   sanitização por whitelist de caracteres (decisão do E1) corrompia dado em
   silêncio. Emenda v1.2 no DATA_MODEL §4: `cmd` no lugar do `note` de texto livre.
7. **`flock -n` ganhou retentativa limitada** (~50ms de teto) em vez de descartar
   na primeira contenção: 20 writers simultâneos perdiam 40% das linhas, e o log
   é o instrumento de medição do projeto. `MAESTRO_LOCK_TRIES=0` volta à letra do
   DATA_MODEL.
8. **Testes em bash puro, não bats.** O ENGINEERING_SPEC pede bats; bats não está
   instalado e a dependência não se paga no E1/E2. Os testes seguem o padrão do
   `test-killswitch.sh` (exit code + saída + efeito em disco) e fazem mutation
   testing onde importa (doctor, common.sh).

### Bugs achados na integração (não estavam na review)

- **`exec 9>&-` sem grupo** em `common.sh`: `exec` sem comando aplica a redireção
  ao shell inteiro, então o stderr do hook chamador virava `/dev/null` após o
  primeiro `log_event` — a mensagem instrutiva do gate no exit 2 desaparecia.
- **`capture` sem delimitador final** no S-205: nome de comando com 49+ chars era
  truncado e um pedaço do prompt ia para o log.
- **Política parcial desarmava a autoproteção**: sem `MAESTRO_PLUGIN_ROOT` na
  policy, `self_paths` não tinha onde ancorar. O gate passou a derivar a raiz da
  própria localização.

### Descartado

- Validar "hooks registrados no `settings.json` do Claude Code" (API_SPEC §2): o
  registro aqui é por auto-descoberta do `hooks/hooks.json` do plugin, e o
  settings do usuário vive fora do repo, sem como isolar em teste. A AC da S-103
  fica coberta pelo lado do plugin.
- `hooks/log-stop.sh` (evento Stop, "opcional v1.1" no API_SPEC) — `session_end`
  segue sem emissor.

### Flags para o próximo épico

- **E3 destrava validação de agente:** `maestro decide` avisa que o roster está
  vazio e não valida `--agents`. Popular `agents/*.md` liga a validação sozinho.
- **Promoção warn→block** (Fase 1b) é uma linha no YAML; o gate já honra os dois.
- **Latência do gate**: 35ms de mínimo contra NFR de 50ms, mas a mediana sob carga
  passa de 50ms. Se apertar, o alvo é o fork de `jq` do `maestro_record_valid`.
- **`.maestro.yaml`** já é lido e filtra o roster — metade da S-303 pronta.
