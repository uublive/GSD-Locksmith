# Feature Research

**Domain:** Team coordination / shared-state CLI plugin system (number registry + integrity checks)
**Researched:** 2026-05-19
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features the team assumes exist. Missing these = the plugin is broken or useless.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Atomic number claim via shared gist registry | Core pain being solved — without this the tool is just the old manual Slack workflow with extra steps | MEDIUM | Read-then-write on GitHub Gist API using `gh`; `updated_at` field enables last-write-wins detection; race is acceptable per PROJECT.md |
| Milestone number allocation (claim next available) | Devs need a milestone number before they can run `/gsd-new-milestone` | LOW | JSON registry in gist; scan for max+1 or first gap |
| Phase number allocation (claim next available within milestone) | Same expectation as milestones — parallel phase creation is the primary collision vector | LOW | Scoped per milestone in the registry JSON |
| Branch + owner metadata in registry | Without knowing who claimed what number on which branch, collision reports are unactionable | LOW | Store `{ number, branch, owner, claimed_at }` per entry |
| CC hook interception of `/gsd-new-milestone` | Automates the claim without requiring devs to run a separate command — if it's not automatic it won't get used | MEDIUM | `PreToolUse` hook matching the slash command bash invocation; exits 0 to allow with modified input |
| CC hook interception of `/gsd-new-phase` | Same expectation as milestones | MEDIUM | Same pattern as milestone hook |
| Git pre-merge-commit hook for integrity checks | Devs expect merge-time safety nets — catching issues after the fact (post-push) is too late | MEDIUM | Hook fires after merge succeeds, before commit is written; can abort with non-zero exit |
| Duplicate REQ-ID detection at merge time | Planning files use sequential REQ-IDs; duplicates silently corrupt traceability | MEDIUM | `grep` across REQUIREMENTS.md for duplicate IDs; straightforward text scan |
| Phase numbering gap detection at merge time | Gaps indicate a merge collision was "resolved" by one branch clobbering the other | LOW | Sort extracted phase numbers, check for non-consecutive sequences |
| Clear error output with actionable remediation steps | Without "here's what broke and here's how to fix it" the hooks just block devs without explanation | LOW | Follow clig.dev: print to stderr, show exact fix command, use colors only when TTY detected |
| Installation script / setup docs | One-time setup per developer; if onboarding is undocumented the tool will never get used by all 3 devs | LOW | Bash installer that copies hooks to `.git/hooks/` and writes `.claude/settings.json` fragments |
| Gist config file (project-level, committed) | Devs need a way to share the gist ID without passing it by hand — a `.gsd-team.json` or similar | LOW | Committed JSON with `gist_id` field; hook scripts read from it |

### Differentiators (Competitive Advantage)

