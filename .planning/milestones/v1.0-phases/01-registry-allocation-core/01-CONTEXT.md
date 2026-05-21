# Phase 1: Registry & Allocation Core - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver a shared GitHub Gist registry with shell library functions for reading/writing claims, automatic milestone and phase number allocation, a status command, and dry-run/verbose modes. This is the foundation layer — all CC hooks (Phase 2) and git hooks (Phase 3) depend on the library and schema built here.

</domain>

<decisions>
## Implementation Decisions

### Registry Schema
- **D-01:** Flat JSON array — all claims in a single `claims` array with a `type` field (`"milestone"` or `"phase"`) to distinguish entry types. Top-level `version` field for future schema migration.
- **D-02:** Claims are marked as released (`"status": "released"` + `released_at` timestamp), never deleted. This preserves history and avoids number reuse confusion in git history.
- **D-03:** Owner field populated via `gh api user` (GitHub username) — consistent across machines, always available when `gh` is authed.
- **D-04:** Each claim entry includes: `type`, `number`, `milestone` (for phase claims), `branch`, `owner`, `claimed_at`, `status` (default `"active"`).

### Config File Format
- **D-05:** Gist ID and project config stored in `.claude/gsd-team.json` (JSON format, committed to git). Hooks read it via `jq`. Sits next to `.claude/settings.json` where CC hook wiring lives.
- **D-06:** All hook scripts live in-repo under `hooks/` directory (committed to git). Directory structure:
  - `hooks/lib/gist.sh` — read/write registry functions
  - `hooks/lib/validate.sh` — integrity check functions (Phase 3)
  - `hooks/lib/common.sh` — dep checks, error output helpers
  - `hooks/claim-number.sh` — allocation logic (called by CC hooks)
  - `hooks/gsd-status.sh` — standalone status display
  - `.githooks/pre-merge-commit` — thin wrapper calling validate scripts (Phase 3)

### Allocation Strategy
- **D-07:** Max+1 allocation — always increment from the highest claimed number of that type. Never reuse released numbers. Gaps are expected and acceptable.
- **D-08:** Claiming a milestone auto-claims phase 1 of that milestone in the same write — single gist PATCH with both entries.
- **D-09:** Collision detection via re-read-and-retry: after writing, immediately re-read the gist. If a different owner claimed the same number, auto-retry once with the next available number and report the near-miss to the user.

### Script Organization
- **D-10:** `gsd-status.sh` is a standalone script invoked directly from terminal (`./hooks/gsd-status.sh`). No CC hook wiring for status.
- **D-11:** All scripts fail fast on missing dependencies — check for `jq`, `gh`, and `gh auth status` at script start. Exit immediately with actionable install hints (`brew install jq`, `gh auth login`).

### Claude's Discretion
- No areas delegated to Claude's discretion in this phase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Context
- `.planning/PROJECT.md` — Project goals, constraints, key decisions
- `.planning/REQUIREMENTS.md` — REG-01..05, ALLOC-01..05 requirements for this phase
- `.planning/ROADMAP.md` — Phase 1 success criteria and dependency chain

### Research
- `.planning/research/STACK.md` — `gh` CLI API patterns, `jq` usage, CC hook contract details
- `.planning/research/ARCHITECTURE.md` — Component boundaries, data flow, build order
- `.planning/research/PITFALLS.md` — Exit code 2 trap, shell profile contamination, auth state differences

### External References
- Claude Code hooks docs: `https://code.claude.com/docs/en/hooks` — PreToolUse event contract, exit code semantics
- GitHub Gist REST API: `https://docs.github.com/en/rest/gists/gists` — PATCH endpoint for updates

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project, no existing code to reuse.

### Established Patterns
- None — all patterns will be established in this phase.

### Integration Points
- `.claude/settings.json` — CC hook entries will be added here (Phase 2 dependency)
- `.claude/gsd-team.json` — new config file created in this phase, read by all subsequent phases

</code_context>

<specifics>
## Specific Ideas

- Registry JSON preview shown during discussion captures the exact schema shape the user approved
- `gsd-status.sh` output format was previewed: table with milestone/phase number, owner, branch, date
- `jq` one-liner for max+1 was shown: `jq '[.claims[] | select(.type=="milestone") | .number] | max + 1'`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 1-Registry & Allocation Core*
*Context gathered: 2026-05-19*
