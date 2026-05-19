# Roadmap: GSD Team Coordination Plugins

**Milestone:** 1
**Granularity:** coarse
**Mode:** mvp
**Created:** 2026-05-19

## Phases

- [x] **Phase 1: Registry & Allocation Core** - Shared gist registry library and automatic number claiming functions (completed 2026-05-19)
- [x] **Phase 2: CC Hook Integration** - PreToolUse on Bash intercepts gsd-sdk init calls for milestone/phase creation; terminal smoke tests pass; live CC session test deferred to next milestone (completed 2026-05-19)
- [ ] **Phase 3: Git Merge Validation** - Pre-merge-commit hook validates planning file integrity before merge to development
- [ ] **Phase 4: Setup & Release Lifecycle** - One-command install, onboarding docs, and stale entry cleanup

## Phase Details

### Phase 1: Registry & Allocation Core
**Goal:** Developers can claim the next available milestone or phase number from a shared GitHub Gist registry using library functions, with full metadata tracking and prerequisite validation.
**Mode:** mvp
**Depends on:** Nothing
**Requirements:** REG-01, REG-02, REG-03, REG-04, REG-05, ALLOC-01, ALLOC-02, ALLOC-03, ALLOC-04, ALLOC-05
**Success Criteria** (what must be TRUE):
  1. Developer can set a gist ID in a committed config file and all scripts read it from that location
  2. Any script that calls the library immediately fails with a clear error if `jq`, `gh`, or auth is missing
  3. Developer can run `read_registry()` and `write_registry()` calls that reliably round-trip JSON claims to/from the shared gist
  4. Developer can call the allocation function and receive the next available milestone or phase number, written to the registry with branch, owner, and timestamp
  5. Developer can set `GSD_DRY_RUN=1` to preview what number would be claimed without writing, and `GSD_VERBOSE=1` to see each gist API call
**Plans:** 3/3 plans complete

Plans:
**Wave 1**
- [x] 01-01-PLAN.md — Walking Skeleton: config file, common.sh, gist.sh, thin claim-number.sh end-to-end

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-02-PLAN.md — Allocation hardening: collision detection, retry loop, dry-run and verbose modes
- [x] 01-03-PLAN.md — Status command: gsd-status.sh formatted active claims table

### Phase 2: CC Hook Integration
**Goal:** Claude Code automatically intercepts `/gsd-new-milestone` and `/gsd-new-phase` commands and claims the next number from the registry before the GSD command executes, blocking on failure.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements:** HOOK-01, HOOK-02, HOOK-03, HOOK-04
**Success Criteria** (what must be TRUE):
  1. Running `/gsd-new-milestone` in a CC session triggers the hook before execution and the claimed number appears in the registry
  2. Running `/gsd-new-phase` in a CC session triggers the hook before execution and the claimed number appears in the registry
  3. When the hook encounters an error (gist unreachable, auth failure), it exits with code 2 and the GSD command is blocked — not silently skipped
  4. Hook stdout produces no shell profile contamination — output is clean JSON or empty
**Plans:** 2 plans

Plans:
**Wave 1**
- [x] 02-01-PLAN.md — settings.json wiring + both CC wrapper scripts (milestone and phase)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 02-02-PLAN.md — Live CC session verification: terminal smoke tests pass; pivot to PreToolUse on Bash; live CC session test deferred to next milestone (accepted-with-pending 2026-05-19)

### Phase 3: Git Merge Validation
**Goal:** Merging a feature branch to development triggers automated validation of planning file integrity, surfacing gaps, duplicates, and drift with exact actionable fix commands.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements:** VAL-01, VAL-02, VAL-03, VAL-04, VAL-05
**Success Criteria** (what must be TRUE):
  1. Merging a branch with a phase number gap in ROADMAP.md is blocked with the exact line and phase numbers that are out of sequence
  2. Merging a branch with a duplicate REQ-ID in REQUIREMENTS.md is blocked with the file, line number, and duplicate ID shown
  3. Merging a branch where STATE.md active phase does not match ROADMAP.md is blocked with the conflicting values shown
  4. Merging a branch with a plan referencing a removed requirement or phase is blocked with the stale reference and its location shown
  5. Every validation error message includes the file path, line number, and an exact command the developer can run to fix it
**Plans:** TBD

### Phase 4: Setup & Release Lifecycle
**Goal:** A new developer can join the team, run one install script, and be fully configured in under 5 minutes; stale registry entries from deleted or merged branches are cleaned up automatically.
**Mode:** mvp
**Depends on:** Phase 2, Phase 3
**Requirements:** SETUP-01, SETUP-02, SETUP-03
**Success Criteria** (what must be TRUE):
  1. Running the install script configures both the git hook (via `core.hooksPath`) and the CC hook entry in `settings.json` without manual edits
  2. The onboarding README lists prerequisites, the one-time gist creation step, and the install command — a developer with no prior context can follow it successfully
  3. When a branch is deleted or merged, its registry entries are automatically released so the numbers become available again
**Plans:** TBD

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Registry & Allocation Core | 3/3 | Complete | 2026-05-19 |
| 2. CC Hook Integration | 2/2 | Complete (accepted-with-pending) | 2026-05-19 |
| 3. Git Merge Validation | 0/? | Not started | - |
| 4. Setup & Release Lifecycle | 0/? | Not started | - |

---
*Roadmap created: 2026-05-19*
*Last updated: 2026-05-19 after Phase 2 plans created*
