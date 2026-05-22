#!/usr/bin/env bash
# .gsd/locksmith/claim-number.sh — Allocation entry point for milestone and phase number claims
# Usage:
#   ./.gsd/locksmith/claim-number.sh milestone
#   ./.gsd/locksmith/claim-number.sh phase <milestone_num>
#
# Environment:
#   GSD_DRY_RUN=1    Preview the claim without writing to the registry
#   GSD_VERBOSE=1    Emit verbose operation logs to stderr

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
source "$REPO_ROOT/.gsd/locksmith/lib/common.sh"
source "$REPO_ROOT/.gsd/locksmith/lib/registry.sh"

check_deps
load_config

# --- Argument handling ---
TYPE="${1:-}"
MILESTONE_NUM="${2:-}"

if [[ -z "$TYPE" ]]; then
  echo "Usage: $(basename "$0") milestone" >&2
  echo "       $(basename "$0") phase <milestone_num>" >&2
  exit 2
fi

if [[ "$TYPE" != "milestone" && "$TYPE" != "phase" ]]; then
  echo "ERROR: TYPE must be 'milestone' or 'phase', got: '$TYPE'" >&2
  echo "Usage: $(basename "$0") milestone" >&2
  echo "       $(basename "$0") phase <milestone_num>" >&2
  exit 2
fi

if [[ "$TYPE" == "phase" ]]; then
  if [[ -z "$MILESTONE_NUM" ]]; then
    echo "ERROR: phase TYPE requires a milestone number as the second argument" >&2
    echo "Usage: $(basename "$0") phase <milestone_num>" >&2
    exit 2
  fi
  # Validate milestone_num is a positive integer (>= 1)
  if ! [[ "$MILESTONE_NUM" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: milestone_num must be a positive integer (>= 1), got: '$MILESTONE_NUM'" >&2
    exit 2
  fi
fi

# --- Gather metadata ---
owner="$(gh api user --jq '.login')"
branch="$(git branch --show-current)"
claimed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Read registry ---
# In dry-run mode, a missing/invalid registry is acceptable — we use a stub
REGISTRY=""
if [[ -n "${GSD_DRY_RUN:-}" ]]; then
  REGISTRY="$(read_registry 2>/dev/null)" || REGISTRY='{"version":1,"claims":[]}'
else
  REGISTRY="$(read_registry)"
fi

if ! echo "$REGISTRY" | jq -e . >/dev/null 2>&1; then
  if [[ -n "${GSD_DRY_RUN:-}" ]]; then
    REGISTRY='{"version":1,"claims":[]}'
  else
    echo "ERROR: registry is not valid JSON" >&2
    exit 2
  fi
fi

# --- Compute next number ---
if [[ "$TYPE" == "milestone" ]]; then
  NEXT_NUM="$(echo "$REGISTRY" | jq '[.claims[] | select(.type=="milestone" and .status=="active") | .number] | if length == 0 then 1 else max + 1 end')"
else
  NEXT_NUM="$(echo "$REGISTRY" | jq --argjson m "$MILESTONE_NUM" '[.claims[] | select(.type=="phase" and .status=="active" and .milestone==$m) | .number] | if length == 0 then 1 else max + 1 end')"
fi

verbose_log "Computed next $TYPE number: $NEXT_NUM"

# --- Build updated registry JSON ---
if [[ "$TYPE" == "milestone" ]]; then
  # D-08: Dual-claim — milestone + phase-1 in a single write
  UPDATED_REGISTRY="$(echo "$REGISTRY" | jq \
    --argjson m "$NEXT_NUM" \
    --arg owner "$owner" \
    --arg branch "$branch" \
    --arg claimed_at "$claimed_at" \
    '.claims += [
      {"type":"milestone","number":$m,"owner":$owner,"branch":$branch,"claimed_at":$claimed_at,"status":"active"},
      {"type":"phase","number":1,"milestone":$m,"owner":$owner,"branch":$branch,"claimed_at":$claimed_at,"status":"active"}
    ]')"
else
  UPDATED_REGISTRY="$(echo "$REGISTRY" | jq \
    --argjson n "$NEXT_NUM" \
    --argjson m "$MILESTONE_NUM" \
    --arg owner "$owner" \
    --arg branch "$branch" \
    --arg claimed_at "$claimed_at" \
    '.claims += [
      {"type":"phase","number":$n,"milestone":$m,"owner":$owner,"branch":$branch,"claimed_at":$claimed_at,"status":"active"}
    ]')"
fi

# --- Dry-run guard (ALLOC-04) ---
# Must short-circuit before any write or collision check. Stdout stays empty in dry-run mode.
if [[ -n "${GSD_DRY_RUN:-}" ]]; then
  if [[ "$TYPE" == "milestone" ]]; then
    echo "[DRY RUN] Would claim: type=milestone number=$NEXT_NUM owner=$owner branch=$branch" >&2
    echo "[DRY RUN] Would also claim: type=phase number=1 milestone=$NEXT_NUM owner=$owner branch=$branch" >&2
  else
    echo "[DRY RUN] Would claim: type=phase number=$NEXT_NUM milestone=$MILESTONE_NUM owner=$owner branch=$branch" >&2
  fi
  echo "[DRY RUN] No registry write performed." >&2
  exit 0
fi

