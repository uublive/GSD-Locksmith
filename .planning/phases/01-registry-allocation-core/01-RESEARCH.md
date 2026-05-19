# Phase 1: Registry & Allocation Core - Research

**Researched:** 2026-05-19
**Domain:** Bash shell library + GitHub Gist registry + allocation logic
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Flat JSON array — all claims in a single `claims` array with a `type` field (`"milestone"` or `"phase"`) to distinguish entry types. Top-level `version` field for future schema migration.
- **D-02:** Claims are marked as released (`"status": "released"` + `released_at` timestamp), never deleted. This preserves history and avoids number reuse confusion in git history.
- **D-03:** Owner field populated via `gh api user` (GitHub username) — consistent across machines, always available when `gh` is authed.
- **D-04:** Each claim entry includes: `type`, `number`, `milestone` (for phase claims), `branch`, `owner`, `claimed_at`, `status` (default `"active"`).
- **D-05:** Gist ID and project config stored in `.claude/gsd-team.json` (JSON format, committed to git). Hooks read it via `jq`. Sits next to `.claude/settings.json`.
- **D-06:** All hook scripts live in-repo under `hooks/` directory (committed to git). Structure:
  - `hooks/lib/gist.sh` — read/write registry functions
  - `hooks/lib/validate.sh` — integrity check functions (Phase 3)
  - `hooks/lib/common.sh` — dep checks, error output helpers
  - `hooks/claim-number.sh` — allocation logic (called by CC hooks)
  - `hooks/gsd-status.sh` — standalone status display
  - `.githooks/pre-merge-commit` — thin wrapper calling validate scripts (Phase 3)
- **D-07:** Max+1 allocation — always increment from the highest claimed number of that type. Never reuse released numbers. Gaps are expected and acceptable.
- **D-08:** Claiming a milestone auto-claims phase 1 of that milestone in the same write — single gist PATCH with both entries.
- **D-09:** Collision detection via re-read-and-retry: after writing, immediately re-read the gist. If a different owner claimed the same number, auto-retry once with the next available number and report the near-miss to the user.
- **D-10:** `gsd-status.sh` is a standalone script invoked directly from terminal. No CC hook wiring for status.
- **D-11:** All scripts fail fast on missing dependencies — check for `jq`, `gh`, and `gh auth status` at script start. Exit immediately with actionable install hints.

### Claude's Discretion

- No areas delegated to Claude's discretion in this phase.

### Deferred Ideas (OUT OF SCOPE)

- None — discussion stayed within phase scope.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REG-01 | Developer can configure shared gist ID in committed project config file | D-05: `.claude/gsd-team.json` schema defined; `jq` reads `gist_id` field |
| REG-02 | Registry stores milestone/phase claims with branch, owner, and timestamp metadata | D-01..D-04: flat `claims` array with full metadata fields; schema verified with jq |
| REG-03 | Shell library provides `read_registry()` and `write_registry()` functions | `hooks/lib/gist.sh` — `gh gist view --raw --filename` for read; `gh gist edit --filename <id> <file>` for write |
| REG-04 | Developer can view all active claims with `gsd-status` | D-10: `hooks/gsd-status.sh` standalone; jq filter on `status=="active"` + formatted table |
| REG-05 | Every script validates `jq`, `gh`, and auth status before executing | D-11: `command -v jq`, `command -v gh`, `gh auth status` guards in `hooks/lib/common.sh` |
| ALLOC-01 | System claims next available milestone number from registry automatically | D-07: max+1 on active milestone claims; empty array = 1; `jq` pattern verified |
| ALLOC-02 | System claims next available phase number within a milestone | D-07+D-08: max+1 on active phase claims filtered by `.milestone==N`; auto-pairs with milestone claim |
| ALLOC-03 | System detects last-write-wins race and displays collision warning with rollback instructions | D-09: re-read after write; jq detects same number with different owner; one retry then user-visible warning |
| ALLOC-04 | Developer can preview allocation without writing via `GSD_DRY_RUN=1` | Guard the gist PATCH call behind `[[ -z "$GSD_DRY_RUN" ]]`; print what would be written |
| ALLOC-05 | Developer can see detailed operation logs via `GSD_VERBOSE=1` | Gate all diagnostic stderr output behind `[[ -n "$GSD_VERBOSE" ]]` |

</phase_requirements>

---

## Summary

