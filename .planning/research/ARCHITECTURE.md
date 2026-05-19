# Architecture Research

**Domain:** CLI plugin system with shared external registry (Claude Code hooks + git hooks + GitHub Gist)
**Researched:** 2026-05-19
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DEVELOPER WORKSTATION                         │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                   CLAUDE CODE SESSION                         │   │
│  │                                                              │   │
│  │   User runs /gsd-new-milestone or /gsd-new-phase            │   │
│  │         ↓                                                    │   │
│  │   PreToolUse hook fires (Bash matcher)                       │   │
│  │         ↓                                                    │   │
│  │   gsd-claim-number.sh (receives JSON on stdin)               │   │
│  │         ↓                                                    │   │
│  │   Returns: exit 0 (allow) or exit 2 (block) + additionalCtx │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    GIT WORKING TREE                           │   │
│  │                                                              │   │
│  │   git merge feature/xyz → development                       │   │
│  │         ↓                                                    │   │
│  │   pre-merge-commit hook fires                                │   │
│  │         ↓                                                    │   │
│  │   gsd-validate-merge.sh                                      │   │
│  │   (gap detection, dup REQ-IDs, STATE drift, stale refs)      │   │
│  │         ↓                                                    │   │
│  │   Exits 0 (proceed) or non-zero (abort merge)               │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                     gh CLI (HTTPS + auth)
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       GITHUB GIST (shared)                           │
│                                                                      │
│   registry.json                                                      │
│   {                                                                  │
│     "milestones": {                                                  │
│       "3": {"branch": "feature/xyz", "owner": "alice",              │
│              "claimed_at": "2026-05-19T10:00:00Z"}                  │
│     },                                                               │
│     "phases": {                                                      │
│       "3.1": {"branch": "feature/xyz", "owner": "alice",            │
│               "claimed_at": "2026-05-19T10:00:00Z"}                 │
│     }                                                                │
│   }                                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| `.claude/settings.json` | Declares hooks wiring — maps GSD command patterns to claim scripts | JSON config file, committed to repo, loaded by CC per project |
| `gsd-claim-number.sh` | Reads gist registry, determines next free number, writes claim back, outputs number to Claude context | Bash script, invoked as PreToolUse command hook |
| `gsd-release-number.sh` | Removes a claim from the gist registry when a branch is abandoned or merged | Bash script, called manually or from post-merge git hook |
| `gsd-validate-merge.sh` | Parses planning files on the branch being merged, runs all integrity checks, reports violations | Bash script, invoked as pre-merge-commit git hook |
| `registry.json` (in Gist) | Single source of truth for claimed milestone/phase numbers — stores branch, owner, timestamp per claim | JSON file inside a private GitHub Gist |
| `.claude/gsd-config` | Per-project config: gist ID, project prefix, team member names | Shell-sourceable config file, committed to repo |
| `.githooks/` | Shareable git hooks directory; activated via `git config core.hooksPath .githooks` | Directory committed to repo |

## Recommended Project Structure

```
.claude/
├── settings.json          # CC hook declarations (PreToolUse matchers)
└── gsd-config             # GIST_ID, PROJECT_PREFIX, etc.

.githooks/
├── pre-merge-commit       # Validates planning files before merge commit
└── post-merge             # Releases stale claims after successful merge

hooks/
├── gsd-claim-number.sh    # Registry read-modify-write, number allocation
├── gsd-release-number.sh  # Registry cleanup on merge/abandon
├── gsd-validate-merge.sh  # All integrity checks (gap, dup, drift, stale)
└── lib/
    ├── gist.sh            # gh CLI wrappers: read_registry(), write_registry()
    ├── validate.sh        # Pure validation functions (no side effects)
    └── output.sh          # Formatted output helpers for Claude context

README-HOOKS.md            # One-time setup: gh auth login, git config core.hooksPath
```

### Structure Rationale

- **`.claude/`**: CC reads `settings.json` from here automatically; keeps CC config separate from git hooks
- **`.githooks/`**: Committed hooks directory; each dev activates once with `git config core.hooksPath .githooks`; avoids `.git/hooks/` which is not tracked by git
- **`hooks/`**: The actual scripts; separated from hook declarations so scripts can be tested standalone
- **`hooks/lib/`**: Shared functions extracted to avoid duplication; `gist.sh` is the single place where `gh` API calls live, making it easy to swap or mock in tests

## Architectural Patterns

