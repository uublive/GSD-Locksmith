#!/usr/bin/env bash
# .gsd/roadmap-gate.sh — PreToolUse hook for Write/Edit on ROADMAP.md
#
# Fires before any Write or Edit to files matching ROADMAP.md.
# Extracts milestone/phase numbers from the content, checks the shared
# registry for conflicts, and either:
#   - BLOCKS the write (exit 2) if a number is already claimed by someone else
#   - CLAIMS unclaimed numbers and allows the write (exit 0)
#
# Registry stored on the gsd-registry orphan branch in the same repo.

set -euo pipefail

HOOK_JSON="$(cat)"

# ── Fast path: only care about ROADMAP.md ────────────────────
TOOL_NAME=$(echo "$HOOK_JSON" | jq -r '.tool_name // ""' 2>/dev/null || true)
FILE_PATH=""

if [[ "$TOOL_NAME" == "Write" ]]; then
  FILE_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  FILE_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
else
  exit 0
fi

if ! echo "$FILE_PATH" | grep -qE 'ROADMAP\.md$'; then
  exit 0
fi

# ── Setup ────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

if [[ ! -f "$REPO_ROOT/.claude/gsd-team.json" ]]; then
  exit 0
fi

source "$REPO_ROOT/.gsd/lib/common.sh"
source "$REPO_ROOT/.gsd/lib/registry.sh"

load_config 2>/dev/null || exit 0

# ── Extract numbers from the content being written ───────────
CONTENT=""
if [[ "$TOOL_NAME" == "Write" ]]; then
  CONTENT=$(echo "$HOOK_JSON" | jq -r '.tool_input.content // ""' 2>/dev/null || true)
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  # For edits, read the current file and check both old and new state
  CONTENT=$(echo "$HOOK_JSON" | jq -r '.tool_input.new_string // ""' 2>/dev/null || true)
  # Also read existing file to get full context
  if [[ -f "$FILE_PATH" ]]; then
    EXISTING=$(cat "$FILE_PATH" 2>/dev/null || true)
    CONTENT="$EXISTING
$CONTENT"
  fi
fi

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Extract milestone number
MILESTONE=$(echo "$CONTENT" | grep -iE '^\*?\*?Milestone' | grep -oE '[0-9]+' | head -1 || true)
if [[ -z "$MILESTONE" ]]; then
  exit 0
fi

# Extract all phase numbers
PHASE_NUMBERS=$(echo "$CONTENT" | grep -oE 'Phase [0-9]+' | grep -oE '[0-9]+' | sort -un)
if [[ -z "$PHASE_NUMBERS" ]]; then
  exit 0
fi

# ── Check registry for conflicts ─────────────────────────────
REGISTRY=$(read_registry 2>/dev/null || echo '{"version":1,"claims":[]}')
MY_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
MY_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

CONFLICTS=""
UNCLAIMED=""

# Check milestone
MS_CLAIM=$(echo "$REGISTRY" | jq --arg m "$MILESTONE" \
  '.claims[] | select(.type=="milestone" and .number==($m|tonumber) and .status=="active")' 2>/dev/null || true)

if [[ -n "$MS_CLAIM" ]]; then
  MS_OWNER=$(echo "$MS_CLAIM" | jq -r '.owner' 2>/dev/null || true)
  MS_BRANCH=$(echo "$MS_CLAIM" | jq -r '.branch' 2>/dev/null || true)
  if [[ "$MS_OWNER" != "$MY_USER" ]]; then
    CONFLICTS="Milestone $MILESTONE is claimed by @$MS_OWNER on branch $MS_BRANCH"
  fi
else
  UNCLAIMED="milestone:$MILESTONE $UNCLAIMED"
fi

# Check each phase
for phase_num in $PHASE_NUMBERS; do
  PH_CLAIM=$(echo "$REGISTRY" | jq --arg m "$MILESTONE" --arg n "$phase_num" \
    '.claims[] | select(.type=="phase" and .milestone==($m|tonumber) and .number==($n|tonumber) and .status=="active")' 2>/dev/null || true)

  if [[ -n "$PH_CLAIM" ]]; then
    PH_OWNER=$(echo "$PH_CLAIM" | jq -r '.owner' 2>/dev/null || true)
    PH_BRANCH=$(echo "$PH_CLAIM" | jq -r '.branch' 2>/dev/null || true)
    if [[ "$PH_OWNER" != "$MY_USER" ]]; then
      CONFLICTS="${CONFLICTS:+$CONFLICTS; }Phase $phase_num (milestone $MILESTONE) is claimed by @$PH_OWNER on branch $PH_BRANCH"
    fi
  else
    UNCLAIMED="phase:$MILESTONE:$phase_num $UNCLAIMED"
  fi
done

# ── Block if conflicts found ─────────────────────────────────
if [[ -n "$CONFLICTS" ]]; then
  # Find the next available numbers to suggest
  MAX_PHASE=$(echo "$REGISTRY" | jq --arg m "$MILESTONE" \
    '[.claims[] | select(.type=="phase" and .milestone==($m|tonumber)) | .number] | if length == 0 then 0 else max end' 2>/dev/null || echo "0")
  NEXT_PHASE=$((MAX_PHASE + 1))

  echo "[GSD TEAM] CONFLICT: $CONFLICTS. Next available phase number: $NEXT_PHASE. Renumber the conflicting phases and retry the write." >&2
  exit 2
fi

# ── Claim unclaimed numbers ──────────────────────────────────
if [[ -n "$UNCLAIMED" ]]; then
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  UPDATED_REGISTRY="$REGISTRY"
  CLAIMS_ADDED=0

  for item in $UNCLAIMED; do
    IFS=':' read -r type ms_num ph_num <<< "$item"

    if [[ "$type" == "milestone" ]]; then
      UPDATED_REGISTRY=$(echo "$UPDATED_REGISTRY" | jq \
        --arg m "$ms_num" --arg o "$MY_USER" --arg b "$MY_BRANCH" --arg t "$timestamp" \
        '.claims += [{"type":"milestone","number":($m|tonumber),"owner":$o,"branch":$b,"claimed_at":$t,"status":"active"}]')
      CLAIMS_ADDED=$((CLAIMS_ADDED + 1))
    elif [[ "$type" == "phase" ]]; then
      UPDATED_REGISTRY=$(echo "$UPDATED_REGISTRY" | jq \
        --arg m "$ms_num" --arg n "$ph_num" --arg o "$MY_USER" --arg b "$MY_BRANCH" --arg t "$timestamp" \
        '.claims += [{"type":"phase","number":($n|tonumber),"milestone":($m|tonumber),"owner":$o,"branch":$b,"claimed_at":$t,"status":"active"}]')
      CLAIMS_ADDED=$((CLAIMS_ADDED + 1))
    fi
  done

  if [[ $CLAIMS_ADDED -gt 0 ]]; then
    write_registry "$UPDATED_REGISTRY" 2>/dev/null || true
    jq -n --arg ctx "[GSD TEAM] $CLAIMS_ADDED number(s) claimed from team registry for milestone $MILESTONE. You MUST tell the user: '$CLAIMS_ADDED number(s) claimed from team registry — no conflicts with other developers.'" \
      '{"additionalContext": $ctx}'
    exit 0
  fi
fi

exit 0