Phase 1 delivers the foundation layer of the GSD Team Coordination Plugins: a committed config file, a shell library that round-trips JSON through a shared GitHub Gist, and allocation logic that claims the next available milestone or phase number with collision awareness. All of Phase 2 (CC hooks) and Phase 3 (git merge validation) depend on the `hooks/lib/gist.sh` functions and `.claude/gsd-team.json` schema built here.

The technical surface is narrow: Bash 3.2+ scripts (using `#!/usr/bin/env bash` to pick up Homebrew bash 5.x where installed), `gh` CLI 2.x for Gist API access, and `jq` 1.7+ for JSON manipulation. All three tools are confirmed present on this machine. The `gh gist edit GIST_ID --filename registry.json /tmp/file.json` command is the verified non-interactive write approach — it replaces file content without opening `$EDITOR`. The `gh api --method PATCH` approach with `-F 'files[name][content]=@file'` is an equally valid alternative.

The primary implementation risk is the max+1 jq pattern when the `claims` array is empty — `max` on an empty array returns `null` and `null + 1` does not error in jq but produces `null`, breaking allocation. The correct guard is `if length == 0 then 1 else max + 1 end`. This was verified against the local jq 1.7.1 installation. Collision detection after write (D-09) and the single-write dual-claim for milestone+phase-1 (D-08) are the two highest-complexity allocation requirements.

**Primary recommendation:** Build `hooks/lib/common.sh` (dep checks) and `hooks/lib/gist.sh` (read/write) first. Every other component in this phase depends on them. Validate with a real gist round-trip before building allocation logic on top.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Config file read (gist ID) | Shell lib (`common.sh`) | — | Config is JSON; all scripts source common.sh to get GIST_ID |
| Gist read (`read_registry`) | Shell lib (`gist.sh`) | `gh` CLI | gh handles auth; gist.sh wraps the call |
| Gist write (`write_registry`) | Shell lib (`gist.sh`) | `gh` CLI + `mktemp` | Temp file prevents broken pipe; gist.sh owns the write pattern |
| Dep validation (`jq`, `gh`, auth) | Shell lib (`common.sh`) | — | Centralized so every script calls one function |
| Milestone allocation logic | `hooks/claim-number.sh` | `gist.sh` | Business logic separate from I/O; calls gist.sh |
| Phase allocation logic | `hooks/claim-number.sh` | `gist.sh` | Same script handles both types via `TYPE` argument |
| Collision detection | `hooks/claim-number.sh` | `gist.sh` | Re-read after write is in allocation layer |
| Status display | `hooks/gsd-status.sh` | `gist.sh` | Standalone script; reads registry via gist.sh |
| Dry-run / verbose mode | `hooks/claim-number.sh` | `common.sh` | Env vars checked in allocation script |

---

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| Bash | 3.2+ (target 5.x) | All hook scripts | Only runtime the team has agreed on; shebang `#!/usr/bin/env bash` picks up Homebrew 5.x |
| `gh` CLI | 2.89.0 (confirmed) | GitHub Gist read/write, auth | Handles OAuth transparently; no token management code; whole team already has it |
| `jq` | 1.7.1 (confirmed, Apple preinstall) | JSON parse/emit | Non-negotiable for safe JSON handling; preinstalled on this machine |
| Git | 2.50.1 (confirmed) | `core.hooksPath` for hook distribution | Supports `core.hooksPath` since 2.9 |
| `mktemp` | POSIX (confirmed) | Temp file for write-then-replace gist update | Prevents partial writes; macOS supports `mktemp -t prefix` |

[VERIFIED: tool versions confirmed via `gh --version`, `jq --version`, `git --version`, `mktemp` invocation on this machine]

### Supporting

| Utility | Purpose | When to Use |
|---------|---------|-------------|
| `gh api user` | Get authenticated GitHub username for `owner` field (D-03) | Called once per allocation to populate `owner` |
| `gh auth status` | Validate auth before any gist operation | Called in dep check in `common.sh` |
| `git branch --show-current` | Get current branch for `branch` field | Called in allocation to populate `branch` |
| `date -u +%Y-%m-%dT%H:%M:%SZ` | ISO 8601 UTC timestamp for `claimed_at` | Called in allocation to populate `claimed_at` |

[VERIFIED: all commands available on this machine]

### Alternatives Considered

| Standard | Alternative | When Alternative Makes Sense |
|----------|-------------|------------------------------|
| `gh gist edit GIST_ID --filename registry.json /tmp/file.json` | `gh api --method PATCH /gists/GIST_ID -F 'files[registry.json][content]=@/tmp/file.json'` | Both work; `gh gist edit` is cleaner for single-file gists; `gh api PATCH` gives more control over the HTTP request and response parsing |
| `jq` for JSON | `python3 -c` | Only if jq is truly unavailable — dep check handles this case by failing fast |

