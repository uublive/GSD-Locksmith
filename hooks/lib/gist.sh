#!/usr/bin/env bash
# hooks/lib/gist.sh — Registry read/write functions via GitHub Gist
# Provides: read_registry(), write_registry()
# Requires: GIST_ID to be set (via load_config() from common.sh)

: "${REPO_ROOT:=$(git rev-parse --show-toplevel)}"
source "$REPO_ROOT/hooks/lib/common.sh"

GIST_FILE="registry.json"

read_registry() {
  verbose_log "Reading registry from gist $GIST_ID"
  gh gist view "$GIST_ID" --filename "$GIST_FILE" --raw
}

write_registry() {
  local content="$1"
  local tmpfile
  tmpfile="$(mktemp /tmp/gsd-registry-XXXXXX.json)"
  printf '%s' "$content" > "$tmpfile"
  verbose_log "Writing registry to gist $GIST_ID"
  local rc=0
  gh api --method PATCH "/gists/$GIST_ID" \
    --field "files[registry.json][content]=@$tmpfile" || rc=$?
  rm -f "$tmpfile"
  return $rc
}
