---
phase: 03-git-merge-validation
verified: 2026-05-20T00:00:00Z
status: human_needed
score: 9/10 must-haves verified
overrides_applied: 0
re_verification: false
human_verification:
  - test: "Activate hook with 'git config core.hooksPath .githooks', checkout development branch, attempt 'git merge' from a feature branch that has a seeded ROADMAP.md phase gap, confirm merge is BLOCKED with compiler-style error"
    expected: "git aborts the merge and prints '.planning/ROADMAP.md:LINE: ERROR: Phase gap -- expected Phase N found Phase M' followed by the Fix: command; exit code 1"
    why_human: "Requires a live git merge against an actual development branch. Cannot simulate pre-merge-commit hook firing without a real git merge context. core.hooksPath is not set in this clone (verified: 'git config core.hooksPath' returned empty). All validation logic passes 8/8 unit tests, but end-to-end hook firing is untestable without a git merge operation."
---

# Phase 3: Git Merge Validation Verification Report

**Phase Goal:** Merging a feature branch to development triggers automated validation of planning file integrity, surfacing gaps, duplicates, and drift with exact actionable fix commands.
**Verified:** 2026-05-20
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | check_phase_gaps() detects phase gaps, returns non-zero, emits compiler-style error naming missing phase and line | VERIFIED | `bash tests/test-validate.sh gap` exits 0; live probe emits `.planning/ROADMAP.md:3: ERROR: Phase gap -- expected Phase 3 found Phase 4` |
| 2 | check_duplicate_req_ids() detects duplicate REQ-IDs, returns non-zero, emits file/line/ID | VERIFIED | `bash tests/test-validate.sh dup` exits 0; live probe emits `.planning/REQUIREMENTS.md:2: ERROR: Duplicate REQ-ID REG-01` |
| 3 | check_state_drift() detects total_phases mismatch, returns non-zero, names both values and fix command | VERIFIED | `bash tests/test-validate.sh drift` exits 0; error format confirmed with STATE.md line number and both values |
| 4 | check_stale_refs() detects plan referencing removed REQ-ID, returns non-zero, names stale ID and plan file | VERIFIED | `bash tests/test-validate.sh stale` exits 0; error format confirmed with plan path and stale ID |
| 5 | bash tests/test-validate.sh exits 0 when all four validation functions pass all fixture cases | VERIFIED | `bash tests/test-validate.sh` produces "Results: 8 passed, 0 failed" and exits 0 |
| 6 | Every error line emitted to stderr matches 'file:line: ERROR:' pattern and is followed by indented Fix: command | VERIFIED | Live probes confirm both patterns. e.g. `.planning/ROADMAP.md:3: ERROR: Phase gap -- expected Phase 3 found Phase 4` + `  Fix: add Phase 3 entry...` |
| 7 | Merging any feature branch into development triggers .githooks/pre-merge-commit automatically | UNCERTAIN | Hook file exists, is executable (chmod 750), syntax-clean. But `git config core.hooksPath` is not set in this clone — activation is a one-command developer step. End-to-end trigger cannot be verified programmatically without a live merge. |
| 8 | When validate.sh detects violations, pre-merge-commit exits 1 and git aborts the merge | UNCERTAIN | Code path verified by inspection: ERRORS accumulates all function returns; `if [[ "$ERRORS" -gt 0 ]]; then ... exit 1; fi` is present and correct. Live merge-blocking behavior deferred (human checkpoint approved-deferred in 03-02-SUMMARY.md). |
| 9 | When no violations exist, pre-merge-commit exits 0 and the merge completes normally | VERIFIED | Exit 0 path is code-verified; unit tests confirm all four check functions return 0 on clean fixtures |
| 10 | Merging to a non-development branch skips validation and exits 0 (D-08) | VERIFIED | Branch filter `if [[ "$CURRENT_BRANCH" != "development" && "$CURRENT_BRANCH" != "develop" ]]; then exit 0; fi` is present and correctly placed before any validation logic |

**Score:** 8/10 truths fully verified (2 UNCERTAIN pending live merge test — accepted-deferred per user checkpoint)

---

### Roadmap Success Criteria Coverage

