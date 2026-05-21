#!/usr/bin/env bash
# .gsd/cc-pretool-claim.sh — PreToolUse hook for Bash tool
#
# Intercepts gsd-sdk init calls that create milestone or phase numbers.
# Claims the next number from the shared gist registry and injects
# additionalContext so Claude uses the team-coordinated number.
#
# Covered commands:
#   - init.new-milestone  → claim milestone N + phase 1
#   - init.new-project    → claim milestone 1 + phase 1
#   - gsd-phase --insert  → claim the inserted phase number
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

# Check if hooks are installed (gsd-team.json exists with a real gist ID)
if [[ ! -f "$REPO_ROOT/.claude/gsd-team.json" ]]; then
  exit 0
fi
GIST_ID=$(jq -r '.gist_id // ""' "$REPO_ROOT/.claude/gsd-team.json" 2>/dev/null || true)
if [[ -z "$GIST_ID" || "$GIST_ID" == "null" || "$GIST_ID" == "REPLACE_WITH_YOUR_GIST_ID" ]]; then
  exit 0
fi

claim_and_inject() {
  local claim_args="$1"
  local context_msg="$2"

  local err_file
  err_file="$(mktemp)"
  set +e
  CLAIM_OUTPUT=$("$REPO_ROOT/.gsd/claim-number.sh" $claim_args 2>"$err_file")
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
  msg=$(echo "$context_msg" | sed "s/%s/$num/g")

  jq -n --arg ctx "$msg" '{"additionalContext": $ctx}'
  exit 0
}

# ── New milestone (/gsd-new-milestone) ───────────────────────
if echo "$COMMAND" | grep -qE 'gsd-sdk query init\.new-milestone'; then
  claim_and_inject "milestone" \
    "[GSD TEAM] Milestone %s claimed from shared registry (and phase 1 auto-claimed). You MUST tell the user: 'Milestone %s claimed from team registry — no conflicts with other developers.' Then use milestone number %s for this command."
  # claim_and_inject exits; unreachable
fi

# ── New project (/gsd-new-project) ───────────────────────────
if echo "$COMMAND" | grep -qE 'gsd-sdk query init\.new-project'; then
  claim_and_inject "milestone" \
    "[GSD TEAM] Project initialized — milestone 1 and phase 1 claimed from shared registry. You MUST tell the user: 'Milestone %s claimed from team registry — your project numbers are reserved.' Then use milestone number %s."
  # claim_and_inject exits; unreachable
fi

# ── Phase insert (/gsd-phase --insert N) ─────────────────────
if echo "$COMMAND" | grep -qE 'gsd-phase\s+--insert|gsd-sdk query roadmap\.insert-phase'; then
  # Extract the milestone number from STATE.md (handles both "Milestone: 1" and "milestone: v1.0")
  CURRENT_MILESTONE=$(grep -iE '^\*?\*?milestone' "$REPO_ROOT/.planning/STATE.md" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
  if [[ -n "$CURRENT_MILESTONE" ]]; then
    claim_and_inject "phase $CURRENT_MILESTONE" \
      "[GSD TEAM] Phase %s claimed from shared registry for milestone $CURRENT_MILESTONE. You MUST tell the user: 'Phase %s claimed from team registry — no conflicts with other developers.' Then use phase number %s for the inserted phase."
  fi
fi

exit 0
