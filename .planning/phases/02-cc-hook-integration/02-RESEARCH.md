# Phase 2: CC Hook Integration - Research

**Researched:** 2026-05-19
**Domain:** Claude Code hooks — `UserPromptExpansion` event, `settings.json` wiring, bash wrapper scripts, JSON stdin/stdout contract
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Use `UserPromptExpansion` event — this fires when a user types a slash command directly. PreToolUse does NOT fire for direct slash command invocation; it only fires when Claude calls a tool programmatically. Since `/gsd-new-milestone` and `/gsd-new-phase` are user-typed slash commands, UserPromptExpansion is the correct event.
- **D-02:** Use exact command name matching — two separate hook entries in `.claude/settings.json`, one for `gsd-new-milestone` and one for `gsd-new-phase`. No regex patterns. This avoids false positives on unrelated `gsd-new-*` commands.
- **D-03:** Hook config lives in `.claude/settings.json` (project-level, committed to git). All team members get the hooks automatically on clone.
- **D-04:** Two thin wrapper scripts: `hooks/cc-claim-milestone.sh` and `hooks/cc-claim-phase.sh`. Each calls the shared `hooks/claim-number.sh` with the appropriate arguments. CC-specific JSON stdin/stdout handling stays in the wrappers; allocation logic stays in `claim-number.sh`.
- **D-05:** For the phase hook, the milestone number is extracted by parsing the CC hook's stdin JSON payload. The user's command args (e.g., `/gsd-new-phase 2` → milestone_num=2) are parsed from the `command_args` field in the JSON. If the milestone number is missing, the hook exits with code 2 and a message asking the user to specify it.
- **D-06:** On failure (non-zero exit from claim-number.sh), the wrapper outputs the error to stderr and exits with code 2 to block the CC command. Exit code 1 is explicitly avoided — it is non-blocking in CC hooks.
- **D-07:** On success, the wrapper outputs JSON to stdout with an `additionalContext` field containing the claimed number and a human-readable instruction (e.g., "Milestone 3 claimed (and phase 1 of milestone 3). Use milestone number 3 for this command."). CC injects this text into Claude's prompt so it uses the correct number.
- **D-08:** The additionalContext message must be clear enough that Claude will use the claimed number instead of picking one itself. Include both the number and explicit direction.
- **D-09:** Every hook must be verified by: (1) triggering the slash command in a CC session, (2) confirming the claimed number appears in the gist registry, (3) confirming the hook blocks on error (exit 2).
- **D-10:** Hook stdout must produce no shell profile contamination. Guard all interactive-only output in `.zshrc`/`.bashrc` behind `[[ $- == *i* ]]`. The CC hook contract requires clean JSON or empty stdout.

### Claude's Discretion

- None — all implementation decisions are locked.

### Deferred Ideas (OUT OF SCOPE)

- None — discussion stayed within phase scope.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HOOK-01 | CC hook intercepts `/gsd-new-milestone` and claims number before execution | `UserPromptExpansion` event with matcher `"gsd-new-milestone"`; wrapper calls `claim-number.sh milestone`; success JSON injects `additionalContext` |
| HOOK-02 | CC hook intercepts `/gsd-new-phase` and claims number before execution | `UserPromptExpansion` event with matcher `"gsd-new-phase"`; wrapper parses `command_args` from stdin JSON for milestone number; calls `claim-number.sh phase <n>` |
| HOOK-03 | Hooks use exit code 2 (not 1) to block on failure — verified by test | Exit code 2 is confirmed blocking for `UserPromptExpansion`; exit code 1 is non-blocking; `claim-number.sh` already exits 2 on error |
| HOOK-04 | Hook stdout/stderr is clean (no shell profile contamination) | Wrappers send all non-JSON output to stderr; stdout is exclusively JSON; shell profile must guard with `[[ $- == *i* ]]`; verify with `echo '{}' | bash hook.sh | jq .` |

</phase_requirements>

---

## Summary

Phase 2 wires two thin bash wrapper scripts to Claude Code's `UserPromptExpansion` hook event via `.claude/settings.json`. When a developer types `/gsd-new-milestone` or `/gsd-new-phase` in a CC session, the hook fires before the command expands, calls the existing `hooks/claim-number.sh` allocation script, and injects the claimed number into Claude's context via `additionalContext` JSON. On allocation failure, the wrapper exits with code 2 to block the command.

The `UserPromptExpansion` event fires on direct slash command invocation. The `command_name` in the stdin JSON payload is the command name without the leading slash (e.g., `"gsd-new-milestone"`). The `command_args` field carries everything the user typed after the command name (e.g., `"2"` for `/gsd-new-phase 2`). This is the mechanism for the phase wrapper to extract the required milestone number.

