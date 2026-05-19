# Research Summary: GSD Team Coordination Plugins

**Domain:** Shell-based CLI plugin system — Claude Code hooks + git hooks + GitHub Gist shared registry
**Researched:** 2026-05-19
**Confidence:** HIGH

## Executive Summary

Zero-infrastructure team coordination layer for a 3-person dev team using GSD. Eliminates manual Slack coordination for sequential number claiming (milestones, phases) and adds merge-time integrity validation for planning files. Pure Bash + `gh` CLI + `jq` — no Node, Python, or server infrastructure.

Two independent subsystems: CC PreToolUse hooks intercept `/gsd-new-milestone` and `/gsd-new-phase` at creation time, claiming the next available number from a shared GitHub Gist registry. Separately, a `pre-merge-commit` git hook validates planning file integrity at merge time. Shared foundation: `hooks/lib/gist.sh`.

## Recommended Stack

- **Bash 5.x** — sole runtime for all hook scripts
- **`gh` CLI 2.x** — Gist read/write, OAuth handled via `gh auth login`
- **`jq` 1.7+** — mandatory for JSON handling (CC hook stdin/stdout is JSON)
- **Git `core.hooksPath`** (Git 2.9+) — version-controlled git hook distribution
- **Claude Code `PreToolUse` hooks** — exit code 2 to block, exit code 1 is non-blocking (critical distinction)
- **`gh api --method PATCH`** for gist writes (not `gh gist edit` which opens `$EDITOR`)

## Table Stakes Features

- Gist config file (`.claude/gsd-config` with `GIST_ID`)
- Milestone + phase number allocation (core bash functions)
- CC hook auto-interception of `/gsd-new-milestone` and `/gsd-new-phase`
- Branch + owner + timestamp metadata in every registry entry
- Duplicate REQ-ID detection at merge time
- Phase numbering gap detection at merge time
- Clear error output with actionable remediation
- Installation script for git hooks

## Critical Pitfalls

1. **Exit code 1 vs 2 in CC hooks** — exit 1 is non-blocking; only exit 2 blocks tool execution. Using exit 1 creates security theater.
2. **Shell profile output corrupts hook JSON** — `.zshrc`/`.bashrc` must guard interactive-only output behind `[[ $- == *i* ]]`.
3. **`gh` auth state differs between shell and CC subprocess** — test from within CC session, not just terminal.
4. **Git hooks not auto-installed on clone** — install script must ship with hooks, not as follow-up.
5. **Stale registry entries accumulate** — include `claimed_at` and `branch` in schema from day one for GC.

## Architecture

Two independent subsystems connected by shared library:
- **CC hooks** → `gsd-claim-number.sh` → `hooks/lib/gist.sh` → GitHub Gist (claim at creation)
- **Git hooks** → `gsd-validate-merge.sh` → `hooks/lib/validate.sh` → `.planning/` files (validate at merge)
- **Config** → `.claude/gsd-config` (gist ID) + `.claude/settings.json` (hook wiring)

Build order: gist library first → claim scripts → CC hook wiring → validation scripts → git hook wiring → setup automation.

## Suggested Phase Structure

1. **Foundation** — config, `gist.sh` library, registry JSON schema
2. **CC Hooks: Number Claiming** — claim-before-create, PreToolUse wiring
3. **Git Hooks: Merge Validation** — duplicate REQ-ID + phase gap detection
4. **Cleanup and Developer Setup** — release lifecycle + onboarding automation
5. **Observability and Resilience** (v1.x) — `gsd-status`, collision warnings, dry-run
6. **Advanced Integrity Checks** (v1.x, deferred) — STATE.md drift, stale cross-references

Phases 2 and 3 are independent once Phase 1 is done and could parallelize.

## Research Flags

- Phase 2: CC hook `if` field syntax in `settings.json` needs live testing
- Phase 3: `pre-merge-commit` file read method (`git show :path` vs working tree) needs verification
- Phase 1: Resolve `gh gist edit` vs `gh api PATCH` for write path

## Sources

- Claude Code Hooks Reference — code.claude.com/docs/en/hooks
- GitHub REST API for Gists — docs.github.com/en/rest/gists/gists
- gh CLI Manual — cli.github.com/manual
- Git Hooks — git-scm.com/docs/githooks
- jq — jqlang.org

---
*Research completed: 2026-05-19*
*Ready for roadmap: yes*