# --- Write registry (first attempt) ---
verbose_log "Writing registry (first attempt)"
if ! write_registry "$UPDATED_REGISTRY"; then
  echo "ERROR: registry write failed" >&2
  exit 2
fi

# --- Re-read immediately after write for collision detection + write confirmation (D-09, Pitfall 4) ---
verbose_log "Re-reading registry for collision check"
REGISTRY_AFTER="$(read_registry)"

detect_collision() {
  local registry_after="$1"
  local num="$2"
  local type="$3"
  echo "$registry_after" | jq --argjson n "$num" --arg t "$type" --arg o "$owner" \
    '[.claims[] | select(.type==$t and .number==$n and .owner!=$o)] | length > 0'
}

collision="$(detect_collision "$REGISTRY_AFTER" "$NEXT_NUM" "$TYPE")"

if [[ "$collision" == "false" ]]; then
  verbose_log "No collision detected for $TYPE $NEXT_NUM"
else
  # First collision — extract competing owner and warn
  COMPETING_OWNER="$(echo "$REGISTRY_AFTER" | jq -r --argjson n "$NEXT_NUM" --arg t "$TYPE" --arg o "$owner" \
    '[.claims[] | select(.type==$t and .number==$n and .owner!=$o)] | .[0].owner // "unknown"')"
  echo "WARNING: Collision detected on $TYPE $NEXT_NUM — another developer claimed it first. Retrying..." >&2
  echo "Competing owner: $COMPETING_OWNER" >&2

  # Retry: strip our own stale active claims from the first (losing) write,
  # then recompute NEXT_NUM from the cleaned registry to avoid permanent orphan entries
  if [[ "$TYPE" == "milestone" ]]; then
    CLEAN_REGISTRY="$(echo "$REGISTRY_AFTER" | jq \
      --arg o "$owner" \
      'del(.claims[] | select(.owner==$o and .status=="active" and (.type=="milestone" or .type=="phase")))')"
    NEXT_NUM="$(echo "$CLEAN_REGISTRY" | jq '[.claims[] | select(.type=="milestone" and .status=="active") | .number] | if length == 0 then 1 else max + 1 end')"
    UPDATED_REGISTRY="$(echo "$CLEAN_REGISTRY" | jq \
      --argjson m "$NEXT_NUM" \
      --arg owner "$owner" \
      --arg branch "$branch" \
      --arg claimed_at "$claimed_at" \
      '.claims += [
        {"type":"milestone","number":$m,"owner":$owner,"branch":$branch,"claimed_at":$claimed_at,"status":"active"},
        {"type":"phase","number":1,"milestone":$m,"owner":$owner,"branch":$branch,"claimed_at":$claimed_at,"status":"active"}
      ]')"
  else
    CLEAN_REGISTRY="$(echo "$REGISTRY_AFTER" | jq \
      --arg o "$owner" --argjson m "$MILESTONE_NUM" \
      'del(.claims[] | select(.owner==$o and .status=="active" and .type=="phase" and .milestone==$m))')"
    NEXT_NUM="$(echo "$CLEAN_REGISTRY" | jq --argjson m "$MILESTONE_NUM" '[.claims[] | select(.type=="phase" and .status=="active" and .milestone==$m) | .number] | if length == 0 then 1 else max + 1 end')"
    UPDATED_REGISTRY="$(echo "$CLEAN_REGISTRY" | jq \
      --argjson n "$NEXT_NUM" \
      --argjson m "$MILESTONE_NUM" \
      --arg owner "$owner" \
      --arg branch "$branch" \
      --arg claimed_at "$claimed_at" \
      '.claims += [
        {"type":"phase","number":$n,"milestone":$m,"owner":$owner,"branch":$branch,"claimed_at":$claimed_at,"status":"active"}
      ]')"
  fi

  verbose_log "Writing registry (retry after collision)"
  if ! write_registry "$UPDATED_REGISTRY"; then
    echo "ERROR: registry write failed on retry" >&2
    exit 2
  fi

  verbose_log "Re-reading registry for collision check after retry"
  REGISTRY_AFTER="$(read_registry)"
  collision="$(detect_collision "$REGISTRY_AFTER" "$NEXT_NUM" "$TYPE")"

  if [[ "$collision" == "true" ]]; then
    COMPETING_OWNER2="$(echo "$REGISTRY_AFTER" | jq -r --argjson n "$NEXT_NUM" --arg t "$TYPE" --arg o "$owner" \
      '[.claims[] | select(.type==$t and .number==$n and .owner!=$o)] | .[0].owner // "unknown"')"
    echo "ERROR: Collision persists after retry on $TYPE $NEXT_NUM. Another developer ($COMPETING_OWNER2) claimed the same number. Resolve manually by editing the registry or running this command again." >&2
    exit 2
  fi

  # Success after retry
  if [[ "$TYPE" == "milestone" ]]; then
    echo "Claimed milestone $NEXT_NUM and phase 1 of milestone $NEXT_NUM (after retry due to collision)"
  else
    echo "Claimed phase $NEXT_NUM of milestone $MILESTONE_NUM (after retry due to collision)"
  fi
  exit 0
fi

# --- Success output (stdout only) ---
if [[ "$TYPE" == "milestone" ]]; then
  echo "Claimed milestone $NEXT_NUM and phase 1 of milestone $NEXT_NUM"
else
  echo "Claimed phase $NEXT_NUM of milestone $MILESTONE_NUM"
fi
