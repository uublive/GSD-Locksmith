# Phase 2: CC Hook Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 2-CC Hook Integration
**Areas discussed:** Hook event type, Command matching, Hook-to-script bridge, additionalContext

---

## Hook Event Type

| Option | Description | Selected |
|--------|-------------|----------|
| UserPromptExpansion | Fires when user types /slash command — correct for direct invocation | ✓ |
| PreToolUse on Bash | Fires when Claude runs a bash command — only catches indirect invocations | |
| Both | UserPromptExpansion for /slash + PreToolUse for indirect bash | |

**User's choice:** UserPromptExpansion
**Notes:** PreToolUse does NOT fire for direct slash command invocation per CC docs research.

---

## Command Matching

| Option | Description | Selected |
|--------|-------------|----------|
| Exact command names | Two separate hook entries, one per command — precise, no false positives | ✓ |
| Pattern match | Single regex matching both commands — risk of false positives | |

**User's choice:** Exact command names
**Notes:** User approved the preview showing two separate entries in settings.json.

---

## Hook-to-Script Bridge

### Wrapper approach

| Option | Description | Selected |
|--------|-------------|----------|
| Thin wrappers | cc-claim-milestone.sh and cc-claim-phase.sh call claim-number.sh | ✓ |
| Independent scripts | Duplicate allocation logic in CC-specific scripts | |

**User's choice:** Thin wrappers
**Notes:** User approved the preview showing wrapper that calls claim-number.sh and formats additionalContext JSON.

### Phase milestone extraction

| Option | Description | Selected |
|--------|-------------|----------|
| Parse from stdin JSON | Extract milestone number from CC hook's stdin JSON payload | ✓ |
| Prompt Claude to pass it | Exit 2 if missing, ask user to specify | |

**User's choice:** Parse from stdin JSON

---

## additionalContext

| Option | Description | Selected |
|--------|-------------|----------|
| additionalContext JSON | Hook stdout JSON with additionalContext field injected into Claude's prompt | ✓ |
| Stderr message only | Print to stderr — user sees it but Claude doesn't | |

**User's choice:** additionalContext JSON
**Notes:** User approved preview showing explicit message format: "Milestone N claimed... Use milestone number N for this command."

---

## Claude's Discretion

No areas delegated to Claude's discretion.

## Deferred Ideas

None — discussion stayed within phase scope.
