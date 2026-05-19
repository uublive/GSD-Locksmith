# Phase 1: Registry & Allocation Core - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 1-Registry & Allocation Core
**Areas discussed:** Registry Schema, Config File Format, Allocation Strategy, Script Organization

---

## Registry Schema

### JSON Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Flat array | All claims in one array with a 'type' field. Simple jq queries, easy to scan raw JSON. | ✓ |
| Nested by milestone | Each milestone is a key with its phases nested inside. Natural grouping but deeper jq paths. | |

**User's choice:** Flat array
**Notes:** User preferred simplicity of jq queries and ability to scan raw JSON easily.

### Release Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Mark as released | Add 'status: released' + 'released_at' — keeps history | ✓ |
| Delete on release | Remove the entry entirely — gist stays small but no history | |

**User's choice:** Mark as released
**Notes:** Preserving history preferred over keeping gist small.

### Owner Field

| Option | Description | Selected |
|--------|-------------|----------|
| gh whoami | Use GitHub username from `gh api user` — consistent across machines | ✓ |
| git config user.name | Use local git username — may differ per machine | |

**User's choice:** gh whoami
**Notes:** Consistency across machines was the deciding factor.

---

## Config File Format

### Config Location

| Option | Description | Selected |
|--------|-------------|----------|
| .claude/gsd-team.json | Next to settings.json in .claude/ — hooks already look there | ✓ |
| .gsd-team.env | Shell-sourceable env file at project root — simpler to source | |
| .planning/team.json | Inside .planning/ with other GSD artifacts | |

**User's choice:** .claude/gsd-team.json
**Notes:** Natural home next to CC settings.json where hooks are wired.

### Script Location

| Option | Description | Selected |
|--------|-------------|----------|
| In-repo | hooks/ directory committed to git — versioned with the project | ✓ |
| External install | Scripts installed from a separate package/repo | |

**User's choice:** In-repo
**Notes:** User approved the proposed directory structure layout shown in preview.

---

## Allocation Strategy

### Number Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Max + 1 | Always increment from highest. Numbers never reused. | ✓ |
| First gap fill | Find lowest unclaimed. Keeps numbering compact but reuses numbers. | |

**User's choice:** Max + 1
**Notes:** Predictability and avoiding confusion in git history valued over compact numbering.

### Milestone + Phase Bundling

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, auto-claim phase 1 | Claiming milestone N also claims phase 1 of that milestone | ✓ |
| No, separate claims | Milestone and phases are independent claims | |

**User's choice:** Yes, auto-claim phase 1
**Notes:** Common case optimization — you always start with phase 1.

### Collision Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Re-read and retry once | After writing, re-read gist. If conflict, auto-retry with next number. | ✓ |
| Warn and abort | Detect conflict, print who holds the number, don't auto-fix. | |

**User's choice:** Re-read and retry once
**Notes:** Automatic recovery preferred over manual intervention for the common case.

---

## Script Organization

### Status Command

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone script | `./hooks/gsd-status.sh` run directly from terminal | ✓ |
| CC hook command | Wire as CC hook triggered from Claude | |
| Both | Standalone + CC hook wrapper | |

**User's choice:** Standalone script
**Notes:** User approved the preview output format (table with number, owner, branch, date).

### Dependency Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Fail fast with install hint | Check at script start, exit with install command | ✓ |
| Common precheck function | Shared check_deps() all scripts source | |

**User's choice:** Fail fast with install hint
**Notes:** Immediate actionable feedback preferred.

---

## Claude's Discretion

No areas delegated to Claude's discretion.

## Deferred Ideas

None — discussion stayed within phase scope.
