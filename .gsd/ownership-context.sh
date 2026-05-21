#!/usr/bin/env bash
# .gsd/ownership-context.sh — PostToolUse hook for Bash
#
# After any Bash call containing `gsd-sdk query roadmap` or `gsd-sdk query init`,
# reads the team registry and injects ownership context as additionalContext.
# Claude then knows who owns which milestones/phases and adjusts routing suggestions.

set -euo pipefail

HOOK_JSON="$(cat)"

COMMAND=$(echo "$HOOK_JSON" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

case "$COMMAND" in
  *"gsd-sdk query roadmap"*|*"gsd-sdk query init"*) ;;
  *) exit 0 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && exit 0
[[ -f "$REPO_ROOT/.claude/gsd-team.json" ]] || exit 0

source "$REPO_ROOT/.gsd/lib/common.sh"
source "$REPO_ROOT/.gsd/lib/registry.sh"

load_config 2>/dev/null || exit 0

REGISTRY=$(read_registry 2>/dev/null || true)
[[ -z "$REGISTRY" ]] && exit 0

ACTIVE_CLAIMS=$(echo "$REGISTRY" | jq '[.claims[] | select(.status=="active")]' 2>/dev/null || true)
CLAIM_COUNT=$(echo "$ACTIVE_CLAIMS" | jq 'length' 2>/dev/null || echo "0")
[[ "$CLAIM_COUNT" == "0" ]] && exit 0

MY_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")

SUMMARY=$(echo "$ACTIVE_CLAIMS" | jq -r --arg me "$MY_USER" '
  group_by(.milestone // .number) |
  map(
    (.[0].milestone // .[0].number) as $ms |
    group_by(.owner) |
    map(
      (.[0].owner) as $owner |
      (.[0].branch) as $branch |
      (map(select(.type=="phase")) | map(.number) | sort) as $phases |
      (map(select(.type=="milestone")) | length) as $has_ms |
      (if $owner == $me then " ← you" else "" end) as $marker |
      if $has_ms > 0 and ($phases | length) > 0 then
        "- Milestone " + ($ms | tostring) + ", phases " + ($phases | map(tostring) | join(", ")) + ": " + $owner + " (branch: " + $branch + ")" + $marker
      elif $has_ms > 0 then
        "- Milestone " + ($ms | tostring) + ": " + $owner + " (branch: " + $branch + ")" + $marker
      elif ($phases | length) > 0 then
        "- Milestone " + ($ms | tostring) + " phases " + ($phases | map(tostring) | join(", ")) + ": " + $owner + " (branch: " + $branch + ")" + $marker
      else
        ""
      end
    ) | join("\n")
  ) | join("\n")
' 2>/dev/null || true)

[[ -z "$SUMMARY" ]] && exit 0

CONTEXT="## Team Registry: Ownership Context\n${SUMMARY}\n\nNote: Items belong to the listed owner. Only suggest working on another user's items if explicitly asked."

jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
exit 0
