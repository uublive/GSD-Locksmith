---
phase: 01-registry-allocation-core
reviewed: 2026-05-19T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - .claude/gsd-team.json
  - hooks/claim-number.sh
  - hooks/gsd-status.sh
  - hooks/lib/common.sh
  - hooks/lib/gist.sh
findings:
  critical: 3
  warning: 4
  info: 2
  total: 9
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-05-19T00:00:00Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Five files implementing the registry allocation core were reviewed: the config file, the two entry-point scripts (`claim-number.sh`, `gsd-status.sh`), and the two library modules (`hooks/lib/common.sh`, `hooks/lib/gist.sh`). The overall structure is reasonable and the happy-path flow is correct. However, three blocking defects were found:

1. `write_registry` uses `gh gist edit` (interactive editor — explicitly prohibited by the project stack doc), making every write call fragile and potentially interactive in CI or non-TTY contexts.
2. `write_registry`'s manual exit-code capture is dead code under the callers' `set -e` regime, meaning a failed write on the retry path silently exits the entire shell without the expected error message and exit-2.
3. After a collision + retry, the stale orphan claims written during the first (losing) attempt are never removed from the registry, causing permanent registry pollution.

---

## Critical Issues

### CR-01: `write_registry` uses `gh gist edit` — prohibited by project stack spec and potentially interactive

**File:** `hooks/lib/gist.sh:23`
**Issue:** The project CLAUDE.md stack section explicitly states: "`gh gist edit` — edit flags and limitations; `gh api PATCH` recommended for scripting." Despite this, `write_registry` calls `gh gist edit "$GIST_ID" --filename "$GIST_FILE" "$tmpfile"`. While `gh gist edit` with a filename argument may avoid opening `$EDITOR` in some versions, this is version-dependent and is not the documented scripting interface. If the gh version or environment does not recognise the positional file argument as non-interactive, this command will block waiting for user input in a hook context (no TTY).

**Fix:**
```bash
write_registry() {
  local content="$1"
  local tmpfile
  tmpfile="$(mktemp /tmp/gsd-registry-XXXXXX.json)"
  printf '%s' "$content" > "$tmpfile"
  verbose_log "Writing registry to gist $GIST_ID"
  gh api --method PATCH "/gists/$GIST_ID" \
    --field "files[registry.json][content]=@$tmpfile"
  local exit_code=$?
  rm -f "$tmpfile"
  return $exit_code
}
```

---

### CR-02: `write_registry` exit-code capture is dead code under `set -e`; retry write failure goes silent

**File:** `hooks/lib/gist.sh:23-26` and `hooks/claim-number.sh:175`
**Issue:** `gist.sh` does not set `set -euo pipefail` itself, but it is sourced into `claim-number.sh` and `gsd-status.sh` which both do. When a function is called directly (not in a subshell) under `set -e`, a non-zero exit from any statement immediately aborts the shell before the next line executes. This means:

- Line 23: `gh gist edit ...` fails (non-zero exit)
- Line 24: `local exit_code=$?` is **never reached** — `set -e` already killed the shell
- Line 25: `rm -f "$tmpfile"` is **never reached** — tmpfile leaks
- Line 26: `return $exit_code` is **never reached**

The first-write call site (line 121–124 of `claim-number.sh`) wraps `write_registry` in `if ! write_registry ...`, which disables `set -e` for that call — so error handling works there. But the **retry write at line 175** calls `write_registry "$UPDATED_REGISTRY"` bare, with no conditional. Under `set -e`, a failure here immediately aborts the shell with no error message and no `exit 2`, leaving the caller with no diagnostic output.

**Fix:**
```bash
# Line 174-176 of claim-number.sh — wrap retry write the same as the first write
verbose_log "Writing registry to gist (retry after collision)"
if ! write_registry "$UPDATED_REGISTRY"; then
  echo "ERROR: gist write failed on retry" >&2
  exit 2
fi
```