Features that make this tool notably better than the manual Slack coordination baseline, without expanding scope beyond what a 3-person bash-based team actually needs.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| STATE.md drift detection | Detects when ROADMAP.md and STATE.md diverge (e.g. a phase exists in one but not the other) after a merge — catches a whole class of subtle planning corruption that duplicate IDs and gaps don't cover | HIGH | Requires parsing both files and comparing phase/milestone sets; the hard part is defining "in sync" for irregular markdown formats |
| Stale cross-reference detection | Flags plan files that reference a REQ-ID, phase number, or milestone that no longer exists — prevents zombie references accumulating silently | HIGH | Multi-file grep + cross-map; expensive to implement correctly for all reference formats in use |
| Collision warning with rollback instructions | When the gist registry detects a number was claimed by two branches simultaneously (last-write-wins race), proactively prints the conflicting claim and the exact commands to resolve it | MEDIUM | Compare registry state before/after write; flag if a same-number entry exists for a different branch |
| `--dry-run` mode for registry operations | Lets devs see what number would be claimed without actually writing to the gist — useful for debugging and scripting | LOW | Skip the gist PATCH; print what would have been written |
| `--verbose` flag on all hooks | Exposes the gist read/write operations, exit codes, and validation steps for debugging without cluttering normal output | LOW | Gate all diagnostic output behind `$GSD_VERBOSE` env var or `--verbose` flag |
| Registry status command (`gsd-status`) | Shows all currently claimed numbers, who holds them, and which branch — replaces the Slack "what numbers are taken?" question entirely | LOW | `gh gist view` + JSON parse + formatted table output |
| Automatic stale claim cleanup | When a branch is deleted or merged, its registry entries are automatically released — prevents the registry from accumulating phantom claims | MEDIUM | Requires checking branch existence via `git branch -r`; can run as PostToolUse or as part of merge hook |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem like natural extensions but should be deliberately excluded.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Strict locking / pessimistic concurrency on gist | "What if two devs claim the same number at exactly the same time?" | GitHub Gist has no atomic test-and-set; true locking requires a separate service (Redis, database) — introduces infra dependency the project explicitly rejects. With 3 devs, simultaneous claims are rare and manual resolution is cheaper than the infra cost | Document the last-write-wins behavior clearly; add collision warning with rollback instructions (see differentiators) |
| Auto-creation of the shared gist | "It should just work out of the box without any setup" | Auto-creation means each dev might create their own gist if the config file doesn't exist yet — race condition on first use leads to split registries that silently diverge | One-time manual creation by one team member; gist ID stored in committed config file; installation script validates the config exists |
| Conflict auto-resolution for merge conflicts | "The hook should fix planning conflicts automatically" | Auto-resolution requires understanding the semantics of what each conflicting plan means — a wrong automated merge is worse than an unresolved conflict because it silently corrupts intent | Detect and report with exact conflict location and the commands to resolve manually |
| Web UI or dashboard | "It would be nice to see the registry in a browser" | Out of scope per PROJECT.md; introduces JS/HTML surface area and a separate deployment concern. The `gsd-status` command (differentiator above) covers the same visibility need from the terminal | `gsd-status` CLI command |
| Non-gitflow workflow support | "What about trunk-based development or monorepo setups?" | Hardcodes assumptions about branch naming and merge targets; supporting multiple workflows exponentially increases edge cases and test surface | Document explicitly that the plugin assumes gitflow (feature branches → development); make the branch naming pattern configurable via the config file if needed |
| Auto-push of registry changes to remote | "The gist update should propagate instantly to everyone" | `gh gist edit` already writes to the remote GitHub Gist API — there is no local-only state to push. This anti-feature is a misunderstanding, not a real request, but documenting it prevents confusion during implementation | The gist IS the remote — reads and writes are always remote via the GitHub API |
| Semantic versioning or changelog for the plugin itself | "The plugin should have releases and a CHANGELOG" | These are internal bash scripts for a 3-person team, not a published library. Versioning overhead (tags, changelogs, release notes) costs more than it benefits | Git history is the changelog; keep scripts in the same repo under a `hooks/` or `plugins/` directory |

## Feature Dependencies

```
[Gist config file (gist_id)]
    └──required by──> [Milestone number allocation]
    └──required by──> [Phase number allocation]
    └──required by──> [Registry status command]
    └──required by──> [Collision warning with rollback]
    └──required by──> [Automatic stale claim cleanup]

[Milestone number allocation]
    └──required by──> [CC hook for /gsd-new-milestone]

[Phase number allocation]
    └──required by──> [CC hook for /gsd-new-phase]

[Git pre-merge-commit hook]
    └──enables──> [Duplicate REQ-ID detection]
    └──enables──> [Phase numbering gap detection]
    └──enables──> [STATE.md drift detection]
    └──enables──> [Stale cross-reference detection]

[Duplicate REQ-ID detection]
    └──independent of──> [Phase numbering gap detection]

[STATE.md drift detection]
    └──requires──> [Phase numbering gap detection] (shares the phase-number extraction logic)

[Stale cross-reference detection]
    └──requires──> [Duplicate REQ-ID detection] (shares the ID extraction logic)

[--verbose flag]
    └──enhances──> [Milestone number allocation]
    └──enhances──> [Phase number allocation]
    └──enhances──> [All git hook checks]

[--dry-run mode]
    └──enhances──> [Milestone number allocation]
    └──enhances──> [Phase number allocation]
    └──conflicts with──> [CC hook auto-interception] (hooks must auto-run; dry-run is opt-in via env var)
```

### Dependency Notes

- **Gist config file is the foundation:** Every registry operation requires knowing the gist ID. This must be implemented first and validated before any registry reads/writes are attempted. No gist ID = immediate fail with onboarding instructions.
- **CC hooks require the allocation functions:** The hook scripts are thin wrappers that call the core allocation bash functions. The allocation logic must exist before the hooks can be wired up.
- **Git merge hook is independent of CC hooks:** The two hook types (CC hooks at creation time, git hooks at merge time) solve different problems and can be developed independently.
- **STATE.md drift shares phase extraction logic with gap detection:** Implement gap detection first; drift detection reuses the same phase-number extraction function.
- **Stale cross-reference shares ID extraction with duplicate detection:** Implement duplicate REQ-ID detection first; stale cross-reference reuses the ID catalog it builds.
- **--dry-run conflicts with auto-interception:** CC hooks run automatically and cannot prompt the user. Dry-run should be an env var (`GSD_DRY_RUN=1`) that the hook checks, not a CLI flag requiring interactive input.

## MVP Definition

### Launch With (v1)

