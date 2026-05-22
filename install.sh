#!/usr/bin/env bash
# install.sh — One-shot installer for GSD Locksmith
#
# Usage:
#   bash install.sh                    # interactive — asks for path
#   bash install.sh /path/to/project   # direct — installs into target
#
# What it does:
#   1. Validates prerequisites (jq, gh, gh auth)
#   2. Creates target directory if needed, inits git if needed
#   3. Copies hooks/, .githooks/, scripts/, tests/, README-HOOKS.md
#   4. Sets up shared registry branch (create new or reuse existing)
#   5. Runs install-hooks.sh to wire git + CC hooks
#
# Safe for existing projects — never overwrites non-hook files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors (only when TTY) ──────────────────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BOLD=''; NC=''
fi

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
header() { echo -e "\n${BOLD}$1${NC}"; }

# ── Step 1: Prerequisites ───────────────────────────────────
header "Checking prerequisites..."

MISSING=0
if ! command -v jq &>/dev/null; then
  error "jq not found — install with: brew install jq"
  MISSING=1
fi
if ! command -v gh &>/dev/null; then
  error "gh CLI not found — install with: brew install gh"
  MISSING=1
fi
if command -v gh &>/dev/null && ! gh auth status &>/dev/null; then
  error "gh not authenticated — run: gh auth login"
  MISSING=1
fi

if [[ $MISSING -ne 0 ]]; then
  echo ""
  error "Fix the above issues and re-run this installer."
  exit 1
fi

info "jq $(jq --version 2>/dev/null)"
info "gh $(gh --version 2>/dev/null | head -1 | awk '{print $3}')"
info "gh auth OK ($(gh api user --jq '.login' 2>/dev/null))"

# ── Step 2: Target path ─────────────────────────────────────
header "Target project..."

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo -n "Enter project path (absolute or relative): "
  read -r TARGET
fi

if [[ -z "$TARGET" ]]; then
  error "No path provided."
  exit 1
fi

TARGET="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)/$(basename "$TARGET")" || TARGET="$(pwd)/$TARGET"

if [[ "$TARGET" == "$SCRIPT_DIR" ]]; then
  error "Cannot install into the plugin source directory itself."
  exit 1
fi

# ── Step 3: Create / validate target ────────────────────────
if [[ ! -d "$TARGET" ]]; then
  echo -n "Directory $TARGET does not exist. Create it? [Y/n] "
  read -r CONFIRM
  if [[ "${CONFIRM:-Y}" =~ ^[Nn] ]]; then
    echo "Aborted."
    exit 0
  fi
  mkdir -p "$TARGET"
  info "Created $TARGET"
fi

cd "$TARGET"

if [[ ! -d .git ]]; then
  echo -n "No git repository found. Initialize one? [Y/n] "
  read -r CONFIRM
  if [[ "${CONFIRM:-Y}" =~ ^[Nn] ]]; then
    warn "Skipping git init — some features require git."
  else
    git init
    info "Git repository initialized"
  fi
fi

# ── Step 4: Copy hook files ─────────────────────────────────
header "Installing GSD Locksmith..."

DIRS_TO_COPY=(.gsd .githooks .claude/commands)
FILES_TO_COPY=(README-HOOKS.md)

for dir in "${DIRS_TO_COPY[@]}"; do
  if [[ -d "$SCRIPT_DIR/$dir" ]]; then
    if [[ -d "$TARGET/$dir" ]]; then
      cp -rn "$SCRIPT_DIR/$dir/." "$TARGET/$dir/" 2>/dev/null || \
        rsync -a --ignore-existing "$SCRIPT_DIR/$dir/" "$TARGET/$dir/"
      info "$dir/ — merged (existing files preserved)"
    else
      cp -r "$SCRIPT_DIR/$dir" "$TARGET/$dir"
      info "$dir/ — created"
    fi
  fi
done

for file in "${FILES_TO_COPY[@]}"; do
  if [[ -f "$SCRIPT_DIR/$file" ]]; then
    if [[ -f "$TARGET/$file" ]]; then
      warn "$file already exists — skipped (won't overwrite)"
    else
      cp "$SCRIPT_DIR/$file" "$TARGET/$file"
      info "$file — created"
    fi
  fi
done

chmod 750 "$TARGET/.gsd/"*.sh 2>/dev/null || true
chmod 644 "$TARGET/.gsd/lib/"*.sh 2>/dev/null || true
chmod 750 "$TARGET/.gsd/tests/"*.sh 2>/dev/null || true
chmod 750 "$TARGET/.githooks/"* 2>/dev/null || true

# ── Step 5: Registry branch setup ──────────────────────────
header "Shared registry branch..."

mkdir -p "$TARGET/.claude"

REGISTRY_BRANCH="gsd-registry"
REPO_NWO="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)" || {
  error "Could not determine GitHub repository. Ensure a GitHub remote is configured."
  error "Run: git remote add origin <your-repo-url>"
  exit 1
}

BRANCH_EXISTS=0
gh api "/repos/$REPO_NWO/git/refs/heads/$REGISTRY_BRANCH" &>/dev/null && BRANCH_EXISTS=1

if [[ "$BRANCH_EXISTS" -eq 1 ]]; then
  info "Registry branch '$REGISTRY_BRANCH' already exists on $REPO_NWO"