| SC | Criterion | Status | Evidence |
|----|-----------|--------|----------|
| SC-1 | Merging a branch with a phase number gap is blocked with exact line and phase numbers | UNCERTAIN (human needed) | check_phase_gaps() emits exact format; hook code path correct; live block not verified |
| SC-2 | Merging a branch with a duplicate REQ-ID is blocked with file, line, and ID | UNCERTAIN (human needed) | check_duplicate_req_ids() emits exact format; hook code path correct; live block not verified |
| SC-3 | Merging a branch where STATE.md active phase does not match ROADMAP.md is blocked with conflicting values | UNCERTAIN (human needed) | check_state_drift() emits conflicting values; hook code path correct; live block not verified |
| SC-4 | Merging a branch with a plan referencing a removed requirement is blocked with stale reference and location | UNCERTAIN (human needed) | check_stale_refs() emits location; hook code path correct; live block not verified |
| SC-5 | Every validation error message includes file path, line number, and exact fix command | VERIFIED | All four functions confirmed via live probes to emit `file:line: ERROR: message` + `  Fix: command` |

Note: SC-1 through SC-4 are UNCERTAIN only at the git hook trigger layer. The validation logic powering them is fully verified by 8/8 passing unit tests. The UNCERTAIN status is isolated to whether git actually invokes the hook (requires core.hooksPath set and a live merge).

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `hooks/lib/validate.sh` | check_phase_gaps, check_duplicate_req_ids, check_state_drift, check_stale_refs; min 100 lines | VERIFIED | 308 lines; all four functions present; bash -n passes; chmod 644 (library) |
| `tests/test-validate.sh` | Fixture-based test runner for all four functions; exit 0 = all pass; min 60 lines | VERIFIED | 308 lines; 8 tests (2 per function); exits 0; executable (chmod 755) |
| `.githooks/pre-merge-commit` | Thin wrapper with branch filter, source validate.sh, 4-check accumulator, exit decision; min 25 lines | VERIFIED | 45 lines; executable (chmod 750); bash -n passes |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| tests/test-validate.sh | hooks/lib/validate.sh | `source "$VALIDATE_SH"` | WIRED | Line 22: `source "$VALIDATE_SH"` where VALIDATE_SH resolved via REPO_ROOT; also re-sourced in subshell at line 58 |
| .githooks/pre-merge-commit | hooks/lib/validate.sh | `source "$REPO_ROOT/hooks/lib/validate.sh"` | WIRED | Line 20: exact pattern present |
| .githooks/pre-merge-commit | git merge target detection | `git rev-parse --abbrev-ref HEAD` | WIRED | Line 25: `CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"` |
| four check functions | ERRORS accumulator | `ERRORS=$((ERRORS + $?))` | WIRED | Lines 35-38: all four calls use `|| ERRORS=$((ERRORS + $?))` pattern |
| check_phase_gaps (production) | .planning/ROADMAP.md (staged) | `git show :.planning/ROADMAP.md` | WIRED | Line 36 of validate.sh: present in else-branch; TESTING_MODE guard at line 33 |
| check_state_drift (production) | .planning/STATE.md (staged) | `git show :.planning/STATE.md` | WIRED | Line 157 of validate.sh: present in else-branch |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase produces shell library functions and a git hook, not components that render dynamic data. All data flows are through bash function return codes and stderr output, verified by the unit test suite.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| check_phase_gaps detects gap at phase 3 | `TESTING_MODE=1 GSD_TEST_ROADMAP=... bash -c 'source hooks/lib/validate.sh; check_phase_gaps'` | `.planning/ROADMAP.md:3: ERROR: Phase gap -- expected Phase 3 found Phase 4` + exit 1 | PASS |
| check_duplicate_req_ids detects REG-01 duplicate | `TESTING_MODE=1 GSD_TEST_REQUIREMENTS=... bash -c 'source hooks/lib/validate.sh; check_duplicate_req_ids'` | `.planning/REQUIREMENTS.md:2: ERROR: Duplicate REQ-ID REG-01` + exit 1 | PASS |
| Full test suite 8/8 | `bash tests/test-validate.sh` | "Results: 8 passed, 0 failed", exit 0 | PASS |
| Individual suite filters | `bash tests/test-validate.sh gap/dup/drift/stale` | Each exits 0 with "2 passed, 0 failed" | PASS |
| validate.sh syntax check | `bash -n hooks/lib/validate.sh` | exit 0 | PASS |
| pre-merge-commit syntax check | `bash -n .githooks/pre-merge-commit` | exit 0 | PASS |
| No exit calls in validate.sh function bodies | `grep '\bexit\b' hooks/lib/validate.sh` | Only awk-internal `exit` at line 287 (inside awk program, not bash); comment references only | PASS |
| No exit 2 in hook | `grep 'exit 2' .githooks/pre-merge-commit` | No output — only exit 0 and exit 1 used | PASS |
| pre-merge-commit executable (chmod 750) | `ls -la .githooks/pre-merge-commit` | `-rwxr-x---` | PASS |
| Live merge-blocking test | `git merge` against development branch with seeded violation | NOT RUN (core.hooksPath not configured; deferred per human checkpoint) | SKIP — human needed |