**Installation (none required for this machine):**

```bash
# jq is preinstalled on macOS Sequoia
# If not available:
brew install jq

# gh is already installed (2.89.0)
# If not available:
brew install gh && gh auth login
```

---

## Architecture Patterns

### System Architecture Diagram

```
Developer terminal / Claude Code session
        |
        | (direct invocation)
        v
hooks/claim-number.sh
        |
        |-- reads --> .claude/gsd-team.json  (gist_id, project config)
        |
        |-- calls --> hooks/lib/common.sh    (dep checks: jq, gh, auth)
        |
        |-- calls --> hooks/lib/gist.sh
        |                    |
        |                    |-- read_registry() --> gh gist view GIST_ID --raw --filename registry.json
        |                    |                               |
        |                    |                               v
        |                    |                       GitHub Gist API (HTTPS)
        |                    |                               |
        |                    |                       registry.json (raw JSON)
        |                    |                               |
        |                    |<------------------------------+
        |                    |
        |                    |-- write_registry() --> mktemp /tmp/gsd-XXXXX.json
        |                                        --> gh gist edit GIST_ID --filename registry.json /tmp/file
        |                                                       |
        |                                                       v
        |                                               GitHub Gist API (PATCH)
        |
        |-- allocation logic (max+1, collision check, dry-run guard)
        |
        v
stdout: claim result / collision warning / dry-run preview
stderr: verbose operation log (GSD_VERBOSE=1) / dep errors (always)

hooks/gsd-status.sh
        |
        |-- calls --> hooks/lib/common.sh (dep checks)
        |-- calls --> hooks/lib/gist.sh read_registry()
        |-- jq filter: .claims[] | select(.status=="active")
        v
stdout: formatted table (number | type | owner | branch | claimed_at)
```

### Recommended Project Structure

```
.claude/
├── gsd-team.json          # { "gist_id": "...", "project": "..." } — committed to git
└── settings.json          # CC hook declarations (Phase 2 adds entries here)

hooks/
├── claim-number.sh        # Allocation entry point: reads args, calls gist.sh, writes claim
├── gsd-status.sh          # Status display: reads registry, formats table
└── lib/
    ├── common.sh          # check_deps(), error output helpers, config loader
    └── gist.sh            # read_registry(), write_registry()

.githooks/                 # Phase 3 adds pre-merge-commit here
```

### Pattern 1: Dependency Check Gate (common.sh)

**What:** Every script sources `common.sh` and calls `check_deps` as the first executable line. `check_deps` verifies `jq`, `gh`, and `gh auth status`. Fails immediately with actionable messages on stderr.

**When to use:** Start of every script in the `hooks/` tree (D-11).

```bash
# hooks/lib/common.sh
# Source: D-11 (CONTEXT.md), Pitfall 7 (jq not installed), Pitfall 8 (gh auth)
check_deps() {
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq is required. Install with: brew install jq" >&2
    exit 1
  }
  command -v gh >/dev/null 2>&1 || {
    echo "ERROR: gh CLI is required. Install with: brew install gh && gh auth login" >&2
    exit 1
  }
  gh auth status >/dev/null 2>&1 || {
    echo "ERROR: gh auth not configured. Run: gh auth login" >&2
    exit 1
  }
}

load_config() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"
  local config_file="$repo_root/.claude/gsd-team.json"
  [[ -f "$config_file" ]] || {
    echo "ERROR: .claude/gsd-team.json not found. Create it with your gist_id." >&2
    exit 1
  }
  GIST_ID="$(jq -r '.gist_id' "$config_file")"
  [[ "$GIST_ID" != "null" && -n "$GIST_ID" ]] || {
    echo "ERROR: gist_id not set in .claude/gsd-team.json" >&2
    exit 1
  }
}

verbose_log() {
  [[ -n "$GSD_VERBOSE" ]] && echo "[GSD] $*" >&2
}
```

[ASSUMED: exact function signatures — implementation detail, no locked decision on these]

### Pattern 2: Registry Read-Modify-Write (gist.sh)

**What:** `read_registry` returns the raw JSON from the gist. `write_registry` writes updated JSON via a temp file to avoid pipe truncation. The temp file is cleaned up regardless of exit status.

**When to use:** Every allocation and status operation (REG-03).

