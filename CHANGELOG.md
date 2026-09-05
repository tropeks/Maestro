# Changelog

All notable changes to Maestro. Format follows [Keep a Changelog](https://keepachangelog.com);
versioning follows [SemVer](https://semver.org). Entries before v1.1.0 were reconstructed
from the decision log and tag messages when this file was introduced.

## [Unreleased]

## [1.14.0] — 2026-09-05

Epics E22 and E23: direction becomes a versioned artifact, and the bet has to be
backed. An outside reading of v1.13.0 landed the sentence this release answers —
*"Maestro records the bet, it does not prove the execution"*. Four places accepted a
declaration where proof was possible: `--agents` was a field no hook ever checked,
`maestro evidence --record -- true` produced a valid receipt, the auto-update
fast-forwarded onto a `main` that CI had not blessed, and the habit sensors counted the
fixtures that exist to prove the sensors as the repo's own slop. A fifth hole was older:
the project had no declared direction, so a plan approved against a direction that had
since moved kept flowing as if nothing had changed. All five close here, under one
criterion (ADR-010): mechanical where the rail reaches, honor declared *as* honor where
it does not.

### Added
- **Versioned project direction — `maestro intent` (E22/S-2201).** A project's direction
  becomes an artifact instead of a sentence in a prompt: `<project>/.maestro/INTENT.md`
  is versioned in the repo, stamped (`<!-- maestro-intent v1`,
  `version`/`ts`/`head`/`author_session`/`hash`) and carries six mandatory sections —
  Problema, Público, Resultado, Prioridades, Limites, Fora de escopo. A heading with no
  text under it counts as missing: an empty section is the intention to write direction,
  not direction. `--init` writes the template, `--check` lists what is missing, `--bump`
  raises the version and **refuses when the content did not change** — the version is the
  number work orders cite, not a save counter. `intent_hash` is 8 hex of the sha256 of
  the body without the stamp, so stamping is not changing. Logs `intent` with
  `n=<version>` and `via=manual`; never the title, the hash or the path.
- **Work orders are born citing the direction (E22/S-2202).** `order --create` stamps
  `intent_version:`/`intent_hash:` when the project has a citable direction, and says
  "ordem sem direção" when it does not — the order is still created, since Maestro never
  blocks work. `--status` shows `direção: vN` and denounces a direction that moved on
  afterwards; `--list` marks `[direção mudou]`; `--accept` refuses under a stale direction
  unless the director declares the re-read with `--intent-reviewed`, and every acceptance
  stamps `accepted_intent:`. An order with no direction stamp is never accused.
- **The session knows which direction it works under (E22/S-2203).** The `## Projeto`
  block of the SessionStart injection carries one of three lines: `direção: INTENT vN
  (.maestro/INTENT.md) → plano cita a seção da direção que serve`, `INTENT sem carimbo →
  maestro intent --check`, or `nenhuma → maestro intent --init (E22)`. Absence is a
  reported fact, never silence. The hook only awks `version:` out of the stamp — no
  sha256 on the hot path — and points at the file instead of dumping its content. The
  plan gate now asks the plan to cite the direction (INTENT vN, section) and to say so
  when there is none. Injection ratchet deliberately bumped 6930 → 7080 bytes.
- **Delegation funnel: `planned → started → received → accepted` (E23/S-2301).**
  `--agents` was a declaration nobody checked: no hook ever saw a subagent start, so the
  retro credited an agent tier for work the director had typed himself. Two new pure-bash
  hooks close the loop — `pre-agent.sh` (PreToolUse, matcher `Agent|Task`) logs
  `delegation phase=started` on the real dispatch, `subagent-stop.sh` (SubagentStop) logs
  `phase=received` when the subagent comes back. `maestro decide` emits `phase=planned`
  when the record carries `agents`, and `order --accept` emits `phase=accepted`. Both
  hooks read a 4096-byte window, never touch the Task `prompt`/`description`, write
  nothing to stdout and always exit 0 — they observe, they never gate.
- **`maestro delegation`.** `--session <id>` counts the funnel for one session across the
  current log and the rotated ones, with a one-line verdict (planned but never dispatched
  · dispatched without return · proven). `--all` aggregates the last 20 sessions seen.
- **Mandatory verifications per area (E23/S-2302).** `.maestro.yaml` gains
  `verifications:` (area → `paths` + `labels`) and `commands:` (canonical command per
  label), parsed by `hooks/lib/verifications.sh` — bash + awk, no yq, no Bun, no jq.
  Touched areas come from the diff (path prefix), never from memory. A project that
  declares nothing owes nothing.
- **`maestro verify [--base REF] [--project P] [--check]`.** Shows the base, the touched
  areas and, per required label, whether the receipt is VÁLIDA/VENCIDA/NENHUMA together
  with the command that produces it. `--check` exits 1 when anything required is missing;
  logs `verify n=<missing>`.
- **Auto-update follows the `stable` tag CI moves (E23/S-2303).** New config
  `update_channel: stable|main` in `~/.maestro/config.yaml` (default `stable`), env
  `MAESTRO_UPDATE_CHANNEL`, and a per-call override `maestro upgrade --channel
  stable|main`. On the `stable` channel the fetch force-carries `refs/tags/stable*` and
  `refs/tags/v*`, and the ff-only target is the commit that tag points at — so a machine
  only ever moves onto a commit that shellcheck and the suite already passed on.
- **CI job `approve` (`needs: [shellcheck, suite]`, tags `v*` only).** Moves the `stable`
  tag onto the green commit. It is the single thing this CI writes; `contents: write` is
  scoped to that job alone and the workflow default stays `contents: read`.
- **State `no-stable`.** Channel `stable` with no such tag on the remote is neither a
  failure nor an update: nothing is applied, nothing is injected into the session, and
  the doctor explains it with the command that opts back into `main`.
- **`.maestro.yaml`: `habits_ignore:`** — path prefixes kept out of `maestro habits
  --all` (and `--baseline`, which is the same scope); empty by default, and whatever it
  filters is reported, never hidden.
- **Two record fields, both enum, both only alongside `outcome`:** `delegation_proof`
  (`started|none`) and `verifications` (`cited|missing`), validated by the doctor's
  `record_schema_ok`.

### Changed
- **`maestro outcome accepted` now demands proof for delegated work.** With a record in
  `mode: subagent|multi`, accepting requires at least one `delegation phase=started` for
  that session; otherwise it exits 1 and points at `maestro delegation --session <id>`.
  `--unproven` is the honest valve: it accepts and stamps `delegation_proof: none` on the
  record, against `started` when the log proves the dispatch. `direct` is untouched and
  stores no field.
- **`outcome accepted` also refuses without the required verifications.** Areas touched
  by the working tree against `merge-base(main, HEAD)`; `--unproven` passes and stamps
  `verifications: missing` (otherwise `cited`). `rework`/`reverted` are never blocked —
  only acceptance claims the work serves.
- **`order --accept` refuses without the required set.** Areas touched by
  `merge-base(main, branch)..branch`; each required label needs a receipt with `exit=0`,
  `wtree_after` equal to the branch tip tree and `cmd_match ≠ no`. `--status` shows the
  same verdict. Orders that touch no declared area keep the previous rule.
- **Receipts now match the declared command.** `evidence --record` writes
  `cmd_match=yes|no|free`; reading rejects `cmd_match=no` and a `cmd_hash` that diverges
  from today's `commands.<label>` — the hash was always recorded, it just was never
  compared. `maestro evidence --record -- true` no longer counts as proof of the suite.
  Schema stays `maestro-evidence-v1`; pre-1.14 receipts read as `free` and remain valid.
- **Order header readers scan 20 lines instead of 14** (the CLI's `_order_field` and the
  frozen-zone awk in session-start): the header grew with the direction stamp, the
  guarantee is the same — stop before the body, where a hand-written `branch:` must never
  become a field.
- **`upgrade` log events now carry `channel`** (`stable|main`) on all three paths
  (`auto`, `manual`, `rollback`), and the state file records `channel=`; the S-1810 fast
  path only reuses a measurement taken on the current channel.
- **Doctor.** Expects **7 hook events** now (SubagentStop). `check_upstream` reports the
  update channel and where `stable` sits relative to HEAD, and warns on an invalid
  `update_channel`; `check_update_state` speaks the channel and accepts `no-stable`;
  `check_release_diagram` matches `v*` only, so the movable `stable` tag cannot hijack the
  release portrait.
- **Operational note for this release:** until CI moves the first `stable` tag — which
  happens when the `v1.14.0` tag is pushed — installations on the default `stable`
  channel sit in `no-stable` and do not update. That is the intended fail-safe: a broken
  approval channel leaves a machine on the version it already proved. `maestro upgrade
  --channel main` takes the tip meanwhile.
- **Maestro dogfoods the rule:** its own `.maestro.yaml` declares areas `hooks`
  (`hooks/`) and `cli` (`bin/`, `src/`), both requiring `suite`, with `commands.suite:
  bash tests/run-all.sh`.
- `tests/run-all.sh` also enumerates `tests/lib/` — library tests were invisible to the
  runner.
- `src/cli.ts` knows the full event vocabulary (19 events), so `maestro log --summary`
  stops filing real events under `unknownEvent`.

### Fixed
- **Habit sensors: heredoc bodies in shell files are data, not code (E23/S-2304).** The
  fixtures that exist to prove the sensors fire were counted as the repo's own slop —
  `skipped-test`, `dead-code`, `lint-suppression` and `slop-comment` all dropped to zero.
  The opening line is still sensed; the body is excluded from `oversized-function` and
  still counted by `oversized-file`, which is file size for real.
- **Habit sensors: a doc table in a file header (`VAR=1   description`) is prose in
  columns, not commented-out code** — kills the `dead-code` false positive on
  `hooks/lib/update-check.sh`, where the "fix" the sensor asked for was deleting
  documentation.
- **`.maestro-habits.tsv` rebaselined with the new sensor** (`deep-nesting 10 ·
  oversized-file 12 · oversized-function 6 · skipped-test 1`); `maestro habits --all`,
  the CI ratchet step, is green again and the CI command is now asserted by the suite
  itself.

## [1.13.0] — 2026-09-02

Epic E21: human gates reach the runtime and the phone. The Captain already runs
sessions inside herdr; Maestro now leaves the gate question where a thin
transport can read it, and the transport (Legatus vNext, own repo) is a page of
Python instead of an orchestrator.

### Added
- **Stop hook `gate-report.sh` (S-2101).** Only inside herdr. When a turn ends
  with a plan gate pending (`approach: pendente` on a plan-gated workflow) or a
  ship gate (workflow `ship` without outcome), writes
  `~/.maestro/herdr/gates/<pane>` with the conducted question — the brief's
  essence only, never `reason` — and reports `blocked` to herdr best-effort.
  Measured while designing: for Claude Code herdr's state authority is screen
  detection and a custom `blocked` report was ignored on a working pane, so the
  file is the guaranteed channel. Without a pending gate the stale file is
  removed. `user-prompt-submit.sh` removes the file and releases the authority
  when the human answers. Doctor expects 6 hook events.

## [1.12.1] — 2026-09-01

### Fixed
- **Release tags now travel with the auto-update (S-1904, Legatus finding).**
  The updater fetched `main` only, so a machine that had cloned at v1.11.0 and
  auto-upgraded to v1.12.0 still had v1.11.0 as its newest tag, and the doctor
  compared the release portrait against it ("verificado em 96dd1c7, release
  v1.11.0"). The fetch now carries `--tags`; a test pins that a tag published
  with a release reaches a clone that only follows `main`.

## [1.12.0] — 2026-09-01

Epic E20: git as the telemetry bus. With two real machines running Maestro,
each retro only saw its own box. The log now rides the same rail that already
crosses machines (upgrade, work orders, docs): a private git repo, no server.

### Added
- **Telemetry publish on session end (S-2001).** `hooks/lib/telemetry-sync.sh`
  reuses the update-check primitives (timed network calls, non-blocking lock,
  fork-free state reads). Opt-in per machine (`telemetry_remote` in
  `~/.maestro/config.yaml`); once per interval the SessionEnd hook mirrors
  only `routing*.jsonl` into `logs/<host-id>/` on branch `main` — one writer
  per file, so rebases are always clean. A failed push leaves the commit and
  the next round publishes it. State in `~/.maestro/telemetry-state`; silence
  never means published.
- **`maestro telemetry` (S-2002)** — `--status`, `--push`, `--pull`,
  `--remote <url>`, `--off`. **`maestro retro --all`** pulls the bus and
  aggregates the other hosts (never its own, already local) with a
  `-- por máquina` line. Doctor `check_telemetry`; envelope gains
  `telemetry.{result,host}`.

### Changed
- DATA_MODEL integrity rule "nothing leaves the machine" gains its single,
  explicit exception: the routing log, metadata by construction, to a private
  repo, opt-in. Records, briefs, evidence and consents stay local.

## [1.11.2] — 2026-09-01

### Fixed
- **The updater told the truth to itself and not to the human (Legatus finding).**
  `maestro upgrade --check` without `--force` honors the fetch interval, so it
  compared against a 31-minute-old `origin/main` and printed "em dia (v1.11.0)"
  while v1.11.1 was already published. Three disclosure defects, one cause:
  the doctor hint said `--check` "forces" (it does not — `--check --force`
  does); the doctor's "verificado há Nh" counted from the last cache read
  instead of the last successful fetch, so it could say 0h with 23h-old network
  data; and `--check` never revealed whether it had fetched. Now the hint
  teaches `--check --force`, the doctor age comes from `fetched`, and the
  `--check` line says "cache do último fetch; --force consulta o origin" (or
  "fetch FALHOU") whenever the claim was made without touching the remote.
  Behavior of the updater unchanged; only what it reports. Tests pin all three.

## [1.11.1] — 2026-09-01

The first release that flows through the auto-updater. Two real items, both
measured, nothing decorative.

### Added
- **`session_end` is finally emitted (S-1811).** The event had been in the log
  vocabulary since E2 and nothing produced it, so a session that ended without
  `maestro outcome` was invisible to the retro. `hooks/session-end.sh` (pure
  bash, no jq) logs `decided`/`settled` by presence in the decision record —
  never its content. Doctor now expects 5 hook events; `maestro retro` prints
  `sessões encerradas · sem decisão · decididas sem desfecho`.

### Changed
- **Update check fast path (S-1810).** Inside the fetch interval the full
  measurement (show, rev-list ×2, branch, status) still ran every session and
  cost ~150ms against the <100ms NFR. When HEAD and `origin/main` match the
  SHAs recorded by the last `current` check, two `rev-parse` decide
  (`reason=fast-path`). State and config are read without `sed`. Measured on
  NetForge: ~50ms over a session with the check disabled.

## [1.11.0] — 2026-09-01

Epic E19: Maestro keeps itself current. Approved by the Captain with one
adjustment to the house rule — network is allowed at runtime as long as it can
never break execution. Until today the plugin had no update path at all: the
README stopped at `git clone`, and on approval day the dev box itself sat two
commits ahead of origin with no upstream, so any other machine pulling would
have silently missed two fixes.

### Added
- **Auto-update on session start (S-1901).** `hooks/lib/update-check.sh` is the
  one and only network call in Maestro: `git fetch` with a 5s timeout, at most
  once per interval (24h), silent on failure, under a non-blocking `flock`.
  When `origin/main` is ahead and the fast-forward is strictly safe (clean
  tree, zero local commits ahead, on `main`), the hook merges and **re-executes
  its new self** — the whole session is born on the new version, no old parser
  reading new config. With `auto_upgrade: false` it injects one header line
  instead (`atualização: vX → vY … maestro upgrade`). A development machine is
  never overwritten: dirty or ahead trees get a one-line "push, não pull".
  Silence never means up to date — every check, including failures, is written
  to `~/.maestro/update-state` for the doctor (the gstack #1974 lesson). Log
  event `upgrade` with `from`/`to`/`via`.
- **`maestro upgrade` (S-1902).** Forced fetch + fast-forward with the guards
  explained in plain language, CHANGELOG delta between the two versions, then
  `exec doctor --ci` on the *new* binary. `--check` (exit 0/1/2), `--rollback`
  (`git reset --keep` to the recorded previous SHA), `--snooze` (24h → 48h →
  7d per remote version), `--set` for `~/.maestro/config.yaml`
  (`update_check`, `auto_upgrade`, `update_interval_hours`). Disabling the
  automatic check never disables the manual command.
- **Doctor (S-1903).** `check_update_state` reads the state file: available →
  warn with the command; failed, or last good fetch older than 7 days → warn;
  blocked → ok naming the dev box. `check_upstream` catches the crack found on
  approval day: commits without push and `main` without upstream are warnings.
  The capabilities envelope gains `update.{result,local,remote}`.

### Changed
- ADR-001 amended: upgrade via git is now a mechanism, not an instruction. The
  "no network at runtime" boundary is reworded everywhere (CLAUDE.md,
  ARCHITECTURE NFRs, READMEs) to "network is never a dependency": one call,
  timed out, rate-limited, silent, recorded.
- The test suite exports `MAESTRO_NO_UPDATE_CHECK=1` globally; the update tests
  opt back in against a `file://` bare remote — the suite never touches the
  network.

## [1.10.1] — 2026-09-01

### Fixed
- **Order label had a crack between suggestion and reader (S-1802).** The order
  contract suggested the raw oid (`order-001` if you typed 001) while the state
  readers normalize (`order-1`): following the suggestion produced an invisible
  receipt — a real 14-minute agent round lost in production. The suggestion now
  derives from the same formula as the reader, and the reader evaluates both
  candidate labels until one PROVES (a stale canonical receipt no longer shadows
  a fresh padded one).
- **Override rate counted lifecycle commands as routing failures (S-1801).** The ADR-008 sensor logs every slash prompt, and retro counted them all: a real 7-day window showed 21% override when every single event was context-save/restore, upgrade or login — true routable override was 0%, and the false signal would have blocked gate hardening forever. Retro now derives the routable set from the routing table itself and scores the rate on routable overrides only, reporting the lifecycle count separately. Sensor unchanged; raw data preserved.

## [1.10.0] — 2026-09-01

### Added
- **Release diagram as a milestone contract (S-1709).** Deterministic archify
  source versioned at docs/assets/architecture.json (evidence-backed against
  the tagged commit) with the rendered HTML beside it; doctor now warns when
  the diagram's verified revision falls behind the latest tag. The archify
  package lives at ~/.tools/archify — a local tool, not an always-loaded
  skill. The release rite gains the regenerate + Architecture Delta step;
  this release is its debut.

## [1.9.1] — 2026-08-31

### Fixed
- **Dissent flags survive re-decide (S-1708).** Found live in NetForge hours
  after v1.9.0: `conduct` recorded 4 flags, a re-decide 9 minutes later rewrote
  the session record and the flag content evaporated (the log keeps only
  `flags_n`, by contract). `decide` now merges the existing `flags[]` into the
  new record, including across workflow/mode changes — the dissent trail
  belongs to the session; deleting flags requires deleting the record.

### Changed
- Governance gotcha paid: EPICS.md covers its own directory, so a sibling
  re-attest commit marks it STALE once; re-attesting EPICS itself converges.

## [1.9.0] — 2026-08-31

Epic E17: conducting — every human contact translated (essence · impact ·
approach, score on demand), declared plan depth, and a formal dissent channel
for agents. Abstracted from the Captain's architecture-skill suite into
existing mechanisms; design survived a cross-model challenge and three rounds
of adversarial review before any code.

### Added
- **Conducted approval**: `maestro decide` gains `--brief` with three literal
  markers (`essencia:`/`impacto:`/`approach:`, caps 200/700); workflows with
  `gate: plan` (feature AND refactor) refuse a record without it. `approach:
  pendente` is valid and closed later.
- **Declared depth**: `--depth standard|deep|day-zero` on the record;
  `--profile prototipo|piloto|produto` required iff day-zero. Day zero NEVER
  fires automatically (S-1602 silent-brownfield preserved) — heuristic H7
  guides the director's judgment.
- **`maestro conduct`**: mutates the record — typed dissent flags
  (`sev|decisao|tradeoff|mitigacao`, each ≤120, sev closed enum) and
  `--approach` closing the pending brief; `conduct` event in the closed log
  vocabulary (counts only, never content). Doctor validates the schema and
  warns on outcome with a pending approach.
- **Regência late nag**: habit sensor at edit tiers 15/40 reinforcing the
  conducted format end-of-session (S-1603 research: injection decays, late
  reinforcement works); S-1603b doc-governed sensor finally has test coverage.
- **Roster**: `seguranca` and `ux` (both opus — deliberate ADR-004 exception,
  recorded in ADR-009: design responsibility + lean subagent context).
- **EPICS.md governed**: roadmap under E16 drift watch (covers
  `docs/architecture/**`, doc-level granularity to stay clear of the fan-out
  guard).
- Injection: H7 + conducted-approval bullet; ratchet 6800 → 6930, measured.

### Changed
- Docs amended in the same changeset (contract rule): ADR-009, DATA_MODEL
  Emenda v1.7 (brief/flags are the director's synthesis — the anti-prompt-leak
  rule stands, now with explicit caps), API_SPEC for decide/conduct.
- `outcome`/`conduct` record mutations now preserve mode 0600.
- Doctor's habit-guide pairing now sees session sensors (`doc-governed`,
  `regencia`), making the orphan-guide guarantee real.

### Routing
- feature workflow: office-hours interrogation forced before every plan
  (shipped in e0cc4f8, released here).

## [1.8.0] — 2026-08-30

Epic E16: documentation as contract — the product spec sessions actually
follow. Designed research-first: a dedicated subagent surveyed spec-driven
tooling and adherence studies before any code, killing three initial guesses.

### Added
- **`maestro docs`**: canonical docs declared in `.maestro.yaml`; each doc's
  frontmatter states the areas it governs (`covers:` globs) and optionally
  `reviewed: <sha>` (re-attest freshness without cosmetic edits — the
  provenance-stamp pattern). Verdicts count COMMITS since
  max(last doc commit, reviewed): boundary settlement, not same-commit
  strictness. Flags absent docs, prose-only docs, and glob fan-out.
- **Docs ratchet** (`.maestro-docs.tsv`, versioned): brownfield debt enters
  without screaming; `--check` fails only NEW drift.
- **Citation rule where research says it works**: short positive rule in the
  session injection plus a single LATE nudge on the first edit inside a
  governed area (`doc-governed` habit sensor) — instruction adherence decays
  measurably within a session; session-start-only rules are theater.
- **Orders name their authorizing doc** (`--doc`): the execution contract
  demands the amendment in the same changeset; `--status` shows doc freshness.

### Changed
- Injection ratchet: first deliberate bump (6500 → 6800B, rationale in the
  test) — the `## Projeto` section now carries four subsystems (brief, graph,
  orders, docs); two prose squeezes preceded the bump.

### Noted
- Dogfood bit the author first: ARCHITECTURE.md measured 6 commits stale on
  first run — settled with a real ADR amendment, not a pin.
- Phase 2 recorded, not built: `maestro converge` (on-demand LLM
  reconciliation) and the fire-and-forget ladder (doc delta → proposed order
  → approved headless dispatch).

## [1.7.0] — 2026-08-30

Epic E15: work orders — Maestro starts directing work it isn't watching. The
third and last contract from the RAD research is implemented; all three now
ship (evidence, budget, work order).

### Added
- **`maestro order`**: versioned work orders in the target repo
  (`.maestro/orders/NNN.md`) carrying objective, acceptance criteria, frozen
  zones, Ask-First triggers, declared budget, and the expected branch — plus a
  generated execution contract (own branch, proof via the ledger, who accepts).
- **Derived state, never self-declared**: open → executing (branch exists) →
  proven (evidence receipt whose wtree matches the branch tip tree — a commit
  after the proof demotes the order automatically) → accepted (director's
  explicit `--accept`, refused without proof, stamped and audited).
- **Frozen zones in the gate**: compiled into the policy at session start;
  autonomous sessions are blocked inside a pending order's frozen zone, humans
  are warned (the S-502 asymmetry); acceptance thaws on recompile.
- Injection: pending orders surface in the `## Projeto` section, so any new
  session in the project discovers the work by itself.

### Noted
- Out of v1 by design: multi-machine fleet (Legatus bridge — the arc's phase
  2) and automatic session dispatch (creating an order ≠ executing it).

## [1.6.0] — 2026-08-30

The gate goes hard, and decisions learn to declare their budget.

### Changed
- **`gate.mode: block` promoted** — with proof, not faith: a 14-day retro (133
  decisions, 13% override) plus a live `claude -p` E2E showing warn let
  one-shot sessions edit without a decision. Every code edit on the machine now
  requires a registered decision; reversal is one line with human approval.
  The stability criterion is codified: the live E2E must pass in block mode —
  and it does.
- The first block-mode E2E run failed with gold and both finds are fixed: the
  gate's block message taught the E1-era hyphenated command name, and headless
  sessions deadlocked on a permission prompt when registering the decision
  (fixed via a scoped harness allow rule for the maestro CLI).

### Added
- **Declared budget** (E14): `maestro decide --max-steps N --max-min N
  --max-cents N` — integer caps, AND-of-caps, warn-only. The gate warns ONCE
  per exceeded cap (steps via per-session counter, minutes via the record
  timestamp) and never blocks; cents is declarative for retro's cost × outcome
  correlation. Record schema v1.6 validates budgets and rejects floats.
- Live-dispatch E2E hardened into the promotion workflow; habit-sensor engine
  killed three structural false-positive classes (list prose in comments,
  marker-strip indentation, shell `--flag)` arms read as SQL comments), ruler
  down 30 → 28.

## [1.5.0] — 2026-08-29

Three additive fronts: infra autonomy under explicit consent, the Opus tier the
MoE ladder was missing, and a mechanical evidence ledger. Plus the week's most
valuable test failure.

### Added
- **`ops` consent scope** (S-1006): with explicit, TTL-bound human consent, the
  Bash guard downgrades block→audited warn for OPERATIONAL categories only
  (sudo, docker, kubectl). A single data-destruction category (rm -rf, force
  push, DROP, dd) keeps the full block even with consent — ops unlocks
  infrastructure, never wipeouts. The block message teaches the consent path.
- **`arquiteto` (opus)** (S-304): the top of the tiering ladder, scoped by its
  description to critical structural decisions only (cross-system, data
  migration, concurrency, security, expensive-to-revert); routine plans stay on
  `engenheiro` (sonnet). H4 forked. Under measurement: retro's accepted/rework
  decides whether the tier pays for itself. First real use of the E10 consent
  flow (roster + routing-table granted, edited through the gate, revoked).
- **`maestro evidence`** (E13): execution receipts bound to content — wtree
  before/after the run, command hash, exit as data, age cap. VALID only for
  byte-identical content + exit 0 + fresh + still tree; anything else names its
  reason. `outcome --suite pass` now cites valid evidence or warns "word of
  honor" (`suite_evidence` on the record); deslop records per-batch evidence;
  retro reports coverage; doctor validates receipts.
- **Live-dispatch E2E** (tests/e2e/, manual paid tier): a real `claude -p`
  session proving whether the injection governs behavior. Its first run failed
  honestly — one-shot headless sessions skip the decision in warn mode while
  interactive sessions comply — new concrete evidence for the warn→block
  promotion, which now additionally requires this E2E to pass in block mode.

### Noted
- gstack 1.60→1.72 mining triage: evidence ledger and live-proof adopted;
  egress ledger (no sink by design), tracker trust-envelope (no ingestion),
  Aside browser and section carves (out of domain) rejected with rationale.

### Fixed (folded 2026-09-01 — shipped in this release, left in Unreleased by mistake)
- **`doctor` reprovava o record de quem registrou o desfecho.** A emenda v1.5
  (E10/S-1001) mandou `maestro outcome` gravar `outcome`, `outcome_ts` e `suite`
  no decision record, mas `RECORD_FIELDS` nunca cresceu — e a checagem "sem campos
  extras" derrubava justamente o record correto. Efeito: qualquer sessão em que
  alguém fechou o loop de calibração fazia `doctor --ci` sair 1, o que empurra o
  operador a apagar o record (o `fix:` da própria mensagem) e perder o dado que o
  E10 existe para colher. A CI não via porque a suíte roda o doctor com
  `MAESTRO_HOME` temporário e zero record; agora vê.

  Os três campos passam a ser validados, não só aceitos: `outcome ∈
  {accepted, rework, reverted}`, `suite ∈ {pass, fail}`, e `outcome_ts`/`suite`
  exigem `outcome` presente (não há desfecho órfão).

### Removed (folded 2026-09-01 — same)
- **`.orphaned_at` destrackeado.** Marcador interno do Claude Code que entrou por
  engano no `d98838a`; viajava para todo clone e para o cache do plugin.

## [1.4.0] — 2026-08-24

Epic E11: knowledge-graph freshness — structure without re-reading code. The
brief (E8) covers state; a graphify graph covers structure; the invariant is
that a stale map is worse than no map.

### Added
- **`grafo:` line in the `## Projeto` injection**: when `graphify-out/graph.json`
  exists, sessions are pointed at it with an honest verdict — fresh → "answer
  structure via graphify query BEFORE reading code"; stale (counting commits
  since generation) → "do NOT trust it". No graph → no line; graphify stays
  optional and out of the envelope. Freshness needs no new stamp: graph mtime
  vs last commit date.
- **`maestro graph [--check]`**: freshness status; `--check` exits 1 only on
  STALE — the refresh routine's trigger.
- **`bin/maestro-graph-refresh`**: versioned operator routine (weekly machine
  crontab, not a hook — the one place headless `claude` is acceptable; session
  hooks stay pure bash, no network). Scans for existing graphs and incrementally
  updates only the stale ones: per-run cap, flock, timeout, its own operations
  log. Generating a first graph remains a human decision.
- **Graph-aware `/maestro:deslop`**: batches built by graph QUERY (verified file
  independence) when the graph is fresh; degrades to session knowledge otherwise.

### Noted
- Measurement gate on record: deeper wiring (workflow bindings, auto-generation)
  only enters if a measured large-repo run moves the number — the same court
  that rejected gbrain at 36% recall@1.

## [1.3.0] — 2026-08-23

Epic E10: the calibration loop — Maestro learns in batches, never at runtime.
Telemetry → retro → proposed diffs → exam (suite + eval-on-diff) → versioned
commit. Learning is git history.

### Added
- **`maestro outcome`**: closes each decision with its result
  (accepted|rework|reverted, optional suite pass|fail) — the dependent variable
  the log was missing. Decision record amendment v1.5; enums only, never text.
- **`maestro retro [--days N]`**: deterministic window report — override rate,
  decisions by mode/workflow, gate stats, habit_warn by smell, outcomes,
  consents, declared-but-unused workflows — plus the warn→block promotion
  criterion encoded (≥14d, ≥10 decisions, override <20%). An empty log answers
  "no data" instead of inventing conclusions.
- **`/maestro:retro`**: the AI reads the report, proposes concrete diffs each
  tied to its justifying signal, and — on explicit approval — applies them under
  minimal consent, passes the suite + eval-on-diff exam before committing, then
  revokes.
- **Scoped consent** (ADR-003 amendment v1.2): `maestro consent --grant
  routing-table|roster [--ttl 1min–4h]` lifts the self-protection denylist for
  DATA only — hooks/, bin/, src/, and .claude-plugin/ have no consentable scope
  by construction; a forged consent file for them unlocks nothing (tested).
  Fail closed; does not bypass the decision record; fully audited; active
  consents surface as doctor warnings.

### Noted
- First real retro run over 14 days of dogfood: 113 decisions, 10% override →
  warn→block promotion eligible — the roadmap Fase 1b gate met on production
  data.

## [1.2.0] — 2026-08-21

Epic E9: anti-slop habit sensors — the habit-hooks pattern (deterministic sensor +
qualitative coaching guide, always together) rebuilt inside Maestro's boundaries.
Everything is warn-only; nothing blocks an edit.

### Added
- **Habit sensors at edit time**: a PostToolUse hook runs 14 pure-awk sensors on every
  edited code file — oversized-{function,file}, deep-nesting, too-many-params,
  swallowed-error (incl. bare `except:`), debug-leftover, lint-suppression, type-escape,
  slop-comment (incl. hedging phrases), empty-impl (incl. pass-only bodies), dead-code,
  skipped-test, risky-shortcut (incl. `import *`), and a session-level test-gap sensor.
  Findings ship with their coaching guide (`config/habit-guides/`); 15-min cooldown per
  (file, smell), ≤3 findings + ≤2 guides per emission; ~40ms typical. `habits:` in
  `.maestro.yaml` tunes the set per project. New `habit_warn` log event (category only).
- **`maestro habits`**: the same engine over the diff (default), `--all`, or paths — for
  the review step and CI. Exit 0 clean · 1 findings · 2 environment.
- **Per-smell baseline ratchet**: `maestro habits --baseline` pins counts in
  `.maestro-habits.tsv` (versioned); with it present, `--all` fails only smells that
  EXCEED the baseline. Untracked non-ignored files count.
- **`/maestro:deslop`**: slash command that pays slop debt in reviewable batches —
  triage by class (mechanical → haiku tier; judgment → language specialist with tests;
  honest false positives → config, never inline suppression), suite as the gate between
  batches, reviewer over the final diff, baseline re-pinned per batch.
- Doctor: 4 hook events, every sensor must have a guide, command frontmatter validated
  (35 checks).

## [1.1.0] — 2026-08-20

Epics E7 (RAD hardening) and E8 (situational awareness), plus the public-release
preparation. Everything ships warn-only/informative: nothing here blocks work.

### Added
- **Project brief** (E8): `maestro brief` — per-project situational state stamped with
  timestamp, git HEAD, content fingerprint (wtree), and session id; pure bash, no
  runtime dependency. SessionStart injects a ~300B `## Projeto` section: a pointer to
  the brief with an honest freshness verdict (`FRESCO` / `STALE — N commit(s) behind`),
  a `memória:` line derived from the new `memory_container:` key in `.maestro.yaml`,
  and the standing request to update the brief when closing substantial work. A fresh
  session reads one file instead of sweeping the repo.
- **Content fingerprint in decision records** (E7/S-701): `bin/maestro-wtree` stamps
  `wtree` on `maestro decide`; `maestro status` reports freshness.
- **Routing-table eval-on-diff** (E7/S-702): per-case verdict baseline pinned in CI —
  a route mutation fails naming the case that changed, before → after.
- **Injection ratchet** (E7/S-703): the doctor runs the real hook and measures the
  actual bytes against the 8000B cap; the conscious 6500B ratchet lives in a test with
  a deliberate same-commit bump protocol.
- **Out-of-envelope signals** (E7/S-704): experimental agent-teams env var warns; MCP
  servers are named (names only — config/URLs never leak).
- **Capability envelope** (E7/S-705): `capabilities.json` (`maestro.capabilities.v1`)
  with measured runtime facts; CLI errors without Bun cite the last doctor run.
- **Binding-resolution drift + pinned vendor** (E7/S-706): target→path→sha256 snapshot
  compared on every doctor run; `vendor/` verified offline against a pinned manifest.
- **Communication style, execution ethos, and Spock directive in the injection**
  (E7/S-707..S-709): versioned config files emitted as injection sections with their
  own byte caps and graceful degradation.
- **Plugin install drift** (E7/S-710): the doctor compares the registered plugin copy
  with the repo byte for byte across the files that define behavior — an identical
  version number once hid six commits of difference. Severity follows who executes:
  with a directory marketplace pointing at the repo, a divergent cache copy is inert.

### Changed
- README rewritten for the public repo, English-first (`README.md`) with a Portuguese
  version (`README.pt-BR.md`). Commit and tag history translated to English.
- Internal improvement research moved out of the repo and its history.

## [1.0.4] — 2026-08-12

Version-only bumps while activating the plugin globally (user scope) and starting
dogfood: `.maestro.yaml` for this repo itself, hermetic test suite via the
`MAESTRO_SKILL_DIRS` fixture (green CI without installed skill packs), and the
`--prefix` realignment of the gstack bindings. No tags were cut for 1.0.3/1.0.4.

## [1.0.2] — 2026-08-09

- ADR-007 closed: memory is supermemory (measured against claude-mem and gbrain);
  Maestro has no memory component.

## [1.0.1] — 2026-08-09

- Injection version derived from the plugin manifest instead of a hardcoded literal.

## [1.0.0] — 2026-08-09

Epics E1–E5 complete: installable plugin with kill switch (`MAESTRO_OFF=1`),
SessionStart injection of the routing table, structural PreToolUse gate with compiled
policy and self-protection, destructive-command guard for Bash, `decide|status|log`
CLI in Bun, manual-override baseline logging, roster of 9 cost-tiered agents (4
specialists vendored from wshobson/agents, MIT), routing table v2 with step→executor
bindings and human gates, blind-judge calibration (routing 73% → 100%), CI with
shellcheck + suite + doctor, MIT license.

## [0.3.0] — 2026-08-09

- E3: tiered roster, vendored specialists, `.maestro.yaml` roster filtering.

## [0.2.0] — 2026-08-09

- E1+E2: plugin skeleton, kill switch, doctor, injection, gate, CLI, override baseline.

[1.10.1]: https://github.com/tropeks/Maestro/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/tropeks/Maestro/compare/v1.9.1...v1.10.0
[1.9.1]: https://github.com/tropeks/Maestro/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/tropeks/Maestro/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/tropeks/Maestro/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/tropeks/Maestro/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/tropeks/Maestro/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/tropeks/Maestro/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/tropeks/Maestro/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/tropeks/Maestro/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/tropeks/Maestro/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/tropeks/Maestro/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/tropeks/Maestro/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/tropeks/Maestro/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/tropeks/Maestro/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/tropeks/Maestro/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/tropeks/Maestro/releases/tag/v0.2.0
