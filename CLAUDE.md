<!-- GSD:project-start source:PROJECT.md -->
## Project

**GSD Locksmith**

A set of shell-based plugins for GSD (Get Shit Done) that enable a 3-person dev team to work in parallel without breaking each other's planning artifacts. The plugins use Claude Code hooks, git hooks, and a shared registry (on an orphan branch in the same repo) to automate milestone/phase number allocation and validate planning file integrity on merge.

**Core Value:** No more manual Slack coordination to claim milestone and phase numbers — the tooling handles it automatically so the team can work independently without collisions.

### Constraints

- **Tech stack**: Bash scripts + `gh` CLI only — no additional runtime dependencies
- **Auth**: Relies on `gh auth login` being configured per developer
- **Registry setup**: One-time `gsd-registry` orphan branch creation via `install.sh`
- **Concurrency**: Best-effort (read-then-write) — strict locking is out of scope
- **Hook types**: Claude Code hooks (settings.json) for GSD command interception + git hooks for merge-time validation
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Bash | 3.2+ (ship for 5.x) | All plugin scripts | The only runtime the team has agreed on. macOS ships 3.2 (GPL licensing), but Homebrew bash 5.x is standard for dev machines. Write for 5.x, test on 3.2 for CI safety. |
| `gh` CLI | 2.x (current: 2.88) | GitHub API access, authentication | The sanctioned access path for GitHub Contents API; handles OAuth token management transparently via `gh auth login`. All team members read/write the registry with their own auth. |
| `jq` | 1.7+ (current: 1.8.1) | JSON parse/emit for registry and CC hook stdin/stdout | Mandatory for safely reading/writing JSON without text-mangling. Ships preinstalled on macOS Sequoia; `brew install jq` on older. Non-negotiable for the hook stdin contract. |
| Git | 2.9+ | git hook installation via `core.hooksPath` | `core.hooksPath` (added in 2.9) is the only portable way to version and distribute team git hooks without per-developer `.git/hooks` symlinks. |
### Claude Code Hook Configuration
| Hook Event | Matcher | Trigger | Purpose |
|------------|---------|---------|---------|
| `UserPromptExpansion` | `gsd-new-milestone\|gsd-new-phase` | Slash command expansion | Intercept before Claude executes the command; call registry to claim next available number; inject allocated number as `additionalContext`. |
| `PreToolUse` | `Bash` | Tool-level gate | Secondary intercept if slash command runs a Bash tool; inspect `tool_input.command` for GSD command patterns. |
| `PostToolUse` | `Write\|Edit` | After planning file writes | Optionally record branch ownership in registry after files are written. |
- Input: JSON on stdin with `hook_event_name`, `tool_name`, `tool_input`, `cwd`, `session_id`
- Output on exit 0: JSON with `hookSpecificOutput.permissionDecision` (`"deny"/"allow"/"ask"`) and `additionalContext`
- Exit 2: blocking error; stderr text fed back to Claude as error message; aborts tool call
- Exit 0 with no JSON: pass-through (allow)
### GitHub Contents API Access Pattern (Orphan Branch)
| Operation | Command | Notes |
|-----------|---------|-------|
| Read registry | `gh api "/repos/{owner}/{repo}/contents/registry.json?ref=gsd-registry" -H "Accept: application/vnd.github.raw+json"` | Returns raw file content; pipe to `jq` |
| Write registry | `gh api --method PUT /repos/{owner}/{repo}/contents/registry.json --input <json>` | PUT with base64 content + file SHA; targets `gsd-registry` branch |
| Bootstrap check | `gh auth status` | Verify `gh auth login` was run; emit helpful error if not |
| Rate limits | 5,000 req/hour authenticated | Well within range for a 3-person team; no throttling concern |
| Create orphan branch | GitHub Git Data API (blobs → trees → commits → refs) | One-time setup via `install.sh` |
### Git Hook Distribution
| Component | Location | How |
|-----------|----------|-----|
| Hook scripts | `.githooks/` (repo root) | Checked into source control |
| Git config | `core.hooksPath = .githooks` | Set once per developer clone via setup script |
| Setup script | `scripts/setup-hooks.sh` | Runs `git config core.hooksPath .githooks` and `chmod +x .githooks/*` |
- `.githooks/pre-merge-commit` — fires after auto-merge, before merge commit; runs validation; exit non-zero aborts merge commit
- `.githooks/post-merge` — fires after successful merge commit; can update local state; cannot abort
### Supporting Utilities
| Utility | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `mktemp` | POSIX | Atomic temp file creation for intermediate JSON | Always use for intermediate JSON files; never write directly to a shared path |
| `flock` | util-linux (Linux) / `shlock` (macOS) | Local critical-section locking | NOT needed for registry operations (best-effort is accepted); use only if local lock files are added later |
| `git diff --cached --name-only` | Git builtin | List files staged in a merge commit | Used in `pre-merge-commit` to enumerate changed planning files for validation |
## Installation
# 1. Install prerequisites (if not present)
# 2. Authenticate GitHub CLI
# 3. Register project git hooks (run once after clone)
# Which runs:
#   git config core.hooksPath .githooks
#   chmod +x .githooks/*
# 4. Registry branch auto-created by install.sh
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Orphan branch in same repo | GitHub Gist | Gist can only be edited by its creator — other team members would need a shared token. Orphan branch uses each dev's own repo push access. |
| Orphan branch in same repo | Separate registry repo | Adds a second repo to manage. Orphan branch keeps everything in one repo without merge conflicts (isolated branch with no common history). |
| Orphan branch in same repo | Redis / shared DB | If team scales beyond ~10 people and race conditions become frequent enough to require strict locking. Overkill for 3 devs. |
| `jq` for JSON | `python3 -c` / `node -e` | If target machine provably has Python/Node and lacks jq. Both add fragility; jq is the standard tool for this job. |
| `core.hooksPath` | Husky / lefthook | If the project were Node-based. For a pure-shell project, Husky adds a runtime dependency that violates the "bash + gh only" constraint. |
| `pre-merge-commit` git hook | `pre-commit` git hook | `pre-commit` fires on every commit, not just merges. Use `pre-commit` only as a fallback for conflict-resolution commits. |
| `.claude/settings.json` project hooks | User-level `~/.claude/settings.json` | If hooks should be opt-in per developer rather than team-wide. Project-level is correct for team tooling — devs get hooks automatically on clone. |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `curl` with raw GitHub API token | Requires token storage and rotation; `gh` handles auth transparently | `gh api` with `gh auth login` |
| Python / Node for hook scripts | Violates explicit project constraint; adds runtime dependency that may not be present in hook execution context | Bash + jq |
| `post-merge` hook for validation | Fires AFTER commit is created; cannot abort; informational only | `pre-merge-commit` for blocking validation |
| Direct `.git/hooks/` scripts | Not version-controlled; every developer must manually install; no team distribution | `.githooks/` + `core.hooksPath` |
| `jq` version < 1.6 | Pre-1.6 lacks `@base64d`, `env`, and `$ENV` which are needed for robust JSON handling | `jq` 1.7+ (1.8.1 current) |
| Husky | Node runtime dependency; incompatible with "no additional runtimes" constraint | Native git hooks via `core.hooksPath` |
| GitHub Gist for registry | Only the gist creator can write; other devs need a shared token | Orphan branch — all devs use their own `gh auth` |
## Stack Patterns by Variant
- `jq` is preinstalled at `/usr/bin/jq` (1.7+); no Homebrew install needed
- Bash is still 3.2 at `/bin/bash`; use `#!/usr/bin/env bash` shebang to pick up Homebrew bash 5.x if available
- `brew install jq` required in setup script
- Detect with: `command -v jq >/dev/null 2>&1 || { echo "jq required: brew install jq"; exit 1; }`
- All registry operations fail with a clear error from `gh`
- Setup script should call `gh auth status` and exit with instructions if not authenticated
- Both read the same registry state; both write their claim; last write wins
- Detection: after writing, re-read and verify your claim is present; if not, report collision and prompt manual resolution
- This is acceptable per project scope (best-effort concurrency)
## Version Compatibility
| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| `gh` 2.x | GitHub REST API v3 | All registry operations use REST Contents API; no breaking changes in v2.x series |
| `jq` 1.7+ | All bash versions | Filter syntax used (`@json`, `env`, `--arg`) requires 1.6+; 1.7+ recommended |
| `core.hooksPath` | Git 2.9+ | macOS Monterey+ ships Git 2.32+; safe assumption for dev machines |
| CC hooks `UserPromptExpansion` | Claude Code (current) | Verified in current official docs; event name and stdin format stable as of 2026-05 |
| CC hooks `PreToolUse` | Claude Code (current) | Stable; `tool_input.command` field confirmed in official stdin schema |
## Sources
- [Claude Code Hooks Reference — code.claude.com](https://code.claude.com/docs/en/hooks) — Hook event names, stdin/stdout contract, exit code semantics, `UserPromptExpansion` details (HIGH confidence, official Anthropic docs)
- [Claude Code Settings — code.claude.com](https://code.claude.com/docs/en/settings) — settings.json location, project vs user scope, array merging behavior (HIGH confidence)
- [REST API endpoints for repository contents — docs.github.com](https://docs.github.com/en/rest/repos/contents) — GET/PUT `/repos/{owner}/{repo}/contents/{path}`, SHA tracking for updates (HIGH confidence)
- [REST API endpoints for Git data — docs.github.com](https://docs.github.com/en/rest/git) — Blobs, trees, commits, refs API for orphan branch creation (HIGH confidence)
- [Rate limits for the REST API — docs.github.com](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — 5,000 req/hour authenticated (HIGH confidence)
- [Git Hooks — git-scm.com](https://git-scm.com/docs/githooks) — `pre-merge-commit`, `post-merge` behavior, arguments, environment (HIGH confidence, official Git docs)
- [Two Ways to Share Git Hooks with Your Team — viget.com](https://www.viget.com/articles/two-ways-to-share-git-hooks-with-your-team) — `core.hooksPath` team distribution pattern (MEDIUM confidence)
- [jq — jqlang.org](https://jqlang.org/) — version 1.8.1 current, macOS Sequoia preinstall confirmed (HIGH confidence)
- [bats-core — github.com](https://github.com/bats-core/bats-core) — Bash Automated Testing System for hook script unit tests (MEDIUM confidence)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
