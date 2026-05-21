#!/usr/bin/env bash
# .gsd/install-hooks.sh — One-command installer for GSD team coordination hooks
#
# Configures:
#   1. git config core.hooksPath .githooks
#   2. CC hooks in .claude/settings.json:
#      - PreToolUse on Write/Edit for ROADMAP gate (conflict detection)
#      - PostToolUse on Bash for ownership context injection
#
# Prerequisites: jq, git, gh, .claude/gsd-team.json
# Usage: bash .gsd/install-hooks.sh
# Safe to run multiple times — idempotent.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# ── Prerequisite checks ──────────────────────────────────────
command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required but not installed." >&2
  echo "  Install with: brew install jq" >&2
  exit 1
}

CONFIG_FILE="$REPO_ROOT/.claude/gsd-team.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: .claude/gsd-team.json not found." >&2
  echo "  See README-HOOKS.md for setup instructions." >&2
  exit 1
fi

REGISTRY_BRANCH="$(jq -r '.registry_branch // "gsd-registry"' "$CONFIG_FILE")"
if [[ -z "$REGISTRY_BRANCH" || "$REGISTRY_BRANCH" == "null" ]]; then
  echo "ERROR: registry_branch is missing in .claude/gsd-team.json." >&2
  exit 1
fi

# ── Step 1: Configure git hooks ──────────────────────────────
git config core.hooksPath .githooks
echo "git hooks configured: core.hooksPath = .githooks"

# ── Step 2: Write .claude/settings.json with roadmap gate ────
SETTINGS_FILE="$REPO_ROOT/.claude/settings.json"
GATE_CMD='${CLAUDE_PROJECT_DIR}/.gsd/roadmap-gate.sh'
OWNERSHIP_CMD='${CLAUDE_PROJECT_DIR}/.gsd/ownership-context.sh'

if [[ -f "$SETTINGS_FILE" ]] && jq -e '.hooks.PreToolUse' "$SETTINGS_FILE" &>/dev/null; then
  ALREADY_GATE=$(jq '[.hooks.PreToolUse[] | select(.hooks[]?.command | test("roadmap-gate"))] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
  ALREADY_OWN=$(jq '[.hooks.PostToolUse // [] | .[] | select(.hooks[]?.command | test("ownership-context"))] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")

  if [[ "$ALREADY_GATE" -gt 0 ]] && [[ "$ALREADY_OWN" -gt 0 ]]; then
    echo "CC hooks already configured — skipping"
  else
    TMPFILE="$(mktemp)"
    jq -n --arg gate "$GATE_CMD" --arg own "$OWNERSHIP_CMD" '{
      "hooks": {
        "PreToolUse": [
          {"matcher": "Write", "hooks": [{"type": "command", "command": $gate}]},
          {"matcher": "Edit", "hooks": [{"type": "command", "command": $gate}]}
        ],
        "PostToolUse": [
          {"matcher": "Bash", "hooks": [{"type": "command", "command": $own}]}
        ]
      }
    }' > "$TMPFILE"
    jq -e '.' "$TMPFILE" >/dev/null 2>&1 || { rm -f "$TMPFILE"; echo "ERROR: invalid JSON" >&2; exit 1; }
    mv "$TMPFILE" "$SETTINGS_FILE"
    echo "CC hooks updated: roadmap gate + ownership context"
  fi
else
  mkdir -p "$REPO_ROOT/.claude"
  TMPFILE="$(mktemp)"
  jq -n --arg gate "$GATE_CMD" --arg own "$OWNERSHIP_CMD" '{
    "hooks": {
      "PreToolUse": [
        {"matcher": "Write", "hooks": [{"type": "command", "command": $gate}]},
        {"matcher": "Edit", "hooks": [{"type": "command", "command": $gate}]}
      ],
      "PostToolUse": [
        {"matcher": "Bash", "hooks": [{"type": "command", "command": $own}]}
      ]
    }
  }' > "$TMPFILE"
  jq -e '.' "$TMPFILE" >/dev/null 2>&1 || { rm -f "$TMPFILE"; echo "ERROR: invalid JSON" >&2; exit 1; }
  mv "$TMPFILE" "$SETTINGS_FILE"
  echo "CC hooks configured: roadmap gate + ownership context"
fi

echo ""
echo "GSD hooks installed. Run: bash .gsd/tests/test-validate.sh to verify."
