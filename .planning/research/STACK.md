# Stack Research

**Domain:** Shell-based CLI plugin system — Claude Code hooks + git hooks + GitHub Gist shared registry
**Researched:** 2026-05-19
**Confidence:** HIGH (core tools verified against official docs; CC hook event details verified against current code.claude.com docs)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Bash | 3.2+ (ship for 5.x) | All plugin scripts | The only runtime the team has agreed on. macOS ships 3.2 (GPL licensing), but Homebrew bash 5.x is standard for dev machines. Write for 5.x, test on 3.2 for CI safety. |
| `gh` CLI | 2.x (current: 2.88) | GitHub Gist read/write, authentication | The sanctioned access path for Gist API; handles OAuth token management transparently via `gh auth login`. No token management code needed. |
| `jq` | 1.7+ (current: 1.8.1) | JSON parse/emit for Gist registry and CC hook stdin/stdout | Mandatory for safely reading/writing JSON without text-mangling. Ships preinstalled on macOS Sequoia; `brew install jq` on older. Non-negotiable for the hook stdin contract. |
| Git | 2.9+ | git hook installation via `core.hooksPath` | `core.hooksPath` (added in 2.9) is the only portable way to version and distribute team git hooks without per-developer `.git/hooks` symlinks. |

### Claude Code Hook Configuration

| Hook Event | Matcher | Trigger | Purpose |
|------------|---------|---------|---------|
| `UserPromptExpansion` | `gsd-new-milestone\|gsd-new-phase` | Slash command expansion | Intercept before Claude executes the command; call Gist registry to claim next available number; inject allocated number as `additionalContext`. |
| `PreToolUse` | `Bash` | Tool-level gate | Secondary intercept if slash command runs a Bash tool; inspect `tool_input.command` for GSD command patterns. |
| `PostToolUse` | `Write\|Edit` | After planning file writes | Optionally record branch ownership in registry after files are written. |

Configuration lives in `.claude/settings.json` (project-level, checked into repo). Per-developer overrides go in `.claude/settings.local.json` (git-ignored). Array fields are concatenated, not overridden — project hooks stack with user-level hooks safely.

**Hook stdin/stdout contract (verified against official docs):**
- Input: JSON on stdin with `hook_event_name`, `tool_name`, `tool_input`, `cwd`, `session_id`
- Output on exit 0: JSON with `hookSpecificOutput.permissionDecision` (`"deny"/"allow"/"ask"`) and `additionalContext`
- Exit 2: blocking error; stderr text fed back to Claude as error message; aborts tool call
- Exit 0 with no JSON: pass-through (allow)

### GitHub Gist API Access Pattern

| Operation | Command | Notes |
|-----------|---------|-------|
| Read registry | `gh gist view <GIST_ID> --raw --filename registry.json` | Returns raw file content; pipe to `jq` |
| Write registry | `gh api --method PATCH /gists/<GIST_ID> --field files[registry.json][content]=@/tmp/updated.json` | PATCH endpoint; only named files are updated; others unchanged |
| Bootstrap check | `gh auth status` | Verify `gh auth login` was run; emit helpful error if not |
| Rate limits | 5,000 req/hour authenticated | Well within range for a 3-person team; no throttling concern |

The PATCH body structure for `gh api`:
```json
{
  "files": {
    "registry.json": {
      "content": "<escaped JSON string>"
    }
  }
}
```

### Git Hook Distribution

| Component | Location | How |
|-----------|----------|-----|
| Hook scripts | `.githooks/` (repo root) | Checked into source control |
| Git config | `core.hooksPath = .githooks` | Set once per developer clone via setup script |
| Setup script | `scripts/setup-hooks.sh` | Runs `git config core.hooksPath .githooks` and `chmod +x .githooks/*` |

Relevant hooks:
- `.githooks/pre-merge-commit` — fires after auto-merge, before merge commit; runs validation; exit non-zero aborts merge commit
- `.githooks/post-merge` — fires after successful merge commit; can update local state; cannot abort

`pre-merge-commit` is the correct hook for validation: it fires when git merge succeeds (no conflicts), before the commit is created. Exit non-zero aborts. Bypass is possible with `--no-verify`, which is acceptable per project scope.

### Supporting Utilities

| Utility | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `mktemp` | POSIX | Atomic temp file creation for write-then-move Gist updates | Always use for intermediate JSON files; never write directly to a shared path |
| `flock` | util-linux (Linux) / `shlock` (macOS) | Local critical-section locking | NOT needed for Gist operations (best-effort is accepted); use only if local lock files are added later |
| `git diff --cached --name-only` | Git builtin | List files staged in a merge commit | Used in `pre-merge-commit` to enumerate changed planning files for validation |

---

## Installation

No package.json. Pure shell. Per-developer setup:

