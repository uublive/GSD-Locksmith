#!/usr/bin/env bash
# .gsd/locksmith/uninstall.sh — Remove all GSD Locksmith artifacts from a project
#
# Usage: bash .gsd/locksmith/uninstall.sh
#
# Removes:
#   - .gsd/locksmith/ directory (all locksmith-owned files)
#   - GSD-LOCKSMITH marker blocks from .githooks/ files
#   - Locksmith hook entries from .claude/settings.json
#   - .claude/commands/gsd-status.md
#   - GSD-LOCKSMITH section from CLAUDE.md
#   - core.hooksPath if .githooks/ is empty after cleanup
#
# Does NOT remove the gsd-registry orphan branch (shared team state).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: Not in a git repository." >&2
  exit 1
}

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
header() { echo -e "\n${BOLD}$1${NC}"; }

header "Uninstalling GSD Locksmith..."

# 1. Strip GSD-LOCKSMITH blocks from .githooks/
if [[ -d "$REPO_ROOT/.githooks" ]]; then
  for hook_file in "$REPO_ROOT/.githooks/"*; do
    [[ -f "$hook_file" ]] || continue
    if grep -q "GSD-LOCKSMITH-START" "$hook_file"; then
      sed -i.bak '/# GSD-LOCKSMITH-START/,/# GSD-LOCKSMITH-END/d' "$hook_file"
      rm -f "$hook_file.bak"

      # Remove file if only shebang/whitespace remains
      content_after=$(grep -v '^[[:space:]]*$' "$hook_file" | grep -v '^#!/' || true)
      if [[ -z "$content_after" ]]; then
        rm -f "$hook_file"
        info "$(basename "$hook_file") — removed (was locksmith-only)"
      else
        info "$(basename "$hook_file") — locksmith block stripped"
      fi
    fi
  done

  # Remove .githooks/ if empty
  if [[ -d "$REPO_ROOT/.githooks" ]] && [[ -z "$(ls -A "$REPO_ROOT/.githooks")" ]]; then
    rmdir "$REPO_ROOT/.githooks"
    git config --unset core.hooksPath 2>/dev/null || true
    info "core.hooksPath unset (.githooks/ was empty)"
  fi
fi

# 2. Remove locksmith entries from .claude/settings.json
SETTINGS="$REPO_ROOT/.claude/settings.json"
if [[ -f "$SETTINGS" ]] && command -v jq &>/dev/null; then
  UPDATED=$(jq '
    if .hooks then
      .hooks.PreToolUse = [.hooks.PreToolUse[]? | select(.hooks[]?.command | test("locksmith/") | not)] |
      .hooks.PostToolUse = [.hooks.PostToolUse[]? | select(.hooks[]?.command | test("locksmith/") | not)] |
      if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end |
      if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end |
      if (.hooks | keys | length) == 0 then del(.hooks) else . end
    else . end
  ' "$SETTINGS" 2>/dev/null)

  if [[ -n "$UPDATED" ]]; then
    if [[ "$UPDATED" == "{}" ]]; then
      rm -f "$SETTINGS"
      info ".claude/settings.json — removed (was locksmith-only)"
    else
      echo "$UPDATED" | jq '.' > "$SETTINGS"
      info ".claude/settings.json — locksmith hooks removed"
    fi
  fi
fi

# 3. Remove slash command
if [[ -f "$REPO_ROOT/.claude/commands/gsd-status.md" ]]; then
  rm -f "$REPO_ROOT/.claude/commands/gsd-status.md"
  info ".claude/commands/gsd-status.md — removed"
fi

# 4. Strip locksmith section from CLAUDE.md
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]] && grep -q "GSD-LOCKSMITH-START" "$CLAUDE_MD"; then
  sed -i.bak '/<!-- GSD-LOCKSMITH-START -->/,/<!-- GSD-LOCKSMITH-END -->/d' "$CLAUDE_MD"
  rm -f "$CLAUDE_MD.bak"
  # Remove trailing blank lines
  sed -i.bak -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$CLAUDE_MD"
  rm -f "$CLAUDE_MD.bak"
  info "CLAUDE.md — locksmith section removed"
fi

# 5. Remove .gsd/locksmith/ directory (self-destruct)
if [[ -d "$REPO_ROOT/.gsd/locksmith" ]]; then
  rm -rf "$REPO_ROOT/.gsd/locksmith"
  info ".gsd/locksmith/ — removed"
fi

header "Uninstall complete."
echo ""
echo "  The gsd-registry branch on GitHub was NOT deleted (shared team state)."
echo "  To delete it manually: gh api --method DELETE /repos/OWNER/REPO/git/refs/heads/gsd-registry"
echo ""
