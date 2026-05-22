#!/usr/bin/env bash
# .gsd/locksmith/lib/common.sh — Shared helper functions for GSD team coordination hooks
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
  local config_file="$repo_root/.gsd/locksmith/config.json"
  [[ -f "$config_file" ]] || {
    echo "ERROR: .gsd/locksmith/config.json not found. Run install.sh to set up." >&2
    exit 1
  }
  REGISTRY_BRANCH="$(jq -r '.registry_branch // "gsd-registry"' "$config_file")"
  REGISTRY_REPO="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)" || {
    echo "ERROR: Could not determine GitHub repository. Ensure a GitHub remote is configured." >&2
    exit 1
  }
}

verbose_log() {
  [[ -n "${GSD_VERBOSE:-}" ]] && echo "[GSD] $*" >&2 || true
}
