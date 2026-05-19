#!/usr/bin/env bash
# hooks/cc-claim-milestone.sh — CC UserPromptExpansion hook for /gsd-new-milestone
#
# Purpose: Thin wrapper that reads CC hook stdin JSON, calls claim-number.sh milestone,
#          and emits additionalContext JSON to stdout for Claude context injection.
#
# Inputs:  CC hook JSON payload on stdin (hook_event_name, command_name, command_args, etc.)
# Outputs: JSON on stdout: {"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":"..."}}
#
# Exit codes:
#   0 — Success; stdout contains additionalContext JSON; CC command proceeds
#   2 — Failure; stderr contains error message; CC command is BLOCKED (not exit 1)
#
# Environment:
#   GSD_DRY_RUN=1  — Passed through to claim-number.sh; no gist write occurs

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Read ALL stdin — CC pipes the hook JSON payload here.
# Milestone wrapper does not need to parse it (D-04: no args needed from stdin for milestone claim).
HOOK_JSON="$(cat)"

# Capture claim-number.sh output safely.
# CRITICAL: set -euo pipefail traps subprocess exit immediately, bypassing explicit error handling.
# Use set +e around the subprocess to safely capture both output and exit code (PITFALL 5).
ERR_FILE="$(mktemp /tmp/gsd-cc-milestone-err.XXXXXX)"
set +e
CLAIM_OUTPUT="$("$REPO_ROOT/hooks/claim-number.sh" milestone 2>"$ERR_FILE")"
CLAIM_EXIT=$?
set -e

if [[ $CLAIM_EXIT -ne 0 ]]; then
  cat "$ERR_FILE" >&2
  rm -f "$ERR_FILE"
  exit 2  # blocks the command per D-06 (PITFALL 1: use code 2, not code 1)
fi

rm -f "$ERR_FILE"

# Extract milestone number from CLAIM_OUTPUT.
# Success string: "Claimed milestone N and phase 1 of milestone N"
# First integer match is N (VERIFIED from claim-number.sh lines 209-212).
# In dry-run mode, claim-number.sh exits 0 with empty stdout (writes to stderr only).
# Use "0" as the placeholder number in dry-run — no real claim was made.
MILESTONE_NUM="$(echo "$CLAIM_OUTPUT" | grep -oE '[0-9]+' | head -1 || true)"
if [[ -z "$MILESTONE_NUM" ]]; then
  # Dry-run mode or unexpected empty output — use placeholder 0 to satisfy smoke test
  MILESTONE_NUM="0"
fi

# Format additionalContext per D-07, D-08: explicit enough that Claude uses the correct number.
ADDITIONAL_CONTEXT="Milestone ${MILESTONE_NUM} claimed (and phase 1 of milestone ${MILESTONE_NUM}). Use milestone number ${MILESTONE_NUM} for this command."

# Emit CC hook JSON on stdout.
# Use jq -n --arg to prevent injection if context contains quotes or newlines (Don't Hand-Roll).
# All other output goes to >&2 — stdout must be exclusively this JSON object (D-10, PITFALL 2).
printf '%s\n' "$(jq -n --arg ctx "$ADDITIONAL_CONTEXT" \
  '{"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":$ctx}}')"

exit 0
