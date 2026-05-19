#!/usr/bin/env bash
# hooks/lib/common.sh — Shared helper functions for GSD team coordination hooks
# Provides: check_deps(), load_config(), verbose_log()

check_deps() {
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq is required. Install with: brew install jq" >&2
    exit 1
  }
  command -v gh >/dev/null 2>&1 || {
    echo "ERROR: gh CLI is required. Install with: brew install gh && gh auth login" >&2
    exit 1
  }
  gh auth status >/dev/null 2>&1 || {
    echo "ERROR: gh auth not configured. Run: gh auth login" >&2
    exit 1
  }
}

load_config() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"
  local config_file="$repo_root/.claude/gsd-team.json"
  [[ -f "$config_file" ]] || {
    echo "ERROR: .claude/gsd-team.json not found. Create it with your gist_id." >&2
    exit 1
  }
  GIST_ID="$(jq -r '.gist_id' "$config_file")"
  [[ "$GIST_ID" != "null" && -n "$GIST_ID" ]] || {
    echo "ERROR: gist_id not set in .claude/gsd-team.json" >&2
    exit 1
  }
}

verbose_log() {
  [[ -n "${GSD_VERBOSE:-}" ]] && echo "[GSD] $*" >&2 || true
}