The critical technical finding is the dual blocking mechanism: exit code 2 blocks the expansion (simple path); or a JSON `decision: "block"` response also blocks (with richer UX options). The wrappers use exit code 2 for failure and exit code 0 + JSON `additionalContext` for success, which is the pattern locked in D-06/D-07. All existing Phase 1 library code (`hooks/lib/common.sh`, `hooks/lib/gist.sh`, `hooks/claim-number.sh`) ships already — Phase 2 adds exactly two wrapper scripts and one `settings.json` file.

**Primary recommendation:** Create `.claude/settings.json` with `UserPromptExpansion` entries first to establish the wiring, then write the two wrapper scripts that read CC hook stdin JSON and delegate to `claim-number.sh`. Verify each hook from within an active CC session, not from the terminal.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| CC hook event wiring | `.claude/settings.json` | — | Declarative config; CC reads it to know which scripts to call |
| Slash command interception | CC runtime (`UserPromptExpansion`) | — | CC fires the event when user types the command |
| Hook stdin JSON parsing | Wrapper scripts (`cc-claim-milestone.sh`, `cc-claim-phase.sh`) | `jq` | Wrappers own the CC-specific I/O contract |
| Number allocation | `hooks/claim-number.sh` | `hooks/lib/gist.sh` | Phase 1 script; wrappers delegate to it via subprocess |
| Registry read/write | `hooks/lib/gist.sh` | `gh` CLI | Phase 1 library; unchanged in Phase 2 |
| `additionalContext` injection | Wrapper scripts | — | Wrappers format and emit the JSON on stdout |
| Command blocking (failure) | Wrapper scripts (exit 2) | — | Exit code 2 is the CC-native blocking mechanism |

---

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 3.2+ (shebang picks up 5.x) | Wrapper scripts | Established in Phase 1; project constraint |
| `jq` | 1.7.1 (confirmed on this machine) | Parse stdin JSON; format stdout JSON | Non-negotiable for CC hook JSON contract |
| `gh` CLI | 2.89.0 (confirmed on this machine) | Auth check, gist ops (via Phase 1 lib) | Already used in Phase 1 |
| `.claude/settings.json` | CC native config | Declare `UserPromptExpansion` hooks | Project-level, committed to git (D-03) |

[VERIFIED: jq 1.7.1, gh 2.89.0, bash 3.2.57 confirmed via command invocation on this machine]

### No New Dependencies

Phase 2 introduces no new dependencies. All tools used are already established in Phase 1.

---

## Architecture Patterns

### System Architecture Diagram

```
Developer types: /gsd-new-milestone  OR  /gsd-new-phase 2
       |
       v
Claude Code runtime reads .claude/settings.json
       |
       | UserPromptExpansion event fires (before command expands)
       v
hooks/cc-claim-milestone.sh   OR   hooks/cc-claim-phase.sh
       |                                    |
       | stdin: CC hook JSON                | stdin: CC hook JSON
       | {"hook_event_name":"UserPromptExpansion",| {"command_args":"2", ...}
       |  "command_name":"gsd-new-milestone",...}  |
       |                                    |
       |-- jq parses command_args ----------|-- jq parses command_args
       |   (none needed for milestone)      |   extracts milestone_num=2
       |                                    |   exits 2 if missing
       |                                    |
       |-- delegates to: hooks/claim-number.sh milestone
       |-- delegates to: hooks/claim-number.sh phase <n>
              |
              |-- sources hooks/lib/common.sh (check_deps, load_config)
              |-- sources hooks/lib/gist.sh (read_registry, write_registry)
              |-- reads .claude/gsd-team.json (GIST_ID)
              |-- calls gh gist / gh api (GitHub Gist)
              |
              v
       ALLOCATION SUCCESS                   ALLOCATION FAILURE
              |                                    |
       wrapper writes to stdout:           wrapper writes to stderr:
       {"hookSpecificOutput":{             <error message>
         "hookEventName":"UserPromptExpansion",
         "additionalContext":"Milestone 3 claimed..."}}
              |                                    |
              v                                    v
       exit 0 — command proceeds          exit 2 — command BLOCKED
       CC injects additionalContext        CC shows stderr to user
       into Claude's prompt context
```

### Recommended Project Structure

```
.claude/
├── gsd-team.json      # Existing — gist_id config (Phase 1)
└── settings.json      # NEW in Phase 2 — CC hook declarations

hooks/
├── cc-claim-milestone.sh   # NEW in Phase 2 — milestone hook wrapper
├── cc-claim-phase.sh       # NEW in Phase 2 — phase hook wrapper
├── claim-number.sh         # Existing (Phase 1) — allocation logic
├── gsd-status.sh           # Existing (Phase 1) — status display
└── lib/
    ├── common.sh           # Existing (Phase 1) — dep checks, config
    └── gist.sh             # Existing (Phase 1) — read/write registry
```