---

### Probe Execution

No formal probe scripts declared in PLAN frontmatter or present at `scripts/*/tests/probe-*.sh`. The equivalent verification is `bash tests/test-validate.sh` which was run directly above.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| VAL-01 | 03-01-PLAN.md, 03-02-PLAN.md | Git pre-merge-commit hook detects phase numbering gaps in ROADMAP.md | SATISFIED | check_phase_gaps() implemented and tested; hook wired; gap_bad and gap_good fixtures pass |
| VAL-02 | 03-01-PLAN.md, 03-02-PLAN.md | Git pre-merge-commit hook detects duplicate REQ-IDs in REQUIREMENTS.md | SATISFIED | check_duplicate_req_ids() implemented and tested; dup_bad and dup_good fixtures pass |
| VAL-03 | 03-01-PLAN.md, 03-02-PLAN.md | Git pre-merge-commit hook detects STATE.md drift | SATISFIED | check_state_drift() implemented and tested; drift_bad and drift_good fixtures pass |
| VAL-04 | 03-01-PLAN.md, 03-02-PLAN.md | Git pre-merge-commit hook detects stale cross-references | SATISFIED | check_stale_refs() implemented and tested; stale_bad and stale_good fixtures pass |
| VAL-05 | 03-01-PLAN.md, 03-02-PLAN.md | Validation errors show file, line, and exact fix command | SATISFIED | All four functions emit `file:line: ERROR: message` + `  Fix: command` confirmed by live probes |

All five requirements are SATISFIED at the logic and wiring level. Full end-to-end satisfaction (hook actually fires in git merge) requires human verification.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| hooks/lib/validate.sh | 287 | `exit` inside awk program | INFO | Not a bash exit; awk's `exit` statement is correct and expected here to terminate awk early after fm>=2 block |

No debt markers (TBD, FIXME, XXX), no unimplemented stubs, no hardcoded empty returns, no placeholder UI found in any file modified by this phase.

---

### Human Verification Required

#### 1. Live Merge-Blocking Test

**Test:** Run `git config core.hooksPath .githooks` in this clone. Create a feature branch. Edit `.planning/ROADMAP.md` to introduce a phase gap (e.g., list phases 1, 2, 4 — skip 3). Commit the change. Checkout `development` branch. Run `git merge <feature-branch>`.

**Expected:** git aborts the merge and prints:
```
.planning/ROADMAP.md:LINE: ERROR: Phase gap -- expected Phase 3 found Phase 4
  Fix: add Phase 3 entry before line LINE, or renumber phases sequentially
.planning: 1 integrity violation(s). Fix above errors and retry the merge.
```
Git then reports the hook aborted the merge (exit code 1). After running `git merge --abort`, confirm the merge did not complete.

**Why human:** The `pre-merge-commit` hook only fires when git actually executes a merge. `core.hooksPath` is not set in this clone (verified). The validation logic powering the hook passes 8/8 unit tests — this test verifies only the OS-level hook invocation and git integration, not the validation logic itself. This was accepted-deferred by the user (checkpoint approved-deferred in 03-02-SUMMARY.md) alongside the Phase 2 CC hook live session test.

---

### Gaps Summary

No implementation gaps found. All four validation functions exist, are substantive (308 lines each for validate.sh and test harness), are correctly wired together, and produce the required compiler-style error format.

The only open item is the live merge-blocking integration test (human_verification item #1), which was explicitly deferred by the user at the Task 2 human-verify checkpoint. This is not a code gap — it is an environment activation step (`git config core.hooksPath .githooks`) plus a live git merge smoke test.

---

_Verified: 2026-05-20_
_Verifier: Claude (gsd-verifier)_