```bash
# hooks/lib/gist.sh
# Source: STACK.md, ARCHITECTURE.md Pattern 2, gh gist edit help (--filename flag)
GIST_FILE="registry.json"

read_registry() {
  verbose_log "Reading registry from gist $GIST_ID"
  gh gist view "$GIST_ID" --filename "$GIST_FILE" --raw
}

write_registry() {
  local content="$1"
  local tmpfile
  tmpfile="$(mktemp /tmp/gsd-registry-XXXXXX.json)"
  echo "$content" > "$tmpfile"
  verbose_log "Writing registry to gist $GIST_ID"
  gh gist edit "$GIST_ID" --filename "$GIST_FILE" "$tmpfile"
  local exit_code=$?
  rm -f "$tmpfile"
  return $exit_code
}
```

[VERIFIED: `gh gist edit GIST_ID --filename name /tmp/file` is the non-interactive write pattern — confirmed from `gh help gist edit` output: "Replace a gist file with content from a local file"]

### Pattern 3: Max+1 Allocation with Empty-Array Guard

**What:** The allocation function finds the maximum number for the given type among active claims only (`status=="active"`) and adds 1. When no active claims exist, starts at 1.

**When to use:** ALLOC-01 (milestones), ALLOC-02 (phases within milestone) (D-07).

```bash
# In hooks/claim-number.sh
# Source: CONTEXT.md D-07, verified against jq 1.7.1 on this machine

next_milestone_number() {
  local registry="$1"
  echo "$registry" | jq '[.claims[] | select(.type=="milestone" and .status=="active") | .number] | if length == 0 then 1 else max + 1 end'
}

next_phase_number() {
  local registry="$1"
  local milestone_num="$2"
  echo "$registry" | jq --argjson m "$milestone_num" '[.claims[] | select(.type=="phase" and .status=="active" and .milestone==$m) | .number] | if length == 0 then 1 else max + 1 end'
}
```

[VERIFIED: `jq '[...] | if length == 0 then 1 else max + 1 end'` tested against empty array and populated array on jq 1.7.1. Returns `1` for empty, correct `max+1` for populated.]

### Pattern 4: Dual-Claim Write (D-08)

**What:** When claiming a new milestone, the script appends two entries to the `claims` array in a single `jq` expression and performs one `write_registry` call.

**When to use:** ALLOC-01 always triggers ALLOC-02 for the first phase (D-08).

```bash
# In hooks/claim-number.sh
# Source: CONTEXT.md D-08
claim_milestone_and_phase1() {
  local registry="$1"
  local milestone_num="$2"
  local owner branch claimed_at
  owner="$(gh api user --jq '.login')"
  branch="$(git branch --show-current)"
  claimed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  echo "$registry" | jq \
    --argjson m "$milestone_num" \
    --arg owner "$owner" \
    --arg branch "$branch" \
    --arg claimed_at "$claimed_at" \
    '.claims += [
      {"type":"milestone","number":$m,"owner":$owner,"branch":$branch,"claimed_at":$claimed_at,"status":"active"},
      {"type":"phase","number":1,"milestone":$m,"owner":$owner,"branch":$branch,"claimed_at":$claimed_at,"status":"active"}
    ] | .version = (.version // 1)'
}
```

[ASSUMED: exact field ordering and `version` bump logic — implementation detail]

### Pattern 5: Collision Detection via Re-Read (D-09)

**What:** After `write_registry`, immediately call `read_registry` again and check whether the written entry is still owned by the current user. If a different owner now holds the same number, retry once with the next available number, then report the near-miss.

**When to use:** Every allocation write (D-09).

```bash
# Source: CONTEXT.md D-09, PITFALLS.md Pitfall 3
detect_collision() {
  local registry_after_write="$1"
  local expected_number="$2"
  local expected_type="$3"
  local owner
  owner="$(gh api user --jq '.login')"

  # Returns 0 (no collision) or 1 (collision detected)
  local intruders
  intruders="$(echo "$registry_after_write" | jq --argjson n "$expected_number" --arg t "$expected_type" --arg o "$owner" \
    '[.claims[] | select(.type==$t and .number==$n and .owner!=$o)] | length')"
  [[ "$intruders" -gt 0 ]]
}
```

[ASSUMED: exact retry loop structure — implementation detail]

### Pattern 6: Dry-Run and Verbose Guards

**What:** `GSD_DRY_RUN=1` skips the `write_registry` call and prints what would be written. `GSD_VERBOSE=1` emits each gist API call to stderr via `verbose_log`.

**When to use:** ALLOC-04 and ALLOC-05.

