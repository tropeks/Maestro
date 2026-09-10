<!-- maestro-intent v1
version: 2
ts: 2026-09-10T12:33:49-03:00
head: ac91cacf8e91995f888226a7ffb33aa67dc5fe53
author_session: c63227f9-8cee-4c01-965f-10182f66b500
hash: b1b21050
-->
# Direção — Maestro

## Problema

- O roteador do ferramental é o humano: 4–5 fontes de skills concorrentes exigem invocação manual a cada tarefa, e o uso real é pelo telefone via RC, onde digitar comando é o maior atrito (PROJECT_BRIEF §1).
- O modelo principal tende a fazer tudo sozinho no contexto mais caro da sessão: um bugfix de uma linha consome o mesmo raciocínio premium que uma decisão de arquitetura (README "The problem"; ADR-004).
- Cada tarefa custava 1–2 intervenções de roteamento que deveriam ser automáticas — "faz via subagentes", lembrar do plano, lembrar de QA e review (PROJECT_BRIEF §1).
- Sessão nova re-varre o repo do zero: não havia estado situacional herdável entre sessões (README "Situational awareness"; EPICS E8).
- A direção do projeto vivia só na cabeça do Capitão, sem versão — um plano aprovado contra uma direção já mudada seguia como se nada tivesse mudado (EPICS E22).
- O sistema registrava a APOSTA (agentes declarados, ordem, recibo `exit=0`) e a tratava como execução: nenhum hook via o disparo real de um subagente, e `maestro evidence --record -- true` produzia recibo válido sem provar nada (ADR-010; EPICS E23).

## Público

- Persona primária única: Romulo — analista sênior de infra de TI, construtor solo de um portfólio SaaS multi-projeto; usuário, comprador e sponsor são a mesma pessoa (PROJECT_BRIEF §2).
- Acompanha sessões pelo telefone com RC ativado: os gates humanos (plano, ship) e o report ao Legatus existem para esse modo de uso (PROJECT_BRIEF §2; EPICS E21).
- Sem personas secundárias na v1; single-user "para sempre na v1", e multi-usuário é assunto de fase 2 (PROJECT_BRIEF §2; ADR-005; ADR-006).
- NÃO é para equipes, multi-tenant, nem para terceiros operando o roteamento (ADR-006).
- NÃO é para a IA decidir gate estrutural, injeção ou kill-switch — esses são do humano ou do hook determinístico; à IA cabe interpretar intenção → workflow/modo/modelo (PROJECT_BRIEF "AI Opportunity Map"; ADR-002).
- Adotante externo NÃO é público-alvo: o repo é público no GitHub sob MIT, e repo aberto não é compromisso de suporte a terceiro (decisão do Capitão, 2026-09-10).

## Resultado

- Override manual de roteamento cai de ~100% para <20%; comandos de skill digitados por sessão vão de vários para 0–1; zero correção manual do modo/modelo escolhido (PROJECT_BRIEF §9, meta de 3 meses).
- Medido de fato: retro de 14 dias com 113 decisões e 10% de override elegeu a promoção warn→block (CHANGELOG v1.3.0); 133 decisões e 13% confirmaram a promoção com E2E ao vivo em modo block (CHANGELOG v1.6.0).
- Acurácia de roteamento em eval cego: de 73% para 100% (15/15, dois juízes independentes) (README "The problem").
- Delegação deixa de ser palavra e vira funil observável — `maestro delegation` mostra `started` real, não apenas `--agents` declarado (EPICS E23/S-2301).
- `maestro verify --check` recusa quando falta recibo válido na área declarada (EPICS E23/S-2302).
- `stable` só se move com CI verde: nenhuma máquina recebe commit que a CI não provou (EPICS E23/S-2303).
- Toda ordem cita a versão do INTENT que a autorizou, e mudar a direção marca as ordens vivas para revisão de plano (EPICS E22).
- O descarte aparece: janela madura sem nenhum `killed` é sintoma, não virtude (EPICS E25/S-2501; CHANGELOG v1.15.0).
- Gatilho da Fase 2: ela abre quando o dogfood medir override <20% numa janela de 30 dias com ≥100 decisões. O gatilho é esse número, não uma data (decisão do Capitão, 2026-09-10; fecha a lacuna de PROJECT_BRIEF §9 × EPICS "Roadmap Fase 2").

## Prioridades

Ordem de desempate: em qualquer colisão, vence a prioridade mais alta desta lista.

1. Nunca bloquear trabalho por estar quebrado — falha de qualquer componente degrada para o fluxo manual; o gate é best-effort, não muralha (CLAUDE.md; ADR-003 emenda v1.1).
2. Custo proporcional à tarefa — delegar é a regra, direto é exceção, e cada tarefa desce ao modelo mais barato que dá conta (ADR-004; README "The problem").
3. Trilho onde o trilho alcança, honra declarada onde ele não alcança — nunca fingir mecânico o que é compliance assistido; toda válvula de escape fica escrita e visível (`--unproven`, `--intent-reviewed`, `no-stable`) (ADR-009; ADR-010; ADR-011).
4. Prova mecânica antes de declaração — decision record, funil de delegação, verificação por área e `stable` aprovada por CI substituem honra por checagem onde é viável (ADR-010; EPICS E23).
5. Contexto contido — a injeção do SessionStart tem orçamento com ratchet (≤ ~2k tokens) e não cresce sem cortar no mesmo commit; o preâmbulo é graduável por projeto (`preamble: full|standard|lean`) (ARCHITECTURE "NFRs"; EPICS E25/S-2502; CHANGELOG v1.15.2).
6. Aprender em lote, nunca em runtime — o Maestro não se autoajusta durante a sessão; calibração é telemetria → retro → diff proposto → exame → commit versionado (README "The learning loop").

