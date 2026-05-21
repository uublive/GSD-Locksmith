# Phase 3: Git Merge Validation - Context

**Gathered:** 2026-05-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver a `pre-merge-commit` git hook that validates planning file integrity when merging feature branches to the development branch. Four checks: phase numbering gaps (ROADMAP.md), duplicate REQ-IDs (REQUIREMENTS.md), STATE.md drift (state vs roadmap consistency), and stale cross-references (PLAN.md files referencing removed requirements or phases). All errors use compiler-style output with file, line, and fix command.

</domain>

<decisions>
## Implementation Decisions

### Validation Scope
- **D-01:** Planning files only — check ROADMAP.md, REQUIREMENTS.md, STATE.md, and PLAN.md files in `.planning/`. No source code scanning.
- **D-02:** Four specific checks mapping to requirements:
  1. ROADMAP.md phase numbers are sequential (no gaps) → VAL-01
  2. REQUIREMENTS.md has no duplicate REQ-IDs → VAL-02
  3. STATE.md active phase matches what exists in ROADMAP.md → VAL-03
  4. PLAN.md files don't reference REQ-IDs or phase numbers absent from REQUIREMENTS.md/ROADMAP.md → VAL-04

### Error Output Format
- **D-03:** Compiler-style format: `file:line: ERROR: message` followed by indented detail and fix command. Familiar to devs, grep-friendly, works in CI.
- **D-04:** Every error includes three parts per VAL-05:
  1. File path and line number
  2. What's wrong (specific — exact IDs, numbers, values)
  3. Suggested fix command (exact text the dev can run or copy)
- **D-05:** All output to stderr. Exit non-zero blocks the merge. Exit 0 allows it.

### Hook Installation
- **D-06:** Use `git config core.hooksPath .githooks` for hook distribution. The `.githooks/` directory is committed to git. One setup command per developer.
- **D-07:** `.githooks/pre-merge-commit` is a thin wrapper that sources `hooks/lib/validate.sh` and runs all 4 checks. Validation logic lives in the library, not the hook file.

### Merge Target Filter
- **D-08:** Only validate when merging INTO `development` or `develop` branch. Feature-to-feature merges and other branch merges skip validation (exit 0 immediately). Matches gitflow intent.

### Script Organization
- **D-09:** `hooks/lib/validate.sh` contains all 4 validation functions. Each function returns 0 (pass) or 1 (fail) and appends errors to a shared error accumulator. The hook collects all errors before exiting, so devs see ALL problems at once (not just the first one).
- **D-10:** Validation functions use `git show :path` to read the merged-state content (staged files after merge resolution), not the working tree files. This ensures correctness when the merge produces different content than either branch had.

### Claude's Discretion
- None — all implementation decisions are locked.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 Artifacts (dependency)
- `hooks/lib/common.sh` — Shared dependency checks and config loading (reuse `check_deps`, `verbose_log`)
- `hooks/lib/gist.sh` — Registry functions (validate.sh does NOT need gist access — but may share common.sh patterns)

### Project Context
- `.planning/PROJECT.md` — Project goals and constraints
- `.planning/REQUIREMENTS.md` — VAL-01..VAL-05 requirements for this phase
- `.planning/ROADMAP.md` — Phase 3 success criteria

### Research
- `.planning/research/STACK.md` — `pre-merge-commit` hook behavior, `core.hooksPath` pattern
- `.planning/research/PITFALLS.md` — Git hook distribution issues, hook bypass risks
- `.planning/research/ARCHITECTURE.md` — Component boundaries, data flow

### External References
- Git hooks docs: `https://git-scm.com/docs/githooks` — `pre-merge-commit` hook behavior and exit code semantics

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `hooks/lib/common.sh` — `check_deps()`, `verbose_log()` patterns reusable for validate.sh
- `.githooks/` directory — already planned in Phase 1 D-06 but not yet created

### Established Patterns
- All scripts use `set -euo pipefail` and `REPO_ROOT=$(git rev-parse --show-toplevel)`
- Error output to stderr, exit code 2 for blocking errors
- `jq` for JSON parsing, `grep` for text scanning

### Integration Points
- `.githooks/pre-merge-commit` — new file, thin wrapper calling validate.sh
- `hooks/lib/validate.sh` — new file, all validation logic

</code_context>

<specifics>
## Specific Ideas

- Compiler-style error format previewed during discussion: `ROADMAP.md:14: ERROR: Phase gap detected`
- Branch target check previewed: `git rev-parse --abbrev-ref HEAD` to detect development/develop
- Use `git show :path` for reading merged-state content (not working tree)
- Error accumulator pattern: collect all errors, report at end, exit non-zero if any found

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 3-Git Merge Validation*
*Context gathered: 2026-05-20*
