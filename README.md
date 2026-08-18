# Maestro

**A MoE routing layer for Claude Code** — deterministic hooks, a declarative routing
table, and a roster of cost-tiered agents.

[![CI](https://github.com/tropeks/Maestro/actions/workflows/ci.yml/badge.svg)](https://github.com/tropeks/Maestro/actions/workflows/ci.yml)
![pure-bash hooks](https://img.shields.io/badge/hooks-pure%20bash-4EAA25?logo=gnubash&logoColor=white)
![CLI in Bun](https://img.shields.io/badge/CLI-Bun-black?logo=bun)
![MIT license](https://img.shields.io/badge/license-MIT-blue)

*Leia em [português](README.pt-BR.md). Internal docs (`docs/`) are in pt-BR.*

> **Philosophy:** deterministic rails, AI at the edges. Hooks guarantee **THAT** a
> routing decision happens; the session's Claude decides **WHAT** to do, guided by
> the table. No LLM on the critical path, no network at runtime, no component that
> blocks work when it fails.

## The problem

In a long Claude Code session, the main model tends to do everything itself — in the
most expensive context in the house. A mechanical one-line bugfix costs the same
premium reasoning as an architecture decision. Maestro inverts the default:
**delegating is the rule, working directly is the exception**, and each task drops to
the cheapest model that can handle it. Measured in a blind eval, this inversion took
routing accuracy from 73% to 100% (15/15, two independent judges).

## How it works

```mermaid
flowchart LR
    subgraph hooks["hooks (pure bash, &lt;50ms)"]
        SS[SessionStart] -->|injects| INJ["routing table + roster<br/>+ gates + heuristics"]
        PT[PreToolUse] -->|Edit/Write| GATE{decision<br/>record?}
        PB[PreToolUse] -->|Bash| GUARD["destructive-command guard<br/>(rm -rf, force push, DROP)"]
    end
    subgraph cli["CLI (Bun)"]
        DEC["maestro decide"] --> REC[("decision record<br/>4h TTL")]
        DOC["maestro doctor"] --> ENV[("capabilities.json<br/>+ drift snapshots")]
    end
    GATE -.->|no record: warn| REC
    INJ -->|"the session's Claude<br/>picks workflow + agent"| DEC
```

1. **SessionStart** injects a `<maestro-routing>` block (~6KB, budget enforced by a
   tested ratchet): intent → workflow routes, step → executor bindings, delegation
   heuristics, human gates, and the roster filtered by the project's `.maestro.yaml`.
2. The session's Claude records its decision before editing code:

   ```bash
   maestro decide --session <id> --workflow fix --mode subagent \
                  --agents golang-pro --reason "bug in 1 Go module"
   ```

3. **PreToolUse** checks: editing code without a valid decision record raises a
   warning on every edit (`gate.mode: warn` is the default; promotion to `block` is
   one line of config, made with dogfood data — not on faith).
4. `maestro log --summary` closes the loop: manual-override rate, model distribution
   per task — the instrument that tells you whether routing is actually working.

## Roster — the model proportional to the role

| agent | model | when |
|---|---|---|
| `dev-junior` | haiku | mechanical task with closed scope and objective criteria |
| `dev-pleno` | sonnet | feature/bugfix that requires judgment |
| `engenheiro` | sonnet | architecture and planning — delivers trade-offs, not code |
| `revisor` | sonnet | **read-only** review — no Write, Edit, or Bash |
| `qa` | sonnet | functional testing and evidence — never implements the fix |
| `golang-pro` · `python-pro` · `typescript-pro` · `postgres-pro` | sonnet | the target's language beats the seniority profile |

The four specialists are adapted from [wshobson/agents](https://github.com/wshobson/agents)
(MIT), with the originals pinned by commit under `vendor/` — which is read-only and
verified against a `sha256` manifest on every `doctor` run.

A `.maestro.yaml` at the project root narrows the active roster:

```yaml
version: 1
project: remedix
languages: [go]
experts: [golang-pro]   # only this one shows up in the injection
```

## Workflows and gates

| intent (examples) | workflow | steps | human gate |
|---|---|---|---|
| "it broke, fix it" | `fix` | investigate → implement → review | — |
| "add, implement" | `feature` | plan → implement → review → qa | plan |
| "clean up, reorganize" | `refactor` | plan → implement → review | plan |
| "deploy, publish" | `ship` | ship | ship |
| "security, audit" | `audit` | audit | — |
| "test, validate" | `verify` | qa | — |
| "review the PR" | `codereview` | review | — |

Every step has a declared **binding** (`skill:` · `agent:` · `native:`) in
`config/routing-table.yaml` — a versioned schema with **eval-on-diff**: a route
mutation fails CI naming the case whose verdict changed, before → after.

Human gates follow risk, not bureaucracy: they stop **only** the near-irreversible
(real production, billing, auth/secrets, destructive migrations, force push). In
private development with the change verified by tests, commit, branch push, and PR
flow without asking — with the decision on record.

## Install

```bash
git clone https://github.com/tropeks/Maestro ~/dev/Maestro
claude   # inside Claude Code:
# /plugin marketplace add ~/dev/Maestro
# /plugin install maestro@maestro
```

Runtime dependencies: `bash`, `jq`, `flock` (hooks) and [Bun](https://bun.sh) (CLI).
The hooks never invoke Bun — if Bun disappears, the CLI degrades with a message
citing the last `doctor` run; the rails stay up.

## Validate

```bash
bin/maestro doctor        # 30 checks; --ci for pipelines
bash tests/run-all.sh     # full suite: 1020 assertions, hermetic
```

The `doctor` doesn't trust — it measures: it runs the injection hook for real and
counts the bytes; compares resolved bindings against the previous run's snapshot
(`binding-resolution-drift`); verifies `vendor/` against the pinned manifest; and
compares the installed plugin copy with the repo **by content, byte for byte** —
because an identical version number once hid six commits of difference. Everything
it establishes becomes integer facts in an envelope (`capabilities.json`) that
consumers read later.

CI runs exactly this on every push/PR, plus `shellcheck` over `hooks/`, `bin/`, and
`tests/` (blocking gate at `error`; the full inventory lands as PR annotations while
the debt is being paid down).

## Hard boundaries

- **`hooks/` is pure bash** — never invokes Bun, never imports `src/`. NFR: <50ms.
- **Kill switch:** `MAESTRO_OFF=1` disables everything instantly. Any component
  failure degrades to the manual flow with exit 0 — Maestro **never** blocks work by
  being broken.
- **Log privacy:** `~/.maestro/logs/routing.jsonl` carries metadata only, with typed
  keys and a closed vocabulary — never the prompt text, never a full file path (only
  the extension). No key accepts `/`.
- **No floats in cost metrics** (integer tokens/cents), **no network at runtime**,
  **`vendor/` is read-only**.
- **Self-protection:** the gate always blocks — even with a decision on record —
  edits to `.claude/` and `.github/workflows/` in any project, and to `hooks/`,
  `bin/`, `src/`, `agents/`, `config/routing-table.yaml`, and `.claude-plugin/`
  under the plugin root. The router doesn't rewrite its own rules; agents edit
  `docs/`, `tests/`, and this README — the gate and the CLI belong to the human.

## Documentation

| doc | what |
|---|---|
| [`docs/architecture/ARCHITECTURE.md`](docs/architecture/ARCHITECTURE.md) | ADRs — the decisions and their whys |
| [`docs/architecture/DATA_MODEL.md`](docs/architecture/DATA_MODEL.md) | schemas: decision record, log, envelope |
| [`docs/architecture/API_SPEC.md`](docs/architecture/API_SPEC.md) | hook and CLI contracts |
| [`docs/architecture/EPICS.md`](docs/architecture/EPICS.md) | scope — nothing gets in without an amendment here |
| [`docs/decision-log.md`](docs/decision-log.md) | diary of decisions, incidents, and corrections |

## License

There are **two different licenses** in this repository, and they don't mix:

| what | license | holder |
|---|---|---|
| Maestro itself — `hooks/`, `bin/`, `src/`, `config/`, `docs/`, `tests/`, and the 5 first-party agents | MIT ([`LICENSE`](LICENSE)) | © 2026 Romulo de Jesus Costa |
| `vendor/wshobson-agents/` — verbatim copies, pinned by commit in `PINNED.md` | upstream MIT | © 2024 Seth Hobson |
| `agents/{golang,python,typescript,postgres}-pro.md` — adaptations (derivative works) | upstream MIT | © 2024 Seth Hobson, adapted |

Choosing MIT for the project **does not relicense** the vendored material: it remains
under Seth Hobson's MIT, with his copyright notice preserved in
`vendor/wshobson-agents/LICENSE` and the provenance in each adaptation's frontmatter.