## Limites

- Precedência da direção: o INTENT vence o ADR. ADR que contradiga a direção emenda o INTENT no MESMO changeset — direção e arquitetura nunca divergem em silêncio (decisão do Capitão, 2026-09-10).
- `hooks/` é bash puro: nunca invoca Bun, nunca importa `src/`; NFR <50ms por invocação (CLAUDE.md; ARCHITECTURE "NFRs").
- Kill-switch `MAESTRO_OFF=1` na primeira linha de todo hook (CLAUDE.md; ENGINEERING_SPEC "Regras canônicas").
- Logs só de metadados, vocabulário fechado: jamais prompt, jamais caminho completo de arquivo (CLAUDE.md; README "Hard boundaries").
- `agents/` é só markdown; `vendor/` é read-only, verificado contra manifesto sha256 a cada `doctor` (CLAUDE.md).
- Nenhum float em métrica de custo — só inteiros de tokens/centavos, validados pelo schema do decision record (CLAUDE.md; CHANGELOG v1.6.0).
- Nenhuma dependência de rede em runtime, exceto o fetch do auto-update (E19): timeout curto, uma vez por intervalo, falha silenciosa e registrada — silêncio nunca significa "atualizado" (CLAUDE.md; ADR-001 emenda E19).
- Telemetria cross-máquina é opt-in e viaja pelo git, como o E20 já a implementa: nunca liga sozinha, nunca carrega além de metadado. Ela emenda o "sem telemetria na v1" do PROJECT_BRIEF §4 (EPICS E20; decisão do Capitão, 2026-09-10).
- Memória em supermemory (cloud) fica ACEITA por escrito, contra o "tudo local" do PROJECT_BRIEF §7: o conflito é consciente e mora aqui, na direção, não escondido num ADR (ADR-007; decisão do Capitão, 2026-09-10).
- Distribuição é plugin local do Claude Code; marketplace e QM são fase 2, e só depois do gatilho (ADR-001; decisão do Capitão, 2026-09-10).
- Autoproteção do gate: mesmo com record válido, edições a `.claude/`, `.github/workflows/`, `hooks/`, `bin/`, `src/`, `agents/`, `config/routing-table.yaml` e `.claude-plugin/` seguem bloqueadas; `maestro consent` levanta a denylist só para DADOS (routing table, roster), nunca para a máquina (ADR-003 v1.2).
- Single-user na v1: sem auth própria, a superfície é a da máquina e da conta Claude (ADR-005).
- Sessões concorrentes na mesma máquina não corrompem a política uma da outra — cada sessão lê e escreve a sua, escopada (EPICS E26/S-2601; CHANGELOG v1.15.1).

## Fora de escopo

- Multi-usuário e QM — fase 2, e só depois do gatilho de override (<20% em 30 dias, ≥100 decisões) (PROJECT_BRIEF §4; ADR-006).
- Fork ou reescrita dos packs upstream (superpowers, gstack): vendorizados, customização só na camada Maestro (PROJECT_BRIEF §4; CLAUDE.md).
- Camada MCP dinâmica `activate(domínio, projeto)` — fase 2, módulo do orchestrator, atrás do mesmo gatilho (PROJECT_BRIEF §4).
- Task-observer embutido e auto-evolução de skills em runtime — o aprendizado é sempre em lote (PROJECT_BRIEF §4; README "The learning loop").
- Suporte a adotante externo: issue, compatibilidade e documentação de terceiro não são obrigação do projeto, mesmo com o repo público sob MIT (decisão do Capitão, 2026-09-10).
- Classificador de intenção dedicado em Haiku (latência + custo + infra) e roteamento por regex/keywords (é a rigidez que motivou o projeto) — ambos rejeitados (ADR-002).
- Bloquear edição direta incondicionalmente — rejeitado pelo usuário no G0 (ADR-003).
- Split de `bin/maestro` e `src/cli.ts` em núcleo + adaptadores (E24) — só depois de E23 provado em uso por ≥1 semana; refatorar antes é mover código sem evidência de fronteira (EPICS E24).
- Interceptar contatos de fim de sessão via hook Stop/SessionEnd — fora do v1 (EPICS E17).
- Importar código do fork pstack ou adotar seu ethos "ship the 80%" (EPICS E25).
- Trocar o Legatus atual pelo Legatus vNext — adiado até o vNext se provar em uso (EPICS E21).
- Os gerentes e o supervisor: vivem em repos próprios; o Maestro só garante suportar N sessões concorrentes sem se corromper (EPICS E26).
- Auditar o CONTEÚDO do INTENT: o CLI valida forma (seções, hash, versão), nunca julga o texto (EPICS E22).
