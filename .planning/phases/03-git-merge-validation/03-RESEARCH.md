# Phase 3: Git Merge Validation - Research

**Researched:** 2026-05-20
**Domain:** Git hooks (pre-merge-commit), Bash shell scripting, planning file markdown parsing
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Planning files only — check ROADMAP.md, REQUIREMENTS.md, STATE.md, and PLAN.md files in `.planning/`. No source code scanning.
- **D-02:** Four specific checks:
  1. ROADMAP.md phase numbers are sequential (no gaps) → VAL-01
  2. REQUIREMENTS.md has no duplicate REQ-IDs → VAL-02
  3. STATE.md active phase matches what exists in ROADMAP.md → VAL-03
  4. PLAN.md files don't reference REQ-IDs or phase numbers absent from REQUIREMENTS.md/ROADMAP.md → VAL-04
- **D-03:** Compiler-style format: `file:line: ERROR: message` followed by indented detail and fix command. Familiar to devs, grep-friendly, works in CI.
- **D-04:** Every error includes three parts: (1) file path and line number, (2) what's wrong (specific — exact IDs, numbers, values), (3) suggested fix command (exact text the dev can run or copy)
- **D-05:** All output to stderr. Exit non-zero blocks the merge. Exit 0 allows it.
- **D-06:** Use `git config core.hooksPath .githooks` for hook distribution. `.githooks/` directory is committed to git.
- **D-07:** `.githooks/pre-merge-commit` is a thin wrapper that sources `hooks/lib/validate.sh` and runs all 4 checks. Validation logic lives in the library, not the hook file.
- **D-08:** Only validate when merging INTO `development` or `develop` branch. Feature-to-feature merges and other branch merges skip validation (exit 0 immediately).
- **D-09:** `hooks/lib/validate.sh` contains all 4 validation functions. Each function returns 0 (pass) or 1 (fail) and appends errors to a shared error accumulator. The hook collects all errors before exiting — devs see ALL problems at once.
- **D-10:** Validation functions use `git show :path` to read the merged-state content (staged files after merge resolution), not the working tree files.

### Claude's Discretion

None — all implementation decisions are locked.

### Deferred Ideas (OUT OF SCOPE)