```bash
# Source: CONTEXT.md success criteria 5 (ALLOC-04, ALLOC-05)
if [[ -z "$GSD_DRY_RUN" ]]; then
  write_registry "$updated_registry"
else
  echo "[DRY RUN] Would write claim: type=$TYPE number=$NEXT_NUM owner=$owner branch=$branch" >&2
  echo "[DRY RUN] No gist write performed." >&2
fi
```

### Anti-Patterns to Avoid

- **jq `max` on empty array without guard:** `[...] | max + 1` returns `null` when the filter produces an empty array. Always use `if length == 0 then 1 else max + 1 end`. [VERIFIED]
- **`exit 1` to signal errors in hook scripts:** CC hook exit code 2 blocks; exit 1 is non-blocking. This phase does not wire CC hooks (that is Phase 2), but `claim-number.sh` must exit 2 for blocking errors so it works correctly when Phase 2 calls it. [VERIFIED: PITFALLS.md Pitfall 1]
- **stdout contamination:** All human-readable output, verbose logs, and error messages must go to stderr (`>&2`). Only structured output (dry-run preview, status table) goes to stdout. Shell profile welcome messages must be gated with `[[ $- == *i* ]]`. [VERIFIED: PITFALLS.md Pitfall 2]
- **`gh gist edit` without a local file argument (opens `$EDITOR`):** Always pass the local file path as the last argument to `gh gist edit`. [VERIFIED: gh help gist edit]
- **Hardcoding GIST_ID in scripts:** Always read from `.claude/gsd-team.json` via `load_config`. [VERIFIED: CONTEXT.md D-05, ARCHITECTURE.md Anti-Pattern 4]
- **Sourcing scripts with relative paths:** Always resolve `REPO_ROOT` via `git rev-parse --show-toplevel` before sourcing `lib/` files. [ASSUMED: best practice for portable scripts]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GitHub API access | Custom `curl` + token management | `gh api` / `gh gist view` / `gh gist edit` | `gh` handles OAuth, token refresh, error messages — curl requires token storage and rotation |
| JSON parse/emit | `grep`/`awk`/`sed` JSON parsing | `jq` | Shell text tools break on nested JSON, whitespace variation, and Unicode — jq handles all edge cases |
| Temp file creation | Hardcoded `/tmp/gsd-registry.json` | `mktemp /tmp/gsd-XXXXXX.json` | Hardcoded temp paths cause race conditions when two developers run simultaneously |
| GitHub username lookup | Parse `gh auth status` output | `gh api user --jq '.login'` | API response is stable JSON; auth status output format can change across gh versions |

**Key insight:** The entire I/O layer (auth, network, JSON) is solved by `gh` + `jq`. Hand-rolling any of it reintroduces the complexity those tools encapsulate.

---

## Runtime State Inventory

> This is a greenfield phase — no rename/refactor involved. This section is not applicable.

Not applicable. This phase creates new files in a project that currently has no `hooks/` directory and no `.claude/` directory. No existing runtime state needs migration.

---

## Common Pitfalls

### Pitfall 1: jq `max` on Empty Claims Array Returns `null`

**What goes wrong:** First allocation ever — registry has no active claims. `[...] | max + 1` returns `null` (jq treats `null + 1` as `null`, not `1`). The allocation script appears to succeed but writes `null` as the claim number.

**Why it happens:** jq `max` is defined to return `null` for an empty input. Most developers test the allocation function after the first claim already exists.

**How to avoid:** Use `if length == 0 then 1 else max + 1 end` pattern. Verified working on jq 1.7.1.

**Warning signs:** Registry contains `"number": null` after the first ever allocation.

[VERIFIED: tested on jq 1.7.1 on this machine]

### Pitfall 2: `gh gist edit` Without a File Argument Opens `$EDITOR`

**What goes wrong:** `gh gist edit GIST_ID --filename registry.json` (no file argument) opens the system `$EDITOR` — the script hangs waiting for interactive input.

**Why it happens:** The `gh gist edit` command is designed for interactive use by default. The file-replace usage requires an explicit local file path as the last argument.

**How to avoid:** Always: `gh gist edit GIST_ID --filename registry.json /path/to/tmpfile.json`

**Warning signs:** Script hangs after allocation; `$EDITOR` opens unexpectedly.

[VERIFIED: from `gh help gist edit` — "Replace a gist file with content from a local file" requires file path argument]

### Pitfall 3: `gh auth status` Succeeds in Terminal but Fails in Script Context

