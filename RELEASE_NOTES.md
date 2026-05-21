# Release Notes

## Post-v1.0 — Ownership-Aware Routing (2026-05-21)

**New: Team ownership context injection**

When Claude runs GSD queries (`gsd-sdk query roadmap` or `gsd-sdk query init`), a PostToolUse hook now reads the team registry and injects an ownership summary into Claude's context:

```
## Team Registry: Ownership Context
- Milestone 1.11, phases 37, 38: alex (branch: feat/payments)
- Milestone 1.15, phases 52, 53: matteo (branch: feat/dashboard) ← you
```

Claude sees who owns what and adjusts routing suggestions — it won't suggest working on another dev's milestones unless you explicitly ask. This is enrichment, not filtering: all claims stay visible.

**Files added/changed:**
- `.gsd/ownership-context.sh` — PostToolUse hook script (66 lines)
- `.claude/settings.json` — added PostToolUse entry for Bash matcher
- `.gsd/install-hooks.sh` — now configures both PreToolUse and PostToolUse hooks

---

## Post-v1.0 — Registry Migration & Project Rename (2026-05-21)

**Breaking: GitHub Gist registry replaced with orphan branch**

Gists can only be edited by their creator, requiring shared tokens for team use. The registry now lives on a `gsd-registry` orphan branch in the same repo. All team members read/write via GitHub Contents API using their own `gh auth`. No shared tokens needed.

**Other changes:**
- Project renamed to **GSD Locksmith**
- Hook infrastructure moved to `.gsd/` hidden directory (prevents Claude from treating it as project source code)
- `CLAUDE.md` integration: installer adds Infrastructure Files section telling Claude to ignore `.gsd/`, `.githooks/`, `.claude/`
- Public README with full documentation

**Breaking: Roadmap gate replaces Bash command interception**

The fragile pattern-matching approach (intercepting `gsd-sdk init` Bash commands) was replaced with a simpler, more robust design: PreToolUse hooks on Write/Edit that fire when *any* agent writes to `ROADMAP.md`. The gate extracts milestone/phase numbers from the content, checks for conflicts, and blocks or claims as needed. Works for all GSD operations, not just known command patterns.

---

## v1.0 — MVP (2026-05-20)

**First release. 4 phases, 9 plans, 22 requirements, ~1,460 LOC Bash.**

No more manual Slack coordination to claim milestone and phase numbers — the tooling handles it automatically so the team can work independently without collisions.

### Phase 4: Setup & Release Lifecycle (2026-05-20)

One-command install and automatic cleanup.

- `install-hooks.sh` — validates prerequisites, sets `core.hooksPath`, merges CC hook entries into `settings.json`. Atomic write via tmpfile. Idempotent (safe to re-run).
- `README-HOOKS.md` — onboarding guide covering prerequisites, setup, verification, usage, and troubleshooting.
- `.githooks/post-merge` — after a successful merge, reads the registry and marks the merged branch's claims as `"released"`. All error paths exit 0 (never blocks post-merge workflow). Respects `GSD_DRY_RUN=1`.

### Phase 3: Git Merge Validation (2026-05-20)

Four integrity checks run at merge time via `pre-merge-commit` hook.

| Check | What it catches |
|-------|----------------|
| Phase gaps | Phase 2 followed by Phase 4 — missing Phase 3 |
| Duplicate REQ-IDs | Same ID defined twice with different content |
| STATE.md drift | Active phase doesn't match ROADMAP.md |
| Stale references | Plan references a removed requirement or phase |

- Errors show file, line number, and exact fix command (compiler-style output)
- TDD: 8/8 fixture-based unit tests passing
- Branch filter: only runs on merges to `development` or `develop`
- Built with BSD awk compatibility (macOS)

### Phase 2: CC Hook Integration (2026-05-19)

Claude Code hooks that intercept GSD commands and claim numbers from the registry before execution.

- **PreToolUse on Bash** intercepts `gsd-sdk init` calls for milestone/phase creation
- Claims numbers via the shared registry, blocks with exit 2 on failure
- Injects `additionalContext` so Claude announces claims to the user
- Clean stdout — no shell profile contamination
- **Pivot:** UserPromptExpansion doesn't reliably intercept GSD plugin skills; switched to PreToolUse on Bash

### Phase 1: Registry & Allocation Core (2026-05-19)

The foundation: shared registry library and automatic number allocation.

- `.claude/gsd-team.json` — single config file for registry location
- `common.sh` — dependency validation (`jq`, `gh`, `gh auth`) with actionable install hints
- `registry.sh` — `read_registry()` and `write_registry()` via GitHub Contents API (orphan branch)
- `claim-number.sh` — claims next available milestone or phase number. Collision detection with one retry. Dry-run and verbose modes.
- `gsd-status.sh` — formatted table of all active claims (who, what number, which branch)
- Best-effort concurrency: read-then-write with collision detection. Team of 3 — simultaneous claims are rare enough for manual resolution.

### Known Limitations

- `pre-merge-commit` only fires on clean auto-merges, not conflict-resolution merges
- Best-effort concurrency — two devs claiming at the exact same millisecond could collide (extremely rare, manually resolvable)
- 7 deferred live tests (CC session, merge blocking, post-merge release) — all environment activation checks, not code gaps
- Requires `gh auth login` on each dev machine and GitHub API access (no offline mode)