else
  echo "Creating orphan branch '$REGISTRY_BRANCH' on $REPO_NWO..."

  BLOB_SHA=$(jq -n '{"content":"{\"version\":1,\"claims\":[]}","encoding":"utf-8"}' | \
    gh api "/repos/$REPO_NWO/git/blobs" --method POST --input - --jq '.sha')

  TREE_SHA=$(jq -n --arg sha "$BLOB_SHA" '{tree:[{path:"registry.json",mode:"100644",type:"blob",sha:$sha}]}' | \
    gh api "/repos/$REPO_NWO/git/trees" --method POST --input - --jq '.sha')

  COMMIT_SHA=$(jq -n --arg tree "$TREE_SHA" '{message:"init: gsd-registry",tree:$tree,parents:[]}' | \
    gh api "/repos/$REPO_NWO/git/commits" --method POST --input - --jq '.sha')

  gh api "/repos/$REPO_NWO/git/refs" --method POST --input - > /dev/null <<REFEOF
{"ref":"refs/heads/$REGISTRY_BRANCH","sha":"$COMMIT_SHA"}
REFEOF

  info "Registry branch created on $REPO_NWO"
fi

PROJECT_NAME=$(basename "$TARGET")
jq -n --arg b "$REGISTRY_BRANCH" --arg p "$PROJECT_NAME" \
  '{registry_branch:$b,project:$p}' > "$TARGET/.claude/gsd-team.json"
info "Config written: .claude/gsd-team.json"

# ── Step 5b: Add locksmith rule to CLAUDE.md ────────────
header "Adding locksmith rule to CLAUDE.md..."

CLAUDE_MD="$TARGET/CLAUDE.md"
TEAM_MARKER="## GSD Locksmith"

if [[ -f "$CLAUDE_MD" ]] && grep -q "$TEAM_MARKER" "$CLAUDE_MD"; then
  info "CLAUDE.md already has locksmith rule — skipped"
else
  cat >> "$CLAUDE_MD" <<'CLAUDEEOF'

## GSD Locksmith

This project uses a shared registry (on the `gsd-registry` orphan branch) to coordinate milestone and phase numbers across the team. CC hooks automatically claim numbers before GSD commands execute.

**IMPORTANT: When you see [GSD TEAM] in hook context or additionalContext:**
1. ALWAYS announce the claim to the user before proceeding (e.g., "Milestone 2 claimed from locksmith")
2. Use the claimed number — do not pick a different one
3. If a claim fails (hook exits with error), stop and show the error to the user

**Registry commands available to the user:**
- `./.gsd/gsd-status.sh` — view all active claims
- `./.gsd/claim-number.sh milestone` — manually claim a milestone number
- `./.gsd/claim-number.sh phase <milestone_num>` — manually claim a phase number
- `GSD_DRY_RUN=1` prefix — preview without writing

## Infrastructure Files (do not modify)

The `.gsd/`, `.githooks/`, and `.claude/` directories contain GSD Locksmith infrastructure.
These are NOT part of this project's source code. Do not modify, review, plan, or include them in
any code analysis, phase scope, or implementation task.
CLAUDEEOF
  info "CLAUDE.md updated with locksmith rule"
fi

# ── Step 6: Run install-hooks.sh ─────────────────────────────
header "Wiring hooks..."

if [[ -f "$TARGET/.gsd/install-hooks.sh" ]]; then
  bash "$TARGET/.gsd/install-hooks.sh"
else
  warn "install-hooks.sh not found — configuring manually"
  git config core.hooksPath .githooks 2>/dev/null || true
  info "git hooks path set to .githooks"
fi

# ── Step 7: Verify ──────────────────────────────────────────
header "Verifying installation..."

ERRORS=0

if [[ "$(git config core.hooksPath 2>/dev/null)" == ".githooks" ]]; then
  info "Git hooks: .githooks"
else
  error "Git hooks path not set"
  ERRORS=$((ERRORS + 1))
fi

if [[ -f "$TARGET/.claude/settings.json" ]] && jq -e '.hooks.PreToolUse' "$TARGET/.claude/settings.json" &>/dev/null; then
  info "CC hooks: PreToolUse configured"
else
  warn "CC hooks: settings.json not configured (run install-hooks.sh manually)"
fi

REG_CHECK=$(jq -r '.registry_branch' "$TARGET/.claude/gsd-team.json" 2>/dev/null)
if [[ -n "$REG_CHECK" && "$REG_CHECK" != "null" ]]; then
  info "Registry branch: $REG_CHECK on $REPO_NWO"
else
  warn "Registry branch: not configured yet"
  ERRORS=$((ERRORS + 1))
fi

if [[ -f "$TARGET/tests/test-validate.sh" ]]; then
  if bash "$TARGET/tests/test-validate.sh" &>/dev/null; then
    info "Validation tests: all passing"
  else
    warn "Validation tests: some failures (run: bash tests/test-validate.sh)"
  fi
fi

# ── Done ─────────────────────────────────────────────────────
echo ""
if [[ $ERRORS -eq 0 ]]; then
  header "Installation complete! ✓"
else
  header "Installation complete with warnings."
fi

echo ""
echo "  Project:   $TARGET"
echo "  Registry:  $REGISTRY_BRANCH branch on $REPO_NWO"
echo ""
echo "  Quick test:"
echo "    cd $TARGET"
echo "    GSD_DRY_RUN=1 bash .gsd/claim-number.sh milestone"
echo ""
echo "  Teammates just clone and run:"
echo "    bash install.sh $TARGET"
echo "    (registry branch is auto-detected — no config to share)"
echo ""
