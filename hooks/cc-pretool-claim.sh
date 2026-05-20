#!/usr/bin/env bash
# hooks/cc-pretool-claim.sh — PreToolUse hook for Bash tool
#
# Intercepts gsd-sdk init calls for new-milestone and plan-phase workflows.
# Claims the next number from the shared gist registry and injects it as
# additionalContext so Claude uses the team-coordinated number.
#
# Fast path: non-GSD bash commands exit 0 immediately (~5ms overhead).

set -euo pipefail

HOOK_JSON="$(cat)"

COMMAND=$(echo "$HOOK_JSON" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

claim_and_inject() {
  local claim_type="$1"
  local claim_args="$2"
  local context_msg="$3"

  local err_file
  err_file="$(mktemp)"
  set +e
  CLAIM_OUTPUT=$("$REPO_ROOT/hooks/claim-number.sh" $claim_args 2>"$err_file")
  CLAIM_EXIT=$?
  set -e

  if [[ $CLAIM_EXIT -ne 0 ]]; then
    cat "$err_file" >&2
    rm -f "$err_file"
    exit 2
  fi
  rm -f "$err_file"

  local num
  num=$(echo "$CLAIM_OUTPUT" | grep -oE '[0-9]+' | head -1 || true)
  if [[ -z "$num" ]]; then
    exit 0
  fi

  local msg
  msg=$(printf "$context_msg" "$num" "$num")

  jq -n --arg ctx "$msg" '{"additionalContext": $ctx}'
  exit 0
}

if echo "$COMMAND" | grep -qE 'gsd-sdk query init\.new-milestone|gsd-new-milestone'; then
  claim_and_inject "milestone" "milestone" \
    "TEAM REGISTRY: Milestone %s claimed (and phase 1). Use milestone number %s for this command."
fi

if echo "$COMMAND" | grep -qE 'gsd-sdk query init\.plan-phase'; then
  milestone_num=$(echo "$COMMAND" | grep -oE '[0-9]+' | head -1 || true)
  if [[ -n "$milestone_num" ]]; then
    claim_and_inject "phase" "phase $milestone_num" \
      "TEAM REGISTRY: Phase %s claimed for current milestone. Use phase number %s for this command."
  fi
fi

exit 0
