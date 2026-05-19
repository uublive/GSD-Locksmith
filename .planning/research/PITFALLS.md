# Pitfalls Research

**Domain:** Shell-based CLI plugins — shared Gist registry, Claude Code hooks, git merge validation
**Researched:** 2026-05-19
**Confidence:** HIGH (Claude Code hooks, git hooks behavior verified against official docs; Gist/concurrency patterns from multiple corroborating sources)

---

## Critical Pitfalls

### Pitfall 1: Exit Code 1 Does Not Block in Claude Code Hooks

**What goes wrong:**
A PreToolUse hook script exits with code 1 when a GSD command should be intercepted (e.g., duplicate milestone number detected). Claude Code treats exit 1 as a non-blocking warning — the tool call proceeds anyway. Developers believe the guard is active but the safety net has zero teeth.

**Why it happens:**
Unix convention: exit 1 = failure. Every shell author's instinct is to `exit 1` on error. Claude Code inverts this: only exit code 2 is blocking. Exit 1 surfaces in verbose mode stderr but does not stop execution. This is documented but counter-intuitive enough that experienced developers discover it in production after a false sense of security.

**How to avoid:**
- Use `exit 2` exclusively for any hook that must block a command.
- Use `exit 1` only for diagnostic hooks that should log but not block.
- Add a comment in every hook script next to the exit code: `exit 2  # blocks the command — NOT exit 1`.
- Test each blocking hook immediately after writing it by triggering the hook and confirming the command did not run.

**Warning signs:**
- Duplicate milestone/phase numbers appear in planning files despite hooks being "active."
- Hook script stderr appears in the terminal but the GSD command completes anyway.
- CI or post-merge checks catch collisions that the CC hook should have prevented.

**Phase to address:**
Phase implementing Claude Code hooks (hook authoring phase). Every hook that is intended to block must be tested with an explicit collision scenario before the phase is considered done.

---

### Pitfall 2: Shell Profile Output Corrupts Hook JSON Parsing

**What goes wrong:**
A developer's `.zshrc` or `.bashrc` prints text on startup (welcome messages, `echo $PATH`, `nvm` init banner, `brew` warnings, etc.). Claude Code hooks receive JSON on stdin and are expected to emit JSON on stdout. Any text from shell profile init ends up prepended to the JSON output, breaking parsing silently or causing the hook to be ignored.

**Why it happens:**
Claude Code invokes hook scripts through a shell, which sources the profile. Most developers never notice because their daily shell use is interactive — the profile output is visually natural. It only breaks in non-interactive programmatic invocations, which hooks are.

**How to avoid:**
- Wrap all interactive-only output in `.zshrc`/`.bashrc` behind an interactive check: `[[ $- == *i* ]] && echo "welcome"`.
- Hook scripts themselves: never `echo` diagnostic text to stdout; use `>&2` for all human-readable output.
- When a hook produces JSON, that must be the only thing on stdout.

**Warning signs:**
- Hooks that work on one developer's machine fail on another's.
- Hook registration appears correct in `/hooks` browser but the hook "does nothing."
- Debugging with `echo` inside a hook script causes it to break further.

**Phase to address:**
Phase implementing Claude Code hooks. Include a "smoke test your shell profile" step in the developer setup instructions.

---

### Pitfall 3: Read-Then-Write on GitHub Gist Has No Atomicity

**What goes wrong:**
Two developers run a GSD command within seconds of each other. Both scripts read the Gist registry, both see milestone 5 unclaimed, both claim it and write back. One write overwrites the other. Both developers end up with milestone 5. The collision the tooling was designed to prevent still happens — silently, with no error.

**Why it happens:**
GitHub Gist's API has no compare-and-swap or conditional update (no ETag-based conditional PUT in the Gist API). The `gh gist edit` command performs a full file replace with no conflict detection. The only way to guarantee atomicity is a true lock service, which the project has explicitly ruled out.

