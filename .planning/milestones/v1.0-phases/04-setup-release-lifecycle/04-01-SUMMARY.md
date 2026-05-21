---
phase: 04-setup-release-lifecycle
plan: 01
subsystem: infra
tags: [bash, jq, git-hooks, cc-hooks, settings.json, onboarding]

# Dependency graph
requires:
  - phase: 02-cc-hook-integration
    provides: .claude/settings.json CC hook wiring and hooks/cc-pretool-claim.sh
  - phase: 03-git-merge-validation
    provides: .githooks/pre-merge-commit hook and core.hooksPath configuration pattern
provides:
  - scripts/install-hooks.sh: idempotent one-command installer for git and CC hooks
  - README-HOOKS.md: complete onboarding doc for new team members (prereqs, setup, verification, troubleshooting)
affects: [any new developer clone, phase-04-02-post-merge-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Idempotent installer: check-before-write with jq select on existing settings.json content"
    - "Atomic JSON write: jq to tmpfile, jq -e validation, then mv to final path (T-04-01)"
    - "Prerequisite guard: jq, git, .claude/gsd-team.json existence, gist_id non-empty before any side effects"

key-files:
  created:
    - scripts/install-hooks.sh
    - README-HOOKS.md
  modified: []

key-decisions:
  - "Use jq select(.command | test()) to detect existing CC hook entry — avoids string-matching the full JSON object"
  - "Atomic write via mktemp + jq -e validate + mv — prevents corrupt settings.json if jq fails mid-write (T-04-01 mitigation)"
  - "README One-time Setup separated into team-lead step (gist creation) vs every-developer step (install) — prevents confusion on who does what"

patterns-established:
  - "Install script pattern: set -euo pipefail, REPO_ROOT from git rev-parse, prereq checks first, idempotency check before each write"

requirements-completed: [SETUP-01, SETUP-02]

# Metrics
duration: 25min
completed: 2026-05-20
---

# Phase 4 Plan 01: Install Script + Onboarding README Summary

**Idempotent one-command installer (scripts/install-hooks.sh) wires git core.hooksPath and merges CC PreToolUse hook into settings.json; README-HOOKS.md provides full onboarding from prerequisites to troubleshooting.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-05-20T14:22:00Z
- **Completed:** 2026-05-20T14:47:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- scripts/install-hooks.sh created — validates jq/gsd-team.json prereqs, sets git config core.hooksPath .githooks, and merges CC hook entry into .claude/settings.json without destroying existing content. Atomic write via tmpfile prevents corruption. Idempotent: second run prints "already configured" without duplicating entries.
- README-HOOKS.md created — covers Prerequisites (jq, gh, gh auth), One-time Setup (gist creation, config, installer), Verification commands, Usage (CC hooks + git hooks), and Troubleshooting (three most common errors with fix commands).
- All existing tests still pass: 8 passed, 0 failed (bash tests/test-validate.sh).

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/install-hooks.sh** - `62de9c1` (feat)
2. **Task 2: Create README-HOOKS.md onboarding doc** - `a8fc36b` (docs)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified

- `/scripts/install-hooks.sh` — One-command idempotent installer for git and CC hooks. chmod 750. Validates prereqs (jq, gsd-team.json with non-empty gist_id), sets core.hooksPath, merges PreToolUse entry.
- `/README-HOOKS.md` — Complete onboarding guide: Prerequisites, One-time Setup (3 steps), Verification (4 commands), Usage summary, Troubleshooting (3 common errors).

## Decisions Made

- Used `jq select(.command | test("cc-pretool-claim\\.sh"))` to detect existing CC hook entry. This is more robust than string-matching JSON structure since it only checks the relevant field.
- Atomic write: jq to tmpfile, validate with `jq -e`, then `mv` to replace original. Prevents partial/corrupt writes if jq fails (T-04-01 mitigation).
- README One-time Setup separates team-lead actions (gist creation) from per-developer actions (install). Prevents confusion about who does what step.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. The existing `.claude/settings.json` already had the CC hook entry from Phase 2, so the idempotency check was exercised on first run: "CC hook already configured in .claude/settings.json — skipping".

## User Setup Required

None - no external service configuration required. Gist ID is already set in `.claude/gsd-team.json`.

## Next Phase Readiness

- SETUP-01 and SETUP-02 complete: install script + onboarding doc delivered.
- Ready for 04-02: post-merge stale cleanup hook (SETUP-03).
- New developers can now run `bash scripts/install-hooks.sh` and be fully configured in under 5 minutes.

## Known Stubs

None.

## Threat Flags

None. The install script does not introduce new network endpoints, auth paths, or schema changes beyond what was already present. The atomic write pattern addresses T-04-01 (settings.json tampering via corrupt jq output).

## Self-Check: PASSED

- FOUND: scripts/install-hooks.sh
- FOUND: README-HOOKS.md
- FOUND: 04-01-SUMMARY.md
- FOUND: commit 62de9c1 (feat: install script)
- FOUND: commit a8fc36b (docs: README-HOOKS.md)
- FOUND: commit 12fced9 (docs: plan metadata)

---
*Phase: 04-setup-release-lifecycle*
*Completed: 2026-05-20*
