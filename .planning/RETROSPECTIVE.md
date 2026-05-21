# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-05-20
**Phases:** 4 | **Plans:** 9
**Timeline:** 2 days (2026-05-19 to 2026-05-20)

### What Was Built
- Registry & allocation library with collision detection, dry-run, and verbose modes
- CC PreToolUse hooks intercepting GSD milestone/phase creation commands
- Pre-merge-commit validation (4 integrity checks with 8/8 unit tests)
- One-command install script + onboarding README
- Post-merge stale claim auto-cleanup
- Roadmap gate hook (catches ROADMAP.md writes from any agent)

### What Worked
- TDD for the validation library — red-green cycle caught BSD awk edge cases early
- Atomic write patterns (jq tmpfile + validate + mv) prevented corruption
- Library decomposition (common.sh, gist.sh, validate.sh) enabled clean reuse across hooks
- Best-effort concurrency was the right call — 3-person team never hit a real race

### What Was Inefficient
- UserPromptExpansion pivot to PreToolUse cost extra investigation time (Phase 2)
- 7 live tests deferred — will need a real multi-branch setup to validate
- Phase 4 skipped verifier in autonomous mode — missing VERIFICATION.md
- Post-milestone refactor (Gist → orphan branch) was major rework after the milestone was "done"

### Patterns Established
- `REPO_ROOT=$(git rev-parse --show-toplevel)` + `source "$REPO_ROOT/..."` for all hook scripts
- `set -euo pipefail` + `set +e/set -e` sandwich for subprocess capture
- Exit code 2 for blocking hooks, exit 0 for pass-through
- `.gsd/` hidden directory for infrastructure (prevents Claude from treating it as project code)
- `jq @tsv | column -t` for formatted CLI output

### Key Lessons
1. UserPromptExpansion doesn't intercept GSD plugin skills — PreToolUse on Bash is the reliable interception point for GSD commands
2. `gh gist edit` with tmpfile as last arg works non-interactively — but Gist ownership is single-user, making it unsuitable for team registries
3. BSD awk on macOS behaves differently from GNU awk — always test on both or use POSIX-safe constructs
4. `grep` exits 1 on no match — requires `|| true` under `set -e` to prevent false failures
5. Orphan branches are ideal for team-shared config: same repo, no merge conflicts, each dev uses own auth

### Cost Observations
- Sessions: ~8 across 2 days
- Notable: coarse granularity + MVP mode kept planning overhead low relative to code output

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 4 | 9 | Initial delivery — coarse MVP mode, 2-day sprint |

### Cumulative Quality

| Milestone | Tests | Key Quality Win |
|-----------|-------|-----------------|
| v1.0 | 8 (validation) | TDD for validation library; atomic writes throughout |

### Top Lessons (Verified Across Milestones)

1. (Will be populated as patterns repeat across milestones)
