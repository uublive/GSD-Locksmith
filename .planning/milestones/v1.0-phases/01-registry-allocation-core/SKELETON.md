# Walking Skeleton — GSD Team Coordination Plugins

**Phase:** 1
**Generated:** 2026-05-19

## Capability Proven End-to-End

A developer can run `./hooks/claim-number.sh milestone` and the next available milestone number (plus its phase-1 entry) is written to the shared GitHub Gist registry, with the claimed numbers printed to stdout.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Runtime | Bash 3.2+ (`#!/usr/bin/env bash`) | Only runtime the team agreed on; shebang picks up Homebrew bash 5.x where present |
| Registry storage | GitHub Gist (single `registry.json` file) | No server infra; accessible via `gh` CLI with OAuth; no merge conflicts on the registry file itself |
| Gist access | `gh gist view` / `gh gist edit` with local temp file | `gh` handles OAuth transparently; `gh gist edit GIST_ID --filename name /tmp/file` is the non-interactive write path |
| JSON processing | `jq` 1.7+ | Mandatory for safe JSON; preinstalled on macOS Sequoia; no custom parsing code |
| Config location | `.claude/gsd-team.json` (committed to git) | Sits next to `.claude/settings.json` where Phase 2 CC hook entries live; all scripts read gist_id from here via `jq` |
| Script layout | `hooks/lib/` for library functions, `hooks/` for entry points | Libraries sourced by entry points; `REPO_ROOT` resolved via `git rev-parse --show-toplevel` before every `source` |
| Registry schema | Flat `claims` array with `type` field; soft-delete via `status: "released"` | Simpler append/filter than nested objects; preserves history; no number reuse |
| Concurrency model | Best-effort (read-modify-write + re-read to detect collision) | Team of 3; simultaneous claims rare; strict locking would require server infra |
| Allocation strategy | max+1 from active claims; starts at 1 when empty | Never reuse released numbers; gaps acceptable; `if length == 0 then 1 else max + 1 end` jq guard required |

## Stack Touched in Phase 1

- [x] Project scaffold — `hooks/` and `.claude/` directory structure, committed to git
- [x] Config — `.claude/gsd-team.json` with `gist_id` and `project` fields
- [x] Library layer — `hooks/lib/common.sh` (dep checks, config load) and `hooks/lib/gist.sh` (read/write registry)
- [x] Entry point — `hooks/claim-number.sh` (allocation: milestone, phase, collision, dry-run, verbose)
- [x] Status command — `hooks/gsd-status.sh` (read-only view of active claims)
- [ ] Deployment — no deployment step; full-stack exercised via `./hooks/claim-number.sh milestone` from terminal

## Out of Scope (Deferred to Later Slices)

- CC hook wiring (`.claude/settings.json` entries) — Phase 2
- Git pre-merge-commit hook (`hooks/lib/validate.sh`, `.githooks/pre-merge-commit`) — Phase 3
- One-command install script (`scripts/setup-hooks.sh`) — Phase 4
- Stale entry cleanup (auto-release on branch delete/merge) — Phase 4
- Strict locking / pessimistic concurrency — explicitly out of scope (PROJECT.md)

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- Phase 2: CC hooks intercept `/gsd-new-milestone` and `/gsd-new-phase` in Claude Code sessions and call `claim-number.sh`
- Phase 3: Git pre-merge-commit hook validates ROADMAP.md/REQUIREMENTS.md/STATE.md integrity before merging to development
- Phase 4: One-command install script + onboarding docs + stale registry entry cleanup