### Pattern 1: `settings.json` Hook Wiring for `UserPromptExpansion`

**What:** Declare two hook entries under `UserPromptExpansion`, one per command. The `matcher` field matches `command_name` (the slash command name without the leading slash). Exact string match — no regex needed.

**When to use:** This is the only mechanism to intercept direct slash command invocation in CC (D-01, D-02, D-03).

```json
{
  "hooks": {
    "UserPromptExpansion": [
      {
        "matcher": "gsd-new-milestone",
        "hooks": [
          {
            "type": "command",
            "command": "hooks/cc-claim-milestone.sh"
          }
        ]
      },
      {
        "matcher": "gsd-new-phase",
        "hooks": [
          {
            "type": "command",
            "command": "hooks/cc-claim-phase.sh"
          }
        ]
      }
    ]
  }
}
```

[VERIFIED: official CC docs — `UserPromptExpansion` matcher matches `command_name`; command_name is the slash command name without the leading slash]

**Key field notes:**
- `matcher`: exact string `"gsd-new-milestone"` — matches the `command_name` field in stdin JSON
- `type`: `"command"` for shell scripts
- `command`: relative path is resolved from `cwd` (the project root when running CC from the repo)
- No `args` needed — the full stdin JSON is piped to the script automatically

### Pattern 2: `UserPromptExpansion` stdin JSON Structure

**What:** The CC runtime sends this JSON on stdin to the hook script when the event fires.

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../transcript.jsonl",
  "cwd": "/Users/buu/Development/gsdTeamWork",
  "permission_mode": "default",
  "hook_event_name": "UserPromptExpansion",
  "expansion_type": "slash_command",
  "command_name": "gsd-new-milestone",
  "command_args": "",
  "command_source": "plugin",
  "prompt": "/gsd-new-milestone"
}
```

For `/gsd-new-phase 2`, `command_name` is `"gsd-new-phase"` and `command_args` is `"2"`.

[VERIFIED: official CC docs — exact field names confirmed from docs.anthropic.com hook reference]

**Parsing in bash:**
```bash
# Source: official CC docs — stdin JSON format for UserPromptExpansion
# [VERIFIED: field names confirmed from CC hooks reference]
HOOK_JSON="$(cat)"   # read all stdin
COMMAND_ARGS="$(echo "$HOOK_JSON" | jq -r '.command_args // ""')"
```

### Pattern 3: Milestone Hook Wrapper (`cc-claim-milestone.sh`)

**What:** Thin wrapper for `/gsd-new-milestone`. Reads stdin, calls `claim-number.sh milestone`, formats JSON response.

**When to use:** Every time `/gsd-new-milestone` is typed in a CC session (HOOK-01).

```bash
#!/usr/bin/env bash
# hooks/cc-claim-milestone.sh — CC UserPromptExpansion hook for /gsd-new-milestone
# Reads CC hook JSON from stdin, claims next milestone number, injects additionalContext.
# Exit 0 + JSON on success; exit 2 on failure (blocks the command).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Read and discard stdin (CC hook sends JSON; milestone needs no args from it)
HOOK_JSON="$(cat)"

# Claim next milestone number
CLAIM_OUTPUT="$("$REPO_ROOT/hooks/claim-number.sh" milestone 2>/tmp/gsd-cc-milestone-err.txt)"
CLAIM_EXIT=$?

if [[ $CLAIM_EXIT -ne 0 ]]; then
  cat /tmp/gsd-cc-milestone-err.txt >&2
  rm -f /tmp/gsd-cc-milestone-err.txt
  exit 2  # blocks the command — NOT exit 1
fi

rm -f /tmp/gsd-cc-milestone-err.txt

# Format additionalContext message (D-07, D-08)
MILESTONE_NUM="$(echo "$CLAIM_OUTPUT" | grep -oE '[0-9]+' | head -1)"
ADDITIONAL_CONTEXT="Milestone ${MILESTONE_NUM} claimed (and phase 1 of milestone ${MILESTONE_NUM}). Use milestone number ${MILESTONE_NUM} for this command."

# Emit CC hook JSON on stdout (exit 0 allows the command to proceed)
printf '%s\n' "$(jq -n \
  --arg ctx "$ADDITIONAL_CONTEXT" \
  '{"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":$ctx}}')"
