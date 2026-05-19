---
phase: 01-registry-allocation-core
plan: 01
subsystem: infra
tags: [bash, gh-cli, jq, github-gist, shell-scripts]

requires: []

provides:
  - ".claude/gsd-team.json — committed config with gist_id and project fields"
  - "hooks/lib/common.sh — check_deps(), load_config(), verbose_log() functions"
  - "hooks/lib/gist.sh — read_registry() and write_registry() via GitHub Gist"
  - "hooks/claim-number.sh — end-to-end milestone and phase number allocation"

affects:
  - 01-02
  - 02-cc-hooks
  - 03-git-hooks

tech-stack:
  added: [bash, gh-cli, jq, mktemp, github-gist]
  patterns:
    - "source-and-function library pattern (common.sh, gist.sh)"
    - "max+1 allocation with empty-array guard via jq"
    - "read-modify-write gist update via temp file + gh gist edit"
    - "dual-claim milestone+phase-1 in single write (D-08)"
    - "collision detection via re-read-after-write (D-09)"
    - "GSD_DRY_RUN guard before any gist write"
    - "all diagnostic output to stderr, success summary to stdout"
    - "GIST_ID sourced from .claude/gsd-team.json via load_config()"

key-files:
  created:
    - ".claude/gsd-team.json"
    - "hooks/lib/common.sh"
    - "hooks/lib/gist.sh"
    - "hooks/claim-number.sh"
  modified:
    - "hooks/lib/common.sh (verbose_log GSD_VERBOSE fix)"

key-decisions:
  - "GSD_DRY_RUN guard placed after arg validation but before gist write; falls back to stub registry for offline preview"
  - "verbose_log() uses ${GSD_VERBOSE:-} (not $GSD_VERBOSE) to be safe with set -u in callers"
  - "write_registry uses printf not echo to avoid flag interpretation on some shells"
  - "gh gist edit with tmpfile as last arg — verified non-interactive write pattern"

patterns-established:
  - "Pattern: source $REPO_ROOT/hooks/lib/common.sh before any hook script logic"
  - "Pattern: check_deps && load_config at top of every hook script"
  - "Pattern: all output except success summary routed to >&2"
  - "Pattern: exit 2 (not exit 1) for blocking errors"

requirements-completed: [REG-01, REG-02, REG-03, REG-05, ALLOC-01, ALLOC-02]

duration: 12min
completed: 2026-05-19
---

# Phase 01 Plan 01: Registry Allocation Core Summary

**Bash shell library + GitHub Gist registry with max+1 milestone/phase allocation, dual-claim writes, and dry-run/collision-detection support**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-19T13:18:00Z
- **Completed:** 2026-05-19T13:30:39Z
- **Tasks:** 2
- **Files created:** 4

## Accomplishments

- Config file `.claude/gsd-team.json` established as the single source of gist_id for all hook scripts
- `hooks/lib/common.sh` provides centralized dep validation (jq, gh, gh auth) with actionable install hints
- `hooks/lib/gist.sh` provides `read_registry()` and `write_registry()` via `gh gist edit` (non-interactive, temp-file pattern)
- `hooks/claim-number.sh` implements the full claim path: read → compute max+1 → dual-claim write → re-read → collision detection with one retry
- `GSD_DRY_RUN=1` skips gist write and prints `[DRY RUN]` preview to stderr; works even without a configured gist ID

## Task Commits

Each task was committed atomically:

1. **Task 1: Config file and library foundation** - `acb2896` (feat)
2. **Task 2: Walking Skeleton — thin end-to-end claim** - `3395489` (feat)

**Plan metadata:** _(final docs commit — see below)_

## Files Created/Modified

- `.claude/gsd-team.json` — Committed config with `gist_id` placeholder and `project` fields
- `hooks/lib/common.sh` — `check_deps()`, `load_config()`, `verbose_log()` functions; 750 permissions
- `hooks/lib/gist.sh` — `read_registry()` and `write_registry()` via `gh gist edit`; 750 permissions
- `hooks/claim-number.sh` — Full allocation entry point with milestone/phase claiming, dual-claim, collision detection, dry-run; 750 permissions

## Decisions Made

- **Dry-run with stub registry:** `GSD_DRY_RUN=1` attempts to read the gist but falls back to `{"version":1,"claims":[]}` if the gist is unreachable. This allows developers to preview allocation even before configuring a real gist ID.
- **`verbose_log` uses `${GSD_VERBOSE:-}`:** The callers use `set -euo pipefail` which treats unbound variables as errors. Using `:-` default expansion makes `verbose_log` safe in strict mode without requiring callers to export the variable.
- **`printf '%s'` for write:** Avoids `echo` flag interpretation (`-e`, `-n`) on some shells; consistent with RESEARCH.md recommendation.
- **`gh gist edit` with tmpfile:** Confirmed non-interactive write pattern per `gh help gist edit` output. The tmpfile is the last positional argument, preventing `$EDITOR` from opening.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed verbose_log unbound variable with set -euo pipefail**
- **Found during:** Task 2 (dry-run acceptance test)
- **Issue:** `verbose_log()` used `$GSD_VERBOSE` directly; `claim-number.sh` uses `set -euo pipefail` which treats unbound variables as errors; running `GSD_DRY_RUN=1 bash claim-number.sh milestone` failed with `unbound variable: GSD_VERBOSE`
- **Fix:** Changed `verbose_log()` to use `${GSD_VERBOSE:-}` (default-empty expansion) in `hooks/lib/common.sh`
- **Files modified:** `hooks/lib/common.sh`
- **Verification:** `GSD_DRY_RUN=1 bash hooks/claim-number.sh milestone` exits 0, prints `[DRY RUN]`
- **Committed in:** `3395489` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug)
**Impact on plan:** Necessary for correctness; `verbose_log` would have broken any caller using `set -u`. Fix is minimal and aligned with RESEARCH.md Pattern 1 which noted `[[ -n "$GSD_VERBOSE" ]]` but didn't account for caller strict mode.

## Issues Encountered

- The research pattern for `verbose_log` used `$GSD_VERBOSE` bare. With `set -euo pipefail` in `claim-number.sh`, this caused an unbound variable error when `GSD_VERBOSE` was not exported. Fixed by using `${GSD_VERBOSE:-}`.
- `GSD_DRY_RUN` guard originally placed after `read_registry` call. With placeholder gist ID, the gist read fails, blocking dry-run mode. Fixed by making the registry read attempt graceful in dry-run context (using `|| REGISTRY=stub`), keeping the dry-run useful for smoke testing before a real gist is configured.

## User Setup Required

Before running `./hooks/claim-number.sh milestone` against a real gist:

1. Create a GitHub Gist with a file named `registry.json` containing: `{"version":1,"claims":[]}`
2. Copy the gist ID from the URL (`gist.github.com/<user>/<GIST_ID>`)
3. Edit `.claude/gsd-team.json` and replace `"REPLACE_WITH_YOUR_GIST_ID"` with your actual gist ID
4. Verify: `GSD_DRY_RUN=1 ./hooks/claim-number.sh milestone` should show the actual next number from the live registry

## Next Phase Readiness

- All four committed files are ready for Phase 2 (CC hooks) to source and call
- `hooks/claim-number.sh` accepts positional args; Phase 2 may need to add stdin JSON parsing per RESEARCH.md Open Question 3
- Threat mitigations T-01-01 through T-01-04 implemented: JSON validation before parsing, jq --arg for injection prevention, stderr-only output, chmod 750

---
*Phase: 01-registry-allocation-core*
*Completed: 2026-05-19*
