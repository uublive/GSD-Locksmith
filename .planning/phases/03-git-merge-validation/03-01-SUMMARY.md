---
phase: 03-git-merge-validation
plan: 01
subsystem: testing
tags: [bash, git-hooks, validation, grep, awk, markdown-parsing]

# Dependency graph
requires: []
provides:
  - "hooks/lib/validate.sh: check_phase_gaps, check_duplicate_req_ids, check_state_drift, check_stale_refs functions"
  - "tests/test-validate.sh: fixture-based test harness for all four validation functions"
affects: [03-git-merge-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TESTING_MODE=1 + GSD_TEST_* env vars for injecting fixture content into functions without a live git repo"
    - "Temp file pattern for error counting across subshell boundaries: mktemp + grep -cE + cat + rm -f"
    - "BSD-awk-safe gap detection: split on literal string instead of three-arg match() (gawk-only)"
    - "grep -oE + sed for REQ-ID extraction; sort | uniq -d for duplicate detection"

key-files:
  created:
    - hooks/lib/validate.sh
    - tests/test-validate.sh
  modified: []

key-decisions:
  - "TESTING_MODE=1 pattern chosen over parameter injection: cleaner function signatures, no production callers affected"
  - "BSD awk split() instead of three-arg match() for gap detection: match(s, re, arr) is gawk-only, not available on macOS BSD awk"
  - "Temp file for duplicate and stale-ref error counting: avoids subshell variable loss from pipe-into-while pattern"
  - "sed to extract phase number after **Phase:** prefix: grep -oE '[0-9]+' | head -1 on grep -n output extracts line number not value"

patterns-established:
  - "Validation function structure: local vars, TESTING_MODE check, content load, error logic, return errors"
  - "Error format: file:line: ERROR: message on stderr, followed by two-space-indented Fix: line"
  - "All grep -c calls append || true to prevent set -e trap on zero-match exit code 1"

requirements-completed: [VAL-01, VAL-02, VAL-03, VAL-04, VAL-05]

# Metrics
duration: 35min
completed: 2026-05-20
---

# Phase 3 Plan 01: Validation Library Summary

**Four planning-file integrity functions in hooks/lib/validate.sh using TESTING_MODE fixture injection, all passing 8-test fixture harness in tests/test-validate.sh**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-05-20T10:40:00Z
- **Completed:** 2026-05-20T11:15:00Z
- **Tasks:** 2 (TDD: RED + GREEN)
- **Files modified:** 2 created

## Accomplishments

- `check_phase_gaps`: detects non-sequential phase numbering in ROADMAP.md via BSD-awk-safe state tracking
- `check_duplicate_req_ids`: finds duplicate REQ-IDs in REQUIREMENTS.md via sort/uniq -d with two-pass line-number lookup
- `check_state_drift`: cross-checks STATE.md total_phases and active phase against ROADMAP.md counts
- `check_stale_refs`: scans PLAN.md frontmatter requirements fields for REQ-IDs absent from REQUIREMENTS.md
- All functions use compiler-style errors (file:line: ERROR: message + Fix: command); return not exit; TESTING_MODE=1 for testability

## Task Commits

1. **Task 1: Write test fixture scaffold** - `ea8ec9f` (test — TDD RED)
2. **Task 2: Implement hooks/lib/validate.sh** - `c001a06` (feat — TDD GREEN)

**Plan metadata:** pending (docs commit follows)

_TDD tasks: test commit (RED) then feat commit (GREEN)_

## TDD Gate Compliance

- RED gate: `ea8ec9f` — `test(03-01): add failing fixture harness for validate.sh functions`
- GREEN gate: `c001a06` — `feat(03-01): implement hooks/lib/validate.sh with four validation functions`
- Both gates present in correct order. No REFACTOR commit needed.

## Files Created/Modified

- `hooks/lib/validate.sh` — Library with four validation functions; sourced by pre-merge-commit hook in plan 03-02
- `tests/test-validate.sh` — Fixture-based test runner; `bash tests/test-validate.sh` exits 0 with 8 passed, 0 failed

## Decisions Made

- **TESTING_MODE=1 pattern:** Functions check `${TESTING_MODE:-0}` before calling `git show`; when set, read from `GSD_TEST_ROADMAP`, `GSD_TEST_REQUIREMENTS`, `GSD_TEST_STATE`, `GSD_TEST_PLAN_CONTENT`, `GSD_TEST_PLAN_PATH`. Allows complete isolation from git in tests.
- **BSD awk split() for gap detection:** macOS ships BSD awk which does not support three-argument `match(str, re, arr)` (gawk extension). Used `split(line, parts, "Phase ")` instead to extract phase numbers. Verified against RESEARCH.md "Simpler awk approach" note.
- **Temp file for error counting:** `check_duplicate_req_ids` and `check_stale_refs` use `mktemp` + append to file + `grep -cE` + `cat >&2` + `rm -f`. Avoids subshell counter loss from pipe-into-while loops (Pitfall 1 from RESEARCH.md).
- **sed for active phase extraction in check_state_drift:** `grep -n '^\*\*Phase:\*\*'` output is `LINE:**Phase:** N`; `grep -oE '[0-9]+' | head -1` would return LINE not N. Used `sed 's/.*\*\*Phase:\*\*[[:space:]]*//'` to strip prefix before extracting number.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed active phase number extraction extracting line number instead of value**
- **Found during:** Task 2 (implement check_state_drift) — discovered during test run
- **Issue:** `grep -n '^\*\*Phase:\*\*' | head -1` produces output like `14:**Phase:** 3`; applying `grep -oE '[0-9]+' | head -1` to that extracts `14` (line number) not `3` (phase number). The drift_good test was failing with "Active phase 14 not found in ROADMAP.md"
- **Fix:** Changed extraction to `sed 's/.*\*\*Phase:\*\*[[:space:]]*//' | grep -oE '^[0-9]+'` which strips the grep-n prefix before extracting the integer
- **Files modified:** hooks/lib/validate.sh (check_state_drift function)
- **Verification:** `drift_good` test passes; `drift_bad` still passes; full suite 8 passed 0 failed
- **Committed in:** `c001a06` (Task 2 feat commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Required for correctness. Line number vs value confusion was a logic bug in initial implementation. No scope creep.

## Issues Encountered

None beyond the auto-fixed bug above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `hooks/lib/validate.sh` is ready to be sourced by `.githooks/pre-merge-commit` (plan 03-02)
- All four functions tested and passing with fixture content
- TESTING_MODE pattern documented for any future test additions
- Known limitation: `check_stale_refs` in production uses `git ls-files` which only lists tracked files; newly-untracked plan files would be skipped (documented in RESEARCH.md Assumption A1 — acceptable for MVP)

---
*Phase: 03-git-merge-validation*
*Completed: 2026-05-20*