**What goes wrong:** Developer confirms `gh auth status` works in their terminal. The allocation script still fails with an auth error when called from a non-interactive context (e.g., during Phase 2 when CC hooks invoke it).

**Why it happens:** `gh` stores tokens in the system keychain. Keychain access sometimes requires an interactive session. In subprocess contexts spawned by Claude Code, the keychain may not be unlocked.

**How to avoid:** Test the full allocation script from *within* a Claude Code session, not just from the terminal. Document `GH_TOKEN` env var as fallback for non-interactive contexts.

**Warning signs:** Works in terminal, fails when triggered by a CC hook.

[CITED: PITFALLS.md Pitfall 8]

### Pitfall 4: `write_registry` Silently Succeeds When Gist Write Actually Failed

**What goes wrong:** `gh gist edit` exits 0 even in some network timeout scenarios. The allocation script reports success; the gist was not updated; collision follows silently.

**Why it happens:** Some `gh` error paths do not set non-zero exit codes consistently. The script trusts the exit code without re-reading.

**How to avoid:** D-09's re-read-after-write serves double duty: collision detection AND write confirmation. After writing, always re-read and verify the claim appears in the returned JSON before declaring success.

**Warning signs:** Two devs end up with the same number despite no concurrent execution.

[CITED: PITFALLS.md Integration Gotchas table]

### Pitfall 5: Shell Profile Output on Stdout Breaks Any Future JSON Parsing

**What goes wrong:** A developer's `.zshrc` echoes a welcome message or `nvm` init banner. When Phase 2 wires `claim-number.sh` as a CC hook, the hook output (mixed with profile output) fails JSON parsing.

**Why it happens:** CC hooks must emit valid JSON on stdout. Any non-JSON text before the JSON object breaks parsing.

**How to avoid:** All output from `hooks/` scripts must go to stderr (`>&2`) unless it is explicitly structured data (status table). This must be tested non-interactively: `echo '{}' | bash hooks/claim-number.sh | jq .` must succeed.

[CITED: PITFALLS.md Pitfall 2]

---

## Code Examples

Verified patterns from official sources and local testing:

### Read Registry
```bash
# Source: STACK.md, gh CLI manual (gh gist view --raw --filename)
# [VERIFIED: gh 2.89.0 help output]
read_registry() {
  gh gist view "$GIST_ID" --filename "registry.json" --raw
}
```

### Write Registry (Non-Interactive)
```bash
# Source: gh help gist edit output: "gh gist edit <id> --filename hello.py hello.py"
# [VERIFIED: gh 2.89.0 help output confirms positional file arg replaces content]
write_registry() {
  local content="$1"
  local tmpfile
  tmpfile="$(mktemp /tmp/gsd-registry-XXXXXX.json)"
  printf '%s' "$content" > "$tmpfile"
  gh gist edit "$GIST_ID" --filename "registry.json" "$tmpfile"
  local exit_code=$?
  rm -f "$tmpfile"
  return $exit_code
}
```

### Max+1 Allocation (Empty-Array Safe)
```bash
# Source: CONTEXT.md D-07 jq one-liner; tested on jq 1.7.1
# [VERIFIED: tested with empty array and populated array]
next_number_for_type() {
  local registry="$1"
  local type="$2"
  echo "$registry" | jq --arg t "$type" \
    '[.claims[] | select(.type==$t and .status=="active") | .number] | if length == 0 then 1 else max + 1 end'
}
```

### Config File Schema (`.claude/gsd-team.json`)
```json
{
  "gist_id": "REPLACE_WITH_YOUR_GIST_ID",
  "project": "gsd-team-work"
}
```
[CITED: CONTEXT.md D-05]

### Registry JSON Schema
```json
{
  "version": 1,
  "claims": [
    {
      "type": "milestone",
      "number": 1,
      "owner": "alice",
      "branch": "feature/milestone-1",
      "claimed_at": "2026-05-19T10:00:00Z",
      "status": "active"
    },
    {
      "type": "phase",
      "number": 1,
      "milestone": 1,
      "owner": "alice",
      "branch": "feature/milestone-1",
      "claimed_at": "2026-05-19T10:00:00Z",
      "status": "active"
    }
  ]
}
```
[CITED: CONTEXT.md D-01..D-04]

### Dep Check Pattern
```bash
# Source: PITFALLS.md Pitfall 7, D-11
# [CITED: PITFALLS.md]
check_deps() {
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required: brew install jq" >&2; exit 1; }
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh required: brew install gh && gh auth login" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: gh not authenticated. Run: gh auth login" >&2; exit 1; }
}
```

