# GSD Team Sync

Automatic milestone and phase number coordination for teams using [GSD (Get Shit Done)](https://github.com/labtroniq/get-shit-done-cc) with Claude Code. Prevents number collisions when multiple developers create milestones and phases in parallel — no Slack coordination needed.

## The Problem

When a team of developers uses GSD with Claude Code on the same project:

1. Dev A runs `/gsd-new-milestone` and gets Milestone 2
2. Dev B runs `/gsd-new-milestone` on their branch and also gets Milestone 2
3. Both merge to development — **conflict**

The same happens with phase numbers, phase inserts, and any roadmap changes.

## The Solution

A shared GitHub Gist acts as a lightweight number registry. Claude Code hooks automatically:

- **Claim numbers** when anyone writes to `ROADMAP.md` (via a PreToolUse gate on Write/Edit)
- **Block conflicts** if a number is already claimed by another developer
- **Validate integrity** when merging to development (phase gaps, duplicate IDs, stale references)
- **Release claims** after branches are merged

No server, no database, no additional runtime — just `bash`, `jq`, and `gh` CLI.

## How It Works

```
Developer writes ROADMAP.md
        │
        ▼
┌─────────────────────┐
│  roadmap-gate.sh    │  PreToolUse hook on Write/Edit
│  (before file save) │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐     ┌──────────────────┐
│  Check gist registry │────▶│  GitHub Gist     │
│  for conflicts       │◀────│  registry.json   │
└────────┬────────────┘     └──────────────────┘
         │
    ┌────┴────┐
    │         │
 conflict   free
    │         │
    ▼         ▼
 BLOCK     CLAIM
 (exit 2)  (exit 0)
 suggest   allow write
 next #
```

## Quick Start

### Install into an existing project

```bash
# Clone this repo somewhere
git clone https://github.com/YOUR_USER/gsd-team-sync.git

# Run the installer, pointing at your project
bash gsd-team-sync/install.sh /path/to/your-project
```

The installer will:
1. Check prerequisites (`jq`, `gh`, `gh auth`)
2. Copy `.gsd/`, `.githooks/` into your project
3. Create or reuse a shared GitHub Gist
4. Configure git hooks and Claude Code hooks
5. Add team registry rules to your `CLAUDE.md`
6. Verify the setup

### Manual setup (step by step)

#### Prerequisites

| Tool | Install | Purpose |
|------|---------|---------|
| `jq` | `brew install jq` | JSON processing |
| `gh` CLI | `brew install gh` | GitHub Gist API |
| GitHub auth | `gh auth login` | Authentication |

#### 1. Create the shared gist (once per team)

```bash
gh gist create --public --filename registry.json - <<'EOF'
{"version":1,"claims":[]}
EOF
```

Copy the gist ID from the output URL.

#### 2. Copy files into your project

```bash
cp -r gsd-team-sync/.gsd /path/to/your-project/
cp -r gsd-team-sync/.githooks /path/to/your-project/
```

#### 3. Configure the gist ID

```bash
mkdir -p .claude
echo '{"gist_id":"YOUR_GIST_ID","project":"your-project-name"}' > .claude/gsd-team.json
```

#### 4. Run the installer

```bash
bash .gsd/install-hooks.sh
```

#### 5. Commit and push

```bash
git add .gsd/ .githooks/ .claude/ README-HOOKS.md
git commit -m "chore: add GSD team sync hooks"
git push
```

Teammates pull and run `bash .gsd/install-hooks.sh` — one command, done.

## What Gets Installed

```
.gsd/                          # Hidden from Claude's project analysis
  roadmap-gate.sh              # PreToolUse hook — claims/blocks on ROADMAP.md writes
  claim-number.sh              # Manual number claiming CLI
  gsd-status.sh                # View active claims
  install-hooks.sh             # Per-developer setup
  lib/common.sh                # Shared: dep checks, config, logging
  lib/gist.sh                  # Shared: gist read/write
  lib/validate.sh              # 4 merge-time integrity checks
  tests/test-validate.sh       # 8 fixture tests

.githooks/                     # Activated via core.hooksPath
  pre-merge-commit             # Blocks merges with integrity issues
  post-merge                   # Releases claims after merge

.claude/
  settings.json                # CC hook wiring (Write/Edit → roadmap-gate)
  gsd-team.json                # Shared gist ID config
```

## Features

### Automatic Number Claiming

When any GSD command writes or edits `ROADMAP.md`, the roadmap gate hook fires **before** the file is saved:

- Extracts all milestone and phase numbers from the content
- Checks the shared gist registry for conflicts
- **Blocks** if a number is claimed by another developer (suggests the next free number)
- **Claims** unclaimed numbers and allows the write
- Injects context so Claude announces the claim to the user

### Merge-Time Validation

When merging a feature branch to `development` or `develop`, four checks run:

| Check | What it catches |
|-------|----------------|
| Phase gaps | Phase 2 followed by Phase 4 — missing Phase 3 |
| Duplicate REQ-IDs | `AUTH-01` defined twice with different content |
| STATE.md drift | State says Phase 2 active but ROADMAP has no Phase 2 |
| Stale references | Plan references a requirement or phase that was removed |

Errors show the exact file, line number, and fix command:

```
ROADMAP.md:14: ERROR: Phase gap -- expected Phase 3 found Phase 4
  Fix: add Phase 3 entry before line 14, or renumber phases sequentially
```

### Stale Claim Cleanup

After a successful merge, the `post-merge` hook marks the merged branch's claims as `"released"` in the registry, freeing those numbers for reuse.

## CLI Tools

```bash
# View all active claims
.gsd/gsd-status.sh

# Manually claim a milestone (+ auto-claims phase 1)
.gsd/claim-number.sh milestone

# Manually claim a phase under milestone 2
.gsd/claim-number.sh phase 2

# Dry run — preview without writing to gist
GSD_DRY_RUN=1 .gsd/claim-number.sh milestone

# Verbose — see all API calls
GSD_VERBOSE=1 .gsd/claim-number.sh milestone

# Run validation tests
bash .gsd/tests/test-validate.sh
```

## CLAUDE.md Integration

The installer adds two sections to your project's `CLAUDE.md`:

**Team Registry** — tells Claude to announce claims visibly when the hook fires, and lists available registry commands.

**Infrastructure Files** — tells Claude that `.gsd/`, `.githooks/`, and `.claude/` are not project source code and should not be modified, reviewed, or included in plans.

## How the Registry Works

The registry is a JSON file stored in a GitHub Gist:

```json
{
  "version": 1,
  "claims": [
    {
      "type": "milestone",
      "number": 2,
      "owner": "matteo",
      "branch": "feature/auth",
      "claimed_at": "2026-05-21T10:00:00Z",
      "status": "active"
    },
    {
      "type": "phase",
      "number": 1,
      "milestone": 2,
      "owner": "matteo",
      "branch": "feature/auth",
      "claimed_at": "2026-05-21T10:00:00Z",
      "status": "active"
    }
  ]
}
```

- **Conflict detection:** same owner = no conflict (you can edit your own numbers freely). Different owner = blocked.
- **Concurrency:** best-effort read-then-write with collision detection and one retry. Team of 3 — simultaneous claims are rare.
- **Cleanup:** merged branches have claims marked `"released"` (never deleted — preserves history).

## Limitations

- **Pre-merge-commit** only fires on clean auto-merges, not conflict-resolution merges
- **Best-effort concurrency** — two developers claiming at the exact same millisecond could collide (extremely rare for small teams, resolved manually)
- **Requires `gh auth login`** on each developer's machine
- **GitHub Gist** must be accessible (no offline mode)

## Troubleshooting

### Hook not firing

Verify hooks are installed:

```bash
git config core.hooksPath          # Should print: .githooks
cat .claude/settings.json | jq .   # Should show PreToolUse entries
```

Re-run the installer:

```bash
bash .gsd/install-hooks.sh
```

### "gh auth not configured"

```bash
gh auth login
```

### Merge blocked by validation

The error message includes the file, line, and fix command. Fix the issue and retry the merge.

To bypass in an emergency:

```bash
git merge --no-verify feature/branch
```

### Stale claims in registry

View and identify stale claims:

```bash
.gsd/gsd-status.sh
```

Manually release by editing the gist — change `"status": "active"` to `"status": "released"` for the stale entries.

## Requirements

- macOS or Linux (bash 3.2+)
- `jq` 1.6+
- `gh` CLI 2.x with `gh auth login` completed
- Git 2.9+ (for `core.hooksPath`)
- Claude Code with GSD plugin

## License

MIT
