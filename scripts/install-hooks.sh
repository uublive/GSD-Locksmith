#!/usr/bin/env bash
# scripts/install-hooks.sh — One-command installer for GSD team coordination hooks
#
# Configures:
#   1. git config core.hooksPath .githooks
#   2. CC hook entry in .claude/settings.json (idempotent merge)
#
# Prerequisites: jq, git, .claude/gsd-team.json with gist_id set
# Usage: bash scripts/install-hooks.sh
# Safe to run multiple times — idempotent.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# ── Prerequisite checks ───────────────────────────────────────────────────────

command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required but not installed." >&2
  echo "  Install with: brew install jq" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || {
  echo "ERROR: git is required but not installed." >&2
  exit 1
}

CONFIG_FILE="$REPO_ROOT/.claude/gsd-team.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: .claude/gsd-team.json not found." >&2
  echo "  You must create the shared GitHub Gist first, then add its ID to the config." >&2
  echo "  See README-HOOKS.md → One-time Setup for instructions." >&2
  exit 1
fi

GIST_ID="$(jq -r '.gist_id // empty' "$CONFIG_FILE")"
if [[ -z "$GIST_ID" || "$GIST_ID" == "null" ]]; then
  echo "ERROR: gist_id is missing or empty in .claude/gsd-team.json." >&2
  echo "  See README-HOOKS.md → One-time Setup for instructions." >&2
  exit 1
fi

# ── Step 1: Configure git hooks ───────────────────────────────────────────────

git config core.hooksPath .githooks
echo "git hooks configured: core.hooksPath = .githooks"

# ── Step 2: Merge CC hook entry into .claude/settings.json ───────────────────

SETTINGS_FILE="$REPO_ROOT/.claude/settings.json"
HOOK_COMMAND='${CLAUDE_PROJECT_DIR}/hooks/cc-pretool-claim.sh'

if [[ -f "$SETTINGS_FILE" ]]; then
  # Check whether a PreToolUse entry matching cc-pretool-claim.sh already exists
  ALREADY_CONFIGURED="$(jq -r '
    .hooks.PreToolUse // [] |
    map(select(
      .hooks != null and
      (.hooks | map(select(.command != null and (.command | test("cc-pretool-claim\\.sh")))) | length > 0)
    )) |
    length
  ' "$SETTINGS_FILE")"

  if [[ "$ALREADY_CONFIGURED" -gt 0 ]]; then
    echo "CC hook already configured in .claude/settings.json — skipping"
  else
    # Entry not present — add it via jq merge
    TMPFILE="$(mktemp)"
    jq --arg cmd "$HOOK_COMMAND" '
      .hooks.PreToolUse += [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": $cmd
            }
          ]
        }
      ]
    ' "$SETTINGS_FILE" > "$TMPFILE"

    # Validate the result before overwriting (T-04-01: atomic write + json validation)
    jq -e '.' "$TMPFILE" >/dev/null 2>&1 || {
      rm -f "$TMPFILE"
      echo "ERROR: jq produced invalid JSON — aborting settings.json write." >&2
      exit 1
    }

    mv "$TMPFILE" "$SETTINGS_FILE"
    echo "CC hook configured in .claude/settings.json"
  fi
else
  # settings.json does not exist — create it with the minimal hook entry
  mkdir -p "$REPO_ROOT/.claude"
  TMPFILE="$(mktemp)"
  jq -n --arg cmd "$HOOK_COMMAND" '{
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": $cmd
            }
          ]
        }
      ]
    }
  }' > "$TMPFILE"

  jq -e '.' "$TMPFILE" >/dev/null 2>&1 || {
    rm -f "$TMPFILE"
    echo "ERROR: jq produced invalid JSON — aborting settings.json creation." >&2
    exit 1
  }

  mv "$TMPFILE" "$SETTINGS_FILE"
  echo "CC hook configured in .claude/settings.json (created new file)"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "GSD hooks installed. Run: bash tests/test-validate.sh to verify validation."