Minimum viable product — validates that the tooling eliminates Slack coordination for number claiming.

- [ ] Gist config file + installer — establishes the shared registry and onboards all 3 devs
- [ ] Milestone number allocation (core bash function) — the primary number-claiming primitive
- [ ] Phase number allocation (core bash function) — the secondary number-claiming primitive
- [ ] CC hook for `/gsd-new-milestone` — automates milestone claim without manual invocation
- [ ] CC hook for `/gsd-new-phase` — automates phase claim without manual invocation
- [ ] Clear error output with actionable remediation — without this, hook failures block devs without explanation (broken user experience)
- [ ] Duplicate REQ-ID detection at merge time — highest-value integrity check; cheap to implement
- [ ] Phase numbering gap detection at merge time — second-highest value; directly detects the collision the tool is designed to prevent

### Add After Validation (v1.x)

Add once core number-claiming workflow is proven stable.

- [ ] STATE.md drift detection — add when team reports planning corruption that gap+duplicate checks didn't catch
- [ ] Stale cross-reference detection — add when zombie references become a recurring complaint
- [ ] Registry status command (`gsd-status`) — add when "what numbers are taken?" still gets asked on Slack despite the automation
- [ ] Collision warning with rollback instructions — add when first real race condition is encountered
- [ ] `--dry-run` mode and `--verbose` flag — add when debugging hooks becomes painful

### Future Consideration (v2+)

Defer until the team has used v1 for at least one full milestone cycle.

- [ ] Automatic stale claim cleanup — requires confidence in branch-detection logic; premature cleanup could release a number that's still in use on a rebased branch
- [ ] Configurable branch naming patterns — defer until the team hits a workflow that doesn't fit gitflow assumptions

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Gist config file | HIGH | LOW | P1 |
| Milestone number allocation | HIGH | LOW | P1 |
| Phase number allocation | HIGH | LOW | P1 |
| CC hook for `/gsd-new-milestone` | HIGH | MEDIUM | P1 |
| CC hook for `/gsd-new-phase` | HIGH | MEDIUM | P1 |
| Clear error output | HIGH | LOW | P1 |
| Duplicate REQ-ID detection | HIGH | LOW | P1 |
| Phase gap detection | HIGH | LOW | P1 |
| STATE.md drift detection | MEDIUM | HIGH | P2 |
| Stale cross-reference detection | MEDIUM | HIGH | P2 |
| Registry status command | MEDIUM | LOW | P2 |
| Collision warning + rollback | MEDIUM | MEDIUM | P2 |
| `--dry-run` / `--verbose` | LOW | LOW | P2 |
| Automatic stale claim cleanup | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for v1 launch
- P2: Should have, add when possible (v1.x)
- P3: Nice to have, future consideration (v2+)

## Competitor Feature Analysis

No direct competitors exist for this exact niche (bash + gh CLI + GSD planning format). The closest analogues are:

| Feature | Jira / Linear (project tools) | pre-commit framework | Our Approach |
|---------|-------------------------------|----------------------|--------------|
| Sequential ID allocation | Server-side; no client race risk | N/A | Client-side with Gist as shared registry; best-effort concurrency |
| Merge-time integrity checks | Server-side branch protection rules | Pre-commit hooks (pre-push) | Git `pre-merge-commit` hook; client-side, no server access needed |
| Cross-reference validation | Deep graph traversal via APIs | Markdownlint rules | Grep-based text scan; good enough for the team's markdown format |
| Team visibility of claims | Real-time dashboard | N/A | `gsd-status` command; pull-on-demand from gist |
| Onboarding | Account creation, org setup | `pip install pre-commit` | Installer script; one-time per dev |

The key architectural difference: all competitors either require a server (Jira, Linear) or a separate language runtime (pre-commit needs Python). This project's constraint of bash + `gh` CLI only is a genuine differentiator for a team that wants zero infrastructure overhead.

## Sources

- Claude Code hooks documentation: https://code.claude.com/docs/en/hooks-guide (HIGH confidence — official Anthropic docs)
- Git hooks reference: https://git-scm.com/docs/githooks (HIGH confidence — official git docs)
- GitHub Gist REST API: https://docs.github.com/en/rest/gists/gists (HIGH confidence — official GitHub docs; `updated_at` field confirmed, no native ETag/OCC)
- CLI UX guidelines (clig.dev): https://clig.dev/ (MEDIUM confidence — community standard, widely cited)
- Bitbucket merge checks guide: https://developer.atlassian.com/server/bitbucket/how-tos/hooks-merge-checks-guide/ (MEDIUM confidence — pattern reference, not implementation target)

---
*Feature research for: GSD Team Coordination Plugins (number registry + integrity checks)*
*Researched: 2026-05-19*
