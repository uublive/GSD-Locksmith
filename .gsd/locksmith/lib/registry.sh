#!/usr/bin/env bash
# .gsd/locksmith/lib/registry.sh — Registry read/write via orphan branch in same repo
# Provides: read_registry(), write_registry()
# Requires: REGISTRY_REPO and REGISTRY_BRANCH to be set (via load_config() from common.sh)

: "${REPO_ROOT:=$(git rev-parse --show-toplevel)}"
source "$REPO_ROOT/.gsd/locksmith/lib/common.sh"

REGISTRY_FILE="registry.json"

read_registry() {
  verbose_log "Reading registry from $REGISTRY_REPO branch $REGISTRY_BRANCH"
  gh api "/repos/$REGISTRY_REPO/contents/$REGISTRY_FILE?ref=$REGISTRY_BRANCH" \
    -H "Accept: application/vnd.github.raw+json"
}

write_registry() {
  local content="$1"
  verbose_log "Writing registry to $REGISTRY_REPO branch $REGISTRY_BRANCH"

  local sha
  sha=$(gh api "/repos/$REGISTRY_REPO/contents/$REGISTRY_FILE?ref=$REGISTRY_BRANCH" --jq '.sha' 2>/dev/null || true)

  local encoded
  encoded=$(printf '%s' "$content" | base64 | tr -d '\n')

  local rc=0
  local payload
  if [[ -n "$sha" ]]; then
    payload=$(jq -n --arg msg "update registry" --arg c "$encoded" --arg s "$sha" --arg b "$REGISTRY_BRANCH" \
      '{message:$msg,content:$c,sha:$s,branch:$b}')
  else
    payload=$(jq -n --arg msg "update registry" --arg c "$encoded" --arg b "$REGISTRY_BRANCH" \
      '{message:$msg,content:$c,branch:$b}')
  fi

  echo "$payload" | gh api --method PUT "/repos/$REGISTRY_REPO/contents/$REGISTRY_FILE" --input - > /dev/null || rc=$?
  return $rc
}
