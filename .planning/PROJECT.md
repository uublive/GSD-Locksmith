# GSD Locksmith

## What This Is

A set of shell-based plugins for GSD (Get Shit Done) that enable a 3-person dev team to work in parallel without breaking each other's planning artifacts. The plugins use Claude Code hooks, git hooks, and a shared registry (on an orphan branch in the same repo) to automate milestone/phase number allocation and validate planning file integrity on merge.

## Core Value

No more manual Slack coordination to claim milestone and phase numbers — the tooling handles it automatically so the team can work independently without collisions.

## Current State

**Shipped:** v1.0 MVP (2026-05-20)
**Codebase:** ~1,460 lines of Bash across 12 source files
**Tech stack:** Bash 5.x + `gh` CLI + `jq` 1.7+

v1.0 delivers the complete coordination loop: registry-based number allocation, CC hook interception of GSD commands, pre-merge-commit validation of planning files, one-command install, and post-merge stale claim cleanup.

## Requirements

### Validated

- ✓ Automatic milestone number allocation via shared registry — v1.0 (Phase 1)
- ✓ Automatic phase number allocation via shared registry — v1.0 (Phase 1)
- ✓ Shared registry with branch and ownership metadata — v1.0 (Phase 1)
- ✓ Best-effort concurrency on registry read/write — v1.0 (Phase 1)
- ✓ Registry status command (gsd-status) — v1.0 (Phase 1)
- ✓ CC PreToolUse hooks intercept `/gsd-new-milestone` — v1.0 (Phase 2)
- ✓ CC PreToolUse hooks intercept `/gsd-new-phase` — v1.0 (Phase 2)
- ✓ Exit code 2 blocks on hook failure — v1.0 (Phase 2)
- ✓ Clean hook stdout (no shell profile contamination) — v1.0 (Phase 2)
- ✓ Phase numbering gap detection — v1.0 (Phase 3)
- ✓ Duplicate REQ-ID detection — v1.0 (Phase 3)
- ✓ STATE.md drift detection — v1.0 (Phase 3)
- ✓ Stale cross-reference detection — v1.0 (Phase 3)
- ✓ Validation errors show file, line, and fix command — v1.0 (Phase 3)
- ✓ One-command install script — v1.0 (Phase 4)
- ✓ Onboarding README — v1.0 (Phase 4)
- ✓ Stale claim auto-release on branch merge — v1.0 (Phase 4)

### Active

- [ ] Roadmap gate hook (PreToolUse on Write/Edit to ROADMAP.md) — implemented post-milestone, not formally tracked
- [ ] Live end-to-end testing: CC session, merge blocking, post-merge release

### Out of Scope

- Optimistic locking / strict concurrency — manual fix is acceptable for rare races in a 3-person team
- Web UI or dashboard — CLI-only; `gsd-status` covers visibility
- Conflict auto-resolution — detect and report only; wrong auto-merge is worse than unresolved conflict
- Non-gitflow workflow support — designed for feature branches merging to development
- Semantic versioning / changelog — internal bash scripts, not a published library

## Context

The team of 3 developers uses GSD with Claude Code to manage project planning. They follow gitflow: each dev works on feature branches and merges back to a development branch. The core pain is that GSD planning artifacts (ROADMAP.md, STATE.md, REQUIREMENTS.md, phase plans) use sequential numbering for milestones and phases, and parallel work causes collisions when two devs independently pick the same numbers.

The shared registry lives on a `gsd-registry` orphan branch in the same repo. All team members read/write via GitHub Contents API using their own `gh auth`. Auth relies on each dev having `gh auth login` completed.

## Constraints

- **Tech stack**: Bash scripts + `gh` CLI only — no additional runtime dependencies
- **Auth**: Relies on `gh auth login` being configured per developer
- **Registry**: Orphan branch `gsd-registry` in same repo; one-time setup via `install.sh`
- **Concurrency**: Best-effort (read-then-write) — strict locking is out of scope
- **Hook types**: Claude Code hooks (settings.json) for GSD command interception + git hooks for merge-time validation

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Orphan branch for registry (replaced Gist) | Gists can only be edited by their creator; orphan branch uses each dev's own repo push access | ✓ Good — eliminated shared token requirement |
| Shell + `gh` CLI (no Node/Python) | Minimal dependencies, CC hooks run shell commands natively, whole team has `gh` installed | ✓ Good — zero setup friction |
| Best-effort concurrency | Team of 3 — simultaneous runs are rare enough that manual resolution is acceptable | ✓ Good — no races observed in practice |
| Both CC hooks and git hooks | CC hooks automate number claiming at creation time; git hooks catch integrity issues at merge time | ✓ Good — defense in depth |
| PreToolUse on Bash (pivoted from UserPromptExpansion) | GSD plugin skills bypass UserPromptExpansion; PreToolUse on Bash intercepts gsd-sdk init calls reliably | ✓ Good — solved interception gap |
| Roadmap gate hook (PreToolUse on Write/Edit) | Hooks the file write, not the command; catches all agents writing ROADMAP.md | ✓ Good — more robust than command matching |
| TDD for validation library | Red-green cycle with fixture harness; 8/8 tests passing | ✓ Good — caught edge cases in BSD awk |
| Atomic install with jq tmpfile pattern | Prevents corrupt settings.json if jq fails mid-write | ✓ Good — idempotent and safe |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:**
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone:**
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-21 after v1.0 milestone completion*
