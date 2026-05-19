#!/usr/bin/env bash
# hooks/gsd-status.sh — Read-only status display for GSD team registry
# Shows a formatted table of all active claims from the shared gist registry.
# Usage: ./hooks/gsd-status.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
source "$REPO_ROOT/hooks/lib/common.sh"
source "$REPO_ROOT/hooks/lib/gist.sh"

check_deps
load_config

REGISTRY="$(read_registry)"

# Validate registry JSON
echo "$REGISTRY" | jq -e . >/dev/null 2>&1 || {
  echo "ERROR: Registry JSON is invalid or could not be read from gist." >&2
  exit 2
}

# Check for active claims
ACTIVE_COUNT="$(echo "$REGISTRY" | jq '[.claims[] | select(.status=="active")] | length')"

if [[ "$ACTIVE_COUNT" -eq 0 ]]; then
  echo "No active claims in registry."
  exit 0
fi

# Render table header
printf "%-12s %-8s %-10s %-12s %-25s %-20s\n" "TYPE" "NUMBER" "MILESTONE" "OWNER" "BRANCH" "CLAIMED_AT"
printf "%s\n" "---------------------------------------------------------------------------------------------"

# Render active claims: sort by type then number, pipe through column for alignment
echo "$REGISTRY" | jq -r '[.claims[] | select(.status=="active")] | sort_by(.type, .number) | .[] | [.type, (.number|tostring), (.milestone // "-"|tostring), .owner, .branch, .claimed_at] | @tsv' \
  | column -t -s $'\t'