### Pattern 1: Claim-Before-Create (PreToolUse Gate)

**What:** A PreToolUse hook intercepts GSD commands that create milestones/phases. The hook's shell script performs the registry read-modify-write and injects the allocated number back into Claude's context before the command executes.

**When to use:** Any time a numbered artifact must be globally unique across concurrent developers.

**Trade-offs:** Adds ~1-2s latency to every creation command (gh API round-trip). Acceptable for planning operations that happen once per session.

**Example:**
```json
// .claude/settings.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "if": "Bash(/gsd-new-milestone*)",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/hooks/gsd-claim-number.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

```bash
# hooks/gsd-claim-number.sh — receives JSON on stdin
INPUT=$(cat)
TYPE=$(echo "$INPUT" | jq -r '.tool_input.command' | grep -oP '(?<=gsd-new-)\w+')

source "$(dirname "$0")/../.claude/gsd-config"
source "$(dirname "$0")/lib/gist.sh"

REGISTRY=$(read_registry)
NEXT_NUM=$(echo "$REGISTRY" | jq -r ".[\"${TYPE}s\"] | keys | map(tonumber) | max + 1")

UPDATED=$(echo "$REGISTRY" | jq \
  ".[\"${TYPE}s\"][\"$NEXT_NUM\"] = {branch: \"$(git branch --show-current)\", owner: \"$GSD_OWNER\", claimed_at: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}")

write_registry "$UPDATED"

# Inject number into Claude's context
jq -n --arg num "$NEXT_NUM" '{
  additionalContext: ("Allocated \(env.TYPE) number: " + $num + ". Use this number in the command.")
}'
exit 0
```

### Pattern 2: Registry Read-Modify-Write via gh API

**What:** All registry mutations follow a strict three-step sequence: (1) read current state via `gh gist view --raw`, (2) compute new state in memory with `jq`, (3) write back via `gh api PATCH`. This is the only access pattern for the shared Gist.

**When to use:** Every operation that changes claimed numbers.

**Trade-offs:** Race window between step 1 and step 3 exists (~200ms). For a 3-person team, simultaneous creation commands are rare enough that manual collision resolution is acceptable (per project decision).

**Example:**
```bash
# hooks/lib/gist.sh
GIST_FILE="registry.json"

read_registry() {
  gh gist view "$GIST_ID" --filename "$GIST_FILE" --raw
}

write_registry() {
  local content="$1"
  local tmpfile
  tmpfile=$(mktemp /tmp/gsd-registry-XXXXXX.json)
  echo "$content" > "$tmpfile"
  gh gist edit "$GIST_ID" --filename "$GIST_FILE" "$tmpfile"
  rm -f "$tmpfile"
}
```

### Pattern 3: Pre-Merge-Commit Validation Gate

**What:** The `pre-merge-commit` git hook runs all planning file integrity checks against files being merged. It parses markdown files, extracts structured data (phase numbers, REQ-IDs, STATE entries, cross-references), and detects violations. Non-zero exit aborts the merge.

**When to use:** Every merge to the `development` branch. The hook is installed in `.githooks/` so it fires automatically.

**Trade-offs:** Slower than pre-commit (runs after merge computation, before commit creation). This is correct for this use case — we need to see the merged state of planning files, not just the branch's files.

**Example:**
```bash
# .githooks/pre-merge-commit
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(git rev-parse --show-toplevel)/hooks"
source "$SCRIPT_DIR/lib/validate.sh"

VIOLATIONS=0

check_phase_gaps && VIOLATIONS=$((VIOLATIONS + $?)) || true
check_duplicate_req_ids && VIOLATIONS=$((VIOLATIONS + $?)) || true
check_state_drift && VIOLATIONS=$((VIOLATIONS + $?)) || true
check_stale_references && VIOLATIONS=$((VIOLATIONS + $?)) || true

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "ERROR: $VIOLATIONS planning integrity violation(s). Merge aborted." >&2
  exit 1
fi
exit 0
```

## Data Flow

### Number Allocation Flow (Happy Path)

```
Developer types: /gsd-new-milestone
        ↓
Claude Code: Bash tool about to execute with command "/gsd-new-milestone"
        ↓
PreToolUse fires → gsd-claim-number.sh receives JSON on stdin
        ↓
  read_registry() → gh gist view GIST_ID --raw → registry.json content
        ↓
  jq: find max existing number, compute NEXT = max + 1
        ↓
  jq: add claim entry {branch, owner, claimed_at} to registry
        ↓
  write_registry() → tmpfile → gh gist edit → GitHub Gist updated
        ↓
  stdout: JSON with additionalContext "Allocated milestone number: 4"
        ↓
