# Changelog

All notable changes to Maestro. Format follows [Keep a Changelog](https://keepachangelog.com);
versioning follows [SemVer](https://semver.org). Entries before v1.1.0 were reconstructed
from the decision log and tag messages when this file was introduced.

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

[1.2.0]: https://github.com/tropeks/Maestro/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/tropeks/Maestro/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/tropeks/Maestro/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/tropeks/Maestro/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/tropeks/Maestro/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/tropeks/Maestro/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/tropeks/Maestro/releases/tag/v0.2.0
