# Phase 2: CC Hook Integration - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire Claude Code hooks that automatically intercept `/gsd-new-milestone` and `/gsd-new-phase` slash commands and claim the next available number from the shared gist registry before the GSD command executes. On failure, the hook blocks the command (exit 2). On success, the claimed number is injected into Claude's context via `additionalContext` JSON.

</domain>

<decisions>
## Implementation Decisions

### Hook Event Type
- **D-01:** Use `UserPromptExpansion` event — this fires when a user types a slash command directly. PreToolUse does NOT fire for direct slash command invocation; it only fires when Claude calls a tool programmatically. Since `/gsd-new-milestone` and `/gsd-new-phase` are user-typed slash commands, UserPromptExpansion is the correct event.

### Command Matching
- **D-02:** Use exact command name matching — two separate hook entries in `.claude/settings.json`, one for `gsd-new-milestone` and one for `gsd-new-phase`. No regex patterns. This avoids false positives on unrelated `gsd-new-*` commands.
- **D-03:** Hook config lives in `.claude/settings.json` (project-level, committed to git). All team members get the hooks automatically on clone.

### Hook-to-Script Bridge
- **D-04:** Two thin wrapper scripts: `hooks/cc-claim-milestone.sh` and `hooks/cc-claim-phase.sh`. Each calls the shared `hooks/claim-number.sh` with the appropriate arguments. CC-specific JSON stdin/stdout handling stays in the wrappers; allocation logic stays in `claim-number.sh`.
- **D-05:** For the phase hook, the milestone number is extracted by parsing the CC hook's stdin JSON payload. The user's command args (e.g., `/gsd-new-phase 2` → milestone_num=2) are parsed from the prompt text in the JSON. If the milestone number is missing, the hook exits with code 2 and a message asking the user to specify it.
- **D-06:** On failure (non-zero exit from claim-number.sh), the wrapper outputs the error to stderr and exits with code 2 to block the CC command. Exit code 1 is explicitly avoided — it is non-blocking in CC hooks.

### additionalContext Injection
- **D-07:** On success, the wrapper outputs JSON to stdout with an `additionalContext` field containing the claimed number and a human-readable instruction (e.g., "Milestone 3 claimed (and phase 1 of milestone 3). Use milestone number 3 for this command."). CC injects this text into Claude's prompt so it uses the correct number.
- **D-08:** The additionalContext message must be clear enough that Claude will use the claimed number instead of picking one itself. Include both the number and explicit direction.

### Verification Requirements
- **D-09:** Every hook must be verified by: (1) triggering the slash command in a CC session, (2) confirming the claimed number appears in the gist registry, (3) confirming the hook blocks on error (exit 2). Research flagged that exit 1 creates "security theater" — the hook appears active but doesn't block.
- **D-10:** Hook stdout must produce no shell profile contamination. Guard all interactive-only output in `.zshrc`/`.bashrc` behind `[[ $- == *i* ]]`. The CC hook contract requires clean JSON or empty stdout.

### Claude's Discretion
- None — all implementation decisions are locked.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 Artifacts (dependency)
- `.planning/phases/01-registry-allocation-core/01-CONTEXT.md` — Registry schema decisions (D-01..D-11) that Phase 2 builds on
- `.planning/phases/01-registry-allocation-core/01-RESEARCH.md` — CC hook contract details, exit code semantics
- `hooks/claim-number.sh` — The allocation script that CC hook wrappers call
- `hooks/lib/common.sh` — Shared dependency checks and config loading
- `hooks/lib/gist.sh` — Registry read/write functions

### External References
- Claude Code hooks docs: `https://code.claude.com/docs/en/hooks` — UserPromptExpansion event contract, stdin/stdout JSON format, exit code semantics
- `.claude/settings.json` — where hook config is written (project-level, committed)

### Research
- `.planning/research/STACK.md` — CC hook contract details
- `.planning/research/PITFALLS.md` — Exit code 2 vs 1 trap, shell profile contamination

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `hooks/claim-number.sh` — Full allocation script with CLI args, already handles milestone and phase claiming. CC hook wrappers call this directly.
- `hooks/lib/common.sh` — `check_deps()`, `load_config()`, `verbose_log()` — all available for hook scripts.
- `hooks/lib/gist.sh` — `read_registry()`, `write_registry()` — gist operations.

### Established Patterns
- All scripts use `set -euo pipefail` and `REPO_ROOT=$(git rev-parse --show-toplevel)` for path resolution.
- Error output goes to stderr; success output to stdout.
- Exit code 2 for blocking errors (consistent with CC hook contract).

### Integration Points
- `.claude/settings.json` — new file to create with hook wiring entries
- `.claude/gsd-team.json` — already exists with gist ID config

</code_context>

<specifics>
## Specific Ideas

- Thin wrapper pattern previewed during discussion: wrapper calls `claim-number.sh`, captures output, formats as `{"additionalContext": "..."}` JSON on stdout
- The additionalContext message should be explicit: "Milestone N claimed (and phase 1 of milestone N). Use milestone number N for this command."
- stdin JSON parsing via `jq` to extract command args from the CC hook payload

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 2-CC Hook Integration*
*Context gathered: 2026-05-19*