Additionally, add `trap 'rm -f "$tmpfile"' EXIT` inside `write_registry` to ensure cleanup on any exit path:
```bash
write_registry() {
  local content="$1"
  local tmpfile
  tmpfile="$(mktemp /tmp/gsd-registry-XXXXXX.json)"
  trap 'rm -f "$tmpfile"' EXIT
  printf '%s' "$content" > "$tmpfile"
  ...
}
```

---

### CR-03: Collision retry appends to a registry that still contains the stale first-write claims — permanent registry pollution

**File:** `hooks/claim-number.sh:150-172`
**Issue:** When a collision is detected on the first write, the script retries by building `UPDATED_REGISTRY` from `REGISTRY_AFTER`. But `REGISTRY_AFTER` already contains the claims from the first (losing) write — e.g., milestone M and phase-1 at M that were written before the collision was discovered. The retry appends *new* claims (milestone M+1, phase-1 at M+1) to this already-polluted `REGISTRY_AFTER`, and writes the result. The stale orphan entries (milestone M owned by `$owner`, phase-1 at M owned by `$owner`) are never cleaned up. Every collision leaves two permanent dead claims in the shared registry, and the `NEXT_NUM` computation for subsequent users will count these stale active entries, advancing numbers faster than expected.

**Fix:** Before appending retry claims, filter out the stale entries from the previous failed write:
```bash
# At retry block, strip our own stale claims first
if [[ "$TYPE" == "milestone" ]]; then
  # Remove our stale milestone-M and phase-1-at-M entries
  CLEAN_REGISTRY="$(echo "$REGISTRY_AFTER" | jq \
    --arg o "$owner" \
    'del(.claims[] | select(.owner==$o and .status=="active" and (.type=="milestone" or .type=="phase")))')"
  NEXT_NUM="$(echo "$CLEAN_REGISTRY" | jq '...')"
  UPDATED_REGISTRY="$(echo "$CLEAN_REGISTRY" | jq ...)"
else
  CLEAN_REGISTRY="$(echo "$REGISTRY_AFTER" | jq \
    --arg o "$owner" --argjson m "$MILESTONE_NUM" \
    'del(.claims[] | select(.owner==$o and .status=="active" and .type=="phase" and .milestone==$m))')"
  NEXT_NUM="$(echo "$CLEAN_REGISTRY" | jq ...)"
  UPDATED_REGISTRY="$(echo "$CLEAN_REGISTRY" | jq ...)"
fi
```

---

## Warnings

### WR-01: `MILESTONE_NUM` regex validation allows `0`, which is semantically invalid

**File:** `hooks/claim-number.sh:44`
**Issue:** The validation `^[0-9]+$` accepts `"0"` as a valid milestone number. Milestone 0 is meaningless in GSD terminology (numbering starts at 1) and would create a `milestone=0` entry that looks like a missing/null value in consumers that check `(.milestone // "-")`. Downstream `max + 1` computation would return 1, which shadows a real milestone-1 claim.

**Fix:**
```bash
if ! [[ "$MILESTONE_NUM" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: milestone_num must be a positive integer (>= 1), got: '$MILESTONE_NUM'" >&2
  exit 2
fi
```

---

### WR-02: `COMPETING_OWNER` extraction does not filter to competing owners — may report the current user

**File:** `hooks/claim-number.sh:144-145`
**Issue:** After `detect_collision` confirms a competing owner exists (`.owner != $owner`), the `COMPETING_OWNER` extraction uses a filter without the owner exclusion:
```bash
'[.claims[] | select(.type==$t and .number==$n)] | .[0].owner'
```
If multiple claims exist for the same type+number and the current user's own claim sorts first in the array (e.g., it was written first), `.[0].owner` returns the current user's login, reporting themselves as the competing owner. The message "Competing owner: `<yourself>`" is actively misleading.

**Fix:** Add the owner filter:
```bash
COMPETING_OWNER="$(echo "$REGISTRY_AFTER" | jq -r \
  --argjson n "$NEXT_NUM" --arg t "$TYPE" --arg o "$owner" \
  '[.claims[] | select(.type==$t and .number==$n and .owner!=$o)] | .[0].owner // "unknown"')"
```
Apply the same fix to `COMPETING_OWNER2` at line 182–183.

