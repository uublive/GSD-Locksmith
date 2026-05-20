# GSD Team Coordination Hooks

Automatic milestone and phase number claiming with collision detection — no Slack coordination needed.

## Prerequisites

Install these tools before running the setup script.

| Tool | Install command | Purpose |
|------|-----------------|---------|
| `jq` | `brew install jq` | JSON processing for registry and settings.json |
| `gh` CLI | `brew install gh` | GitHub Gist read/write for the shared registry |
| GitHub auth | `gh auth login` | Authenticates `gh` CLI against your GitHub account |

Verify all three are ready:

```bash
jq --version
gh --version
gh auth status
```

## One-time Setup

These steps are done **once per repository** (usually by the team lead). If your team lead has already completed steps 1 and 2, start from step 3.

### Step 1: Create the shared GitHub Gist (team lead only)

Create a public Gist that will hold the shared number registry:

```bash
gh gist create --public --filename registry.json - <<'EOF'
{"version":1,"claims":[]}
EOF
```

The command prints a URL. Copy the Gist ID from the URL (the alphanumeric string at the end, e.g. `74549bde02583c38325b1f0af81fd0ad`).

### Step 2: Add the Gist ID to the project config

Replace `<YOUR_GIST_ID>` with the ID copied above:

```bash
echo '{"gist_id":"<YOUR_GIST_ID>","project":"gsd-team-work"}' > .claude/gsd-team.json
```

If `.claude/gsd-team.json` already exists in the repo (team lead committed it), skip this step — the file is already correct.

### Step 3: Run the installer

```bash
bash scripts/install-hooks.sh
```

Expected output:

```
git hooks configured: core.hooksPath = .githooks
CC hook configured in .claude/settings.json
GSD hooks installed. Run: bash tests/test-validate.sh to verify validation.
```

The installer is idempotent — running it again is safe and will print `already configured` instead of re-writing.

## Verification

Run these commands after installation to confirm everything is wired up:

```bash
# 1. Git hooks path
git config core.hooksPath
# Expected: .githooks

# 2. CC hook entry in settings.json
cat .claude/settings.json | jq '.hooks.PreToolUse'
# Expected: JSON array showing the cc-pretool-claim.sh entry

# 3. Planning file validation suite
bash tests/test-validate.sh
# Expected: 8 passed, 0 failed

# 4. Dry-run number claim (no gist write)
GSD_DRY_RUN=1 bash hooks/claim-number.sh milestone
# Expected: [DRY RUN] Would claim: type=milestone ...
```

## Usage

Once installed, the following workflows are automated:

### CC hooks — number claiming

When you run `/gsd-new-milestone` or `/gsd-new-phase` in a Claude Code session, the `hooks/cc-pretool-claim.sh` hook fires automatically before the GSD command executes. It:

1. Reads the shared Gist registry to find the next available number
2. Claims that number with your branch name and GitHub username
3. Returns the allocated number so the GSD command can use it

No Slack coordination needed — the registry handles collision detection automatically.

### Git hooks — merge-time validation

When a feature branch is merged to `development` or `develop`, the `.githooks/pre-merge-commit` hook fires and validates:

- Phase number gaps in `ROADMAP.md`
- Duplicate REQ-IDs in `REQUIREMENTS.md`
- STATE.md vs ROADMAP.md consistency
- Stale plan cross-references

If validation fails, the merge is blocked with the exact file, line number, and fix command.

## Troubleshooting

### "ERROR: gh auth not configured"

The `gh` CLI is installed but not authenticated.

```bash
gh auth login
```

Follow the prompts to authenticate with GitHub. Re-run `bash scripts/install-hooks.sh` after.

### "ERROR: .claude/gsd-team.json not found"

The project config file does not exist.

```bash
echo '{"gist_id":"<YOUR_GIST_ID>","project":"gsd-team-work"}' > .claude/gsd-team.json
```

Replace `<YOUR_GIST_ID>` with the shared Gist ID (get it from your team lead or from the repo if already committed).

### "pre-merge-commit hook not firing on merge"

The git hooks path is not configured for this clone.

```bash
git config core.hooksPath .githooks
```

Or re-run the installer:

```bash
bash scripts/install-hooks.sh
```