exit 0 → Claude Code receives context injection, executes /gsd-new-milestone with number 4
```

### Number Allocation Flow (Collision Path)

```
Alice and Bob both run /gsd-new-milestone within ~200ms
        ↓
Both read registry showing max = 3
        ↓
Both compute NEXT = 4
        ↓
Alice writes first → registry shows claim "4" = Alice
Bob writes ~100ms later → registry shows claim "4" = Bob (Alice's write is overwritten)
        ↓
Both devs now have milestone 4 — collision detected at next registry read
        ↓
RESOLUTION: Manual — one dev runs gsd-release-number.sh 4 and re-runs /gsd-new-milestone
```

**Note:** This is the accepted "best-effort" concurrency model per project decision. Collision detection surfaces at next read; no automatic resolution is provided.

### Merge Validation Flow

```
git merge feature/xyz (targeting development)
        ↓
Git computes merge result (files merged in memory)
        ↓
pre-merge-commit hook fires (merged state is staged, not yet committed)
        ↓
gsd-validate-merge.sh reads staged .planning/ files
        ↓
  check_phase_gaps: parse ROADMAP.md, verify phase numbers are sequential
  check_duplicate_req_ids: parse REQUIREMENTS.md, detect REQ-ID collisions
  check_state_drift: compare STATE.md phases vs ROADMAP.md phases
  check_stale_references: find phase/req references in plans, verify targets exist
        ↓
All checks pass → exit 0 → merge commit created
Any check fails → exit 1 → merge aborted, violations printed to stderr
```

### Registry Release Flow

```
git merge feature/xyz completes successfully
        ↓
post-merge hook fires
        ↓
gsd-release-number.sh reads branch name from merged ref
        ↓
read_registry() → find all claims where branch = merged branch
        ↓
Remove those claims from registry JSON
        ↓
write_registry() → registry updated, numbers available for reuse
```

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| GitHub Gist API | `gh gist view --raw` (read) + `gh gist edit` or `gh api PATCH` (write) | Requires `gh auth login`; GIST_ID stored in `.claude/gsd-config`; no auth tokens needed beyond gh's credential store |
| Claude Code settings.json | Hook declarations in `.claude/settings.json`; scripts invoked as `type: "command"` | `${CLAUDE_PROJECT_DIR}` resolves to repo root at runtime; scripts must be executable |
| Git hooks system | `.githooks/` directory activated via `git config core.hooksPath .githooks` | One-time per developer; `pre-merge-commit` is the primary hook; `post-merge` for cleanup |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| CC hook → claim script | JSON on stdin (tool_name, tool_input.command, cwd, session_id) | Script reads stdin, parses with jq; outputs JSON with additionalContext |
| claim script → gist lib | Shell function calls; string passing (registry JSON) | lib/gist.sh is sourced; functions return data via stdout |
| claim script → Claude | JSON stdout with additionalContext field | Injected into Claude's context window; informs subsequent command execution |
| git hook → validate lib | Shell function calls; exit codes | validate.sh functions return violation counts; hook sums and exits accordingly |
| validate script → planning files | Direct file reads via git show HEAD:path or staged file paths | Must read merged state (staged), not working tree or branch head |

## Anti-Patterns

### Anti-Pattern 1: Writing Registry State Into the Repo

**What people do:** Store the claims registry in a `.planning/registry.json` file committed to the repo.

**Why it's wrong:** Every claim or release generates a commit. Feature branches diverge from development, so registry updates conflict on every merge — the very problem the registry is meant to solve. Merge conflicts in the registry itself create a circular problem.

**Do this instead:** Use an external store (GitHub Gist) that is not branch-aware and has no merge semantics. All developers write to the same flat namespace.

### Anti-Pattern 2: Blocking on Gist Write in a Synchronous Validation Hook

**What people do:** Put the registry write inside the pre-merge-commit git hook to "validate then claim."

**Why it's wrong:** The pre-merge-commit hook should only read and validate — it fires inside a critical git operation. A gh API failure (network, rate limit) would abort every merge, even when the planning files are perfectly valid.

**Do this instead:** Separate concerns. CC hooks handle claiming (write); git hooks handle validation (read-only). The registry is advisory — it prevents accidental collisions at creation time, not at merge time.

### Anti-Pattern 3: Using a Single Monolithic Hook Script

**What people do:** Put all logic — gist reads, number allocation, file validation, output formatting — in one large shell script.

**Why it's wrong:** Claude Code invokes the claim hook on every matching Bash tool call. A script that tries to do everything (validate AND claim AND release) has complex branching on command content and is fragile to test. A validation script that also touches the gist wastes a network round-trip during merge.

**Do this instead:** One script per responsibility. Shared logic goes in `hooks/lib/`. The hook declarations in `settings.json` wire specific scripts to specific command patterns using the `if` field.

### Anti-Pattern 4: Hardcoding the Gist ID in Scripts

**What people do:** Embed `GIST_ID="abc123..."` at the top of each hook script.

**Why it's wrong:** Rotating the gist (if compromised or lost) requires editing every script. New team members who fork the approach for other projects must diff-hunt the ID.

**Do this instead:** Store `GIST_ID` in `.claude/gsd-config` (a shell-sourceable key=value file, committed to the repo). All scripts `source "$REPO_ROOT/.claude/gsd-config"`. One place to change.

## Build Order (Phase Dependencies)

The components have a clear build dependency chain that must inform roadmap phase sequencing:

```
Phase 1: Foundation
  └── .claude/gsd-config (config schema)
  └── hooks/lib/gist.sh (gh API wrappers — all other scripts depend on this)
  └── Registry JSON schema definition

Phase 2: CC Hook — Number Claiming
  └── Depends on: gist.sh lib (Phase 1)
  └── gsd-claim-number.sh
  └── .claude/settings.json (PreToolUse wiring)
  └── Manual test: run /gsd-new-milestone, verify registry updated

Phase 3: Git Hook — Merge Validation
  └── Depends on: Phase 1 (gist.sh for any registry reads in future)
  └── hooks/lib/validate.sh (pure validation functions)
  └── gsd-validate-merge.sh
  └── .githooks/pre-merge-commit
  └── Manual test: create conflicting branch, attempt merge

Phase 4: Cleanup & Release
  └── Depends on: gist.sh lib (Phase 1)
  └── gsd-release-number.sh
  └── .githooks/post-merge
  └── Manual test: merge succeeds, claims removed from registry

Phase 5: Developer Setup Automation
  └── Depends on: all previous phases
  └── README-HOOKS.md or setup.sh script
  └── Validates: gh auth status, core.hooksPath configured, GIST_ID accessible
```

**Critical dependency:** `hooks/lib/gist.sh` is the single most load-bearing component. If the gh CLI interface changes or auth fails, every other script fails. It must be built and tested first, and should include error handling for auth failures and network timeouts.

## Scaling Considerations

This system is scoped to a 3-person team by design. Scaling considerations are included for completeness but are explicitly out of scope per PROJECT.md.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 2-5 devs (current) | Best-effort read-modify-write; manual collision resolution; GitHub Gist sufficient |
| 6-15 devs | Collision rate rises; consider adding an ETag/version field to registry JSON for basic optimistic locking detection; Gist still works |
| 15+ devs | Gist throughput becomes a bottleneck; migrate to a lightweight HTTP service with proper locking (Redis SETNX, Postgres advisory locks) |

## Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — Hook event lifecycle, settings.json schema, stdin/stdout contract, exit code behavior (HIGH confidence, official docs)
- [gh gist view manual](https://cli.github.com/manual/gh_gist_view) — `--raw` and `--filename` flags (HIGH confidence, official docs)
- [gh gist edit manual](https://cli.github.com/manual/gh_gist_edit) — `--filename`, `--add`, `--remove` flags (HIGH confidence, official docs)
- [Git githooks documentation](https://git-scm.com/docs/githooks) — `pre-merge-commit` and `post-merge` hook specifications (HIGH confidence, official docs)
- [Scripting with GitHub CLI](https://github.blog/engineering/engineering-principles/scripting-with-github-cli/) — `gh api` PATCH patterns for non-interactive gist updates (MEDIUM confidence, official GitHub blog)
- [Atomic Read-Modify-Write failure patterns](https://thomwright.co.uk/failure-patterns/atomic-read-then-write/) — Concurrency race window characterization (MEDIUM confidence)

---
*Architecture research for: GSD Team Coordination Plugins — CLI plugin system with shared GitHub Gist registry*
*Researched: 2026-05-19*