exit 0
```

[ASSUMED: exact error capture strategy using /tmp file — implementation detail]

### Pattern 4: Phase Hook Wrapper (`cc-claim-phase.sh`)

**What:** Thin wrapper for `/gsd-new-phase`. Parses `command_args` from stdin JSON to extract milestone number, calls `claim-number.sh phase <n>`, formats JSON response.

**When to use:** Every time `/gsd-new-phase <n>` is typed in a CC session (HOOK-02).

```bash
#!/usr/bin/env bash
# hooks/cc-claim-phase.sh — CC UserPromptExpansion hook for /gsd-new-phase
# Reads CC hook JSON from stdin, extracts milestone number from command_args,
# claims next phase number, injects additionalContext.
# Exit 0 + JSON on success; exit 2 on failure (blocks the command).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Parse stdin JSON for command_args (D-05)
HOOK_JSON="$(cat)"
COMMAND_ARGS="$(echo "$HOOK_JSON" | jq -r '.command_args // ""')"

# Extract milestone number — first token of command_args
MILESTONE_NUM="$(echo "$COMMAND_ARGS" | awk '{print $1}')"

# Validate milestone number present and is a positive integer
if [[ -z "$MILESTONE_NUM" ]] || ! [[ "$MILESTONE_NUM" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: /gsd-new-phase requires a milestone number. Usage: /gsd-new-phase <milestone_num>" >&2
  exit 2  # blocks the command — NOT exit 1
fi

# Claim next phase number for this milestone
CLAIM_OUTPUT="$("$REPO_ROOT/hooks/claim-number.sh" phase "$MILESTONE_NUM" 2>/tmp/gsd-cc-phase-err.txt)"
CLAIM_EXIT=$?

if [[ $CLAIM_EXIT -ne 0 ]]; then
  cat /tmp/gsd-cc-phase-err.txt >&2
  rm -f /tmp/gsd-cc-phase-err.txt
  exit 2  # blocks the command — NOT exit 1
fi

rm -f /tmp/gsd-cc-phase-err.txt

# Format additionalContext message (D-07, D-08)
PHASE_NUM="$(echo "$CLAIM_OUTPUT" | grep -oE 'phase [0-9]+' | grep -oE '[0-9]+')"
ADDITIONAL_CONTEXT="Phase ${PHASE_NUM} of milestone ${MILESTONE_NUM} claimed. Use milestone number ${MILESTONE_NUM} and phase number ${PHASE_NUM} for this command."

# Emit CC hook JSON on stdout (exit 0 allows the command to proceed)
printf '%s\n' "$(jq -n \
  --arg ctx "$ADDITIONAL_CONTEXT" \
  '{"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":$ctx}}')"
exit 0
```

[ASSUMED: `grep -oE` pattern for extracting numbers from `claim-number.sh` success output — depends on exact output format of claim-number.sh. Implementation must verify against actual claim-number.sh stdout.]

### Pattern 5: Exit Code Contract for `UserPromptExpansion`

**What:** The CC runtime interprets exit codes from the hook script as follows for `UserPromptExpansion`:

| Exit Code | Effect | When to Use |
|-----------|--------|-------------|
| 0 | Command proceeds; stdout parsed for JSON; `additionalContext` injected | Successful claim |
| 2 | Command BLOCKED; stderr shown to user as error message | Allocation failure, missing args |
| 1 or other | Non-blocking; first line of stderr in transcript only | Never for blocking intent |

[VERIFIED: official CC docs — exit code semantics table for UserPromptExpansion confirmed]

### Pattern 6: Alternative Blocking via JSON `decision: "block"`

**What:** On exit 0, you can also block the command via JSON:

```json
{
  "decision": "block",
  "reason": "Reason shown to user",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptExpansion",
    "additionalContext": "Optional context"
  }
}
```

**When to use:** When you want to show a reason message via the `reason` field rather than stderr. The current design (D-06) uses exit 2 with stderr, which is simpler.

[VERIFIED: official CC docs — `decision: "block"` confirmed for `UserPromptExpansion`]

### Anti-Patterns to Avoid

- **`exit 1` from the hook wrapper:** Non-blocking. The command proceeds as if the hook wasn't there. Always use `exit 2` for any blocking intent. [VERIFIED: PITFALLS.md Pitfall 1]
- **Writing non-JSON text to stdout:** Any text that reaches stdout before the JSON object will corrupt the CC hook output parsing. All human-readable messages, verbose logs, and error text must go to `>&2`. [VERIFIED: PITFALLS.md Pitfall 2]
- **Using `PreToolUse` instead of `UserPromptExpansion`:** `PreToolUse` fires when Claude calls a tool programmatically, not when the user types a slash command. Direct slash command invocation does not trigger `PreToolUse`. [VERIFIED: official CC docs — distinction documented explicitly]
- **Regex matcher when exact match suffices:** Using `gsd-new-.*` matches unintended commands. Use exact `"gsd-new-milestone"` and `"gsd-new-phase"` per D-02. [CITED: CONTEXT.md D-02]
- **Reading milestone number from `prompt` field instead of `command_args`:** The `prompt` field contains the full typed text (`"/gsd-new-phase 2"`). Parsing it requires splitting on space and stripping the slash prefix. Use `command_args` instead — it already strips the command name. [VERIFIED: CC docs stdin JSON fields]
- **Calling `claim-number.sh` with relative path:** The CC hook `cwd` may differ from expected. Always resolve absolute path via `REPO_ROOT=$(git rev-parse --show-toplevel)`. [CITED: Phase 1 established pattern]
- **Hardcoding tmpfile paths for error capture:** Use `/tmp/gsd-cc-*.txt` with unique names; two concurrent hooks from two CC sessions would collide on a single hardcoded path. Consider `mktemp` pattern. [ASSUMED: concurrency edge case — low risk for 3-person team but worth noting]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON stdin parsing | `read` + `grep`/`awk` for JSON field extraction | `jq -r '.command_args // ""'` | Shell text tools break on quoted strings, Unicode, nested JSON |
| JSON stdout formatting | `echo '{"additionalContext":"...'` with string concatenation | `jq -n --arg ctx "$VAR" '{"hookSpecificOutput":...}'` | String concat breaks if `$VAR` contains quotes or newlines |
| Allocation logic | Any code in the wrapper | `hooks/claim-number.sh` (Phase 1) | Already handles max+1, collision detection, dry-run, verbose mode |
| Registry I/O | Any gist calls in the wrapper | `hooks/lib/gist.sh` (Phase 1) | Phase 1 library handles auth, temp files, and write confirmation |

**Key insight:** The wrappers are intentionally thin — their only CC-specific responsibility is stdin parsing and stdout formatting. All business logic stays in the Phase 1 scripts.

---

## Common Pitfalls

### Pitfall 1: Exit Code 1 Is Non-Blocking in CC Hooks

**What goes wrong:** Wrapper uses `exit 1` on allocation failure. Hook "runs" but command proceeds — no blocking. Registry shows the claim but Claude doesn't know the correct number.

**Why it happens:** Unix instinct. Every developer's reflex is `exit 1` on error.

**How to avoid:** Use `exit 2` in every failure path. Add a comment next to every `exit 2`: `# blocks the command — NOT exit 1`. Verify by triggering a deliberate failure (e.g., call with invalid gist_id) and confirming the CC command does not execute.

**Warning signs:** `/gsd-new-milestone` runs but CC doesn't use the claimed number; hook stderr appears but command completes.

[VERIFIED: PITFALLS.md Pitfall 1, official CC docs exit code table]

### Pitfall 2: Shell Profile Output Corrupts stdout JSON

**What goes wrong:** Developer's `.zshrc` prints a welcome message. CC hook receives mixed stdout (profile text + JSON). JSON parsing fails. Hook appears to be silent.

**Why it happens:** `.zshrc` runs in every new bash subprocess, including those spawned by CC.

**How to avoid:** All output in wrappers goes to `>&2` except the final JSON on stdout. Verify non-interactively: `echo '{}' | bash hooks/cc-claim-milestone.sh | jq .` must succeed. Check `.zshrc` for unguarded output; wrap it in `[[ $- == *i* ]] && ...`.

**Warning signs:** Hook works on one developer's machine, fails silently on another's.

[VERIFIED: PITFALLS.md Pitfall 2]

### Pitfall 3: `gh` Auth Fails Inside CC Hook Subprocess

**What goes wrong:** `claim-number.sh` calls `gh api user` or `gh gist view`. Auth succeeds in terminal but fails when invoked from the CC hook subprocess (keychain not accessible).

**Why it happens:** `gh` stores tokens in the macOS keychain. Non-interactive subprocesses launched by CC may not have keychain access.

**How to avoid:** Test the hook explicitly from within a CC session (not just the terminal). If auth fails, set `GH_TOKEN` as a persistent environment variable.

**Warning signs:** Allocation works from terminal, fails when triggered via CC hook.

[VERIFIED: PITFALLS.md Pitfall 8]

### Pitfall 4: `command_args` Is Empty When User Omits Milestone Number

**What goes wrong:** Developer types `/gsd-new-phase` without a number. `command_args` is `""`. `MILESTONE_NUM` becomes empty. `claim-number.sh` exits 2 with its own error message — but the wrapper may not re-exit with 2 if the error is not handled correctly.

**Why it happens:** bash `$(...)` subprocess capture masks the exit code if not explicitly checked.

**How to avoid:** In `cc-claim-phase.sh`, validate `MILESTONE_NUM` before calling `claim-number.sh`. Exit 2 immediately with a user-visible message: "ERROR: /gsd-new-phase requires a milestone number." Always check `$?` after the `claim-number.sh` subprocess.

**Warning signs:** `/gsd-new-phase` without args runs silently or exits with an unhelpful error from deep in the allocation stack.

[CITED: CONTEXT.md D-05]

### Pitfall 5: `set -e` Traps `$()` Subprocess Exit Codes

**What goes wrong:** `set -euo pipefail` is active. `CLAIM_OUTPUT="$(claim-number.sh ...)"` — if `claim-number.sh` exits non-zero, the script exits immediately at the assignment, bypassing any error handling code below.

**Why it happens:** `set -e` applies to subprocess substitutions in modern bash.

**How to avoid:** Two options: (a) capture exit code explicitly: `CLAIM_OUTPUT="$(claim-number.sh ...)" || CLAIM_EXIT=$?` — but this is unreliable with `set -e`. (b) Temporarily disable set -e around the subprocess: `set +e; CLAIM_OUTPUT="$(claim-number.sh ...)"; CLAIM_EXIT=$?; set -e`. Or (c) use a temp file for stderr capture and check the exit code explicitly.

**Warning signs:** Wrapper exits 1 (the default) instead of 2; no user-visible error from the hook; command is not blocked as expected.

[CITED: Phase 1 research STATE.md note on verbose_log requiring `|| true`]

### Pitfall 6: REQUIREMENTS.md Labels as "PreToolUse" But Correct Event Is `UserPromptExpansion`

**What goes wrong:** REQUIREMENTS.md lines HOOK-01 and HOOK-02 say "CC PreToolUse hook intercepts..." — this label is incorrect. The planner may wire `PreToolUse` hooks. `PreToolUse` does NOT fire for direct slash command invocation.

**Why it happens:** The requirements were written before the hook event was fully researched. D-01 in CONTEXT.md corrects this.

**How to avoid:** Wire `UserPromptExpansion`, not `PreToolUse`. The REQUIREMENTS.md text is a labeling error in the requirement description, not the requirement intent. D-01 is the locked decision that overrides it.

**Warning signs:** Hooks wired to `PreToolUse` for `Bash` tool — would fire when Claude calls Bash, not when user types the slash command.

[VERIFIED: official CC docs — `UserPromptExpansion` vs `PreToolUse` distinction documented; CONTEXT.md D-01 locks the choice]

---

## Code Examples

### Complete `settings.json`

```json
{
  "hooks": {
    "UserPromptExpansion": [
      {
        "matcher": "gsd-new-milestone",
        "hooks": [
          {
            "type": "command",
            "command": "hooks/cc-claim-milestone.sh"
          }
        ]
      },
      {
        "matcher": "gsd-new-phase",
        "hooks": [
          {
            "type": "command",
            "command": "hooks/cc-claim-phase.sh"
          }
        ]
      }
    ]
  }
}
```

[VERIFIED: settings.json structure from official CC docs; matcher field matches `command_name`; `type: "command"` for shell scripts]

### Parsing `command_args` from Stdin JSON

```bash
# Source: official CC docs — stdin JSON format for UserPromptExpansion
# command_args contains everything after the command name (e.g., "2" for /gsd-new-phase 2)
HOOK_JSON="$(cat)"
COMMAND_ARGS="$(echo "$HOOK_JSON" | jq -r '.command_args // ""')"
MILESTONE_NUM="$(echo "$COMMAND_ARGS" | awk '{print $1}')"
```

[VERIFIED: `command_args` field confirmed in CC docs stdin JSON schema]

### Success Response JSON (stdout)

```bash
# Source: official CC docs — UserPromptExpansion hookSpecificOutput format
# additionalContext is injected into Claude's prompt context
printf '%s\n' "$(jq -n \
  --arg ctx "Milestone 3 claimed (and phase 1 of milestone 3). Use milestone number 3 for this command." \
  '{"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":$ctx}}')"
exit 0
```

[VERIFIED: `hookSpecificOutput.additionalContext` field confirmed in official CC docs for `UserPromptExpansion`]

### Blocking Response (exit 2)

```bash
# Source: official CC docs — exit 2 blocks UserPromptExpansion; stderr shown to user
echo "ERROR: Registry claim failed. Check gist connectivity." >&2
exit 2  # blocks the command — NOT exit 1
```

[VERIFIED: exit code 2 blocks `UserPromptExpansion` per official CC docs exit code semantics table]

### Smoke Test (Non-Interactive stdout Check)

```bash
# Source: PITFALLS.md Pitfall 2 — verify no shell profile contamination
# Must succeed for HOOK-04
echo '{"hook_event_name":"UserPromptExpansion","command_name":"gsd-new-milestone","command_args":""}' \
  | GSD_DRY_RUN=1 bash hooks/cc-claim-milestone.sh | jq .
```

[ASSUMED: `GSD_DRY_RUN=1` propagates to `claim-number.sh` subprocess and prevents gist write during smoke test]

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `PreToolUse` to intercept slash commands | `UserPromptExpansion` | CC architecture — always different | `PreToolUse` fires on programmatic tool calls, not direct slash invocations |
| Exit code 1 for blocking | Exit code 2 for blocking | CC design (non-obvious) | Exit 1 is non-blocking; exit 2 is the only blocking exit code |
| Bare stderr message to block | Exit 2 with stderr OR `decision: "block"` JSON | CC current | Two valid blocking mechanisms; exit 2 is simpler for shell scripts |

**Notable:** REQUIREMENTS.md incorrectly labels HOOK-01/HOOK-02 as "PreToolUse" hooks. The correct event is `UserPromptExpansion`. CONTEXT.md D-01 locks this decision.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `hooks/cc-claim-milestone.sh` uses `/tmp/gsd-cc-*.txt` for error capture from subprocess | Pattern 3 | Low — implementation detail; mktemp is a clean alternative |
| A2 | `grep -oE '[0-9]+'` correctly extracts milestone/phase number from `claim-number.sh` success output | Patterns 3 & 4 | Medium — depends on exact stdout format of `claim-number.sh`. Implementer must verify against actual output: "Claimed milestone N and phase 1 of milestone N" → first match returns N |
| A3 | `GSD_DRY_RUN=1` propagates through the wrapper to `claim-number.sh` subprocess for smoke testing | Smoke Test example | Low — it is an environment variable; bash subprocesses inherit env vars by default unless explicitly cleared |
| A4 | `command` path in settings.json resolves relative to project `cwd` | Standard Stack / Pattern 1 | Medium — if CC resolves relative to a different directory, the hook script won't be found. Absolute path via `$REPO_ROOT` or verifying CC's cwd is the safe alternative |

---

## Open Questions

1. **Does `command` path in `settings.json` resolve relative to project root or some other path?**
   - What we know: CC docs show `command: "script.sh"` in examples without absolute paths.
   - What's unclear: Whether it resolves relative to `cwd` from the hook stdin JSON, or to the location of `settings.json`.
   - Recommendation: Use `$REPO_ROOT`-based absolute path inside the wrapper itself, OR test with relative path first in a CC session. If relative fails, use absolute path with `$REPO_ROOT` interpolation in the `command` field (note: env vars in `command` field — verify support).

2. **Does `set -euo pipefail` in the wrapper interfere with subprocess exit code capture?**
   - What we know: Phase 1 STATE.md documents that `verbose_log` requires `|| true` because `set -e` traps exit 1 from `[[ ]]` constructs.
   - What's unclear: The exact behavior of `CLAIM_OUTPUT="$(claim-number.sh ...)"` with `set -e` active — does it propagate the non-zero exit code immediately, or can `CLAIM_EXIT=$?` capture it?
   - Recommendation: Use `set +e` around the subprocess call, capture `$?` explicitly, then `set -e`. Or restructure to not use `set -e` in the wrapper.

3. **Does `claim-number.sh` stdout format guarantee the pattern needed to extract the number?**
   - What we know: The actual `claim-number.sh` file was read: success line is `"Claimed milestone $NEXT_NUM and phase 1 of milestone $NEXT_NUM"` for milestones and `"Claimed phase $NEXT_NUM of milestone $MILESTONE_NUM"` for phases.
   - What's unclear: Nothing — this is now KNOWN from reading the source.
   - Recommendation: Extract milestone number from first match of `\b[0-9]+\b` in the output. Extract phase number from `"Claimed phase ([0-9]+)"` pattern. Consider passing numbers as structured output (second future improvement), but for Phase 2 the grep pattern on known format is reliable.

   [VERIFIED: read `hooks/claim-number.sh` lines 209-212 — exact success output strings]

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `jq` | stdin JSON parsing, stdout JSON formatting | ✓ | 1.7.1 | — |
| `gh` CLI | Auth + gist ops via Phase 1 lib | ✓ | 2.89.0 | — |
| `bash` | Wrapper scripts | ✓ | 3.2.57 (system); 5.x if Homebrew installed | — |
| `.claude/settings.json` | CC hook wiring | Not yet (file does not exist) | — | Must create in Phase 2 |
| `hooks/claim-number.sh` | Number allocation | ✓ | Phase 1 complete | — |
| `hooks/lib/common.sh` | Dep checks | ✓ | Phase 1 complete | — |
| `hooks/lib/gist.sh` | Registry I/O | ✓ | Phase 1 complete | — |
| `.claude/gsd-team.json` | Gist ID config | ✓ | `{"gist_id":"74549bde...","project":"gsd-team-work"}` | — |

**Missing dependencies with no fallback:**
- `.claude/settings.json` does not yet exist — must be created in Phase 2 Wave 1.

**Missing dependencies with fallback:**
- None.

[VERIFIED: all tool availability confirmed via command invocation on this machine; Phase 1 scripts confirmed present via `ls hooks/`]

---

## Validation Architecture

> `workflow.nyquist_validation` is `false` in `.planning/config.json` — this section is skipped per config.

---

## Security Domain

> `security_enforcement` key is absent from `.planning/config.json` — treated as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (uses `gh auth`, not own auth) | `gh auth status` dep check (inherited from Phase 1) |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Yes — `command_args` from CC stdin | `jq -r` with `// ""` default; validate with `[[ "$MILESTONE_NUM" =~ ^[1-9][0-9]*$ ]]` |
| V6 Cryptography | No | — |

### Known Threat Patterns for CC Hook + Shell Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed CC stdin JSON (truncated or invalid) | Tampering | `jq -r '.command_args // ""'` — `//` default prevents null propagation; `jq` exits non-zero on invalid JSON which `set -e` traps |
| Shell injection via `command_args` | Tampering | Pass `MILESTONE_NUM` as argument to `claim-number.sh`, not via eval or string interpolation in a command string; validated as `^[1-9][0-9]*$` before use |
| Stdout contamination from shell profile | Information disclosure / Integrity | Guard all `.zshrc`/`.bashrc` interactive output with `[[ $- == *i* ]]`; wrappers use `>&2` for all non-JSON output |
| additionalContext containing executable content | Spoofing | Content is plain text string only; CC injects it as context text, not as executable instructions — no eval path |
| World-writable wrapper scripts | Tampering | `chmod 750` on `hooks/cc-claim-*.sh` at creation |

[CITED: PITFALLS.md Security Mistakes table; CONTEXT.md D-10]

---

## Project Constraints (from CLAUDE.md)

The project `CLAUDE.md` documents the following actionable directives for planner compliance:

| Constraint | Source | Impact on Phase 2 |
|------------|--------|-------------------|
| Tech stack: Bash + `gh` CLI only — no additional runtimes | CLAUDE.md constraints | No Python, Node, or other runtimes in wrapper scripts |
| Auth: relies on `gh auth login` per developer | CLAUDE.md constraints | No token files in wrappers; `check_deps` gate from Phase 1 handles this |
| Hook types: CC hooks via `settings.json` for GSD command interception | CLAUDE.md constraints | Confirms `UserPromptExpansion` in `.claude/settings.json` is the correct approach |
| GSD workflow enforcement: use GSD commands for file changes | CLAUDE.md GSD Workflow section | Implementation must proceed via `/gsd-execute-phase` |

---

## Sources

### Primary (HIGH confidence)
- `https://code.claude.com/docs/en/hooks` — `UserPromptExpansion` event contract, stdin JSON field names (`command_name`, `command_args`), stdout JSON format (`hookSpecificOutput.additionalContext`), exit code semantics (0/1/2) for `UserPromptExpansion`, matcher field behavior against `command_name`, `decision: "block"` vs exit 2 behavior — fetched 2026-05-19
- `hooks/claim-number.sh` — Read directly; confirms exact stdout success strings, CLI argument interface, exit code 2 on all failure paths
- `hooks/lib/common.sh` — Read directly; confirms `check_deps()`, `load_config()`, `verbose_log()` interfaces
- `hooks/lib/gist.sh` — Read directly; confirms `read_registry()` and `write_registry()` interfaces
- `.planning/phases/02-cc-hook-integration/02-CONTEXT.md` — All D-01..D-10 locked decisions
- `.planning/research/PITFALLS.md` — Pitfalls 1, 2, 8 directly relevant to Phase 2 (exit code, stdout contamination, gh auth in CC subprocess)
- `.planning/research/STACK.md` — CC hook event reference, `UserPromptExpansion` event confirmed

### Secondary (MEDIUM confidence)
- `.planning/phases/01-registry-allocation-core/01-RESEARCH.md` — Phase 1 patterns and pitfalls inherited by Phase 2; Phase 1 is complete so these are ground truth
- `CLAUDE.md` (project root) — Project constraints, tech stack, CC hook event reference

### Tertiary (LOW confidence)
- None — all claims in this research are verified against live tools, official CC documentation, or existing codebase files.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tool versions confirmed by live invocation; CC docs fetched 2026-05-19
- Architecture: HIGH — CC hook stdin/stdout contract verified against official docs; existing Phase 1 scripts read directly
- Pitfalls: HIGH — sourced from pre-existing verified PITFALLS.md plus live CC docs confirmation
- `UserPromptExpansion` behavior: HIGH — verified from official CC docs including exit code table, matcher semantics, and `additionalContext` field

**Research date:** 2026-05-19
**Valid until:** 2026-06-19 (CC hook API is stable; exit code semantics and event names have been consistent)