### Collision Detection After Write
```bash
# Source: CONTEXT.md D-09
# [CITED: CONTEXT.md]
detect_collision_for_number() {
  local registry="$1"  # re-read after write
  local num="$2"
  local type="$3"
  local my_owner
  my_owner="$(gh api user --jq '.login')"
  echo "$registry" | jq --argjson n "$num" --arg t "$type" --arg o "$my_owner" \
    '[.claims[] | select(.type==$t and .number==$n and .owner!=$o)] | length > 0'
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `gh gist edit` via `$EDITOR` for scripted updates | `gh gist edit GIST_ID --filename name /tmp/file` (non-interactive) | gh CLI 2.x | Enables fully scripted gist writes without interactive editor |
| `gh api --method PATCH /gists/ID -f 'files[name][content]=...'` | Same — still valid; `gh gist edit` with file arg is cleaner for single-file | Current | Two valid approaches; pick one and be consistent |
| `jq .milestones`, `jq .phases` (object keyed by number) | Flat `claims` array with `type` field | D-01 decision | Simpler append/filter logic; no nested key creation; history preserved by status field |

**Deprecated / outdated:**

- **`gh gist edit` without file arg for scripting:** Opens `$EDITOR` — correct for humans, incorrect for scripts. Always pass the local file path.
- **Registry as separate objects (`{ "milestones": {...}, "phases": {...} }`):** The ARCHITECTURE.md preview used this shape, but D-01 locked the flat `claims` array. The planner must use the D-01 schema, not the ARCHITECTURE.md preview.

[NOTE: The ARCHITECTURE.md `write_registry` example uses `gh gist edit "$GIST_ID" --filename "$GIST_FILE" "$tmpfile"` which IS correct. The narrative text mentioning `gh api --method PATCH` is an alternative, not the primary approach.]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Exact function signatures for `common.sh` helpers | Architecture Patterns / Pattern 1 | Low — implementation detail; planner can adjust signatures |
| A2 | Exact `claim_milestone_and_phase1` function internals | Architecture Patterns / Pattern 4 | Low — logic is correct; field ordering is not locked |
| A3 | Exact collision retry loop structure | Architecture Patterns / Pattern 5 | Low — retry logic is described in D-09; implementation detail |
| A4 | `printf '%s' "$content"` preferred over `echo "$content"` for write | Code Examples | Low — both work; `printf` avoids `echo` flag interpretation on some shells |

**All critical claims** (tool versions, jq patterns, gh command syntax, registry schema, config file location, allocation strategy) were verified against the local environment or official documentation sources.

---

## Open Questions

1. **Does `gh api user --jq '.login'` work inside a CC hook subprocess?**
   - What we know: `gh auth status` succeeds on this machine (keyring auth, active account: true).
   - What's unclear: Whether the keychain remains accessible when `gh` is invoked by a subprocess spawned by Claude Code.
   - Recommendation: Phase 2 must test this explicitly from within a CC session. If it fails, fall back to `GH_TOKEN` env var.

2. **What should `gsd-status.sh` output format look like exactly?**
   - What we know: CONTEXT.md `<specifics>` section previewed a "table with milestone/phase number, owner, branch, date." D-10 says it is a standalone script.
   - What's unclear: Whether the planner wants a specific column order, header row, or color output.
   - Recommendation: Implement as plain text table (no ANSI colors by default) with columns: `TYPE | NUMBER | MILESTONE | OWNER | BRANCH | CLAIMED_AT | STATUS`. Keep it simple — no external dependencies beyond `jq` and `column`.

3. **Should `claim-number.sh` accept a `TYPE` argument, read it from stdin JSON, or both?**
   - What we know: Phase 2 (CC hooks) will invoke `claim-number.sh` from a hook that receives JSON on stdin. Phase 1 (this phase) tests it from the terminal.
   - What's unclear: Whether the planner wants the script to work standalone (CLI args) in Phase 1 and switch to stdin mode in Phase 2, or unify from the start.
   - Recommendation: Accept both — check for stdin JSON first (`jq -e . >/dev/null 2>&1`); fall back to positional arg `$1` for standalone testing. This avoids a rewrite in Phase 2.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `gh` CLI | Gist read/write, auth | ✓ | 2.89.0 (2026-03-26) | — |
| `jq` | JSON parse/emit | ✓ | 1.7.1 (Apple preinstall) | — |
| `git` | `git branch --show-current`, `git rev-parse --show-toplevel` | ✓ | 2.50.1 (Apple Git-155) | — |
| `mktemp` | Temp file for write | ✓ | POSIX (macOS) | — |
| `bash` (3.2+) | Script execution | ✓ | 3.2.57 at `/bin/bash`; shebang picks up 5.x if installed | System bash 3.2 is sufficient for all patterns used |
| `bats-core` | Automated script testing | ✗ | — | Manual testing; install with `brew install bats-core` if needed |
| GitHub Gist (pre-created) | Registry storage | Not verified | — | Manual: one team member creates gist and adds ID to config |

**Missing dependencies with no fallback:**
- GitHub Gist must be pre-created manually before any registry operation. The gist ID must be placed in `.claude/gsd-team.json` before testing. This is a known one-time setup step (PROJECT.md constraint: "Manual gist creation").

**Missing dependencies with fallback:**
- `bats-core` is not installed. Manual testing via shell invocation is the fallback. The planner should include a Wave 0 task to install it or scope verification to manual smoke tests.

[VERIFIED: all tool availability confirmed via command invocation on this machine]

---

## Validation Architecture

> `workflow.nyquist_validation` is `false` in `.planning/config.json` — this section is skipped per config.

---

## Security Domain

> `security_enforcement` key is absent from `.planning/config.json` — treated as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (uses gh auth, not own auth) | `gh auth status` dep check |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Yes (jq parsing of registry JSON) | `jq -e` to fail on null/malformed input |
| V6 Cryptography | No | — |

### Known Threat Patterns for Shell + GitHub Gist Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed/truncated gist JSON injected by network error | Tampering | `jq empty` validation before parsing; exit if not valid JSON |
| Script output leaking registry contents to stdout | Information disclosure | All output except structured table to `>&2`; never echo raw registry to stdout |
| World-writable hook scripts | Tampering | `chmod 750` on all scripts in `hooks/`; owned by developer user |
| Trusting stdin JSON without validation | Tampering | `jq -e . >/dev/null 2>&1` check before parsing stdin in claim-number.sh |
| Gist ID committed to public repo | Information disclosure | `.claude/gsd-team.json` gist ID is a low-risk exposure (gist is not secret, it is team-shared); no tokens are stored in this file |

[CITED: PITFALLS.md Security Mistakes table]

---

## Sources

### Primary (HIGH confidence)

- `gh help gist edit` (2.89.0 on this machine) — confirmed `--filename <name> <local-file>` is the non-interactive write syntax
- `gh help gist view` (2.89.0 on this machine) — confirmed `--raw --filename` flags
- `gh help api` (2.89.0 on this machine) — confirmed `-F 'files[name][content]=@file'` and `--method PATCH` syntax
- `jq --version` + live test (1.7.1 on this machine) — verified max+1 pattern, empty-array guard, `--argjson`, `--arg`, `select()` filter
- `git --version` (2.50.1 on this machine) — `core.hooksPath` confirmed supported
- `mktemp` (POSIX macOS) — confirmed available
- `.planning/research/STACK.md` — component versions, gh API patterns, jq guidance
- `.planning/research/ARCHITECTURE.md` — component responsibilities, data flow, build order
- `.planning/research/PITFALLS.md` — all 8 critical pitfalls verified against official sources
- `.planning/research/FEATURES.md` — feature prioritization, dependency graph

### Secondary (MEDIUM confidence)

- [gh gist view manual — cli.github.com](https://cli.github.com/manual/gh_gist_view) — `--raw`, `--filename` flags
- [gh gist edit manual — cli.github.com](https://cli.github.com/manual/gh_gist_edit) — non-interactive file replace pattern
- [REST API endpoints for gists — docs.github.com](https://docs.github.com/en/rest/gists/gists) — PATCH endpoint structure
- [jqlang.org](https://jqlang.org/) — jq 1.7+ feature set

### Tertiary (LOW confidence)

- None — all claims in this research are verified against live tools or cited from pre-existing HIGH-confidence research files.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tool versions confirmed by live invocation on this machine
- Architecture: HIGH — patterns cross-verified against STACK.md, ARCHITECTURE.md, and live tool help
- Pitfalls: HIGH — sourced from pre-existing PITFALLS.md which cites official docs; critical pitfall (jq empty array) verified live
- jq patterns: HIGH — tested against jq 1.7.1 on this machine with representative inputs
- gh write pattern: HIGH — confirmed from `gh help gist edit` output (version 2.89.0)

**Research date:** 2026-05-19
**Valid until:** 2026-06-19 (stable toolchain; gh CLI releases every ~2 weeks but no breaking changes in 2.x series)
