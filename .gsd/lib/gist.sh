#!/usr/bin/env bash
# .gsd/lib/gist.sh — Registry read/write functions via GitHub Gist
# Provides: read_registry(), write_registry()
# Requires: GIST_ID to be set (via load_config() from common.sh)

: "${REPO_ROOT:=$(git rev-parse --show-toplevel)}"
source "$REPO_ROOT/.gsd/lib/common.sh"

GIST_FILE="registry.json"

read_registry() {
  verbose_log "Reading registry from gist $GIST_ID"
  gh gist view "$GIST_ID" --filename "$GIST_FILE" --raw
}

write_registry() {
  local content="$1"
  verbose_log "Writing registry to gist $GIST_ID"
  local payload
  payload=$(jq -n --arg c "$content" '{"files":{"registry.json":{"content":$c}}}')
  local rc=0
  echo "$payload" | gh api --method PATCH "/gists/$GIST_ID" --input - > /dev/null || rc=$?
  return $rc
}
