# Phase 4: Setup & Release Lifecycle - Context

**Gathered:** 2026-05-20
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Deliver a one-command install script that configures both git hooks (via `core.hooksPath`) and CC hook entries (via `settings.json`) for a new developer, an onboarding README with prerequisites and setup steps, and automatic release of stale registry entries when branches are deleted or merged.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions.

Prior phase patterns to follow:
- From Phase 1: `.claude/gsd-team.json` for config, `hooks/lib/` for libraries, `chmod 750` for scripts
- From Phase 2: `.claude/settings.json` for CC hook wiring, `${CLAUDE_PROJECT_DIR}` for paths
- From Phase 3: `.githooks/` for git hooks, `core.hooksPath` for distribution

</decisions>

<canonical_refs>
## Canonical References

### Prior Phase Artifacts
- `hooks/lib/common.sh` — shared dependency checks
- `hooks/lib/gist.sh` — registry read/write
- `hooks/lib/validate.sh` — validation functions
- `hooks/claim-number.sh` — allocation script
- `.claude/settings.json` — CC hook wiring
- `.claude/gsd-team.json` — gist config
- `.githooks/pre-merge-commit` — git hook wrapper

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `hooks/lib/common.sh` — `check_deps()` pattern for prerequisite validation
- `hooks/lib/gist.sh` — `read_registry()`, `write_registry()` for stale claim cleanup

### Established Patterns
- All scripts: `set -euo pipefail`, `REPO_ROOT=$(git rev-parse --show-toplevel)`
- Error output to stderr, exit codes: 1 for git hooks, 2 for CC hooks
- `jq` for JSON, `gh` CLI for GitHub API

### Integration Points
- `scripts/install-hooks.sh` — new install script
- `README-HOOKS.md` — new onboarding doc
- `.githooks/post-merge` — new hook for stale claim release

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Refer to ROADMAP phase description and success criteria.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 4-Setup & Release Lifecycle*
*Context gathered: 2026-05-20*
