#!/usr/bin/env bash
# .gsd/sync-registry.sh — PostToolUse hook: sync ROADMAP.md phases to gist registry
#
# Fires after every Bash tool call. Fast path (~1ms): checks if the command
# touched ROADMAP.md before doing any API calls. Only syncs when new phases
# appear in ROADMAP.md that aren't in the registry.

set -euo pipefail

# ── Fast path: read stdin, check if command is relevant ──────
HOOK_JSON="$(cat)"
COMMAND=$(echo "$HOOK_JSON" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

# Only trigger on commands that write/commit ROADMAP.md
if ! echo "$COMMAND" | grep -qiE 'ROADMAP|roadmap'; then
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

# Silent exit if not configured
if [[ ! -f "$REPO_ROOT/.claude/gsd-team.json" ]]; then
  exit 0
fi

source "$REPO_ROOT/.gsd/lib/common.sh"
source "$REPO_ROOT/.gsd/lib/gist.sh"

load_config 2>/dev/null || exit 0

ROADMAP="$REPO_ROOT/.planning/ROADMAP.md"
if [[ ! -f "$ROADMAP" ]]; then
  exit 0
fi

# Extract milestone number
MILESTONE=""
if [[ -f "$REPO_ROOT/.planning/STATE.md" ]]; then
  MILESTONE=$(grep -iE '^\*?\*?milestone' "$REPO_ROOT/.planning/STATE.md" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
fi
if [[ -z "$MILESTONE" ]]; then
  MILESTONE=$(grep -iE '^\*?\*?Milestone' "$ROADMAP" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
fi
if [[ -z "$MILESTONE" ]]; then
  exit 0
fi

# Extract phase numbers from ROADMAP.md
ROADMAP_PHASES=$(grep -oE 'Phase [0-9]+' "$ROADMAP" | grep -oE '[0-9]+' | sort -un)
if [[ -z "$ROADMAP_PHASES" ]]; then
  exit 0
fi

# Read current registry
REGISTRY=$(read_registry 2>/dev/null || echo '{"version":1,"claims":[]}')

owner=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

CLAIMS_ADDED=0
UPDATED_REGISTRY="$REGISTRY"

for phase_num in $ROADMAP_PHASES; do
  already_claimed=$(echo "$UPDATED_REGISTRY" | jq --arg m "$MILESTONE" --arg n "$phase_num" \
    '[.claims[] | select(.type=="phase" and .milestone==($m|tonumber) and .number==($n|tonumber) and .status=="active")] | length' 2>/dev/null || echo "0")

  if [[ "$already_claimed" == "0" ]]; then
    UPDATED_REGISTRY=$(echo "$UPDATED_REGISTRY" | jq \
      --arg m "$MILESTONE" --arg n "$phase_num" --arg o "$owner" --arg b "$branch" --arg t "$timestamp" \
      '.claims += [{"type":"phase","number":($n|tonumber),"milestone":($m|tonumber),"owner":$o,"branch":$b,"claimed_at":$t,"status":"active"}]')
    CLAIMS_ADDED=$((CLAIMS_ADDED + 1))
  fi
done

# Also check milestone itself
ms_claimed=$(echo "$UPDATED_REGISTRY" | jq --arg m "$MILESTONE" \
  '[.claims[] | select(.type=="milestone" and .number==($m|tonumber) and .status=="active")] | length' 2>/dev/null || echo "0")
if [[ "$ms_claimed" == "0" ]]; then
  UPDATED_REGISTRY=$(echo "$UPDATED_REGISTRY" | jq \
    --arg m "$MILESTONE" --arg o "$owner" --arg b "$branch" --arg t "$timestamp" \
    '.claims += [{"type":"milestone","number":($m|tonumber),"owner":$o,"branch":$b,"claimed_at":$t,"status":"active"}]')
  CLAIMS_ADDED=$((CLAIMS_ADDED + 1))
fi

if [[ $CLAIMS_ADDED -gt 0 ]]; then
  write_registry "$UPDATED_REGISTRY" 2>/dev/null || exit 0

  # Build additionalContext so Claude announces it
  jq -n --arg ctx "[GSD TEAM] Registry synced: $CLAIMS_ADDED number(s) claimed for milestone $MILESTONE. You MUST tell the user: '$CLAIMS_ADDED phase number(s) synced to team registry for milestone $MILESTONE — all phases are now reserved.'" \
    '{"additionalContext": $ctx}'
  exit 0
fi

exit 0