---

### WR-03: `gsd-status.sh` header and data rows use incompatible alignment strategies — table is misaligned

**File:** `hooks/gsd-status.sh:32-37`
**Issue:** The header row is rendered with `printf` using fixed-width format specifiers (`%-12s %-8s ...`), producing space-padded columns of exact widths. The data rows are piped through `column -t -s $'\t'`, which calculates column widths from the actual data content and re-emits with variable spacing. These two approaches produce different column widths whenever any data value is longer than the printf-fixed width (e.g., a branch name > 25 chars or an owner > 12 chars). The header separator line is also a static 93-dash string that will not match either.

**Fix:** Use a consistent approach — either pipe both header and data through `column`, or use `printf` for both with a common format string:
```bash
# Option: prepend header as first row so column -t aligns everything together
{
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "TYPE" "NUMBER" "MILESTONE" "OWNER" "BRANCH" "CLAIMED_AT"
  echo "$REGISTRY" | jq -r '...'
} | column -t -s $'\t'
```

---

### WR-04: `hooks/lib/gist.sh` sources `common.sh` redundantly and sets `REPO_ROOT` as a side-effect global

**File:** `hooks/lib/gist.sh:6-8`
**Issue:** `gist.sh` unconditionally runs `git rev-parse --show-toplevel` at source time (line 7) and stores the result in the global `REPO_ROOT`, silently overwriting any `REPO_ROOT` set by the caller. `claim-number.sh` also sets `REPO_ROOT` at line 13 before sourcing `gist.sh`, so gist.sh's source-time re-execution of `git rev-parse` is redundant and could produce a different value if the working directory changed (unlikely but possible in hook contexts). Additionally, `SCRIPT_DIR` is computed and assigned at line 6 but never used anywhere in the file — dead code.

**Fix:** Remove the `SCRIPT_DIR` computation (line 6). Guard the `REPO_ROOT` assignment to avoid overwriting the caller's value:
```bash
# gist.sh
: "${REPO_ROOT:=$(git rev-parse --show-toplevel)}"
source "$REPO_ROOT/hooks/lib/common.sh"
```
Remove `SCRIPT_DIR` entirely:
```bash
# delete line 6:
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

---

## Info

### IN-01: No validation that the milestone exists in the registry before claiming a phase for it

**File:** `hooks/claim-number.sh:37-48`
**Issue:** When `TYPE == "phase"`, the script validates that `MILESTONE_NUM` is a positive integer but never verifies that a milestone with that number actually exists (has an active claim) in the registry. A user could claim `phase 99` for a non-existent `milestone 99`, polluting the registry with orphaned phase entries.

**Fix:** After reading the registry, add an existence check:
```bash
if [[ "$TYPE" == "phase" ]]; then
  milestone_exists="$(echo "$REGISTRY" | jq --argjson m "$MILESTONE_NUM" \
    '[.claims[] | select(.type=="milestone" and .status=="active" and .number==$m)] | length > 0')"
  if [[ "$milestone_exists" != "true" ]]; then
    echo "ERROR: milestone $MILESTONE_NUM does not exist or is not active in the registry" >&2
    exit 2
  fi
fi
```

---

### IN-02: `hooks/lib/common.sh` and `hooks/lib/gist.sh` lack `set -euo pipefail`

**File:** `hooks/lib/common.sh:1`, `hooks/lib/gist.sh:1`
**Issue:** Neither library file declares `set -euo pipefail`. They rely on being sourced into scripts that do declare it. This is fragile: if either library is ever executed directly (e.g., during testing or debugging), there are no safety guarantees. It also makes the files misleading to read in isolation — `write_registry`'s manual `exit_code` capture appears to be functional error handling but is only safe because of the caller's `set -e` (and as CR-02 shows, even then it breaks down in the retry path).

**Fix:** Add `set -euo pipefail` at the top of each library file:
```bash
# hooks/lib/common.sh — add after shebang line:
set -euo pipefail

# hooks/lib/gist.sh — add after shebang line:
set -euo pipefail
```

---

_Reviewed: 2026-05-19T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