None.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VAL-01 | Git pre-merge-commit hook detects phase numbering gaps in ROADMAP.md | Phase number extraction with `grep -E '^\- \[.\] \*\*Phase [0-9]+:'` + awk gap detection confirmed against actual ROADMAP.md format |
| VAL-02 | Git pre-merge-commit hook detects duplicate REQ-IDs in REQUIREMENTS.md | REQ-ID extraction with `grep -oE '\*\*[A-Z]+-[0-9]+\*\*'` + `sort | uniq -d` confirmed against actual REQUIREMENTS.md format |
| VAL-03 | Git pre-merge-commit hook detects STATE.md drift (active phase doesn't match ROADMAP.md) | STATE.md has `**Phase:** N` body field and `progress.total_phases` in YAML frontmatter; ROADMAP.md phase count is the ground truth |
| VAL-04 | Git pre-merge-commit hook detects stale cross-references (plans referencing removed requirements/phases) | PLAN.md YAML frontmatter `requirements:` field contains structured REQ-ID list; body text references are lower priority |
| VAL-05 | Validation errors show file, line, and exact fix command | Compiler-style format `file:line: ERROR: message` with embedded fix command; D-03/D-04 from CONTEXT.md |
</phase_requirements>

---

## Summary

Phase 3 delivers a `pre-merge-commit` git hook that reads the merged state of four planning files and runs four integrity checks before any merge to `development` is committed. All decisions are locked — the only open implementation questions are the exact grep/awk patterns for each check and the precise definition of "STATE.md drift" given the current file format.

The hook architecture is a thin wrapper (`.githooks/pre-merge-commit`) that sources `hooks/lib/validate.sh` and calls four functions. Each function uses `git show :path` to read staged (merged) content, appends errors to a shared accumulator array, and returns 0 or 1. The hook sums all errors and exits non-zero if any exist, reporting all failures at once.

The stack is pure POSIX/bash — no new dependencies. `grep`, `awk`, `sort`, `uniq` are all available. No `jq` is needed (no JSON parsing — only markdown parsing). `bats` is not installed on the developer machine so any tests must be manual shell invocations or written as standalone test scripts.

**Primary recommendation:** Implement the four validation functions in `hooks/lib/validate.sh` using `git show :path` to read staged content, `grep -nE` for line-number-aware extraction, and `awk` for sequential gap detection. The thin wrapper in `.githooks/pre-merge-commit` handles branch filtering and error accumulation. Create `.githooks/` as a committed directory alongside the library.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Branch target filtering | Git hook (pre-merge-commit) | — | `git rev-parse --abbrev-ref HEAD` is available only in git hook context |
| Merged file content reading | Git hook (via `git show :path`) | — | The index (stage 0) holds merged content only during `pre-merge-commit` execution |
| Phase gap detection (VAL-01) | `hooks/lib/validate.sh` function | — | Pure markdown parsing, no git knowledge needed; decoupled from hook entry point |
| Duplicate REQ-ID detection (VAL-02) | `hooks/lib/validate.sh` function | — | Pure markdown parsing |
| STATE.md drift detection (VAL-03) | `hooks/lib/validate.sh` function | — | Cross-file comparison between STATE.md and ROADMAP.md |
| Stale cross-reference detection (VAL-04) | `hooks/lib/validate.sh` function | — | Cross-file comparison between PLAN.md files and REQUIREMENTS.md/ROADMAP.md |
| Error accumulation and reporting | `.githooks/pre-merge-commit` wrapper | — | Aggregates return codes from all four functions; owns final exit decision |
| Hook distribution | `.githooks/` + `git config core.hooksPath` | Phase 4 setup script | Files committed to git; activation requires one-time developer config |

---

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 3.2+ (macOS ships 3.2.57) | Hook and library scripting | Already used in all Phase 1 and 2 scripts; no new dep |
| Git | 2.9+ (2.50.1 on dev machine) | `git show :path`, `git rev-parse`, `core.hooksPath` | `core.hooksPath` requires 2.9+; dev machine has 2.50.1 |
| grep (ugrep 7.5 / POSIX) | System | Line-number-aware markdown parsing | `-n`, `-E`, `-o` flags used; PCRE (`-P`) also works on this machine |
| awk (BSD awk 20200816) | System | Sequential gap detection with state across lines | Superior to grep for multi-pass logic |
| sort + uniq | System POSIX | Duplicate detection for REQ-IDs | One-liner: `sort | uniq -d` produces duplicates only |

### No New Dependencies
`jq` is NOT needed for this phase. All four checks parse markdown with standard POSIX tools. This is intentional — the `pre-merge-commit` hook must succeed even if the developer hasn't run the full setup yet. [VERIFIED: reviewed CONTEXT.md and all four check targets are markdown files]

### Existing Reusable Assets
| Asset | Location | Reuse Pattern |
|-------|----------|---------------|
| `check_deps()` | `hooks/lib/common.sh` | Source in validate.sh only if dependencies beyond grep/awk are needed (currently: none needed) |
| `verbose_log()` | `hooks/lib/common.sh` | Source for `GSD_VERBOSE=1` support in validate.sh |
| `set -euo pipefail` pattern | All existing hooks | Apply to validate.sh header |
| `REPO_ROOT=$(git rev-parse --show-toplevel)` | All existing hooks | Use in pre-merge-commit wrapper to build absolute paths |
| `chmod 750` | Phase 2 pattern | Apply to new `.githooks/pre-merge-commit` at creation time |

---

## Architecture Patterns

### System Architecture Diagram

```
git merge feature/xyz
        |
        v
  Git computes merge (auto-resolve)
        |
  Merge result staged in index
        |
        v
  pre-merge-commit fires
        |
  [D-08] Check: git rev-parse --abbrev-ref HEAD
        |
  +-----+-------+
  |             |
  v             v
NOT development  development/develop
  |             |
exit 0          |
(skip)          v
           source hooks/lib/validate.sh
                |
         +------+------+------+------+
         |      |      |      |
         v      v      v      v
      VAL-01  VAL-02  VAL-03  VAL-04
      gaps    dups    drift   stale
         |      |      |      |
         +------+------+------+
                |
         errors accumulated
                |
        +-------+-------+
        |               |
     no errors        errors exist
        |               |
      exit 0         print to stderr
      (merge ok)        |
                     exit 1
                     (merge aborted)
```

Data flow for each check:
- `git show :.planning/ROADMAP.md` → stdin for gap and drift checks
- `git show :.planning/REQUIREMENTS.md` → stdin for dup and stale checks
- `git show :.planning/STATE.md` → stdin for drift check
- `git show :.planning/phases/*/??-??-PLAN.md` paths → each PLAN.md for stale refs

### Recommended Project Structure (changes from Phase 3)

```
.githooks/                        # NEW — committed, activated via core.hooksPath
└── pre-merge-commit              # NEW — thin wrapper (chmod +x)

hooks/
└── lib/
    ├── common.sh                 # EXISTING — reuse verbose_log()
    ├── gist.sh                   # EXISTING — not used by validate.sh
    └── validate.sh               # NEW — all 4 validation functions
```

No other directories change.

### Pattern 1: pre-merge-commit Thin Wrapper (D-07, D-08, D-09)

**What:** The `.githooks/pre-merge-commit` script handles three concerns: branch target filtering, sourcing the library, running all checks.

**Key behaviors:**
- `git rev-parse --abbrev-ref HEAD` returns the current branch name (the merge TARGET, which is the checked-out branch when `git merge` is run) [VERIFIED: git-scm.com/docs/githooks]
- The hook fires after a clean auto-merge but before the commit is created; exit non-zero aborts [VERIFIED: git-scm.com/docs/githooks]
- The hook does NOT fire when there are merge conflicts (user must resolve manually and then commit, at which point `pre-commit` fires instead) [VERIFIED: git-scm.com/docs/githooks]
- `--no-verify` can bypass the hook (acceptable per project scope) [VERIFIED: git-scm.com/docs/githooks]
- Error accumulator: collect all function return codes, report all errors, then decide exit code

```bash
#!/usr/bin/env bash
# .githooks/pre-merge-commit
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
source "$REPO_ROOT/hooks/lib/validate.sh"

# D-08: Only validate merges to development/develop
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "development" && "$CURRENT_BRANCH" != "develop" ]]; then
  exit 0
fi

# D-09: Collect all errors before exiting
ERRORS=0
check_phase_gaps    || ERRORS=$((ERRORS + $?))
check_duplicate_req_ids || ERRORS=$((ERRORS + $?))
check_state_drift   || ERRORS=$((ERRORS + $?))
check_stale_refs    || ERRORS=$((ERRORS + $?))

if [[ "$ERRORS" -gt 0 ]]; then
  echo ".planning: $ERRORS integrity violation(s). Fix above errors and retry the merge." >&2
  exit 1
fi
exit 0
```

### Pattern 2: git show :path for Merged-State Content (D-10)

**What:** `git show :path` reads from the index stage 0 — the content that will become the merge commit. During `pre-merge-commit` execution, the merged result (auto-resolved) is in the index. This is the correct target to validate.

**Why not working tree files:** Working tree files may differ if there are unstaged changes or if `git merge -X` strategies modified content. `git show :path` gives the exact merged result that will be committed.

**Why not HEAD:path:** `git show HEAD:path` reads the pre-merge version. Validation must check the POST-merge content.

```bash
# Source: git-scm.com/docs/gitrevisions — colon prefix = index stage 0
ROADMAP_CONTENT="$(git show :.planning/ROADMAP.md)"
REQUIREMENTS_CONTENT="$(git show :.planning/REQUIREMENTS.md)"
STATE_CONTENT="$(git show :.planning/STATE.md)"
```

**IMPORTANT:** If a planning file was not changed in the merge, `git show :path` still returns its current HEAD content (the index always reflects the current state). This is correct — we want to validate all planning files regardless of whether they changed in this specific merge.

### Pattern 3: VAL-01 Phase Gap Detection

**Target file:** `.planning/ROADMAP.md`
**Line pattern:** Phase entries under `## Phases` match `^\- \[.\] \*\*Phase [0-9]+:` [VERIFIED: against actual ROADMAP.md]

```bash
check_phase_gaps() {
  local content errors=0
  content="$(git show :.planning/ROADMAP.md 2>/dev/null)" || {
    echo ".planning/ROADMAP.md: 0: ERROR: file not found in merged state" >&2
    return 1
  }

  # Extract phase numbers with line numbers for error reporting
  local prev=0
  while IFS=: read -r linenum phase_num; do
    local expected=$((prev + 1))
    if [[ "$phase_num" -ne "$expected" ]]; then
      echo ".planning/ROADMAP.md:$linenum: ERROR: Phase gap — expected Phase $expected, found Phase $phase_num" >&2
      echo "  Fix: add a '- [ ] **Phase $expected: ...' entry before Phase $phase_num, or renumber" >&2
      errors=$((errors + 1))
    fi
    prev="$phase_num"
  done < <(echo "$content" | grep -nE '^\- \[.\] \*\*Phase [0-9]+:' | \
             grep -oE '[0-9]+:.*Phase [0-9]+' | \
             awk -F: '{print $1":"$NF}')
  return $errors
}
```

**Note on awk approach for gap detection:** Because the while loop needs to track `prev` across iterations (stateful), use a process substitution `< <(...)` to avoid running the loop in a subshell (which would lose variable state). This is bash 3.2+ compatible. [VERIFIED: bash --version = 3.2.57 on dev machine]

**Simpler awk approach (alternative):** Let awk do the sequential check internally and emit error lines, then bash counts errors:

```bash
# awk handles state natively — no subshell issue
local gap_errors
gap_errors=$(echo "$content" | \
  grep -nE '^\- \[.\] \*\*Phase [0-9]+:' | \
  grep -oE '^[0-9]+:.*Phase [0-9]+' | \
  awk -F: '{
    match($0, /Phase ([0-9]+)/, arr)
    n = arr[1]; linenum = $1
    if (NR==1) { prev=n; next }
    expected = prev + 1
    if (n != expected) {
      print ".planning/ROADMAP.md:" linenum ": ERROR: Phase gap — expected Phase " expected " found Phase " n
      print "  Fix: add Phase " expected " entry before line " linenum ", or renumber phases sequentially"
    }
    prev=n
  }')
```

**Recommendation:** The awk-only approach is simpler and avoids bash arithmetic edge cases. Use it.

### Pattern 4: VAL-02 Duplicate REQ-ID Detection

**Target file:** `.planning/REQUIREMENTS.md`
**Line pattern:** `\*\*[A-Z]+-[0-9]+\*\*:` [VERIFIED: against actual REQUIREMENTS.md]

```bash
check_duplicate_req_ids() {
  local content errors=0
  content="$(git show :.planning/REQUIREMENTS.md 2>/dev/null)" || { ...; return 1; }

  # Find duplicates: extract all REQ-IDs, sort, find repeated ones
  local dups
  dups=$(echo "$content" | grep -oE '\*\*[A-Z]+-[0-9]+\*\*' | \
         sed 's/\*\*//g' | sort | uniq -d)

  if [[ -n "$dups" ]]; then
    while IFS= read -r dup_id; do
      # Find line numbers for each occurrence
      echo "$content" | grep -nE "\*\*${dup_id}\*\*" | \
      while IFS=: read -r linenum rest; do
        echo ".planning/REQUIREMENTS.md:$linenum: ERROR: Duplicate REQ-ID $dup_id" >&2
        echo "  Fix: rename one occurrence of $dup_id to the next available ID in its category" >&2
        errors=$((errors + 1))
      done
    done <<< "$dups"
  fi
  return $errors
}
```

**Note:** The outer while-and-inner-while pattern has the same subshell issue. In practice, use a temp file or count externally. Verified approach: accumulate errors in a temp file, count lines at end.

### Pattern 5: VAL-03 STATE.md Drift Detection

**Target files:** `.planning/STATE.md` and `.planning/ROADMAP.md`
**What "drift" means:** Two specific checks based on current file formats [VERIFIED: against actual STATE.md and ROADMAP.md]:

1. **progress.total_phases mismatch:** STATE.md YAML frontmatter `progress.total_phases` value should equal the count of `**Phase N:` entries in ROADMAP.md `## Phases` section.
2. **Active phase reference invalid:** STATE.md body field `**Phase:** N` (the "currently working on" phase) should reference a phase number that exists in ROADMAP.md.

```bash
check_state_drift() {
  local state_content roadmap_content errors=0
  state_content="$(git show :.planning/STATE.md 2>/dev/null)" || { ...; return 1; }
  roadmap_content="$(git show :.planning/ROADMAP.md 2>/dev/null)" || { ...; return 1; }

  # Count phases in ROADMAP.md
  local roadmap_phase_count
  roadmap_phase_count=$(echo "$roadmap_content" | \
    grep -cE '^\- \[.\] \*\*Phase [0-9]+:' || true)

  # Extract total_phases from STATE.md YAML frontmatter
  # Pattern: "  total_phases: N" (indented, under progress:)
  local state_total_phases state_line
  state_line=$(echo "$state_content" | grep -n "total_phases:" | head -1)
  state_total_phases=$(echo "$state_line" | grep -oE '[0-9]+$')
  local line_num=$(echo "$state_line" | cut -d: -f1)

  if [[ "$state_total_phases" != "$roadmap_phase_count" ]]; then
    echo ".planning/STATE.md:$line_num: ERROR: total_phases ($state_total_phases) does not match ROADMAP.md phase count ($roadmap_phase_count)" >&2
    echo "  Fix: update STATE.md progress.total_phases to $roadmap_phase_count" >&2
    errors=$((errors + 1))
  fi

  # Extract current active phase number from STATE.md body
  # Pattern: "**Phase:** N" in body (after the YAML frontmatter block)
  local active_phase_line active_phase_num active_line_num
  active_phase_line=$(echo "$state_content" | grep -n '^\*\*Phase:\*\*' | head -1)
  active_phase_num=$(echo "$active_phase_line" | grep -oE '[0-9]+' | head -1)
  active_line_num=$(echo "$active_phase_line" | cut -d: -f1)

  if [[ -n "$active_phase_num" ]]; then
    local exists
    exists=$(echo "$roadmap_content" | \
      grep -cE "^\- \[.\] \*\*Phase ${active_phase_num}:" || true)
    if [[ "$exists" -eq 0 ]]; then
      echo ".planning/STATE.md:$active_line_num: ERROR: Active phase $active_phase_num not found in ROADMAP.md" >&2
      echo "  Fix: update STATE.md **Phase:** to a phase number listed in ROADMAP.md ## Phases, or add Phase $active_phase_num back to ROADMAP.md" >&2
      errors=$((errors + 1))
    fi
  fi

  return $errors
}
```

### Pattern 6: VAL-04 Stale Cross-Reference Detection

**Target files:** All `.planning/phases/*/??-??-PLAN.md` files
**Where references live:** PLAN.md YAML frontmatter `requirements:` field lists REQ-IDs in `- REQ-ID` format [VERIFIED: against 01-01-PLAN.md, 01-02-PLAN.md, 02-01-PLAN.md]

```bash
check_stale_refs() {
  local req_content roadmap_content errors=0
  req_content="$(git show :.planning/REQUIREMENTS.md 2>/dev/null)" || { ...; return 1; }
  roadmap_content="$(git show :.planning/ROADMAP.md 2>/dev/null)" || { ...; return 1; }

  # Build lists of valid IDs
  local valid_req_ids
  valid_req_ids=$(echo "$req_content" | grep -oE '\*\*[A-Z]+-[0-9]+\*\*' | sed 's/\*\*//g')

  local valid_phase_nums
  valid_phase_nums=$(echo "$roadmap_content" | \
    grep -E '^\- \[.\] \*\*Phase [0-9]+:' | grep -oE 'Phase [0-9]+' | grep -oE '[0-9]+')

  # For each PLAN.md file, check its requirements: YAML field
  while IFS= read -r plan_path; do
    local plan_content
    plan_content="$(git show ":${plan_path}" 2>/dev/null)" || continue

    # Extract REQ-IDs from frontmatter requirements: field
    # Pattern: lines between "^---" markers that match "^  - [A-Z]+-[0-9]+"
    local in_frontmatter=0
    local linenum=0
    while IFS= read -r line; do
      linenum=$((linenum + 1))
      if [[ "$line" == "---" ]]; then
        in_frontmatter=$((in_frontmatter + 1))
        continue
      fi
      [[ "$in_frontmatter" -lt 2 ]] || break  # Past frontmatter

      if echo "$line" | grep -qE '^\s+- [A-Z]+-[0-9]+$'; then
        local ref_id
        ref_id=$(echo "$line" | grep -oE '[A-Z]+-[0-9]+')
        if ! echo "$valid_req_ids" | grep -qx "$ref_id"; then
          echo ".planning/${plan_path}:$linenum: ERROR: Stale REQ-ID reference $ref_id (not in REQUIREMENTS.md)" >&2
          echo "  Fix: remove '- $ref_id' from requirements: field, or restore $ref_id to REQUIREMENTS.md" >&2
          errors=$((errors + 1))
        fi
      fi
    done <<< "$plan_content"
  done < <(git ls-files '.planning/phases' | grep -E '[0-9]+-[0-9]+-PLAN\.md$')

  return $errors
}
```

**Note on `git ls-files` vs `find`:** During `pre-merge-commit`, the index contains all tracked files. `git ls-files` lists files tracked in the index — this is more reliable than `find` for detecting PLAN.md files that may have been added or removed in the merge. [ASSUMED — not explicitly confirmed in git docs, but consistent with git object model]

### Anti-Patterns to Avoid

- **Reading working tree files directly:** `cat .planning/ROADMAP.md` reads the working directory, not the merged state. Use `git show :.planning/ROADMAP.md` (D-10).
- **Stopping at first error per check:** Each check should report ALL violations before returning. A developer merging 3 changes should see all 3 errors, not just the first.
- **Subshell variable loss in error counting:** A while loop piped from a command runs in a subshell; `errors` changes are lost. Use process substitution `while ... done < <(command)` or write errors to a temp file.
- **Using `exit` inside validation functions:** Functions should `return` (not `exit`) so the hook can collect all errors. `exit` in a sourced function terminates the calling script immediately.
- **Checking for `--no-verify` as a bypass:** The hook cannot prevent `--no-verify` — this is acceptable per project scope (PITFALLS.md Pitfall 5).
- **Using `exit 2` for git hooks:** For `pre-merge-commit`, any non-zero exit blocks the merge. Exit code 2 is the CC-hooks pattern; for git hooks, convention is `exit 1`. Both block — use `exit 1` for clarity.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sequential gap detection | Manual prev/curr tracking in bash loop | `awk` with stateful NR logic | awk handles state cleanly; bash loop in pipe loses variable state |
| Duplicate ID detection | Manual loop comparing IDs | `sort \| uniq -d` | Two lines, correct, handles any number of duplicates |
| YAML frontmatter parsing | Custom state machine in bash | `grep -E` pattern matching on known fields | STATE.md YAML is simple key-value; no need for a YAML parser |
| File content at merge state | `cat` or file read | `git show :path` | The only way to get the post-merge, pre-commit content |
| Line number reporting | Recount lines manually | `grep -n` flag | `-n` prefixes every match with line number — free |

---

## Common Pitfalls

### Pitfall 1: Subshell Variable Loss in Error Accumulation

**What goes wrong:** Writing `some_command | while IFS= read -r line; do errors=$((errors+1)); done` — the `errors` counter increments inside the subshell but the parent shell never sees the updated value. The function returns 0 even when errors were found.

**Why it happens:** In bash, a pipeline's right-hand side runs in a subshell. This is consistent across bash 3.2 and 5.x.

**How to avoid:** Use process substitution (`while ... done < <(command)`) to keep the while loop in the current shell. Or accumulate errors in a temp file and count lines after the loop.

**Warning signs:** Functions always return 0 regardless of validation failures. Testing with a deliberately broken ROADMAP.md shows no output.

### Pitfall 2: grep -c Returns Exit 1 on Zero Count

**What goes wrong:** Using `set -euo pipefail` with `count=$(grep -c pattern file)` — when pattern matches 0 lines, `grep -c` exits with code 1, which `set -e` traps as a fatal error and aborts the script.

**Why it happens:** `grep` exit code semantics: 0 = match found, 1 = no match, 2 = error. `grep -c` returns 1 when count is 0.

**How to avoid:** Append `|| true` to `grep -c` calls: `count=$(grep -c pattern file || true)`. When count is 0, the `|| true` prevents the exit-1 trap. Already established in Phase 1 (01-02 decision log).

**Warning signs:** Script aborts unexpectedly when a planning file has zero matching entries. `set -e` trace shows it exits at the `grep -c` line.

### Pitfall 3: git show :path Fails for Untracked Files

**What goes wrong:** A newly created PLAN.md file that was added in the merge but not yet committed returns an error from `git show :path`. This can happen if the merge added the file to the index.

**Why it happens:** During `pre-merge-commit`, the file IS in the index (it was added as part of the merge). `git show :.planning/phases/X/Y-PLAN.md` should work. However, if the file path contains special characters or spaces, the colon-path syntax may need quoting.

**How to avoid:** Always quote the path argument to `git show`. Use `git ls-files` to enumerate PLAN.md files rather than constructing paths manually — `git ls-files` only lists tracked/staged files.

**Warning signs:** Errors like `fatal: Path '.planning/phases/...' does not exist in the index` appearing for files that were clearly changed in the merge.

### Pitfall 4: Branch Name Detection Reads Merge Source, Not Target

**What goes wrong:** Using `git rev-parse --abbrev-ref HEAD` to get the merge TARGET branch, but getting confused by the `MERGE_HEAD` env variable or similar. The result is that `HEAD` correctly returns the checked-out branch (the target), but a developer might accidentally check `MERGE_HEAD` (the source branch being merged in).

**Why it happens:** During a merge, two refs exist: `HEAD` (the target, currently checked out) and `MERGE_HEAD` (the source). `git rev-parse --abbrev-ref HEAD` always returns the target branch name. This is what D-08 requires.

**How to avoid:** Use `git rev-parse --abbrev-ref HEAD` exactly as written in CONTEXT.md specifics. Do not check `MERGE_HEAD`. [VERIFIED: git-scm.com/docs/githooks — hook executes in the context of the target branch]

### Pitfall 5: pre-merge-commit Does Not Fire on Conflicted Merges

**What goes wrong:** A developer resolves merge conflicts manually and commits (`git commit`). The `pre-merge-commit` hook does NOT fire — only `pre-commit` fires. The planning file integrity check is silently skipped.

**Why it happens:** `pre-merge-commit` only fires on auto-resolved merges. When conflicts require manual resolution, git uses the regular commit flow, which fires `pre-commit` instead.

**How to avoid:** Accept as a known limitation for MVP. The hook covers the common case (clean auto-merge of a feature branch). For Phase 4, a `pre-commit` hook could add coverage. Document this limitation in the hook file header.

**Warning signs:** A developer reports that a conflicted merge bypassed validation.

### Pitfall 6: Using exit Inside a Sourced Library Function

**What goes wrong:** A validation function in `hooks/lib/validate.sh` uses `exit 1` instead of `return 1`. Because the library is sourced (not executed as a subprocess), `exit` terminates the entire calling script immediately — only the first failing check runs, and the error accumulator never completes.

**Why it happens:** `exit` and `return` behave differently in sourced scripts. `exit` terminates the calling shell process; `return` returns to the caller.

**How to avoid:** Every function in `validate.sh` must use `return N` (not `exit N`). Reserve `exit` for the hook entry point `.githooks/pre-merge-commit` only.

### Pitfall 7: grep Pattern Escaping on BSD vs GNU grep

**What goes wrong:** A pattern like `\*\*Phase [0-9]+:` works with GNU grep (`grep -E`) but may fail with BSD grep on older macOS. The `+` quantifier requires `-E` (extended regex) flag.

**Why it happens:** Without `-E`, `+` is treated as a literal character in basic regex. This is POSIX behavior.

**How to avoid:** Always use `grep -E` (or `grep -nE`) when using `+`, `|`, `()` in patterns. All four validation checks need `-E`. [VERIFIED: tested on dev machine macOS with ugrep 7.5 — `-E` works, `-P` also works but is not needed]

---

## Runtime State Inventory

Not applicable — this phase is greenfield (creates new files, no rename/refactor/migration).

---

## Code Examples

### Check 1 Verified: Phase Gap Detection against Actual ROADMAP.md

```bash
# Source: verified against /Users/buu/Development/gsdTeamWork/.planning/ROADMAP.md
# ROADMAP.md phase line format: - [x] **Phase 1: Registry & Allocation Core** - ...
# grep -E '^\- \[.\] \*\*Phase [0-9]+:' extracts these lines [VERIFIED: local test]
# grep -oE '[0-9]+$' gets just the phase number

# Gap detection via awk (state-safe, no subshell issue):
echo "$content" | \
  grep -nE '^\- \[.\] \*\*Phase [0-9]+:' | \
  awk -F: '{ 
    match($0, /Phase ([0-9]+):/, arr); n=arr[1]+0; linenum=$1
    if (NR==1) { prev=n; next }
    expected=prev+1
    if (n != expected) print ".planning/ROADMAP.md:" linenum ": ERROR: Phase gap — expected Phase " expected " found Phase " n
    prev=n
  }'
```

### Check 2 Verified: Duplicate REQ-ID Detection against Actual REQUIREMENTS.md

```bash
# Source: verified against /Users/buu/Development/gsdTeamWork/.planning/REQUIREMENTS.md
# REQ-ID format: **REG-01**: — bold ID followed by colon
# grep -oE extracts just the ID including stars, sed removes stars

echo "$content" | grep -oE '\*\*[A-Z]+-[0-9]+\*\*' | sed 's/\*\*//g' | sort | uniq -d
# Returns: empty = no duplicates; non-empty = duplicate IDs (one per line)
```

### Check 3 Verified: STATE.md Field Extraction

```bash
# Source: verified against /Users/buu/Development/gsdTeamWork/.planning/STATE.md
# 
# YAML frontmatter total_phases: "  total_phases: 4" (2-space indent under progress:)
echo "$state_content" | grep -n 'total_phases:' | grep -oE '[0-9]+$'
# Returns: 4

# Body active phase: "**Phase:** 3" (markdown bold label + space + number)
echo "$state_content" | grep -n '^\*\*Phase:\*\* ' | grep -oE ' [0-9]+$' | tr -d ' '
# Returns: 3

# ROADMAP.md phase count:
echo "$roadmap_content" | grep -cE '^\- \[.\] \*\*Phase [0-9]+:' || true
# Returns: 4
```

### Check 4 Verified: PLAN.md Requirements Frontmatter Extraction

```bash
# Source: verified against /Users/buu/Development/gsdTeamWork/.planning/phases/01-registry-allocation-core/01-01-PLAN.md
# PLAN.md frontmatter format (between --- delimiters):
#   requirements:
#     - REG-01
#     - REG-02
#
# Between first and second "---" marker, lines matching "  - [A-Z]+-[0-9]+"

echo "$plan_content" | awk '/^---/{fm++; next} fm<2 && /^  - [A-Z]+-[0-9]+/{print}' | \
  grep -oE '[A-Z]+-[0-9]+'
# Returns: REG-01\nREG-02\nREG-03\nREG-05\nALLOC-01\nALLOC-02
```

### Error Output Format (D-03, D-04, VAL-05)

```bash
# Compiler-style: file:line: ERROR: message
# Each error: location line + detail line + fix command line
echo ".planning/ROADMAP.md:12: ERROR: Phase gap — expected Phase 3, found Phase 4" >&2
echo "  What: ROADMAP.md jumps from Phase 2 to Phase 4 (Phase 3 is missing)" >&2
echo "  Fix: add '- [ ] **Phase 3: [Name]** - [description]' at line 12" >&2
```

### Branch Detection for Merge Target Filter (D-08)

```bash
# Source: git-scm.com/docs/githooks — HEAD is the merge target branch
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "development" && "$CURRENT_BRANCH" != "develop" ]]; then
  exit 0  # Not merging to development — skip validation
fi
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.git/hooks/` scripts (not version-controlled) | `.githooks/` + `core.hooksPath` (version-controlled, committed) | Git 2.9 (2016) | Team distribution without per-developer symlinks |
| `pre-commit` for merge validation | `pre-merge-commit` | Git 1.7.x | Only fires on merge; avoids running expensive checks on every commit |
| Shell heredoc file reading | `git show :path` | N/A | Reads merged state, not working tree — essential for correctness |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash | All scripts | Yes | 3.2.57 (macOS) | — |
| git | Hook execution, `git show :path` | Yes | 2.50.1 | — |
| grep -E | Pattern matching | Yes | ugrep 7.5 (POSIX compatible) | — |
| grep -n | Line number reporting | Yes | ugrep 7.5 | — |
| awk | Gap detection, frontmatter parsing | Yes | BSD awk 20200816 | — |
| sort + uniq -d | Duplicate detection | Yes | BSD sort 2.3-Apple | — |
| bats | Automated hook testing | No (not installed) | — | Manual test scripts |

**Missing with no fallback:** None — all required tools are available.

**bats absent:** Tests will be manual shell invocations or a simple `test-validate.sh` script that calls each function with known-bad content and checks exit codes. This is acceptable for MVP.

---

## Validation Architecture

No `.planning/config.json` found — treating `nyquist_validation` as enabled (absent = enabled).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None (bats not installed; manual shell test scripts) |
| Config file | None — create `tests/test-validate.sh` in Wave 0 |
| Quick run command | `bash tests/test-validate.sh` |
| Full suite command | `bash tests/test-validate.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAL-01 | Gap in ROADMAP.md phases is detected with file, line, and expected number | manual + scripted | `bash tests/test-validate.sh gap` | No — Wave 0 |
| VAL-02 | Duplicate REQ-ID in REQUIREMENTS.md is detected with file and line | manual + scripted | `bash tests/test-validate.sh dup` | No — Wave 0 |
| VAL-03 | STATE.md total_phases mismatch is detected; active phase not in ROADMAP.md is detected | manual + scripted | `bash tests/test-validate.sh drift` | No — Wave 0 |
| VAL-04 | PLAN.md frontmatter references REQ-ID not in REQUIREMENTS.md is detected | manual + scripted | `bash tests/test-validate.sh stale` | No — Wave 0 |
| VAL-05 | Error output includes file, line number, and fix command for each violation | inspection | `bash tests/test-validate.sh | grep ': ERROR:'` | No — Wave 0 |

### Sampling Rate

- **Per task commit:** `bash tests/test-validate.sh`
- **Per wave merge:** `bash tests/test-validate.sh`
- **Phase gate:** Full test pass + manual merge test into `development` branch with a seeded ROADMAP.md gap

### Wave 0 Gaps

- [ ] `tests/test-validate.sh` — covers VAL-01 through VAL-05 via fixture files with known violations

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Yes (low) | Planning files are team-controlled markdown; no untrusted input path |
| V6 Cryptography | No | — |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious content in ROADMAP.md causing shell injection via unquoted variable | Tampering | Quote all `git show :path` outputs before piping to grep/awk; use `echo "$var"` not `echo $var` |
| Hook bypass via `--no-verify` | Tampering | Accepted per project scope (small trusted team). Document limitation. |
| Hook bypass via IDE merge tools | Tampering | Document: merges to `development` must use CLI (`git merge`). Accept for MVP. |

**Risk assessment:** LOW overall. Planning files are written by the same 3-person team that writes the hooks. No external input path. Primary risk is accidental bypass, not malicious tampering.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `git ls-files '.planning/phases'` during `pre-merge-commit` lists all PLAN.md files in the index, including newly added ones from the merge | Pattern 6 (VAL-04) | New PLAN.md files added in a merge would not be checked for stale refs; low risk since new PLAN.md files reference current REQ-IDs |
| A2 | `**Phase:** 3` is the authoritative "active phase" field in STATE.md body that VAL-03 should check | Pattern 5 (VAL-03) | Wrong field checked = VAL-03 reports false positives or misses real drift; field format verified against current STATE.md but could change |
| A3 | PLAN.md YAML frontmatter `requirements:` field uses exactly 2-space indented `- REQ-ID` format | Pattern 6 (VAL-04) | Stale refs not detected if formatting varies; verified against 5 existing PLAN.md files |

---

## Open Questions (RESOLVED)

1. **VAL-04 scope: frontmatter only vs body text references**
   - What we know: PLAN.md frontmatter `requirements:` lists REQ-IDs in structured format; body text also has inline references like "per REG-03"
   - What's unclear: Should VAL-04 also scan body text for inline REQ-ID references?
   - Recommendation: RESOLVED: Frontmatter only for MVP. Body text scanning produces many false positives (comments, cross-references in prose). CONTEXT.md D-02 says "reference" without specifying location — frontmatter is the safer interpretation.

2. **VAL-03 precise definition: what counts as "drift"?**
   - What we know: STATE.md has `progress.total_phases: 4` in YAML frontmatter and `**Phase:** 3` in body
   - What's unclear: Is the check `total_phases vs roadmap phase count`, or `active phase number vs roadmap phases`, or both?
   - Recommendation: RESOLVED: Implement both checks as described in Pattern 5. Both represent genuine drift scenarios.

3. **Error exit code: exit 1 vs exit 2 for pre-merge-commit**
   - What we know: For git hooks, any non-zero exit blocks the merge. Exit 2 is the CC-hooks convention.
   - What's unclear: The existing ARCHITECTURE.md example uses `exit 1` but CONTEXT.md says "Exit non-zero"
   - Recommendation: RESOLVED: Use `exit 1` for git hooks (standard unix convention). Reserve `exit 2` for CC hooks only. Both block, but `exit 1` is more idiomatic.

---

## Sources

### Primary (HIGH confidence)
- [Git githooks documentation — git-scm.com/docs/githooks](https://git-scm.com/docs/githooks) — `pre-merge-commit` behavior, arguments, environment, exit code semantics, bypass conditions, verified via WebFetch
- `/Users/buu/Development/gsdTeamWork/.planning/phases/03-git-merge-validation/03-CONTEXT.md` — All locked decisions (D-01 through D-10)
- `/Users/buu/Development/gsdTeamWork/.planning/research/PITFALLS.md` — Pitfalls 4 and 5 specific to git hooks and distribution
- `/Users/buu/Development/gsdTeamWork/.planning/research/STACK.md` — pre-merge-commit behavior, core.hooksPath pattern
- `/Users/buu/Development/gsdTeamWork/hooks/lib/common.sh` — Established patterns: `set -euo pipefail`, `REPO_ROOT`, `verbose_log`, `check_deps`
- Local bash/grep/awk verification against actual project files (confirmed patterns)

### Secondary (MEDIUM confidence)
- `/Users/buu/Development/gsdTeamWork/.planning/research/ARCHITECTURE.md` — Data flow diagram for merge validation, component responsibilities
- `.planning/phases/01-*/01-0*-PLAN.md` (5 files) — Established YAML frontmatter `requirements:` format, confirmed 2-space indent pattern

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools verified present on dev machine via `command -v` checks
- Architecture: HIGH — all patterns verified against official git docs and actual file formats
- Pitfalls: HIGH — sourced from existing project PITFALLS.md plus new bash-specific pitfalls verified against bash 3.2.57

**Research date:** 2026-05-20
**Valid until:** 2026-06-20 (stable domain — git hook behavior and POSIX tools are stable)
