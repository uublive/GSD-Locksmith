---
phase: quick
plan: 260521-l1o
subsystem: infra
tags: [bash, cc-hooks, registry, PostToolUse, ownership]
status: complete
---

# Summary: Registry Ownership Context Hook

## Performance
- Duration: ~10 min
- Tasks: 2 of 2 complete

## Accomplishments

- `.gsd/ownership-context.sh` created — PostToolUse hook on Bash that fires after `gsd-sdk query roadmap` or `gsd-sdk query init` commands. Reads team registry from orphan branch, builds ownership summary grouped by milestone, marks current user's claims with `← you`, and injects as `additionalContext`.
- Fast-path exit for non-matching commands (no performance impact on other Bash calls).
- All error paths exit 0 — hook never blocks GSD workflows if registry is unreachable or empty.
- `.claude/settings.json` updated with PostToolUse entry for Bash matcher.
- `.gsd/install-hooks.sh` updated to configure both PreToolUse (roadmap gate) and PostToolUse (ownership context) hooks for new clones.

## Task Commits

1. **Task 1: ownership-context.sh** — `d789cda` (feat)
2. **Task 2: settings.json + install script wiring** — `7a375f2` (feat)

## Files Created/Modified

- `.gsd/ownership-context.sh` (created, 66 lines)
- `.claude/settings.json` (modified — added PostToolUse section)
- `.gsd/install-hooks.sh` (modified — added ownership hook to installer)

## Decisions Made

- PostToolUse on Bash (not Read) — because GSD reads ROADMAP.md via `gsd-sdk query` Bash calls, not the Read tool
- jq group_by for milestone grouping — produces clean per-milestone ownership lines
- `← you` marker for current user — makes own claims instantly recognizable
- Enrichment, not filtering — Claude sees all claims and makes informed routing suggestions
