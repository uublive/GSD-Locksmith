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
#   4. Sets up shared gist (create new or reuse existing)
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

DIRS_TO_COPY=(.gsd .githooks)
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

# ── Step 5: Gist setup ──────────────────────────────────────
header "Shared registry gist..."

mkdir -p "$TARGET/.claude"

if [[ -f "$TARGET/.claude/gsd-team.json" ]]; then
  EXISTING_ID=$(jq -r '.gist_id // ""' "$TARGET/.claude/gsd-team.json" 2>/dev/null)
  if [[ -n "$EXISTING_ID" && "$EXISTING_ID" != "REPLACE_WITH_YOUR_GIST_ID" && "$EXISTING_ID" != "null" ]]; then
    info "Gist already configured: $EXISTING_ID"
  else
    warn "gsd-team.json exists but gist_id is not set."
    EXISTING_ID=""
  fi
else
  EXISTING_ID=""
fi

if [[ -z "$EXISTING_ID" ]]; then
  echo ""
  echo "The team needs a shared GitHub Gist to store number claims."
  echo ""
  echo "  1) Create a new gist (first person setting up)"
  echo "  2) Enter an existing gist ID (teammate already created it)"
  echo ""
  echo -n "Choice [1/2]: "
  read -r GIST_CHOICE

  if [[ "${GIST_CHOICE:-1}" == "1" ]]; then
    echo "Creating shared gist..."
    GIST_URL=$(gh gist create --public --filename registry.json - <<'GISTEOF'
{"version":1,"claims":[]}
GISTEOF
    )
    GIST_ID=$(echo "$GIST_URL" | grep -oE '[a-f0-9]{20,}' | tail -1)
    if [[ -z "$GIST_ID" ]]; then
      error "Failed to extract gist ID from: $GIST_URL"
      echo "Create a gist manually at https://gist.github.com with a file named registry.json"
      echo "containing: {\"version\":1,\"claims\":[]}"
      echo -n "Then enter the gist ID: "
      read -r GIST_ID
    else
      info "Gist created: $GIST_URL"
    fi
  else
    echo -n "Enter the gist ID: "
    read -r GIST_ID
  fi

  if [[ -z "$GIST_ID" ]]; then
    error "No gist ID provided. You can set it later in .claude/gsd-team.json"
    GIST_ID="REPLACE_WITH_YOUR_GIST_ID"
  fi

  PROJECT_NAME=$(basename "$TARGET")
  echo "{\"gist_id\":\"$GIST_ID\",\"project\":\"$PROJECT_NAME\"}" | jq '.' > "$TARGET/.claude/gsd-team.json"
  info "Config written: .claude/gsd-team.json"
fi

# ── Step 5b: Add locksmith rule to CLAUDE.md ────────────
header "Adding locksmith rule to CLAUDE.md..."

CLAUDE_MD="$TARGET/CLAUDE.md"
TEAM_MARKER="## GSD Locksmith"

if [[ -f "$CLAUDE_MD" ]] && grep -q "$TEAM_MARKER" "$CLAUDE_MD"; then
  info "CLAUDE.md already has locksmith rule — skipped"
else
  cat >> "$CLAUDE_MD" <<'CLAUDEEOF'

## GSD Locksmith

This project uses a shared GitHub Gist registry to coordinate milestone and phase numbers across the team. CC hooks automatically claim numbers before GSD commands execute.

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

GIST_CHECK=$(jq -r '.gist_id' "$TARGET/.claude/gsd-team.json" 2>/dev/null)
if [[ -n "$GIST_CHECK" && "$GIST_CHECK" != "REPLACE_WITH_YOUR_GIST_ID" && "$GIST_CHECK" != "null" ]]; then
  info "Registry gist: $GIST_CHECK"
else
  warn "Registry gist: not configured yet"
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
echo "  Project:  $TARGET"
echo "  Gist:     ${GIST_CHECK:-not set}"
echo ""
echo "  Quick test:"
echo "    cd $TARGET"
echo "    GSD_DRY_RUN=1 bash .gsd/claim-number.sh milestone"
echo ""
echo "  Share the gist ID with your team — they run:"
echo "    bash install.sh $TARGET"
echo "    (choose option 2 and enter the same gist ID)"
echo ""
