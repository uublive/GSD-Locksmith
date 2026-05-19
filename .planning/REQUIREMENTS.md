# Requirements: GSD Team Coordination Plugins

**Defined:** 2026-05-19
**Core Value:** No more manual Slack coordination to claim milestone and phase numbers — the tooling handles it automatically so the team can work independently without collisions.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Registry

- [ ] **REG-01**: Developer can configure shared gist ID in committed project config file
- [ ] **REG-02**: Registry stores milestone/phase claims with branch, owner, and timestamp metadata
- [ ] **REG-03**: Shell library provides `read_registry()` and `write_registry()` functions for all gist operations
- [ ] **REG-04**: Developer can view all active claims with `gsd-status` (who, what number, which branch)
- [ ] **REG-05**: Every script validates `jq`, `gh`, and auth status before executing

### Allocation

- [ ] **ALLOC-01**: System claims next available milestone number from registry automatically
- [ ] **ALLOC-02**: System claims next available phase number within a milestone from registry automatically
- [ ] **ALLOC-03**: System detects last-write-wins race and displays collision warning with rollback instructions
- [ ] **ALLOC-04**: Developer can preview allocation without writing via `GSD_DRY_RUN=1` env var
- [ ] **ALLOC-05**: Developer can see detailed operation logs via `GSD_VERBOSE=1` env var

### Hooks

- [ ] **HOOK-01**: CC PreToolUse hook intercepts `/gsd-new-milestone` and claims number before execution
- [ ] **HOOK-02**: CC PreToolUse hook intercepts `/gsd-new-phase` and claims number before execution
- [ ] **HOOK-03**: Hooks use exit code 2 (not 1) to block on failure — verified by test
- [ ] **HOOK-04**: Hook stdout/stderr is clean (no shell profile contamination)

### Validation

- [ ] **VAL-01**: Git pre-merge-commit hook detects phase numbering gaps in ROADMAP.md
- [ ] **VAL-02**: Git pre-merge-commit hook detects duplicate REQ-IDs in REQUIREMENTS.md
- [ ] **VAL-03**: Git pre-merge-commit hook detects STATE.md drift (active phase doesn't match ROADMAP.md)
- [ ] **VAL-04**: Git pre-merge-commit hook detects stale cross-references (plans referencing removed requirements/phases)
- [ ] **VAL-05**: Validation errors show file, line, and exact fix command

### Setup

- [ ] **SETUP-01**: One-command install script configures git hooks and CC hook settings
- [ ] **SETUP-02**: Onboarding README documents prerequisites and setup checklist
- [ ] **SETUP-03**: Stale registry entries are auto-released when branches are deleted or merged

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Workflow Extensions

- **EXT-01**: Configurable branch naming patterns for non-standard gitflow setups
- **EXT-02**: Support for monorepo workspaces with multiple GSD projects

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Strict locking / pessimistic concurrency | Requires server infra (Redis, DB); team of 3 — race is rare enough for manual fix |
| Auto-creation of shared gist | Race on first use could create split registries that silently diverge |
| Conflict auto-resolution on merge | Wrong auto-merge is worse than unresolved conflict — detect and report only |
| Web UI or dashboard | CLI-only project; `gsd-status` covers the visibility need from terminal |
| Non-gitflow workflow support | Designed for feature branches -> development; supporting trunk-based is scope creep |
| Semantic versioning / changelog | Internal bash scripts for 3-person team, not a published library |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| REG-01 | — | Pending |
| REG-02 | — | Pending |
| REG-03 | — | Pending |
| REG-04 | — | Pending |
| REG-05 | — | Pending |
| ALLOC-01 | — | Pending |
| ALLOC-02 | — | Pending |
| ALLOC-03 | — | Pending |
| ALLOC-04 | — | Pending |
| ALLOC-05 | — | Pending |
| HOOK-01 | — | Pending |
| HOOK-02 | — | Pending |
| HOOK-03 | — | Pending |
| HOOK-04 | — | Pending |
| VAL-01 | — | Pending |
| VAL-02 | — | Pending |
| VAL-03 | — | Pending |
| VAL-04 | — | Pending |
| VAL-05 | — | Pending |
| SETUP-01 | — | Pending |
| SETUP-02 | — | Pending |
| SETUP-03 | — | Pending |

**Coverage:**
- v1 requirements: 22 total
- Mapped to phases: 0
- Unmapped: 22

---
*Requirements defined: 2026-05-19*
*Last updated: 2026-05-19 after initial definition*
