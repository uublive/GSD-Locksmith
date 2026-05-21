---
phase: 01-registry-allocation-core
fixed_at: 2026-05-19T00:00:00Z
review_path: .planning/phases/01-registry-allocation-core/01-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-05-19T00:00:00Z
**Source review:** .planning/phases/01-registry-allocation-core/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (3 Critical, 4 Warning)
- Fixed: 7
- Skipped: 0

## Fixed Issues

### CR-01: `write_registry` uses `gh gist edit` — prohibited by project stack spec and potentially interactive

**Files modified:** `hooks/lib/gist.sh`
**Commit:** e9f6f60
**Applied fix:** Replaced `gh gist edit "$GIST_ID" --filename "$GIST_FILE" "$tmpfile"` with `gh api --method PATCH "/gists/$GIST_ID" --field "files[registry.json][content]=@$tmpfile"`. Also added `trap 'rm -f "$tmpfile"' EXIT` inside `write_registry` to ensure tmpfile cleanup on all exit paths (addressing the gist.sh portion of CR-02 simultaneously). Removed the now-dead manual `exit_code` capture and `rm -f` since the trap handles cleanup and `gh api` propagates exit status through `set -e`.

---

### CR-02: `write_registry` exit-code capture is dead code under `set -e`; retry write failure goes silent

**Files modified:** `hooks/claim-number.sh`
**Commit:** 05f1c58
**Applied fix:** Wrapped the bare `write_registry "$UPDATED_REGISTRY"` call at the retry path (line 175) in `if ! write_registry "$UPDATED_REGISTRY"; then ... exit 2; fi`, matching the guard already present at the first-write call site. This ensures a failed retry write produces a diagnostic error message and exits with code 2 rather than silently aborting the shell.

---

### CR-03: Collision retry appends to a registry that still contains the stale first-write claims — permanent registry pollution

**Files modified:** `hooks/claim-number.sh`
**Commit:** 8130427
**Applied fix:** Before recomputing `NEXT_NUM` in the retry block, introduced a `CLEAN_REGISTRY` variable derived from `REGISTRY_AFTER` with the current owner's own stale active claims removed via `jq del(...)`. For `milestone` type, removes all entries where `.owner==$o and .status=="active" and (.type=="milestone" or .type=="phase")`. For `phase` type, removes entries where `.owner==$o and .status=="active" and .type=="phase" and .milestone==$m`. Both `NEXT_NUM` and `UPDATED_REGISTRY` are then computed from `CLEAN_REGISTRY`, so the stale orphan claims from the losing first write are not persisted to the gist.

---

### WR-01: `MILESTONE_NUM` regex validation allows `0`, which is semantically invalid

**Files modified:** `hooks/claim-number.sh`
**Commit:** 36460f6
**Applied fix:** Changed regex from `^[0-9]+$` to `^[1-9][0-9]*$` to reject `0` and require the number to start with a non-zero digit. Updated the error message to say "must be a positive integer (>= 1)".

---

### WR-02: `COMPETING_OWNER` extraction does not filter to competing owners — may report the current user

**Files modified:** `hooks/claim-number.sh`
**Commit:** 953444b
**Applied fix:** Added `--arg o "$owner"` and `.owner!=$o` predicate to both `COMPETING_OWNER` (first collision, line 144) and `COMPETING_OWNER2` (second collision, line 192) jq filter expressions. Both now select only claims where the owner differs from the current user, preventing the misleading "Competing owner: `<yourself>`" message.

---

### WR-03: `gsd-status.sh` header and data rows use incompatible alignment strategies — table is misaligned

**Files modified:** `hooks/gsd-status.sh`
**Commit:** eff081d
**Applied fix:** Replaced the separate `printf` header line, static separator line, and `column -t` data block with a single process substitution group: the header is emitted as a tab-separated printf line and the jq data rows follow, all piped together through one `column -t -s $'\t'` call. This ensures `column` uses actual data widths to align both header and data rows consistently, and eliminates the static 93-dash separator that would not match calculated widths.

---

### WR-04: `hooks/lib/gist.sh` sources `common.sh` redundantly and sets `REPO_ROOT` as a side-effect global

**Files modified:** `hooks/lib/gist.sh`
**Commit:** 6dc0079
**Applied fix:** Removed the unused `SCRIPT_DIR` assignment entirely. Changed the unconditional `REPO_ROOT="$(git rev-parse --show-toplevel)"` to `: "${REPO_ROOT:=$(git rev-parse --show-toplevel)}"` — the no-op colon command with default-assignment syntax. This preserves any `REPO_ROOT` already set by the caller (e.g., `claim-number.sh` sets it before sourcing gist.sh) and only runs `git rev-parse` as a fallback when the caller has not set it.

---

_Fixed: 2026-05-19T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
