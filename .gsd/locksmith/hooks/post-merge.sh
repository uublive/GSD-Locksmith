#!/usr/bin/env bash
# .githooks/post-merge
#
# Phase:    04-setup-release-lifecycle
# Purpose:  Mark claims for the merged branch as "released" in the registry.
#           Keeps the registry clean after PRs land — no manual cleanup required.
#
# Limitation: This hook fires after successful merges (including fast-forward) but
#             NOT after rebases. Rebase-based workflows will leave claims as "active"
#             until they expire or are released manually.
#
# Activate:  git config core.hooksPath .githooks
#
# Note:      post-merge fires AFTER the merge is complete and cannot abort it.
#            All error paths MUST exit 0 — this hook must never disrupt the developer.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=.gsd/locksmith/lib/common.sh
source "$REPO_ROOT/.gsd/locksmith/lib/common.sh"
# shellcheck source=.gsd/locksmith/lib/registry.sh
source "$REPO_ROOT/.gsd/locksmith/lib/registry.sh"

# --- Prerequisite checks (non-blocking: wrap with || exit 0) ---
check_deps || {
  echo "WARNING: post-merge gsd-registry cleanup skipped — missing dependencies (jq/gh/gh auth)" >&2
  exit 0
}
load_config || {
  echo "WARNING: post-merge gsd-registry cleanup skipped — .gsd/locksmith/config.json not configured" >&2
  exit 0
}

# --- Determine merged branch name ---
# git reflog in post-merge context: HEAD -1 shows the merge action.
# Formats:
#   "merge feature/foo: Fast-forward"
#   "merge origin/feature/foo: Merge made by the 'ort' strategy."
MERGED_BRANCH="$(git reflog show --format="%gs" HEAD -1 2>/dev/null | sed 's/^merge \(.*\): .*/\1/' || true)"

# Validate extraction: sed returns the full line unchanged if no match occurred.
# Also check it's non-empty.
if [[ -z "$MERGED_BRANCH" ]] || [[ "$MERGED_BRANCH" == "$(git reflog show --format="%gs" HEAD -1 2>/dev/null || true)" ]]; then
  verbose_log "post-merge: could not determine merged branch name, skipping stale release."
  exit 0
fi

verbose_log "post-merge: detected merged branch: $MERGED_BRANCH"

# --- Read registry (non-blocking) ---
REGISTRY="$(read_registry 2>/dev/null)" || {
  verbose_log "post-merge: registry read failed, skipping"
  exit 0
}

# Validate JSON
if ! echo "$REGISTRY" | jq -e . >/dev/null 2>&1; then
  verbose_log "post-merge: registry is not valid JSON, skipping"
  exit 0
fi

# --- Check for matching active claims ---
MATCH_COUNT="$(echo "$REGISTRY" | jq --arg b "$MERGED_BRANCH" '[.claims[] | select(.branch==$b and .status=="active")] | length')"

if [[ "$MATCH_COUNT" -eq 0 ]]; then
  echo "post-merge: no active claims for branch $MERGED_BRANCH — nothing to release"
  exit 0
fi

# --- Build updated registry with claims set to "released" ---
UPDATED="$(echo "$REGISTRY" | jq --arg b "$MERGED_BRANCH" '.claims |= map(if .branch==$b and .status=="active" then .status="released" else . end)')"

# --- Dry-run guard: skip write but report ---
if [[ -n "${GSD_DRY_RUN:-}" ]]; then
  echo "GSD (dry-run): Would release $MATCH_COUNT claim(s) for merged branch $MERGED_BRANCH"
  exit 0
fi

# --- Write updated registry (non-blocking) ---
write_registry "$UPDATED" || {
  echo "WARNING: post-merge registry write failed — stale claims for $MERGED_BRANCH not released" >&2
  exit 0
}

echo "GSD: Released $MATCH_COUNT claim(s) for merged branch $MERGED_BRANCH"
