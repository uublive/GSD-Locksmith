#!/usr/bin/env bash
# .gsd/tests/test-validate.sh — Fixture-based test harness for .gsd/lib/validate.sh
# Usage: bash .gsd/tests/test-validate.sh [gap|dup|drift|stale]
# Exit 0 = all selected tests pass; exit 1 = any failure
#
# No bats dependency — plain bash only.
# Functions are tested via TESTING_MODE=1 with GSD_TEST_* env vars injected,
# so no real git repo or staged files are needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_SH="$REPO_ROOT/.gsd/lib/validate.sh"

if [[ ! -f "$VALIDATE_SH" ]]; then
  echo "ERROR: .gsd/lib/validate.sh not found (expected at $VALIDATE_SH)" >&2
  exit 1
fi

# shellcheck source=../.gsd/lib/validate.sh
source "$VALIDATE_SH"

# ---------------------------------------------------------------------------
# Test runner helpers
# ---------------------------------------------------------------------------

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# run_test <name> <expected_exit_nonzero:0|1> [env var assignments...]
# Calls the named function in a subshell with the provided env vars.
# For "should fail" tests: verifies exit non-zero AND stderr contains ": ERROR:"
# For "should pass" tests: verifies exit 0 AND stderr is empty
run_test() {
  local test_name="$1"
  local expect_fail="$2"   # 1 = expect function to return non-zero
  local func_name="$3"
  shift 3
  # remaining args are "VAR=value" assignments

  local stderr_out
  local ret=0

  # Build env prefix from remaining args
  local env_prefix=""
  for assign in "$@"; do
    env_prefix="$env_prefix $assign"
  done

  # Run in subshell: source validate.sh, set env vars, call function
  stderr_out=$(
    # shellcheck disable=SC2030
    eval "export TESTING_MODE=1 $env_prefix"
    source "$VALIDATE_SH"
    "$func_name" 2>&1 >/dev/null
  ) || ret=$?

  if [[ "$expect_fail" -eq 1 ]]; then
    # Should detect a violation: non-zero exit AND ": ERROR:" in stderr
    if [[ "$ret" -ne 0 && "$stderr_out" == *": ERROR:"* ]]; then
      pass "$test_name"
    elif [[ "$ret" -eq 0 ]]; then
      fail "$test_name — expected non-zero exit, got 0 (no violation detected)"
    else
      fail "$test_name — non-zero exit but no ': ERROR:' in output: $stderr_out"
    fi
  else
    # Should pass clean: exit 0 AND no output
    if [[ "$ret" -eq 0 ]]; then
      pass "$test_name"
    else
      fail "$test_name — expected exit 0, got $ret; output: $stderr_out"
    fi
  fi
}

# ---------------------------------------------------------------------------
# VAL-01 Fixtures: check_phase_gaps
# ---------------------------------------------------------------------------

# Bad: phases 1, 2, 4 — gap at 3
FIXTURE_GAP_BAD=$(cat <<'EOF'
# GSD Team Coordination Plugins — ROADMAP

## Phases

- [x] **Phase 1: Registry Core** - Allocation via Gist
- [x] **Phase 2: Claude Code Hooks** - Command interception
- [ ] **Phase 4: Setup and Distribution** - Packaging
EOF
)

# Good: phases 1, 2, 3, 4 — sequential
FIXTURE_GAP_GOOD=$(cat <<'EOF'
# GSD Team Coordination Plugins — ROADMAP

## Phases

- [x] **Phase 1: Registry Core** - Allocation via Gist
- [x] **Phase 2: Claude Code Hooks** - Command interception
- [ ] **Phase 3: Git Merge Validation** - Pre-merge checks
- [ ] **Phase 4: Setup and Distribution** - Packaging
EOF
)

run_val01_tests() {
  echo ""
  echo "VAL-01: check_phase_gaps"
  run_test "gap_bad (phases 1,2,4 — gap at 3 detected)" 1 check_phase_gaps \
    "GSD_TEST_ROADMAP=$(printf '%q' "$FIXTURE_GAP_BAD")"
  run_test "gap_good (phases 1,2,3,4 — no gap)" 0 check_phase_gaps \
    "GSD_TEST_ROADMAP=$(printf '%q' "$FIXTURE_GAP_GOOD")"
}

# ---------------------------------------------------------------------------
# VAL-02 Fixtures: check_duplicate_req_ids
# ---------------------------------------------------------------------------

# Bad: REG-01 appears twice
FIXTURE_DUP_BAD=$(cat <<'EOF'
# Requirements

| ID | Description |
|----|-------------|
| **REG-01**: Registry must store claimed numbers | — |
| **REG-02**: Registry must store branch name | — |
| **REG-01**: Duplicate entry for registry | — |
| **REG-03**: Registry must support concurrency | — |
EOF
)

# Good: no duplicates
FIXTURE_DUP_GOOD=$(cat <<'EOF'
# Requirements

| ID | Description |
|----|-------------|
| **REG-01**: Registry must store claimed numbers | — |
| **REG-02**: Registry must store branch name | — |
| **REG-03**: Registry must support concurrency | — |
EOF
)