```bash
# 1. Install prerequisites (if not present)
brew install gh jq

# 2. Authenticate GitHub CLI
gh auth login

# 3. Register project git hooks (run once after clone)
bash scripts/setup-hooks.sh
# Which runs:
#   git config core.hooksPath .githooks
#   chmod +x .githooks/*

# 4. Set gist ID in project config
echo '{"gist_id": "YOUR_GIST_ID_HERE"}' > .gsd-team.json
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| GitHub Gist via `gh` CLI | GitHub repo file (same repo) | Never for this use case: a same-repo registry file would create merge conflicts on the very artifact meant to prevent merge conflicts. |
| GitHub Gist via `gh` CLI | Redis / shared DB | If team scales beyond ~10 people and race conditions become frequent enough to require strict locking. Overkill for 3 devs. |
| `jq` for JSON | `python3 -c` / `node -e` | If target machine provably has Python/Node and lacks jq. Both add fragility; jq is the standard tool for this job. |
| `core.hooksPath` | Husky / lefthook | If the project were Node-based. For a pure-shell project, Husky adds a runtime dependency that violates the "bash + gh only" constraint. |
| `pre-merge-commit` git hook | `pre-commit` git hook | `pre-commit` fires on every commit, not just merges. Use `pre-commit` only as a fallback for conflict-resolution commits. |
| `.claude/settings.json` project hooks | User-level `~/.claude/settings.json` | If hooks should be opt-in per developer rather than team-wide. Project-level is correct for team tooling — devs get hooks automatically on clone. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `curl` with raw GitHub API token | Requires token storage and rotation; `gh` handles auth transparently | `gh api` / `gh gist` with `gh auth login` |
| Python / Node for hook scripts | Violates explicit project constraint; adds runtime dependency that may not be present in hook execution context | Bash + jq |
| `post-merge` hook for validation | Fires AFTER commit is created; cannot abort; informational only | `pre-merge-commit` for blocking validation |
| Direct `.git/hooks/` scripts | Not version-controlled; every developer must manually install; no team distribution | `.githooks/` + `core.hooksPath` |
| `jq` version < 1.6 | Pre-1.6 lacks `@base64d`, `env`, and `$ENV` which are needed for robust JSON handling | `jq` 1.7+ (1.8.1 current) |
| Husky | Node runtime dependency; incompatible with "no additional runtimes" constraint | Native git hooks via `core.hooksPath` |
| `gh gist edit` (interactive) | Opens `$EDITOR` interactively; cannot be scripted | `gh api --method PATCH /gists/<id>` |

---

## Stack Patterns by Variant

**If running on macOS Sequoia+:**
- `jq` is preinstalled at `/usr/bin/jq` (1.7+); no Homebrew install needed
- Bash is still 3.2 at `/bin/bash`; use `#!/usr/bin/env bash` shebang to pick up Homebrew bash 5.x if available

**If running on macOS pre-Sequoia:**
- `brew install jq` required in setup script
- Detect with: `command -v jq >/dev/null 2>&1 || { echo "jq required: brew install jq"; exit 1; }`

**If a developer lacks `gh auth login`:**
- All Gist operations fail with a clear error from `gh`
- Setup script should call `gh auth status` and exit with instructions if not authenticated

**If two developers run a GSD command simultaneously (race condition):**
- Both read the same registry state; both write their claim; last write wins
- Detection: after writing, re-read and verify your claim is present; if not, report collision and prompt manual resolution
- This is acceptable per project scope (best-effort concurrency)

---

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| `gh` 2.x | GitHub REST API v3 | All gist operations use REST; no breaking changes in v2.x series |
| `jq` 1.7+ | All bash versions | Filter syntax used (`@json`, `env`, `--arg`) requires 1.6+; 1.7+ recommended |
| `core.hooksPath` | Git 2.9+ | macOS Monterey+ ships Git 2.32+; safe assumption for dev machines |
| CC hooks `UserPromptExpansion` | Claude Code (current) | Verified in current official docs; event name and stdin format stable as of 2026-05 |
| CC hooks `PreToolUse` | Claude Code (current) | Stable; `tool_input.command` field confirmed in official stdin schema |

---

## Sources

- [Claude Code Hooks Reference — code.claude.com](https://code.claude.com/docs/en/hooks) — Hook event names, stdin/stdout contract, exit code semantics, `UserPromptExpansion` details (HIGH confidence, official Anthropic docs)
- [Claude Code Settings — code.claude.com](https://code.claude.com/docs/en/settings) — settings.json location, project vs user scope, array merging behavior (HIGH confidence)
- [gh gist view — cli.github.com](https://cli.github.com/manual/gh_gist_view) — `--raw`, `--filename` flags (HIGH confidence, official GitHub CLI docs)
- [gh gist edit — cli.github.com](https://cli.github.com/manual/gh_gist_edit) — edit flags and limitations; `gh api PATCH` recommended for scripting (HIGH confidence)
- [REST API endpoints for gists — docs.github.com](https://docs.github.com/en/rest/gists/gists) — PATCH `/gists/{gist_id}` body structure, authentication requirements (HIGH confidence)
- [Rate limits for the REST API — docs.github.com](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — 5,000 req/hour authenticated (HIGH confidence)
- [Git Hooks — git-scm.com](https://git-scm.com/docs/githooks) — `pre-merge-commit`, `post-merge` behavior, arguments, environment (HIGH confidence, official Git docs)
- [Two Ways to Share Git Hooks with Your Team — viget.com](https://www.viget.com/articles/two-ways-to-share-git-hooks-with-your-team) — `core.hooksPath` team distribution pattern (MEDIUM confidence)
- [jq — jqlang.org](https://jqlang.org/) — version 1.8.1 current, macOS Sequoia preinstall confirmed (HIGH confidence)
- [bats-core — github.com](https://github.com/bats-core/bats-core) — Bash Automated Testing System for hook script unit tests (MEDIUM confidence)

---
*Stack research for: GSD Team Coordination Plugins (Claude Code hooks + git hooks + GitHub Gist registry)*
*Researched: 2026-05-19*
