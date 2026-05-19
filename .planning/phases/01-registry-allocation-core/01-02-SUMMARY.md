---
phase: 01-registry-allocation-core
plan: 02
subsystem: infra
tags: [bash, collision-detection, dry-run, verbose, gh-cli, github-gist, shell-scripts]

requires:
  - 01-01

provides:
  - "hooks/claim-number.sh — Production-quality dry-run, verbose mode, and collision detection with single retry"

affects:
  - 02-cc-hooks
  - 03-git-hooks

tech-stack:
  added: []
  patterns:
    - "verbose_log() requires || true guard in functions called from set -e scripts"
    - "GSD_DRY_RUN short-circuits before all writes and collision checks"
    - "flat two-attempt collision retry: write -> re-read -> check -> retry write -> re-read -> check -> exit 2"
    - "competing owner extracted from fresh re-read before retrying"

key-files:
  created: []
  modified:
    - "hooks/claim-number.sh (dry-run format fix, verbose_log callsites, collision detection complete)"
    - "hooks/lib/common.sh (verbose_log || true guard)"

key-decisions:
  - "verbose_log() uses '|| true' suffix: the [[ -n ... ]] && echo pattern returns exit 1 when condition is false; without || true, set -e in the calling script traps this as an error"
  - "Dry-run format uses 'Would claim:' / 'Would also claim:' per ALLOC-04 spec (not 'Would write claim:')"
  - "Collision first hit prints explicit WARNING to stderr including competing owner name before retrying"
  - "Collision second hit exits 2 with ERROR including competing owner and manual resolution instructions"

requirements-completed: [ALLOC-03, ALLOC-04, ALLOC-05]

duration: 15min
completed: 2026-05-19
---

# Phase 01 Plan 02: Collision Detection + Dry-Run + Verbose Summary

**Production-hardened claim-number.sh with correct dry-run preview format, multi-site verbose logging, and flat two-attempt collision retry with competing-owner identification**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-05-19T13:32:00Z
- **Completed:** 2026-05-19T13:47:00Z
- **Tasks:** 2 (implemented in unified write; both covered by single commit)
- **Files modified:** 2 (hooks/claim-number.sh, hooks/lib/common.sh)

## Accomplishments

- `GSD_DRY_RUN=1` now produces `[DRY RUN] Would claim:` / `[DRY RUN] Would also claim:` output on stderr with empty stdout — safe for Phase 2 CC hooks to parse stdout without interference
- `GSD_VERBOSE=1` emits `[GSD]`-prefixed operation logs at: NEXT_NUM computation, first write, first re-read, collision-or-not detection, retry write, and retry re-read
- No verbose_log call sites expose raw registry JSON content (T-02-01 mitigated)
- Collision detection sends explicit `WARNING: Collision detected...` + `Competing owner: <name>` to stderr before retrying
- Second collision exits 2 with `ERROR: Collision persists after retry...` naming the competing owner and instructing manual resolution
- Exactly two write_registry calls (not a loop) — flat two-attempt structure per spec

## Task Commits

Both tasks modify `hooks/claim-number.sh` only. Implementation was written as a unified change; committed as one task commit:

1. **Task 1 + Task 2: Dry-run hardening + Collision detection** — `f440304` (feat)

**Plan metadata:** (final docs commit — see below)

## Files Modified

- `hooks/claim-number.sh` — Full dry-run/verbose/collision-detection implementation; 120+ lines
- `hooks/lib/common.sh` — `verbose_log()` fix: added `|| true` to prevent `set -e` trap on false condition

## Decisions Made

- **`verbose_log || true` fix:** The original `verbose_log()` used `[[ -n "${GSD_VERBOSE:-}" ]] && echo "[GSD] $*" >&2`. When `GSD_VERBOSE` is unset, the `[[` test returns exit 1, and the `&&` short-circuits (echo not called). The function then returns exit 1. Callers using `set -euo pipefail` treat this as a fatal error and silently exit. Fix: `|| true` appended so the function always returns 0.
- **Dry-run format correction:** Plan 01 used `"Would write claim:"` but the ALLOC-04 spec and acceptance criteria require `"Would claim:"` / `"Would also claim:"`. Corrected in this plan.
- **First collision: explicit near-miss warning (not verbose-gated):** The plan spec requires the near-miss warning to go to stderr unconditionally. Only verbose_log calls are gated by `GSD_VERBOSE`. The `WARNING: Collision detected...` and `Competing owner:` messages are always emitted on collision, not behind `GSD_VERBOSE`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed verbose_log() returning exit 1 in set -e context**
- **Found during:** Task 1 (first dry-run test attempt)
- **Issue:** `verbose_log()` uses `[[ -n ... ]] && echo ...`. When `GSD_VERBOSE` is unset, `[[` test is false, returns exit 1, function returns exit 1. `set -euo pipefail` in `claim-number.sh` treats this as a fatal error and exits the script silently.
- **Fix:** Changed `verbose_log()` to `[[ -n "${GSD_VERBOSE:-}" ]] && echo "[GSD] $*" >&2 || true`
- **Files modified:** `hooks/lib/common.sh`
- **Commit:** `f440304`

**2. [Rule 1 - Bug] Corrected dry-run output format to match spec**
- **Found during:** Task 1 (acceptance criteria review)
- **Issue:** Plan 01 implementation used `"[DRY RUN] Would write claim:"` but ALLOC-04 spec and plan 02 acceptance criteria require `"[DRY RUN] Would claim:"` and `"[DRY RUN] Would also claim:"`
- **Fix:** Updated dry-run output format strings in claim-number.sh
- **Files modified:** `hooks/claim-number.sh`
- **Commit:** `f440304`

### Task Commit Consolidation

Both tasks modify only `hooks/claim-number.sh`. Since the file was written as a single unit, both tasks are covered by commit `f440304`. This is noted as a deviation from the per-task commit protocol but does not affect correctness — all acceptance criteria from both tasks pass.

## Verification Results

All plan verification steps passed on 2026-05-19:

1. `bash -n hooks/claim-number.sh` — exits 0 (PASS)
2. `GSD_DRY_RUN=1 ./hooks/claim-number.sh milestone 2>&1` — exits 0, stderr has "[DRY RUN] Would claim: type=milestone" (PASS)
3. `GSD_DRY_RUN=1 ./hooks/claim-number.sh milestone 2>/dev/null` — stdout empty (PASS)
4. `GSD_VERBOSE=1 GSD_DRY_RUN=1 ./hooks/claim-number.sh milestone 2>&1` — stderr has "[GSD]" lines (PASS)
5. `grep -c 'write_registry' hooks/claim-number.sh` — returns 2 (PASS)
6. `grep -c 'read_registry' hooks/claim-number.sh` — returns 4 (PASS, exceeds minimum 3)
7. `grep 'exit 2' hooks/claim-number.sh | wc -l` — returns 7 (PASS, exceeds minimum 2)

## Known Stubs

None — all outputs wire to real logic. Collision detection requires a live gist; unit testing the collision path requires two concurrent writers.

## Threat Flags

None — T-02-01 (verbose_log information disclosure) was the only threat and is mitigated: verbose_log call sites emit operation names only, not registry content.

---
*Phase: 01-registry-allocation-core*
*Completed: 2026-05-19*