run_val02_tests() {
  echo ""
  echo "VAL-02: check_duplicate_req_ids"
  run_test "dup_bad (REG-01 appears twice — duplicate detected)" 1 check_duplicate_req_ids \
    "GSD_TEST_REQUIREMENTS=$(printf '%q' "$FIXTURE_DUP_BAD")"
  run_test "dup_good (no duplicates)" 0 check_duplicate_req_ids \
    "GSD_TEST_REQUIREMENTS=$(printf '%q' "$FIXTURE_DUP_GOOD")"
}

# ---------------------------------------------------------------------------
# VAL-03 Fixtures: check_state_drift
# ---------------------------------------------------------------------------

# Bad: STATE.md says total_phases: 3 but ROADMAP.md has 4 phases
FIXTURE_DRIFT_STATE_BAD=$(cat <<'EOF'
---
gsd_state_version: 1.0
milestone: v1.0
status: executing
progress:
  total_phases: 3
  completed_phases: 2
---

# STATE

## Current Position

**Phase:** 3
EOF
)

# For DRIFT BAD test, use a roadmap with 4 phases (mismatch with total_phases: 3 above)
FIXTURE_DRIFT_ROADMAP_4=$(cat <<'EOF'
# ROADMAP

## Phases

- [x] **Phase 1: Registry Core** - Done
- [x] **Phase 2: Claude Code Hooks** - Done
- [ ] **Phase 3: Git Merge Validation** - In progress
- [ ] **Phase 4: Setup and Distribution** - Pending
EOF
)

# Good: STATE.md total_phases: 4 matches ROADMAP.md's 4 phases; active phase 3 exists
FIXTURE_DRIFT_STATE_GOOD=$(cat <<'EOF'
---
gsd_state_version: 1.0
milestone: v1.0
status: executing
progress:
  total_phases: 4
  completed_phases: 2
---

# STATE

## Current Position

**Phase:** 3
EOF
)

run_val03_tests() {
  echo ""
  echo "VAL-03: check_state_drift"
  run_test "drift_bad (total_phases:3 vs roadmap 4 phases — mismatch detected)" 1 check_state_drift \
    "GSD_TEST_STATE=$(printf '%q' "$FIXTURE_DRIFT_STATE_BAD")" \
    "GSD_TEST_ROADMAP=$(printf '%q' "$FIXTURE_DRIFT_ROADMAP_4")"
  run_test "drift_good (total_phases:4 matches roadmap 4 phases; active phase 3 exists)" 0 check_state_drift \
    "GSD_TEST_STATE=$(printf '%q' "$FIXTURE_DRIFT_STATE_GOOD")" \
    "GSD_TEST_ROADMAP=$(printf '%q' "$FIXTURE_DRIFT_ROADMAP_4")"
}

# ---------------------------------------------------------------------------
# VAL-04 Fixtures: check_stale_refs
# ---------------------------------------------------------------------------

# Bad: PLAN.md frontmatter references REMOVED-99 which is not in REQUIREMENTS.md
FIXTURE_STALE_PLAN_BAD=$(cat <<'EOF'
---
phase: 01-test
plan: 01
requirements:
  - REG-01
  - REMOVED-99
---

## Plan content here
EOF
)

# For STALE BAD test, REQUIREMENTS.md has only REG-01 (no REMOVED-99)
FIXTURE_STALE_REQS=$(cat <<'EOF'
# Requirements

| ID | Description |
|----|-------------|
| **REG-01**: Registry must store claimed numbers | — |
| **REG-02**: Registry must store branch name | — |
EOF
)

# Good: PLAN.md frontmatter only references valid REQ-IDs
FIXTURE_STALE_PLAN_GOOD=$(cat <<'EOF'
---
phase: 01-test
plan: 01
requirements:
  - REG-01
  - REG-02
---

## Plan content here
EOF
)

run_val04_tests() {
  echo ""
  echo "VAL-04: check_stale_refs"
  run_test "stale_bad (plan references REMOVED-99 not in requirements — detected)" 1 check_stale_refs \
    "GSD_TEST_PLAN_CONTENT=$(printf '%q' "$FIXTURE_STALE_PLAN_BAD")" \
    "GSD_TEST_PLAN_PATH='.planning/phases/01-test/01-01-PLAN.md'" \
    "GSD_TEST_REQUIREMENTS=$(printf '%q' "$FIXTURE_STALE_REQS")"
  run_test "stale_good (plan references only valid REQ-IDs)" 0 check_stale_refs \
    "GSD_TEST_PLAN_CONTENT=$(printf '%q' "$FIXTURE_STALE_PLAN_GOOD")" \
    "GSD_TEST_PLAN_PATH='.planning/phases/01-test/01-01-PLAN.md'" \
    "GSD_TEST_REQUIREMENTS=$(printf '%q' "$FIXTURE_STALE_REQS")"
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

FILTER="${1:-all}"

case "$FILTER" in
  gap)   run_val01_tests ;;
  dup)   run_val02_tests ;;
  drift) run_val03_tests ;;
  stale) run_val04_tests ;;
  all)
    run_val01_tests
    run_val02_tests
    run_val03_tests
    run_val04_tests
    ;;
  *)
    echo "Usage: $0 [gap|dup|drift|stale]" >&2
    exit 1
    ;;
esac

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
