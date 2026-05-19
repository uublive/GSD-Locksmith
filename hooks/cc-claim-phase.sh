#!/usr/bin/env bash
# hooks/cc-claim-phase.sh — CC UserPromptExpansion hook for /gsd-new-phase
#
# Purpose: Thin wrapper that reads CC hook stdin JSON, extracts milestone number from
#          command_args, calls claim-number.sh phase <n>, and emits additionalContext
#          JSON to stdout for Claude context injection.
#
# Inputs:  CC hook JSON payload on stdin (hook_event_name, command_name, command_args, etc.)
#          command_args field contains the milestone number (e.g., "2" for /gsd-new-phase 2)
# Outputs: JSON on stdout: {"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":"..."}}
#
# Exit codes:
#   0 — Success; stdout contains additionalContext JSON; CC command proceeds
#   2 — Failure; stderr contains error message; CC command is BLOCKED (not code 1)
#
# Environment:
#   GSD_DRY_RUN=1  — Passed through to claim-number.sh; no gist write occurs

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Parse stdin JSON — read ALL stdin first, then extract command_args (D-05).
# Use jq -r with // "" default to prevent null propagation (T-02-02).
# jq exits non-zero on malformed JSON which set -e traps.
HOOK_JSON="$(cat)"
COMMAND_ARGS="$(echo "$HOOK_JSON" | jq -r '.command_args // ""')"

# Extract milestone number — first token of command_args.
MILESTONE_NUM="$(echo "$COMMAND_ARGS" | awk '{print $1}')"

# Validate MILESTONE_NUM before calling claim-number.sh (D-05, PITFALL 4, T-02-01).
# Must be a positive integer matching ^[1-9][0-9]*$ to prevent shell injection.
if [[ -z "$MILESTONE_NUM" ]] || ! [[ "$MILESTONE_NUM" =~ ^[1-9][0-9]*$ ]]; then
  if [[ -z "$MILESTONE_NUM" ]]; then
    echo "ERROR: /gsd-new-phase requires a milestone number. Usage: /gsd-new-phase <milestone_num>" >&2
  else
    echo "ERROR: /gsd-new-phase milestone number must be a positive integer, got: '${MILESTONE_NUM}'. Usage: /gsd-new-phase <milestone_num>" >&2
  fi
  exit 2  # blocks the command per D-06 (PITFALL 1: use code 2, not code 1)
fi

# Capture claim-number.sh output safely.
# CRITICAL: set -euo pipefail traps subprocess exit immediately, bypassing explicit error handling.
# Use set +e around the subprocess to safely capture both output and exit code (PITFALL 5).
ERR_FILE="$(mktemp /tmp/gsd-cc-phase-err.XXXXXX)"
set +e
CLAIM_OUTPUT="$("$REPO_ROOT/hooks/claim-number.sh" phase "$MILESTONE_NUM" 2>"$ERR_FILE")"
CLAIM_EXIT=$?
set -e

if [[ $CLAIM_EXIT -ne 0 ]]; then
  cat "$ERR_FILE" >&2
  rm -f "$ERR_FILE"
  exit 2  # blocks the command per D-06 (PITFALL 1: use code 2, not code 1)
fi

rm -f "$ERR_FILE"

# Extract phase number from CLAIM_OUTPUT.
# Success string: "Claimed phase N of milestone M"
# Use pattern to match "phase <number>" and extract the number.
# Also handles retry variant: "Claimed phase N of milestone M (after retry due to collision)"
PHASE_NUM="$(echo "$CLAIM_OUTPUT" | grep -oE 'phase [0-9]+' | grep -oE '[0-9]+' || true)"
if [[ -z "$PHASE_NUM" ]]; then
  # Dry-run mode or unexpected empty output — use placeholder 0
  PHASE_NUM="0"
fi

# Format additionalContext per D-07, D-08: explicit enough that Claude uses the correct numbers.
ADDITIONAL_CONTEXT="Phase ${PHASE_NUM} of milestone ${MILESTONE_NUM} claimed. Use milestone number ${MILESTONE_NUM} and phase number ${PHASE_NUM} for this command."

# Emit CC hook JSON on stdout.
# Use jq -n --arg to prevent injection if context contains quotes or newlines (Don't Hand-Roll).
# All other output goes to >&2 — stdout must be exclusively this JSON object (D-10, PITFALL 2).
printf '%s\n' "$(jq -n --arg ctx "$ADDITIONAL_CONTEXT" \
  '{"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":$ctx}}')"

exit 0