**How to avoid:**
- Accept this as a known limitation (it's in scope as "best-effort") — do not try to engineer around it with flawed workarounds like sleep-and-retry without a real lock.
- Make collision recovery explicit and documented: the recovery path (read the Gist, manually re-claim the correct number, re-run) must be written into the tooling's `--help` output and error messages.
- Include a timestamp and developer identity in every registry write so the "who won" question is answerable post-collision.
- Consider a short random jitter (100–500ms) before the write step to reduce the collision window for near-simultaneous runs without hiding the race.

**Warning signs:**
- Two feature branches with the same milestone or phase number.
- Gist registry shows a claim but the claimant doesn't recognize it as theirs.
- `--status` command shows stale ownership from a branch that was already merged.

**Phase to address:**
Phase implementing the Gist registry read/write. Design the JSON structure to include `claimed_by`, `claimed_at`, `branch` from day one — retrofitting identity into the registry after collisions occur is painful.

---

### Pitfall 4: Git Hooks Are Not Automatically Shared or Installed

**What goes wrong:**
The merge-validation git hooks are committed to the repo under `.githooks/` or similar. A developer clones the repo or another developer joins the team. The hooks are never active on their machine because git does not install `.git/hooks/` from version-controlled directories on clone. The first merge from that developer bypasses all integrity checks.

**Why it happens:**
Git intentionally does not auto-install hooks from the working tree — it is a security boundary. This is correct behavior, but it creates a reliable onboarding gap in any project that relies on git hooks for enforcement.

**How to avoid:**
- Provide a single-command setup script (`./scripts/install-hooks.sh`) that runs `git config core.hooksPath .githooks`.
- Make the setup script idempotent and include it in the project README and onboarding docs.
- Add a CI check that verifies the hooks directory is present (can't verify local installation, but can verify the hook scripts exist and are correct).
- Consider a `PostToolUse` CC hook on `SessionStart` that checks whether `core.hooksPath` is configured and warns the developer if not.

**Warning signs:**
- A developer reports that merge produced no validation output.
- New team member's first merge to `development` introduces planning file integrity errors.
- `git config --get core.hooksPath` returns empty on a developer's machine.

**Phase to address:**
Phase implementing git hooks. The install script must ship in the same phase as the hooks themselves — never as a follow-up.

---

### Pitfall 5: Git Merge Hooks Can Be Bypassed With --no-verify (But Not on git merge)

**What goes wrong:**
Developers who know about `--no-verify` may try to bypass pre-commit hooks to speed up their workflow. However, `git merge` does not support `--no-verify`, which means the pre-merge-commit hook cannot be skipped this way. The actual bypass risk is different: developers may use `git merge --strategy` options, reset the hook path, or set `core.hooksPath=/dev/null`. The risk is inadvertent bypass through IDE tooling that runs merge operations in ways that skip hooks entirely.

**Why it happens:**
IDEs (VS Code Source Control, IntelliJ Git integration) run git operations through their own subprocess pipelines. Some do not preserve `core.hooksPath` overrides or run with a different environment. Developers who merge via IDE may never see the validation output.

**How to avoid:**
- Make the hook output visible (non-silent) so developers notice when it did not run.
- Add a post-merge hook that writes a timestamped entry to a local log file. If the log entry is missing after a merge, hooks were bypassed.
- Document that merges to `development` should be done via CLI, not IDE tooling.

**Warning signs:**
- Planning integrity errors discovered after merge that the hook should have caught.
- No hook output in terminal despite a merge having just completed.
- Developer reports "the merge just worked instantly" without any validation pause.

**Phase to address:**
Phase implementing git hooks. Test the hooks explicitly through both CLI (`git merge`) and at least one common IDE integration.

---

### Pitfall 6: Stale Registry Entries Accumulate and Corrupt Allocation Logic

**What goes wrong:**
A developer claims milestone 6 on branch `feature/foo`. That branch is abandoned and deleted. The Gist registry still shows milestone 6 as claimed by that branch. Future developers cannot tell if the number is truly in use or stale. Allocation scripts that check "is this number unclaimed?" return false positives indefinitely.

**Why it happens:**
There is no cleanup lifecycle tied to branch deletion. The registry only gets updated when someone actively claims or releases a number. Abandoned branches never trigger a release.

**How to avoid:**
- Include branch existence check as part of the registry read: when a claim is read, verify that the claiming branch still exists with `git ls-remote --heads origin <branch>`. If the branch is gone, treat the claim as stale.
- Add a `--gc` subcommand to the registry tool that prunes claims for branches that no longer exist on the remote.
- Store a `claimed_at` timestamp so entries older than a configurable threshold (e.g., 30 days) are flagged for review.

**Warning signs:**
- Registry shows claimed numbers that no active developer recognizes.
- Available number sequence has gaps that correspond to no merged or active branches.
- Team starts manually editing the Gist to clean it up.

**Phase to address:**
Phase implementing the Gist registry. Design the stale-claim detection into the read path from the start; it is much harder to retrofit.

---

### Pitfall 7: jq Is Assumed Installed but May Not Be

**What goes wrong:**
Hook scripts and registry tools parse JSON using `jq`. On a fresh developer machine, `jq` is not installed. The script fails with `jq: command not found`, but depending on how the error is handled, the failure may look like a hook that "did nothing" rather than a missing dependency.

**Why it happens:**
`jq` is ubiquitous among CLI developers and comes pre-installed on many systems, so it feels like a safe assumption. But it is not part of macOS base, and a new team member or a CI environment may lack it.

**How to avoid:**
- Add a dependency check at the top of every script that requires `jq`: `command -v jq >/dev/null 2>&1 || { echo "jq is required. Install with: brew install jq" >&2; exit 1; }`.
- Include `jq` in the project's setup checklist alongside `gh auth login`.
- Consider whether any JSON parsing can be done with `python3 -c` or `grep`/`awk` as a fallback, though `jq` is the cleaner path.

**Warning signs:**
- A hook appears to do nothing on a developer's machine but works on another's.
- Script errors containing "command not found" that only appear in non-verbose mode.

**Phase to address:**
Initial tooling setup / first phase. Dependency checks should be the first code written in every script.

---

### Pitfall 8: gh Auth State Differs Between Shell and CC Hook Environment

**What goes wrong:**
A developer has `gh auth login` configured but only in their user shell. Claude Code hooks run in a subprocess that may not inherit the full shell environment, especially when CC was launched from an IDE or a non-login shell. The `gh` CLI fails with an authentication error. The hook exits non-zero (or silently) and the registry operation is skipped.

**Why it happens:**
`gh` stores auth tokens in the system keychain or a config file at `~/.config/gh/`. It reads them correctly in interactive shells. In subprocess environments launched by Claude Code, the `GH_TOKEN` environment variable may be absent if the developer relies on keychain-based auth that requires an interactive session.

**How to avoid:**
- Test hooks explicitly from within a CC session, not just from the terminal.
- Add an explicit auth check at the top of any script that calls `gh`: `gh auth status >/dev/null 2>&1 || { echo "gh auth not configured" >&2; exit 1; }`.
- Document that `GH_TOKEN` can be set as a persistent environment variable for non-interactive contexts.

**Warning signs:**
- Registry operations work in terminal but fail when triggered by a CC hook.
- `gh gist view` works in terminal but the hook reports a network or auth error.

**Phase to address:**
Phase implementing Claude Code hooks + Gist integration. Auth testing must be done from within a CC session, not the surrounding shell.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip collision detection on registry read | Simpler code, fewer API calls | Silent number duplication accumulates; team loses trust in tooling | Never — detection is the core value proposition |
| Hardcode gist ID in scripts instead of config file | Saves one config read | Gist ID leaks into version history; rotating the gist requires code changes | Never — always read from config |
| Use `exit 1` for "soft" blocking in CC hooks | Feels semantically natural | Hook appears to work but does not block; silent security theater | Never for any blocking intent |
| Skip stale-claim GC until it becomes a problem | Faster initial build | Registry corruption grows quietly; team manually edits the Gist | Only acceptable if team commits to running `--gc` on a regular cadence |
| Assume `jq` and `gh` are installed without checking | Fewer lines of code | Cryptic failures on developer onboarding | Never — fail-fast dependency checks are 3 lines |
| Rely on git hook stderr output as the only user signal | Simple implementation | Developers miss errors buried in git output; IDE integrations swallow stderr | Acceptable for MVP; add explicit exit-code-based blocking in a follow-up |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| GitHub Gist API via `gh gist edit` | Assuming the edit is atomic and reflects the latest state | Always re-read the Gist immediately before writing; treat the window between read and write as a known race |
| `gh gist view --raw` | Assuming the response body is always valid JSON | Validate with `jq empty` before parsing; Gist content can be truncated or malformed if the file is too large |
| Claude Code PreToolUse hooks | Using `exit 1` to block commands | Only `exit 2` blocks; `exit 1` is a non-blocking warning |
| Claude Code hooks + shell profile | Printing text in `.zshrc` unconditionally | Guard all interactive output with `[[ $- == *i* ]]` |
| git `pre-merge-commit` hook | Expecting it to catch all merge scenarios | The hook only fires on `git merge`; direct cherry-pick, rebase, and IDE merges may bypass it |
| git `core.hooksPath` | Committing hooks and assuming they are installed | Requires per-developer `git config core.hooksPath <dir>` after clone; never auto-installs |
| `gh` auth in CC hook subprocess | Assuming keychain auth works non-interactively | Test inside a CC session; fall back to `GH_TOKEN` env var for non-interactive contexts |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Network call on every CC hook invocation | Every GSD command adds 1-2s latency for Gist read | Cache registry locally with a TTL (e.g., 30s file-based cache); only write to Gist when claiming | Immediately noticeable with any hook that fires frequently |
| Gist read in a synchronous PreToolUse hook | CC session stalls until network responds | Set hook `timeout` explicitly; consider async hooks with `asyncRewake: true` for non-blocking paths | GitHub API latency spikes (rare but real) |
| GitHub API rate limit | Registry operations start failing with 403 | 5,000 requests/hour per PAT; at 3 developers with frequent GSD usage, this is unlikely but possible if hooks fire on every tool use | Unlikely at team of 3, but will surface if hooks are attached to high-frequency events like every `Edit` |
| Slow regex/grep over large planning files | Git hook validation takes 10+ seconds on large repos | Scope validation to changed files only (`git diff --name-only HEAD`) rather than scanning all files | Planning files growing to hundreds of entries |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing gist ID in a `.env` file that is committed | Gist is publicly findable; if public, exposes team's planning state | Store gist ID in a gitignored config file or in a project-level CC settings entry; document this in setup |
| Printing full JSON registry to stdout during debug | Registry data (branch names, developer identities) leaks into CC session transcript | Always redirect debug output to stderr; never print registry contents to stdout in a hook |
| Running hook scripts with world-writable permissions | Any process on the developer's machine can modify hook behavior | Hook scripts should be `chmod 750` at most; owned by the developer's user |
| Trusting stdin JSON without validation in hook scripts | Malformed input causes `jq` to fail mid-script, potentially leaving partial state | Always check `jq` exit code after parsing; use `jq -e` to fail explicitly on null |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Hook errors appear only in CC verbose mode | Developer doesn't know the registry claim failed; proceeds with a potentially colliding number | Write all user-facing errors to stderr unconditionally, not only in verbose mode; output a clear one-line summary even on success |
| "Number claimed" message with no confirmation of what was claimed | Developer has to re-read planning files to verify | Output the full claim summary: number, branch, timestamp, and how to release |
| Validation errors reported as a wall of text at merge time | Developer doesn't know which file or line to fix | Report one error per line with file path and line number; sort by severity |
| Silent success when Gist write fails | Developer thinks claim succeeded; collision follows | Distinguish between "claimed in local session" and "claim persisted to registry"; treat write failure as a warning that requires manual follow-up |
| No way to see current registry state without reading raw Gist | Debugging collisions is slow | Provide a `--status` subcommand that pretty-prints all active claims with branch existence indicators |

---

## "Looks Done But Isn't" Checklist

- [ ] **CC Hook blocking:** The hook exits with code 2 (not 1) for every blocking case — verify by triggering a collision and confirming the GSD command does not complete.
- [ ] **Hook JSON output:** No text other than JSON reaches stdout when the hook is invoked non-interactively — verify with `echo '{}' | bash hook.sh | jq .`.
- [ ] **Gist write confirmed:** The registry write returns successfully and the updated content is re-read to confirm — do not assume `gh gist edit` succeeded silently.
- [ ] **Git hooks installed on all machines:** Run `git config --get core.hooksPath` on each developer's machine before shipping — not just on the author's machine.
- [ ] **Stale claim detection active:** A claim for a deleted branch is treated as stale, not blocking — verify by manually adding a stale entry to the registry and running the allocator.
- [ ] **Dependency checks present:** Every script checks for `jq`, `gh`, and any other deps before using them — verify on a machine where `jq` is uninstalled.
- [ ] **Auth works from CC context:** Registry operations succeed when triggered from within a CC session, not just from the terminal — test this explicitly.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Two developers claimed same number | LOW | One developer re-runs allocation with `--force-renumber`; update their branch's planning files; re-push |
| Stale registry entries blocking allocation | LOW | Run `registry --gc` to prune dead-branch claims; or manually edit the Gist |
| Hook script broken by profile output corruption | LOW | Fix `.zshrc` to guard interactive output; re-test hook |
| Git hooks not installed after clone | LOW | Run `./scripts/install-hooks.sh`; merge was already completed — run validation manually with `./scripts/validate-planning.sh` |
| Gist write failed silently (auth/network) | MEDIUM | Check `gh auth status`; re-run the claim command; if Gist is out of sync, manually edit to reflect current state |
| Registry JSON corrupted by concurrent writes | MEDIUM | Fetch raw Gist content; manually merge the two conflicting JSON states; re-publish; communicate to team |
| Registry entirely missing (Gist deleted) | HIGH | Re-create Gist; reconstruct state from all active branches' planning files; update config with new Gist ID |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Exit code 1 non-blocking | CC hooks implementation phase | Trigger a collision; confirm command does not run |
| Shell profile JSON corruption | CC hooks implementation phase | Test hooks non-interactively with clean env |
| Gist read-write race condition | Gist registry implementation phase | Acceptance criteria: race is documented, collision message is clear |
| Git hooks not auto-installed | Git hooks implementation phase | Verify `core.hooksPath` setup script ships with hooks |
| IDE bypasses git hooks | Git hooks implementation phase | Test with VS Code Source Control panel and confirm hook fires |
| Stale registry entries | Gist registry implementation phase | GC subcommand exists and removes dead-branch entries |
| Missing jq/gh dependencies | First phase (any script) | Dependency check is first thing each script does |
| gh auth in CC subprocess | CC hooks + Gist integration phase | Registry op succeeds from within a CC session, not just terminal |

---

## Sources

- [Automate workflows with hooks — Claude Code Docs](https://code.claude.com/docs/en/hooks-guide) — official hooks documentation, exit code semantics
- [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks) — exit code behavior, JSON output format, timeout settings
- [The Silent Failure Mode in Claude Code Hooks — Medium](https://thinkingthroughcode.medium.com/the-silent-failure-mode-in-claude-code-hook-every-dev-should-know-about-0466f139c19f) — exit code 1 vs 2 trap, real-world failure case
- [Git Hooks Documentation — git-scm.com](https://git-scm.com/docs/githooks) — pre-merge-commit, --no-verify behavior
- [How to Include Githooks in a Repository to Share With Your Team](https://justinjbird.com/blog/2026/how-to-include-githooks-in-a-repository-to-share-with-your-team/) — core.hooksPath distribution pattern
- [Rate limits for the REST API — GitHub Docs](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — API rate limit context
- [gh gist edit — CLI manual](https://cli.github.com/manual/gh_gist_edit) — gist update behavior
- [Bash: Fail Fast on Missing Dependencies — Medium](https://samanpavel.medium.com/bash-fail-fast-on-missing-dependencies-b7560bf143e8) — dependency check patterns
- [Avoid Race Conditions — TLDP Secure Programs HOWTO](https://tldp.org/HOWTO/Secure-Programs-HOWTO/avoid-race.html) — read-modify-write race conditions in shell scripts
- [Mastering Git Hooks — Kinsta](https://kinsta.com/blog/git-hooks/) — performance, bypass, and distribution patterns

---
*Pitfalls research for: Shell-based CLI plugins — GSD team coordination (Gist registry, CC hooks, git merge validation)*
*Researched: 2026-05-19*
