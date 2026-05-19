# GSD Team Coordination Plugins

## What This Is

A set of shell-based plugins for GSD (Get Shit Done) that enable a 3-person dev team to work in parallel without breaking each other's planning artifacts. The plugins use Claude Code hooks, git hooks, and a shared GitHub Gist registry to automate milestone/phase number allocation and validate planning file integrity on merge.

## Core Value

No more manual Slack coordination to claim milestone and phase numbers — the tooling handles it automatically so the team can work independently without collisions.

## Requirements

### Validated

- ✓ Automatic milestone number allocation via shared gist registry — Phase 1
- ✓ Automatic phase number allocation via shared gist registry — Phase 1
- ✓ Shared gist registry with branch and ownership metadata — Phase 1
- ✓ Best-effort concurrency on gist read/write — Phase 1
- ✓ Registry status command (gsd-status) — Phase 1

### Active

- [ ] Claude Code hooks that intercept milestone/phase creation commands
- [ ] Claude Code hooks that intercept milestone/phase creation commands
- [ ] Git hooks that validate planning file integrity on merge to development
- [ ] Phase numbering gap detection
- [ ] Duplicate REQ-ID detection
- [ ] STATE.md drift detection (state vs roadmap consistency)
- [ ] Stale cross-reference detection (plans referencing removed requirements/phases)
- [ ] Shared gist registry with branch and ownership metadata
- [ ] Best-effort concurrency on gist read/write (race conditions acceptable, manually resolvable)

### Out of Scope

- Optimistic locking / strict concurrency control on gist — manual fix is acceptable for rare races
- Auto-creation of the shared gist — one team member creates it once and shares the ID
- Web UI or dashboard — CLI-only
- Conflict auto-resolution — detect and report, don't auto-fix merge conflicts
- Non-gitflow workflows — designed for feature branches merging to development

## Context

The team of 3 developers uses GSD with Claude Code to manage project planning. They follow gitflow: each dev works on feature branches and merges back to a development branch. The core pain is that GSD planning artifacts (ROADMAP.md, STATE.md, REQUIREMENTS.md, phase plans) use sequential numbering for milestones and phases, and parallel work causes collisions when two devs independently pick the same numbers.

Current workaround: devs message each other on Slack to "claim" numbers before running GSD commands. This is error-prone and slows everyone down.

The plugins are shell scripts (bash) that use the `gh` CLI for GitHub Gist access. Auth relies on each dev having `gh auth login` completed. The shared gist holds a JSON registry of claimed numbers, which branch they're on, and who claimed them.

## Constraints

- **Tech stack**: Bash scripts + `gh` CLI only — no additional runtime dependencies
- **Auth**: Relies on `gh auth login` being configured per developer
- **Gist setup**: Manual one-time creation — gist ID stored in a project config file
- **Concurrency**: Best-effort (read-then-write) — strict locking is out of scope
- **Hook types**: Claude Code hooks (settings.json) for GSD command interception + git hooks for merge-time validation

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| GitHub Gist for shared registry | No infra needed, accessible via `gh` API, avoids branch merge issues that a same-repo file would have | — Pending |
| Shell + `gh` CLI (no Node/Python) | Minimal dependencies, CC hooks run shell commands natively, whole team has `gh` installed | — Pending |
| Best-effort concurrency | Team of 3 — simultaneous runs are rare enough that manual resolution is acceptable | — Pending |
| Both CC hooks and git hooks | CC hooks automate number claiming at creation time; git hooks catch integrity issues at merge time | — Pending |
| Manual gist creation | Simpler than auto-create logic; one-time setup cost is negligible | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-19 after Phase 1 completion*
